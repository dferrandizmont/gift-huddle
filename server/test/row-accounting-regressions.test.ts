import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { ListStorageBudget, StorageBlocksNeeded } from "../src/list-storage-budget";
import type { RowStatus } from "../src/daily-row-budget";
import { RecoveryStore } from "../src/recovery-store";
import { recoveryReadVerifier } from "../src/recovery-contract";
import { canonicalJson } from "../src/v2-contract";
import { LIST_TTL_MS, V2_CLIENT_ROWS_PER_DAY, V2_GLOBAL_LIST_ROWS_PER_DAY, V2_ROW_REPORT_MS, V2_STORAGE_BLOCK_BYTES } from "../src/limits";
import { b64u, call, newList, rand } from "./helpers";

const key = () => b64u(rand(32));
const operation = () => b64u(rand(16));
const list = (sid: string) => env.LISTS_V2.get(env.LISTS_V2.idFromName(sid));
const ledger = () => env.STORAGE_LEDGER.get(env.STORAGE_LEDGER.idFromName("v2:storage"));
const client = (ip: string) => env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:rows:${ip}`));
const snapshot = () => ({ deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: key() }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
const create = async () => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
  return { ...id, path };
};
type Setup = Awaited<ReturnType<typeof create>>;
type Internal = { budget: ListStorageBudget; rowCounter: (key: string, amount?: number) => Promise<RowStatus>; notify: (m: any) => void };
const meta = (id: Setup) => runInDurableObject(list(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data));
const edit = (id: Setup, change: (m: any) => void) => runInDurableObject(list(id.syncId), (_o, s) => {
  const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
  change(m); s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
});
const put = (id: Setup, version = 1) => call("PUT", `${id.path}/common`, { key: id.key, ip: id.ip, headers: { "If-Match": `"${version}"` }, body: { common: "BBBB" } });
const quota = (stub: ReturnType<typeof ledger> | ReturnType<typeof client>) => runInDurableObject(stub, (_o, s) => s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'row_quota'").toArray().length ? s.storage.sql.exec<{ written: number }>("SELECT written FROM row_quota").one().written : 0);
function capsule(rid: string) {
  const header = new TextEncoder().encode(canonicalJson({ k: "capsule", kdf: { a: "argon2id", m: 19456, p: 1, t: 2 }, rid, r: 1, s: b64u(new Uint8Array(16)), v: 2 }));
  const bytes = new Uint8Array(4096);
  bytes.set([0x47, 0x48, 0x52, 2, header.length >> 8, header.length & 255]); bytes.set(header, 6);
  return b64u(bytes);
}
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe("row accounting at admission and after commit", () => {
  it.each(["client", "global"] as const)("writes zero rows for repeated exhausted %s rejections across minutes and eviction", async (kind) => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime((Math.floor(Date.now() / 86400000) + 1) * 86400000 + 3600000);
    const id = await create();
    await edit(id, (m) => { for (const entry of Object.values(m.rowReports.keys) as any[]) { entry.pending = 0; entry.checkedAt = 0; } });
    if (kind === "global") await ledger().rows(V2_GLOBAL_LIST_ROWS_PER_DAY);
    else await client(id.ip).rows(V2_CLIENT_ROWS_PER_DAY, V2_CLIENT_ROWS_PER_DAY);
    const stubs = [list(id.syncId), ledger(), client(id.ip)];
    let writes = 0, reports = 0, queries = 0;
    const observe = async () => {
      for (const stub of stubs) await runInDurableObject(stub, (_o, s) => {
        const exec = s.storage.sql.exec.bind(s.storage.sql);
        vi.spyOn(s.storage.sql, "exec").mockImplementation((q, ...args) => { const c = exec(q, ...args); writes += c.rowsWritten; return c; });
      });
      await runInDurableObject(list(id.syncId), (o) => {
        const internal = o as unknown as Internal, counter = internal.rowCounter.bind(internal);
        vi.spyOn(internal, "rowCounter").mockImplementation((k, amount = 0) => {
          if (amount) reports++;
          else if (k === (kind === "global" ? "global" : `v2:rows:${id.ip}`)) queries++;
          return counter(k, amount);
        });
      });
    };
    await observe();
    for (let n = 0; n < 8; n++) {
      vi.setSystemTime(Date.now() + 61_000);
      expect((await put(id)).status).toBe(429);
      if (n === 3) {
        vi.restoreAllMocks();
        await evictDurableObject(list(id.syncId));
        await observe();
      }
    }
    expect(writes).toBe(0); expect(reports).toBe(0); expect(queries).toBe(2);
  });

  it.each([false, true])("keeps an idle tail without an alarm and charges it on the next day's GET (near midnight: %s)", async (nearMidnight) => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const day = Math.floor(Date.now() / 86400000) + 1, midnight = (day + 1) * 86400000;
    vi.setSystemTime(nearMidnight ? midnight - 1 : day * 86400000 + 3600000);
    const id = await create(), saved = await meta(id);
    await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.getAlarm()).toBeGreaterThan(midnight));
    await evictDurableObject(list(id.syncId));
    vi.setSystemTime(midnight + 1);
    expect((await call("GET", id.path, { key: id.key, ip: id.ip })).status).toBe(200);
    expect(await quota(ledger())).toBe(saved.rowReports.keys.global.pending);
    expect(await quota(client(id.ip))).toBe(saved.rowReports.keys[`v2:rows:${id.ip}`].pending);
    const after = await meta(id);
    expect(after.rowReports.keys.global.day).toBe(day + 1);
    expect(after.rowReports.keys.global.pending).toBeLessThan(25);
    await runInDurableObject(ledger(), (_o, s) => expect(s.storage.sql.exec<{ day: number }>("SELECT day FROM row_quota").one().day).toBe(day + 1));
  });

  it("does not turn accounting writes into new pending reports", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime((Math.floor(Date.now() / 86400000) + 1) * 86400000 + 3600000);
    const id = await create();
    vi.setSystemTime(Date.now() + 1);
    // Warm activity so only the acknowledgement changes state on the next GET.
    await call("GET", id.path, { key: id.key, ip: id.ip });
    const before = await meta(id);
    vi.setSystemTime(Date.now() + V2_ROW_REPORT_MS);
    expect((await call("GET", id.path, { key: id.key, ip: id.ip })).status).toBe(200);
    const after = await meta(id);
    expect(after.rowBudget.written).toBe(before.rowBudget.written + 1);
    for (const entry of Object.values(after.rowReports.keys) as any[]) expect(entry.pending).toBe(0);
    const billed = await quota(ledger());
    vi.setSystemTime(Date.now() + V2_ROW_REPORT_MS);
    await call("GET", id.path, { key: id.key, ip: id.ip });
    expect(await quota(ledger())).toBe(billed);
    expect((await meta(id)).rowBudget).toEqual(after.rowBudget);
  });

  it("uses at most one reporting round per day for one daily PUT", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const start = (Math.floor(Date.now() / 86400000) + 1) * 86400000 + 3600001;
    vi.setSystemTime(start);
    const id = await create();
    let reports = 0;
    await runInDurableObject(list(id.syncId), (o) => {
      const internal = o as unknown as Internal, counter = internal.rowCounter.bind(internal);
      vi.spyOn(internal, "rowCounter").mockImplementation((k, amount = 0) => {
        if (amount) reports++;
        return counter(k, amount);
      });
    });
    for (let day = 1; day <= 3; day++) {
      const before = (await meta(id)).rowReports.keys.global.pending;
      vi.setSystemTime(start + day * 86400000);
      expect((await put(id, day)).status).toBe(200);
      expect(reports).toBe(day * 2);
      expect(await quota(ledger())).toBe(before);
      expect(await quota(client(id.ip))).toBe(before);
      await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.getAlarm()).toBeGreaterThan(Date.now() + 3600000));
    }
  });

  it("charges a report whose RPC crosses midnight on the counter's current day", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const midnight = (Math.floor(Date.now() / 86400000) + 2) * 86400000;
    vi.setSystemTime(midnight - 3600000);
    const id = await create(), before = await meta(id);
    await runInDurableObject(list(id.syncId), (o) => {
      const internal = o as unknown as Internal, counter = internal.rowCounter.bind(internal);
      vi.spyOn(internal, "rowCounter").mockImplementation((k, amount = 0) => {
        if (amount) vi.setSystemTime(midnight + 1);
        return counter(k, amount);
      });
    });
    vi.setSystemTime(midnight - 1);
    expect((await call("GET", id.path, { key: id.key, ip: id.ip })).status).toBe(200);
    expect(await quota(ledger())).toBe(before.rowReports.keys.global.pending);
    expect(await quota(client(id.ip))).toBe(before.rowReports.keys[`v2:rows:${id.ip}`].pending);
    await runInDurableObject(ledger(), (_o, s) => expect(s.storage.sql.exec<{ day: number }>("SELECT day FROM row_quota").one().day).toBe(Math.floor(midnight / 86400000)));
  });

  it("removes a short retry after its overdue report succeeds", async () => {
    const id = await create();
    await runInDurableObject(list(id.syncId), async (o, s) => {
      (o as unknown as { rowRetryAt: number }).rowRetryAt = Date.now() - 1;
      await s.storage.setAlarm(Date.now() + 30_000);
    });
    expect((await call("GET", id.path, { key: id.key, ip: id.ip })).status).toBe(200);
    await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.getAlarm()).toBeGreaterThan(Date.now() + 3600000));
  });

  it("keeps reconciliation at +30 seconds with an overdue row retry", async () => {
    const id = await create(), now = Date.now(), next = now + 30_000;
    await runInDurableObject(list(id.syncId), async (o, s) => {
      const internal = o as unknown as { rowRetryAt: number; scheduleAlarm: (at: number) => Promise<void> };
      internal.rowRetryAt = now - 1000;
      await s.storage.put("storageLedger", { blocks: 1, pending: true });
      await s.storage.setAlarm(next);
      await internal.scheduleAlarm(now + LIST_TTL_MS);
      expect(await s.storage.getAlarm()).toBe(next);
      await s.storage.delete("storageLedger");
      await s.storage.deleteAlarm();
      const beforeSchedule = Date.now();
      await internal.scheduleAlarm(now + LIST_TTL_MS);
      const afterSchedule = Date.now();
      const alarmAt = await s.storage.getAlarm();
      expect(alarmAt).toBeGreaterThanOrEqual(beforeSchedule + 60_000);
      expect(alarmAt).toBeLessThanOrEqual(afterSchedule + 60_000);
    });
  });

  it("does not rearm a valid retry on a false Bearer GET", async () => {
    const id = await create();
    let alarms = 0;
    await runInDurableObject(list(id.syncId), async (o, s) => {
      const next = Date.now() + 60_000;
      (o as unknown as { rowRetryAt: number }).rowRetryAt = next;
      await s.storage.setAlarm(next);
      vi.spyOn(s.storage, "setAlarm").mockImplementation(async () => { alarms++; });
    });
    expect((await call("GET", id.path, { key: key(), ip: id.ip })).status).toBe(401);
    expect(alarms).toBe(0);
  });

  it("rejects before commit when a required counter query fails", async () => {
    const id = await create();
    await edit(id, (m) => { for (const e of Object.values(m.rowReports.keys) as any[]) { e.pending = 0; e.checkedAt = 0; } });
    await runInDurableObject(list(id.syncId), (o) => { vi.spyOn(o as unknown as Internal, "rowCounter").mockRejectedValue(new Error("Counter unavailable")); });
    expect((await put(id)).status).toBe(429);
    expect((await meta(id)).version).toBe(1);
  });

  it.each(["client", "global"] as const)("preserves a committed PUT and its notification when the %s report throws", async (kind) => {
    const id = await create();
    await edit(id, (m) => { for (const entry of Object.values(m.rowReports.keys) as any[]) entry.pending = 24; });
    const initial = await meta(id);
    let failures = 0, notified = false;
    await runInDurableObject(list(id.syncId), (o, s) => {
      const internal = o as unknown as Internal, counter = internal.rowCounter.bind(internal);
      vi.spyOn(internal, "notify").mockImplementation((m) => { notified = m.version === 2; });
      vi.spyOn(internal, "rowCounter").mockImplementation((k, amount = 0) => {
        const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
        if (amount && m.version === 2 && k === (kind === "global" ? "global" : `v2:rows:${id.ip}`)) { failures++; throw new Error("Counter unavailable"); }
        return counter(k, amount);
      });
    });
    expect((await put(id)).status).toBe(200);
    expect(failures).toBe(1); expect(notified).toBe(true);
    const saved = await meta(id);
    expect(saved.version).toBe(2);
    expect(saved.rowReports.keys[kind === "global" ? "global" : `v2:rows:${id.ip}`].pending).toBeGreaterThanOrEqual(25);
    await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.getAlarm()).toBeLessThanOrEqual(Date.now() + 60_000));
    vi.restoreAllMocks(); await evictDurableObject(list(id.syncId));
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    const after = await meta(id);
    // The PUT adds activity + common + state; acknowledgement rows stay local.
    expect(await quota(client(id.ip))).toBe(27);
    expect(after.rowBudget.written - initial.rowBudget.written).toBeGreaterThan(3);
  });

  it.each([
    ["invitation", "throws"], ["recovery", "throws"],
    ["invitation", "exhausted"], ["recovery", "exhausted"],
  ] as const)("finishes a confirmed %s when reporting %s", async (kind, outcome) => {
    const id = await create(), inviteId = operation(), rid = key(), cap = key();
    let failures = 0;
    await runInDurableObject(list(id.syncId), (o, s) => {
      const internal = o as unknown as Internal, counter = internal.rowCounter.bind(internal);
      const internalReports = o as unknown as { reportRows: (force?: string) => Promise<void> };
      const report = internalReports.reportRows.bind(o);
      vi.spyOn(internalReports, "reportRows").mockImplementation(async (force) => {
        const confirmed = kind === "invitation"
          ? s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'pending_release'").toArray().length > 0
          : new RecoveryStore(s.storage.sql).get(rid)?.published === true;
        return report(confirmed ? "global" : force);
      });
      vi.spyOn(internal, "rowCounter").mockImplementation((k, amount = 0) => {
        const confirmed = kind === "invitation"
          ? s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'pending_release'").toArray().length > 0
          : new RecoveryStore(s.storage.sql).get(rid)?.published === true;
        if (amount && confirmed) {
          failures++;
          if (outcome === "throws") throw new Error("Counter unavailable");
          return Promise.resolve({ day: Math.floor(Date.now() / 86400000), remaining: 0, exhausted: true });
        }
        return counter(k, amount);
      });
    });
    const response = kind === "invitation"
      ? await call("POST", `${id.path}/invites`, { key: id.key, ip: id.ip, body: { inviteId, offer: { v: 2, host: { d: "aritz" }, c: key() } } })
      : await call("PUT", `${id.path}/recoveries/${rid}`, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"', "X-Recovery-Operation": operation() }, body: { v: 2, deviceId: "aritz", readVerifier: await recoveryReadVerifier(cap), capsule: capsule(rid) } });
    expect(response.status).toBe(201);
    if (outcome === "throws") expect(failures).toBe(1);
    else expect(failures).toBeGreaterThan(0);
    await runInDurableObject(list(id.syncId), async (_o, s) => {
      if (kind === "invitation") expect(s.storage.sql.exec("SELECT id FROM invite WHERE id = ?", inviteId).toArray()).toHaveLength(1);
      else expect(new RecoveryStore(s.storage.sql).get(rid)).toMatchObject({ state: "active", published: true });
      if (outcome === "throws") expect(await s.storage.getAlarm()).toBeLessThanOrEqual(Date.now() + 60_000);
    });
    if (kind === "invitation") await runInDurableObject(env.INVITES_V2.get(env.INVITES_V2.idFromName(inviteId)), async (_o, s) => expect(await s.storage.get("locator")).toBeDefined());
    else expect((await call("GET", `/v2/recoveries/${rid}`, { headers: { "X-Recovery-Cap": cap } })).status).toBe(200);
    if (outcome === "throws") {
      const pending = (await meta(id)).rowReports.keys.global.pending, billed = await quota(ledger());
      expect(pending).toBeGreaterThan(0);
      vi.restoreAllMocks(); await evictDurableObject(list(id.syncId));
      expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
      expect(await quota(ledger())).toBeGreaterThanOrEqual(billed + pending);
    }
  });

  it.each([false, true])("drains a capped list while rejecting new mutations (failed report: %s)", async (fail) => {
    const id = await create();
    await edit(id, (m) => { m.rowBudget.written = 6000; for (const e of Object.values(m.rowReports.keys) as any[]) e.pending = 37; });
    await evictDurableObject(list(id.syncId));
    if (fail) await runInDurableObject(list(id.syncId), (o) => { vi.spyOn(o as unknown as Internal, "rowCounter").mockRejectedValue(new Error("Counter unavailable")); });
    expect((await put(id)).status).toBe(429);
    if (fail) {
      expect((await meta(id)).rowReports.keys.global.pending).toBe(37);
      await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.getAlarm()).toBeLessThanOrEqual(Date.now() + 60_000));
      vi.restoreAllMocks(); await evictDurableObject(list(id.syncId));
      expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    }
    expect(await quota(ledger())).toBeGreaterThanOrEqual(37);
    expect((await meta(id)).version).toBe(1);
  });

  it("reserves the first snapshot including row reports at a storage block boundary", async () => {
    const sample = await create(), saved = await meta(sample), body = snapshot();
    const oldSize = saved.storedBytes - JSON.stringify(saved.rowReports).length - '\"rowReports\":,'.length;
    // Leave room under the old estimate, but cross the block once reports fit.
    body.common = "A".repeat(4 + V2_STORAGE_BLOCK_BYTES - oldSize - 80);
    const id = newList();
    let probes = 0;
    await runInDurableObject(list(id.syncId), (o) => {
      const budget = (o as unknown as Internal).budget, stage = budget.stage.bind(budget);
      vi.spyOn(budget, "stage").mockImplementation((...args) => { try { return stage(...args); } catch (e) { if (e instanceof StorageBlocksNeeded) probes++; throw e; } });
    });
    expect((await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body })).status).toBe(201);
    expect(probes).toBe(0);
    const after = await meta({ ...id, path: `/v2/lists/${id.syncId}` });
    expect(after.storedBytes).toBeGreaterThan(V2_STORAGE_BLOCK_BYTES);
    expect(after.rowBudget.written).toBe(19);
    expect(after.rowReports.keys.global.pending).toBe(19);
  });

  it.each([false, true])("retains reverted first-creation rows across eviction and retry (existing alarm: %s)", async (drain) => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime((Math.floor(Date.now() / 86400000) + 1) * 86400000 + 3600000);
    const id = newList();
    let written = 0;
    await runInDurableObject(list(id.syncId), async (o, s) => {
      const budget = (o as unknown as Internal).budget, day = Math.floor(Date.now() / 86400000), now = Date.now();
      budget.rowContext = { keys: ["global"], reports: { day, keys: { global: { day, remaining: V2_GLOBAL_LIST_ROWS_PER_DAY, exhausted: false, pending: 0, checkedAt: now, reportedAt: now, usedAt: now } } } };
      const exec = s.storage.sql.exec.bind(s.storage.sql);
      vi.spyOn(s.storage.sql, "exec").mockImplementation((q, ...args) => { const c = exec(q, ...args); written += c.rowsWritten; return c; });
      expect(() => budget.stage(() => {
        budget.sql.exec("CREATE TABLE state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)");
        budget.sql.exec("INSERT INTO state VALUES (1, ?)", JSON.stringify(budget.decorate({ credentials: [], version: 1 })));
      }, 0)).toThrow(StorageBlocksNeeded);
      expect(s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'state'").toArray()).toHaveLength(0);
      const debt = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM row_attempts").one().data);
      expect(debt.rowBudget.written).toBe(written);
      expect(debt.rowReports.keys.global.pending).toBe(written - 3);
      await (o as unknown as { settleRows: () => Promise<void> }).settleRows();
      expect(await s.storage.getAlarm()).toBe(now + LIST_TTL_MS);
    });
    const reverted = written;
    vi.restoreAllMocks(); await evictDurableObject(list(id.syncId));
    await runInDurableObject(list(id.syncId), (_o, s) => {
      const exec = s.storage.sql.exec.bind(s.storage.sql);
      vi.spyOn(s.storage.sql, "exec").mockImplementation((q, ...args) => { const c = exec(q, ...args); written += c.rowsWritten; return c; });
    });
    if (drain) {
      vi.setSystemTime(Date.now() + V2_ROW_REPORT_MS);
      await runInDurableObject(list(id.syncId), async (_o, s) => { await s.storage.setAlarm(Date.now()); });
      expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
      expect(await quota(ledger())).toBe(reverted - 3);
    }
    expect((await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
    const after = await meta({ ...id, path: `/v2/lists/${id.syncId}` });
    expect(after.rowBudget.written).toBe(written);
    expect(written).toBeGreaterThan(reverted + 18);
    expect(await quota(ledger())).toBe(after.rowBudget.written - after.rowReports.keys.global.pending - (drain ? 4 : 3));
  });
  it.each(["request", "alarm"] as const)("expires orphan attempt accounting through %s", async (wake) => {
    const id = newList();
    await runInDurableObject(list(id.syncId), async (o, s) => {
      s.storage.sql.exec("CREATE TABLE row_attempts (id INTEGER PRIMARY KEY, data TEXT NOT NULL)");
      s.storage.sql.exec("INSERT INTO row_attempts VALUES (1, ?)", JSON.stringify({ expiresAt: Date.now() - 1, rowBudget: { day: 0, written: 3 } }));
      await s.storage.setAlarm(Date.now());
      (o as unknown as Internal).budget = new ListStorageBudget(s.storage);
    });
    if (wake === "request") expect((await call("GET", `/v2/lists/${id.syncId}`, { key: id.key })).status).toBe(404);
    else expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    await runInDurableObject(list(id.syncId), async (_o, s) => {
      expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite%' AND name NOT LIKE '_cf%'").toArray()).toEqual([]);
      expect(await s.storage.getAlarm()).toBeNull();
    });
  });

  it("cleans legacy attempt rows beside a retirement marker without a short alarm", async () => {
    const id = await create();
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '\"1\"' } })).status).toBe(204);
    const deadline = await runInDurableObject(list(id.syncId), async (_o, s) => {
      s.storage.sql.exec("CREATE TABLE IF NOT EXISTS row_attempts (id INTEGER PRIMARY KEY, data TEXT NOT NULL)");
      s.storage.sql.exec("INSERT INTO row_attempts VALUES (1, ?)", JSON.stringify({ rowBudget: { day: 0, written: 4 } }));
      return s.storage.getAlarm();
    });
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    await runInDurableObject(list(id.syncId), async (_o, s) => {
      expect(s.storage.sql.exec("SELECT * FROM state").toArray()).toEqual([{ id: 1, data: '{"retired":true}' }]);
      expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE name = 'row_attempts'").toArray()).toEqual([]);
      expect(await s.storage.getAlarm()).toBe(deadline);
    });
  });

});
