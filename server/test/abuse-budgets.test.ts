import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { clientKey, clientKey48 } from "../src/ip";
import { ListStorageBudget, ListTooLarge } from "../src/list-storage-budget";
import { V2_GLOBAL_NEW_LISTS_PER_DAY, V2_GLOBAL_NEW_LISTS_PER_HOUR, V2_LIST_BASE_BYTES, v2ListByteLimit } from "../src/limits";
import worker from "../src/index";
import type { Env } from "../src/env";
import { b64u, call, newList } from "./helpers";

const snapshot = () => ({ deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: b64u(new Uint8Array(32).fill(7)) }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
afterEach(() => vi.useRealTimers());

describe("creation and public abuse budgets", () => {
  it("canonicalizes /48 keys, including compressed, expanded and mapped addresses", () => {
    expect(clientKey48("2001:db8:1234:abff::1")).toBe("2001:0db8:1234::/48");
    expect(clientKey48("2001:0DB8:1234:1200:0000:0000:0000:0001")).toBe(clientKey48("2001:db8:1234:ff00::2"));
    expect(clientKey("2001:db8:1234:1200::1")).not.toBe(clientKey("2001:db8:1234:ff00::2"));
    expect(clientKey48("2001:db8:1235::1")).not.toBe(clientKey48("2001:db8:1234::1"));
    expect(clientKey48("::ffff:192.0.2.1")).toBe("192.0.2.1");
    expect(clientKey48("192.0.2.1")).toBe("192.0.2.1");
    expect(clientKey48(null)).toBe("unknown");
  });
  it("accepts the configured hourly and daily global creation budgets, rejects without writes or alarms", async () => {
    const stub = env.CREATION_BUDGET.get(env.CREATION_BUDGET.newUniqueId());
    vi.useFakeTimers({ toFake: ["Date"] });
    const start = Date.now();
    for (let h = 0; h < V2_GLOBAL_NEW_LISTS_PER_DAY / V2_GLOBAL_NEW_LISTS_PER_HOUR; h++) {
      vi.setSystemTime(start + h * 3600000);
      const decisions = await Promise.all(Array.from({ length: V2_GLOBAL_NEW_LISTS_PER_HOUR + 1 }, () => stub.reserve()));
      expect(decisions.filter((d) => d.ok)).toHaveLength(V2_GLOBAL_NEW_LISTS_PER_HOUR);
      expect(decisions[V2_GLOBAL_NEW_LISTS_PER_HOUR]).toEqual({ ok: false, retryAfter: 3600 });
    }
    vi.setSystemTime(start + 6 * 3600000);
    await runInDurableObject(stub, (o, state) => {
      const exec = vi.spyOn(state.storage.sql, "exec");
      try {
        expect(o.reserve()).toEqual({ ok: false, retryAfter: 3600 });
        expect(exec.mock.calls.some(([sql]) => /^(INSERT|DELETE|UPDATE)/.test(sql))).toBe(false);
      } finally { exec.mockRestore(); }
    });
    vi.setSystemTime(start + 24 * 3600000);
    expect((await stub.reserve()).ok).toBe(true);
    await runInDurableObject(stub, async (_o, state) => {
      expect(state.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM creation").one().n).toBe(V2_GLOBAL_NEW_LISTS_PER_DAY);
      expect(await state.storage.getAlarm()).toBeNull();
    });
  });
  it("counts new lists across /56s in one /48", async () => {
    for (let n = 0; n < 25; n++) {
      const id = newList();
      const response = await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: `2001:db8:9876:${(n * 256).toString(16)}::1`, headers: { "If-Match": '"0"' }, body: snapshot() });
      expect(response.status).toBe(n < 24 ? 201 : 429);
    }
  });
  it("does not spend the global budget on invalid creation; existing lists bypass it", async () => {
    const id = newList(), path = `/v2/lists/${id.syncId}`;
    const global = env.CREATION_BUDGET.get(env.CREATION_BUDGET.idFromName("v2:new-lists"));
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"0"' }, body: { ...snapshot(), registry: {} } })).status).toBe(400);
    await runInDurableObject(global, (_o, s) => {
      if (s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'creation'").toArray().length) expect(s.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM creation").one().n).toBe(0);
    });
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
    await runInDurableObject(global, (_o, s) => {
      s.storage.sql.exec("DELETE FROM creation");
      for (let n = 1; n <= V2_GLOBAL_NEW_LISTS_PER_HOUR; n++) s.storage.sql.exec("INSERT INTO creation VALUES (?, ?)", n, Date.now());
    });
    const fresh = newList();
    const denied = await call("PUT", `/v2/lists/${fresh.syncId}`, { key: fresh.key, headers: { "If-Match": '"0"' }, body: snapshot() });
    expect(denied.status).toBe(429); expect(denied.headers.get("Retry-After")).toBe("3600");
    expect((await call("GET", path, { key: id.key })).status).toBe(200);
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"1"' }, body: snapshot() })).status).toBe(200);
  });
  it.each([
    ["/v2/invites/AAAAAAAAAAAAAAAAAAAAAA/offer", "INVITE_IP_LIMITER", "INVITE_IP48_LIMITER"],
    ["/v2/lists/AAAAAAAAAAAAAAAAAAAAAA/guards/nora/open", "GUARD_IP_LIMITER", "GUARD_IP48_LIMITER"],
    [`/v2/recoveries/${"A".repeat(43)}`, "RECOVERY_IP_LIMITER", "RECOVERY_IP48_LIMITER"],
  ])("uses write-free /56 and /48 bindings on %s", async (path, narrow, wide) => {
    const small = { limit: vi.fn(async () => ({ success: true })) };
    const large = { limit: vi.fn(async () => ({ success: false })) };
    const fake = { ...env, [narrow]: small, [wide]: large } as Env;
    const response = await worker.fetch(new Request(`https://sync.test${path}`, { method: path.endsWith("open") ? "POST" : "GET", headers: { "CF-Connecting-IP": "2001:db8:1234:ab00::1" } }), fake);
    expect(response.status).toBe(429); expect(response.headers.get("Retry-After")).toBe("60");
    expect(small.limit).toHaveBeenCalledWith({ key: "2001:0db8:1234:ab00::/56" });
    expect(large.limit).toHaveBeenCalledWith({ key: "2001:0db8:1234::/48" });
  });
});

