import { AuthenticatedBody } from "./authenticated-body";
import { euNamespace } from "./eu-namespace";
import type { Env } from "./env";
import { decodeB64Url, encodeB64Url, sha256 } from "./encoding";
import { err, readJsonObject, toResponse, type ApiResult } from "./http";
import { clientKey, clientKey48 } from "./ip";
import {
  V2_BODY_READ_DEADLINE_MS,
  V2_MAX_GUARD_BODY_BYTES,
  V2_MAX_BODY_BYTES,
  V2_MAX_CREATE_BODY_BYTES,
  V2_MAX_INVITE_BODY_BYTES,
  V2_MAX_REVOKE_BODY_BYTES,
  V2_MAX_RENEWAL_BODY_BYTES,
  V2_WS_PROTOCOL,
} from "./limits";
import { matchV2, type V2Route } from "./v2-contract";
import { renewalCommand } from "./renewal";
import { operationId, recoveryCas, recoveryReadVerifier, recoveryShape } from "./recovery-contract";
import { key32 } from "./v2-contract";
import { RECOVERY_CONTROL_BYTES, RECOVERY_MAX_BODY_BYTES } from "./limits";

const BEARER = /^Bearer ([A-Za-z0-9_-]{43})$/;
const WS_BEARER = /^bearer\.([A-Za-z0-9_-]{43})$/;

/** SHA-256 of the 32-byte service credential; the credential itself goes no further. */
async function verifierOf(credential: string | undefined): Promise<string | null> {
  const raw = credential === undefined ? null : decodeB64Url(credential, 32);
  return raw ? encodeB64Url(await sha256(raw)) : null;
}

/** Each route reads only what it can accept; large PUTs are authenticated in the list. */
function bodyLimit(r: V2Route, match: string | null): number {
  if (r.resource === "withdraw") return 64;
  if (r.resource === "recoveryCommit") return RECOVERY_CONTROL_BYTES;
  if (r.recoveryId !== undefined) return RECOVERY_MAX_BODY_BYTES;
  if (r.resource === "renewal") return V2_MAX_RENEWAL_BODY_BYTES;
  if (r.resource === "guard") return V2_MAX_GUARD_BODY_BYTES;
  if (r.resource === "common") return V2_MAX_BODY_BYTES;
  if (r.resource === "revoke" || r.resource === "capability") return V2_MAX_REVOKE_BODY_BYTES;
  if (r.resource === "list") return match === '"0"' ? V2_MAX_CREATE_BODY_BYTES : V2_MAX_BODY_BYTES;
  return V2_MAX_INVITE_BODY_BYTES;
}

/**
 * Production selects `.jurisdiction("eu")` before an id is made. Only an
 * explicit local development opt-in bypasses jurisdiction in workerd.
 * The list object decides everything else (access, revocation, versions) under
 * one lock, so a revocation is ordered against every other operation.
 */
