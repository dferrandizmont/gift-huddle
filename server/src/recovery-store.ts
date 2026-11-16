import type { ApiResult } from "./http";
import { err } from "./http";
import { CHUNK_CHARS, RECOVERY_MAX_HISTORY_BYTES, RECOVERY_MAX_IDS, RECOVERY_MAX_RECEIPTS, RECOVERY_MAX_RECEIPT_BYTES, RECOVERY_MAX_RETIRED_VERIFIERS, RECOVERY_MUTATIONS_PER_MINUTE, RECOVERY_WRITES_PER_DAY, RECOVERY_WRITES_PER_DEVICE_DAY, RECOVERY_CLAIMS_PER_DAY, RECOVERY_CLAIMS_PER_DEVICE_DAY, RECOVERY_MAX_IDS_PER_DEVICE } from "./limits";
import { bytes } from "./v2-contract";

export type RecoveryReceipt = { operationId: string; fingerprint: string; verifier: string; response: ApiResult };
export type RecoveryRow = {
  rid: string; deviceId: string; reservationId: string;
  state: "intention" | "active" | "candidate" | "retired";
  readVerifier: string; revision: number; size: number;
  published?: boolean;
  initial: RecoveryReceipt;
  /** Candidate's source CAS and deadline are immutable, including after closure. */
  parent?: string; expectedRevision?: number; expiresAt?: number;
  terminal?: "committed" | "cancelled" | "expired";
  claim?: RecoveryReceipt;
  deletion?: { verifier: string; deviceId: string; expectedRevision: number; response: ApiResult };
  commit?: { verifier: string; expectedRevision: number; response: ApiResult };
};
type Quota = { minute: number; mutations: number; day: number; writes: number; claims?: number; devices?: Record<string, { writes: number; claims: number }> };

/** All methods run under the list's concurrency lock. Its caller chooses the
 * transaction so credential, invitations, recovery and quota commit together. */
