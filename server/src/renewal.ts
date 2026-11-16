import { decodeB64Url, encodeB64Url, sha256 } from "./encoding";
import { err, type ApiResult } from "./http";
import { bytes, canonicalJson, identifier, key32, object, type V2Device } from "./v2-contract";
import { V2_MAX_RENEWAL_BODY_BYTES, V2_MAX_RENEWAL_STATE_BYTES, V2_MAX_RENEWAL_PARTICIPANTS, V2_MAX_RENEWAL_BRANCHES, V2_RENEWAL_ABSENCE_MS, V2_RENEWAL_LOG_COMMANDS, V2_RENEWAL_LOG_BYTES, V2_RENEWAL_RESCUE_COMMANDS_PER_SIGNER, V2_RENEWAL_RESCUE_BYTES_PER_SIGNER, V2_RENEWAL_REFILL_COMMANDS, V2_RENEWAL_REFILL_BYTES, V2_RENEWAL_LOG_MAX_COMMANDS, V2_RENEWAL_LOG_MAX_BYTES } from "./limits";

/** The Worker authenticates every append with the credential-bound key.
 * Phones independently verify historical trust and the complete signed chain. */
export type RenewalCommand = Record<string, unknown> & {
  v: 1;
  action: "reserve" | "replace" | "recover" | "revise" | "ready" | "ack" | "exclude" | "prepare" | "confirm" | "abort" | "revoke" | "resume" | "capability";
  operationId: string;
  sourceSyncId: string;
  targetSyncId: string;
  revision: number;
  sourceVersion: number;
  signerDeviceId: string;
  signature: string;
  prev: string | null;
};
export type RenewalState = {
  head: string | null;
  height: number;
  logBytes: number;
  operationId: string;
  sourceSyncId: string;
  targetSyncId: string;
  revision: number;
  participants: string[];
  /** Replaced destinations are retained as recovery references, never deleted. */
  branches: string[];
  /** Most recent recovery transition; its predecessors remain in the log. */
  recovery: RenewalCommand | null;
  plan: RenewalCommand;
  /** Original destination identity commitment, retained across revalidation. */
  reservation: RenewalCommand;
  /** Internal compatibility views only; never persisted in the projection. */
  identities: RenewalCommand[];
  revokedIdentities: Record<string, RenewalCommand>;
  /** Signed evidence for a barrier retained across invalidation/revision. */
  barrier: RenewalCommand | null;
  abortion: RenewalCommand | null;
  ready: RenewalCommand | null;
  acknowledgements: Record<string, RenewalCommand>;
  /** Receipts retained at revalidation; fresh receipts remain in acknowledgements. */
  transfers: Record<string, RenewalCommand>;
  exclusions: Record<string, RenewalCommand>;
  preparation: RenewalCommand | null;
  confirmation: RenewalCommand | null;
  barrierVersion: number | null;
  confirmedVersion: number | null;
  needsRevalidation: boolean;
};
export type RenewalContext = {
  syncId: string;
  version: number;
  caller: V2Device;
  devices: V2Device[];
  /** All source signing keys in the stored registry (including revoked ones). */
  signingKeys: string[];
  lastRequests?: Record<string, number>;
  now?: number;
  commands?: RenewalCommand[];
  commandHash?: string;
  history?: RenewalHistory;
};
/** Indexed service history; no full-log read is needed on append. */
export type RenewalHistory = {
  exact: (hash: string) => boolean;
  target: (target: string) => boolean;
  identity: (c: RenewalCommand, sameOwner?: boolean) => boolean;
  liveAck: (devices: V2Device[]) => boolean;
  resumed: (signer: string) => boolean;
  usage: (signer: string) => { count: number; bytes: number; afterRevoke: boolean };
};

export async function verifyRenewalSignature(c: RenewalCommand, signingKey: string): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey("raw", decodeB64Url(signingKey, 32)!, "Ed25519", false, ["verify"]);
    const { signature, ...unsigned } = c;
    return await crypto.subtle.verify("Ed25519", key, decodeB64Url(signature, 64)!,
      new TextEncoder().encode(`gift-huddle-renewal-control-v2\0${canonicalJson(unsigned)}`));
  } catch { return false; }
}

