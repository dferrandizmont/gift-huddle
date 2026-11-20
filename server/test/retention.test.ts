import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { LIST_TTL_MS, V2_REVOKED_SLOTS_GRACE_MS } from "../src/limits";
import maintenance from "../maintenance/worker";

const DAY = 86400000;
const list = () => {
  const ns = env.LISTS_V2.jurisdiction("eu");
  return ns.get(ns.newUniqueId());
};
const locator = () => {
  const ns = env.RECOVERIES_V2.jurisdiction("eu");
  return ns.get(ns.newUniqueId());
};
const listState = (stub: ReturnType<typeof list>) => runInDurableObject(stub, async (_o, s) => {
  const tables = s.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite%' AND name NOT LIKE '_cf%'").toArray();
  return {
    tables: tables.map(({ name }) => ({ name, rows: s.storage.sql.exec(`SELECT * FROM ${name}`).toArray().map((row) => {
      // Retention may migrate the byte meter; compare the retained data itself.
      if (name !== "state" || typeof row.data !== "string") return row;
      const meta = JSON.parse(row.data);
      delete meta.storedBytes;
      delete meta.rowBudget;
      for (const credential of meta.credentials ?? []) delete credential.createdAt;
      return { ...row, data: JSON.stringify(meta) };
    }) })),
    kv: [...await s.storage.list()].filter(([key]) => key !== "storageLedger"), alarm: await s.storage.getAlarm(),
  };
});
const locatorState = (stub: ReturnType<typeof locator>) => runInDurableObject(stub, async (_o, s) => ({
  kv: [...await s.storage.list()], alarm: await s.storage.getAlarm(),
}));

async function seedList(stub: ReturnType<typeof list>, value: unknown) {
  await runInDurableObject(stub, (_o, s) => {
    s.storage.sql.exec("CREATE TABLE state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)");
    s.storage.sql.exec("INSERT INTO state VALUES (1, ?)", JSON.stringify(value));
  });
}
async function seedLive(stub: ReturnType<typeof list>, revoked = false) {
  const state = {
    syncId: "legacy", version: 7, lastAccess: Date.now() - 2 * DAY,
    credentials: [
      { deviceId: "aritz", verifier: "active", revoked: false, records: [], lastRequest: 123 },
      ...(revoked ? [{ deviceId: "nora", verifier: null, revoked: true, records: [] }] : []),
    ], denied: [], knownRecords: [], recordTimes: [], approvals: [],
  };
  await seedList(stub, state);
  await runInDurableObject(stub, (_o, s) => {
    s.storage.sql.exec("CREATE TABLE invite (id TEXT PRIMARY KEY, expires_at INTEGER, data TEXT)");
    s.storage.sql.exec("CREATE TABLE slot (person TEXT, device TEXT, ver INTEGER, data TEXT)");
    if (revoked) s.storage.sql.exec("INSERT INTO slot VALUES ('leo', 'nora', 6, 'ciphertext')");
  });
  return state;
}

afterEach(() => vi.useRealTimers());

