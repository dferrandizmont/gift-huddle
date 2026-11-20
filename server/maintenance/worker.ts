import type { ListV2Object, PurgeCandidate, PurgeCriteria } from "../src/list-v2-object";
import type { RecoveryLocatorObject } from "../src/recovery-locator-object";
import type { StorageLedgerObject } from "../src/storage-ledger-object";

type Env = {
  LISTS_V2: DurableObjectNamespace<ListV2Object>;
  RECOVERIES_V2: DurableObjectNamespace<RecoveryLocatorObject>;
  STORAGE_LEDGER: DurableObjectNamespace<StorageLedgerObject>;
};
const MAX_OBJECTS = 20;
const MAX_BYTES = 8192;
const LOOPBACK_HOST = "127.0.0.1:8791";
const MIN_INACTIVE_MS = 30 * 86_400_000;
// Keep in sync with run-storage.mjs, using the release's UTC date.
const DATED_LISTS_FROM = Date.UTC(2026, 10, 20);
const noStore = { "Cache-Control": "no-store" };
const validId = (id: unknown): id is string => typeof id === "string" && /^[a-f0-9]{64}$/.test(id);
const timestamp = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;

async function purge(body: {
  apply?: unknown; criteria?: PurgeCriteria; objects?: { id: string; expected?: PurgeCandidate }[];
}, env: Env): Promise<Response> {
  const { apply, criteria, objects } = body ?? {};
  if ((apply !== undefined && apply !== true) ||
      !criteria || !timestamp(criteria.createdFrom) || !timestamp(criteria.createdBefore) ||
      criteria.createdFrom >= criteria.createdBefore || !timestamp(criteria.inactiveBefore) ||
      criteria.inactiveBefore > Date.now() - MIN_INACTIVE_MS ||
      (criteria.includeLegacy !== undefined && criteria.includeLegacy !== true) ||
      (criteria.createdFrom < DATED_LISTS_FROM && criteria.includeLegacy !== true) ||
      !Array.isArray(objects) || objects.length < 1 || objects.length > MAX_OBJECTS) return new Response(null, { status: 400 });

  const seen = new Set<string>();
  const ns = env.LISTS_V2.jurisdiction("eu");
  // Validate the whole batch before allowing any retirements.
  const targets = objects.map((item) => {
    if (!item || !validId(item.id) || seen.has(item.id)) throw new Error("Invalid object");
    const expected = item.expected;
    if (apply === true ? !expected || (expected.createdAt !== null && !timestamp(expected.createdAt)) ||
        !timestamp(expected.lastActivity) || !Number.isSafeInteger(expected.version) || expected.version < 1 ||
        !timestamp(expected.storedBytes) || expected.hasRecovery !== false || !timestamp(expected.pendingInvites) : expected !== undefined) {
      throw new Error("Invalid candidate");
    }
    seen.add(item.id);
    return { ...item, stub: ns.get(ns.idFromString(item.id)) };
  });

  let purged = 0;
  const candidates: (PurgeCandidate & { id: string })[] = [];
  for (const [index, { stub, id, expected }] of targets.entries()) {
    try {
      if (apply === true) {
        if (await stub.purgeInactive(criteria, expected!)) purged++;
      } else {
        const candidate = await stub.previewPurge(criteria);
        if (candidate) candidates.push({ id, ...candidate });
      }
    } catch {
      return Response.json({ checked: index, purged, failed: true }, { status: 503, headers: noStore });
    }
    if ((index + 1) % 5 === 0 && index + 1 < targets.length) await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return Response.json(apply === true ? { purged } : { candidates }, { headers: noStore });
}

/** Dev-session entry only: this separate Worker has no published URL or trigger. */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.headers.get("Host") !== LOOPBACK_HOST || request.headers.has("Origin")) {
      return new Response(null, { status: 403 });
    }
    const path = new URL(request.url).pathname;
    if (request.method === "GET" && path === "/storage-occupancy") {
      try {
        const ns = env.STORAGE_LEDGER.jurisdiction("eu");
        const usage = await ns.get(ns.idFromName("v2:storage")).occupancy();
        return Response.json({ ...usage, alert: usage.percent >= 50 }, { headers: noStore });
      } catch { return new Response(null, { status: 503 }); }
    }
    if (request.method !== "POST" || (path !== "/apply-retention" && path !== "/purge-inactive")) {
      return new Response(null, { status: 404 });
    }
    // A browser's simple cross-origin form/POST cannot start a local sweep.
    // There is deliberately no OPTIONS/CORS handler.
    if (request.headers.get("Content-Type")?.split(";")[0]?.trim() !== "application/json") {
      return new Response(null, { status: 415 });
    }
    // Bound the body even when Content-Length is absent or inaccurate.
    const reader = request.body?.getReader();
    if (!reader) return new Response(null, { status: 400 });
    let text = "", length = 0;
    const decoder = new TextDecoder();
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.byteLength;
        if (length > MAX_BYTES) {
          await reader.cancel();
          return new Response(null, { status: 413 });
        }
        text += decoder.decode(value, { stream: true });
      }
      text += decoder.decode();
    } catch { return new Response(null, { status: 400 }); }
    finally { reader.releaseLock(); }

    let stubs: { applyRetention(): Promise<void> }[];
    try {
      const body = JSON.parse(text);
      if (path === "/purge-inactive") return await purge(body, env);
      if (!Array.isArray(body.objects) || body.objects.length < 1 || body.objects.length > MAX_OBJECTS) throw new Error();
      const lists = env.LISTS_V2.jurisdiction("eu");
      const recoveries = env.RECOVERIES_V2.jurisdiction("eu");
      // Validate the whole batch, including namespace/jurisdiction checks, before any RPC.
      stubs = body.objects.map((item: { className: string; id: string }) => {
        if (!item || !validId(item.id)) throw new Error();
        const ns = item.className === "ListV2Object" ? lists : item.className === "RecoveryLocatorObject" ? recoveries : null;
        if (!ns) throw new Error();
        return ns.get(ns.idFromString(item.id));
      });
    } catch { return new Response(null, { status: 400 }); }

    let applied = 0;
    for (const stub of stubs) {
      try { await stub.applyRetention(); }
      catch {
        // No identifiers, exception text or content in responses/logs.
        return Response.json({ applied, failed: true }, { status: 503 });
      }
      applied++;
      if (applied % 5 === 0 && applied < stubs.length) await new Promise((resolve) => setTimeout(resolve, 250));
    }
    return Response.json({ applied });
  },
};
