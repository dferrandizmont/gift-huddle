import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { V2_GLOBAL_STORAGE_CEILING_BYTES, V2_STORAGE_BLOCK_BYTES, V2_GLOBAL_LIST_ROWS_PER_DAY } from "./limits";
import { dailyRows } from "./daily-row-budget";

/** Absolute per-list balances make retries and lost responses idempotent. */
export class StorageLedgerObject extends DurableObject<Env> {
  rows(amount = 0) { return dailyRows(this.ctx.storage, V2_GLOBAL_LIST_ROWS_PER_DAY, amount); }
  private total?: number;
  private sumBlocks(): number {
    return this.ctx.storage.sql.exec<{ total: number }>("SELECT COALESCE(SUM(blocks), 0) AS total FROM balances").one().total;
  }
  occupancy(): { reservedBytes: number; ceilingBytes: number; percent: number } {
    const sql = this.ctx.storage.sql;
    const blocks = this.total ?? (sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'balances' AND type = 'table'").toArray().length
      ? this.sumBlocks() : 0);
    const reservedBytes = blocks * V2_STORAGE_BLOCK_BYTES;
    const ceilingBytes = V2_GLOBAL_STORAGE_CEILING_BYTES;
    return { reservedBytes, ceilingBytes, percent: reservedBytes * 100 / ceilingBytes };
  }
  set(list: string, blocks: number, existing = false): boolean {
    if (!Number.isSafeInteger(blocks) || blocks < 0) throw new Error("Invalid balance");
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS balances (list TEXT PRIMARY KEY, blocks INTEGER NOT NULL)");
    // The cached sum is rebuilt on wake; only one balance row changes per block
    // transition. No account-wide total row is rewritten on every reservation.
    this.total ??= this.sumBlocks();
    const change = this.ctx.storage.transactionSync(() => {
      const before = sql.exec<{ blocks: number }>("SELECT blocks FROM balances WHERE list = ?", list).toArray()[0]?.blocks ?? 0;
      if (blocks > before && !existing && (this.total! + blocks - before) * V2_STORAGE_BLOCK_BYTES > V2_GLOBAL_STORAGE_CEILING_BYTES) return null;
      if (blocks === before) return 0;
      if (blocks) sql.exec("INSERT INTO balances VALUES (?, ?) ON CONFLICT(list) DO UPDATE SET blocks = excluded.blocks", list, blocks);
      else sql.exec("DELETE FROM balances WHERE list = ?", list);
      return blocks - before;
    });
    if (change === null) return false;
    this.total += change;
    return true;
  }
}
