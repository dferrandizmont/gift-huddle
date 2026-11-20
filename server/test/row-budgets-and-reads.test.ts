import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { StorageLedgerObject } from "../src/storage-ledger-object";
import { ListStorageBudget, ListTooLarge } from "../src/list-storage-budget";
import { routeV2 } from "../src/v2-router";
import { dailyRows, type RowStatus } from "../src/daily-row-budget";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";
import { clientKey, clientKey48 } from "../src/ip";
import { LIST_TTL_MS, V2_BODY_READ_DEADLINE_MS, V2_CREDENTIAL_CAP_AGE_MS, V2_CLIENT_ROWS_PER_DAY, V2_CLIENT_ROWS_PER_DAY_48, V2_GLOBAL_LIST_ROWS_PER_DAY, V2_LIST_BASE_BYTES, V2_STORAGE_BLOCK_BYTES, WINDOW_MS, v2ListByteLimit } from "../src/limits";
import { b64u, call, newList, rand } from "./helpers";

const key = () => b64u(rand(32));
const ipv6 = () => `2001:db8:${Math.floor(Math.random() * 65535).toString(16)}:1200::1`;
const snapshot = () => ({ deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: key() }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
const list = (sid: string) => env.LISTS_V2.get(env.LISTS_V2.idFromName(sid));
const ledger = () => env.STORAGE_LEDGER.get(env.STORAGE_LEDGER.idFromName("v2:storage"));
const limiter = (name: string) => env.LIMITER_V2.get(env.LIMITER_V2.idFromName(name));
const create = async (ip?: string) => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  if (ip) id.ip = ip;
  expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
  return { ...id, path };
};
type Setup = Awaited<ReturnType<typeof create>>;
const edit = (id: Setup, change: (m: any) => void) => runInDurableObject(list(id.syncId), (_o, s) => {
  const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
  change(m); s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
});
const readMeta = (id: Setup) => runInDurableObject(list(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data));
const total = () => runInDurableObject(ledger(), (_o, s) => s.storage.sql.exec<{ n: number }>("SELECT COALESCE(SUM(blocks), 0) AS n FROM balances").one().n);
const put = (id: Setup, version = 1, common = "BBBB") => call("PUT", `${id.path}/common`, { key: id.key, ip: id.ip, headers: { "If-Match": `"${version}"` }, body: { common } });
const rowQuota = (stub: ReturnType<typeof limiter> | ReturnType<typeof ledger>) => runInDurableObject(stub, (_o, s) => s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'row_quota'").toArray().length ? s.storage.sql.exec<{ written: number }>("SELECT written FROM row_quota WHERE id = 1").toArray()[0]?.written ?? 0 : 0);
const verify = async (value: string) => encodeB64Url(await sha256(decodeB64Url(value, 32)!));
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

describe("account mutation row budgets", () => {
  it.each([V2_CLIENT_ROWS_PER_DAY, V2_CLIENT_ROWS_PER_DAY_48, V2_GLOBAL_LIST_ROWS_PER_DAY])("reports real rows against %i, queries without writes and resets at midnight", async (limit) => {
    const stub = limit === V2_GLOBAL_LIST_ROWS_PER_DAY ? ledger() : limiter(`test:rows:${limit}`);
    const rows = (amount = 0) => limit === V2_GLOBAL_LIST_ROWS_PER_DAY ? ledger().rows(amount) : limiter(`test:rows:${limit}`).rows(limit, amount);
    vi.useFakeTimers({ toFake: ["Date"] });
    const midnight = (Math.floor(Date.now() / 86400000) + 1) * 86400000;
    vi.setSystemTime(midnight - 1500);
    await runInDurableObject(stub, (_o, s) => {
      const exec = vi.spyOn(s.storage.sql, "exec");
      expect(dailyRows(s.storage, limit).remaining).toBe(limit);
      expect(exec.mock.calls.some(([q]) => /^(CREATE|INSERT|UPDATE|DELETE)/.test(q))).toBe(false);
      exec.mockRestore();
    });
    expect((await rows(limit - 1)).exhausted).toBe(false);
    expect((await rows(45)).exhausted).toBe(true);
    await evictDurableObject(stub);
    expect((await rows()).exhausted).toBe(true);
    expect(await rowQuota(stub)).toBe(limit + 44);
    vi.setSystemTime(midnight);
    expect((await rows()).remaining).toBe(limit);
    expect((await rows(7)).remaining).toBe(limit - 7);
    expect(await rowQuota(stub)).toBe(7);
  });

  it.each(["client", "48", "global"] as const)("enforces exhausted %s counters and preserves reads and cleanup", async (kind) => {
    const ip = kind === "48" ? ipv6() : newList().ip;
    const id = await create(ip);
    const limit = kind === "global" ? V2_GLOBAL_LIST_ROWS_PER_DAY : kind === "48" ? V2_CLIENT_ROWS_PER_DAY_48 : V2_CLIENT_ROWS_PER_DAY;
    if (kind === "global") await ledger().rows(limit);
    else await limiter(kind === "48" ? `v2:rows48:${clientKey48(ip)}` : `v2:rows:${ip}`).rows(limit, limit);
    await edit(id, (m) => { for (const entry of Object.values(m.rowReports.keys) as any[]) entry.checkedAt -= 60_001; });
    await evictDurableObject(list(id.syncId));
    const rejected = await put(id);
    expect(rejected.status).toBe(429);
    expect(Number(rejected.headers.get("Retry-After"))).toBeGreaterThan(0);
    expect(Number(rejected.headers.get("Retry-After"))).toBeLessThanOrEqual(3600);
    const next = newList();
    expect((await call("PUT", `/v2/lists/${next.syncId}`, { key: next.key, ip: kind === "48" ? ip.replace(":1200:", ":ff00:") : kind === "global" ? next.ip : ip, headers: { "If-Match": '\"0\"' }, body: snapshot() })).status).toBe(429);
    expect((await call("GET", id.path, { key: id.key, ip })).status).toBe(200);
    expect((await call("DELETE", id.path, { key: id.key, ip, headers: { "If-Match": '\"1\"' } })).status).toBe(204);
  });

  it("keeps small writes across many lists and evictions below real row consumption", async () => {
    // Each list is woken again after eviction. The former 500-row prepayments
    // exhausted this one household after twenty wakes.
    const ip = newList().ip;
    const ids: Setup[] = [];
    for (let n = 0; n < 10; n++) ids.push(await create(ip));
    for (const id of ids) for (let version = 1; version <= 4; version++) {
      await evictDurableObject(list(id.syncId));
      expect((await put(id, version, version % 2 ? "BBBB" : "AAAA")).status).toBe(200);
    }
    let actual = 0, pending = 0;
    for (const id of ids) {
      const m = await readMeta(id);
      actual += m.rowBudget.written;
      pending += m.rowReports.keys[`v2:rows:${ip}`].pending;
    }
    expect(await rowQuota(limiter(`v2:rows:${ip}`))).toBe(actual - pending - ids.length);
    expect(actual).toBeLessThan(1000);
    expect(await rowQuota(ledger())).toBeLessThanOrEqual(actual);
  });

  it("does not exhaust the global counter after 150 single-write lists and evictions", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const start = (Math.floor(Date.now() / 86400000) + 1) * 86400000;
    let actual = 0, pending = 0;
    for (let n = 0; n < 150; n++) {
      vi.setSystemTime(start + Math.floor(n / 50) * 3600000);
      const id = await create();
      await evictDurableObject(list(id.syncId));
      const m = await readMeta(id);
      actual += m.rowBudget.written;
      pending += m.rowReports.keys.global.pending;
    }
    expect(actual).toBeLessThan(4000);
    expect(await rowQuota(ledger())).toBe(actual - pending);
  }, 60_000);

  it("bounds saved keys and reports the oldest client's tail before eviction", async () => {
    const id = await create();
    let first = "";
    for (let n = 0; n < 10; n++) {
      const ip = newList().ip;
      if (!n) first = ip;
      expect((await put({ ...id, ip }, n + 1, n % 2 ? "AAAA" : "BBBB")).status).toBe(200);
      await evictDurableObject(list(id.syncId));
      expect(Object.keys((await readMeta(id)).rowReports.keys).length).toBeLessThanOrEqual(8);
    }
    expect(await rowQuota(limiter(`v2:rows:${first}`))).toBeGreaterThan(0);
    expect((await readMeta(id)).rowReports.keys[`v2:rows:${first}`]).toBeUndefined();
  });

  it.each(["client", "48", "global"] as const)("charges a large mutation entirely near the %s limit across eviction", async (kind) => {
    const id = await create(kind === "48" ? ipv6() : undefined);
    const name = kind === "global" ? "global" : kind === "48" ? `v2:rows48:${clientKey48(id.ip)}` : `v2:rows:${id.ip}`;
    const limit = kind === "global" ? V2_GLOBAL_LIST_ROWS_PER_DAY : kind === "48" ? V2_CLIENT_ROWS_PER_DAY_48 : V2_CLIENT_ROWS_PER_DAY;
    const counter = kind === "global" ? ledger() : limiter(name);
    const tail = (await readMeta(id)).rowReports.keys[name].pending;
    if (kind === "global") await ledger().rows(limit - tail - 2);
    else await limiter(name).rows(limit, limit - tail - 2);
    await edit(id, (m) => { m.rowReports.keys[name].checkedAt -= 60_001; });
    const before = (await readMeta(id)).rowBudget.written;
    expect((await put(id, 1, "A".repeat(V2_STORAGE_BLOCK_BYTES * 2))).status).toBe(200);
    const m = await readMeta(id);
    expect(m.rowBudget.written - before).toBeGreaterThan(5);
    // All five application rows are charged; four accounting rows (including
    // the reverted probe's persistence) consume only the local list budget.
    expect(await rowQuota(counter)).toBe(limit + 3);
    expect(m.rowBudget.written - before).toBe(9);
    expect(m.rowReports.keys[name].exhausted).toBe(true);
    await evictDurableObject(list(id.syncId));
    const billed = await rowQuota(counter);
    for (let n = 0; n < 5; n++) expect((await put(id, 2)).status).toBe(429);
    expect(await rowQuota(counter)).toBe(billed);
  });

  it("charges yesterday's sub-block tails and refreshes exhausted status at midnight", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const midnight = (Math.floor(Date.now() / 86400000) + 1) * 86400000;
    vi.setSystemTime(midnight - 5000);
    const id = await create();
    const previous = await readMeta(id);
    expect(previous.rowReports.keys.global.pending).toBeLessThan(25);
    await ledger().rows(V2_GLOBAL_LIST_ROWS_PER_DAY);
    vi.setSystemTime(midnight);
    await evictDurableObject(list(id.syncId));
    expect((await put(id)).status).toBe(200);
    const m = await readMeta(id);
    expect(m.rowReports.day).toBe(Math.floor(midnight / 86400000));
    expect(await rowQuota(ledger())).toBe(previous.rowReports.keys.global.pending);
    expect(m.rowReports.keys.global.pending).toBe(m.rowBudget.written - 1);
    expect(m.rowBudget.written).toBeLessThanOrEqual(4);
    expect(m.rowReports.keys.global.exhausted).toBe(false);
  });

  it.each([false, true])("reports each 25-row block with one RPC and counter write per key (IPv6 %s)", async (isV6) => {
    const id = await create(isV6 ? ipv6() : undefined);
    const names = ["global", ...(isV6 ? [`v2:rows48:${clientKey48(id.ip)}`] : []), `v2:rows:${clientKey(id.ip)}`];
    const calls: Record<string, number[]> = {};
    const rpcs: Record<string, number[][]> = {};
    for (const name of names) await runInDurableObject(name === "global" ? ledger() : limiter(name), (o, s) => {
      calls[name] = [];
      rpcs[name] = [];
      const exec = s.storage.sql.exec.bind(s.storage.sql);
      vi.spyOn(s.storage.sql, "exec").mockImplementation((query, ...args) => {
        const cursor = exec(query, ...args);
        if (/^INSERT INTO row_quota/.test(query)) calls[name]!.push(cursor.rowsWritten);
        return cursor;
      });
    });
    await runInDurableObject(list(id.syncId), (o) => {
      const internal = o as unknown as { rowCounter: (key: string, amount?: number) => Promise<RowStatus> };
      const counter = internal.rowCounter.bind(internal);
      vi.spyOn(internal, "rowCounter").mockImplementation((name, amount = 0) => { rpcs[name]!.push([amount]); return counter(name, amount); });
    });
    for (let version = 1; version <= 26; version++) {
      expect((await put(id, version, version % 2 ? "BBBB" : "AAAA")).status).toBe(200);
    }
    const m = await readMeta(id);
    for (const name of names) {
      expect(calls[name]!.length).toBe(2);
      expect(rpcs[name]!.length).toBe(2);
      expect(rpcs[name]!.every((args) => args.at(-1)! >= 25)).toBe(true);
      expect(calls[name]!.every((written) => written === 1)).toBe(true);
      expect(await rowQuota(name === "global" ? ledger() : limiter(name))).toBe(m.rowBudget.written - m.rowReports.keys[name].pending - 2);
    }
  });

  it("reports sub-block tails after ten minutes and refreshes cached status after sixty seconds", async () => {
    const id = await create();
    await call("GET", id.path, { key: id.key });
    await edit(id, (m) => { for (const e of Object.values(m.rowReports.keys) as any[]) { e.reportedAt -= 600_001; e.checkedAt -= 60_001; } });
    const before = (await readMeta(id)).rowReports.keys.global.pending;
    expect((await put(id)).status).toBe(200);
    expect(await rowQuota(ledger())).toBe(before);
    expect((await readMeta(id)).rowReports.keys.global.pending).toBe(2);
  });
});

