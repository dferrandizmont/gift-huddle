import type { RpcStub } from "cloudflare:workers";
import type { AuthenticatedBody } from "./authenticated-body";
import { ListStorageBudget, ListTooLarge, StorageBlocksNeeded } from "./list-storage-budget";
import { clientKey48 } from "./ip";
import { rowRetryAfter, type RowReports, type RowStatus } from "./daily-row-budget";
import { euNamespace, localhostRequest } from "./eu-namespace";
import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { decodeB64Url, encodeB64Url, randomBytes, sha256, timingSafeEqual } from "./encoding";
import { err, NOT_FOUND, UNAUTHORIZED, readJsonObject, type ApiResult } from "./http";
import {
  CHUNK_CHARS,
  INVITE_TTL_MS,
  LIST_TTL_MS,
  MAX_FIRST_UPLOAD_BYTES,
  MAX_OPEN_INVITES,
  MAX_SOCKETS,
  MAX_WRITES_PER_WINDOW,
  NEW_LIST_WINDOW_MS,
  TOUCH_INTERVAL_MS,
  V2_CREDENTIAL_REQUESTS,
  V2_CREDENTIAL_WRITES,
  V2_INVITE_REQUESTS_PER_INVITE,
  V2_MAX_CHECKPOINTS,
  V2_MAX_DECLARATION_BYTES,
  V2_MAX_DEVICES,
  V2_MAX_KNOWN_RECORDS,
  V2_MAX_PACKAGE_BYTES,
  V2_MAX_PACKAGES_PER_WRITER,
  V2_MAX_PACKAGE_BYTES_PER_WRITER,
  V2_MAX_REVEAL_BYTES,
  V2_MAX_SLOTS,
  V2_MAX_SLOTS_PER_WRITER,
  V2_MAX_WEB_SLOTS,
  V2_NEW_DEVICES_PER_LIST,
  V2_NEW_LISTS_PER_HOUR,
  V2_NEW_LISTS_PER_DAY,
  V2_NEW_LISTS_PER_DAY_48,
  V2_LIST_ROWS_PER_DAY,
  V2_CLIENT_ROWS_PER_DAY,
  V2_CLIENT_ROWS_PER_DAY_48,
  V2_ROW_REPORT_BLOCK,
  V2_ROW_REPORT_MS,
  V2_ROW_STATUS_MS,
  V2_ROW_REPORT_KEYS,
  V2_CREDENTIAL_CAP_AGE_MS,
  V2_STORAGE_BLOCK_BYTES,
  V2_NEW_RECORDS_PER_CREDENTIAL,
  V2_NEW_RECORDS_PER_LIST,
  V2_QUOTA_WINDOW_MS,
  V2_NEW_LISTS_PER_HOUR_48,
  V2_REVOKED_SLOTS_GRACE_MS,
  V2_WARN_DEVICES,
  V2_WARN_KNOWN_RECORDS,
  V2_WARN_SLOTS,
  V2_LEGACY_MAX_SLOTS,
  V2_LEGACY_WARN_SLOTS,
  V2_SLOT_CAPACITY,
  V2_WS_PROTOCOL,
  WINDOW_MS,
} from "./limits";
import { bytes, canonicalJson, commonFormatError, commonFormatValue, identifier, storedCommonFormat, key32, object, validateCommon, validateSlotData, validateSnapshot, type SlotChange, type Snapshot, type V2Route, type V2Device, type Role } from "./v2-contract";
import { PinGuard } from "./pin-guard";
import { renewalCanClose, renewalProjection, renewalHash, renewalCommand, verifyRenewalSignature, transitionRenewal, type RenewalState, type RenewalCommand, type RenewalHistory } from "./renewal";
import { V2_RENEWAL_REQUESTS, V2_RENEWAL_WRITES, V2_MAX_RENEWAL_PARTICIPANTS, V2_RENEWAL_LOG_COMMANDS, V2_RENEWAL_LOG_BYTES, V2_RENEWAL_LOG_PAGE_COMMANDS, V2_RENEWAL_LOG_PAGE_BYTES } from "./limits";
import { RecoveryStore, type RecoveryRow } from "./recovery-store";
import { operationId, recoveryCas, recoveryEtag, recoveryFingerprint, recoveryShape, validateCapsule } from "./recovery-contract";
import { RECOVERY_MAX_ACTIVE, RECOVERY_MAX_ACTIVE_BYTES, RECOVERY_RESERVATION_MS } from "./limits";
import { V2_BODY_READ_DEADLINE_MS } from "./limits";

type Counter = { start: number; count: number };
class RowsLimited extends Error {}
/** `verifier` is SHA-256 of the service credential; null once revoked. */
type Credential = {
  createdAt?: number;
  /** Immutable key captured only at credential registration. */
  signingKey?: string;
  /** Explicit support announcement, independent of common ciphertext format. */
  renewalProtocol?: 1;
  lastRequest?: number;
  deviceId: string;
  verifier: string | null;
  revoked: boolean;
  /** Fixed at service revocation; removed after the writer's slots are erased. */
  slotsExpireAt?: number;
  approvedBy?: string;
  /** Absent in pre-web rows: those credentials remain devices. */
  role?: Role;
  /** When this credential added its recent new record declarations (sliding 24 h, at most 8). */
  records: number[];
  /**
   * The latest common format this credential has announced it reads and writes
   * (`POST S/capability`, ADR 0005, B4). Absent: 1. Only ever goes up. Service
   * data, not signed trust: phones decide the cut-over from it, and a lying
   * server can only delay or break availability, never decrypt.
   */
  commonFormat?: number;
  /**
   * 2 once this credential announced it reads slot lists of up to V2_MAX_SLOTS
   * (`POST S/capability {slotCapacity: 2}`, 1.0.6). Absent: 1, the 1.0.5 cap of
   * V2_LEGACY_MAX_SLOTS. Service data like `commonFormat`: a lying server or
   * phone can only break availability.
   */
  slotCapacity?: number;
};
type Meta = {
  /** Invitation lifetime, extended only by a new invitation within the fixed cap. */
  inviteCopyExpiresAt?: number;
  inviteCopyMaxExpiresAt?: number;
  renewalStartedAt?: number;
  renewalReturned?: string[];
  /** One activity fence per participant and operation, separate from signed resume. */
  renewalActivityUsed?: string[];
  storedBytes?: number;
  rowBudget?: { day: number; written: number };
  rowReports?: RowReports;
  syncId: string;
  version: number;
  /** Actual birth of the list, independent of credential age backfills. */
  createdAt?: number;
  lastAccess: number;
  credentials: Credential[];
  /** Verifiers of revoked credentials: they can never register again in this list. */
  denied: string[];
  /** SHA-256 of every device-record declaration this generation has accepted. */
  knownRecords: string[];
  /** When the list accepted its recent new record declarations, from any credential (at most 16). */
  recordTimes: number[];
  /** When the list registered its recent credentials (at most 8). */
  approvals: number[];
  /**
   * Lowest common format this generation accepts (ADR 0005, B4). Absent: 1.
   * Raised by a device in the same `PUT` that uploads the first common of that
   * format, never lowered: `PUT S` and `PUT S/common` refuse anything older.
   */
  minCommonFormat?: number;
};
/**
 * All that is left of a deleted or expired list: its state row holds only this
 * marker (no credentials, device ids, hashes or content) and refuses `create`
 * for 400 days. Its deadline is kept separately in storage, including through retries.
 */
const RETIRED = { retired: true } as const;
type Stored = Meta | typeof RETIRED | null;
export type PurgeCriteria = { createdFrom: number; createdBefore: number; inactiveBefore: number; includeLegacy?: true };
export type PurgeCandidate = {
  createdAt: number | null;
  lastActivity: number;
  version: number;
  storedBytes: number;
  hasRecovery: false;
  pendingInvites: number;
};
const isRetired = (s: Stored): s is typeof RETIRED => s !== null && "retired" in s;
const MARKER_TEXT = JSON.stringify(RETIRED);
const RETIRED_UNTIL = "retiredUntil";
// An upper bound on activity: renewal must never exclude someone before 72 h.
const activityHour = (time: number): number => Math.ceil(time / TOUCH_INTERVAL_MS) * TOUCH_INTERVAL_MS;
const strings = (v: unknown): boolean => Array.isArray(v) && v.every((x) => typeof x === "string");
const numbers = (v: unknown): boolean => Array.isArray(v) && v.every((x) => typeof x === "number");
/**
 * A state row in the current format, and nothing else. A row with `deleted: true`
 * (the earlier deletion marker), one missing a field of this format or one that
 * does not parse is treated as retired (finding 17): never as a live list.
 */
function isCurrentMeta(v: unknown): v is Meta {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false;
  const m = v as Record<string, unknown>;
  if (m.deleted !== undefined || m.retired !== undefined) return false;
  return (
    typeof m.syncId === "string" &&
    Number.isSafeInteger(m.version) &&
    (m.version as number) >= 1 &&
    typeof m.lastAccess === "number" &&
    (m.inviteCopyExpiresAt === undefined || (Number.isSafeInteger(m.inviteCopyExpiresAt) && (m.inviteCopyExpiresAt as number) >= 0)) &&
    Array.isArray(m.credentials) &&
    m.credentials.every(
      (c: unknown) =>
        typeof c === "object" &&
        c !== null &&
        typeof (c as Credential).deviceId === "string" &&
        ((c as Credential).verifier === null || typeof (c as Credential).verifier === "string") &&
        typeof (c as Credential).revoked === "boolean" &&
        ((c as Credential).signingKey === undefined || key32((c as Credential).signingKey)) &&
        ((c as Credential).renewalProtocol === undefined || (c as Credential).renewalProtocol === 1) &&
        ((c as Credential).lastRequest === undefined || (Number.isSafeInteger((c as Credential).lastRequest) && (c as Credential).lastRequest! >= 0)) &&
        ((c as Credential).approvedBy === undefined || identifier((c as Credential).approvedBy)) &&
        ((c as Credential).role === undefined || (c as Credential).role === "device" || (c as Credential).role === "web") &&
        numbers((c as Credential).records) &&
        ((c as Credential).commonFormat === undefined || storedCommonFormat((c as Credential).commonFormat)) &&
        ((c as Credential).slotCapacity === undefined || (c as Credential).slotCapacity === V2_SLOT_CAPACITY),
    ) &&
    (m.minCommonFormat === undefined || storedCommonFormat(m.minCommonFormat)) &&
    (m.renewalReturned === undefined || (Array.isArray(m.renewalReturned) && m.renewalReturned.length <= V2_MAX_RENEWAL_PARTICIPANTS && m.renewalReturned.every(identifier) && new Set(m.renewalReturned).size === m.renewalReturned.length)) &&
    (m.renewalActivityUsed === undefined || (Array.isArray(m.renewalActivityUsed) && m.renewalActivityUsed.length <= V2_MAX_RENEWAL_PARTICIPANTS && m.renewalActivityUsed.every(identifier) && new Set(m.renewalActivityUsed).size === m.renewalActivityUsed.length)) &&
    (m.renewalStartedAt === undefined || (Number.isSafeInteger(m.renewalStartedAt) && (m.renewalStartedAt as number) >= 0)) &&
    strings(m.denied) &&
    strings(m.knownRecords) &&
    numbers(m.recordTimes) &&
    numbers(m.approvals)
  );
}
function registrySigningKey(records: unknown[], deviceId: string): string | null {
  const keys = new Set(records.flatMap((r) => object(r) && r.d === deviceId && key32(r.e) ? [r.e] : []));
  return keys.size === 1 ? [...keys][0]! : null;
}

type Invitation = {
  id: string;
  reservationId?: string;
  owner: string;
  expiresAt: number;
  offer: Record<string, unknown>;
  guestPerson?: string | null;
  answer?: Record<string, unknown>;
  guest?: string;
  verifier?: string;
  reveal?: Record<string, unknown>;
  package?: Record<string, unknown>;
  minVersion?: number;
  /**
   * Hashes of the pairing checkpoint (ADR 0005, B7) copied at approval: the
   * exact common and registry the host approved, kept in `checkpoint` rows.
   */
  checkpoint?: { common: string; registry: string };
};
type Release = Pick<Invitation, "id" | "expiresAt" | "reservationId"> & { syncId: string };
export type V2Call = {
  /** Internal router proof, never taken from a client header/body. */
  localRequest?: boolean;
  /** Router's fail-closed switch, independent of the object's environment. */
  renewalDisabled?: boolean;
  recoveryReadVerifier?: string;
  recoveryOperation?: string;
  automaticRetirement?: boolean;
  destinationCreated?: boolean;
  route: V2Route;
  method: string;
  verifier: string | null;
  client: string;
  client48?: string;
  match: string | null;
  none: string | null;
  body: Record<string, unknown>;
  bodyAuthorized?: boolean;
};

/** WebSocket close codes. */
const CLOSE_REVOKED = 4401;
const CLOSE_GONE = 4404;
const CLOSE_POLICY = 1008;
const CLOSE_REPLACED = 4410;

const limited = (retryAfter = 60) => err(429, "rate_limited", { "Retry-After": String(retryAfter) });
const etag = (version: number) => `"${version}"`;
const equal = (a: string, b: string): boolean => timingSafeEqual(decodeB64Url(a, 32)!, decodeB64Url(b, 32)!);
const snapshotError = (status: 400 | 413) => err(status, status === 413 ? "too_large" : "bad_request");
/**
 * Hash of one part of a pairing checkpoint (ADR 0005, B7): SHA-256 of a domain,
 * a zero byte and the exact UTF-8 text served (the common's base64url text, or
 * the registry as canonical JSON), in base64url. The app computes the same.
 */
async function checkpointHash(part: "common" | "registry", text: string): Promise<string> {
  const domain = new TextEncoder().encode(`gift-huddle-pairing-checkpoint-${part}-v1`);
  const body = new TextEncoder().encode(text);
  const message = new Uint8Array(domain.length + 1 + body.length);
  message.set(domain);
  message.set(body, domain.length + 1);
  return encodeB64Url(await sha256(message));
}
/**
 * Slot ownership (ADR 0005, 7): a device credential changes only its own slots,
 * with data or with `data: null`, never another writer's (active, revoked,
 * orphaned, of a deleted person or of an old epoch). Checked over the whole
 * delta before anything is written, so a mixed delta is refused entirely.
 */
function slotOwnership(slots: SlotChange[], deviceId: string, role: Role): ApiResult | null {
  if (slots.length === 0) return null;
  if (role !== "device") return err(403, "forbidden_role");
  return slots.some((x) => x.deviceId !== deviceId) ? err(403, "forbidden_slot") : null;
}
/**
 * Key package ownership (ADR 0005, B3), like slots in B2: an entry that is not
 * already stored is accepted only when its `from` is the caller, so nobody can
 * plant packages in another device's name. Stored entries forwarded unchanged
 * are kept (older apps upload the whole list) and dropping any entry is
 * allowed. A new entry must be a v3 (surprise) or v4 (common key) package
 * (`400 bad_package` otherwise). One writer has at most
 * [V2_MAX_PACKAGES_PER_WRITER] entries and [V2_MAX_PACKAGE_BYTES_PER_WRITER]
 * bytes of both kinds together, a quarter of the list's caps, so it takes at
 * least four credentials to fill the list and block a rotation; a writer
 * already above may keep or drop its own. A list with the same entry twice
 * is `400`: copies of a stored entry would otherwise skip these checks.
 */
function packageOwnership(fresh: unknown[], stored: unknown[], deviceId: string, role: Role): ApiResult | null {
  if (new Set(fresh.map((p) => JSON.stringify(p))).size !== fresh.length) return err(400, "duplicate_package");
  const known = new Set(stored.map((p) => JSON.stringify(p)));
  const added = fresh.filter((p) => !known.has(JSON.stringify(p)));
  if (added.length === 0) return null;
  if (role !== "device") return err(403, "forbidden_role");
  if (added.some((p) => !object(p) || p.from !== deviceId)) return err(403, "forbidden_package");
  if (added.some((p) => object(p) && p.v !== 3 && p.v !== 4)) return err(400, "bad_package");
  const own = (list: unknown[]) => list.filter((p) => object(p) && p.from === deviceId);
  const size = (list: unknown[]) => list.reduce<number>((n, p) => n + bytes(p), 0);
  const after = own(fresh);
  const before = own(stored);
  if (after.length > V2_MAX_PACKAGES_PER_WRITER && after.length > before.length) return err(413, "too_many_writer_packages");
  if (size(after) > V2_MAX_PACKAGE_BYTES_PER_WRITER && size(after) > size(before)) return err(413, "too_many_writer_packages");
  return null;
}
/** Sliding window: the times that still count, oldest first. */
const recent = (times: number[], now: number) => times.filter((t) => now - t < V2_QUOTA_WINDOW_MS);
/** Seconds until `n` more fit under `max`, or 0 if they fit now (`times` comes from `recent`). */
function waitFor(times: number[], n: number, max: number, now: number): number {
  if (times.length + n <= max) return 0;
  if (n > max) return V2_QUOTA_WINDOW_MS / 1000;
  return Math.max(1, Math.ceil((times[times.length + n - max - 1]! + V2_QUOTA_WINDOW_MS - now) / 1000));
}
/** A generation cap is permanent: the app offers to renew (new syncId) when it sees this. */
const generationFull = () => err(409, "generation_full");
const recordHash = async (record: unknown) => encodeB64Url(await sha256(new TextEncoder().encode(JSON.stringify(record))));
/** Stable digest of an offer, independent of JSON object key order. */
function canonical(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(canonical);
  if (object(v)) return Object.fromEntries(Object.keys(v).sort().map((k) => [k, canonical(v[k])]));
  return v;
}