export class RecoveryStore {
  constructor(private readonly sql: SqlStorage) {}
  private exists(table: string): boolean {
    return this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", table).toArray().length > 0;
  }
  rows(): RecoveryRow[] {
    return this.exists("recovery") ? this.sql.exec<{ data: string }>("SELECT data FROM recovery").toArray().map((r) => JSON.parse(r.data) as RecoveryRow) : [];
  }
  get(rid: string): RecoveryRow | undefined {
    if (!this.exists("recovery")) return undefined;
    const row = this.sql.exec<{ data: string }>("SELECT data FROM recovery WHERE rid = ?", rid).toArray()[0];
    return row ? JSON.parse(row.data) as RecoveryRow : undefined;
  }
  save(row: RecoveryRow): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS recovery (rid TEXT PRIMARY KEY, data TEXT NOT NULL) WITHOUT ROWID");
    this.sql.exec("INSERT INTO recovery (rid, data) VALUES (?, ?) ON CONFLICT(rid) DO UPDATE SET data = excluded.data", row.rid, JSON.stringify(row));
  }
  /** reserve(false) proves this token was never assigned globally. Unlike an
   * abandoned successful reservation, it needs no tombstone or lifetime slot. */
  discardUnreserved(row: RecoveryRow): void {
    this.sql.exec("DELETE FROM recovery WHERE rid = ?", row.rid);
    const q = this.quota(), acceptedAt = row.expiresAt! - 86400000;
    if (q.minute === Math.floor(acceptedAt / 60000)) q.mutations = Math.max(0, q.mutations - 1);
    if (q.day === Math.floor(acceptedAt / 86400000)) {
      q.writes = Math.max(0, q.writes - 1);
      const device = q.devices && Object.hasOwn(q.devices, row.deviceId) ? q.devices[row.deviceId] : undefined;
      if (device) device.writes = Math.max(0, device.writes - 1);
    }
    this.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify(q));
  }
  blob(rid: string): string {
    return this.exists("recovery_blob") ? this.sql.exec<{ data: string }>("SELECT data FROM recovery_blob WHERE rid = ? ORDER BY idx", rid).toArray().map((r) => r.data).join("") : "";
  }
  writeBlob(rid: string, capsule: string): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS recovery_blob (rid TEXT NOT NULL, idx INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (rid, idx)) WITHOUT ROWID");
    this.sql.exec("DELETE FROM recovery_blob WHERE rid = ?", rid);
    for (let at = 0; at < capsule.length; at += CHUNK_CHARS) this.sql.exec("INSERT INTO recovery_blob (rid, idx, data) VALUES (?, ?, ?)", rid, at / CHUNK_CHARS, capsule.slice(at, at + CHUNK_CHARS));
  }
  close(row: RecoveryRow, terminal?: RecoveryRow["terminal"]): void {
    row.state = "retired";
    if (terminal) row.terminal = terminal;
    this.save(row);
    if (this.exists("recovery_blob")) this.sql.exec("DELETE FROM recovery_blob WHERE rid = ?", row.rid);
  }
  retired(verifier: string | null): { deviceId: string } | undefined {
    if (verifier === null || !this.exists("recovery_retired")) return undefined;
    return this.sql.exec<{ deviceId: string }>("SELECT device AS deviceId FROM recovery_retired WHERE verifier = ?", verifier).toArray()[0];
  }
  retireVerifier(verifier: string, deviceId: string): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS recovery_retired (verifier TEXT PRIMARY KEY, device TEXT NOT NULL, cause TEXT NOT NULL) WITHOUT ROWID");
    this.sql.exec("INSERT INTO recovery_retired (verifier, device, cause) VALUES (?, ?, 'claim')", verifier, deviceId);
  }
  /** Reserve two lifetime receipts per id (initial + terminal), plus a reusable
   * claim receipt for each live id. 8 KiB per id includes all terminal metadata;
   * retired hashes reserve 256 bytes each. These reservations are never pruned. */
  history(nextRows: RecoveryRow[], additionalVerifier = false): ApiResult | null {
    const perDevice = new Map<string, number>();
    for (const row of nextRows) perDevice.set(row.deviceId, (perDevice.get(row.deviceId) ?? 0) + 1);
    // Existing over-limit legacy history must not block another identity or a
    // claim that allocates no new id. Only reject an increase beyond the cap.
    const current = new Map<string, number>();
    for (const row of this.rows()) current.set(row.deviceId, (current.get(row.deviceId) ?? 0) + 1);
    const identityFull = [...perDevice].some(([device, count]) => count > RECOVERY_MAX_IDS_PER_DEVICE && count > (current.get(device) ?? 0));
    const hashes = this.exists("recovery_retired") ? this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM recovery_retired").one().n : 0;
    const count = hashes + Number(additionalVerifier);
    const receipts = nextRows.length * 2 + nextRows.filter((r) => r.state !== "retired" || r.claim !== undefined).length;
    const tooBigReceipt = nextRows.some((r) => [r.initial, r.claim, r.deletion, r.commit].some((receipt) => receipt && bytes(receipt) > RECOVERY_MAX_RECEIPT_BYTES));
    const metadata = nextRows.reduce((n, r) => n + Math.max(8192, bytes(r)), 0) + count * 256 + 4096;
    return identityFull || nextRows.length > RECOVERY_MAX_IDS || receipts > RECOVERY_MAX_RECEIPTS || count > RECOVERY_MAX_RETIRED_VERIFIERS || metadata > RECOVERY_MAX_HISTORY_BYTES || tooBigReceipt ? err(409, "recovery_history_full") : null;
  }
  private quota(): Quota {
    if (!this.exists("recovery_quota")) return { minute: 0, mutations: 0, day: 0, writes: 0 };
    return JSON.parse(this.sql.exec<{ data: string }>("SELECT data FROM recovery_quota").one().data) as Quota;
  }
  quotaError(write: boolean, deviceId: string, claim = false): ApiResult | null {
    const q = this.quota();
    const now = Date.now();
    const minute = Math.floor(now / 60000), day = Math.floor(now / 86400000);
    const device = q.devices && Object.hasOwn(q.devices, deviceId) ? q.devices[deviceId] : undefined;
    const dailyFull = claim
      ? (q.claims ?? 0) >= RECOVERY_CLAIMS_PER_DAY || (device?.claims ?? 0) >= RECOVERY_CLAIMS_PER_DEVICE_DAY
      : q.writes >= RECOVERY_WRITES_PER_DAY || (device?.writes ?? 0) >= RECOVERY_WRITES_PER_DEVICE_DAY;
    const until = q.minute === minute && q.mutations >= RECOVERY_MUTATIONS_PER_MINUTE ? (minute + 1) * 60000 : write && q.day === day && dailyFull ? (day + 1) * 86400000 : 0;
    return until ? err(429, "rate_limited", { "Retry-After": String(Math.max(1, Math.ceil((until - now) / 1000))) }) : null;
  }
  charge(write: boolean, deviceId: string, claim = false): void {
    const q = this.quota();
    const minute = Math.floor(Date.now() / 60000), day = Math.floor(Date.now() / 86400000);
    const devices = q.day === day ? q.devices ?? {} : {};
    const device = Object.hasOwn(devices, deviceId) ? devices[deviceId]! : { writes: 0, claims: 0 };
    // Identifiers may be object prototype names; always create an own property.
    Object.defineProperty(devices, deviceId, { value: { writes: device.writes + Number(write && !claim), claims: device.claims + Number(write && claim) }, enumerable: true, configurable: true, writable: true });
    const fresh: Quota = { minute, day, mutations: (q.minute === minute ? q.mutations : 0) + 1, writes: (q.day === day ? q.writes : 0) + Number(write && !claim), claims: (q.day === day ? q.claims ?? 0 : 0) + Number(write && claim), devices };
    this.sql.exec("CREATE TABLE IF NOT EXISTS recovery_quota (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL)");
    this.sql.exec("INSERT INTO recovery_quota (id, data) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data", JSON.stringify(fresh));
  }
}