describe("reverted writes and cleanup", () => {
  it("durably counts repeated 413 PUT attempts until admission is exhausted", async () => {
    const id = await create();
    await edit(id, (m) => { m.rowBudget = { day: Math.floor(Date.now() / 86400000), written: 5980 }; });
    let denied = false;
    for (let n = 0; n < 12; n++) {
      const response = await put(id, 1, "A".repeat(V2_LIST_BASE_BYTES));
      if (response.status === 429) { denied = true; break; }
      expect(response.status).toBe(413);
    }
    expect(denied).toBe(true);
    await evictDurableObject(list(id.syncId));
    expect((await put(id)).status).toBe(429);
    const current = await call("GET", id.path, { key: id.key });
    expect(await current.json()).toMatchObject({ version: 1, common: "AAAA" });
  });

  it("counts successful previews, failed previews and rolled-back block probes exactly", async () => {
    const id = await create();
    await runInDurableObject(list(id.syncId), (o, s) => {
      const budget = (o as unknown as { budget: ListStorageBudget }).budget;
      const saved = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      budget.rowContext = { keys: Object.keys(saved.rowReports.keys), reports: structuredClone(saved.rowReports) };
      const before = saved.rowBudget.written;
      const pending = saved.rowReports.keys.global.pending;
      const start = budget.rowsWritten;
      budget.preview(() => budget.sql.exec("UPDATE common SET data = 'BBBB'"));
      expect(() => budget.preview(() => budget.sql.exec("UPDATE common SET data = ?", "A".repeat(V2_LIST_BASE_BYTES)))).toThrow(ListTooLarge);
      expect(() => budget.stage(() => budget.sql.exec("UPDATE common SET data = ?", "A".repeat(V2_STORAGE_BLOCK_BYTES)), 1)).toThrow();
      const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      expect(m.rowBudget.written - before).toBe(budget.rowsWritten - start);
      expect(m.rowBudget.written - before).toBeGreaterThanOrEqual(9);
      // Three common-row writes were attempted; six rows persisted accounting.
      expect(m.rowReports.keys.global.pending - pending).toBe(3);
      expect(budget.rowsWritten - start).toBe(9);
      budget.rowContext = undefined;
      expect(s.storage.sql.exec<{ data: string }>("SELECT data FROM common").one().data).toBe("AAAA");
    });
  });

  it("applies row admission to a correctly authenticated guard open", async () => {
    const id = await create(), token = key(), proof = key();
    const current = { version: 1, tokenHash: await verify(token), verifier: await verify(proof), secret: key() };
    await runInDurableObject(list(id.syncId), (_o, s) => {
      s.storage.sql.exec("CREATE TABLE guard (device TEXT PRIMARY KEY, data TEXT NOT NULL)");
      s.storage.sql.exec("INSERT INTO guard VALUES ('nora', ?)", JSON.stringify({ current, failures: 0, nextAttemptAt: 0, suspended: false }));
    });
    await edit(id, (m) => { m.rowBudget = { day: Math.floor(Date.now() / 86400000), written: 6000 }; });
    const response = await call("POST", `${id.path}/guards/nora/open`, { body: { proofs: [{ version: 1, guardToken: token, prueba: proof }] } });
    expect(response.status).toBe(429); expect(await response.json()).toEqual({ error: "rate_limited" });
    expect(Number(response.headers.get("Retry-After"))).toBeGreaterThan(0);
  });
});