/** Explicit allowlist: every newly added route starts closed to web credentials. */
function webAllowed(auth: Credential, c: V2Call): boolean {
  const r = c.route;
  return (c.method === "GET" && ["list", "slot", "ws", "renewal"].includes(r.resource)) ||
    (c.method === "PUT" && r.resource === "renewal" && ["ack", "resume", "capability"].includes(c.body.action as string)) ||
    (c.method === "PUT" && r.resource === "common") ||
    // 1.0.6 (ADR 0009): a web writes only its own inbox slots.
    (c.method === "PUT" && r.resource === "slot" && r.deviceId === auth.deviceId) ||
    // ADR 0005, B5: a web announces the common format it reads and writes.
    (c.method === "POST" && r.resource === "capability") ||
    (c.method === "POST" && r.resource === "revoke" && c.body.deviceId === auth.deviceId) ||
    (r.resource === "guard" && r.deviceId === auth.deviceId &&
      ((c.method === "PUT" && r.action === "prepare") || (c.method === "POST" && (r.action === "commit" || r.action === "cancel"))));
}

/**
 * One EU Durable Object per v2 list. Every request runs under one lock
 * (`blockConcurrencyWhile`), so revocation, PUT, DELETE, approval and invitation
 * delivery are totally ordered: nothing a revoked credential sends after its
 * revocation is accepted. It stores ciphertext, the signed registry as opaque
 * JSON and credential hashes; it never verifies signatures or decides trust.
 */
export class ListV2Object extends DurableObject<Env> {
  private bodyReads = new Map<string, number>();
  private rowCall?: V2Call;
  private exhaustedUntil = new Map<string, number>();
  private rowRetryAt?: number;
  /** Minute counters are deliberately ephemeral across hibernation. */
  private rate = new Map<string, Counter>();
  /** Scoped to the object lock; alarms and unrelated RPCs never inherit it. */
  private localRequest = false;

