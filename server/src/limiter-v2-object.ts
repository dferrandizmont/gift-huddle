import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";

/** Synchronous SQLite decision: concurrent calls cannot spend the same token. */
export class LimiterV2Object extends DurableObject<Env> {
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
  override async alarm(): Promise<void> { await this.ctx.storage.deleteAll(); }
}
