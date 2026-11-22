import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { ListStorageBudget } from "../src/list-storage-budget";
import { StorageLedgerObject } from "../src/storage-ledger-object";
import { readJsonObject } from "../src/http";
import { routeV2 } from "../src/v2-router";
import { MAX_ENVELOPE_CHARS, V2_CREDENTIAL_CAP_AGE_MS, V2_GLOBAL_STORAGE_CEILING_BYTES, V2_STORAGE_BLOCK_BYTES, V2_LIST_ROWS_PER_DAY, LIST_TTL_MS, V2_MAX_CREATE_BODY_BYTES, V2_MAX_SLOT_CHARS, V2_MAX_SLOTS, V2_WARN_SLOTS, v2ListByteLimit } from "../src/limits";
import { b64u, call, newList, rand } from "./helpers";

const snapshot = () => ({ deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: b64u(rand(32)) }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
const list = (sid: string) => env.LISTS_V2.get(env.LISTS_V2.idFromName(sid));
const ledger = () => env.STORAGE_LEDGER.get(env.STORAGE_LEDGER.idFromName("v2:storage"));
const ceiling = V2_GLOBAL_STORAGE_CEILING_BYTES / V2_STORAGE_BLOCK_BYTES;
const directFetch = (request: Request) => routeV2(request, env);
const create = async () => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
  return { ...id, path };
};
type Setup = Awaited<ReturnType<typeof create>>;
const edit = (id: Setup, change: (m: any) => void) => runInDurableObject(list(id.syncId), (_o, s) => {
  const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
  change(m); s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
});
const total = () => runInDurableObject(ledger(), (_o, s) => s.storage.sql.exec<{ n: number }>("SELECT COALESCE(SUM(blocks), 0) AS n FROM balances").one().n);
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe("daily client creation admission", () => {
  it.each([[12, 12], [24, 24]])("keeps %i/hour and %i/day sliding across an hour boundary without rejected writes", async (hourly, daily) => {
    const stub = env.LIMITER_V2.get(env.LIMITER_V2.newUniqueId()), start = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(start);
    for (let n = 0; n < daily; n++) expect((await stub.creation(hourly, daily)).ok).toBe(true);
    vi.setSystemTime(start + 3600001);
    await runInDurableObject(stub, async (o, s) => {
      const alarm = await s.storage.getAlarm(), sql = vi.spyOn(s.storage.sql, "exec");
      expect(await o.creation(hourly, daily)).toEqual({ ok: false, retryAfter: 3600 });
      expect(sql.mock.calls.some(([q]) => /^(INSERT|UPDATE|DELETE)/.test(q))).toBe(false);
      expect(await s.storage.getAlarm()).toBe(alarm); sql.mockRestore();
    });
    vi.setSystemTime(start + 86400000);
    expect((await stub.creation(hourly, daily)).ok).toBe(true);
  });
  it("checks a full /48 before touching the /56", async () => {
    const wide = "2001:0db8:7654::/48";
    const limiter = env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:new48:${wide}`));
    for (let n = 0; n < 24; n++) expect((await limiter.creation(24, 24)).ok).toBe(true);
    const id = newList();
    expect((await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: "2001:db8:7654:ab00::1", headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(429);
    const narrow = env.LIMITER_V2.get(env.LIMITER_V2.idFromName("v2:new:2001:0db8:7654:ab00::/56"));
    await runInDurableObject(narrow, async (_o, s) => {
      expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE name = 'creation'").toArray()).toEqual([]);
      expect(await s.storage.getAlarm()).toBeNull();
    });
  });
  it("uses the write-free creation binding before any namespace lookup", async () => {
    const id = newList(), limit = vi.fn(async () => ({ success: false }));
    const lookup = vi.fn(() => { throw new Error("Unexpected namespace lookup"); });
    const response = await routeV2(new Request(`https://sync.test/v2/lists/${id.syncId}`, { method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "CF-Connecting-IP": id.ip, "If-Match": '"0"' } }), { ...env, CREATE_IP_LIMITER: { limit }, LISTS_V2: { jurisdiction: lookup } } as unknown as typeof env);
    expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("60");
    expect(limit).toHaveBeenCalledWith({ key: id.ip }); expect(lookup).not.toHaveBeenCalled();
  });
  it("IPv4 consumes a single counter", async () => {
    const id = await create();
    const unused = env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:new48:${id.ip}`));
    await runInDurableObject(unused, (_o, s) => expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE name = 'creation'").toArray()).toEqual([]));
  });
});

describe("block storage ledger", () => {
  it("serializes the last block, is idempotent, and permits legacy enrolment and reductions above the ceiling", async () => {
    expect(await ledger().set("fixture", ceiling - 1, true)).toBe(true);
    const decisions = await Promise.all([ledger().set("aritz", 1), ledger().set("nora", 1)]);
    expect(decisions.filter(Boolean)).toHaveLength(1);
    expect(await ledger().set("aritz", 1)).toBe(true); expect(await total()).toBe(ceiling);
    expect(await ledger().set("legacy", 3, true)).toBe(true);
    await evictDurableObject(ledger());
    expect(await ledger().set("legacy", 4)).toBe(false);
    expect(await ledger().set("legacy", 1)).toBe(true);
    expect(await ledger().set("legacy", 0)).toBe(true); expect(await total()).toBe(ceiling);
  });
  it("counts creation, denies only block growth, and returns all blocks on deletion", async () => {
    expect(await ledger().set("fixture", ceiling - 1, true)).toBe(true);
    const id = await create(); expect(await total()).toBe(ceiling);
    const put = (text: string, version: number) => call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": `"${version}"` }, body: { common: text } });
    expect((await put("BBBB", 1)).status).toBe(200);
    const denied = await put("A".repeat(V2_STORAGE_BLOCK_BYTES), 2);
    expect(denied.status).toBe(413); expect(await denied.json()).toEqual({ error: "too_large" });
    expect((await call("GET", id.path, { key: id.key })).headers.get("ETag")).toBe('"2"');
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(204);
    expect(await total()).toBe(ceiling - 1); await create(); expect(await total()).toBe(ceiling);
  });
  it("enrols a legacy list above the global ceiling on its first read", async () => {
    const id = await create();
    await runInDurableObject(list(id.syncId), async (o, s) => {
      await ledger().set(s.id.toString(), 0);
      await s.storage.delete("storageLedger");
      (o as unknown as { ledgerBlocks?: number }).ledgerBlocks = undefined;
    });
    expect(await ledger().set("fixture", ceiling, true)).toBe(true);
    await evictDurableObject(list(id.syncId));
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect(await total()).toBe(ceiling + 1);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"1"' }, body: { common: "A".repeat(V2_STORAGE_BLOCK_BYTES) } })).status).toBe(413);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(204);
    expect(await total()).toBe(ceiling);
  });
  it("retries a deleted list's block release after eviction", async () => {
    const id = await create(), set = StorageLedgerObject.prototype.set;
    await runInDurableObject(ledger(), (o) => {
      Object.getPrototypeOf(o).set = function(this: StorageLedgerObject, ...args: Parameters<typeof set>) {
        if (args[1] === 0) throw new Error("Ledger release unavailable");
        return set.apply(this, args);
      };
    });
    try {
      expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(204);
      expect(await total()).toBe(1);
      await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.get("storageLedger")).toMatchObject({ pending: true }));
    } finally { await runInDurableObject(ledger(), (o) => { Object.getPrototypeOf(o).set = set; }); }
    await evictDurableObject(list(id.syncId)); await runDurableObjectAlarm(list(id.syncId));
    expect(await total()).toBe(0);
  });
  it("reports no changes for writes within one block, and releases on shrink and expiry", async () => {
    const id = await create();
    let calls = 0;
    await runInDurableObject(ledger(), (o) => {
      const prototype = Object.getPrototypeOf(o) as StorageLedgerObject, set = prototype.set;
      vi.spyOn(prototype, "set").mockImplementation(function(this: StorageLedgerObject, ...args: Parameters<StorageLedgerObject["set"]>) { calls++; return set.apply(this, args); });
    });
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"1"' }, body: { common: "BBBB" } })).status).toBe(200);
    expect(calls).toBe(0);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"2"' }, body: { common: "A".repeat(V2_STORAGE_BLOCK_BYTES) } })).status).toBe(200);
    expect(await total()).toBe(2);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"3"' }, body: { common: "AAAA" } })).status).toBe(200);
    expect(await total()).toBe(1);
    await edit(id, (m) => { m.lastAccess = Date.now() - LIST_TTL_MS; });
    await runDurableObjectAlarm(list(id.syncId)); expect(await total()).toBe(0);
  });
  it.each(["response", "commit"])("repairs a reservation durably after a lost %s", async (failure) => {
    const id = newList(), path = `/v2/lists/${id.syncId}`;
    const set = StorageLedgerObject.prototype.set;
    await runInDurableObject(ledger(), (o) => {
      let once = false;
      Object.getPrototypeOf(o).set = function(this: StorageLedgerObject, ...args: Parameters<typeof set>) {
        if (!once && args[1] > 0) { once = true; const accepted = set.apply(this, args); if (failure === "response") throw new Error("Lost ledger response"); return accepted; }
        if (once && args[1] === 0) throw new Error("Ledger cleanup unavailable");
        return set.apply(this, args);
      };
    });
    if (failure === "commit") await runInDurableObject(list(id.syncId), (o) => {
      vi.spyOn(o as unknown as { saveMeta: () => void }, "saveMeta").mockImplementation(() => { throw new Error("Local commit failed"); });
    });
    try {
      expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(500);
      expect(await total()).toBe(1);
      await runInDurableObject(list(id.syncId), async (_o, s) => {
        expect(await s.storage.get("storageLedger")).toMatchObject({ pending: true }); expect(await s.storage.getAlarm()).not.toBeNull();
      });
    } finally { await runInDurableObject(ledger(), (o) => { Object.getPrototypeOf(o).set = set; }); }
    await evictDurableObject(list(id.syncId)); await runDurableObjectAlarm(list(id.syncId)); expect(await total()).toBe(0);
  });
});

describe("credential storage capacity", () => {
  it("grants the second phone immediately, retains revoked grace, and ages only extras", () => {
    const now = Date.now(), fresh = { revoked: false, createdAt: now }, mature = { revoked: false, createdAt: now - V2_CREDENTIAL_CAP_AGE_MS };
    expect(v2ListByteLimit([fresh], now)).toBe(1.5 * 1048576);
    expect(v2ListByteLimit([fresh, fresh], now)).toBe(4 * 1048576);
    expect(v2ListByteLimit([fresh, fresh, fresh], now)).toBe(4 * 1048576);
    expect(v2ListByteLimit([fresh, fresh, mature], now)).toBe(5 * 1048576);
    expect(v2ListByteLimit([fresh, fresh, { ...mature, createdAt: mature.createdAt + 1 }], now)).toBe(4 * 1048576);
    expect(v2ListByteLimit([fresh, { ...fresh, revoked: true, slotsExpireAt: now + 1 }], now)).toBe(4 * 1048576);
    expect(v2ListByteLimit([fresh, { ...mature, revoked: true, slotsExpireAt: now }], now)).toBe(1.5 * 1048576);
    expect(v2ListByteLimit(Array.from({ length: 64 }, () => mature), now)).toBe(64.5 * 1048576);
  });

  describe("slot supplement (1.0.6): the stored bytes of slot rows of phones that may write them", () => {
    const now = Date.now();
    /** A stored slot row at its largest: the data plus short keys and the version. */
    const ROW = V2_MAX_SLOT_CHARS + 40;
    const phone = (n: number, extra: object = {}) => ({ deviceId: `phone${n}`, role: "device", revoked: false, createdAt: now, ...extra });
    const web = (n: number) => ({ deviceId: `web${n}`, role: "web", revoked: false, createdAt: now });
    /** Every device of [ids] holds [each] rows of [bytes]. */
    const rows = (ids: string[], each: number, bytes = ROW) => new Map(ids.map((d) => [d, Array.from({ length: each }, () => bytes)]));

    it("a family of 10 that all protect each other gets room for its 90 slots in the first week", () => {
      const phones = Array.from({ length: 10 }, (_, n) => phone(n));
      const limit = v2ListByteLimit(phones, now, rows(phones.map((p) => p.deviceId), 9));
      expect(limit).toBe(4 * 1048576 + 88 * ROW);
      // The 90 slots at their largest, the largest common, registry and packages at their caps.
      expect(limit).toBeGreaterThanOrEqual(90 * ROW + MAX_ENVELOPE_CHARS + 2 * 256 * 1024 - 2 * ROW);
      // Six phones paired in the same week (the 1.0.5 limit refused their 30 slots).
      const six = phones.slice(0, 6);
      expect(v2ListByteLimit(six, now, rows(six.map((p) => p.deviceId), 5))).toBe(4 * 1048576 + 28 * ROW);
    });

    it("pays the real bytes of each row, not a fixed allowance: smaller rows give less", () => {
      const phones = Array.from({ length: 3 }, (_, n) => phone(n));
      const ids = phones.map((p) => p.deviceId);
      expect(v2ListByteLimit(phones, now, rows(ids, 2, 1000))).toBe(4 * 1048576 + 4 * 1000);
      // The two largest rows are the ones the ordinary budget already holds.
      const mixed = new Map([["phone0", [5000, 100]], ["phone1", [100, 100]], ["phone2", [7000, 100]]]);
      expect(v2ListByteLimit(phones, now, mixed)).toBe(4 * 1048576 + 400);
    });

    it("the same ten credentials without slot rows only get the ordinary budget for other resources", () => {
      const phones = Array.from({ length: 10 }, (_, n) => phone(n));
      expect(v2ListByteLimit(phones, now)).toBe(4 * 1048576);
      expect(v2ListByteLimit(phones, now, rows(["phone0"], 2))).toBe(4 * 1048576);
    });

    it("one phone and nine webs get nothing extra, whatever the webs store", () => {
      const creds = [phone(0), ...Array.from({ length: 9 }, (_, n) => web(n))];
      expect(v2ListByteLimit(creds, now, rows(creds.map((c) => c.deviceId), 9))).toBe(4 * 1048576);
    });

    it("each phone is paid for at most one row per other phone; revoked phones only in grace", () => {
      const phones = Array.from({ length: 3 }, (_, n) => phone(n));
      // A newly approved phone writing 32 junk rows adds 2 (n − 1), not 32.
      expect(v2ListByteLimit(phones, now, new Map([["phone0", [ROW, ROW]], ["phone1", [ROW, ROW]], ["phone2", Array(32).fill(ROW)]]))).toBe(4 * 1048576 + 4 * ROW);
      const gone = [...phones, phone(3, { revoked: true, slotsExpireAt: now - 1 })];
      expect(v2ListByteLimit(gone, now, rows(gone.map((p) => p.deviceId), 3))).toBe(4 * 1048576 + 4 * ROW);
      const grace = [...phones, phone(3, { revoked: true, slotsExpireAt: now + 1 })];
      expect(v2ListByteLimit(grace, now, rows(grace.map((p) => p.deviceId), 3))).toBe(4 * 1048576 + 10 * ROW);
    });

    it("stops at V2_MAX_SLOTS and 64.5 MiB", () => {
      const phones = Array.from({ length: 12 }, (_, n) => phone(n));
      expect(v2ListByteLimit(phones, now, rows(phones.map((p) => p.deviceId), 11))).toBe(4 * 1048576 + (V2_MAX_SLOTS - 2) * ROW);
      const many = Array.from({ length: 64 }, (_, n) => phone(n, { createdAt: now - V2_CREDENTIAL_CAP_AGE_MS }));
      expect(v2ListByteLimit(many, now, rows(many.map((p) => p.deviceId), 63))).toBe(64.5 * 1048576);
      expect(V2_MAX_SLOTS).toBeGreaterThanOrEqual(90);
      expect(V2_WARN_SLOTS).toBeGreaterThan(90);
      expect(V2_WARN_SLOTS).toBeLessThan(V2_MAX_SLOTS);
    });
  });
});

describe("daily SQL row budget", () => {
  it("counts actual cursor writes in state, rejects mutations before body reads, and permits reads, alarms and revocation", async () => {
    const id = await create();
    await runInDurableObject(list(id.syncId), (o, s) => {
      const budget = (o as unknown as { budget: ListStorageBudget }).budget;
      s.storage.sql.exec("CREATE TABLE row_cost (id INTEGER PRIMARY KEY, data TEXT)");
      budget.transaction(() => {
        const cursor = budget.sql.exec("INSERT INTO row_cost WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < 6000) SELECT x, 'x' FROM n");
        expect(cursor.rowsWritten).toBe(V2_LIST_ROWS_PER_DAY);
      });
      const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      expect(m.rowBudget.written).toBeGreaterThanOrEqual(V2_LIST_ROWS_PER_DAY);
      expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE name = 'row_budget'").toArray()).toEqual([]);
    });
    await evictDurableObject(list(id.syncId));
    const rejected = await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"1"' }, body: { common: "BBBB" } });
    expect(rejected.status).toBe(429); expect(await rejected.json()).toEqual({ error: "rate_limited" });
    expect(Number(rejected.headers.get("Retry-After"))).toBeGreaterThan(0); expect(Number(rejected.headers.get("Retry-After"))).toBeLessThanOrEqual(3600);
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "aritz" } })).status).toBe(200);
  });
  it("resets on UTC midnight and caps Retry-After to the remaining UTC day", async () => {
    const id = await create(), midnight = (Math.floor(Date.now() / 86400000) + 1) * 86400000;
    vi.useFakeTimers({ toFake: ["Date"] }); vi.setSystemTime(midnight - 1500);
    await edit(id, (m) => { m.rowBudget = { day: Math.floor(Date.now() / 86400000), written: 6000 }; });
    const put = () => call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"1"' }, body: { common: "BBBB" } });
    expect((await put()).headers.get("Retry-After")).toBe("2");
    vi.setSystemTime(midnight); expect((await put()).status).toBe(200);
  });
});

describe("deferred authenticated body", () => {
  it("times out a stalled create at 60 seconds in the Worker before any list lookup", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const id = newList();
    const lookup = vi.fn();
    const cancel = vi.fn();
    let start!: () => void;
    const reading = new Promise<void>((resolve) => { start = resolve; });
    const body = new ReadableStream<Uint8Array>({ pull: start, cancel }, { highWaterMark: 0 });
    const upload = routeV2(new Request(`https://sync.test/v2/lists/${id.syncId}`, {
      method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "If-Match": '"0"', "Content-Type": "application/json" }, body,
    }), { ...env, LISTS_V2: { jurisdiction: lookup } } as unknown as typeof env);
    await reading;
    await vi.advanceTimersByTimeAsync(59_999);
    expect(cancel).not.toHaveBeenCalled();
    expect(lookup).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    const response = await upload;
    expect(response.status).toBe(408);
    expect(await response.json()).toEqual({ error: "bad_request" });
    expect(cancel).toHaveBeenCalledOnce();
    expect(lookup).not.toHaveBeenCalled();
  });

  it("enforces the streamed byte cap on creates before looking up a list", async () => {
    const id = newList();
    const lookup = vi.fn();
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(V2_MAX_CREATE_BODY_BYTES));
        controller.enqueue(Uint8Array.of(1));
        controller.close();
      },
    });
    const response = await routeV2(new Request(`https://sync.test/v2/lists/${id.syncId}`, {
      method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "If-Match": '"0"', "Content-Type": "application/json" }, body,
    }), { ...env, LISTS_V2: { jurisdiction: lookup } } as unknown as typeof env);
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({ error: "too_large" });
    expect(lookup).not.toHaveBeenCalled();
  });

  it.each(["role", "rotation", "frequency", "rows"])("rejects %s before opening the stream", async (kind) => {
    const id = await create();
    if (kind === "role" || kind === "rotation") await edit(id, (m) => { m.credentials[0].role = "web"; });
    if (kind === "rotation") await runInDurableObject(list(id.syncId), (_o, s) => {
      s.storage.sql.exec("CREATE TABLE guard (device TEXT PRIMARY KEY, data TEXT NOT NULL)");
      s.storage.sql.exec("INSERT INTO guard VALUES ('aritz', ?)", JSON.stringify({ rotationRequired: true }));
    });
    if (kind === "frequency") await runInDurableObject(list(id.syncId), (o) => {
      (o as unknown as { rate: Map<string, unknown> }).rate.set("w:aritz", { start: Date.now(), count: 30 });
    });
    if (kind === "rows") await edit(id, (m) => { m.rowBudget = { day: Math.floor(Date.now() / 86400000), written: 6000 }; });
    const pull = vi.fn(() => { throw new Error("Rejected body read"); });
    const response = await directFetch(new Request(`https://sync.test${id.path}${kind === "role" ? "" : "/common"}`, { method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "If-Match": '"1"', "Content-Type": "application/json" }, body: new ReadableStream({ pull }, { highWaterMark: 0 }) }));
    expect(response.status).toBe(kind === "role" ? 403 : kind === "rotation" ? 409 : 429); expect(pull).not.toHaveBeenCalled();
  });
  it("allows revocation during a slow body and reauthenticates after the upload", async () => {
    const id = await create();
    let controller!: ReadableStreamDefaultController<Uint8Array>, started!: () => void;
    const reading = new Promise<void>((resolve) => { started = resolve; });
    const body = new ReadableStream<Uint8Array>({ start(c) { controller = c; }, pull() { started(); } }, { highWaterMark: 0 });
    const upload = directFetch(new Request(`https://sync.test${id.path}/common`, { method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "If-Match": '"1"', "Content-Type": "application/json" }, body }));
    await reading;
    const revoke = await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "aritz" } });
    expect(revoke.status).toBe(200);
    controller.enqueue(new TextEncoder().encode('{"common":"BBBB"}')); controller.close();
    expect((await upload).status).toBe(410);
  });
  it("cancels a stalled reader at its deadline", async () => {
    const cancel = vi.fn();
    const body = new ReadableStream<Uint8Array>({ cancel }, { highWaterMark: 0 });
    const result = await readJsonObject(new Request("https://sync.test/body", { method: "PUT", headers: { "Content-Type": "application/json" }, body }), 1024, 10);
    expect(result).toMatchObject({ ok: false, result: { status: 408 } }); expect(cancel).toHaveBeenCalled();
  });
});
