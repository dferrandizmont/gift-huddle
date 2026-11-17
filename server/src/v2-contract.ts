import { decodeB64Url, isB64UrlText } from "./encoding";
import { err, type ApiResult } from "./http";
import {
  MAX_ENVELOPE_BYTES,
  MAX_ENVELOPE_CHARS,
  V2_ID_PATTERN,
  V2_MAX_PACKAGES,
  V2_MAX_PACKAGES_BYTES,
  V2_MAX_RECORDS,
  V2_MAX_REGISTRY_BYTES,
  V2_MAX_REVOCATIONS,
  V2_MAX_SLOT_BYTES,
  V2_MAX_SLOT_CHARS,
  V2_MAX_SLOTS,
  V2_MAX_VOUCHES,
} from "./limits";

export const object = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
export const identifier = (v: unknown): v is string => typeof v === "string" && V2_ID_PATTERN.test(v);
/** UTF-8 bytes of the JSON text of `v`. */
export const bytes = (v: unknown): number => new TextEncoder().encode(JSON.stringify(v) ?? "").length;
export const key32 = (v: unknown): v is string => typeof v === "string" && decodeB64Url(v, 32) !== null;
/**
 * Canonical JSON text (B7): keys sorted by UTF-16 code units and written as an
 * ordered list of pairs, never through an object (which would move integer-like
 * keys first), so it matches the app's `canonicalJsonText` byte for byte for
 * strings, booleans, null and safe integers.
 */