  private async withLocalRequest<T>(local: boolean, run: () => Promise<T>): Promise<T> {
    this.localRequest = local;
    try {
      return await run();
    } finally {
      this.localRequest = false;
    }
  }

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // Ping is handled under the authorization gate too: an automatic pong
    // would bypass credential replacement after hibernation.
  }

  private budget = new ListStorageBudget(this.ctx.storage);

  private get sql() { return this.budget.sql; }

  private ledgerBlocks?: number;
  private ledger() {
    const ns = euNamespace(this.env.STORAGE_LEDGER, this.env, this.localRequest);
    return ns.get(ns.idFromName("v2:storage"));
  }
  private currentBlocks(): number {
    const m = this.stored();
    // Uncommitted admission caches must not change the authoritative balance.
    return m && !isRetired(m) ? Math.ceil((m.storedBytes ?? this.budget.decorate(m).storedBytes ?? 0) / V2_STORAGE_BLOCK_BYTES) : 0;
  }
  private async armLedgerRetry(): Promise<void> {
    const next = Date.now() + WINDOW_MS, alarm = await this.ctx.storage.getAlarm();
    if (alarm === null || alarm > next) await this.ctx.storage.setAlarm(next);
  }
  /** A later maintenance deadline must never disarm durable reconciliation. */
  private async scheduleAlarm(next: number): Promise<void> {
    const now = Date.now(), current = await this.ctx.storage.getAlarm();
    const saved = await this.ctx.storage.get<{ pending?: boolean }>("storageLedger");
    if (this.rowRetryAt !== undefined) next = Math.min(next, Math.max(now + WINDOW_MS, this.rowRetryAt));
    if (saved?.pending) next = Math.min(next, current !== null && current > now ? current : now + WINDOW_MS, now + WINDOW_MS);
    if (current === next || ((saved?.pending || this.rowRetryAt !== undefined) && current !== null && current > now && current <= next)) return;
    await this.ctx.storage.setAlarm(Math.max(now + 1, next));
  }

  private async reconcileLedger(): Promise<void> {
    const blocks = this.currentBlocks();
    const saved = await this.ctx.storage.get<{ blocks: number; pending?: boolean }>("storageLedger");
    if (!saved && blocks === 0 && !this.ledgerBlocks) { this.ledgerBlocks = 0; return; }
    if (saved?.pending || this.ledgerBlocks === undefined || blocks !== this.ledgerBlocks) {
      // A legacy list is enrolled even above the ceiling. All subsequent
      // growth is reserved before local commit by commit().
      const previousAlarm = await this.ctx.storage.getAlarm();
      await this.ctx.storage.put("storageLedger", { blocks: saved?.blocks ?? 0, pending: true });
      await this.armLedgerRetry();
      await this.ledger().set(this.ctx.id.toString(), blocks, true);
      if (blocks) await this.ctx.storage.put("storageLedger", { blocks });
      else await this.ctx.storage.delete("storageLedger");
      const m = this.stored();
      const next = m && !isRetired(m) ? this.nextAlarm(m) : await this.ctx.storage.get<number>(RETIRED_UNTIL);
      if (next !== undefined) await this.scheduleAlarm(saved?.pending ? next : Math.min(previousAlarm ?? next, next));
    }
    this.ledgerBlocks = blocks;
  }
  private async withLedger<T>(run: () => Promise<T>): Promise<T> {
    const saved = await this.ctx.storage.get<{ blocks: number; pending?: boolean }>("storageLedger");
    this.ledgerBlocks = saved?.blocks;
    try { await this.reconcileLedger(); }
    catch { await this.armLedgerRetry(); }
    try { return await run(); }
    finally {
      try { await this.reconcileLedger(); }
      catch { await this.armLedgerRetry(); }
    }
  }
  private async commit(run: () => void, cleanup = false, report = true, accounting = false): Promise<void> {
    if (!cleanup && this.rowCall) await this.admitRows(this.rowCall);
    const counted = <T>(action: () => T): T => accounting ? this.budget.accountingOnly(action) : action();
    try { counted(() => this.budget.stage(run, this.ledgerBlocks ?? this.currentBlocks(), cleanup)); }
    catch (e) {
      if (!(e instanceof StorageBlocksNeeded)) throw e;
      // Persist a reconciliation intention before any remote effect. A crash
      // or lost response is repaired from committed local size on the alarm.
      if (e.blocks > (this.ledgerBlocks ?? 0)) await this.reserveBlocks(e.blocks);
      else {
        await this.ctx.storage.put("storageLedger", { blocks: this.ledgerBlocks ?? 0, pending: true });
        await this.armLedgerRetry();
      }
      counted(() => this.budget.replay(e.statements));
    }
    if (report) await this.settleRows();
  }
  private async reserveBlocks(blocks: number): Promise<void> {
    await this.ctx.storage.put("storageLedger", { blocks: this.ledgerBlocks ?? 0, pending: true });
    await this.armLedgerRetry();
    if (!await this.ledger().set(this.ctx.id.toString(), blocks)) throw new ListTooLarge();
    this.ledgerBlocks = blocks;
  }

  // ---- storage ----------------------------------------------------------------

  /** Read-only: probing an unknown syncId never creates a schema. */
  private stored(): Stored {
    const raw = this.rawState();
    if (raw === null) return null;
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return RETIRED;
    }
    return isCurrentMeta(parsed) ? parsed : RETIRED;
  }

  /** The state row as stored, or null when there is none. */
  private rawState(): string | null {
    if (!this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'state'").toArray().length) return null;
    return this.sql.exec<{ data: string }>("SELECT data FROM state WHERE id = 1").toArray()[0]?.data ?? null;
  }

  private saveMeta(m: Meta | typeof RETIRED, maintenance = false): void {
    this.budget.transaction(() => {
      this.sql.exec("INSERT INTO state (id, data) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data WHERE data != excluded.data", JSON.stringify(this.budget.decorate(m)));
    }, maintenance);
  }

  private createSchema(): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK (id = 1), data TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS common (idx INTEGER PRIMARY KEY, data TEXT NOT NULL)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS resource (name TEXT PRIMARY KEY, data TEXT NOT NULL)");
    this.sql.exec(
      "CREATE TABLE IF NOT EXISTS slot (person TEXT NOT NULL, device TEXT NOT NULL, ver INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (person, device))",
    );
    this.sql.exec("CREATE TABLE IF NOT EXISTS invite (id TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, data TEXT NOT NULL)");
  }

  /** Rows are rewritten only when their content changes (a row write is billed). */
  private writeSnapshot(s: Snapshot, version: number): void {
    this.writeCommon(s.common);
    for (const [name, value] of [["registry", s.registry], ["packages", s.keyPackages]] as const) {
      this.sql.exec(
        "INSERT INTO resource (name, data) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET data = excluded.data WHERE data != excluded.data",
        name,
        JSON.stringify(value),
      );
    }
    this.writeSlots(s.slots, version);
  }

  private writeSlots(slots: SlotChange[], version: number): void {
    for (const slot of slots) {
      if (slot.data === null) {
        this.sql.exec("DELETE FROM slot WHERE person = ? AND device = ?", slot.personId, slot.deviceId);
      } else {
        this.sql.exec(
          "INSERT INTO slot (person, device, ver, data) VALUES (?, ?, ?, ?) ON CONFLICT(person, device) DO UPDATE SET data = excluded.data, ver = excluded.ver WHERE data != excluded.data",
          slot.personId,
          slot.deviceId,
          version,
          slot.data,
        );
      }
    }
  }

  private writeCommon(common: string): void {
    const chunks = Math.max(1, Math.ceil(common.length / CHUNK_CHARS));
    for (let i = 0; i < chunks; i++) {
      this.sql.exec(
        "INSERT INTO common (idx, data) VALUES (?, ?) ON CONFLICT(idx) DO UPDATE SET data = excluded.data WHERE data != excluded.data",
        i,
        common.slice(i * CHUNK_CHARS, (i + 1) * CHUNK_CHARS),
      );
    }
    this.sql.exec("DELETE FROM common WHERE idx >= ?", chunks);
  }

  private readCommon(): string {
    return this.sql.exec<{ data: string }>("SELECT data FROM common ORDER BY idx").toArray().map((r) => r.data).join("");
  }

  private readResource(name: string): unknown {
    return JSON.parse(this.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = ?", name).one().data);
  }

  private readonly renewalHashes = new WeakMap<RenewalCommand, string>();

  private ensureRenewalLog(): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS renewal_command (operation TEXT NOT NULL, height INTEGER NOT NULL, hash TEXT NOT NULL, data TEXT NOT NULL, action TEXT NOT NULL, signer TEXT NOT NULL, target TEXT NOT NULL, new_device TEXT, new_key TEXT, PRIMARY KEY(operation, height), UNIQUE(operation, hash))");
    this.sql.exec("CREATE INDEX IF NOT EXISTS renewal_target ON renewal_command(operation, target, action)");
    this.sql.exec("CREATE INDEX IF NOT EXISTS renewal_device ON renewal_command(operation, new_device)");
    this.sql.exec("CREATE INDEX IF NOT EXISTS renewal_key ON renewal_command(operation, new_key)");
    this.sql.exec("CREATE INDEX IF NOT EXISTS renewal_signer ON renewal_command(operation, action, signer)");
    this.sql.exec("CREATE TABLE IF NOT EXISTS renewal_usage (operation TEXT NOT NULL, signer TEXT NOT NULL, count INTEGER NOT NULL, bytes INTEGER NOT NULL, PRIMARY KEY(operation, signer))");
  }

  private renewalHistory(operation: string): RenewalHistory {
    const exists = (query: string, ...args: (string | number)[]) => this.sql.exec(query, operation, ...args).toArray().length > 0;
    const afterRevoke = exists("SELECT 1 FROM renewal_command WHERE operation = ? AND action = 'revoke' LIMIT 1");
    return {
      exact: (hash) => exists("SELECT 1 FROM renewal_command WHERE operation = ? AND hash = ?", hash),
      target: (target) => exists("SELECT 1 FROM renewal_command WHERE operation = ? AND target = ? AND action IN ('reserve','replace','recover') LIMIT 1", target),
      identity: (c, sameOwner = false) => ["new_device", "new_key"].some((field) => exists(
        `SELECT 1 FROM renewal_command WHERE operation = ? AND ${field} = ?${sameOwner ? " AND (target != ? OR signer != ?)" : ""} LIMIT 1`,
        c[field === "new_device" ? "newDeviceId" : "newSigningKey"] as string,
        ...(sameOwner ? [c.targetSyncId, c.signerDeviceId] : []))),
      liveAck: (devices) => devices.some((d) => !d.revoked && exists("SELECT 1 FROM renewal_command WHERE operation = ? AND action = 'ack' AND signer = ? LIMIT 1", d.deviceId)),
      resumed: (signer) => exists("SELECT 1 FROM renewal_command WHERE operation = ? AND action = 'resume' AND signer = ? LIMIT 1", signer),
      usage: (signer) => ({ ...(this.sql.exec<{ count: number; bytes: number }>("SELECT count, bytes FROM renewal_usage WHERE operation = ? AND signer = ?", operation, signer).toArray()[0] ?? { count: 0, bytes: 0 }), afterRevoke }),
    };
  }

  private readRenewal(): RenewalState | null {
    const row = this.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = 'renewal'").toArray()[0];
    if (!row) return null;
    const p = JSON.parse(row.data);
    const resolve = (hash: string | null): RenewalCommand | null => {
      if (hash === null) return null;
      const c = this.sql.exec<{ data: string }>("SELECT data FROM renewal_command WHERE operation = ? AND hash = ?", p.operationId, hash).one();
      const command = JSON.parse(c.data) as RenewalCommand;
      this.renewalHashes.set(command, hash);
      return command;
    };
    for (const key of ["plan", "reservation", "recovery", "barrier", "abortion", "ready", "preparation", "confirmation"]) p[key] = resolve(p[key]);
    for (const key of ["acknowledgements", "transfers", "exclusions"]) p[key] = Object.fromEntries(Object.entries(p[key]).map(([id, h]) => [id, resolve(h as string)]));
    return { ...p, identities: [], revokedIdentities: {} };
  }

  private saveRenewal(s: RenewalState): void {
    const p = renewalProjection(s, (c) => {
      const hash = this.renewalHashes.get(c);
      if (!hash) throw new Error("missing renewal command");
      return hash;
    });
    this.sql.exec("INSERT INTO resource (name, data) VALUES ('renewal', ?) ON CONFLICT(name) DO UPDATE SET data = excluded.data", JSON.stringify(p));
  }

  /** Internal probe: minimal live destination creator and its committed key. */
  async renewalDestination(deviceId: string, signingKey: string): Promise<boolean> {
    return this.ctx.blockConcurrencyWhile(() => this.withLedger(async () => {
      const m = await this.live();
      if (!m || isRetired(m)) return false;
      const registry = this.readResource("registry") as { records: unknown[] };
      const creator = m.credentials[0];
      return m.credentials.length === 1 && creator !== undefined && creator.deviceId === deviceId &&
        !creator.revoked && (creator.role ?? "device") === "device" &&
        creator.signingKey === signingKey &&
        registry.records.some((r) => object(r) && r.d === deviceId && r.e === signingKey);
    }));
  }

  private async renewal(m: Meta, auth: Credential, c: V2Call, current: RenewalState | null): Promise<ApiResult> {
    const currentProjection = () => {
      const row = this.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = 'renewal'").toArray()[0];
      return row ? JSON.parse(row.data) : null;
    };
    const response = (): ApiResult => ({ status: 200, headers: { ETag: etag(m.version) }, body: { version: m.version, renewal: currentProjection() } });
    if (c.method === "GET") {
      if (c.route.logOperation) {
        this.ensureRenewalLog();
        const tip = this.sql.exec<{ height: number }>("SELECT height FROM renewal_command WHERE operation = ? AND hash = ?", c.route.logOperation, c.route.logHead!).toArray()[0];
        if (!tip || c.route.logAfter! > tip.height) return NOT_FOUND;
        const commands: unknown[] = [];
        let size = 2;
        const rows = this.sql.exec<{ data: string }>("SELECT data FROM renewal_command WHERE operation = ? AND height > ? AND height <= ? ORDER BY height LIMIT ?", c.route.logOperation, c.route.logAfter!, tip.height, V2_RENEWAL_LOG_PAGE_COMMANDS).toArray();
        for (const row of rows) {
          const weight = new TextEncoder().encode(row.data).length + (commands.length === 0 ? 0 : 1);
          if (size + weight > V2_RENEWAL_LOG_PAGE_BYTES && commands.length > 0) break;
          commands.push(JSON.parse(row.data)); size += weight;
        }
        const next = c.route.logAfter! + commands.length;
        return { status: 200, body: { operationId: c.route.logOperation, sourceSyncId: m.syncId, head: c.route.logHead, height: tip.height, after: c.route.logAfter, next: next === tip.height ? null : next, commands } };
      }
      return c.none === etag(m.version) ? { status: 304, headers: { ETag: etag(m.version) } } : response();
    }
    if (c.match === null) return err(428, "precondition_required", { ETag: etag(m.version) });
    // The signed validator and HTTP validator must be the same strong ETag.
    if (c.match !== etag(c.body.sourceVersion as number)) return err(412, "precondition_failed", { ETag: etag(m.version) });
    const registry = this.readResource("registry") as { records: unknown[] };
    const signingKeys = registry.records.flatMap((r) => object(r) && typeof r.e === "string" ? [r.e] : []);
    const devices = m.credentials.map((a): V2Device => ({ deviceId: a.deviceId, revoked: a.revoked, role: a.role ?? "device" }));
    this.ensureRenewalLog();
    if (!renewalCommand(c.body)) return err(400, "bad_renewal");
    // No key from this request participates in signature verification.
    if (!auth.signingKey) return err(409, "renewal_key_binding_required");
    if (!await verifyRenewalSignature(c.body, auth.signingKey)) return err(403, "renewal_bad_signature");
    if (c.body.action === "reserve") {
      const active = m.credentials.filter((a) => !a.revoked);
      if (active.some((a) => !a.signingKey)) return err(409, "renewal_key_binding_required");
      if (active.some((a) => a.renewalProtocol !== 1)) return err(409, "renewal_capability_required");
    }
    const history = this.renewalHistory(c.body.operationId);
    const hash = await renewalHash(c.body as RenewalCommand);
    this.renewalHashes.set(c.body, hash);
    if ((m.renewalReturned ?? []).length > 0 && ["prepare", "confirm"].includes(c.body.action as string)) return err(409, "renewal_revalidation_required");
    const next = transitionRenewal(current, c.body, {
      syncId: m.syncId, version: m.version, caller: { deviceId: auth.deviceId, revoked: false, role: auth.role ?? "device", commonFormat: auth.commonFormat }, devices, signingKeys,
      lastRequests: Object.fromEntries([
        ...(current?.participants ?? []).map((id) => [id, m.renewalStartedAt ?? Date.now()]),
        ...m.credentials.map((d) => [d.deviceId, d.lastRequest ?? Date.now()]),
      ]), now: Date.now(), history, commandHash: hash,
    });
    if (!next.ok) return { ...next.error, headers: { ...next.error.headers, ETag: etag(m.version) } };
    if (next.unchanged) return response();
    if (["reserve", "replace", "recover"].includes(c.body.action as string)) {
      if (c.destinationCreated !== true) return err(409, "renewal_destination_missing");
    }
    // Reserve cancels only unfinished invitations. Approved results/checkpoints
    // remain recoverable until installation, expiry or explicit cancellation.
    const removed = this.invites().filter((i) => c.body.action === "reserve" ? !i.package : c.body.action === "revoke" && (i.owner === c.body.participantDeviceId || i.guest === c.body.participantDeviceId));
    if (c.body.action === "reserve" && this.pendingReleases().length + removed.length > MAX_OPEN_INVITES) return limited();
    m.version++;
    if (c.body.action === "reserve") { m.renewalStartedAt = Date.now(); m.renewalActivityUsed = []; }
    if (["reserve", "revise", "replace", "recover"].includes(c.body.action as string)) m.renewalReturned = [];
    if (["resume", "revoke"].includes(c.body.action as string)) m.renewalReturned = (m.renewalReturned ?? []).filter((id) => id !== auth.deviceId);
    await this.commit(() => {
      this.sql.exec("INSERT INTO renewal_command (operation, height, hash, data, action, signer, target, new_device, new_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", next.state.operationId, next.state.height, hash, JSON.stringify(c.body), c.body.action, auth.deviceId, c.body.targetSyncId, c.body.newDeviceId as string ?? null, c.body.newSigningKey as string ?? null);
      if (c.body.action === "revoke") this.sql.exec("DELETE FROM renewal_usage WHERE operation = ?", next.state.operationId);
      else if ((next.state.height > V2_RENEWAL_LOG_COMMANDS || next.state.logBytes > V2_RENEWAL_LOG_BYTES) && !["recover", "abort"].includes(c.body.action as string)) {
        this.sql.exec("INSERT INTO renewal_usage VALUES (?, ?, 1, ?) ON CONFLICT(operation, signer) DO UPDATE SET count = count + 1, bytes = bytes + excluded.bytes", next.state.operationId, auth.deviceId, bytes(c.body));
      }
      if (c.body.action === "revoke") {
        const target = m.credentials.find((a) => a.deviceId === c.body.participantDeviceId)!;
        m.denied.push(target.verifier!); target.verifier = null; target.revoked = true;
        // A web's inbox slots go at once, as in `revoke` (ADR 0009, B3).
        if (target.role === "web") this.sql.exec("DELETE FROM slot WHERE device = ?", target.deviceId);
        else target.slotsExpireAt = Date.now() + V2_REVOKED_SLOTS_GRACE_MS;
        this.retireDeviceRecoveries(m, target.deviceId);
        new PinGuard(this.sql).delete(target.deviceId);
      }
      if (c.body.action === "capability") auth.commonFormat = 2;
      this.saveRenewal(next.state);
      for (const i of removed) {
        this.queueRelease(m.syncId, i);
        this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
        this.dropCheckpoints(i.id);
      }
      this.saveMeta(m);
    }, c.body.action === "revoke");
    if (removed.length > 0 || c.body.action === "revoke") await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
    if (c.body.action === "revoke") this.closeSockets(CLOSE_REVOKED, c.body.participantDeviceId as string);
    this.notify(m);
    // The durable queue, not a successful RPC, is the cancellation guarantee.
    // If delivery fails the accepted reservation is still recoverable by GET.
    await this.drainReleases();
    await this.drainRecoveryReleases();
    return response();
  }

  /** Which slots exist and the list version that last changed each one. */
  private manifest(): { personId: string; deviceId: string; version: number }[] {
    return this.sql
      .exec<{ personId: string; deviceId: string; version: number }>(
        "SELECT person AS personId, device AS deviceId, ver AS version FROM slot ORDER BY person, device",
      )
      .toArray();
  }

  /**
   * Slots the list may hold now: V2_MAX_SLOTS once every active phone announced
   * `slotCapacity` 2, otherwise the 1.0.5 cap. Webs run the deployed bundle and
   * revoked credentials no longer sync, so neither holds the list back.
   */
  private slotLimit(m: Meta): number {
    const legacy = m.credentials.some((a) => !a.revoked && (a.role ?? "device") === "device" && (a.slotCapacity ?? 1) < V2_SLOT_CAPACITY);
    return legacy ? V2_LEGACY_MAX_SLOTS : V2_MAX_SLOTS;
  }

  private slotKeys(): Set<string> {
    return new Set(this.manifest().map((s) => `${s.personId}/${s.deviceId}`));
  }

  private invites(): Invitation[] {
    const now = Date.now();
    return this.sql
      .exec<{ data: string }>("SELECT data FROM invite WHERE expires_at > ?", now)
      .toArray()
      .map((r) => JSON.parse(r.data) as Invitation);
  }

  private hasCheckpoints(): boolean {
    return this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'checkpoint'").toArray().length > 0;
  }

  /** Writes the checkpoint rows of invitation `id` (inside the approval transaction). */
  private saveCheckpoint(id: string, common: string, registry: string): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS checkpoint (invite TEXT NOT NULL, part TEXT NOT NULL, idx INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (invite, part, idx))");
    this.sql.exec("DELETE FROM checkpoint WHERE invite = ?", id);
    for (const [part, text] of [["common", common], ["registry", registry]] as const) {
      const chunks = Math.max(1, Math.ceil(text.length / CHUNK_CHARS));
      for (let n = 0; n < chunks; n++) {
        this.sql.exec("INSERT INTO checkpoint (invite, part, idx, data) VALUES (?, ?, ?, ?)", id, part, n, text.slice(n * CHUNK_CHARS, (n + 1) * CHUNK_CHARS));
      }
    }
  }

  private readCheckpoint(id: string, part: "common" | "registry"): string | null {
    if (!this.hasCheckpoints()) return null;
    const rows = this.sql.exec<{ data: string }>("SELECT data FROM checkpoint WHERE invite = ? AND part = ? ORDER BY idx", id, part).toArray();
    return rows.length === 0 ? null : rows.map((r) => r.data).join("");
  }

  /** Drops the checkpoint rows of `id`, or of every invitation that is gone (no `id`). */
  private dropCheckpoints(id?: string): void {
    if (!this.hasCheckpoints()) return;
    if (id === undefined) this.sql.exec("DELETE FROM checkpoint WHERE invite NOT IN (SELECT id FROM invite)");
    else this.sql.exec("DELETE FROM checkpoint WHERE invite = ?", id);
  }

  private saveInvite(i: Invitation): void {
    this.sql.exec(
      "INSERT INTO invite (id, expires_at, data) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET expires_at = excluded.expires_at, data = excluded.data",
      i.id,
      i.expiresAt,
      JSON.stringify(i),
    );
  }

  private nextAlarm(m: Meta): number {
    const row = this.sql.exec<{ next: number | null }>("SELECT MIN(expires_at) AS next FROM invite").one();
    const recoveryExpiry = this.recoveryStore().rows().filter((r) => r.state === "candidate" || r.state === "intention").reduce((next, r) => Math.min(next, r.expiresAt!), Number.MAX_SAFE_INTEGER);
    const recoveryPending = this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recovery_release'").toArray().length > 0 &&
      this.sql.exec("SELECT 1 FROM recovery_release WHERE action != 'pending' LIMIT 1").toArray().length > 0;
    const slotExpiry = m.credentials.reduce((next, c) => Math.min(next, c.revoked ? c.slotsExpireAt ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER), Number.MAX_SAFE_INTEGER);
    return Math.min(m.lastAccess + LIST_TTL_MS, m.inviteCopyExpiresAt ?? Number.MAX_SAFE_INTEGER, row.next ?? Number.MAX_SAFE_INTEGER, recoveryExpiry, slotExpiry, this.hasReleases() || recoveryPending ? Date.now() + WINDOW_MS : Number.MAX_SAFE_INTEGER);
  }

  /** Any authenticated activity before confirm cancels an exclusion. */
  private recordActivity(m: Meta, auth: Credential): boolean {
    const now = Date.now();
    for (const credential of m.credentials) credential.lastRequest = activityHour(credential.lastRequest ?? now);
    auth.lastRequest = activityHour(now);
    this.saveMeta(m, true);
    const observed = this.readRenewal();
    if (observed !== null) m.renewalStartedAt ??= now;
    const wasExcluded = observed !== null && Object.hasOwn(observed.exclusions, auth.deviceId);
    if (observed && wasExcluded && !(m.renewalActivityUsed ?? []).includes(auth.deviceId) && (observed.confirmation === null || observed.confirmedVersion !== m.version)) {
      if (!(m.renewalReturned ?? []).includes(auth.deviceId)) {
        m.renewalReturned = [...(m.renewalReturned ?? []), auth.deviceId];
        m.renewalActivityUsed = [...(m.renewalActivityUsed ?? []), auth.deviceId];
        m.version++;
        this.saveMeta(m);
        this.notify(m);
      }
    }
    this.saveMeta(m);
    return wasExcluded;
  }

  /** Refreshes `lastAccess` at most hourly and moves the alarm. */
  private async touch(m: Meta): Promise<void> {
    const now = Date.now();
    if (now - m.lastAccess < TOUCH_INTERVAL_MS && m.lastAccess === activityHour(m.lastAccess)) return;
    m.lastAccess = activityHour(now);
    this.saveMeta(m, true);
    await this.scheduleAlarm(this.nextAlarm(m));
  }

  // ---- access -----------------------------------------------------------------

  private active(m: Meta, verifier: string | null): Credential | null {
    if (verifier === null) return null;
    return m.credentials.find((a) => !a.revoked && a.verifier !== null && equal(a.verifier, verifier)) ?? null;
  }

  private denied(m: Meta, verifier: string | null): boolean {
    return verifier !== null && (m.denied.some((v) => equal(v, verifier)) || new RecoveryStore(this.sql).retired(verifier) !== undefined);
  }

  private replacedError(m: Meta, verifier: string | null): ApiResult | null {
    const retired = new RecoveryStore(this.sql).retired(verifier);
    if (!retired) return null;
    return err(403, m.credentials.find((a) => a.deviceId === retired.deviceId)?.revoked ? "revoked" : "credential_replaced");
  }

  /** Counts one request against `key`; false when the window is full. */
  private async hit(key: string, max: number, checkOnly = false): Promise<boolean> {
    const now = Date.now();
    let c = this.rate.get(key);
    if (!c || now - c.start >= WINDOW_MS) c = { start: now, count: 0 };
    this.rate.set(key, c);
    if (checkOnly) return c.count <= max;
    if (c.count >= max) return false;
    c.count++;
    return true;
  }

  private precondition(m: Meta, match: string | null): ApiResult | null {
    if (match === null) return err(428, "precondition_required", { ETag: etag(m.version) });
    // Only one exact strong validator: no `*`, no weak ETags, no lists.
    return match === etag(m.version) ? null : err(412, "precondition_failed", { ETag: etag(m.version) });
  }

  private versioned(m: Meta, status = 200): ApiResult {
    return { status, body: { version: m.version }, headers: { ETag: etag(m.version) } };
  }

  // ---- sockets ----------------------------------------------------------------

  private openSockets(): WebSocket[] {
    const time = (ws: WebSocket) => (ws.deserializeAttachment() as { t?: number } | null)?.t ?? 0;
    return this.ctx
      .getWebSockets()
      .filter((ws) => ws.readyState === WebSocket.READY_STATE_OPEN)
      .sort((a, b) => time(a) - time(b));
  }

  private closeSockets(code: number, device?: string): void {
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as { device?: string; deviceId?: string } | null;
      if (device !== undefined && (attachment?.deviceId ?? attachment?.device) !== device) continue;
      try {
        ws.close(code, code === CLOSE_REPLACED ? "credential_replaced" : code === CLOSE_REVOKED ? "revoked" : "gone");
      } catch {
        // Already closed.
      }
    }
  }

  private socketAuthorized(ws: WebSocket, m: Meta): boolean {
    const a = ws.deserializeAttachment() as { deviceId?: string; credentialVerifier?: string } | null;
    const auth = a && key32(a.credentialVerifier) ? this.active(m, a.credentialVerifier) : null;
    if (auth && auth.deviceId === a?.deviceId) return true;
    const retired = key32(a?.credentialVerifier) ? this.recoveryStore().retired(a.credentialVerifier) : undefined;
    const replaced = retired !== undefined && retired.deviceId === a?.deviceId;
    const revoked = key32(a?.credentialVerifier) && (replaced || m.denied.some((v) => equal(v, a.credentialVerifier!))) && m.credentials.find((c) => c.deviceId === a?.deviceId)?.revoked;
    try { ws.close(revoked ? CLOSE_REVOKED : replaced ? CLOSE_REPLACED : CLOSE_POLICY, revoked ? "revoked" : replaced ? "credential_replaced" : "unauthorized"); } catch { /* closed */ }
    return false;
  }

  private notify(m: Meta): void {
    const message = JSON.stringify({ type: "version", version: m.version });
    for (const ws of this.openSockets()) {
      if (!this.socketAuthorized(ws, m)) continue;
      try {
        ws.send(message);
      } catch {
        // A dead socket is cleaned up by the runtime.
      }
    }
  }

  // ---- API --------------------------------------------------------------------

  async handle(c: V2Call): Promise<ApiResult> {
    return this.ctx.blockConcurrencyWhile(() => this.withLocalRequest(c.localRequest === true, async () => {
      try {
        // The Worker has already buffered version-zero PUTs. Keep the same
        // authorization and rate accounting if the destination already exists.
        if (c.route.resource === "list" && c.method === "PUT" && c.match === etag(0) && !c.bodyAuthorized) {
          const rejected = await this.authorize(c);
          if (rejected) return rejected;
          c = { ...c, bodyAuthorized: true };
        }
        return await this.withLedger(() => this.locked(c));
      }
      catch (e) {
        if (e instanceof RowsLimited) return limited(rowRetryAfter());
        if (e instanceof ListTooLarge) return err(413, "too_large");
        throw e;
      } finally {
        try { await this.settleRows(); }
        finally { this.rowCall = undefined; this.budget.rowContext = undefined; }
      }
    }));
  }

  /** Preflight and commit take short independent locks. No body I/O holds one. */
  async handleBody(c: V2Call, reader: RpcStub<AuthenticatedBody>, max: number): Promise<ApiResult> {
    const credential = c.verifier ?? c.route.deviceId ?? c.route.inviteId ?? c.route.recoveryId ?? "public";
    let reading = false;
    try {
      const rejected = await this.ctx.blockConcurrencyWhile(() => this.withLocalRequest(c.localRequest === true, async () => {
        const rejected = await this.authorize(c);
        if (rejected) return rejected;
        const total = [...this.bodyReads.values()].reduce((a, b) => a + b, 0);
        if (total >= 4 || (this.bodyReads.get(credential) ?? 0) >= 2) return limited(1);
        this.bodyReads.set(credential, (this.bodyReads.get(credential) ?? 0) + 1);
        reading = true;
        return null;
      }));
      if (rejected) return rejected;
      const request = await reader.open();
      let parsed: Awaited<ReturnType<typeof readJsonObject>>;
      try { parsed = await readJsonObject(request, max, V2_BODY_READ_DEADLINE_MS); }
      finally { request[Symbol.dispose](); }
      if (!parsed.ok) return c.route.recoveryId !== undefined || c.route.resource === "recoveries"
        ? err(parsed.result.status === 408 ? 408 : parsed.result.status === 413 ? 413 : 400, parsed.result.status === 413 ? "recovery_too_large" : "invalid_recovery") : parsed.result;
      if (c.route.recoveryId !== undefined || c.route.resource === "recoveries") {
        const kind = c.route.resource === "recoveryClaim" ? "claim" : c.route.resource === "recoveryRotation" ? "prepare" : c.route.resource === "recoveryCommit" ? "commit" : "put";
        if (!recoveryShape(kind, parsed.value)) return err(400, "invalid_recovery");
      }
      return await this.handle({ ...c, body: parsed.value, bodyAuthorized: true });
    } finally {
      if (reading) {
        const left = this.bodyReads.get(credential)! - 1;
        if (left) this.bodyReads.set(credential, left); else this.bodyReads.delete(credential);
      }
      reader[Symbol.dispose]();
    }
  }

  private async rowsError(m: Meta, c: V2Call): Promise<ApiResult | null> {
    const day = Math.floor(Date.now() / 86400000);
    if (this.rowsExempt(c) || m.rowBudget?.day !== day || m.rowBudget.written < V2_LIST_ROWS_PER_DAY) return null;
    // Admission remains closed, but a capped list must still pay its old debt.
    const previous = this.budget.rowContext;
    this.restoreRowContext(m.rowReports);
    try { await this.settleRows(); }
    finally { this.budget.rowContext = previous; }
    return limited(rowRetryAfter());
  }

  private rowsExempt(c: V2Call): boolean {
    return c.method === "GET" || c.method === "DELETE" || c.route.resource === "revoke" || c.route.resource === "withdraw" ||
      (c.route.resource === "renewal" && c.body.action === "revoke");
  }
  private rowCounter(key: string, amount = 0): Promise<RowStatus> {
    if (key === "global") return this.ledger().rows(amount);
    const ns = euNamespace(this.env.LIMITER_V2, this.env, this.localRequest);
    return ns.get(ns.idFromName(key)).rows(key.startsWith("v2:rows48:") ? V2_CLIENT_ROWS_PER_DAY_48 : V2_CLIENT_ROWS_PER_DAY, amount);
  }
  private restoreRowContext(reports = this.budget.pendingReports()): void {
    // Maintenance and exempt writes are charged only to the list itself; reportRows()
    // still walks reports.keys, so rows already pending for a client are reported.
    if (!this.budget.rowContext && reports) {
      this.budget.rowContext = { keys: [], reports: structuredClone(reports) };
    }
  }
  /** Reporting after a local commit cannot change its result or skip its
   * remaining application steps. Admission uses reportRows() directly. */
  private async settleRows(force?: string): Promise<void> {
    if (isRetired(this.stored())) { this.rowRetryAt = undefined; this.budget.rowContext = undefined; return; }
    const expiry = this.budget.attemptsExpireAt();
    if (this.stored() === null && expiry !== undefined) {
      const current = await this.ctx.storage.getAlarm();
      if (current === null || current > expiry) await this.scheduleAlarm(expiry);
    }
    try {
      if (this.rowRetryAt !== undefined && this.rowRetryAt > Date.now()) {
        await this.scheduleAlarm(this.rowRetryAt);
        return;
      }
      const retry = this.rowRetryAt;
      await this.reportRows(retry !== undefined ? "*" : force);
      this.rowRetryAt = undefined;
      if (retry !== undefined) {
        const m = this.stored();
        const next = m && !isRetired(m) ? this.nextAlarm(m) : this.budget.attemptsExpireAt();
        if (next !== undefined) await this.scheduleAlarm(next);
      }
    } catch {
      this.rowRetryAt = Date.now() + V2_ROW_STATUS_MS;
      try { await this.scheduleAlarm(this.rowRetryAt); }
      catch { /* Durable pending rows remain available on the next wake. */ }
    }
  }
  private async reportRows(force?: string, evict = false): Promise<void> {
    const context = this.budget.rowContext;
    if (!context) return;
    const now = Date.now(), day = Math.floor(now / 86400000);
    let changed = false;
    try {
      const entries = Object.entries(context.reports.keys).sort(([a], [b]) => Number(b === force) - Number(a === force));
      for (const [key, entry] of entries) {
        const due = force === "*" || key === force || entry.pending >= V2_ROW_REPORT_BLOCK || (!entry.exhausted && entry.pending >= entry.remaining) || entry.day !== day || now - entry.reportedAt >= V2_ROW_REPORT_MS;
        if (entry.pending && due) {
          const status = await this.rowCounter(key, entry.pending);
          Object.assign(entry, status, { pending: 0, checkedAt: now, reportedAt: now });
          if (status.exhausted) this.exhaustedUntil.set(key, (day + 1) * 86400000);
          changed = true;
        }
        if (evict && key === force) delete context.reports.keys[key];
      }
    } finally {
      context.reports.day = day;
      const m = this.stored();
      if (changed && !isRetired(m)) {
        // Acknowledgements are batched into one state write per report round;
        // that write is charged only to the list budget.
        try {
          if (m) await this.commit(() => this.saveMeta(m), true, false, true);
          else this.budget.acknowledgeReports();
        }
        catch (e) {
          // Only a durable acknowledgement may remove pending rows.
          this.budget.rowContext = undefined;
          this.restoreRowContext();
          throw e;
        }
      }
    }
  }
  private async admitRows(c: V2Call): Promise<void> {
    try { await this.checkRowAdmission(c); }
    catch (e) {
      if (e instanceof RowsLimited) throw e;
      // Counter availability is required before admitting any new mutation.
      throw new RowsLimited();
    }
  }
  private async checkRowAdmission(c: V2Call): Promise<void> {
    if (this.rowsExempt(c)) return;
    if (this.rowCall === c) return;
    const day = Math.floor(Date.now() / 86400000), wide = c.client48 ?? clientKey48(c.client);
    for (const [key, until] of this.exhaustedUntil) if (until <= Date.now()) this.exhaustedUntil.delete(key);
    // Check wider ceilings first so an exhausted account or /48 cannot cause
    // fresh narrow-counter writes on every rejected request.
    const keys = ["global", ...(wide === c.client ? [] : [`v2:rows48:${wide}`]), `v2:rows:${c.client}`];
    const saved = this.budget.pendingReports();
    // Pending rows survive midnight and are charged to each counter's current day.
    const reports: RowReports = saved ? structuredClone(saved) : { day, keys: {} };
    this.budget.rowContext = { keys, reports };
    if (Object.values(reports.keys).some((entry) => entry.day !== day)) await this.reportRows();
    for (const key of keys) {
      let entry = this.budget.rowContext.reports.keys[key];
      if ((this.exhaustedUntil.get(key) ?? 0) > Date.now() || (entry?.day === day && entry.exhausted)) {
        if (entry?.pending) await this.reportRows();
        throw new RowsLimited();
      }
      if (!entry) {
        const status = await this.rowCounter(key);
        entry = { ...status, pending: 0, checkedAt: Date.now(), reportedAt: Date.now(), usedAt: Date.now() };
        this.budget.rowContext.reports.keys[key] = entry;
        if (status.exhausted) {
          this.exhaustedUntil.set(key, (day + 1) * 86400000);
          throw new RowsLimited();
        }
        if (Object.keys(this.budget.rowContext.reports.keys).length > V2_ROW_REPORT_KEYS) {
          const oldest = Object.keys(this.budget.rowContext.reports.keys).filter((k) => !keys.includes(k)).sort((a, b) => this.budget.rowContext!.reports.keys[a]!.usedAt - this.budget.rowContext!.reports.keys[b]!.usedAt)[0]!;
          try { await this.reportRows(oldest, true); }
          catch (e) { delete this.budget.rowContext.reports.keys[key]; throw e; }
        }
      } else if (entry.day !== day || Date.now() - entry.checkedAt > V2_ROW_STATUS_MS || entry.pending >= V2_ROW_REPORT_BLOCK || Date.now() - entry.reportedAt > V2_ROW_REPORT_MS || entry.pending >= entry.remaining) {
        if (entry.pending) {
          await this.reportRows(key);
          entry = this.budget.rowContext.reports.keys[key]!;
        }
        else Object.assign(entry, await this.rowCounter(key), { checkedAt: Date.now() });
      }
      if (entry.exhausted) {
        this.exhaustedUntil.set(key, (day + 1) * 86400000);
        throw new RowsLimited();
      }
    }
    this.rowCall = c;
  }

  private async authorize(c: V2Call): Promise<ApiResult | null> {
    const m = this.stored();
    if (isRetired(m)) return this.retiredAnswer(c);
    if (!m) {
      if (c.route.resource !== "list" || c.method !== "PUT") return NOT_FOUND;
      if (c.match === null) return err(428, "precondition_required");
      return c.match === etag(0) ? null : err(412, "precondition_failed", { ETag: etag(0) });
    }
    const replaced = this.replacedError(m, c.verifier);
    if (replaced) return replaced;
    // Public invitation/recovery endpoints authenticate their scoped capability
    // in handle; they still stream outside the lock and have the same deadline.
    if (c.route.syncId === undefined) return this.rowsError(m, c);
    const auth = this.active(m, c.verifier);
    if (!auth) return UNAUTHORIZED;
    if (auth.role === "web" && !webAllowed(auth, c)) return err(403, "forbidden_role");
    if (auth.role === "web" && new PinGuard(this.sql).requiresRotation(auth.deviceId) && c.route.resource !== "guard") return err(409, "guard_rotation_required");
    const rows = await this.rowsError(m, c);
    if (rows) return rows;
    if (!await this.hit(`r:${auth.deviceId}`, V2_CREDENTIAL_REQUESTS) ||
        !await this.hit(`w:${auth.deviceId}`, V2_CREDENTIAL_WRITES)) return limited();
    return null;
  }

  private async locked(c: V2Call): Promise<ApiResult> {
    const recovery = c.route.resource === "recoveries" || c.route.recoveryId !== undefined;
    // Public recovery auth has its own 404/receipt precedence. All other ways
    // of presenting a retired Bearer, including public invite and guard/open,
    // hit this fence before role, CAS, disabled renewal or invitation checks.
    if (!(recovery && c.route.syncId === undefined)) {
      const prior = this.stored();
      if (prior && !isRetired(prior)) {
        const replaced = this.replacedError(prior, c.verifier);
        if (replaced) return replaced;
      }
    }
    // Also guard internal calls, before live(), activity, counters or invitations.
    if (c.route.resource === "renewal" && c.method === "PUT" && c.body.action === "reserve" && (c.renewalDisabled === true || this.env.RENEWAL_ENABLED !== "true")) {
      return err(409, "renewal_disabled");
    }
    const s = await this.live();
    if (!isRetired(s)) { this.restoreRowContext(); await this.settleRows(); }
    if (c.route.resource === "guard" && c.route.action === "open") {
      if (s && !isRetired(s)) {
        const rows = await this.rowsError(s, c);
        if (rows) return rows;
      }
      return new PinGuard(this.sql).handle(c.route.deviceId!, "open", c.body, s !== null && !isRetired(s), () => this.admitRows(c));
    }
    if (s === null) return this.create(c);
    if (isRetired(s)) return this.retiredAnswer(c);
    const m = s;
    const rowsError = await this.rowsError(m, c);
    if (rowsError) return rowsError;
    if (recovery) {
      if (!this.rowsExempt(c)) await this.admitRows(c);
      await this.expireRecoveries();
      return this.recovery(m, c);
    }
    // Public invitation routes: authority is the live state of this list.
    if (c.route.syncId === undefined) {
      if (!this.rowsExempt(c)) await this.admitRows(c);
      const authenticated = this.active(m, c.verifier);
      if (authenticated) this.recordActivity(m, authenticated);
      return this.publicInvite(m, c);
    }

    const auth = this.active(m, c.verifier);
    if (!auth) return UNAUTHORIZED;
    await this.admitRows(c);
    const controlRow = this.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = 'renewal'").toArray()[0];
    if (controlRow && !key32((JSON.parse(controlRow.data) as Record<string, unknown>).head)) return err(409, "renewal_upgrade_required");
    const wasExcluded = this.recordActivity(m, auth);
    if (wasExcluded && c.route.resource === "renewal" && c.body.action === "revise") return err(403, "renewal_excluded");
    if (auth.role === "web" && !webAllowed(auth, c)) return err(403, "forbidden_role");
    // Guard cancellation is recovery bookkeeping only: it never lifts this gate.
    if (auth.role === "web" && new PinGuard(this.sql).requiresRotation(auth.deviceId) && c.route.resource !== "guard") return err(409, "guard_rotation_required");
    const control = c.route.resource === "renewal";
    if (!await this.hit(`${control ? "renewal-r" : "r"}:${auth.deviceId}`, control ? V2_RENEWAL_REQUESTS : V2_CREDENTIAL_REQUESTS, c.bodyAuthorized === true)) return limited();
    if (control && c.method !== "GET" && !await this.hit(`renewal-w:${auth.deviceId}`, V2_RENEWAL_WRITES)) return limited();
    if (c.method !== "GET" && c.route.resource !== "guard" && !control) {
      if (!await this.hit(`w:${auth.deviceId}`, V2_CREDENTIAL_WRITES, c.bodyAuthorized === true)) return limited();
      // Another writer spending the list budget must never block a revocation.
      if (c.route.resource !== "revoke" && !await this.hit("list", MAX_WRITES_PER_WINDOW)) return limited();
    }
    await this.touch(m);

    const r = c.route;
    const renewal = this.readRenewal();
    if (renewal !== null && renewal.abortion === null) {
      if ((r.resource === "invites" && c.method === "POST") || r.resource === "approve") return err(409, "renewal_in_progress");
      if (renewal.barrierVersion !== null && c.method === "PUT" && (r.resource === "list" || r.resource === "common" || r.resource === "slot")) return err(409, "renewal_frozen");
    }
    switch (r.resource) {
      case "renewal":
        return this.renewal(m, auth, c, renewal);
      case "list":
        if (c.method === "GET") return this.read(m, c);
        if (c.method === "PUT") return this.put(m, auth, c);
        return this.remove(m, c, auth);
      case "slot":
        if (c.method === "PUT") return this.putWebSlot(m, auth, c);
        return this.readSlot(m, c);
      case "common":
        return this.putCommon(m, c);
      case "capability":
        return this.capability(m, auth, c);
      case "guard":
        if (r.action !== "resume" && (auth.role !== "web" || auth.deviceId !== r.deviceId)) return err(403, "forbidden_role");
        let guarded!: ApiResult;
        await this.commit(() => { guarded = new PinGuard(this.sql).mutate(r.deviceId!, r.action, c.body); });
        return guarded;
      case "revoke":
        return this.revoke(m, c);
      default:
        return this.invitation(m, auth, c);
    }
  }

  /** One-off operator RPC. No activity, authorization, version bump or notification. */
  async applyRetention(): Promise<void> {
    await this.ctx.blockConcurrencyWhile(() => this.withLedger(async () => {
      const m = await this.retained();
      if (m === null || isRetired(m)) return;
      const next = this.nextAlarm(m);
      const current = await this.ctx.storage.getAlarm();
      // An already earlier alarm may be retrying a release. Never postpone it.
      if (current === null || current > next) await this.scheduleAlarm(next);
    }));
  }

  /** Read-only operator preview, without retention, activity or ledger mutations. */
  previewPurge(criteria: PurgeCriteria): PurgeCandidate | null {
    const m = this.stored();
    const credential = m && !isRetired(m) && m.credentials.length === 1 ? m.credentials[0] : undefined;
    if (!m || isRetired(m) || !credential || credential.revoked || credential.verifier === null) return null;
    if (this.readRenewal() !== null || this.hasReleases()) return null;
    const now = Date.now();
    const lastActivity = Math.max(m.lastAccess, credential.lastRequest ?? 0);
    if (!Number.isSafeInteger(lastActivity) || lastActivity < 0 || lastActivity > criteria.inactiveBefore ||
        now - m.lastAccess >= LIST_TTL_MS || now >= (m.inviteCopyExpiresAt ?? Infinity) ||
        this.bodyReads.size > 0 || this.openSockets().length > 0) return null;

    // Old credential timestamps may have been synthesized for capacity
    // accounting. The fixed invitation cap records the real creation time.
    if (m.createdAt === undefined && criteria.includeLegacy !== true) return null;
    const createdAt = m.createdAt ?? (m.inviteCopyMaxExpiresAt === undefined ? null : m.inviteCopyMaxExpiresAt - 7 * INVITE_TTL_MS);
    if (createdAt === null) {
      // For undated lists the full possible range must fit the window.
      if (criteria.createdFrom !== 0 || lastActivity >= criteria.createdBefore) return null;
    } else if (!Number.isSafeInteger(createdAt) || createdAt < criteria.createdFrom ||
               createdAt >= criteria.createdBefore || createdAt > lastActivity) return null;
    const hasRecovery = this.recoveryStore().rows().some((row) => row.state !== "retired");
    if (hasRecovery) return null;
    const storedBytes = m.storedBytes;
    if (storedBytes === undefined || !Number.isSafeInteger(storedBytes) || storedBytes < 0) return null;
    const pendingInvites = this.invites().filter((invite) => !invite.package).length;
    return { createdAt, lastActivity, version: m.version, storedBytes, hasRecovery, pendingInvites };
  }

  /** Only retire a reviewed candidate that still matches under the list lock. */
  async purgeInactive(criteria: PurgeCriteria, expected: PurgeCandidate): Promise<boolean> {
    return this.ctx.blockConcurrencyWhile(async () => {
      const current = this.previewPurge(criteria);
      if (!current || current.createdAt !== expected.createdAt ||
          current.lastActivity !== expected.lastActivity || current.version !== expected.version ||
          current.storedBytes !== expected.storedBytes || current.hasRecovery !== expected.hasRecovery ||
          current.pendingInvites !== expected.pendingInvites) return false;
      return this.withLedger(async () => {
        if (!await this.retire()) throw new Error("Retirement cleanup pending");
        return true;
      });
    });
  }

  /** What is stored, after retiring a list that has gone 400 days without access. */
  private async retained(): Promise<Stored> {
    const s = this.stored();
    if (s === null && (this.budget.attemptsExpireAt() ?? Infinity) <= Date.now()) {
      await this.ctx.storage.deleteAll();
      await this.ctx.storage.deleteAlarm();
      this.budget = new ListStorageBudget(this.ctx.storage);
      this.rowRetryAt = undefined;
      return null;
    }
    if (isRetired(s) && this.rawState() === MARKER_TEXT) {
      this.rowRetryAt = undefined;
      this.budget.rowContext = undefined;
      // Remove accounting left beside bare markers by older versions.
      this.budget.transaction(() => this.sql.exec("DROP TABLE IF EXISTS row_attempts"), true);
      // Old bare markers acquire a deadline on their first wake after upgrade.
      const previous = await this.ctx.storage.get<number>(RETIRED_UNTIL);
      const until = previous ?? Date.now() + LIST_TTL_MS;
      if (Date.now() >= until) {
        await this.ctx.storage.deleteAll();
        this.budget = new ListStorageBudget(this.ctx.storage);
        await this.ctx.storage.deleteAlarm();
        this.rate.clear();
        return null;
      }
      if (previous === undefined) await this.ctx.storage.put(RETIRED_UNTIL, until);
      if (await this.ctx.storage.getAlarm() !== until) await this.scheduleAlarm(until);
      return s;
    }
    // A legacy or malformed row is retired for good, wiping whatever it left.
    if (isRetired(s) && this.rawState() !== MARKER_TEXT) {
      await this.retire();
      return RETIRED;
    }
    if (s !== null && !isRetired(s) && (Date.now() - s.lastAccess >= LIST_TTL_MS || Date.now() >= (s.inviteCopyExpiresAt ?? Infinity))) {
      await this.retire();
      return RETIRED;
    }
    if (s !== null && !isRetired(s)) {
      if (s.credentials.some((c) => c.createdAt === undefined)) {
        for (const c of s.credentials) c.createdAt ??= Date.now() - V2_CREDENTIAL_CAP_AGE_MS;
        this.saveMeta(s, true);
      }
      if (s.storedBytes === undefined) this.saveMeta(s, true);
      // Older versions never dated service revocations. Their remaining slots
      // receive one fixed grace on first wake; reads cannot renew it.
      const legacy = s.credentials.filter((c) => c.revoked && c.slotsExpireAt === undefined &&
        this.sql.exec("SELECT 1 FROM slot WHERE device = ? LIMIT 1", c.deviceId).toArray().length > 0);
      if (legacy.length > 0) {
        for (const credential of legacy) credential.slotsExpireAt = Date.now() + V2_REVOKED_SLOTS_GRACE_MS;
        await this.scheduleAlarm(this.nextAlarm(s));
        this.saveMeta(s, true);
      }
    }
    return s;
  }

  private async live(): Promise<Stored> {
    const s = await this.retained();
    if (s !== null && !isRetired(s)) {
      await this.drainReleases();
      await this.drainRecoveryReleases();
    }
    return s;
  }

  // ---- personal recovery (ADR 0007) -------------------------------------------

  private recoveryStore(): RecoveryStore { return new RecoveryStore(this.sql); }

  private recoveryPrecondition(row: RecoveryRow | undefined, match: string | null): ApiResult | null {
    const headers = { ETag: recoveryEtag(row?.revision ?? 0) };
    if (match === null) return err(428, "precondition_required", headers);
    return recoveryCas(match) === (row?.revision ?? 0) ? null : err(412, "precondition_failed", headers);
  }

  /** Queue lives outside the content tables so list retirement can finish even
   * when a locator RPC fails. A delayed confirm can never supersede retirement. */
  private queueRecoveryLocator(sid: string, row: RecoveryRow, pending = false): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS recovery_release (rid TEXT PRIMARY KEY, sid TEXT NOT NULL, token TEXT NOT NULL, action TEXT NOT NULL) WITHOUT ROWID");
    this.sql.exec("INSERT INTO recovery_release VALUES (?, ?, ?, ?) ON CONFLICT(rid) DO UPDATE SET action = CASE WHEN action = 'retire' THEN action ELSE excluded.action END", row.rid, sid, row.reservationId, pending ? "pending" : row.state === "retired" ? "retire" : "confirm");
  }

  private async drainRecoveryReleases(): Promise<boolean> {
    if (!this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'recovery_release'").toArray().length) return true;
    let failed = false;
    for (const row of this.sql.exec<{ rid: string; sid: string; token: string; action: string }>("SELECT * FROM recovery_release").toArray()) {
      // An intention owns this space until reserve completes or expiry retires
      // it. Never confirm discovery before the authoritative blob is active.
      if (row.action === "pending") continue;
      try {
        const ns = euNamespace(this.env.RECOVERIES_V2, this.env, this.localRequest);
        const locator = ns.get(ns.idFromName(row.rid));
        if (row.action === "retire") await locator.retire(row.sid, row.token);
        else if (!await locator.confirm(row.sid, row.token)) { failed = true; continue; }
        await this.commit(() => { this.sql.exec("DELETE FROM recovery_release WHERE rid = ?", row.rid); }, true);
      } catch { failed = true; }
    }
    if (failed) await this.scheduleAlarm(Date.now() + WINDOW_MS);
    else if (!this.sql.exec("SELECT 1 FROM recovery_release LIMIT 1").toArray().length) await this.commit(() => { this.sql.exec("DROP TABLE recovery_release"); }, true);
    return !failed;
  }

  private closeRecovery(m: Meta, row: RecoveryRow, terminal?: RecoveryRow["terminal"]): void {
    this.recoveryStore().close(row, terminal);
    this.queueRecoveryLocator(m.syncId, row);
  }

  private cancelRecoveryCandidate(m: Meta, parent: string): void {
    for (const candidate of this.recoveryStore().rows()) {
      if (candidate.parent === parent && candidate.state !== "retired") this.closeRecovery(m, candidate, "cancelled");
    }
  }

  private retireDeviceRecoveries(m: Meta, deviceId: string): void {
    for (const row of this.recoveryStore().rows()) if (row.deviceId === deviceId && row.state !== "retired") this.closeRecovery(m, row, row.parent ? "cancelled" : undefined);
  }

  private async expireRecoveries(): Promise<void> {
    const s = this.stored();
    if (!s || isRetired(s)) return;
    let expired = false;
    await this.commit(() => {
      for (const row of this.recoveryStore().rows()) if ((row.state === "intention" || row.state === "candidate") && row.expiresAt! <= Date.now()) {
        this.closeRecovery(s, row, row.parent ? "expired" : undefined);
        expired = true;
      }
    }, true);
    if (expired) await this.scheduleAlarm(this.nextAlarm(s));
  }

  /** Called by the locator outside its own lock. Cancellation and blob commit
   * are serialized here, so a late token cannot commit after this acknowledgement. */
  async recoveryReconcile(token: string): Promise<"linked" | "reserved" | "retired"> {
    return this.ctx.blockConcurrencyWhile(() => this.withLedger(async () => {
      const m = await this.live();
      if (!m || isRetired(m)) return "retired";
      await this.expireRecoveries();
      const row = this.recoveryStore().rows().find((r) => r.reservationId === token);
      if (!row || row.state === "retired") return "retired";
      return row.state === "intention" ? "reserved" : "linked";
    }));
  }

  private async finishRecoveryIntention(m: Meta, row: RecoveryRow, capsule: string): Promise<ApiResult> {
    // Also upgrades interrupted intentions from before capacity was reserved.
    // The unpublished row, blob and pending queue cover the entire final commit.
    await this.commit(() => {
      row.published = false;
      if (this.recoveryStore().blob(row.rid) !== capsule) this.recoveryStore().writeBlob(row.rid, capsule);
      this.recoveryStore().save(row);
      this.queueRecoveryLocator(m.syncId, row, true);
    });
    await this.scheduleAlarm(this.nextAlarm(m));
    const ns = euNamespace(this.env.RECOVERIES_V2, this.env, this.localRequest);
    let reserved: boolean;
    try { reserved = await ns.get(ns.idFromName(row.rid)).reserve(m.syncId, row.reservationId); }
    catch { return err(503, "recovery_unavailable", { "Retry-After": "60" }); }
    if (!reserved) {
      await this.commit(() => {
        this.recoveryStore().discardUnreserved(row);
        this.sql.exec("DELETE FROM recovery_blob WHERE rid = ?", row.rid);
        this.sql.exec("DELETE FROM recovery_release WHERE rid = ?", row.rid);
      }, true);
      return err(409, "recovery_retired");
    }
    const publishedMeta = { ...m, lastAccess: activityHour(Date.now()) };
    delete publishedMeta.inviteCopyExpiresAt;
    delete publishedMeta.inviteCopyMaxExpiresAt;
    try {
      await this.commit(() => {
        const published: RecoveryRow = { ...row, state: row.parent ? "candidate" : "active", published: true };
        if (!published.parent) delete published.expiresAt;
        this.recoveryStore().save(published);
        this.queueRecoveryLocator(m.syncId, published);
        this.saveMeta(publishedMeta);
      });
    } catch (e) {
      // A successful reserve (including a lost response) must always have a
      // durable terminal path, even if the final local commit fails.
      // Reload the unpublished intention: SQLite rollback cannot undo JS mutations.
      await this.commit(() => {
        const intention = this.recoveryStore().get(row.rid)!;
        this.closeRecovery(m, intention, intention.parent ? "cancelled" : undefined);
      }, true);
      throw e;
    }
    await this.drainRecoveryReleases();
    await this.scheduleAlarm(this.nextAlarm(publishedMeta));
    return row.initial.response;
  }

  private recoveryResponse(row: RecoveryRow, status = 200, op?: string): ApiResult {
    return { status, body: { v: 2, recoveryId: row.rid, revision: row.revision, ...(op ? { operationId: op } : {}) }, headers: { ETag: recoveryEtag(row.revision) } };
  }

  private async recovery(m: Meta, c: V2Call): Promise<ApiResult> {
    const store = this.recoveryStore(), r = c.route, b = c.body;
    const row = r.recoveryId ? store.get(r.recoveryId) : undefined;
    let auth: Credential | null;
    if (r.syncId === undefined) {
      auth = row ? m.credentials.find((a) => a.deviceId === row.deviceId && !a.revoked && a.role !== "web") ?? null : null;
      if (!row || (row.state !== "active" && row.state !== "candidate") || !auth || !c.recoveryReadVerifier || !equal(row.readVerifier, c.recoveryReadVerifier)) return NOT_FOUND;
      if (c.method === "GET") return { ...this.recoveryResponse(row), body: { v: 2, recoveryId: row.rid, revision: row.revision, capsule: store.blob(row.rid) } };
      if (row.state === "candidate") return err(409, "recovery_not_active");
      if (!await this.hit(`r:${auth.deviceId}`, V2_CREDENTIAL_REQUESTS)) return limited();
      if (row.claim && c.verifier === row.claim.verifier && b.operationId === row.claim.operationId) {
        const fingerprint = await recoveryFingerprint(b, recoveryCas(c.match));
        return fingerprint === row.claim.fingerprint ? row.claim.response : err(409, "recovery_operation_conflict");
      }
      const replaced = this.replacedError(m, c.verifier);
      if (replaced) return replaced;
      if (c.verifier === null || auth.verifier === null || !equal(auth.verifier, c.verifier)) return UNAUTHORIZED;
      if (row.claim?.operationId === b.operationId) return err(409, "recovery_operation_conflict");
      if (!operationId(b.operationId) || !key32(b.newCredentialVerifier)) return err(400, "invalid_recovery");
      const cas = this.recoveryPrecondition(row, c.match);
      if (cas) return cas;
      if (row.revision === Number.MAX_SAFE_INTEGER || m.version === Number.MAX_SAFE_INTEGER) return err(409, "recovery_limit");
      const capsuleError = validateCapsule(b.capsule, row.rid, row.revision + 1);
      if (capsuleError) return capsuleError;
      const fingerprint = await recoveryFingerprint(b, recoveryCas(c.match));
      const fresh = b.newCredentialVerifier;
      if (this.denied(m, fresh) || m.credentials.some((a) => a.verifier === fresh) || this.invites().some((i) => i.verifier === fresh)) return err(409, "recovery_credential_conflict");
      const updated = { ...row, revision: row.revision + 1, size: Math.floor((b.capsule as string).length * 3 / 4) };
      const response = this.recoveryResponse(updated, 200, b.operationId);
      response.body!.deviceId = auth.deviceId;
      updated.claim = { operationId: b.operationId, fingerprint, verifier: c.verifier, response };
      const error = store.history(store.rows().map((a) => a.rid === row.rid ? updated : a), true) ?? store.quotaError(true, auth.deviceId, true);
      if (error) return error;
      const removed = this.invites().filter((i) => i.owner === auth!.deviceId || i.guest === auth!.deviceId);
      await this.commit(() => {
        store.retireVerifier(c.verifier!, auth!.deviceId);
        auth!.verifier = fresh;
        // The receiving install may be an older app: it announces again (1.0.6).
        delete auth!.slotCapacity;
        auth!.lastRequest = activityHour(Date.now());
        m.version++;
        m.lastAccess = activityHour(Date.now());
        this.cancelRecoveryCandidate(m, row.rid);
        store.writeBlob(row.rid, b.capsule as string);
        store.save(updated);
        for (const i of removed) {
          this.queueRelease(m.syncId, i);
          this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
          this.dropCheckpoints(i.id);
        }
        store.charge(true, auth!.deviceId, true);
        this.saveMeta(m);
      });
      await this.scheduleAlarm(this.nextAlarm(m));
      // The committed credential fence protects notify even if the process dies
      // here, before explicit close (including hibernated sockets).
      this.closeSockets(CLOSE_REPLACED, auth.deviceId);
      this.notify(m);
      await this.drainReleases();
      await this.drainRecoveryReleases();
      await this.scheduleAlarm(this.nextAlarm(m));
      return response;
    }

    auth = this.active(m, c.verifier);
    if (!auth) return this.denied(m, c.verifier) ? err(403, "revoked") : UNAUTHORIZED;
    if (auth.role === "web") return err(403, "mobile_required");
    if (!await this.hit(`r:${auth.deviceId}`, V2_CREDENTIAL_REQUESTS)) return limited();
    if (r.resource === "recoveries") {
      const rows = store.rows();
      return { status: 200, body: { v: 2, recoveries: rows.filter((a) => a.state === "active").map((a) => ({ deviceId: a.deviceId, recoveryId: a.rid, revision: a.revision, state: rows.some((other) => other.parent === a.rid && (other.state === "candidate" || other.state === "intention")) ? "rotationPending" : "active" })) } };
    }
    const expected = recoveryCas(c.match);
    if (c.method === "DELETE") {
      if (!row) return NOT_FOUND;
      if (row.deletion?.deviceId === auth.deviceId && row.deletion.expectedRevision === expected) return row.deletion.response;
      if (row.state === "retired") return row.deletion?.deviceId === auth.deviceId ? err(c.match === null ? 428 : 412, c.match === null ? "precondition_required" : "precondition_failed") : NOT_FOUND;
      if (row.state !== "active") return NOT_FOUND;
      const error = this.recoveryPrecondition(row, c.match) ?? store.quotaError(false, auth.deviceId);
      if (error) return error;
      await this.scheduleAlarm(Date.now() + WINDOW_MS);
      const response: ApiResult = { status: 204 };
      await this.commit(() => {
        row.deletion = { verifier: c.verifier!, deviceId: auth!.deviceId, expectedRevision: expected!, response };
        this.cancelRecoveryCandidate(m, row.rid);
        this.closeRecovery(m, row);
        store.charge(false, auth!.deviceId);
        m.lastAccess = activityHour(Date.now()); this.saveMeta(m);
      }, true);
      await this.drainRecoveryReleases();
      await this.scheduleAlarm(this.nextAlarm(m));
      return response;
    }

    if (r.resource === "recoveryRotation" || r.resource === "recoveryCommit") return this.recoveryRotation(m, auth, c, row);
    if (b.deviceId !== auth.deviceId) return err(403, "forbidden_role");
    if (row && row.deviceId !== auth.deviceId) return err(403, "forbidden_role");
    if (row && c.recoveryOperation === row.initial.operationId && row.initial.verifier === c.verifier && row.deviceId === auth.deviceId && !row.parent) {
      if (row.state === "retired" && !row.published) return err(409, "recovery_retired");
      const fingerprint = await recoveryFingerprint(b, expected);
      if (fingerprint !== row.initial.fingerprint) return err(409, "recovery_operation_conflict");
      if (row.state === "intention") return this.finishRecoveryIntention(m, row, b.capsule as string);
      if (!row.published) return err(409, "recovery_retired");
      await this.drainRecoveryReleases();
      return row.initial.response;
    }
    if (row && row.state === "retired") return err(409, "recovery_retired");
    if (row && row.state !== "active") return err(409, "recovery_exists");
    const cas = this.recoveryPrecondition(row, c.match);
    if (cas) return cas;
    if (row?.revision === Number.MAX_SAFE_INTEGER) return err(409, "recovery_limit");
    const capsuleError = validateCapsule(b.capsule, r.recoveryId!, (row?.revision ?? 0) + 1);
    if (capsuleError) return capsuleError;
    const fingerprint = await recoveryFingerprint(b, expected);
    if (row && b.readVerifier !== row.readVerifier) return err(400, "invalid_recovery");
    if (!row && !operationId(c.recoveryOperation)) return err(400, "invalid_recovery");
    const rows = store.rows();
    if (!row && rows.some((a) => a.deviceId === auth!.deviceId && (a.state === "active" || (a.state === "intention" && !a.parent)))) return err(409, "recovery_exists");
    if (!row && rows.filter((a) => a.state === "active" || (a.state === "intention" && !a.parent)).length >= RECOVERY_MAX_ACTIVE) return err(409, "recovery_limit");
    const size = Math.floor((b.capsule as string).length * 3 / 4);
    if (rows.filter((a) => a.state === "active" && a.rid !== row?.rid).reduce((n, a) => n + a.size, 0) + size > RECOVERY_MAX_ACTIVE_BYTES) return err(409, "recovery_limit");
    const updated: RecoveryRow = row ? { ...row, revision: row.revision + 1, size } : {
      rid: r.recoveryId!, deviceId: auth.deviceId, reservationId: encodeB64Url(randomBytes(16)), state: "intention", readVerifier: b.readVerifier as string, revision: 1, size,
      expiresAt: Date.now() + RECOVERY_RESERVATION_MS,
      initial: { operationId: c.recoveryOperation!, fingerprint, verifier: c.verifier!, response: { status: 201 } },
    };
    if (!row) updated.initial.response = this.recoveryResponse(updated, 201);
    const error = store.history(row ? rows.map((a) => a.rid === row.rid ? updated : a) : [...rows, updated]) ?? store.quotaError(true, auth.deviceId);
    if (error) return error;
    await this.commit(() => {
      if (row) { this.cancelRecoveryCandidate(m, row.rid); store.writeBlob(row.rid, b.capsule as string); }
      else {
        updated.published = false;
        store.writeBlob(updated.rid, b.capsule as string);
        this.queueRecoveryLocator(m.syncId, updated, true);
      }
      store.save(updated); store.charge(true, auth!.deviceId);
      m.lastAccess = activityHour(Date.now()); this.saveMeta(m);
    });
    if (!row) return this.finishRecoveryIntention(m, updated, b.capsule as string);
    await this.scheduleAlarm(this.nextAlarm(m));
    await this.drainRecoveryReleases();
    await this.scheduleAlarm(this.nextAlarm(m));
    return this.recoveryResponse(updated);
  }

  private async recoveryRotation(m: Meta, auth: Credential, c: V2Call, old: RecoveryRow | undefined): Promise<ApiResult> {
    const store = this.recoveryStore(), b = c.body, expected = recoveryCas(c.match);
    if (!old) return NOT_FOUND;
    if (old.deviceId !== auth.deviceId) return err(403, "forbidden_role");
    const commit = c.route.resource === "recoveryCommit";
    const op = commit ? c.route.recoveryOperation! : b.operationId as string;
    const candidate = store.rows().find((r) => r.parent === old.rid && r.initial.operationId === op);
    if (candidate) {
      const fingerprint = !commit ? await recoveryFingerprint(b, expected) : undefined;
      if ((!commit && fingerprint !== candidate.initial.fingerprint) || (commit && expected !== candidate.expectedRevision)) return err(409, "recovery_operation_conflict");
      if (candidate.terminal === "committed") return old.commit!.response;
      if (candidate.terminal) return err(409, candidate.terminal === "expired" ? "recovery_rotation_expired" : "recovery_rotation_cancelled");
      if (!commit) return candidate.state === "intention" ? this.finishRecoveryIntention(m, candidate, b.capsule as string) : candidate.initial.response;
    }
    if (old.state !== "active") return NOT_FOUND;
    const cas = this.recoveryPrecondition(old, c.match);
    if (cas) return cas;
    if (commit) {
      if (!candidate || candidate.state !== "candidate") return NOT_FOUND;
      const quota = store.quotaError(false, auth.deviceId);
      if (quota) return quota;
      const response = this.recoveryResponse(candidate, 200, op);
      await this.commit(() => {
        candidate.state = "active"; candidate.terminal = "committed"; delete candidate.expiresAt;
        store.save(candidate);
        old.commit = { verifier: c.verifier!, expectedRevision: expected!, response };
        this.closeRecovery(m, old);
        store.charge(false, auth!.deviceId); m.lastAccess = activityHour(Date.now()); this.saveMeta(m);
      });
      await this.scheduleAlarm(this.nextAlarm(m));
      await this.drainRecoveryReleases();
      await this.scheduleAlarm(this.nextAlarm(m));
      return response;
    }
    if (store.rows().some((r) => r.parent && (r.state === "candidate" || r.state === "intention"))) return err(409, "recovery_exists");
    const rid = b.newRecoveryId as string;
    if (store.get(rid)) return err(409, "recovery_retired");
    const capsuleError = validateCapsule(b.capsule, rid, 1);
    if (capsuleError) return capsuleError;
    const fingerprint = await recoveryFingerprint(b, expected);
    const row: RecoveryRow = { rid, deviceId: auth.deviceId, reservationId: encodeB64Url(randomBytes(16)), state: "intention", readVerifier: b.readVerifier as string, revision: 1, size: Math.floor((b.capsule as string).length * 3 / 4), parent: old.rid, expectedRevision: expected!, expiresAt: Date.now() + RECOVERY_RESERVATION_MS, initial: { operationId: op, fingerprint, verifier: c.verifier!, response: { status: 201 } } };
    row.initial.response = this.recoveryResponse(row, 201, op);
    const error = store.history([...store.rows(), row]) ?? store.quotaError(true, auth.deviceId);
    if (error) return error;
    await this.commit(() => {
      row.published = false;
      store.writeBlob(row.rid, b.capsule as string);
      store.save(row);
      this.queueRecoveryLocator(m.syncId, row, true);
      m.lastAccess = activityHour(Date.now()); this.saveMeta(m);
      store.charge(true, auth!.deviceId);
    });
    return this.finishRecoveryIntention(m, row, b.capsule as string);
  }

  /**
   * A retired syncId refuses creation for 400 days. Web mutation routes report retirement;
   * open and the older read routes keep their uniform `404`.
   */
  private retiredAnswer(c: V2Call): ApiResult {
    const r = c.route;
    if (r.syncId !== undefined && ((r.resource === "list" && c.method === "PUT") || r.resource === "common" || r.resource === "renewal" || (r.resource === "guard" && r.action !== "open"))) return err(410, "retired");
    return NOT_FOUND;
  }

  /** `PUT /v2/lists/{syncId}` with `If-Match: "0"` on a list that does not exist. */
  private async create(c: V2Call): Promise<ApiResult> {
    const r = c.route;
    if (r.syncId === undefined || r.resource !== "list" || c.method !== "PUT") return NOT_FOUND;
    if (c.verifier === null) return UNAUTHORIZED;
    if (c.match === null) return err(428, "precondition_required");
    if (c.match !== etag(0)) return err(412, "precondition_failed", { ETag: etag(0) });
    const ns = euNamespace(this.env.LIMITER_V2, this.env, this.localRequest);
    const wide = c.client48 ?? clientKey48(c.client);
    const quotas: [string, number, number][] = wide === c.client
      ? [[`v2:new:${c.client}`, V2_NEW_LISTS_PER_HOUR, V2_NEW_LISTS_PER_DAY]]
      : [[`v2:new48:${wide}`, V2_NEW_LISTS_PER_HOUR_48, V2_NEW_LISTS_PER_DAY_48], [`v2:new:${c.client}`, V2_NEW_LISTS_PER_HOUR, V2_NEW_LISTS_PER_DAY]];
    for (const [key, hourly, daily] of quotas) {
      const quota = await ns.get(ns.idFromName(key)).creation(hourly, daily);
      if (!quota.ok) return limited(quota.retryAfter);
    }
    const b = c.body;
    if (!identifier(b.deviceId)) return err(400, "bad_request");
    if (b.inviteCopy !== undefined && typeof b.inviteCopy !== "boolean") return err(400, "bad_request");
    const invalid = validateSnapshot(b);
    if (invalid) return snapshotError(invalid);
    const s = b as unknown as Snapshot;
    // A generation may be born in the new format (renewal, lote 4): its creator
    // writes it, so its credential counts as having announced it.
    if (b.minCommonFormat !== undefined && !commonFormatValue(b.minCommonFormat)) return err(400, "bad_request");
    const minCommonFormat = (b.minCommonFormat as number | undefined) ?? 1;
    const formatError = commonFormatError(s.common, minCommonFormat);
    if (formatError) return formatError;
    const foreign = slotOwnership(s.slots, b.deviceId, "device");
    if (foreign) return foreign;
    const planted = packageOwnership(s.keyPackages, [], b.deviceId, "device");
    if (planted) return planted;
    if (s.slots.filter((x) => x.data !== null).length > V2_MAX_SLOTS_PER_WRITER) return err(413, "too_many_writer_slots");
    const signingKey = registrySigningKey(s.registry.records as unknown[], b.deviceId);
    if (!signingKey) return err(400, "renewal_key_binding_required");
    // A new list stays small; it can grow with later versions.
    if (bytes(b) > MAX_FIRST_UPLOAD_BYTES) return err(413, "too_large");

    const now = Date.now();
    const knownRecords = [...new Set(await Promise.all((s.registry.records as unknown[]).map(recordHash)))];
    const m: Meta = {
      syncId: r.syncId,
      version: 1,
      createdAt: now,
      lastAccess: activityHour(now),
      ...(b.inviteCopy === true ? { inviteCopyExpiresAt: now + INVITE_TTL_MS, inviteCopyMaxExpiresAt: now + 7 * INVITE_TTL_MS } : {}),
      // The first registry is bounded by its own caps and costs no quota.
      credentials: [{ deviceId: b.deviceId, verifier: c.verifier, revoked: false, createdAt: now, records: [], role: "device",
        signingKey,
        ...(minCommonFormat > 1 ? { commonFormat: minCommonFormat } : {}) }],
      denied: [],
      knownRecords,
      recordTimes: [],
      approvals: [],
      ...(minCommonFormat > 1 ? { minCommonFormat } : {}),
    };
    const global = euNamespace(this.env.CREATION_BUDGET, this.env, this.localRequest);
    const reservation = await global.get(global.idFromName("v2:new-lists")).reserve();
    if (!reservation.ok) return limited(reservation.retryAfter);
    await this.admitRows(c);
    // Arm before committing the first copy, including a crash before the reply.
    await this.scheduleAlarm(m.inviteCopyExpiresAt ?? now + LIST_TTL_MS);
    const slots = s.slots.filter((x) => x.data !== null);
    // Schema rows (13), snapshot/state rows (6), and slot index entries.
    const blocks = this.budget.initialBlocks(m, [
      { idx: 0, data: s.common },
      { name: "registry", data: JSON.stringify(s.registry) },
      { name: "packages", data: JSON.stringify(s.keyPackages) },
      ...slots.map((slot) => ({ person: slot.personId, device: slot.deviceId, ver: 1, data: slot.data })),
    ], 19 + 2 * slots.length);
    await this.reserveBlocks(blocks);
    await this.commit(() => {
      this.createSchema();
      this.writeSnapshot({ ...s, slots }, 1);
      this.saveMeta(m);
    });
    return this.versioned(m, 201);
  }

  private read(m: Meta, c: V2Call): ApiResult {
    const headers = { ETag: etag(m.version) };
    if (c.none === headers.ETag) return { status: 304, headers };
    return {
      status: 200,
      headers,
      body: {
        version: m.version,
        common: this.readCommon(),
        registry: this.readResource("registry"),
        keyPackages: this.readResource("packages"),
        slots: this.manifest(),
        // Which service credentials the server accepts: a phone can spot one that
        // a later-revoked device approved without publishing it in the registry.
        devices: m.credentials.map((a): V2Device => ({ deviceId: a.deviceId, revoked: a.revoked, role: a.role ?? "device",
          ...(a.approvedBy === undefined ? {} : { approvedBy: a.approvedBy }),
          ...((a.commonFormat ?? 1) > 1 ? { commonFormat: a.commonFormat } : {}),
          ...((a.slotCapacity ?? 1) > 1 ? { slotCapacity: a.slotCapacity } : {}) })),
        capacity: this.capacity(m),
        // This server takes `slotCapacity` announcements (1.0.6).
        slotCapacity: V2_SLOT_CAPACITY,
        ...((m.minCommonFormat ?? 1) > 1 ? { minCommonFormat: m.minCommonFormat } : {}),
      },
    };
  }

  /**
   * How full this generation is. Past a warning threshold the app offers to renew
   * (new syncId, keys and registry) before a cap turns into `generation_full`.
   */
  private capacity(m: Meta) {
    const credentials = { used: m.credentials.length, warn: V2_WARN_DEVICES, max: V2_MAX_DEVICES };
    const records = { used: m.knownRecords.length, warn: V2_WARN_KNOWN_RECORDS, max: V2_MAX_KNOWN_RECORDS };
    // Nobody removes another writer's slot (B2): abandoned ones fill the cap
    // until their writers replace them or the family renews.
    const legacy = this.slotLimit(m) < V2_MAX_SLOTS;
    const slots = { used: this.slotKeys().size, warn: legacy ? V2_LEGACY_WARN_SLOTS : V2_WARN_SLOTS, max: this.slotLimit(m) };
    return { credentials, records, slots, renew: credentials.used >= credentials.warn || records.used >= records.warn || slots.used >= slots.warn };
  }

  /** A slot of one snapshot: `If-Match` must name the version the client is assembling. */
  private readSlot(m: Meta, c: V2Call): ApiResult {
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    const row = this.sql
      .exec<{ ver: number; data: string }>("SELECT ver, data FROM slot WHERE person = ? AND device = ?", c.route.personId!, c.route.deviceId!)
      .toArray()[0];
    if (!row) return NOT_FOUND;
    return { status: 200, headers: { ETag: etag(m.version) }, body: { version: m.version, slotVersion: row.ver, data: row.data } };
  }

  private async put(m: Meta, auth: Credential, c: V2Call): Promise<ApiResult> {
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    const invalid = validateSnapshot(c.body);
    if (invalid) return snapshotError(invalid);
    const s = c.body as unknown as Snapshot;
    // The cut-over (ADR 0005, B4): a device that announced the format raises the
    // minimum in the same write as the first common of that format. Never lowered.
    const raise = c.body.minCommonFormat;
    if (raise !== undefined) {
      if (!commonFormatValue(raise)) return err(400, "bad_request");
      if ((auth.role ?? "device") !== "device") return err(403, "forbidden_role");
      // Every live credential, of any role (webs too), must have announced the
      // format: phones check their registry, but only honest ones do (M1).
      if (raise > (m.minCommonFormat ?? 1) && m.credentials.some((a) => !a.revoked && (a.commonFormat ?? 1) < raise)) {
        return err(409, "common_format_unannounced");
      }
    }
    const minCommonFormat = Math.max(m.minCommonFormat ?? 1, (raise as number | undefined) ?? 1);
    const formatError = commonFormatError(s.common, minCommonFormat);
    if (formatError) return formatError;
    // Only the writer's own slots, for data and for removal alike (B2).
    const foreign = slotOwnership(s.slots, auth.deviceId, auth.role ?? "device");
    if (foreign) return foreign;
    // Only the writer's own new key packages (B3); stored ones may be forwarded.
    const stored = this.readResource("packages") as unknown[];
    const planted = packageOwnership(s.keyPackages, stored, auth.deviceId, auth.role ?? "device");
    if (planted) return planted;
    const keys = this.slotKeys();
    for (const x of s.slots) {
      if (x.data === null) keys.delete(`${x.personId}/${x.deviceId}`);
      else keys.add(`${x.personId}/${x.deviceId}`);
    }
    // Above the cap a list only refuses growth: replacing or removing still works
    // (a phone that never announced may have paired after the list grew).
    if (keys.size > this.slotLimit(m) && keys.size > this.slotKeys().size) return err(413, "too_many_slots");
    // One credential cannot fill the list's cap on its own (B2: nobody else may
    // remove its slots). A writer already above it may still replace or remove.
    const own = (set: Set<string>) => [...set].filter((k) => k.endsWith(`/${auth.deviceId}`)).length;
    const after = own(keys);
    if (after > V2_MAX_SLOTS_PER_WRITER && after > own(this.slotKeys())) return err(413, "too_many_writer_slots");

    // Bounded growth of the registry (ADR 0004, 4 rest), without reading signatures.
    const hashes = [...new Set(await Promise.all((s.registry.records as unknown[]).map(recordHash)))];
    const fresh = hashes.filter((h) => !m.knownRecords.includes(h));
    if (fresh.length > 0) {
      if (m.knownRecords.length + fresh.length > V2_MAX_KNOWN_RECORDS) return generationFull();
      // Two sliding 24 h windows: the credential's own 8 and the list's 16, so
      // extra credentials of one attacker do not multiply the budget.
      const now = Date.now();
      const own = recent(auth.records, now);
      const list = recent(m.recordTimes, now);
      const wait = Math.max(
        waitFor(own, fresh.length, V2_NEW_RECORDS_PER_CREDENTIAL, now),
        waitFor(list, fresh.length, V2_NEW_RECORDS_PER_LIST, now),
      );
      if (wait > 0) return err(429, "too_many_records", { "Retry-After": String(wait) });
      const stamps = Array<number>(fresh.length).fill(now);
      auth.records = [...own, ...stamps];
      m.recordTimes = [...list, ...stamps];
      m.knownRecords.push(...fresh);
    }

    m.version++;
    m.lastAccess = activityHour(Date.now());
    if (minCommonFormat > (m.minCommonFormat ?? 1)) m.minCommonFormat = minCommonFormat;
    await this.commit(() => {
      this.writeSnapshot(s, m.version);
      this.saveMeta(m);
    });
    this.notify(m);
    return this.versioned(m);
  }

  /**
   * `PUT S/slots/{person}/{device} {data}` (1.0.6, ADR 0009): a web's inbox
   * slot, the changes it made to the surprises of one person, for the phones
   * of its own person to collect. Only a web credential and only its own
   * device id (phones keep `PUT S`); `data: null` removes it. Same header and
   * size checks as a phone's slot, the global ETag and the list's slot cap,
   * plus [V2_MAX_WEB_SLOTS] per web. The server never reads the content.
   */
  private async putWebSlot(m: Meta, auth: Credential, c: V2Call): Promise<ApiResult> {
    if ((auth.role ?? "device") !== "web") return err(403, "forbidden_role");
    if (c.route.deviceId !== auth.deviceId) return err(403, "forbidden_slot");
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    if (Object.keys(c.body).length !== 1 || !("data" in c.body)) return err(400, "bad_request");
    const data = c.body.data;
    if (data !== null && typeof data !== "string") return err(400, "bad_request");
    const change: SlotChange = { personId: c.route.personId!, deviceId: auth.deviceId, data };
    const invalid = validateSlotData(change);
    if (invalid) return snapshotError(invalid);
    const keys = this.slotKeys();
    const key = `${change.personId}/${change.deviceId}`;
    const had = keys.has(key);
    if (data === null && !had) return this.versioned(m);
    if (data !== null && !had) {
      keys.add(key);
      if (keys.size > this.slotLimit(m)) return err(413, "too_many_slots");
      if ([...keys].filter((k) => k.endsWith(`/${auth.deviceId}`)).length > V2_MAX_WEB_SLOTS) return err(413, "too_many_writer_slots");
    }
    m.version++;
    m.lastAccess = activityHour(Date.now());
    await this.commit(() => {
      this.writeSlots([change], m.version);
      this.saveMeta(m);
    });
    this.notify(m);
    return this.versioned(m);
  }

  private async putCommon(m: Meta, c: V2Call): Promise<ApiResult> {
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    if (Object.keys(c.body).length !== 1 || !("common" in c.body)) return err(400, "bad_request");
    const invalid = validateCommon(c.body.common);
    if (invalid) return snapshotError(invalid);
    const formatError = commonFormatError(c.body.common as string, m.minCommonFormat ?? 1);
    if (formatError) return formatError;
    m.version++;
    m.lastAccess = activityHour(Date.now());
    await this.commit(() => {
      this.writeCommon(c.body.common as string);
      this.saveMeta(m);
    });
    this.notify(m);
    return this.versioned(m);
  }

  /**
   * `POST S/capability {commonFormat, renewalProtocol?}`: this credential reads
   * and writes that common format and may explicitly opt into renewal v1.
   * Both announcements are monotonic and idempotent. A first announcement bumps
   * the version and notifies; common format alone never opts into renewal.
   */
  private async capability(m: Meta, auth: Credential, c: V2Call): Promise<ApiResult> {
    if (this.readRenewal()?.abortion === null) return err(409, "renewal_signed_capability_required");
    const format = c.body.commonFormat;
    const slotOnly = !("commonFormat" in c.body) && "slotCapacity" in c.body;
    if (Object.keys(c.body).some((k) => k !== "commonFormat" && k !== "renewalProtocol" && k !== "slotCapacity") ||
      (!slotOnly && (!commonFormatValue(format) || format < 2)) ||
      ("slotCapacity" in c.body && c.body.slotCapacity !== V2_SLOT_CAPACITY) ||
      ("renewalProtocol" in c.body && c.body.renewalProtocol !== 1)) return err(400, "bad_request");
    // Mobiles and webs (B5): both read and write the common.
    if (!["device", "web"].includes(auth.role ?? "device")) return err(403, "forbidden_role");
    const announceRenewal = c.body.renewalProtocol === 1 && auth.renewalProtocol !== 1;
    const announceSlots = c.body.slotCapacity === V2_SLOT_CAPACITY && (auth.slotCapacity ?? 1) < V2_SLOT_CAPACITY;
    if ((slotOnly || (auth.commonFormat ?? 1) >= (format as number)) && !announceRenewal && !announceSlots) return this.versioned(m);
    const limitBefore = this.slotLimit(m);
    if (!slotOnly) auth.commonFormat = Math.max(auth.commonFormat ?? 1, format as number);
    if (announceRenewal) auth.renewalProtocol = 1;
    if (announceSlots) auth.slotCapacity = V2_SLOT_CAPACITY;
    // `slotCapacity` alone only moves the version (new ETag, notify) when it
    // changes the effective cap (the last phone announcing: 64 -> 128), so a
    // reader that kept 64 does not get a 304. Otherwise it is stored quietly.
    const bump = !slotOnly || announceRenewal || this.slotLimit(m) !== limitBefore;
    if (bump) m.version++;
    m.lastAccess = activityHour(Date.now());
    await this.commit(() => this.saveMeta(m));
    if (bump) this.notify(m);
    return this.versioned(m);
  }

  /** Conditional delete (closes N7): everything goes at once and the syncId is retired. */
  private async remove(m: Meta, c: V2Call, auth: Credential): Promise<ApiResult> {
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    if (c.automaticRetirement && this.recoveryStore().rows().some((r) => r.state === "active")) return err(409, "recovery_active");
    const renewal = this.readRenewal();
    if (renewal !== null && renewal.abortion === null) {
      const devices = m.credentials.map((a): V2Device => ({ ...a, role: a.role ?? "device" }));
      if ((m.renewalReturned ?? []).length > 0 || !renewalCanClose(renewal, { ...auth, role: auth.role ?? "device" }, devices, m.version)) return err(409, "renewal_close_pending");
      return await this.retire() ? { status: 204 } : err(500, "internal");
    }
    // Only the last phone erases the list: with another live credential it is
    // theirs too (the app already checks; this is the server's own guard).
    if (m.credentials.some((a) => !a.revoked && a.deviceId !== auth.deviceId)) return err(409, "devices_active");
    return await this.retire() ? { status: 204 } : err(500, "internal");
  }

  /**
   * Revoke wins: idempotent, by any active credential. `If-Match` is optional:
   * without it the revocation is unconditional (explicit ones, older phones);
   * with it, it must name the current version exactly or the answer is `412`,
   * so a phone that decided from a snapshot re-reads before cutting (B2).
   */
  private async revoke(m: Meta, c: V2Call): Promise<ApiResult> {
    if (this.readRenewal()?.abortion === null) return err(409, "renewal_signed_revoke_required");
    const deviceId = c.body.deviceId;
    if (!identifier(deviceId)) return err(400, "bad_request");
    if (c.match !== null) {
      const failed = this.precondition(m, c.match);
      if (failed) return failed;
    }
    const target = m.credentials.find((a) => a.deviceId === deviceId);
    if (!target) return NOT_FOUND;
    if (!target.revoked) {
      m.denied.push(target.verifier!);
      target.verifier = null;
      target.revoked = true;
      // A web's inbox slots go at once (1.0.6, ADR 0009): no honest reader
      // needs them after the revocation, and what its phone has not
      // collected yet is dropped with them. A phone's slots keep their grace.
      const web = target.role === "web";
      if (!web) target.slotsExpireAt = Date.now() + V2_REVOKED_SLOTS_GRACE_MS;
      m.version++;
      if (!m.credentials.some((credential) => !credential.revoked)) {
        // Preserve the v2 revoke response for installed clients; erase all content.
        const response = this.versioned(m);
        return await this.retire() ? response : err(500, "internal");
      }
      const removed = this.invites().filter((i) => i.owner === deviceId || i.guest === deviceId);
      await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
      await this.commit(() => {
        for (const i of removed) {
          this.queueRelease(m.syncId, i);
          this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
          this.dropCheckpoints(i.id);
        }
        new PinGuard(this.sql).delete(deviceId);
        if (web) this.sql.exec("DELETE FROM slot WHERE device = ?", deviceId);
        // Surviving readers get a fixed grace before the alarm erases slots.
        this.retireDeviceRecoveries(m, deviceId);
        this.saveMeta(m);
      }, true);
      this.closeSockets(CLOSE_REVOKED, deviceId);
      this.notify(m);
      if (!await this.drainReleases()) return err(500, "internal");
      await this.drainRecoveryReleases();
    }
    return this.versioned(m);
  }

  /** An invitation is usable only while it has not expired and its owner is still active. */
  private liveInvite(m: Meta, id: string | undefined): Invitation | null {
    if (id === undefined) return null;
    const i = this.invites().find((v) => v.id === id);
    return i && m.credentials.some((a) => a.deviceId === i.owner && !a.revoked) ? i : null;
  }

  private async invitation(m: Meta, auth: Credential, c: V2Call): Promise<ApiResult> {
    const { route: r, body: b } = c;
    if (r.resource === "invites") {
      const offer = b.offer;
      if (bytes(offer) > V2_MAX_DECLARATION_BYTES) return err(413, "too_large");
      // `PairingOffer`: the host record must be this credential's device.
      if (!object(offer) || offer.v !== 2 || !object(offer.host) || offer.host.d !== auth.deviceId || (offer.host.k !== undefined && offer.host.k !== "web") || !key32(offer.c)) {
        return err(400, "bad_offer");
      }
      if (b.inviteId !== undefined && (typeof b.inviteId !== "string" || decodeB64Url(b.inviteId, 16) === null)) return err(400, "bad_request");
      if (b.guestPerson !== undefined && !identifier(b.guestPerson)) return err(400, "bad_request");
      const guestPerson = b.guestPerson as string | undefined ?? null;
      const offerHash = await recordHash(canonical(offer));
      const existing = b.inviteId === undefined ? undefined : this.invites().find((i) => i.id === b.inviteId);
      if (existing) {
        if (existing.owner !== auth.deviceId || (existing.guestPerson ?? null) !== guestPerson || await recordHash(canonical(existing.offer)) !== offerHash) return err(409, "invite_exists");
        return { status: 201, body: { inviteId: existing.id, expiresAt: existing.expiresAt } };
      }
      // A pending release of this id must be confirmed before the id can be
      // reserved again: it would otherwise release the recreated reservation.
      const pending = this.pendingReleases();
      if (b.inviteId !== undefined && pending.some((p) => p.id === b.inviteId)) return err(409, "invite_exists");
      if (pending.length >= MAX_OPEN_INVITES) return limited(Math.ceil(WINDOW_MS / 1000));
      if (this.invites().filter((i) => !i.package).length >= MAX_OPEN_INVITES) return err(429, "too_many_invites");
      const i: Invitation = { id: b.inviteId as string | undefined ?? encodeB64Url(randomBytes(16)), owner: auth.deviceId, expiresAt: Date.now() + INVITE_TTL_MS, offer, guestPerson, reservationId: encodeB64Url(randomBytes(16)) };
      const invitedMeta = { ...m };
      if (invitedMeta.inviteCopyExpiresAt !== undefined) {
        invitedMeta.inviteCopyMaxExpiresAt ??= invitedMeta.inviteCopyExpiresAt + 6 * INVITE_TTL_MS;
        invitedMeta.inviteCopyExpiresAt = Math.min(i.expiresAt, invitedMeta.inviteCopyMaxExpiresAt);
      }
      // Validate the full invitation, metadata and cancellation queue together.
      // The lock prevents another writer from spending this capacity while the
      // RPC is in flight. A crash leaves only a durable cancellation to drain.
      this.budget.preview(() => {
        this.queueRelease(m.syncId, i);
        this.saveInvite(i);
        this.saveMeta(invitedMeta);
      });
      await this.commit(() => this.queueRelease(m.syncId, i));
      await this.scheduleAlarm(this.nextAlarm(m));
      const ns = euNamespace(this.env.INVITES_V2, this.env, this.localRequest);
      let release = JSON.stringify({ id: i.id, syncId: m.syncId, expiresAt: i.expiresAt, reservationId: i.reservationId });
      try {
        const reservation = await ns.get(ns.idFromName(i.id)).reserve({ syncId: m.syncId, owner: auth.deviceId, offerHash, guestPerson, expiresAt: i.expiresAt, reservationId: i.reservationId });
        if (!reservation.ok) {
          this.sql.exec("DELETE FROM pending_release WHERE data = ?", release);
          return err(409, "invite_exists");
        }
        i.expiresAt = reservation.expiresAt;
        i.reservationId = reservation.reservationId;
        // An identical global reservation can return its original fencing token.
        const confirmedRelease = JSON.stringify({ id: i.id, syncId: m.syncId, expiresAt: i.expiresAt, reservationId: i.reservationId });
        if (confirmedRelease !== release) await this.commit(() => {
          this.sql.exec("DELETE FROM pending_release WHERE data = ?", release);
          this.queueRelease(m.syncId, i);
        }, true);
        release = confirmedRelease;
        if (invitedMeta.inviteCopyExpiresAt !== undefined) invitedMeta.inviteCopyExpiresAt = Math.min(i.expiresAt, invitedMeta.inviteCopyMaxExpiresAt!);
        await this.commit(() => {
          this.saveInvite(i);
          this.saveMeta(invitedMeta);
          this.sql.exec("DELETE FROM pending_release WHERE data = ?", release);
          if (this.pendingReleases().length === 0) this.sql.exec("DROP TABLE pending_release");
        });
        await this.scheduleAlarm(this.nextAlarm(invitedMeta));
      } catch (e) {
        await this.commit(() => {
          this.queueRelease(m.syncId, i);
          this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
          this.saveMeta(m);
        }, true);
        await this.drainReleases();
        throw e;
      }
      return { status: 201, body: { inviteId: i.id, expiresAt: i.expiresAt } };
    }

    const i = this.liveInvite(m, r.inviteId);
    if (!i) return NOT_FOUND;
    if (i.owner !== auth.deviceId) return err(403, "forbidden");
    if (c.method === "DELETE") {
      if (this.pendingReleases().length >= MAX_OPEN_INVITES) return limited(Math.ceil(WINDOW_MS / 1000));
      await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
      await this.commit(() => {
        this.queueRelease(m.syncId, i);
        this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
        this.dropCheckpoints(i.id);
      }, true);
      if (!await this.drainReleases()) return err(500, "internal");
      return { status: 204 };
    }
    if (r.resource === "invite") {
      // `canApprove`: an approval now would fit the daily quota, the live
      // checkpoints and the generation, so the host can stop before publishing
      // the guest's record (B7, M2). Advisory: approve still checks.
      const canApprove = (this.readRenewal() === null || this.readRenewal()!.abortion !== null) && recent(m.approvals, Date.now()).length < V2_NEW_DEVICES_PER_LIST &&
        this.invites().filter((x) => x.checkpoint !== undefined).length < V2_MAX_CHECKPOINTS &&
        m.credentials.length < V2_MAX_DEVICES;
      return { status: 200, body: { offer: i.offer, answer: i.answer ?? null, revealed: !!i.reveal, approved: !!i.package, canApprove, expiresAt: i.expiresAt } };
    }
    if (r.resource === "reveal") {
      if (bytes(b.reveal) > V2_MAX_REVEAL_BYTES) return err(413, "too_large");
      if (!i.answer || i.reveal) return err(409, "invalid_state");
      if (!object(b.reveal) || b.reveal.v !== 2 || !key32(b.reveal.n)) return err(400, "bad_reveal");
      i.reveal = b.reveal;
      await this.commit(() => this.saveInvite(i));
      return { status: 200, body: { expiresAt: i.expiresAt } };
    }
    // approve: registers the guest credential under the version the host saw.
    const failed = this.precondition(m, c.match);
    if (failed) return failed;
    if (!i.reveal || !i.guest || !i.verifier || i.package) return err(409, "invalid_state");
    if (!object(b.package)) return err(400, "bad_package");
    const role = b.role === undefined ? "device" : b.role;
    if (role !== "device" && role !== "web") return err(400, "bad_request");
    const guestRecord = i.answer?.guest;
    if (!object(guestRecord) || !key32(guestRecord.e)) return err(400, "renewal_key_binding_required");
    if ((object(guestRecord) && guestRecord.k === "web") !== (role === "web")) return err(400, "role_mismatch");
    if (bytes(b.package) > V2_MAX_PACKAGE_BYTES) return err(413, "too_large");
    // B7: the host names the exact common and registry it approves (the state
    // at its `If-Match`); they are copied here and kept for the guest. Without
    // it (an older host) nothing is copied, as before.
    let checkpoint: { common: string; registry: string; commonText: string; registryText: string } | null = null;
    if (b.checkpoint !== undefined) {
      const claim = b.checkpoint;
      if (!object(claim) || Object.keys(claim).length !== 2 || !key32(claim.common) || !key32(claim.registry)) return err(400, "bad_checkpoint");
      const live = this.invites().filter((x) => x.checkpoint !== undefined && x.id !== i.id).length;
      if (live >= V2_MAX_CHECKPOINTS) return err(429, "too_many_checkpoints", { "Retry-After": "3600" });
      const commonText = this.readCommon();
      const registryText = canonicalJson(this.readResource("registry"));
      const common = await checkpointHash("common", commonText);
      const registry = await checkpointHash("registry", registryText);
      if (!timingSafeEqual(decodeB64Url(common, 32)!, decodeB64Url(claim.common, 32)!) || !timingSafeEqual(decodeB64Url(registry, 32)!, decodeB64Url(claim.registry, 32)!)) {
        return err(409, "checkpoint_mismatch");
      }
      checkpoint = { common, registry, commonText, registryText };
    }
    if (m.credentials.length >= V2_MAX_DEVICES) return generationFull();
    const guest = i.guest;
    const verifier = i.verifier;
    if (this.denied(m, verifier) || m.credentials.some((a) => a.deviceId === guest || (a.verifier !== null && equal(a.verifier, verifier))) || this.invites().some((other) => other.id !== i.id && other.verifier === verifier)) {
      return err(409, "credential_exists");
    }
    // Slot rows left under this id (by an older server or a long-gone writer)
    // would become the new credential's own: refuse the id instead.
    if (this.sql.exec("SELECT 1 FROM slot WHERE device = ? LIMIT 1", guest).toArray().length > 0) return err(409, "credential_exists");
    const now = Date.now();
    const approvals = recent(m.approvals, now);
    const wait = waitFor(approvals, 1, V2_NEW_DEVICES_PER_LIST, now);
    if (wait > 0) return err(429, "too_many_approvals", { "Retry-After": String(wait) });
    m.approvals = [...approvals, now];
    m.credentials.push({ deviceId: guest, verifier, revoked: false, createdAt: now, records: [], approvedBy: i.owner, role,
      signingKey: guestRecord.e });
    delete m.inviteCopyExpiresAt;
    delete m.inviteCopyMaxExpiresAt;
    m.version++;
    i.package = b.package;
    i.minVersion = m.version;
    if (checkpoint) i.checkpoint = { common: checkpoint.common, registry: checkpoint.registry };
    await this.commit(() => {
      if (checkpoint) this.saveCheckpoint(i.id, checkpoint.commonText, checkpoint.registryText);
      this.saveInvite(i);
      this.saveMeta(m);
    });
    this.notify(m);
    return this.versioned(m);
  }

  private async publicInvite(m: Meta, c: V2Call): Promise<ApiResult> {
    if (this.denied(m, c.verifier)) return UNAUTHORIZED;
    const i = this.liveInvite(m, c.route.inviteId);
    if (!i) return NOT_FOUND;
    // Per invitation, so families behind one NAT do not share it (finding 16).
    if (!await this.hit(`i:${i.id}`, V2_INVITE_REQUESTS_PER_INVITE)) return limited();
    if (c.route.resource === "offer") return { status: 200, body: { offer: i.offer, guestPerson: i.guestPerson ?? null, expiresAt: i.expiresAt } };

    if (c.route.resource === "answer") {
      const { answer, serviceCredentialVerifier: verifier } = c.body;
      if (bytes(answer) > V2_MAX_DECLARATION_BYTES) return err(413, "too_large");
      if (!object(answer) || answer.v !== 2 || !object(answer.guest) || !identifier(answer.guest.d) || (answer.guest.k !== undefined && answer.guest.k !== "web") || !object(answer.vouch) || !key32(verifier)) {
        return err(400, "bad_answer");
      }
      // QA 1.0.6, m1: an answer without a person (a 1.0.5 guest, which sends "p": null) reaches the
      // host, which refuses it and tells its user to update; another person is still rejected here.
      if (i.guestPerson != null && answer.guest.p != null && answer.guest.p !== i.guestPerson) return err(400, "person_mismatch");
      const guest = answer.guest.d;
      if (this.denied(m, verifier)) return UNAUTHORIZED;
      const prior = this.invites().filter((other) => other.id !== i.id && other.verifier === verifier);
      if (m.credentials.some((a) => a.deviceId === guest || (a.verifier !== null && equal(a.verifier, verifier))) || prior.some((other) => other.guest !== guest || other.package !== undefined)) {
        return err(409, "credential_exists");
      }
      if (i.answer) return err(409, "already_answered");
      if (this.pendingReleases().length + prior.length > MAX_OPEN_INVITES) return limited();
      i.answer = answer;
      i.guest = guest;
      i.verifier = verifier;
      await this.commit(() => {
        for (const old of prior) {
          this.queueRelease(m.syncId, old);
          this.sql.exec("DELETE FROM invite WHERE id = ?", old.id);
          this.dropCheckpoints(old.id);
        }
        this.saveInvite(i);
      });
      if (prior.length) await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
      if (prior.length) await this.drainReleases();
      return { status: 201, body: { expiresAt: i.expiresAt } };
    }

    // Only the credential whose hash came with the answer has guest authority.
    if (c.verifier === null || !i.verifier || !equal(c.verifier, i.verifier)) return NOT_FOUND;
    if (c.route.resource === "withdraw") {
      // Shape follows guest authentication: wrong credentials and unknown ids
      // keep the same 404, including when the object has extra fields.
      if (Object.keys(c.body).length !== 0) return err(400, "bad_request");
      // Ordered against approval by handle's list lock. An approved credential
      // is real: do not silently erase its package/checkpoint or claim success.
      if (i.package) return err(409, "already_approved");
      if (this.pendingReleases().length >= MAX_OPEN_INVITES) return limited();
      await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
      await this.commit(() => {
        this.queueRelease(m.syncId, i);
        this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
        this.dropCheckpoints(i.id);
      }, true);
      // The authoritative deletion is committed; failed locator cleanup is
      // retried by the alarm, just like the other invitation releases.
      await this.drainReleases();
      return { status: 204 };
    }
    if (c.route.resource === "checkpoint") {
      // B7: the exact approved common and registry, immutable until the
      // invitation expires or is cancelled. The app checks the hashes.
      if (!i.package) return NOT_FOUND;
      if (c.method === "DELETE") {
        // Installation acknowledgement ends retries, including for older hosts
        // which did not provide a checkpoint. Erase the entire opaque package.
        await this.scheduleAlarm(Math.min(this.nextAlarm(m), Date.now() + WINDOW_MS));
        await this.commit(() => {
          this.queueRelease(m.syncId, i);
          this.dropCheckpoints(i.id);
          this.sql.exec("DELETE FROM invite WHERE id = ?", i.id);
        }, true);
        await this.drainReleases();
        return { status: 204 };
      }
      if (!i.checkpoint) return NOT_FOUND;
      const common = this.readCheckpoint(i.id, "common");
      const registry = this.readCheckpoint(i.id, "registry");
      if (common === null || registry === null) return NOT_FOUND;
      return { status: 200, body: { common, registry } };
    }
    // Clients pace at 1-2 s with their invitation budget; a 4 s hint would
    // unnecessarily delay pairing. Only rate limits prescribe a retry delay.
    if (!i.package) return { status: 202, body: { status: "pending", reveal: i.reveal ?? null } };
    // Repeatable until the invitation expires: a lost response must not strand a
    // guest whose credential is already registered.
    return { status: 200, body: { reveal: i.reveal, package: i.package, minVersion: i.minVersion, syncId: m.syncId } };
  }

  // ---- WebSocket --------------------------------------------------------------

  /** Only reachable from the router, which sets `x-verifier` itself. */
  override async fetch(request: Request): Promise<Response> {
    const local = this.env.LOCAL_DEV === "true" && localhostRequest(request);
    if (this.env.LOCAL_DEV === "true" && !local) return new Response(null, { status: 500 });
    return this.ctx.blockConcurrencyWhile(() => this.withLocalRequest(local, () => this.withLedger(async () => {
      const m = await this.live();
      if (m === null || isRetired(m)) return new Response(null, { status: 404 });
      const v = request.headers.get("x-verifier");
      const replaced = this.replacedError(m, v);
      if (replaced) return new Response(null, { status: 403, headers: { "x-auth-error": String(replaced.body!.error) } });
      const auth = key32(v) ? this.active(m, v) : null;
      if (!auth) return new Response(null, { status: 401 });
      this.recordActivity(m, auth);
      if (auth.role === "web" && new PinGuard(this.sql).requiresRotation(auth.deviceId)) return new Response(null, { status: 401 });
      if (!await this.hit(`r:${auth.deviceId}`, V2_CREDENTIAL_REQUESTS)) return new Response(null, { status: 429, headers: { "Retry-After": "60" } });
      await this.touch(m);
      const open = this.openSockets();
      for (const ws of open.slice(0, Math.max(0, open.length - MAX_SOCKETS + 1))) ws.close(CLOSE_POLICY, "replaced");
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].serializeAttachment({ deviceId: auth.deviceId, credentialVerifier: auth.verifier, t: Date.now() });
      const headers: Record<string, string> = request.headers.has("x-ws-protocol") ? { "Sec-WebSocket-Protocol": V2_WS_PROTOCOL } : {};
      return new Response(null, { status: 101, webSocket: pair[0], headers });
    })));
  }

  /** Text keepalives are bounded per device and revalidate the stored credential. */
  override async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (message !== "ping") { ws.close(CLOSE_POLICY, "read only"); return; }
    await this.ctx.blockConcurrencyWhile(() => this.withLedger(async () => {
      const m = this.stored();
      if (!m || isRetired(m)) { ws.close(CLOSE_GONE, "gone"); return; }
      if (Date.now() - m.lastAccess >= LIST_TTL_MS) { ws.close(CLOSE_GONE, "gone"); return; }
      if (!this.socketAuthorized(ws, m)) return;
      const a = ws.deserializeAttachment() as { deviceId: string };
      if (!await this.hit(`p:${a.deviceId}`, 12)) { ws.close(CLOSE_POLICY, "rate limited"); return; }
      ws.send("pong");
    }));
  }

  override webSocketClose(ws: WebSocket, code: number): void {
    try {
      ws.close(code === 1005 ? 1000 : code);
    } catch {
      // Already closed.
    }
  }

  override webSocketError(ws: WebSocket): void {
    try {
      ws.close(1011);
    } catch {
      // Already closed.
    }
  }

  // ---- expiry -----------------------------------------------------------------

  /**
   * DELETE and the 400-day expiry end the same way: in one transaction the
   * content tables are dropped (common, registry, packages, slots, invitations)
   * and the state row, with credentials, revocation tombstones, device ids and
   * record hashes, is overwritten by a retiring marker. Pending releases survive
   * RPC errors/restarts; only their acknowledgement permits the final bare
   * marker with a 400-day expiry alarm. Access ends with the first commit.
   */
  private async retire(): Promise<boolean> {
    const m = this.stored();
    const invitations = this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'invite'").toArray().length
      ? this.sql.exec<{ data: string }>("SELECT data FROM invite").toArray().map((r) => JSON.parse(r.data) as Invitation) : [];
    // Arm recovery before committing any local mutation, including a crash
    // between that commit and the first remote release.
    await this.scheduleAlarm(Date.now() + WINDOW_MS);
    const until = await this.ctx.storage.get<number>(RETIRED_UNTIL) ?? Date.now() + LIST_TTL_MS;
    await this.ctx.storage.put(RETIRED_UNTIL, until);
    await this.commit(() => {
      if (m && !isRetired(m)) for (const i of invitations) this.queueRelease(m.syncId, i);
      if (m && !isRetired(m)) for (const row of this.recoveryStore().rows()) this.queueRecoveryLocator(m.syncId, { ...row, state: "retired" });
      for (const table of ["common", "resource", "slot", "invite", "checkpoint", "guard", "rate", "renewal_command", "renewal_usage", "recovery", "recovery_blob", "recovery_retired", "recovery_quota", "row_attempts"]) this.sql.exec(`DROP TABLE IF EXISTS ${table}`);
      this.sql.exec("INSERT INTO state (id, data) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data", JSON.stringify({ retiring: true }));
    });
    this.closeSockets(CLOSE_GONE);
    this.rate.clear();
    const invitesReleased = await this.drainReleases();
    const recoveriesReleased = await this.drainRecoveryReleases();
    if (!invitesReleased || !recoveriesReleased) return false;
    this.rowRetryAt = undefined;
    this.budget.rowContext = undefined;
    this.saveMeta(RETIRED);
    this.budget = new ListStorageBudget(this.ctx.storage);
    await this.scheduleAlarm(until);
    return true;
  }

  private hasReleases(): boolean {
    return this.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pending_release'").toArray().length > 0;
  }

  /** Called in the same SQLite transaction as invitation removal/revocation. */
  private queueRelease(syncId: string, i: Invitation): void {
    this.sql.exec("CREATE TABLE IF NOT EXISTS pending_release (data TEXT PRIMARY KEY)");
    const release: Release = { id: i.id, syncId, expiresAt: i.expiresAt, reservationId: i.reservationId };
    this.sql.exec("INSERT OR IGNORE INTO pending_release (data) VALUES (?)", JSON.stringify(release));
  }

  private pendingReleases(): Release[] {
    if (!this.hasReleases()) return [];
    return this.sql.exec<{ data: string }>("SELECT data FROM pending_release").toArray().map((r) => JSON.parse(r.data) as Release);
  }

  /** Persist until acknowledgement; safe after restart or a lost RPC response.
   * A release whose reservation has already expired is dropped (the global
   * reservation expires by itself); a failing one never blocks the others. */
  private async drainReleases(): Promise<boolean> {
    if (!this.hasReleases()) return true;
    let failed = false;
    for (const row of this.sql.exec<{ data: string }>("SELECT data FROM pending_release").toArray()) {
      const r = JSON.parse(row.data) as Release;
      if (r.expiresAt <= Date.now()) {
        await this.commit(() => { this.sql.exec("DELETE FROM pending_release WHERE data = ?", row.data); }, true);
        continue;
      }
      try {
        const ns = euNamespace(this.env.INVITES_V2, this.env, this.localRequest);
        await ns.get(ns.idFromName(r.id)).release(r.syncId, r.expiresAt, r.reservationId);
      } catch {
        failed = true;
        continue;
      }
      await this.commit(() => { this.sql.exec("DELETE FROM pending_release WHERE data = ?", row.data); }, true);
    }
    if (failed) {
      await this.scheduleAlarm(Date.now() + WINDOW_MS);
      return false;
    }
    await this.commit(() => { this.sql.exec("DROP TABLE pending_release"); }, true);
    return true;
  }

  override async alarm(): Promise<void> {
    await this.ctx.blockConcurrencyWhile(() => this.withLedger(async () => {
      const m = await this.live();
      if (isRetired(m)) return;
      this.restoreRowContext();
      try {
        if (m === null) return;
        const now = Date.now();
        for (const [key, counter] of this.rate) if (counter.start <= now - WINDOW_MS) this.rate.delete(key);
        let removedSlots = false;
        await this.commit(() => {
          this.sql.exec("DROP TABLE IF EXISTS rate");
          this.sql.exec("DELETE FROM invite WHERE expires_at <= ?", now);
          this.dropCheckpoints();
          for (const credential of m.credentials) {
            if (!credential.revoked || credential.slotsExpireAt === undefined || credential.slotsExpireAt > now) continue;
            removedSlots = this.sql.exec("DELETE FROM slot WHERE device = ?", credential.deviceId).rowsWritten > 0 || removedSlots;
            delete credential.slotsExpireAt;
          }
          if (removedSlots) m.version++;
          this.saveMeta(m);
        }, true);
        if (removedSlots) this.notify(m);
        await this.expireRecoveries();
        await this.drainRecoveryReleases();
        await this.scheduleAlarm(this.nextAlarm(m));
      } finally {
        // A retry alarm must drain even a sub-block tail after hibernation,
        // when the in-memory reason for the wake has been lost.
        await this.settleRows("*");
        this.budget.rowContext = undefined;
      }
    }));
  }
}
