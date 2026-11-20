import { env } from "cloudflare:workers";

// workerd explicitly throws "Jurisdiction restrictions are not implemented in
// workerd." Production must NEVER fall back to an unrestricted namespace.
// All tests run in the application's Worker isolate, including its DOs, so this
// test-only prototype adapter supplies local storage while asserting every
// jurisdiction selection is EU. The HTTP test also spies on the three bindings.
const prototype = Object.getPrototypeOf(env.LISTS_V2);
Object.defineProperty(prototype, "jurisdiction", {
  configurable: true,
  writable: true,
  value(this: DurableObjectNamespace, jurisdiction: DurableObjectJurisdiction) {
    if (jurisdiction !== "eu") throw new Error("Tests require EU jurisdiction");
    return this;
  },
});

// Production has one account-wide budget. Each test starts with its own empty
// creation window; identities alone cannot isolate a fixed-name singleton.
import { beforeEach } from "vitest";
import { runInDurableObject } from "cloudflare:test";
beforeEach(async () => {
  const ns = env.CREATION_BUDGET;
  await runInDurableObject(ns.get(ns.idFromName("v2:new-lists")), (_o, state) => {
    if (state.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'creation'").toArray().length) state.storage.sql.exec("DROP TABLE creation");
  });
});

beforeEach(async () => {
  const ns = env.STORAGE_LEDGER;
  await runInDurableObject(ns.get(ns.idFromName("v2:storage")), async (o, state) => { await state.storage.deleteAll(); (o as unknown as { total?: number }).total = undefined; });
});
