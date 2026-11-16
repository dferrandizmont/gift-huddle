import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { setTimeout as pause } from "node:timers/promises";

export function inventoryObjects(inventory) {
  if (inventory.version !== 1 || inventory.scriptName !== "gift-huddle-sync" || inventory.jurisdiction !== "eu" ||
      !/^[a-f0-9]{32}$/.test(inventory.accountId)) throw new Error("Invalid inventory metadata");
  const objects = [];
  for (const className of ["ListV2Object", "RecoveryLocatorObject"]) {
    const namespace = inventory.namespaces?.[className];
    if (!/^[a-f0-9]{32}$/.test(namespace?.namespaceId) || !Array.isArray(namespace?.ids)) throw new Error("Invalid namespace inventory");
    const seen = new Set();
    for (const id of namespace.ids) {
      if (typeof id !== "string" || !/^[a-f0-9]{64}$/.test(id) || seen.has(id)) throw new Error("Invalid or duplicate object ID");
      seen.add(id);
      objects.push({ className, id });
    }
  }
  return objects;
}

export async function run(objects, start = 0, fetcher = fetch, sleep = pause, log = console.log) {
  if (!Number.isSafeInteger(start) || start < 0 || start > objects.length) throw new Error("Invalid start offset");
  if (start === objects.length) log(`Completed ${start}/${objects.length}`);
  for (let offset = start; offset < objects.length; offset += 20) {
    const batch = objects.slice(offset, offset + 20);
    let applied = 0;
    try {
      const response = await fetcher("http://127.0.0.1:8791/apply-retention", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ objects: batch }), redirect: "error", signal: AbortSignal.timeout(120_000),
      });
      const result = await response.json();
      if (Number.isSafeInteger(result.applied) && result.applied >= 0 && result.applied <= batch.length) applied = result.applied;
      if (!response.ok || result.applied !== batch.length || result.failed) throw new Error();
    } catch {
      throw new Error(`Stopped. Resume with start offset ${offset + applied} using the SAME inventory (an uncertain batch can safely be repeated).`);
    }
    log(`Completed ${offset + batch.length}/${objects.length}`);
    if (offset + batch.length < objects.length) await sleep(1000);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [file, start = "0"] = process.argv.slice(2);
    if (!file || process.argv.length > 4 || !/^\d+$/.test(start)) throw new Error("Usage: node maintenance/run-retention.mjs INVENTORY.json [START_OFFSET]");
    const objects = inventoryObjects(JSON.parse(await readFile(file, "utf8")));
    await run(objects, Number(start));
  } catch (error) {
    // Only locally generated messages, never server exceptions or object identifiers.
    console.error(error instanceof SyntaxError ? "Invalid inventory JSON" : error.message);
    process.exitCode = 1;
  }
}
