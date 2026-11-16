import { exports } from "cloudflare:workers";

export function b64u(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export const randomIp = () => `10.${Math.floor(Math.random() * 256)}.${Math.floor(Math.random() * 256)}.${Math.floor(Math.random() * 256)}`;

export const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

let counter = 0;
/** A fresh list identity and a fresh client IP, so tests never share state or rate limits. */
export function newList() {
  counter++;
  return {
    syncId: b64u(rand(16)), // what the client derives with HKDF: 16 bytes, 22 characters
    key: b64u(rand(32)),
    ip: `10.${(counter >> 8) & 255}.${counter & 255}.${Math.floor(Math.random() * 250) + 1}`,
  };
}
export type Ident = ReturnType<typeof newList>;

export const envelope = (n = 64) => b64u(rand(n));

interface CallOptions {
  key?: string | null;
  body?: unknown;
  rawBody?: string;
  ip?: string;
  headers?: Record<string, string>;
}

export async function call(method: string, path: string, opts: CallOptions = {}): Promise<Response> {
  const headers = new Headers(opts.headers);
  if (opts.key) headers.set("Authorization", `Bearer ${opts.key}`);
  headers.set("CF-Connecting-IP", opts.ip ?? randomIp());
  let body: string | undefined = opts.rawBody;
  if (body === undefined && opts.body !== undefined) body = JSON.stringify(opts.body);
  if (body !== undefined && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  return exports.default.fetch(new Request(`https://sync.test${path}`, { method, headers, body }));
}

export async function json<T = Record<string, unknown>>(res: Response): Promise<T> {
  return (await res.json()) as T;
}