type Outcome = { ok: true; state: RenewalState; unchanged: boolean } | { ok: false; error: ApiResult };
const fail = (code: string, status = 409): Outcome => ({ ok: false, error: err(status, code) });
const id16 = (v: unknown): v is string => typeof v === "string" && decodeB64Url(v, 16) !== null;
const positive = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) > 0;
const base = ["v", "action", "operationId", "sourceSyncId", "targetSyncId", "revision", "sourceVersion", "signerDeviceId", "signature", "prev"];
const fields: Record<RenewalCommand["action"], string[]> = {
  reserve: ["participants", "newDeviceId", "newSigningKey", "targetCommitment", "inventoryCommitment"],
  replace: ["participants", "newDeviceId", "newSigningKey", "targetCommitment", "inventoryCommitment", "previousTargetSyncId"],
  recover: ["participants", "newDeviceId", "newSigningKey", "targetCommitment", "inventoryCommitment", "previousTargetSyncId"],
  revise: ["participants", "inventoryCommitment"],
  ready: ["destinationVersion"],
  ack: ["newDeviceId", "newSigningKey", "receipt", "destinationVersion"],
  exclude: ["participantDeviceId", "loss", "receipt"],
  prepare: ["pendingResources", "coverageCommitment"],
  confirm: ["snapshotVersion", "pendingResources", "coverageCommitment"],
  abort: [],
  revoke: ["participantDeviceId"],
  resume: [],
  capability: ["commonFormat"],
};

/** Strict public wire validator, also used to avoid unbounded persisted input. */
export function renewalCommand(v: unknown): v is RenewalCommand {
  if (!object(v) || v.v !== 1 || typeof v.action !== "string" || !Object.hasOwn(fields, v.action)) return false;
  const extra = fields[v.action as RenewalCommand["action"]]!;
  if (v.prev !== null && !key32(v.prev)) return false;
  if (Object.keys(v).length !== base.length + extra.length || [...base, ...extra].some((k) => !Object.hasOwn(v, k))) return false;
  if (!id16(v.operationId) || !id16(v.sourceSyncId) || !id16(v.targetSyncId) || v.sourceSyncId === v.targetSyncId ||
    !positive(v.revision) || !positive(v.sourceVersion) || !identifier(v.signerDeviceId) ||
    typeof v.signature !== "string" || decodeB64Url(v.signature, 64) === null) return false;
  if (extra.includes("participants") && (!Array.isArray(v.participants) || v.participants.length === 0 ||
    v.participants.length > V2_MAX_RENEWAL_PARTICIPANTS || !v.participants.every(identifier) || new Set(v.participants).size !== v.participants.length)) return false;
  if (extra.includes("newDeviceId") && (!identifier(v.newDeviceId) || !key32(v.newSigningKey))) return false;
  if (extra.includes("destinationVersion") && !positive(v.destinationVersion)) return false;
  if (extra.includes("snapshotVersion") && !positive(v.snapshotVersion)) return false;
  if (extra.includes("participantDeviceId") && (!identifier(v.participantDeviceId) || (v.action === "exclude" && v.loss !== true))) return false;
  if (extra.includes("pendingResources") && v.pendingResources !== 0) return false;
  if (extra.includes("previousTargetSyncId") && !id16(v.previousTargetSyncId)) return false;
  if (v.action === "capability" && v.commonFormat !== 2) return false;
  return ["targetCommitment", "inventoryCommitment", "receipt", "coverageCommitment"].every((k) => !extra.includes(k) || key32(v[k]));
}

const same = (a: unknown, b: unknown) => canonicalJson(a) === canonicalJson(b);
const migrated = (s: RenewalState, device: string) => Object.hasOwn(s.acknowledgements, device) && !Object.hasOwn(s.exclusions, device);
const transferred = (s: RenewalState, device: string) => Object.hasOwn(s.transfers, device) && !Object.hasOwn(s.exclusions, device);
export const renewalIdentities = (s: RenewalState): RenewalCommand[] =>
  [...s.identities, s.reservation, ...Object.values(s.transfers), ...Object.values(s.acknowledgements), ...Object.values(s.revokedIdentities)];
