import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { V2_GLOBAL_NEW_LISTS_PER_DAY, V2_GLOBAL_NEW_LISTS_PER_HOUR } from "./limits";

/** One bounded ring: a successful reservation overwrites only an expired row. */
export class CreationBudgetObject extends DurableObject<Env> {
  reserve(): { ok: boolean; retryAfter: number } {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS creation (id INTEGER PRIMARY KEY, time INTEGER NOT NULL)");
    return this.ctx.storage.transactionSync(() => {
      const now = Date.now(), hour = 3600000, day = 24 * hour;
      const rows = sql.exec<{ id: number; time: number }>("SELECT id, time FROM creation ORDER BY time, id").toArray();
      const daily = rows.filter((r) => r.time > now - day);
      const hourly = daily.filter((r) => r.time > now - hour);
      const until = Math.max(daily.length >= V2_GLOBAL_NEW_LISTS_PER_DAY ? daily[0]!.time + day : 0, hourly.length >= V2_GLOBAL_NEW_LISTS_PER_HOUR ? hourly[0]!.time + hour : 0);
      if (until > now) return { ok: false, retryAfter: Math.min(3600, Math.max(1, Math.ceil((until - now) / 1000))) };
      const expired = rows.find((r) => r.time <= now - day);
      sql.exec("INSERT INTO creation (id, time) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET time = excluded.time", expired?.id ?? rows.length + 1, now);
      return { ok: true, retryAfter: 0 };
    });
  }
}
