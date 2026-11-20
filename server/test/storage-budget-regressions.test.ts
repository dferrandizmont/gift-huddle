import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { ListStorageBudget, ListTooLarge } from "../src/list-storage-budget";
import { InviteV2Object } from "../src/invite-v2-object";
import { RecoveryLocatorObject } from "../src/recovery-locator-object";
import { RecoveryStore } from "../src/recovery-store";
import { recoveryReadVerifier } from "../src/recovery-contract";
import { canonicalJson } from "../src/v2-contract";
import { TOUCH_INTERVAL_MS, V2_LIST_BASE_BYTES, V2_STORAGE_BLOCK_BYTES } from "../src/limits";
import { b64u, call, newList, rand } from "./helpers";

const key = () => b64u(rand(32));
const operation = () => b64u(rand(16));
const list = (sid: string) => env.LISTS_V2.get(env.LISTS_V2.idFromName(sid));
const inviteLocator = (id: string) => env.INVITES_V2.get(env.INVITES_V2.idFromName(id));
const recoveryLocator = (rid: string) => env.RECOVERIES_V2.get(env.RECOVERIES_V2.idFromName(rid));
type BudgetOwner = { budget: ListStorageBudget };
type Meta = { storedBytes: number; version: number; lastAccess: number; credentials: { lastRequest?: number; commonFormat?: number; renewalProtocol?: number }[] };
function expectOnlyAccountingChanged(after: Meta, before: Meta) {
  const { storedBytes: _a, rowBudget: rowsAfter, rowReports: _reportsAfter, ...a } = after as Meta & { rowBudget: { written: number }; rowReports?: unknown };
  const { storedBytes: _b, rowBudget: rowsBefore, rowReports: _reportsBefore, ...b } = before as Meta & { rowBudget: { written: number }; rowReports?: unknown };
  expect(a).toEqual(b);
  expect(rowsAfter.written).toBeGreaterThan(rowsBefore.written);
}
const setup = async () => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  const body = { deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: key() }], vouches: [], revocations: [] }, keyPackages: [], slots: [] };
  expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body })).status).toBe(201);
  expect((await call("GET", path, { key: id.key, ip: id.ip })).status).toBe(200);
  return { ...id, path };
};
type Setup = Awaited<ReturnType<typeof setup>>;
const meta = (id: Setup) => runInDurableObject(list(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as Meta);

/** Simulate exact boundary and legacy oversized lists without API body caps.
 * Reset accounting just as on eviction, then persist the cold scan's total. */
async function fill(id: Setup, remaining = 0) {
  await runInDurableObject(list(id.syncId), (o, s) => {
    const raw = s.storage.sql;
    const m = JSON.parse(raw.exec<{ data: string }>("SELECT data FROM state").one().data);
    delete m.storedBytes;
    raw.exec("UPDATE state SET data = ?", JSON.stringify(m));
    const current = new ListStorageBudget(s.storage).decorate(m).storedBytes as number;
    const common = raw.exec<{ data: string }>("SELECT data FROM common WHERE idx = 0").one().data;
    raw.exec("UPDATE common SET data = ? WHERE idx = 0", "A".repeat(common.length + V2_LIST_BASE_BYTES - remaining - current));
    const budget = new ListStorageBudget(s.storage);
    (o as unknown as BudgetOwner).budget = budget;
    budget.transaction(() => undefined, true);
    // The row counter is part of state: a decimal digit boundary can add a
    // byte during accounting itself. Settle the fixture to the exact target.
    const counted = JSON.parse(raw.exec<{ data: string }>("SELECT data FROM state").one().data);
    const delta = counted.storedBytes - (V2_LIST_BASE_BYTES - remaining);
    if (delta) {
      const text = raw.exec<{ data: string }>("SELECT data FROM common WHERE idx = 0").one().data;
      raw.exec("UPDATE common SET data = ? WHERE idx = 0", text.slice(0, text.length - delta));
      delete counted.storedBytes;
      raw.exec("UPDATE state SET data = ?", JSON.stringify(counted));
      const exact = new ListStorageBudget(s.storage);
      (o as unknown as BudgetOwner).budget = exact;
      exact.transaction(() => undefined, true);
    }
    expect(JSON.parse(raw.exec<{ data: string }>("SELECT data FROM state").one().data).storedBytes).toBe(V2_LIST_BASE_BYTES - remaining);
  });
  // This fixture changes storage outside the API. Enrol its new blocks before
  // observing the side effects of the request under test.
  await runInDurableObject(list(id.syncId), async (o, s) => {
    const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
    const blocks = Math.ceil(m.storedBytes / V2_STORAGE_BLOCK_BYTES);
    const ns = env.STORAGE_LEDGER;
    await ns.get(ns.idFromName("v2:storage")).set(s.id.toString(), blocks, true);
    await s.storage.put("storageLedger", { blocks });
    (o as unknown as { ledgerBlocks: number }).ledgerBlocks = blocks;
  });
}
async function expectAccurate(id: Setup) {
  await runInDurableObject(list(id.syncId), (_o, s) => {
    const raw = s.storage.sql, saved = raw.exec<{ data: string }>("SELECT data FROM state").one().data;
    const m = JSON.parse(saved), expected = m.storedBytes;
    delete m.storedBytes;
    raw.exec("UPDATE state SET data = ?", JSON.stringify(m));
    try { expect(new ListStorageBudget(s.storage).decorate(m).storedBytes).toBe(expected); }
    finally { raw.exec("UPDATE state SET data = ?", saved); }
  });
}
const recoveryRows = (id: Setup) => runInDurableObject(list(id.syncId), (_o, s) => new RecoveryStore(s.storage.sql).rows());
const quota = (id: Setup) => runInDurableObject(list(id.syncId), (_o, s) => s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'recovery_quota'").toArray().length ? s.storage.sql.exec<{ data: string }>("SELECT data FROM recovery_quota").one().data : null);
const pending = (id: Setup, table: "pending_release" | "recovery_release") => runInDurableObject(list(id.syncId), (_o, s) => s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = ?", table).toArray().length ? s.storage.sql.exec(`SELECT * FROM ${table}`).toArray() : []);
function capsule(rid: string, size = 4096): string {
  const header = new TextEncoder().encode(canonicalJson({ k: "capsule", kdf: { a: "argon2id", m: 19456, p: 1, t: 2 }, rid, r: 1, s: b64u(new Uint8Array(16)), v: 2 }));
  const bytes = new Uint8Array(size);
  bytes.set([0x47, 0x48, 0x52, 2, header.length >> 8, header.length & 255]); bytes.set(header, 6);
  return b64u(bytes);
}
async function draft(id: Setup, parent?: string) {
  const rid = key(), cap = key(), op = operation();
  const body = { v: 2, readVerifier: await recoveryReadVerifier(cap), capsule: capsule(rid), ...(parent ? { operationId: op, newRecoveryId: rid } : { deviceId: "aritz" }) };
  const send = () => call(parent ? "POST" : "PUT", parent ? `${id.path}/recoveries/${parent}/rotation` : `${id.path}/recoveries/${rid}`, { key: id.key, ip: id.ip, headers: { "If-Match": parent ? '"1"' : '"0"', "X-Recovery-Operation": op }, body });
  return { rid, body, send };
}
afterEach(() => vi.restoreAllMocks());

describe("transactional storage budget regressions", () => {
  it("keeps uncommitted row-status caches out of the ledger balance", async () => {
    const id = await setup(); await fill(id);
    await runInDurableObject(list(id.syncId), (o, s) => {
      const internal = o as unknown as BudgetOwner & { currentBlocks: () => number };
      const saved = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      const reports = structuredClone(saved.rowReports);
      reports.keys[`v2:rows:${newList().ip}`] = { ...reports.keys.global };
      internal.budget.rowContext = { keys: [], reports };
      try { expect(internal.currentBlocks()).toBe(V2_LIST_BASE_BYTES / V2_STORAGE_BLOCK_BYTES); }
      finally { internal.budget.rowContext = undefined; }
    });
  });

  it("repeated oversized invitations create no remote reservation, alarm or local queue", async () => {
    const id = await setup(); await fill(id, 100);
    const before = await meta(id);
    let alarms = 0;
    await runInDurableObject(list(id.syncId), (_o, s) => { vi.spyOn(s.storage, "setAlarm").mockImplementation(async () => { alarms++; }); });
    for (let n = 0; n < 12; n++) {
      const inviteId = operation();
      const response = await call("POST", `${id.path}/invites`, { key: id.key, ip: id.ip, body: { inviteId, offer: { v: 2, host: { d: "aritz" }, c: key() } } });
      expect(response.status).toBe(413); expect(await response.json()).toEqual({ error: "too_large" });
      await runInDurableObject(inviteLocator(inviteId), async (_o, s) => {
        expect(await s.storage.get("locator")).toBeUndefined(); expect(await s.storage.getAlarm()).toBeNull();
      });
    }
    expect(alarms).toBe(0);
    expect(await pending(id, "pending_release")).toEqual([]);
    expectOnlyAccountingChanged(await meta(id), before);
    await runInDurableObject(list(id.syncId), (_o, s) => expect(s.storage.sql.exec("SELECT * FROM invite").toArray()).toEqual([]));
    await expectAccurate(id);
  });

  it.each(["response", "commit"] as const)("durably cancels an invitation when reserve succeeds but the %s fails", async (failure) => {
    const id = await setup(), inviteId = operation(), stub = inviteLocator(inviteId);
    const reserve = InviteV2Object.prototype.reserve, release = InviteV2Object.prototype.release;
    await runInDurableObject(stub, (o) => {
      if (failure === "response") Object.getPrototypeOf(o).reserve = async function(this: InviteV2Object, ...args: Parameters<InviteV2Object["reserve"]>) { await reserve.apply(this, args); throw new Error("lost reservation response"); };
      Object.getPrototypeOf(o).release = async () => { throw new Error("cleanup unavailable"); };
    });
    if (failure === "commit") await runInDurableObject(list(id.syncId), (o) => {
      const internal = o as unknown as { saveInvite: (i: unknown) => void }, save = internal.saveInvite.bind(internal);
      let writes = 0;
      vi.spyOn(internal, "saveInvite").mockImplementation((i) => {
        if (++writes === 2) throw new Error("local invitation commit failed");
        save(i);
      });
    });
    try {
      expect((await call("POST", `${id.path}/invites`, { key: id.key, ip: id.ip, body: { inviteId, offer: { v: 2, host: { d: "aritz" }, c: key() } } })).status).toBe(500);
      expect(await pending(id, "pending_release")).toHaveLength(1);
      await expectAccurate(id);
    } finally {
      await runInDurableObject(stub, (o) => { Object.getPrototypeOf(o).reserve = reserve; Object.getPrototypeOf(o).release = release; });
    }
    await evictDurableObject(list(id.syncId));
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    expect(await pending(id, "pending_release")).toEqual([]);
    await runInDurableObject(stub, async (_o, s) => expect(await s.storage.get("locator")).toMatchObject({ released: true }));
    await expectAccurate(id);
  });

  it.each(["create", "rotate"] as const)("rejects the full %s footprint before quota, alarms or discovery, and permits a fresh attempt", async (kind) => {
    const id = await setup(), old = kind === "rotate" ? await draft(id) : undefined;
    if (old) expect((await old.send()).status).toBe(201);
    // The intention fits, and the blob alone fits; their combined metadata and
    // locator queue exceed the remaining bytes.
    const request = await draft(id, old?.rid);
    await fill(id, request.body.capsule.length + 300);
    const before = await meta(id), beforeQuota = await quota(id), beforeRows = await recoveryRows(id);
    let alarms = 0;
    await runInDurableObject(list(id.syncId), (_o, s) => {
      const original = s.storage.setAlarm.bind(s.storage);
      vi.spyOn(s.storage, "setAlarm").mockImplementation(async (time) => { alarms++; await original(time); });
    });
    expect((await request.send()).status).toBe(413);
    expect(alarms).toBe(0);
    expect(await quota(id)).toBe(beforeQuota); expectOnlyAccountingChanged(await meta(id), before); expect(await recoveryRows(id)).toEqual(beforeRows);
    expect(await pending(id, "recovery_release")).toEqual([]);
    await runInDurableObject(recoveryLocator(request.rid), async (_o, s) => { expect(await s.storage.get("locator")).toBeUndefined(); expect(await s.storage.getAlarm()).toBeNull(); });
    await expectAccurate(id);
    await fill(id, 20000);
    const fresh = await draft(id, old?.rid);
    expect((await fresh.send()).status).toBe(201);
    await expectAccurate(id);
  });

  it.each(["create", "rotate"] as const)("never replays a successful %s receipt after the reserved recovery's local commit fails", async (kind) => {
    const id = await setup(), old = kind === "rotate" ? await draft(id) : undefined;
    if (old) expect((await old.send()).status).toBe(201);
    const request = await draft(id, old?.rid);
    await runInDurableObject(list(id.syncId), (o, s) => {
      const internal = o as unknown as { saveMeta: (m: unknown) => void }, save = internal.saveMeta.bind(internal);
      let failed = false;
      vi.spyOn(internal, "saveMeta").mockImplementation((m) => {
        save(m);
        const row = new RecoveryStore(s.storage.sql).get(request.rid);
        // Fail after all publication writes, inside the SQLite transaction.
        if (!failed && row?.published && row.state !== "retired") {
          failed = true;
          throw new ListTooLarge();
        }
      });
    });
    expect((await request.send()).status).toBe(413);
    const row = (await recoveryRows(id)).find((r) => r.rid === request.rid)!;
    expect(row.state).toBe("retired");
    await runInDurableObject(list(id.syncId), (_o, s) => expect(new RecoveryStore(s.storage.sql).blob(request.rid)).toBe(""));
    expect(await pending(id, "recovery_release")).toMatchObject([{ rid: request.rid, token: row.reservationId, action: "retire" }]);
    const beforeQuota = await quota(id);
    for (const reopen of [false, true]) {
      if (reopen) await evictDurableObject(list(id.syncId));
      const replay = await request.send();
      expect(replay.status).toBe(409);
      expect(await replay.json()).toEqual({ error: old ? "recovery_rotation_cancelled" : "recovery_retired" });
    }
    expect(row.published).toBe(false);
    if (old) {
      expect((await recoveryRows(id)).find((r) => r.rid === old.rid)!.state).toBe("active");
      await runInDurableObject(list(id.syncId), (_o, s) => expect(new RecoveryStore(s.storage.sql).blob(old.rid)).toBe(old.body.capsule));
    }
    expect(await quota(id)).toBe(beforeQuota);
    expect(await recoveryLocator(request.rid).locate()).toBeNull();
    await expectAccurate(id);
  });

  it("reserves interrupted recovery blobs locally so ordinary writes cannot spend their capacity", async () => {
    const id = await setup(), request = await draft(id), stub = recoveryLocator(request.rid), reserve = RecoveryLocatorObject.prototype.reserve;
    await fill(id, 8000);
    await runInDurableObject(stub, (o) => {
      Object.getPrototypeOf(o).reserve = async function(this: RecoveryLocatorObject, sid: string, token: string) { await reserve.call(this, sid, token); throw new Error("lost reservation response"); };
    });
    try { expect((await request.send()).status).toBe(503); }
    finally { await runInDurableObject(stub, (o) => { Object.getPrototypeOf(o).reserve = reserve; }); }
    expect((await recoveryRows(id))[0]!.state).toBe("intention");
    await runInDurableObject(list(id.syncId), (_o, s) => expect(new RecoveryStore(s.storage.sql).blob(request.rid)).toBe(request.body.capsule));
    const beforeQuota = await quota(id);
    await evictDurableObject(list(id.syncId));
    // A valid, growing common PUT cannot consume the reserved blob bytes.
    expect((await call("PUT", `${id.path}/common`, { key: id.key, ip: id.ip, headers: { "If-Match": '"1"' }, body: { common: "A".repeat(V2_LIST_BASE_BYTES - 1000) } })).status).toBe(413);
    expect((await request.send()).status).toBe(201);
    expect(await quota(id)).toBe(beforeQuota); await expectAccurate(id);
  });

  it.each(["route", "alarm"] as const)("expires a legacy intention without a blob above the limit through %s and durably retries cleanup", async (kind) => {
    const id = await setup(), request = await draft(id);
    expect((await request.send()).status).toBe(201);
    let token = "";
    await runInDurableObject(list(id.syncId), (_o, s) => {
      const store = new RecoveryStore(s.storage.sql), row = store.get(request.rid)!;
      row.state = "intention"; row.published = false; row.expiresAt = Date.now() - 1;
      token = row.reservationId; store.save(row);
      s.storage.sql.exec("DELETE FROM recovery_blob WHERE rid = ?", row.rid);
    });
    await fill(id, -100);
    const stub = recoveryLocator(request.rid), retire = RecoveryLocatorObject.prototype.retire;
    await runInDurableObject(stub, (o) => { Object.getPrototypeOf(o).retire = async () => { throw new Error("cleanup unavailable"); }; });
    try {
      if (kind === "route") expect((await call("GET", `${id.path}/recoveries`, { key: id.key, ip: id.ip })).status).toBe(200);
      else expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
      expect((await recoveryRows(id))[0]!.state).toBe("retired");
      expect(await pending(id, "recovery_release")).toMatchObject([{ token, action: "retire" }]);
      expect((await meta(id)).storedBytes).toBeGreaterThan(V2_LIST_BASE_BYTES + 100);
      await expectAccurate(id);
    } finally { await runInDurableObject(stub, (o) => { Object.getPrototypeOf(o).retire = retire; }); }
    await evictDurableObject(list(id.syncId));
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    expect(await pending(id, "recovery_release")).toEqual([]);
    expect(await stub.locate()).toBeNull(); await expectAccurate(id);
  });

  it("rejects state-only capability growth atomically and still permits activity above the limit", async () => {
    const id = await setup(); await fill(id);
    const before = await meta(id);
    const announce = () => call("POST", `${id.path}/capability`, { key: id.key, ip: id.ip, body: { commonFormat: 2, renewalProtocol: 1 } });
    const rejected = await announce();
    expect(rejected.status).toBe(413); expect(await rejected.json()).toEqual({ error: "too_large" });
    expectOnlyAccountingChanged(await meta(id), before); await expectAccurate(id);
    await evictDurableObject(list(id.syncId));
    expect((await announce()).status).toBe(413);
    await fill(id, 100);
    expect((await announce()).status).toBe(200);
    expect((await meta(id)).version).toBe(before.version + 1);
    expect((await announce()).status).toBe(200);
    await fill(id, -100);
    // Legacy activity fields can themselves grow when first rounded/recorded.
    await runInDurableObject(list(id.syncId), (o, s) => {
      const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      m.lastAccess = Date.now() - 2 * TOUCH_INTERVAL_MS;
      delete m.credentials[0].lastRequest; delete m.storedBytes;
      s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
      (o as unknown as BudgetOwner).budget = new ListStorageBudget(s.storage);
    });
    expect((await call("GET", id.path, { key: id.key, ip: id.ip })).status).toBe(200);
    expect((await meta(id)).lastAccess).toBeGreaterThan(before.lastAccess - TOUCH_INTERVAL_MS);
    expect((await meta(id)).credentials[0]!.lastRequest).toBeDefined();
    await expectAccurate(id);
  });

  it("enforces the same gate for direct state SQL and rolls back its storedBytes", async () => {
    const id = await setup(); await fill(id);
    await runInDurableObject(list(id.syncId), (_o, s) => {
      const budget = new ListStorageBudget(s.storage), before = s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data;
      const changed = { ...JSON.parse(before), extra: "growth" };
      expect(() => budget.sql.exec("UPDATE state SET data = ? WHERE id = 1", JSON.stringify(changed))).toThrow(ListTooLarge);
      expectOnlyAccountingChanged(JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data), JSON.parse(before));
    });
    await expectAccurate(id);
  });
});
