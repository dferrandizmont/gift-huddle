import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { listObjects } from "./list-do-objects.mjs";
import { inventoryObjects, run } from "../maintenance/run-retention.mjs";
import { run as runStorage } from "../maintenance/run-storage.mjs";

const account = "a".repeat(32), namespace = "b".repeat(32);
const id = (n) => n.toString(16).padStart(64, "0");
const DAY_MS = 86_400_000;
const candidate = { id: id(1), createdAt: 1000, lastActivity: 2000, version: 1, storedBytes: 1024, hasRecovery: false, pendingInvites: 1 };
const inventory = (ids = [id(1)]) => ({
  version: 1, scriptName: "gift-huddle-sync", jurisdiction: "eu", accountId: account,
  namespaces: {
    ListV2Object: { namespaceId: namespace, ids },
    RecoveryLocatorObject: { namespaceId: "c".repeat(32), ids: [id(2)] },
  },
});

test("maintenance config keeps all published entry points closed and binds only the existing external classes", async () => {
  const config = await readFile(new URL("../maintenance/wrangler.toml", import.meta.url), "utf8");
  assert.match(config, /^workers_dev = false$/m);
  assert.match(config, /^preview_urls = false$/m);
  assert.match(config, /^routes = \[\]$/m);
  assert.match(config, /^ip = "127\.0\.0\.1"$/m);
  assert.doesNotMatch(config, /^\[{1,2}(?:triggers|migrations)|^crons\s*=/m);
  assert.equal([...config.matchAll(/^script_name = "gift-huddle-sync"$/gm)].length, 3);
  assert.deepEqual([...config.matchAll(/^class_name = "([^"]+)"$/gm)].map((m) => m[1]), ["ListV2Object", "RecoveryLocatorObject", "StorageLedgerObject"]);
});

test("API listing follows cursors.after, deduplicates and includes objects without stored data", async () => {
  const calls = [];
  const ids = await listObjects(account, namespace, "test-token", async (url, options) => {
    calls.push({ url, options });
    return Response.json(calls.length === 1
      ? { success: true, result: [{ id: id(2), hasStoredData: false }], result_info: { cursors: { after: "next" } } }
      : { success: true, result: [{ id: id(2) }, { id: id(1) }], result_info: { cursors: { after: "" } } });
  });
  assert.deepEqual(ids, [id(1), id(2)]);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url.pathname, `/client/v4/accounts/${account}/workers/durable_objects/namespaces/${namespace}/objects`);
  assert.equal(calls[0].url.searchParams.get("limit"), "1000");
  assert.equal(calls[1].url.searchParams.get("cursor"), "next");
  assert.equal(calls[0].options.headers.Authorization, "Bearer test-token");
  assert.equal(calls[0].options.redirect, "error");
});

test("listing stops on API failure without retrying or exposing response content", async () => {
  let calls = 0;
  await assert.rejects(listObjects(account, namespace, "test-token", async () => {
    calls++;
    return new Response("private error body", { status: 429 });
  }), { message: "Object listing failed (HTTP 429); no retry or output file" });
  assert.equal(calls, 1);
});

test("listing refuses invalid IDs, unsuccessful envelopes and repeated cursors", async () => {
  for (const page of [
    { success: true, result: [{ id: "invalid" }] }, { success: false, result: [] },
  ]) await assert.rejects(listObjects(account, namespace, "test-token", async () => Response.json(page)));
  let calls = 0;
  await assert.rejects(listObjects(account, namespace, "test-token", async () => {
    calls++;
    return Response.json({ success: true, result: [{ id: id(1) }], result_info: { cursors: { after: "loop" } } });
  }), /Repeated pagination cursor/);
  assert.equal(calls, 2);
});

test("inventory rejects the wrong script/jurisdiction and invalid or duplicate IDs before invocation", () => {
  assert.deepEqual(inventoryObjects(inventory()), [
    { className: "ListV2Object", id: id(1) }, { className: "RecoveryLocatorObject", id: id(2) },
  ]);
  for (const input of [
    { ...inventory(), jurisdiction: "fedramp" }, { ...inventory(), scriptName: "other" },
    inventory([id(1), id(1)]), inventory(["invalid"]), inventory([[id(1)]]),
  ]) assert.throws(() => inventoryObjects(input));
});

test("runner batches 20 with pauses, contacts only loopback and supports a stable resume offset", async () => {
  const objects = inventoryObjects(inventory(Array.from({ length: 42 }, (_, n) => id(n + 10))));
  const batches = [], sleeps = [];
  await run(objects, 3, async (url, options) => {
    assert.equal(url, "http://127.0.0.1:8791/apply-retention");
    const batch = JSON.parse(options.body).objects;
    batches.push(batch);
    return Response.json({ applied: batch.length });
  }, async (ms) => { sleeps.push(ms); }, () => {});
  assert.deepEqual(batches.map((b) => b.length), [20, 20]);
  assert.deepEqual(batches.flat(), objects.slice(3));
  assert.deepEqual(sleeps, [1000]);
});

test("runner stops immediately on a partial or uncertain failure and reports a safe restart offset", async () => {
  const objects = inventoryObjects(inventory());
  let calls = 0;
  await assert.rejects(run(objects, 0, async () => {
    calls++;
    return Response.json({ applied: 1, failed: true }, { status: 503 });
  }, async () => assert.fail("must not pause/retry"), () => {}), /start offset 1/);
  assert.equal(calls, 1);
  await assert.rejects(run(objects, 0, async () => { throw new Error("private response"); }), /start offset 0/);
});

test("empty and already completed inventories report completion without RPC", async () => {
  const messages = [];
  await run([], 0, async () => assert.fail("no objects to wake"), undefined, (message) => messages.push(message));
  assert.deepEqual(messages, ["Completed 0/0"]);
});

test("storage usage checks loopback and warns at exactly 50 percent", async () => {
  const result = { reservedBytes: 1, ceilingBytes: 2, percent: 50, alert: true };
  const messages = [], warnings = [];
  await runStorage(["usage"], {
    fetcher: async (url, options) => {
      assert.equal(url, "http://127.0.0.1:8791/storage-occupancy");
      assert.equal(options.redirect, "error");
      return Response.json(result);
    },
    log: (message) => messages.push(JSON.parse(message)),
    warn: (message) => warnings.push(message),
  });
  assert.deepEqual(messages, [result]);
  assert.deepEqual(warnings, ["Storage ledger at 50.00% of its ceiling"]);
});

test("purge defaults to preview and applies only the reviewed candidates with --apply", async () => {
  let plan;
  await runStorage(["purge", "inventory.json", "30", "2026-11-20", "2026-11-27"], {
    read: async () => JSON.stringify(inventory([id(1), id(3)])),
    fetcher: async (url, options) => {
      assert.equal(url, "http://127.0.0.1:8791/purge-inactive");
      const body = JSON.parse(options.body);
      assert.equal(body.apply, undefined);
      assert.deepEqual(body.objects, [{ id: id(1) }, { id: id(3) }]);
      assert.equal(body.criteria.createdFrom, Date.parse("2026-11-20"));
      assert.equal(body.criteria.createdBefore, Date.parse("2026-11-27"));
      assert.equal(body.criteria.includeLegacy, undefined);
      return Response.json({ candidates: [candidate] });
    },
    log: (message) => { plan = JSON.parse(message); },
  });
  assert.equal(plan.version, 2);
  assert.deepEqual(plan.candidates, [candidate]);
  await runStorage(["purge", "--apply", "plan.json"], {
    read: async () => JSON.stringify(plan),
    fetcher: async (_url, options) => {
      const { id: candidateId, ...expected } = candidate;
      assert.deepEqual(JSON.parse(options.body), {
        apply: true, criteria: plan.criteria, objects: [{ id: candidateId, expected }],
      });
      return Response.json({ purged: 1 });
    },
    log: (message) => assert.deepEqual(JSON.parse(message), { purged: 1, reviewed: 1 }),
  });
});

test("purge rejects invalid configuration before contacting maintenance", async () => {
  const options = { read: async () => JSON.stringify(inventory()), fetcher: async () => assert.fail("unexpected RPC") };
  await assert.rejects(runStorage(["purge", "inventory", "29", "2026-11-20", "2026-11-27"], options), /minimum 30 days/);
  await assert.rejects(runStorage(["purge", "inventory", "30", "2026-02-30", "2026-11-20"], options), /Invalid UTC date/);
  await assert.rejects(runStorage(["purge", "--apply", "inventory"], options), /Invalid purge plan/);
});

test("historical purge windows need explicit --include-legacy for preview and apply", async () => {
  const options = { read: async () => JSON.stringify(inventory()), fetcher: async () => assert.fail("unexpected RPC") };
  for (const date of ["1970-01-01", "2026-11-19"]) {
    await assert.rejects(runStorage(["purge", "inventory.json", "30", date, "2026-11-20"], options), /requires --include-legacy/);
  }
  let plan;
  await runStorage(["purge", "--include-legacy", "inventory.json", "30", "1970-01-01", "2026-11-20"], {
    ...options,
    fetcher: async (_url, { body }) => {
      const { criteria } = JSON.parse(body);
      assert.equal(criteria.createdFrom, 0);
      assert.equal(criteria.includeLegacy, true);
      return Response.json({ candidates: [{ ...candidate, createdAt: null }] });
    },
    log: (message) => { plan = JSON.parse(message); },
  });
  const read = async () => JSON.stringify(plan);
  await assert.rejects(runStorage(["purge", "--apply", "plan.json"], { ...options, read }), /requires --include-legacy/);
  await runStorage(["purge", "--include-legacy", "--apply", "plan.json"], {
    read, fetcher: async (_url, { body }) => {
      const request = JSON.parse(body);
      assert.equal(request.apply, true);
      assert.deepEqual(request.criteria, plan.criteria);
      assert.equal(request.objects[0].expected.createdAt, null);
      return Response.json({ purged: 1 });
    },
    log: (message) => assert.deepEqual(JSON.parse(message), { purged: 1, reviewed: 1 }),
  });
});

test("apply rejects a short inactivity cutoff and plans missing or falsifying review fields", async () => {
  const criteria = { createdFrom: Date.parse("2026-11-20"), createdBefore: Date.parse("2026-11-27"), inactiveBefore: Date.now() - 30 * DAY_MS };
  const plan = { version: 2, criteria, candidates: [candidate] };
  const apply = (data) => runStorage(["purge", "--apply", "plan.json"], {
    read: async () => JSON.stringify(data), fetcher: async () => assert.fail("unexpected RPC"),
  });
  await assert.rejects(apply({ ...plan, version: 1 }), /Invalid purge plan/);
  await assert.rejects(apply({ ...plan, criteria: { ...criteria, inactiveBefore: Date.now() - 29 * DAY_MS } }), /minimum 30 days/);
  for (const change of [{ storedBytes: undefined }, { hasRecovery: true }, { pendingInvites: -1 }]) {
    await assert.rejects(apply({ ...plan, candidates: [{ ...candidate, ...change }] }), /Invalid or duplicate purge candidate/);
  }
});