export async function routeV2(request: Request, env: Env, localRequest = false): Promise<Response> {
  if (env.LOCAL_DEV === "true" && !localRequest) return toResponse(err(500, "internal"));
  const r = matchV2(new URL(request.url).pathname);
  const recoveryPath = /^\/v2\/(recoveries(?:\/|$)|lists\/[^/]+\/recoveries(?:\/|$))/.test(new URL(request.url).pathname);
  if (!r) return toResponse(err(recoveryPath ? 400 : 404, recoveryPath ? "invalid_recovery" : "not_found"));
  if (!r.methods.includes(request.method)) return toResponse(err(405, "method_not_allowed", { Allow: r.methods.join(", ") }));
  const pendingOffer = r.resource === "offer" && new URL(request.url).searchParams.get("pending") === "204";
  const client = clientKey(request.headers.get("CF-Connecting-IP"));
  const protocols = (request.headers.get("Sec-WebSocket-Protocol") ?? "").split(",").map((p) => p.trim());
  const bearer = BEARER.exec(request.headers.get("Authorization") ?? "")?.[1];
  const credential = r.resource === "ws" ? (protocols.map((p) => WS_BEARER.exec(p)?.[1]).find(Boolean) ?? bearer) : bearer;
  const verifier = await verifierOf(credential);
  const listRoute = r.syncId !== undefined;
  const guardOpen = r.resource === "guard" && r.action === "open";
  if (listRoute && !guardOpen && !verifier && !recoveryPath) return toResponse(err(401, "unauthorized"));

  const client48 = clientKey48(request.headers.get("CF-Connecting-IP"));
  const limitedBy = async (narrow: RateLimit, wide: RateLimit) => {
    if (!(await narrow.limit({ key: client })).success) return true;
    return !(await wide.limit({ key: client48 })).success;
  };
  if (recoveryPath && !listRoute && await limitedBy(env.RECOVERY_IP_LIMITER, env.RECOVERY_IP48_LIMITER)) return toResponse(err(429, "rate_limited", { "Retry-After": "60" }));
  if (guardOpen && await limitedBy(env.GUARD_IP_LIMITER, env.GUARD_IP48_LIMITER)) return toResponse(err(429, "rate_limited", { "Retry-After": "60" }));
  if ((r.inviteId !== undefined || r.resource === "invites") && await limitedBy(env.INVITE_IP_LIMITER, env.INVITE_IP48_LIMITER)) return toResponse(err(429, "rate_limited", { "Retry-After": "60" }));

  // Cheap syntax checks precede body streaming and discovery, whether or not
  // the locator exists. Semantic CAS/auth decisions remain in the list object.
  if (recoveryPath) {
    const match = request.headers.get("If-Match");
    if (match !== null && recoveryCas(match) === null) return toResponse(err(400, "invalid_recovery"));
    const operation = request.headers.get("X-Recovery-Operation");
    if (operation !== null && !operationId(operation)) return toResponse(err(400, "invalid_recovery"));
    if (!listRoute && !key32(request.headers.get("X-Recovery-Cap"))) return toResponse(err(400, "invalid_recovery"));
    if (listRoute && !verifier) return toResponse(err(401, "unauthorized"));
    if (request.method === "PUT" && match === '"0"' && !operationId(operation)) return toResponse(err(400, "invalid_recovery"));
  }

  const match = request.headers.get("If-Match");
  const creating = r.resource === "list" && request.method === "PUT" && match === '"0"';
  if (creating &&
      !(await env.CREATE_IP_LIMITER.limit({ key: client })).success) return toResponse(err(429, "rate_limited", { "Retry-After": "60" }));

  const streamed = !creating && (request.method === "PUT" || request.method === "POST") && r.resource !== "withdraw" && (r.resource === "list" || r.resource === "common" || (listRoute && recoveryPath) || r.resource === "invites" || r.inviteId !== undefined);
  let body: Record<string, unknown> = {};
  if (!streamed && (request.method === "PUT" || request.method === "POST") && !(r.resource === "guard" && r.action === "resume" && request.body === null)) {
    const parsed = await readJsonObject(request, bodyLimit(r, match), creating ? V2_BODY_READ_DEADLINE_MS : undefined);
    if (!parsed.ok) return toResponse(recoveryPath ? err(parsed.result.status === 413 ? 413 : 400, parsed.result.status === 413 ? "recovery_too_large" : "invalid_recovery") : parsed.result);
    body = parsed.value;
  }

  let readVerifier: string | undefined;
  if (recoveryPath) {
    if ((request.method === "GET" || request.method === "DELETE") && request.body) {
      const reader = request.body.getReader();
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) break;
        if (chunk.value.length > 0) {
          await reader.cancel();
          return toResponse(err(400, "invalid_recovery"));
        }
      }
    }
    const match = request.headers.get("If-Match");
    if (match !== null && recoveryCas(match) === null) return toResponse(err(400, "invalid_recovery"));
    if (!streamed && (request.method === "PUT" || request.method === "POST")) {
      const kind = r.resource === "recoveryClaim" ? "claim" : r.resource === "recoveryRotation" ? "prepare" : r.resource === "recoveryCommit" ? "commit" : "put";
      if (!recoveryShape(kind, body)) return toResponse(err(400, "invalid_recovery"));
    }
    if (!listRoute) {
      const cap = request.headers.get("X-Recovery-Cap");
      if (!key32(cap)) return toResponse(err(400, "invalid_recovery"));
      readVerifier = await recoveryReadVerifier(cap);
    } else if (!verifier) return toResponse(err(401, "unauthorized"));
  }

  let syncId = r.syncId;
  if (!listRoute) {
    if (recoveryPath) {
      const ns = euNamespace(env.RECOVERIES_V2, env, localRequest);
      syncId = (await ns.get(ns.idFromName(r.recoveryId!)).locate()) ?? undefined;
    } else {
      const ns = euNamespace(env.INVITES_V2, env, localRequest);
      syncId = (await ns.get(ns.idFromName(r.inviteId!)).locate()) ?? undefined;
    }
    if (!syncId) return toResponse(pendingOffer ? { status: 204 } : err(404, "not_found"));
  }
  const ns = euNamespace(env.LISTS_V2, env, localRequest);
  const list = ns.get(ns.idFromName(syncId!));
  // Probe before acquiring the source lock: cross-object probes while holding
  // two source locks could deadlock. The result is an internal field only;
  // source authentication, signed shape and CAS still precede acceptance.
  let destinationCreated: boolean | undefined;
  if (env.RENEWAL_ENABLED === "true" && r.resource === "renewal" && renewalCommand(body) && ["reserve", "replace", "recover"].includes(body.action)) {
    destinationCreated = await ns.get(ns.idFromName(body.targetSyncId)).renewalDestination(body.newDeviceId as string, body.newSigningKey as string);
  }

  if (r.resource === "ws") {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return toResponse(err(426, "upgrade_required"));
    // Built from scratch: Authorization, Cookie, bearer protocols and any other
    // client header never reach the object.
    const headers = new Headers({ Upgrade: "websocket", "x-verifier": verifier! });
    if (protocols.includes(V2_WS_PROTOCOL)) headers.set("x-ws-protocol", V2_WS_PROTOCOL);
    const response = await list.fetch(new Request(localRequest ? new URL("/ws", request.url) : "https://internal/ws", { headers }));
    if (response.status === 101) return response;
    const retry = response.headers.get("Retry-After");
    const code = response.status === 403 ? response.headers.get("x-auth-error") ?? "credential_replaced" : response.status === 404 ? "not_found" : response.status === 429 ? "rate_limited" : "unauthorized";
    return toResponse(err(response.status, code, retry ? { "Retry-After": retry } : undefined));
  }

  const c = {
      localRequest,
      destinationCreated,
      renewalDisabled: env.RENEWAL_ENABLED !== "true",
      recoveryReadVerifier: readVerifier,
      recoveryOperation: request.headers.get("X-Recovery-Operation") ?? undefined,
      automaticRetirement: request.headers.get("X-Automatic-Retirement") === "true",
      route: r,
      method: request.method,
      verifier,
      client,
      client48,
      match,
      none: request.headers.get("If-None-Match"),
      body,
    };
  const result: ApiResult = streamed
    ? await list.handleBody(c, new AuthenticatedBody(request), bodyLimit(r, c.match))
    : await list.handle(c);
  // Keep liveness, authentication and quotas in the list object unchanged.
  if (pendingOffer && result.status === 404 && result.body?.error === "not_found") {
    return toResponse({ status: 204, headers: result.headers });
  }
  return toResponse(result);
}
