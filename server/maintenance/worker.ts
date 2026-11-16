import type { ListV2Object } from "../src/list-v2-object";
import type { RecoveryLocatorObject } from "../src/recovery-locator-object";

type Env = {
  LISTS_V2: DurableObjectNamespace<ListV2Object>;
  RECOVERIES_V2: DurableObjectNamespace<RecoveryLocatorObject>;
};
const MAX_OBJECTS = 20;
const MAX_BYTES = 8192;

/** Dev-session entry only: this separate Worker has no published URL or trigger. */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/apply-retention") {
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
    } finally { reader.releaseLock(); }

    let stubs: { applyRetention(): Promise<void> }[];
    try {
      const body = JSON.parse(text);
      if (!Array.isArray(body.objects) || body.objects.length < 1 || body.objects.length > MAX_OBJECTS) throw new Error();
      const lists = env.LISTS_V2.jurisdiction("eu");
      const recoveries = env.RECOVERIES_V2.jurisdiction("eu");
      // Validate the whole batch, including namespace/jurisdiction checks, before any RPC.
      stubs = body.objects.map((item: { className: string; id: string }) => {
        if (!item || !/^[a-f0-9]{64}$/.test(item.id)) throw new Error();
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
