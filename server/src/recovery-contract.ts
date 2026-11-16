import { decodeB64Url, encodeB64Url, sha256 } from "./encoding";
import { err, type ApiResult } from "./http";
import { RECOVERY_MAX_BYTES, RECOVERY_MAX_HEADER_BYTES } from "./limits";
import { canonicalJson, identifier, key32, object } from "./v2-contract";

export const operationId = (v: unknown): v is string => typeof v === "string" && decodeB64Url(v, 16) !== null;
export const revision = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
export const recoveryEtag = (n: number): string => `"${n}"`;
export const recoveryCas = (match: string | null): number | null => {
  if (match === null || !/^"(0|[1-9][0-9]*)"$/.test(match)) return null;
  const n = Number(match.slice(1, -1));
  return revision(n) ? n : null;
};
export const exact = (b: Record<string, unknown>, fields: string[]): boolean =>
  Object.keys(b).length === fields.length && fields.every((f) => Object.hasOwn(b, f));

/** Domain separation is identical to ADR 0007; the capability never reaches storage. */
export async function recoveryReadVerifier(cap: string): Promise<string> {
  const prefix = new TextEncoder().encode("gift-huddle-recovery-read-verifier-v2\0");
  const input = new Uint8Array(prefix.length + 32);
  input.set(prefix);
  input.set(decodeB64Url(cap, 32)!, prefix.length);
  return encodeB64Url(await sha256(input));
}
export async function recoveryFingerprint(body: Record<string, unknown>, expectedRevision: number | null): Promise<string> {
  return encodeB64Url(await sha256(new TextEncoder().encode(canonicalJson({ body, expectedRevision }))));
}

/** Only the authenticated envelope is inspected. No Argon2, decryption or plaintext. */
export function validateCapsule(text: unknown, rid: string, expected: number): ApiResult | null {
  if (typeof text !== "string") return err(400, "invalid_recovery");
  if (Math.floor(text.length * 3 / 4) > RECOVERY_MAX_BYTES) return err(413, "recovery_too_large");
  // Inspect the alphabet and canonical trailing bits without allocating or
  // re-encoding the (up to 1 MiB) ciphertext. Only decode the bounded header.
  const remainder = text.length % 4;
  if (remainder === 1 || !/^[A-Za-z0-9_-]+$/.test(text) || (remainder !== 0 && !decodeB64Url(text.slice(-remainder)))) return err(400, "invalid_recovery");
  const prefix = decodeB64Url(text.slice(0, 8));
  const length = Math.floor(text.length * 3 / 4);
  if (!prefix || prefix.length !== 6 || length < 6 + 12 + 16 || prefix[0] !== 0x47 || prefix[1] !== 0x48 || prefix[2] !== 0x52 || prefix[3] !== 2) return err(400, "invalid_recovery");
  const size = prefix[4]! * 256 + prefix[5]!;
  if (size > RECOVERY_MAX_HEADER_BYTES || size === 0 || length < 6 + size + 12 + 16) return err(400, "invalid_recovery");
  const bin = decodeB64Url(text.slice(0, Math.ceil((6 + size) / 3) * 4))!;
  try {
    const headerText = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bin.subarray(6, 6 + size));
    const h: unknown = JSON.parse(headerText);
    if (!object(h) || !exact(h, ["k", "kdf", "rid", "r", "s", "v"]) || h.v !== 2 || h.k !== "capsule" || h.rid !== rid || h.r !== expected || !revision(h.r) || h.r < 1 || typeof h.s !== "string" || !decodeB64Url(h.s, 16) || !object(h.kdf) || !exact(h.kdf, ["a", "m", "p", "t"]) || h.kdf.a !== "argon2id" || h.kdf.m !== 19456 || h.kdf.p !== 1 || h.kdf.t !== 2 || canonicalJson(h) !== headerText) return err(400, "invalid_recovery");
    return null;
  } catch {
    return err(400, "invalid_recovery");
  }
}

/** Superficial validation precedes discovery; CAS and envelope semantics follow cap authentication. */
export function recoveryShape(kind: "put" | "claim" | "prepare" | "commit", b: Record<string, unknown>): boolean {
  if (b.v !== 2) return false;
  if (kind === "commit") return exact(b, ["v"]);
  if (typeof b.capsule !== "string") return false;
  if (kind === "put") return exact(b, ["v", "deviceId", "readVerifier", "capsule"]) && identifier(b.deviceId) && key32(b.readVerifier);
  if (kind === "claim") return exact(b, ["v", "operationId", "newCredentialVerifier", "capsule"]) && typeof b.operationId === "string" && typeof b.newCredentialVerifier === "string";
  return exact(b, ["v", "operationId", "newRecoveryId", "readVerifier", "capsule"]) && operationId(b.operationId) && key32(b.newRecoveryId) && key32(b.readVerifier);
}
