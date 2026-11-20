import { err, toResponse } from "./http";
import { matchV2 } from "./v2-contract";

const REQUEST_HEADERS = ["authorization", "content-type", "if-none-match", "x-public-key"];

export function allowedOrigin(request: Request, configured: string): boolean {
  const origin = request.headers.get("Origin");
  return origin === null || (origin !== "null" && configured.split(",").map((o) => o.trim()).includes(origin));
}

export function preflight(request: Request): Response {
  const path = new URL(request.url).pathname;
  const v2 = path.startsWith("/v2/");
  const match = v2 ? matchV2(path) : null;
  if (!match || "error" in match) return toResponse(err(404, "not_found"));
  const { methods } = match;
  const method = request.headers.get("Access-Control-Request-Method");
  if (!request.headers.has("Origin") || method === null || !methods.includes(method)) {
    return toResponse(err(405, "method_not_allowed", { Allow: methods.join(", ") }));
  }
  const headers = (request.headers.get("Access-Control-Request-Headers") ?? "")
    .split(",").map((h) => h.trim().toLowerCase()).filter(Boolean);
  if (headers.some((h) => !REQUEST_HEADERS.includes(h) && !(v2 && h === "if-match"))) return toResponse(err(403, "forbidden"));
  return new Response(null, { status: 204, headers: {
    "Access-Control-Allow-Methods": methods.join(", "),
    "Access-Control-Allow-Headers": "Authorization, Content-Type, If-None-Match, X-Public-Key" + (v2 ? ", If-Match" : ""),
    "Access-Control-Max-Age": "600",
  } });
}

/** Also wraps upgrades, preserving the accepted socket and fixed subprotocol. */
export function apiHeaders(response: Response, request: Request, configured: string): Response {
  const headers = new Headers(response.headers);
  // no-transform: Cloudflare would compress big snapshots and turn the strong ETag into W/"n",
  // which the app rejects (early test clients failed to pair behind the proxy).
  headers.set("Cache-Control", "no-store, no-transform");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  const vary = headers.get("Vary");
  headers.set("Vary", vary ? `${vary}, Origin` : "Origin");
  const origin = request.headers.get("Origin");
  if (origin !== null && allowedOrigin(request, configured)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Expose-Headers", "ETag, Retry-After");
  }
  return new Response(response.body, {
    status: response.status, statusText: response.statusText, headers,
    ...(response.webSocket ? { webSocket: response.webSocket } : {}),
  });
}
