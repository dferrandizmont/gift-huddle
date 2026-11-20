import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { dailyRows } from "./daily-row-budget";

/** Synchronous SQLite decision: concurrent calls cannot spend the same token. */
export class LimiterV2Object extends DurableObject<Env> {
  rows(limit: number, amount = 0) { return dailyRows(this.ctx.storage, limit, amount); }
  async hit(limit: number, windowMs: number): Promise<{ ok: boolean; retryAfter: number }> {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS quota (id INTEGER PRIMARY KEY, start INTEGER, count INTEGER)");
    const now = Date.now();
    let w = sql.exec<{ start: number; count: number }>("SELECT start, count FROM quota WHERE id = 1").toArray()[0];
    const fresh = !w || now - w.start >= windowMs;
    if (fresh) w = { start: now, count: 0 };
    if (w!.count >= limit) return { ok: false, retryAfter: Math.max(1, Math.ceil((w!.start + windowMs - now) / 1000)) };
    sql.exec("INSERT OR REPLACE INTO quota VALUES (1, ?, ?)", w!.start, w!.count + 1);
    if (fresh) await this.ctx.storage.setAlarm(now + windowMs);
    return { ok: true, retryAfter: 0 };
  }
  async creation(hourly: number, daily: number): Promise<{ ok: boolean; retryAfter: number }> {
    const sql = this.ctx.storage.sql, now = Date.now(), day = 86400000;
    sql.exec("CREATE TABLE IF NOT EXISTS creation (id INTEGER PRIMARY KEY, time INTEGER NOT NULL)");
    const result = this.ctx.storage.transactionSync(() => {
      const rows = sql.exec<{ id: number; time: number }>("SELECT id, time FROM creation ORDER BY time, id").toArray();
      const recent = rows.filter((r) => r.time > now - day), hour = recent.filter((r) => r.time > now - 3600000);
      const until = Math.max(recent.length >= daily ? recent[0]!.time + day : 0, hour.length >= hourly ? hour[0]!.time + 3600000 : 0);
      if (until > now) return { ok: false, retryAfter: Math.min(3600, Math.max(1, Math.ceil((until - now) / 1000))) };
      const expired = rows.find((r) => r.time <= now - day);
      sql.exec("INSERT INTO creation VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET time = excluded.time", expired?.id ?? rows.length + 1, now);
      return { ok: true, retryAfter: 0 };
    });
    if (result.ok) await this.ctx.storage.setAlarm(now + day);
    return result;
  }
  override async alarm(): Promise<void> { await this.ctx.storage.deleteAll(); }
}
