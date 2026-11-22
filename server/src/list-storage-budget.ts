import { LIST_TTL_MS, V2_STORAGE_BLOCK_BYTES, v2ListByteLimit } from "./limits";
import type { RowReports } from "./daily-row-budget";

export class ListTooLarge extends Error {}
export class StorageBlocksNeeded extends Error {
  constructor(readonly blocks: number, readonly statements: [string, SqlStorageValue[]][]) { super("Storage blocks required"); }
}
type Row = Record<string, SqlStorageValue>;
type Table = { keys: string[]; sizes: Map<string, number> };
const size = (row: Row) => Object.values(row).reduce<number>((n, v) => n + (typeof v === "string" ? new TextEncoder().encode(v).length : v instanceof ArrayBuffer ? v.byteLength : v === null ? 0 : 8), 0);
const applicationContent = (value: object) => {
  const { storedBytes: _bytes, rowBudget: _budget, rowReports: _reports, ...rest } = value as Record<string, unknown>;
  return JSON.stringify(rest);
};
const ignored = new Set(["state", "rate", "recovery_quota", "renewal_usage", "row_attempts"]);

/** Tracks changed rows, including keys and UTF-8 bytes, without rescanning payloads.
 * The one cold scan also migrates old lists. Only bounded counters are excluded.
 * Every SQL mutation and the total in state commit in the same transaction. */
