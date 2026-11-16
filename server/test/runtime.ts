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