export function renewalResolved(s: RenewalState, devices: V2Device[]): boolean {
  return s.participants.every((id) => Object.hasOwn(s.exclusions, id) ||
    (migrated(s, id) && !devices.some((d) => d.deviceId === id && d.revoked)));
}
export const renewalCanClose = (s: RenewalState, caller: V2Device, devices: V2Device[], version: number): boolean =>
  !caller.revoked && !devices.some((d) => d.deviceId === s.reservation.signerDeviceId && d.revoked) &&
  s.abortion === null && caller.role === "device" && migrated(s, caller.deviceId) && !s.needsRevalidation &&
  s.confirmation !== null && s.confirmedVersion === version && renewalResolved(s, devices);

/** Revocation never removes the content barrier; it invalidates the signed plan.
 * A signed revise and fresh receipts are required, even after prepare/confirm. */
export function invalidateRenewal(s: RenewalState): void {
  s.needsRevalidation = true;
  s.preparation = null;
  s.confirmation = null;
  s.confirmedVersion = null;
}

export function transitionRenewal(current: RenewalState | null, input: Record<string, unknown>, ctx: RenewalContext): Outcome {
  if (bytes(input) > V2_MAX_RENEWAL_BODY_BYTES) return fail("too_large", 413);
  if (!renewalCommand(input)) return fail("bad_renewal", 400);
  const c = input;
  const h = ctx.history;
  if (c.sourceSyncId !== ctx.syncId || c.signerDeviceId !== ctx.caller.deviceId) return fail("renewal_context_mismatch", 403);
  if (ctx.caller.role !== "device" && !["ack", "resume", "capability"].includes(c.action)) return fail("forbidden_role", 403);
  if (ctx.caller.revoked) return fail("forbidden_role", 403);
  // Recovery of a response lost after commit, including with an old If-Match.
  // Scope checking precedes equality; a receipt from another revision never wins.
  if (current && current.operationId === c.operationId && current.targetSyncId === c.targetSyncId && current.revision === c.revision) {
    const recorded = ctx.commands ?? [current.plan, current.reservation, current.ready, current.preparation, current.confirmation,
      current.abortion, ...Object.values(current.acknowledgements), ...Object.values(current.exclusions)];
    if (h ? h.exact(ctx.commandHash!) : recorded.some((old) => old !== null && same(old, c))) return { ok: true, state: current, unchanged: true };
  }
  if (c.sourceVersion !== ctx.version) return fail("precondition_failed", 412);
  if (current?.abortion) {
    if (c.action !== "reserve" || c.operationId === current.operationId) return fail("renewal_aborted");
    current = null;
  }
  if (c.prev !== (current?.head ?? null)) return fail("renewal_prev_mismatch");
  if (current && current.operationId !== c.operationId) return fail("renewal_exists");
  if (current && ["replace", "recover"].includes(c.action) && (h ? h.target(c.targetSyncId) : (ctx.commands ?? []).some((old) =>
      ["reserve", "replace", "recover"].includes(old.action) && old.targetSyncId === c.targetSyncId))) return fail("renewal_identity_reused");
  let s: RenewalState;
  const replacing = c.action === "replace" || c.action === "recover";
  if (c.action === "reserve" || replacing || c.action === "revise") {
    const participants = c.participants as string[];
    // Local-only records can be included, but no known live service participant
    // (including a web with a queue) may silently disappear from the plan.
    if (ctx.devices.some((d) => !d.revoked && !participants.includes(d.deviceId)) || !participants.includes(ctx.caller.deviceId)) return fail("renewal_participants_missing");
    if (current && current.participants.some((d) => !participants.includes(d))) return fail("renewal_participants_missing");
    if (c.action === "reserve") {
      if (current) return fail("renewal_exists");
      if (c.revision !== 1) return fail("renewal_revision");
    } else {
      if (!current || c.revision !== current.revision + 1) return fail("renewal_revision");
      if (Object.hasOwn(current.exclusions, ctx.caller.deviceId)) return fail("renewal_excluded", 403);
      if (c.action === "revise" && ctx.devices.some((d) => d.deviceId === current!.reservation.signerDeviceId && d.revoked)) return fail("renewal_replace_required");
      if (replacing && Object.keys(current.transfers).length > 0 && !transferred(current, ctx.caller.deviceId) && !current.needsRevalidation) return fail("renewal_not_migrated", 403);
      if (c.action === "recover" && (!ctx.devices.some((d) => d.deviceId === current!.reservation.signerDeviceId && d.revoked))) return fail("renewal_recovery_mismatch");
      if (c.action === "revise" && c.targetSyncId !== current.targetSyncId) return fail("renewal_context_mismatch");
      if (replacing && (c.previousTargetSyncId !== current.targetSyncId || c.targetSyncId === current.targetSyncId || current.branches.includes(c.targetSyncId))) return fail("renewal_context_mismatch");
    }
    if (c.action !== "revise" && (ctx.devices.some((d) => d.deviceId === c.newDeviceId) || ctx.signingKeys.includes(c.newSigningKey as string))) return fail("renewal_identity_reused");
    if (c.action !== "revise" && current && (h ? h.identity(c) : (ctx.commands ?? renewalIdentities(current))
      .some((old) => old.newDeviceId === c.newDeviceId || old.newSigningKey === c.newSigningKey))) return fail("renewal_identity_reused");
    const branches = c.action === "recover" ? [] : [...(current?.branches ?? [])];
    if (c.action === "replace" && Object.keys(current!.transfers).length > 0) branches.push(current!.targetSyncId);
    if (branches.length > V2_MAX_RENEWAL_BRANCHES) return fail("renewal_branches_full");
    const keepBarrier = !replacing || (current !== null && (h ? h.liveAck(ctx.devices) : (ctx.commands ?? renewalIdentities(current)).some((old) => old.action === "ack" && ctx.devices.some((d) => d.deviceId === old.signerDeviceId && !d.revoked))));
    s = {
      head: current?.head ?? null, height: current?.height ?? 0, logBytes: current?.logBytes ?? 0,
      operationId: c.operationId, sourceSyncId: c.sourceSyncId, targetSyncId: c.targetSyncId,
      revision: c.revision, participants, branches, plan: c, reservation: c.action === "revise" ? current!.reservation : c, ready: null,
      recovery: c.action === "recover" ? c : current?.recovery ?? null,
      identities: [],
      revokedIdentities: {}, abortion: null,
      barrier: keepBarrier ? current?.barrier ?? null : null,
      acknowledgements: Object.create(null) as Record<string, RenewalCommand>, exclusions: Object.create(null) as Record<string, RenewalCommand>,
      transfers: c.action === "revise" ? { ...current!.transfers, ...current!.acknowledgements } : {},
      preparation: null, confirmation: null, barrierVersion: keepBarrier ? current?.barrierVersion ?? null : null,
      confirmedVersion: null, needsRevalidation: false,
    };
  } else {
    if (!current || c.targetSyncId !== current.targetSyncId || c.revision !== current.revision) return fail("renewal_context_mismatch");
    if (current.needsRevalidation && !["abort", "revoke", "resume", "capability"].includes(c.action)) return fail("renewal_revalidation_required");
    // Signed commands are immutable evidence. Copy the mutable projection maps
    // while retaining command references and their already indexed hashes.
    s = { ...current, acknowledgements: { ...current.acknowledgements },
      transfers: { ...current.transfers }, exclusions: { ...current.exclusions } };
    if (c.action === "revoke") {
      const id = c.participantDeviceId as string;
      if (id === c.signerDeviceId || !ctx.devices.some((d) => d.deviceId === id && !d.revoked)) return fail("renewal_invalid_state");
      delete s.exclusions[c.signerDeviceId];
      invalidateRenewal(s);
    } else if (c.action === "resume") {
      if (!Object.hasOwn(s.exclusions, c.signerDeviceId)) return fail("renewal_invalid_state");
      if (h ? h.resumed(c.signerDeviceId) : (ctx.commands ?? []).some((old) => old.action === "resume" && old.signerDeviceId === c.signerDeviceId)) return fail("renewal_resume_used");
      delete s.exclusions[c.signerDeviceId];
      invalidateRenewal(s);
    } else if (c.action === "capability") {
      if (ctx.caller.commonFormat === 2) return fail("renewal_invalid_state");
    } else if (c.action === "abort") {
      if (s.recovery != null || Object.keys(s.transfers).length > 0 || s.branches.length > 0 || s.barrierVersion !== null) return fail("renewal_invalid_state");
      s.abortion = c;
    } else if (c.action === "ready") {
      if (c.signerDeviceId !== s.reservation.signerDeviceId && !transferred(s, c.signerDeviceId)) return fail("renewal_not_initiator", 403);
      if (s.ready !== null || s.preparation !== null || s.confirmation !== null) return fail("renewal_invalid_state");
      s.ready = c;
    } else {
      if (s.ready === null) return fail("renewal_not_ready");
      if (c.action === "ack") {
        if (!s.participants.includes(ctx.caller.deviceId) || s.confirmation !== null || Object.hasOwn(s.exclusions, ctx.caller.deviceId)) return fail("renewal_invalid_state");
        if ((c.destinationVersion as number) < (s.ready.destinationVersion as number)) return fail("renewal_invalid_state");
        if (Object.hasOwn(s.acknowledgements, ctx.caller.deviceId)) return fail("renewal_ack_exists");
        if (s.reservation.signerDeviceId !== c.signerDeviceId &&
          (s.reservation.newDeviceId === c.newDeviceId || s.reservation.newSigningKey === c.newSigningKey)) return fail("renewal_identity_reused");
        if (ctx.devices.some((d) => d.deviceId === c.newDeviceId) || ctx.signingKeys.includes(c.newSigningKey as string) ||
          (h ? h.identity(c, true) : (ctx.commands ?? renewalIdentities(s)).some((a) =>
            (a.targetSyncId !== c.targetSyncId || a.signerDeviceId !== c.signerDeviceId) &&
            (a.newDeviceId === c.newDeviceId || a.newSigningKey === c.newSigningKey))) ||
          [...Object.values(s.transfers), ...Object.values(s.revokedIdentities)].some((a) => a.signerDeviceId !== c.signerDeviceId && (a.newDeviceId === c.newDeviceId || a.newSigningKey === c.newSigningKey))) return fail("renewal_identity_reused");
        const oldTransfer = Object.hasOwn(s.transfers, c.signerDeviceId) ? s.transfers[c.signerDeviceId] : undefined;
        if (oldTransfer && (oldTransfer.newDeviceId !== c.newDeviceId || oldTransfer.newSigningKey !== c.newSigningKey)) return fail("renewal_context_mismatch");
        // The preparer's destination identity is committed before reservation.
        if (s.reservation.signerDeviceId === c.signerDeviceId &&
          (s.reservation.newDeviceId !== c.newDeviceId || s.reservation.newSigningKey !== c.newSigningKey)) return fail("renewal_context_mismatch");
        Object.defineProperty(s.acknowledgements, ctx.caller.deviceId, { value: c, enumerable: true, writable: true, configurable: true });
        if (!oldTransfer) Object.defineProperty(s.transfers, ctx.caller.deviceId, { value: c, enumerable: true, writable: true, configurable: true });
      } else {
        if (!migrated(s, ctx.caller.deviceId)) return fail("renewal_not_migrated", 403);
        if (c.action === "exclude") {
          const id = c.participantDeviceId as string;
          if (!s.participants.includes(id) || id === ctx.caller.deviceId || s.preparation !== null || s.confirmation !== null) return fail("renewal_invalid_state");
          if (transferred(s, id) && !ctx.devices.some((d) => d.deviceId === id && d.revoked)) return fail("renewal_already_migrated");
          if (Object.hasOwn(s.acknowledgements, id)) return fail("renewal_already_migrated");
          // Legacy credentials start their inactivity window at first observation.
          const last = ctx.lastRequests?.[id] ?? ctx.now ?? Date.now();
          if (!ctx.devices.some((d) => d.deviceId === id && d.revoked) && (ctx.now ?? Date.now()) - last < V2_RENEWAL_ABSENCE_MS) return fail("renewal_participant_active");
          if (Object.hasOwn(s.exclusions, id)) return fail("renewal_exclusion_exists");
          Object.defineProperty(s.exclusions, id, { value: c, enumerable: true, writable: true, configurable: true });
        } else {
          if (!renewalResolved(s, ctx.devices)) return fail("renewal_participants_pending");
          if (c.action === "prepare") {
            if (s.preparation !== null || s.confirmation !== null) return fail("renewal_invalid_state");
            s.preparation = c;
            // Includes the control write itself; the content is frozen atomically.
            s.barrierVersion = ctx.version + 1;
            s.barrier = c;
          } else {
            if (s.preparation === null || c.snapshotVersion !== s.barrierVersion) return fail("renewal_snapshot_mismatch");
            s.confirmation = c;
            s.confirmedVersion = ctx.version + 1;
          }
        }
      }
    }
  }
  s.height++;
  s.logBytes += bytes(c);
  s.head = ctx.commandHash ?? s.head;
  if (s.height > V2_RENEWAL_LOG_MAX_COMMANDS || s.logBytes > V2_RENEWAL_LOG_MAX_BYTES) return fail("renewal_log_full");
  if (s.height > V2_RENEWAL_LOG_COMMANDS || s.logBytes > V2_RENEWAL_LOG_BYTES) {
    if (c.action === "replace" || (c.action === "revise" && !current?.needsRevalidation)) return fail("renewal_log_full");
    // Rescue is isolated per signer; effective revocations refill survivors.
    if (!["recover", "revoke", "abort"].includes(c.action)) {
      let count = 0, used = 0, afterRevoke = false;
      if (h) {
        const u = h.usage(c.signerDeviceId); count = u.count; used = u.bytes; afterRevoke = u.afterRevoke;
      } else {
        let height = 0, total = 0;
        for (const old of ctx.commands ?? []) {
          height++; const weight = bytes(old); total += weight;
          if (old.action === "revoke") { count = 0; used = 0; afterRevoke = true; }
          if ((height > V2_RENEWAL_LOG_COMMANDS || total > V2_RENEWAL_LOG_BYTES) &&
              old.signerDeviceId === c.signerDeviceId && !["recover", "revoke", "abort"].includes(old.action)) { count++; used += weight; }
        }
      }
      // Every revocation grants each survivor a complete 40-command exit:
      // optional resume + revise + ready + ack + 31 losses + prepare + confirm.
      if (count >= (afterRevoke ? V2_RENEWAL_REFILL_COMMANDS : V2_RENEWAL_RESCUE_COMMANDS_PER_SIGNER) ||
          used + bytes(c) > (afterRevoke ? V2_RENEWAL_REFILL_BYTES : V2_RENEWAL_RESCUE_BYTES_PER_SIGNER)) return fail("renewal_log_full");
    }
  }
  if (bytes(renewalProjection(s, () => "x".repeat(43))) > V2_MAX_RENEWAL_STATE_BYTES) return fail("renewal_full", 413);
  return { ok: true, state: s, unchanged: false };
}

/** SHA-256 of UTF-8 canonical JSON INCLUDING the signature, unpadded base64url. */
export async function renewalHash(command: RenewalCommand): Promise<string> {
  return encodeB64Url(await sha256(new TextEncoder().encode(canonicalJson(command))));
}

/** The active row carries references, never a growing collection of evidence. */
export function renewalProjection(s: RenewalState, digest: (c: RenewalCommand) => string): Record<string, unknown> {
  const value: Record<string, unknown> = { ...s };
  delete value.identities;
  delete value.revokedIdentities;
  for (const key of ["plan", "reservation", "recovery", "barrier", "abortion", "ready", "preparation", "confirmation"] as const) {
    value[key] = s[key] === null ? null : digest(s[key]!);
  }
  for (const key of ["acknowledgements", "transfers", "exclusions"] as const) {
    value[key] = Object.fromEntries(Object.entries(s[key]).map(([id, c]) => [id, digest(c)]));
  }
  return value;
}