describe("body preconditions and memory", () => {
  it.each([null, '"1"'])("reads zero bytes from a false Bearer PUT to an absent list with If-Match %s", async (match) => {
    const id = newList(), pull = vi.fn(() => { throw new Error("Unexpected body read"); });
    const headers = new Headers({ Authorization: `Bearer ${id.key}`, "Content-Type": "application/json" });
    if (match) headers.set("If-Match", match);
    const response = await routeV2(new Request(`https://sync.test/v2/lists/${id.syncId}`, { method: "PUT", headers, body: new ReadableStream({ pull }, { highWaterMark: 0 }) }), env);
    expect(response.status).toBe(match ? 412 : 428); expect(pull).not.toHaveBeenCalled();
  });

  it("admits two readers per credential and four per list, and releases slots after parse failure", async () => {
    const id = await create(), nora = key(), leo = key();
    const noraVerifier = await verify(nora), leoVerifier = await verify(leo);
    await edit(id, (m) => {
      m.credentials.push({ deviceId: "nora", verifier: noraVerifier, revoked: false, createdAt: Date.now(), records: [] }, { deviceId: "leo", verifier: leoVerifier, revoked: false, createdAt: Date.now(), records: [] });
    });
    const start = (credential: string) => {
      let controller!: ReadableStreamDefaultController<Uint8Array>, began!: () => void;
      const reading = new Promise<void>((r) => { began = r; });
      const pull = vi.fn(() => began());
      const body = new ReadableStream<Uint8Array>({ start(c) { controller = c; }, pull }, { highWaterMark: 0 });
      const response = routeV2(new Request(`https://sync.test${id.path}/common`, { method: "PUT", headers: { Authorization: `Bearer ${credential}`, "Content-Type": "application/json", "If-Match": '"1"' }, body }), env);
      return { reading, response, pull, finish: () => { controller.enqueue(new TextEncoder().encode("invalid")); controller.close(); } };
    };
    const active: ReturnType<typeof start>[] = [];
    try {
      for (const credential of [id.key, id.key, nora, nora]) {
        const upload = start(credential); active.push(upload); await upload.reading;
        if (active.length === 2) {
          const rejected = start(id.key), response = await rejected.response;
          expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("1"); expect(rejected.pull).not.toHaveBeenCalled();
        }
      }
      const rejected = start(leo), response = await rejected.response;
      expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("1"); expect(rejected.pull).not.toHaveBeenCalled();
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      active[0]!.finish(); expect((await active[0]!.response).status).toBe(400);
      const replacement = start(id.key); active[0] = replacement; await replacement.reading;
    } finally {
      for (const upload of active) upload.finish();
      await Promise.all(active.map((upload) => upload.response));
    }
  });

  it("uses the configured 60-second deadline on the real body route and releases its slot", async () => {
    const id = await create();
    const cancel = vi.fn();
    const schedule = globalThis.setTimeout;
    // Shorten the runtime timer in its owning I/O context, while inspecting the
    // actual route's requested duration. Fake timers cannot cross DO contexts.
    const timer = vi.spyOn(globalThis, "setTimeout").mockImplementation((callback, delay, ...args) => schedule(callback, delay === V2_BODY_READ_DEADLINE_MS ? 10 : delay, ...args));
    const response = await routeV2(new Request(`https://sync.test${id.path}/common`, { method: "PUT", headers: { Authorization: `Bearer ${id.key}`, "Content-Type": "application/json", "If-Match": '"1"' }, body: new ReadableStream({ cancel }, { highWaterMark: 0 }) }), env);
    expect(V2_BODY_READ_DEADLINE_MS).toBe(60_000);
    expect(timer.mock.calls.some(([, delay]) => delay === V2_BODY_READ_DEADLINE_MS)).toBe(true);
    expect(response.status).toBe(408); expect(cancel).toHaveBeenCalled(); timer.mockRestore();
    await runInDurableObject(list(id.syncId), (o) => expect((o as unknown as { bodyReads: Map<string, number> }).bodyReads.size).toBe(0));
    expect((await put(id)).status).toBe(200);
  });
});

