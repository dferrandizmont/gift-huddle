import { allowedOrigin, apiHeaders, preflight } from "./cors";
import type { Env } from "./env";
import { clientKey } from "./ip";
import { err, toResponse } from "./http";
import { routeV2 } from "./v2-router";
import { localhostRequest } from "./eu-namespace";

export { ListV2Object } from "./list-v2-object";
export { InviteV2Object } from "./invite-v2-object";
export { LimiterV2Object } from "./limiter-v2-object";
export { RecoveryLocatorObject } from "./recovery-locator-object";

/** Origin checks and preflight run before quota or Durable Object access. */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const configured = env.ALLOWED_ORIGIN ?? "https://gifthuddle.app,https://web.gifthuddle.app";
    const finish = (response: Response) => apiHeaders(response, request, configured);
    const localRequest = env.LOCAL_DEV === "true" && localhostRequest(request);
    if (env.LOCAL_DEV === "true" && !localRequest) return finish(toResponse(err(500, "internal")));
    if (!allowedOrigin(request, configured)) return finish(toResponse(err(403, "forbidden")));
    if (new URL(request.url).pathname.startsWith("/v1/")) return finish(toResponse(err(410, "gone")));
    if (request.method === "OPTIONS") return finish(preflight(request));
    try {
      const { success } = await env.IP_LIMITER.limit({ key: clientKey(request.headers.get("CF-Connecting-IP")) });
      if (!success) return finish(toResponse(err(429, "rate_limited", { "Retry-After": "60" })));
      return finish(await (new URL(request.url).pathname.startsWith("/v2/") ? routeV2(request, env, localRequest) : toResponse(err(404, "not_found"))));
    } catch {
      // Deliberately generic and unlogged: bodies and headers hold ciphertext and keys.
      return finish(toResponse(err(500, "internal")));
    }
  },
} satisfies ExportedHandler<Env>;