export function canonicalJson(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(",")}]`;
  if (object(v)) return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonicalJson(v[k])}`).join(",")}}`;
  return JSON.stringify(v) ?? "null";
}

/** `data` is the base64url text of a sealed slot; `null` removes it. */
export type SlotChange = { personId: string; deviceId: string; data: string | null };
/** Creation only: inviteCopy gives an unpaired invitation copy a fixed 24 h TTL.
 * Omitted by older clients and for permanent sync/recovery copies. Approval or
 * recovery publication promotes the copy to ordinary list retention. */
export type Snapshot = { common: string; registry: Record<string, unknown>; keyPackages: unknown[]; slots: SlotChange[]; inviteCopy?: boolean };

export type Role = "device" | "web";
/** Service permissions and provenance, never signed registry trust. approvedBy
 * is absent on the creator and credentials stored before that field existed. */
export type V2Device = { deviceId: string; revoked: boolean; role: Role; approvedBy?: string; commonFormat?: number };

export function validateCommon(common: unknown): 400 | 413 | null {
  if (typeof common !== "string" || !isB64UrlText(common)) return 400;
  if (common.length > MAX_ENVELOPE_CHARS || Math.floor((common.length * 3) / 4) > MAX_ENVELOPE_BYTES) return 413;
  return null;
}

/** Latest format of the common envelope ("RG" + version byte) this server knows (ADR 0005, B4). */
export const COMMON_FORMAT_LATEST = 2;

/** The version byte of an "RG" common envelope, or null when the text is not one. Decodes 3 bytes only. */
export function commonFormat(common: string): number | null {
  const head = decodeB64Url(common.length <= 4 ? common : common.slice(0, 4));
  if (!head || head.length < 3 || head[0] !== 0x52 || head[1] !== 0x47) return null;
  return head[2]!;
}

/**
 * The format byte of a common against the list's persisted minimum (ADR 0005,
 * B4). A later format than this server knows is `400` (a phone would stop and
 * ask to update, so one credential could block everyone); a lower one than the
 * minimum is `409 common_format_too_old` (an old client cannot degrade the
 * family). Under the legacy minimum (1) text that is not an "RG" envelope is
 * still accepted, as before: phones treat it as forged and replace it.
 */
export function commonFormatError(common: string, min: number): ApiResult | null {
  // A stored minimum from a later server (a rollback of this code): refuse the
  // write without retiring the list, until the newer code is back.
  if (min > COMMON_FORMAT_LATEST) return err(409, "common_format_unsupported");
  const f = commonFormat(common);
  if (f !== null && f > COMMON_FORMAT_LATEST) return err(400, "common_format_unknown");
  if (min <= 1) return null;
  if (f === null) return err(400, "common_format_unknown");
  return f < min ? err(409, "common_format_too_old") : null;
}

/** A format a client may announce or ask the list to require: 1 up to [COMMON_FORMAT_LATEST]. */
export const commonFormatValue = (v: unknown): v is number => storedCommonFormat(v) && (v as number) <= COMMON_FORMAT_LATEST;

/**
 * A format as stored in the state row: any safe integer from 1. The upper bound
 * applies only to what arrives through the API, so rolling the Worker back to
 * an older version never retires a list that a newer one raised.
 */
export const storedCommonFormat = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 1;

/** "GHS" + format 2 (`protected_envelope.dart`). */
const SLOT_MAGIC = [0x47, 0x48, 0x53, 0x02];
/** Magic + version, epoch, revision, policy, policy revision and kid. */
const SLOT_FIXED_HEADER = 4 + 4 + 8 + 1 + 8 + 8;
/**
 * What follows the header in every slot: nonce (12), the fixed 128 KiB of
 * ciphertext (`kSlotPlainBytes`), GCM tag (16) and Ed25519 signature (64).
 */
export const SLOT_BODY_BYTES = 12 + 128 * 1024 + 16 + 64;
/** Revisions are below 2^53: the high word of each uint64 is at most 0x1FFFFF. */
const MAX_HIGH_WORD = 0x1fffff;

/**
 * Reads only the header of a slot (ids, the policy flags and the range of both
 * revisions), never the signature or the ciphertext: the server binds the
 * resource name to what the slot says and refuses what no phone could parse
 * (`SealedSlot.parse`), so one malformed slot cannot stop the family's sync.
 */
export function slotIds(slot: Uint8Array): { personId: string; writer: string; headerBytes: number } | null {
  if (slot.length < SLOT_FIXED_HEADER + 3) return null;
  for (let i = 0; i < SLOT_MAGIC.length; i++) if (slot[i] !== SLOT_MAGIC[i]) return null;
  const view = new DataView(slot.buffer, slot.byteOffset, slot.byteLength);
  if (view.getUint32(8) > MAX_HIGH_WORD || slot[16]! > 1 || view.getUint32(17) > MAX_HIGH_WORD) return null;
  const ids: string[] = [];
  let at = SLOT_FIXED_HEADER;
  for (let k = 0; k < 3; k++) {
    const n = slot[at++]!;
    if (n === 0 || at + n > slot.length) return null;
    const id = String.fromCharCode(...slot.subarray(at, at + n));
    if (!identifier(id)) return null;
    ids.push(id);
    at += n;
  }
  return { personId: ids[1]!, writer: ids[2]!, headerBytes: at };
}

/**
 * Shape and bounds of a v2 snapshot. Counts are checked before anything is
 * measured or decoded, and nothing looks at signatures (they stay on the phones).
 * Returns the HTTP status to answer, or null when it is acceptable.
 */
export function validateSnapshot(b: Record<string, unknown>): 400 | 413 | null {
  if (!Array.isArray(b.slots)) return 400;
  if (b.slots.length > V2_MAX_SLOTS) return 413;
  const r = b.registry;
  if (!object(r) || !Array.isArray(r.records) || !Array.isArray(r.vouches) || !Array.isArray(r.revocations)) return 400;
  if (r.records.length > V2_MAX_RECORDS || r.vouches.length > V2_MAX_VOUCHES || r.revocations.length > V2_MAX_REVOCATIONS) return 413;
  if (r.records.some((record) => object(record) && "k" in record && record.k !== "web")) return 400;
  if (!Array.isArray(b.keyPackages)) return 400;
  if (b.keyPackages.length > V2_MAX_PACKAGES) return 413;
  const commonError = validateCommon(b.common);
  if (commonError) return commonError;
  const seen = new Set<string>();
  for (const s of b.slots) {
    if (!object(s) || !identifier(s.personId) || !identifier(s.deviceId)) return 400;
    if (s.data !== null && typeof s.data !== "string") return 400;
    const k = `${s.personId}/${s.deviceId}`;
    if (seen.has(k)) return 400;
    seen.add(k);
    if (typeof s.data === "string" && s.data.length > V2_MAX_SLOT_CHARS) return 413;
  }
  if (bytes(r) > V2_MAX_REGISTRY_BYTES || bytes(b.keyPackages) > V2_MAX_PACKAGES_BYTES) return 413;
  for (const s of b.slots as SlotChange[]) {
    if (s.data === null) continue;
    if (!isB64UrlText(s.data)) return 400;
    if (Math.floor((s.data.length * 3) / 4) > V2_MAX_SLOT_BYTES) return 413;
    // Only the header is decoded (CPU per request is scarce on the free plan).
    const head = decodeB64Url(s.data.length <= SLOT_HEADER_CHARS ? s.data : s.data.slice(0, SLOT_HEADER_CHARS));
    const ids = head && slotIds(head);
    if (!ids || ids.personId !== s.personId || ids.writer !== s.deviceId) return 400;
    // The exact size, from the text length alone (the body is never decoded).
    if (Math.floor((s.data.length * 3) / 4) !== ids.headerBytes + SLOT_BODY_BYTES) return 400;
  }
  return null;
}

/** Base64url characters that always cover the longest header (420 bytes); a multiple of 4. */
const SLOT_HEADER_CHARS = 560;

export type V2Route = {
  resource: "list" | "common" | "capability" | "guard" | "ws" | "revoke" | "invites" | "slot" | "invite" | "reveal" | "approve" | "offer" | "answer" | "withdraw" | "result" | "checkpoint" | "renewal" | "recoveries" | "recovery" | "recoveryClaim" | "recoveryRotation" | "recoveryCommit";
  action?: "prepare" | "commit" | "cancel" | "open" | "resume";
  methods: string[];
  syncId?: string;
  recoveryId?: string;
  recoveryOperation?: string;
  inviteId?: string;
  personId?: string;
  deviceId?: string;
  logOperation?: string;
  logHead?: string;
  logAfter?: number;
};

const id16 = (v: string | undefined): v is string => v !== undefined && decodeB64Url(v, 16) !== null;

/** The single v2 route map, shared by dispatch and CORS; never touches bindings. */
export function matchV2(path: string): V2Route | null {
  const p = path.split("/");
  if (p[0] === "" && p[1] === "v2" && p[2] === "recoveries" && key32(p[3])) {
    if (p.length === 4) return { recoveryId: p[3], resource: "recovery", methods: ["GET"] };
    if (p.length === 5 && p[4] === "claim") return { recoveryId: p[3], resource: "recoveryClaim", methods: ["POST"] };
    return null;
  }
  if (p[0] !== "" || p[1] !== "v2" || !id16(p[3])) return null;
  if (p[2] === "invites") {
    if (p.length !== 5) return null;
    if (p[4] === "offer" || p[4] === "result") return { inviteId: p[3], resource: p[4], methods: ["GET"] };
    if (p[4] === "checkpoint") return { inviteId: p[3], resource: "checkpoint", methods: ["GET", "DELETE"] };
    if (p[4] === "answer" || p[4] === "withdraw") return { inviteId: p[3], resource: p[4], methods: ["POST"] };
    return null;
  }
  if (p[2] !== "lists") return null;
  const syncId = p[3];
  if (p[4] === "recoveries") {
    if (p.length === 5) return { syncId, resource: "recoveries", methods: ["GET"] };
    if (!key32(p[5])) return null;
    const recoveryId = p[5];
    if (p.length === 6) return { syncId, recoveryId, resource: "recovery", methods: ["PUT", "DELETE"] };
    if (p.length === 7 && p[6] === "rotation") return { syncId, recoveryId, resource: "recoveryRotation", methods: ["POST"] };
    if (p.length === 9 && p[6] === "rotation" && id16(p[7]) && p[8] === "commit") return { syncId, recoveryId, recoveryOperation: p[7], resource: "recoveryCommit", methods: ["POST"] };
    return null;
  }
  if (p.length === 4) return { syncId, resource: "list", methods: ["GET", "PUT", "DELETE"] };
  if (p.length === 9 && p[4] === "renewal" && p[5] === "log" && id16(p[6]) && key32(p[7]) && /^(0|[1-9][0-9]{0,5})$/.test(p[8]!)) return { syncId, resource: "renewal", logOperation: p[6], logHead: p[7], logAfter: Number(p[8]), methods: ["GET"] };
  if (p.length === 5) {
    if (p[4] === "renewal") return { syncId, resource: "renewal", methods: ["GET", "PUT"] };
    if (p[4] === "common") return { syncId, resource: "common", methods: ["PUT"] };
    if (p[4] === "ws") return { syncId, resource: "ws", methods: ["GET"] };
    if (p[4] === "revoke" || p[4] === "invites" || p[4] === "capability") return { syncId, resource: p[4], methods: ["POST"] };
    return null;
  }
  if (p[4] === "guards" && p.length === 7 && identifier(p[5])) {
    const action = p[6];
    if (action === "prepare" || action === "commit" || action === "cancel" || action === "open" || action === "resume") {
      return { syncId, resource: "guard", deviceId: p[5], action, methods: [action === "prepare" ? "PUT" : "POST"] };
    }
  }
  if (p[4] === "slots" && p.length === 7 && identifier(p[5]) && identifier(p[6])) {
    return { syncId, resource: "slot", personId: p[5], deviceId: p[6], methods: ["GET"] };
  }
  if (p[4] === "invites" && id16(p[5])) {
    if (p.length === 6) return { syncId, inviteId: p[5], resource: "invite", methods: ["GET", "DELETE"] };
    if (p.length === 7 && (p[6] === "reveal" || p[6] === "approve")) return { syncId, inviteId: p[5], resource: p[6], methods: ["POST"] };
  }
  return null;
}