describe("ledger recovery and legacy credentials", () => {
  it.each(["read", "revoke", "alarm"] as const)("keeps %s working when the first pending ledger reconciliation fails", async (entry) => {
    const id = await create(), set = StorageLedgerObject.prototype.set;
    await runInDurableObject(list(id.syncId), async (_o, s) => { await s.storage.put("storageLedger", { blocks: 1, pending: true }); });
    if (entry === "alarm") await edit(id, (m) => { m.lastAccess = Date.now() - LIST_TTL_MS; });
    await runInDurableObject(ledger(), (o) => { Object.getPrototypeOf(o).set = () => { throw new Error("Ledger unavailable"); }; });
    try {
      if (entry === "read") expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      if (entry === "revoke") expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "aritz" } })).status).toBe(200);
      if (entry === "alarm") expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
      await runInDurableObject(list(id.syncId), async (_o, s) => {
        expect(await s.storage.get("storageLedger")).toMatchObject({ pending: true });
        expect(await s.storage.getAlarm()).toBeLessThanOrEqual(Date.now() + WINDOW_MS);
      });
    } finally { await runInDurableObject(ledger(), (o) => { Object.getPrototypeOf(o).set = set; }); }
  });

  it("returns the balance when renewalDestination retires an expired destination", async () => {
    const id = await create();
    await edit(id, (m) => { m.lastAccess = Date.now() - LIST_TTL_MS; });
    expect(await total()).toBe(1);
    expect(await list(id.syncId).renewalDestination("aritz", key())).toBe(false);
    expect(await total()).toBe(0);
  });

  it("arms durable reconciliation before committing a shrink even if the finalizer never runs", async () => {
    const id = await create();
    expect((await put(id, 1, "A".repeat(V2_STORAGE_BLOCK_BYTES))).status).toBe(200); expect(await total()).toBe(2);
    await runInDurableObject(list(id.syncId), (o) => {
      const internal = o as unknown as { withLedger: (run: () => Promise<unknown>) => Promise<unknown>; reconcileLedger: () => Promise<void> };
      // Simulate interruption immediately after the local commit, before finally.
      vi.spyOn(internal, "withLedger").mockImplementation(async (run) => { await internal.reconcileLedger(); return run(); });
    });
    expect((await put(id, 2)).status).toBe(200);
    expect(await total()).toBe(2);
    await runInDurableObject(list(id.syncId), async (_o, s) => {
      expect(await s.storage.get("storageLedger")).toMatchObject({ blocks: 2, pending: true });
      expect(await s.storage.getAlarm()).toBeLessThanOrEqual(Date.now() + WINDOW_MS);
    });
    vi.restoreAllMocks(); await evictDurableObject(list(id.syncId)); await runDurableObjectAlarm(list(id.syncId));
    expect(await total()).toBe(1);
  });

  it.each(["checkpoint", "revoked slot"] as const)("durably prepares alarm expiry of a %s and preserves its retry without a finalizer", async (kind) => {
    const id = await create();
    await runInDurableObject(list(id.syncId), (o, s) => {
      const raw = s.storage.sql;
      const m = JSON.parse(raw.exec<{ data: string }>("SELECT data FROM state").one().data);
      if (kind === "checkpoint") {
        raw.exec("CREATE TABLE checkpoint (invite TEXT NOT NULL, part TEXT NOT NULL, idx INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (invite, part, idx))");
        raw.exec("INSERT INTO invite VALUES ('expired', ?, '{}')", Date.now() + 86400000);
        raw.exec("INSERT INTO checkpoint VALUES ('expired', 'common', 0, ?)", "A".repeat(V2_STORAGE_BLOCK_BYTES));
      } else {
        m.credentials.push({ deviceId: "nora", revoked: true, verifier: null, slotsExpireAt: Date.now() + 86400000, createdAt: Date.now(), records: [] });
        raw.exec("INSERT INTO slot VALUES ('leo', 'nora', 1, ?)", "A".repeat(V2_STORAGE_BLOCK_BYTES));
      }
      delete m.storedBytes;
      raw.exec("UPDATE state SET data = ?", JSON.stringify(m));
      const budget = new ListStorageBudget(s.storage);
      (o as unknown as { budget: ListStorageBudget }).budget = budget;
      budget.transaction(() => undefined, true);
    });
    // Enrol the fixture, then simulate termination after local cleanup and
    // its ordinary alarm scheduling, before the ledger finalizer can run.
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect(await total()).toBe(2);
    await runInDurableObject(list(id.syncId), (o, s) => {
      if (kind === "checkpoint") s.storage.sql.exec("UPDATE invite SET expires_at = ?", Date.now() - 1);
      else {
        const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
        m.credentials[1].slotsExpireAt = Date.now() - 1;
        s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
      }
      const internal = o as unknown as { withLedger: (run: () => Promise<unknown>) => Promise<unknown>; reconcileLedger: () => Promise<void> };
      vi.spyOn(internal, "withLedger").mockImplementation(async (run) => { await internal.reconcileLedger(); return run(); });
    });
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    expect(await total()).toBe(2);
    await runInDurableObject(list(id.syncId), async (_o, s) => {
      expect(await s.storage.get("storageLedger")).toMatchObject({ blocks: 2, pending: true });
      const retry = await s.storage.getAlarm();
      expect(retry).toBeLessThanOrEqual(Date.now() + WINDOW_MS);
      const table = kind === "checkpoint" ? "checkpoint" : "slot";
      expect(s.storage.sql.exec(`SELECT * FROM ${table}`).toArray()).toEqual([]);
    });
    vi.restoreAllMocks();
    await evictDurableObject(list(id.syncId));
    expect(await runDurableObjectAlarm(list(id.syncId))).toBe(true);
    expect(await total()).toBe(1);
    await runInDurableObject(list(id.syncId), async (_o, s) => expect(await s.storage.get("storageLedger")).toEqual({ blocks: 1 }));
  });

  it("backfills three legacy credentials as mature and immediately permits their existing capacity", async () => {
    const id = await create();
    await edit(id, (m) => {
      delete m.credentials[0].createdAt;
      m.credentials.push({ deviceId: "nora", verifier: key(), revoked: false, records: [] }, { deviceId: "leo", verifier: key(), revoked: false, records: [] });
      delete m.storedBytes;
    });
    await runInDurableObject(list(id.syncId), (_o, s) => {
      for (let n = 0; n < 4; n++) s.storage.sql.exec("INSERT INTO resource VALUES (?, ?)", `legacy-${n}`, "A".repeat(1_000_000));
    });
    await evictDurableObject(list(id.syncId));
    expect((await put(id, 1, "A".repeat(300_000))).status).toBe(200);
    const m = await readMeta(id);
    for (const credential of m.credentials) expect(credential.createdAt).toBeLessThanOrEqual(Date.now() - V2_CREDENTIAL_CAP_AGE_MS);
    expect(v2ListByteLimit(m.credentials)).toBe(5 * 1048576);
  });
});
