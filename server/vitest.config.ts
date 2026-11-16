import { cloudflareTest, getRunnerName } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import type { TestProject } from "vitest/node";
import { ModuleKind, ScriptTarget, sys, transpileModule } from "typescript";

// Run the actual maintenance Worker in a separate isolate to verify script_name
// bindings + RPC, not just direct calls in the application's test isolate.
const maintenanceSource = sys.readFile("maintenance/worker.ts");
if (maintenanceSource === undefined) throw new Error("Run Vitest from server/: maintenance Worker source not found");
const maintenanceScript = transpileModule(maintenanceSource, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 },
}).outputText;
// workerd has no EU storage implementation (same adapter as test/runtime.ts).
const jurisdictionAdapter = `
import { env as testEnv } from "cloudflare:workers";
Object.defineProperty(Object.getPrototypeOf(testEnv.LISTS_V2), "jurisdiction", {
  value(jurisdiction) { if (jurisdiction !== "eu") throw new Error("Tests require EU jurisdiction"); return this; }
});
`;
// The plugin renames the application isolate; auxiliary DO bindings must use
// that name. getRunnerName's project input only uses the configured test name.
const applicationWorker = getRunnerName({ name: "sync" } as TestProject);

export default defineConfig({
  // Exercise the future protocol; production wrangler.toml stays disabled.
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.toml" },
    miniflare: {
      bindings: { RENEWAL_ENABLED: "true" },
      serviceBindings: { MAINTENANCE: "retention-maintenance-test" },
      workers: [{
        name: "retention-maintenance-test", modules: true,
        compatibilityDate: "2026-10-01",
        script: jurisdictionAdapter + maintenanceScript,
        durableObjects: {
          LISTS_V2: { className: "ListV2Object", scriptName: applicationWorker },
          RECOVERIES_V2: { className: "RecoveryLocatorObject", scriptName: applicationWorker },
        },
      }],
    },
  })],
  test: {
    name: "sync",
    include: ["test/**/*.test.ts"],
    setupFiles: ["./test/runtime.ts"],
  },
});