describe("operator retention RPC", () => {
  it.each([{ retired: true }, { deleted: true }])("dates old list marker %j without reviving it; retries keep the deadline", async (marker) => {
    const stub = list(), now = Date.now();
    await seedList(stub, marker);
    expect((await listState(stub)).alarm).toBeNull();
    vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(now);
    await stub.applyRetention(); // Real stub RPC, not a direct instance call.
    const once = await listState(stub);
    expect(once.alarm).toBe(now + LIST_TTL_MS);
    expect(once.kv).toEqual([["retiredUntil", now + LIST_TTL_MS]]);
    expect(once.tables.find((t) => t.name === "state")?.rows).toEqual([{ id: 1, data: '{"retired":true}' }]);
    vi.setSystemTime(now + DAY);
    await stub.applyRetention();
    expect(await listState(stub)).toEqual(once);
  });

  it("repairs a missing marker alarm using its existing deadline and erases an elapsed marker", async () => {
    const stub = list(), now = Date.now(), until = now + 3 * DAY;
    await seedList(stub, { retired: true });
    await runInDurableObject(stub, (_o, s) => s.storage.put("retiredUntil", until));
    vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(now);
    await stub.applyRetention();
    expect((await listState(stub)).alarm).toBe(until);
    vi.setSystemTime(until);
    await stub.applyRetention();
    expect(await listState(stub)).toEqual({ tables: [], kv: [], alarm: null });
  });

  it("dates legacy revoked blocks once, schedules their grace and lets the alarm erase them", async () => {
    const stub = list(), now = Date.now();
    const original = await seedLive(stub, true);
    vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(now);
    await stub.applyRetention();
    const once = await listState(stub);
    expect(once.alarm).toBe(now + V2_REVOKED_SLOTS_GRACE_MS);
    const meta = JSON.parse(String(once.tables.find((t) => t.name === "state")!.rows[0]!.data));
    expect(meta).toEqual({ ...original, credentials: [original.credentials[0], { ...original.credentials[1], slotsExpireAt: now + V2_REVOKED_SLOTS_GRACE_MS }] });
    expect(once.tables.find((t) => t.name === "slot")!.rows).toHaveLength(1);
    vi.setSystemTime(now + DAY);
    await stub.applyRetention();
    expect(await listState(stub)).toEqual(once);
    vi.setSystemTime(now + V2_REVOKED_SLOTS_GRACE_MS);
    await runDurableObjectAlarm(stub);
    expect((await listState(stub)).tables.find((t) => t.name === "slot")!.rows).toEqual([]);
  });

  it("restores the original live-list expiry without extending activity, changing data or creating rate rows", async () => {
    const stub = list();
    const meta = await seedLive(stub);
    const before = await listState(stub);
    await stub.applyRetention();
    const after = await listState(stub);
    expect(after).toEqual({ ...before, alarm: meta.lastAccess + LIST_TTL_MS });
    await stub.applyRetention();
    expect(await listState(stub)).toEqual(after);
  });

  it("leaves current live and retired lists and empty objects unchanged", async () => {
    const live = list(), retired = list(), empty = list();
    const meta = await seedLive(live);
    await runInDurableObject(live, (_o, s) => s.storage.setAlarm(meta.lastAccess + LIST_TTL_MS));
    await seedList(retired, { retired: true });
    const until = Date.now() + LIST_TTL_MS;
    await runInDurableObject(retired, async (_o, s) => { await s.storage.put("retiredUntil", until); await s.storage.setAlarm(until); });
    for (const stub of [live, retired, empty]) {
      const before = await listState(stub);
      await stub.applyRetention(); await stub.applyRetention();
      expect(await listState(stub)).toEqual(before);
    }
  });

  it("does not drain release queues or postpone an earlier alarm on a current list", async () => {
    const stub = list(); await seedLive(stub);
    await runInDurableObject(stub, async (_o, s) => {
      s.storage.sql.exec("CREATE TABLE pending_release (data TEXT PRIMARY KEY)");
      s.storage.sql.exec("INSERT INTO pending_release VALUES (?)", JSON.stringify({ id: "untouched", syncId: "untouched", expiresAt: Date.now() + DAY }));
      await s.storage.setAlarm(Date.now() + 10000);
    });
    const before = await listState(stub);
    await stub.applyRetention();
    expect(await listState(stub)).toEqual(before);
  });

  it("preserves current revoked-block deadlines and content across a repeated sweep", async () => {
    const stub = list(); await seedLive(stub, true);
    const deadline = Date.now() + DAY;
    await runInDurableObject(stub, async (_o, s) => {
      const meta = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      meta.credentials[1].slotsExpireAt = deadline;
      s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(meta));
      await s.storage.setAlarm(deadline);
    });
    const before = await listState(stub);
    await stub.applyRetention(); await stub.applyRetention();
    expect(await listState(stub)).toEqual(before);
  });

  it("minimizes a legacy retired locator and fixes its 400-day deadline once", async () => {
    const stub = locator(), now = Date.now();
    await runInDurableObject(stub, (_o, s) => s.storage.put("locator", {
      state: "retired", sid: "old-list", reservationId: "old-token", reservedAt: 17, alarmAt: now + 1000,
    }));
    vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(now);
    await stub.applyRetention();
    const once = await locatorState(stub);
    expect(once).toEqual({ kv: [["locator", { state: "retired", alarmAt: now + LIST_TTL_MS, retiredUntil: now + LIST_TTL_MS }]], alarm: now + LIST_TTL_MS });
    vi.setSystemTime(now + DAY);
    await stub.applyRetention();
    expect(await locatorState(stub)).toEqual(once);
    vi.setSystemTime(now + LIST_TTL_MS);
    await stub.applyRetention();
    expect(await locatorState(stub)).toEqual({ kv: [], alarm: null });
  });

  it("keeps a dated locator's deadline when minimizing legacy extra fields and repairing its alarm", async () => {
    const stub = locator(), until = Date.now() + DAY;
    await runInDurableObject(stub, (_o, s) => s.storage.put("locator", {
      state: "retired", sid: "old-list", reservationId: "old-token", alarmAt: 17, retiredUntil: until,
    }));
    await stub.applyRetention();
    expect(await locatorState(stub)).toEqual({ kv: [["locator", { state: "retired", alarmAt: until, retiredUntil: until }]], alarm: until });
  });

  it.each(["reserved", "linked", "retired", "empty"])("leaves a current %s locator unchanged without reconciliation", async (state) => {
    const stub = locator(), alarmAt = Date.now() + DAY;
    if (state !== "empty") await runInDurableObject(stub, async (_o, s) => {
      const row = state === "retired" ? { state, alarmAt, retiredUntil: alarmAt } : { state, sid: "untouched", reservationId: "untouched", reservedAt: 17, alarmAt };
      await s.storage.put("locator", row); await s.storage.setAlarm(alarmAt);
    });
    const before = await locatorState(stub);
    await stub.applyRetention(); await stub.applyRetention();
    expect(await locatorState(stub)).toEqual(before);
  });
});

