import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { listObjects } from "./list-do-objects.mjs";
import { inventoryObjects, run } from "../maintenance/run-retention.mjs";

const account = "a".repeat(32), namespace = "b".repeat(32);
const id = (n) => n.toString(16).padStart(64, "0");
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
  assert.equal([...config.matchAll(/^script_name = "gift-huddle-sync"$/gm)].length, 2);
  assert.deepEqual([...config.matchAll(/^class_name = "([^"]+)"$/gm)].map((m) => m[1]), ["ListV2Object", "RecoveryLocatorObject"]);
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
