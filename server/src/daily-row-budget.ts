export const rowRetryAfter = () => Math.min(3600, Math.max(1, Math.ceil(((Math.floor(Date.now() / 86400000) + 1) * 86400000 - Date.now()) / 1000)));

export type RowStatus = { day: number; remaining: number; exhausted: boolean };
export type RowReport = RowStatus & { pending: number; checkedAt: number; reportedAt: number; usedAt: number };
export type RowReports = { day: number; keys: Record<string, RowReport> };

/** Queries never create a schema or write a row. Reports charge actual rows,
 * including an admitted mutation that crosses the daily limit. */
export function dailyRows(storage: DurableObjectStorage, limit: number, amount = 0): RowStatus {
  if (!Number.isSafeInteger(amount) || amount < 0) throw new Error("Invalid row report");
  const sql = storage.sql, day = Math.floor(Date.now() / 86400000);
  const exists = sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'row_quota'").toArray().length > 0;
  if (!exists && !amount) return { day, remaining: limit, exhausted: false };
  if (!exists) sql.exec("CREATE TABLE row_quota (id INTEGER PRIMARY KEY, day INTEGER NOT NULL, written INTEGER NOT NULL)");
  return storage.transactionSync(() => {
    const row = sql.exec<{ day: number; written: number }>("SELECT day, written FROM row_quota WHERE id = 1").toArray()[0];
    const written = (row?.day === day ? row.written : 0) + amount;
    if (amount) sql.exec("INSERT INTO row_quota VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET day = excluded.day, written = excluded.written", day, written);
    return { day, remaining: Math.max(0, limit - written), exhausted: written >= limit };
  });
}