describe("isolated maintenance Worker", () => {
  const origin = "http://127.0.0.1:8791";
  const host = "127.0.0.1:8791";
  const request = (objects: unknown) => new Request(origin + "/apply-retention", {
    method: "POST", headers: { Host: host, "Content-Type": "application/json" }, body: JSON.stringify({ objects }),
  });

  it("invokes both actual RPC bindings by enumerated IDs in the EU namespace", async () => {
    const a = list(), b = locator();
    await seedList(a, { retired: true });
    await runInDurableObject(b, (_o, s) => s.storage.put("locator", { state: "retired", alarmAt: 17, sid: "legacy" }));
    const response = await (env as unknown as { MAINTENANCE: Fetcher }).MAINTENANCE.fetch(request([
      { className: "ListV2Object", id: a.id.toString() }, { className: "RecoveryLocatorObject", id: b.id.toString() },
    ]));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ applied: 2 });
    expect((await listState(a)).alarm).not.toBeNull();
    expect((await locatorState(b)).alarm).not.toBeNull();
  });

  it.each([[], Array(21).fill({}), [{ className: "Other", id: "a".repeat(64) }], [{ className: "ListV2Object", id: "invalid" }]])("rejects invalid or oversized batches before any mutation (%j)", async (objects) => {
    expect((await maintenance.fetch(request(objects), env)).status).toBe(400);
  });

  it("validates the entire batch before applying any retention", async () => {
    const stub = list(); await seedList(stub, { retired: true });
    const before = await listState(stub);
    expect((await maintenance.fetch(request([{ className: "ListV2Object", id: stub.id.toString() }, {}]), env)).status).toBe(400);
    expect(await listState(stub)).toEqual(before);
  });

  it("rejects other paths/methods and bounds streaming bodies", async () => {
    expect((await maintenance.fetch(new Request(origin + "/", { headers: { Host: host } }), env)).status).toBe(404);
    expect((await maintenance.fetch(new Request(origin + "/apply-retention", { method: "POST", headers: { Host: host }, body: "{}" }), env)).status).toBe(415);
    expect((await maintenance.fetch(new Request(origin + "/apply-retention", {
      method: "POST", headers: { Host: host, "Content-Type": "application/json" }, body: "x".repeat(8193),
    }), env)).status).toBe(413);
  });

  it.each([
    ["GET", "/storage-occupancy"], ["POST", "/apply-retention"], ["POST", "/purge-inactive"], ["OPTIONS", "/"],
  ])("rejects a missing or wrong Host and any Origin on %s %s before reading the body", async (method, path) => {
    const rejectedHeaders: Record<string, string>[] = [
      {}, { Host: "localhost:8791" }, { Host: "127.0.0.1" }, { Host: "127.0.0.1:8792" },
      { Host: host, Origin: origin }, { Host: host, Origin: "null" }, { Host: host, Origin: "" },
    ];
    for (const headers of rejectedHeaders) {
      const req = new Request(origin + path, {
        method, headers: { ...headers, "Content-Type": "application/json" }, ...(method === "POST" ? { body: "{}" } : {}),
      });
      const response = await maintenance.fetch(req, env);
      expect(response.status).toBe(403);
      expect(req.bodyUsed).toBe(false);
    }
  });

  it("stops on an RPC error and reports only the completed count", async () => {
    const applyRetention = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("private content"));
    const jurisdiction = vi.fn();
    const ns = { jurisdiction, idFromString: (id: string) => id, get: () => ({ applyRetention }) };
    jurisdiction.mockReturnValue(ns);
    const bindings = { LISTS_V2: ns, RECOVERIES_V2: ns } as unknown as Parameters<typeof maintenance.fetch>[1];
    const response = await maintenance.fetch(request([1, 2, 3].map((n) => ({ className: "ListV2Object", id: n.toString(16).padStart(64, "0") }))), bindings);
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ applied: 1, failed: true });
    expect(applyRetention).toHaveBeenCalledTimes(2);
    expect(jurisdiction.mock.calls).toEqual([["eu"], ["eu"]]);
  });

  it("pauses after five RPCs before completing the next group", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const applyRetention = vi.fn().mockResolvedValue(undefined);
    const ns = { jurisdiction: () => ns, idFromString: (id: string) => id, get: () => ({ applyRetention }) };
    const bindings = { LISTS_V2: ns, RECOVERIES_V2: ns } as unknown as Parameters<typeof maintenance.fetch>[1];
    const pending = maintenance.fetch(request(Array.from({ length: 6 }, (_, n) => ({ className: "ListV2Object", id: n.toString(16).padStart(64, "0") }))), bindings);
    await vi.advanceTimersByTimeAsync(0);
    expect(applyRetention).toHaveBeenCalledTimes(5);
    await vi.advanceTimersByTimeAsync(250);
    expect((await pending).status).toBe(200);
    expect(applyRetention).toHaveBeenCalledTimes(6);
  });
});
