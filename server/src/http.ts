import { V2_BODY_READ_DEADLINE_MS } from "./limits";
/** What a Durable Object hands back to the Worker, which turns it into a Response. */
export interface ApiResult {
  status: number;
  body?: Record<string, unknown>;
  headers?: Record<string, string>;
}

export const err = (status: number, code: string, headers?: Record<string, string>): ApiResult => ({
  status,
  body: { error: code },
  headers,
});

export const NOT_FOUND = err(404, "not_found");
export const UNAUTHORIZED = err(401, "unauthorized");

export function toResponse(r: ApiResult): Response {
  const headers = new Headers(r.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  if (!headers.has("Cache-Control")) headers.set("Cache-Control", "no-store, no-transform");
  if (r.body === undefined || r.status === 204 || r.status === 304) {
    return new Response(null, { status: r.status, headers });
  }
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(r.body), { status: r.status, headers });
}

export type BodyResult = { ok: true; value: Record<string, unknown> } | { ok: false; result: ApiResult };

/** Reads a JSON object body with a hard byte cap, counted while streaming. */
export async function readJsonObject(request: Request, maxBytes: number, timeoutMs = V2_BODY_READ_DEADLINE_MS): Promise<BodyResult> {
  const type = request.headers.get("Content-Type") ?? "";
  if (!/^application\/json\s*(;|$)/i.test(type)) return { ok: false, result: err(415, "unsupported_media_type") };
  const declared = request.headers.get("Content-Length");
  if (declared !== null && Number(declared) > maxBytes) return { ok: false, result: err(413, "too_large") };
  if (!request.body) return { ok: false, result: err(400, "bad_request") };

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let expired = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { expired = true; reject(new Error("Body deadline")); }, timeoutMs); });
  try {
    for (;;) {
      const { done, value } = await Promise.race([reader.read(), timeout]);
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        void reader.cancel().catch(() => undefined);
        return { ok: false, result: err(413, "too_large") };
      }
      chunks.push(value);
    }
  } catch {
    void reader.cancel().catch(() => undefined);
    return { ok: false, result: err(expired ? 408 : 400, "bad_request") };
  } finally { if (timer !== undefined) clearTimeout(timer); }
  const all = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    all.set(c, offset);
    offset += c.byteLength;
  }
  try {
    const parsed: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(all));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return { ok: false, result: err(400, "bad_request") };
    }
    return { ok: true, value: parsed as Record<string, unknown> };
  } catch {
    return { ok: false, result: err(400, "bad_request") };
  }
}
