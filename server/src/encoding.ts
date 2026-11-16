const B64URL = /^[A-Za-z0-9_-]*$/;

export function encodeB64Url(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]!);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** Strict base64url (no padding, canonical). Returns null if `s` is not that, or not `length` bytes. */
export function decodeB64Url(s: string, length?: number): Uint8Array | null {
  if (!B64URL.test(s) || s.length % 4 === 1) return null;
  const std = s.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (s.length % 4)) % 4);
  let bin: string;
  try {
    bin = atob(std);
  } catch {
    return null;
  }
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  if (length !== undefined && out.length !== length) return null;
  if (encodeB64Url(out) !== s) return null; // non-canonical trailing bits
  return out;
}

/** Cheap shape check for the stored envelope: it is never decoded by the server. */
export function isB64UrlText(s: string): boolean {
  return s.length > 0 && s.length % 4 !== 1 && B64URL.test(s);
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

export function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

/** Constant time for equal lengths; different lengths are not a secret here (always 32). */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

export function asBytes(v: unknown): Uint8Array {
  return v instanceof Uint8Array ? v : new Uint8Array(v as ArrayBuffer);
}