export class ListStorageBudget {
  /** Validated first snapshots can be sized without writing and rolling back SQL. */
  initialBlocks(meta: object, rows: Row[], written: number): number {
    const day = Math.floor(Date.now() / 86400000), attempts = this.attempts();
    const prior = attempts?.rowBudget as { day: number; written: number } | undefined;
    const rowBudget = { day, written: written + (prior?.day === day ? prior.written : 0) };
    const rowReports = this.rowContext && structuredClone(this.rowContext.reports);
    if (rowReports) for (const key of this.rowContext!.keys) {
      const entry = rowReports.keys[key];
      if (entry) { entry.pending += written; entry.usedAt = Date.now(); }
    }
    return Math.ceil((rows.reduce((n, row) => n + size(row), 0) + size({ id: 1, data: JSON.stringify({ ...meta, rowBudget, ...(rowReports ? { rowReports } : {}), storedBytes: 0 }) })) / V2_STORAGE_BLOCK_BYTES);
  }
  private tables?: Map<string, Table>;
  private payload = 0;
  private depth = 0;
  private written = 0;
  private reportWritten = 0;
  private accountingDepth = 0;
  /** Counter persistence is charged only to the list budget. */
  accountingOnly<T>(run: () => T): T {
    this.accountingDepth++;
    try { return run(); } finally { this.accountingDepth--; }
  }
  private rowStart = 0;
  private capacity?: number;
  private statements?: [string, SqlStorageValue[]][];
  private previewing = false;
  /** Scoped to an admitted call. Pending rows themselves always live in state. */
  rowContext?: { keys: string[]; reports: RowReports };
  private reportStart?: RowReports;
  private rowTime = 0;
  /** Includes reverted writes and the durable accounting for those attempts. */
  rowsWritten = 0;
  readonly sql: SqlStorage;
  constructor(private readonly storage: DurableObjectStorage) {
    this.sql = new Proxy(storage.sql, { get: (target, key) => key === "exec" ? this.exec.bind(this) : Reflect.get(target, key, target) });
  }
  private key(table: Table, row: Row): string { return JSON.stringify(table.keys.map((k) => row[k])); }
  private loadTable(name: string): Table {
    const columns = this.storage.sql.exec<{ name: string; pk: number }>(`PRAGMA table_info("${name}")`).toArray();
    const keys = columns.filter((c) => c.pk).sort((a, b) => a.pk - b.pk).map((c) => c.name);
    const table: Table = { keys: keys.length ? keys : columns.map((c) => c.name), sizes: new Map() };
    for (const row of this.storage.sql.exec(`SELECT * FROM "${name}"`)) table.sizes.set(this.key(table, row), size(row));
    return table;
  }
  private initialize(): void {
    if (this.tables) return;
    this.tables = new Map(); this.payload = 0;
    const m = this.meta();
    if (m && Number.isSafeInteger(m.storedBytes)) {
      this.payload = (m.storedBytes as number) - size({ id: 1, data: JSON.stringify({ ...m, storedBytes: 0 }) });
      return;
    }
    for (const { name } of this.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite%' AND name NOT LIKE '_cf%'")) {
      if (ignored.has(name)) continue;
      const table = this.loadTable(name);
      this.tables.set(name, table);
      for (const n of table.sizes.values()) this.payload += n;
    }
  }
  /** The bytes of each stored slot row per writer (as [size] counts them): what the slot supplement of v2ListByteLimit pays for. */
  private slotRows(): Map<string, number[]> {
    const rows = new Map<string, number[]>();
    // Only the list's own slot table (person, device, ver, data) pays.
    const columns = this.storage.sql.exec<{ name: string }>(`PRAGMA table_info("slot")`).toArray().map((c) => c.name);
    if (!["person", "device", "ver", "data"].every((c) => columns.includes(c))) return rows;
    const encoder = new TextEncoder();
    for (const r of this.storage.sql.exec<{ person: string; device: string; data: number }>("SELECT person, device, LENGTH(CAST(data AS BLOB)) AS data FROM slot")) {
      const bytes = encoder.encode(r.person).length + encoder.encode(r.device).length + 8 + r.data;
      const list = rows.get(r.device);
      if (list) list.push(bytes); else rows.set(r.device, [bytes]);
    }
    return rows;
  }
  private meta(): Record<string, unknown> | null {
    if (!this.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'state'").toArray().length) return null;
    const row = this.storage.sql.exec<{ data: string }>("SELECT data FROM state WHERE id = 1").toArray()[0];
    if (!row) return null;
    try {
      const m: unknown = JSON.parse(row.data);
      return typeof m === "object" && m !== null && "credentials" in m && Array.isArray(m.credentials) ? m as Record<string, unknown> : null;
    } catch { return null; }
  }
  /** A failed first transaction has no list state in which to keep its debt. */
  private attempts(): Record<string, unknown> | null {
    if (!this.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'row_attempts'").toArray().length) return null;
    const row = this.storage.sql.exec<{ data: string }>("SELECT data FROM row_attempts WHERE id = 1").toArray()[0];
    return row ? JSON.parse(row.data) as Record<string, unknown> : null;
  }
  private total(m: Record<string, unknown>): number {
    return this.payload + size({ id: 1, data: JSON.stringify({ ...m, storedBytes: 0 }) });
  }
  private accounting(written: number, pending = this.reportWritten): { rowBudget: { day: number; written: number }; rowReports?: RowReports } {
    const day = Math.floor(Date.now() / 86400000);
    const source = this.reportStart;
    const reports = source && structuredClone(source);
    if (reports && this.rowContext) for (const key of this.rowContext.keys) {
      const entry = reports.keys[key];
      if (entry) { entry.pending += pending; if (pending) entry.usedAt = this.rowTime; }
    }
    return { rowBudget: { day, written: this.rowStart + written }, ...(reports ? { rowReports: reports } : {}) };
  }
  decorate<T extends object>(m: T): T {
    this.initialize();
    if (!("credentials" in m)) return m;
    const current = this.meta();
    let updated = { ...m, ...(current?.rowBudget ? { rowBudget: current.rowBudget } : {}), ...(this.rowContext ? { rowReports: this.rowContext.reports } : {}) };
    const content = (value: object) => {
      const { storedBytes: _storedBytes, ...rest } = value as Record<string, unknown>;
      return JSON.stringify(rest);
    };
    // Most transactions save state last. Include accounting in that same write.
    if (this.depth && (this.written || content(updated) !== content(current ?? {}))) {
      updated = { ...updated, ...this.accounting(this.written + 1, this.reportWritten + (this.accountingDepth || applicationContent(updated) === applicationContent(current ?? {}) ? 0 : 1)) };
    }
    return { ...updated, storedBytes: this.total(updated as Record<string, unknown>) };
  }
  transaction<T>(run: () => T, cleanup = false): T {
    if (this.depth) return run();
    this.initialize();
    const prior = this.meta();
    const accountingPrior = prior ?? this.attempts();
    this.rowTime = Date.now();
    this.reportStart = this.rowContext?.reports ?? accountingPrior?.rowReports as RowReports | undefined;
    this.written = 0; this.reportWritten = 0;
    const rowBudget = accountingPrior?.rowBudget as { day: number; written: number } | undefined;
    this.rowStart = rowBudget?.day === Math.floor(Date.now() / 86400000) ? rowBudget.written : 0;
    const before = prior ? this.total(prior) : 0;
    try {
      return this.storage.transactionSync(() => {
        this.depth++;
        try {
          const result = run(), m = this.meta();
          if (m) {
            const total = this.total(m);
            const expected = this.accounting(this.written);
            if (m.storedBytes !== total || (this.written && (JSON.stringify(m.rowBudget) !== JSON.stringify(expected.rowBudget) || JSON.stringify(m.rowReports) !== JSON.stringify(expected.rowReports)))) {
              const updated = { ...m, ...this.accounting(this.written + 1) };
              this.count(this.storage.sql.exec("UPDATE state SET data = ? WHERE id = 1", JSON.stringify({ ...updated, storedBytes: this.total(updated) })), true);
            }
            const final = this.meta()!;
            const finalTotal = this.total(final);
            if (!cleanup && finalTotal > before && finalTotal > v2ListByteLimit(final.credentials as Parameters<typeof v2ListByteLimit>[0], Date.now(), this.slotRows())) throw new ListTooLarge();
            const blocks = Math.ceil((final.storedBytes as number) / V2_STORAGE_BLOCK_BYTES);
            if (this.capacity !== undefined && blocks !== this.capacity && (!cleanup || blocks < this.capacity)) throw new StorageBlocksNeeded(blocks, this.statements!.slice());
            if (!this.previewing && this.rowContext && final.rowReports) this.rowContext.reports = final.rowReports as RowReports;
          } else if (this.capacity !== undefined && this.capacity > 0) {
            throw new StorageBlocksNeeded(0, this.statements!.slice());
          }
          return result;
        } finally { this.depth--; }
      });
    } catch (e) {
      this.tables = undefined;
      if (!this.previewing) this.persistAttempts(this.written, this.reportWritten);
      throw e;
    }
  }
  private count(cursor: SqlStorageCursor<Row>, accounting = false): void {
    if (!accounting && !this.accountingDepth) this.reportWritten += cursor.rowsWritten;
    this.written += cursor.rowsWritten;
    this.rowsWritten += cursor.rowsWritten;
  }
  private persistAttempts(written: number, pending: number, acknowledge = false): void {
    if (!written && !acknowledge) return;
    // Never recreate accounting beside a retirement marker.
    if (this.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'state'").toArray().length && !this.meta() && this.storage.sql.exec("SELECT 1 FROM state").toArray().length) return;
    this.initialize();
    const m = this.meta(), priorAccounting = m ?? this.attempts();
    const day = Math.floor(Date.now() / 86400000);
    this.rowTime = Date.now();
    const prior = priorAccounting?.rowBudget as { day: number; written: number } | undefined;
    this.rowStart = prior?.day === day ? prior.written : 0;
    this.reportStart = this.rowContext?.reports ?? priorAccounting?.rowReports as RowReports | undefined;
    const schemaRows = m ? 0 : this.storage.sql.exec("CREATE TABLE IF NOT EXISTS row_attempts (id INTEGER PRIMARY KEY, data TEXT NOT NULL)").rowsWritten;
    this.rowsWritten += schemaRows;
    const updated = { ...(m ?? { expiresAt: priorAccounting?.expiresAt ?? Date.now() + LIST_TTL_MS }), ...this.accounting(written + schemaRows + 1, pending) };
    if (m) this.rowsWritten += this.storage.sql.exec("UPDATE state SET data = ? WHERE id = 1", JSON.stringify({ ...updated, storedBytes: this.total(updated) })).rowsWritten;
    else {
      this.rowsWritten += this.storage.sql.exec("INSERT INTO row_attempts VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data", JSON.stringify(updated)).rowsWritten;
    }
    if (this.rowContext && updated.rowReports) this.rowContext.reports = updated.rowReports;
  }
  attemptsExpireAt(): number | undefined {
    const attempts = this.attempts();
    if (!attempts) return;
    const day = (attempts.rowBudget as { day: number } | undefined)?.day;
    return typeof attempts.expiresAt === "number" ? attempts.expiresAt : (day ?? Math.floor(Date.now() / 86400000)) * 86400000 + LIST_TTL_MS;
  }
  pendingReports(): RowReports | undefined {
    const prior = this.meta() ?? this.attempts();
    return prior?.rowReports as RowReports | undefined;
  }
  acknowledgeReports(): void { this.persistAttempts(0, 0, true); }
  /** Only a block crossing rolls back. Replay SQL, never application callbacks:
   * callbacks can update JS objects and must run exactly once. */
  stage(run: () => void, capacity: number, cleanup = false): void {
    this.capacity = capacity; this.statements = [];
    try { this.transaction(run, cleanup); }
    finally { this.capacity = undefined; this.statements = undefined; }
  }
  replay(statements: [string, SqlStorageValue[]][]): void {
    this.transaction(() => { for (const [query, args] of statements) this.sql.exec(query, ...args); });
  }
  /** Validate the complete local commit before an external effect. The list
   * lock must remain held until commit; only the billed row count survives. */
  preview(run: () => void): void {
    const rollback = new Error("storage preview");
    const before = this.rowsWritten;
    this.previewing = true;
    try {
      this.storage.transactionSync(() => {
        this.transaction(run);
        throw rollback;
      });
    } catch (e) { if (e !== rollback) throw e; }
    finally {
      this.previewing = false;
      this.tables = undefined;
      this.persistAttempts(this.rowsWritten - before, this.reportWritten);
    }
  }
  private exec(query: string, ...bindings: SqlStorageValue[]): SqlStorageCursor<Row> {
    if (this.statements && /^(INSERT|UPDATE|DELETE|CREATE|DROP)/i.test(query)) this.statements.push([query, bindings]);
    const mutation = /^(?:INSERT(?: OR \w+)? INTO|UPDATE|DELETE FROM) (\w+)/i.exec(query);
    const drop = /^DROP TABLE (?:IF EXISTS )?(\w+)/i.exec(query);
    if (!mutation && !drop) {
      if (!/^CREATE/i.test(query)) return this.storage.sql.exec(query, ...bindings);
      return this.transaction(() => {
        const cursor = this.storage.sql.exec(query, ...bindings);
        this.count(cursor);
        return cursor;
      });
    }
    return this.transaction(() => {
      const name = (mutation ?? drop)![1]!;
      // State is counted as metadata by total(), and bounded counters do not
      // contribute payload. Their mutations still share the transaction gate.
      if (ignored.has(name)) {
        const before = name === "state" ? this.meta() : null;
        const cursor = this.storage.sql.exec(query, ...bindings);
        const after = before && this.meta();
        const accounting = name === "row_attempts" || !!(before && after && applicationContent(before) === applicationContent(after));
        this.count(cursor, accounting);
        return cursor;
      }
      if (drop) {
        const exists = this.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", name).toArray().length > 0;
        const table = this.tables!.get(name) ?? (exists ? this.loadTable(name) : undefined);
        const cursor = this.storage.sql.exec(query, ...bindings);
        this.count(cursor);
        if (table) for (const n of table.sizes.values()) this.payload -= n;
        this.tables!.delete(name);
        return cursor;
      }
      let table = this.tables!.get(name);
      if (!table) { table = this.loadTable(name); this.tables!.set(name, table); }
      const cursor = this.storage.sql.exec(`${query} RETURNING *`, ...bindings);
      for (const row of cursor) {
        const key = this.key(table, row), old = table.sizes.get(key) ?? 0;
        const next = /^DELETE/i.test(query) ? 0 : size(row);
        this.payload += next - old;
        if (next) table.sizes.set(key, next); else table.sizes.delete(key);
      }
      this.count(cursor);
      return cursor;
    });
  }
}