describe("atomic list byte budget", () => {
  it("counts payload tables and UTF-8, scales with active credentials, and permits reductions", async () => {
    const stub = env.LISTS_V2.get(env.LISTS_V2.newUniqueId());
    await runInDurableObject(stub, (_o, state) => {
      const raw = state.storage.sql;
      raw.exec("CREATE TABLE state (id INTEGER PRIMARY KEY, data TEXT NOT NULL)");
      raw.exec("INSERT INTO state VALUES (1, ?)", JSON.stringify({ credentials: [{ revoked: false }] }));
      const names = ["common", "slot", "resource", "invite", "checkpoint", "guard", "renewal_command", "recovery", "recovery_blob", "pending_release", "recovery_release", "recovery_retired"];
      for (const name of names) { raw.exec(`CREATE TABLE ${name} (id INTEGER PRIMARY KEY, data TEXT)`); raw.exec(`INSERT INTO ${name} VALUES (1, 'é')`); }
      const budget = new ListStorageBudget(state.storage);
      budget.transaction(() => undefined);
      const read = () => JSON.parse(raw.exec<{ data: string }>("SELECT data FROM state").one().data);
      expect(read().storedBytes).toBe(names.length * 10 + 8 + new TextEncoder().encode(JSON.stringify({ credentials: [{ revoked: false }], rowBudget: read().rowBudget, storedBytes: 0 })).length);
      budget.transaction(() => budget.sql.exec("UPDATE common SET data = ?", "x".repeat(V2_LIST_BASE_BYTES - 1000)));
      expect(() => budget.transaction(() => budget.sql.exec("UPDATE slot SET data = ?", "x".repeat(2000)))).toThrow(ListTooLarge);
      expect(raw.exec<{ data: string }>("SELECT data FROM slot").one().data).toBe("é");
      const m = read(); m.credentials.push({ revoked: true }); raw.exec("UPDATE state SET data = ?", JSON.stringify(m));
      expect(() => budget.transaction(() => budget.sql.exec("UPDATE slot SET data = ?", "x".repeat(2000)))).toThrow(ListTooLarge);
      m.credentials[1].revoked = false; raw.exec("UPDATE state SET data = ?", JSON.stringify(m));
      budget.transaction(() => budget.sql.exec("UPDATE slot SET data = ?", "x".repeat(2000)));
      expect(read().storedBytes).toBeGreaterThan(V2_LIST_BASE_BYTES);
      expect(v2ListByteLimit([{ revoked: false }, { revoked: false }])).toBe(4 * 1048576);
      const revoke = read(); revoke.credentials[1].revoked = true; raw.exec("UPDATE state SET data = ?", JSON.stringify(revoke));
      budget.transaction(() => budget.sql.exec("UPDATE common SET data = ?", "x".repeat(V2_LIST_BASE_BYTES - 1500)));
      budget.transaction(() => budget.sql.exec("DELETE FROM slot"));
      expect(read().storedBytes).toBeLessThan(V2_LIST_BASE_BYTES);
      expect(v2ListByteLimit(Array.from({ length: 64 }, () => ({ revoked: false, createdAt: Date.now() - 8 * 86400000 })))).toBe(64.5 * 1048576);
      const cold = new ListStorageBudget(state.storage);
      cold.transaction(() => undefined);
      expect(read().storedBytes).toBe(budget.decorate(read()).storedBytes);
    });
  });
  it("returns the client-compatible 413 and preserves version and content", async () => {
    const id = newList(), path = `/v2/lists/${id.syncId}`;
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"0"' }, body: snapshot() })).status).toBe(201);
    const denied = await call("PUT", `${path}/common`, { key: id.key, headers: { "If-Match": '"1"' }, body: { common: "A".repeat(V2_LIST_BASE_BYTES) } });
    expect(denied.status).toBe(413); expect(await denied.json()).toEqual({ error: "too_large" });
    const current = await call("GET", path, { key: id.key });
    expect(current.headers.get("ETag")).toBe('"1"'); expect(await current.json()).toHaveProperty("common", "AAAA");
  });
});
