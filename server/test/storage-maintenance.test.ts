import { describe, expect, it } from "vitest";
import { env } from "cloudflare:workers";
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { LIST_TTL_MS, V2_GLOBAL_STORAGE_CEILING_BYTES, V2_STORAGE_BLOCK_BYTES } from "../src/limits";
import type { PurgeCandidate } from "../src/list-v2-object";
import { b64u, call, newList, rand } from "./helpers";

const DAY = 86_400_000;
const maintenance = (env as unknown as { MAINTENANCE: Fetcher }).MAINTENANCE;
const endpoint = "http://127.0.0.1:8791";
const host = "127.0.0.1:8791";
const ledger = () => env.STORAGE_LEDGER.get(env.STORAGE_LEDGER.idFromName("v2:storage"));
const usage = () => maintenance.fetch(endpoint + "/storage-occupancy", { headers: { Host: host } });
const purge = (body: object) => maintenance.fetch(endpoint + "/purge-inactive", {
  method: "POST", headers: { Host: host, "Content-Type": "application/json" }, body: JSON.stringify(body),
});
const preview = async (id: string, criteria: object) =>
  (await purge({ criteria, objects: [{ id }] })).json<{ candidates: (PurgeCandidate & { id: string })[] }>();

async function ageList(age = 90) {
  const now = Date.now(), createdAt = now - age * DAY, lastActivity = createdAt + DAY;
  const list = newList(), path = `/v2/lists/${list.syncId}`;
  const stub = env.LISTS_V2.get(env.LISTS_V2.idFromName(list.syncId));
  const snapshot = {
    deviceId: "nora", common: "AAAA", keyPackages: [], slots: [],
    registry: { v: 2, l: "family", records: [{ d: "nora", e: b64u(rand(32)) }], vouches: [], revocations: [] },
  };
  const create = () => call("PUT", path, { key: list.key, ip: list.ip, headers: { "If-Match": '"0"' }, body: snapshot });
  expect((await create()).status).toBe(201);
  const edit = (change: (meta: Record<string, any>) => void) => runInDurableObject(stub, (_o, s) => {
    const data = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
    change(data);
    s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(data));
  });
  await edit((m) => {
    expect(m.createdAt).toBeGreaterThanOrEqual(now);
    m.createdAt = createdAt;
    m.lastAccess = lastActivity;
    m.credentials[0].createdAt = createdAt;
  });
  const criteria = { createdFrom: createdAt, createdBefore: now - DAY, inactiveBefore: now - 30 * DAY, includeLegacy: true };
  const state = () => runInDurableObject(stub, async (_o, s) => ({
    data: s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data,
    alarm: await s.storage.getAlarm(),
    until: await s.storage.get<number>("retiredUntil"),
    ledger: await s.storage.get("storageLedger"),
  }));
  return { id: stub.id.toString(), stub, path, key: list.key, create, criteria, createdAt, lastActivity, edit, state };
}

describe("private storage occupancy", () => {
  it("reads an empty ledger without initializing tables or arming an alarm", async () => {
    expect(await ledger().occupancy()).toEqual({ reservedBytes: 0, ceilingBytes: V2_GLOBAL_STORAGE_CEILING_BYTES, percent: 0 });
    await runInDurableObject(ledger(), async (_o, s) => {
      expect(s.storage.sql.exec("SELECT name FROM sqlite_master WHERE name = 'balances'").toArray()).toEqual([]);
      expect(await s.storage.getAlarm()).toBeNull();
    });
  });

  it("reports persisted reservations through the maintenance binding and flags 50%", async () => {
    const half = V2_GLOBAL_STORAGE_CEILING_BYTES / 2;
    await ledger().set("fixture", half / V2_STORAGE_BLOCK_BYTES - 1);
    expect(await (await usage()).json()).toMatchObject({ alert: false });
    await ledger().set("fixture", half / V2_STORAGE_BLOCK_BYTES);
    await evictDurableObject(ledger());
    const response = await usage();
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.json()).toEqual({ reservedBytes: half, ceilingBytes: half * 2, percent: 50, alert: true });
  });
});

describe("private list purge", () => {
  it("previews without side effects and explicit apply retires for 400 days and releases the ledger", async () => {
    const { id, criteria, createdAt, lastActivity, create, state } = await ageList();
    const before = await state();
    const reservedBefore = (await ledger().occupancy()).reservedBytes;
    const { candidates } = await preview(id, criteria);
    expect(candidates).toEqual([{
      id, createdAt, lastActivity, version: 1,
      storedBytes: JSON.parse(before.data).storedBytes, hasRecovery: false, pendingInvites: 0,
    }]);
    expect(await state()).toEqual(before);
    expect((await ledger().occupancy()).reservedBytes).toBe(reservedBefore);

    const { id: candidateId, ...expected } = candidates[0]!;
    const apply = { criteria, apply: true, objects: [{ id: candidateId, expected }] };
    const started = Date.now();
    expect(await (await purge(apply)).json()).toEqual({ purged: 1 });
    const retired = await state();
    expect(retired.data).toBe('{"retired":true}');
    expect(retired.until).toBeGreaterThanOrEqual(started + LIST_TTL_MS);
    expect(retired.alarm).toBe(retired.until);
    expect(retired.ledger).toBeUndefined();
    expect((await ledger().occupancy()).reservedBytes).toBe(reservedBefore - V2_STORAGE_BLOCK_BYTES);
    expect(await (await purge(apply)).json()).toEqual({ purged: 0 });
    expect((await create()).status).toBe(410);
    expect(await state()).toEqual(retired);
  });

  it("rechecks the reviewed candidate after activity and validates an entire apply batch", async () => {
    const { id, criteria, path, key, state } = await ageList();
    const { id: candidateId, ...expected } = (await preview(id, criteria)).candidates[0]!;
    const objects = [{ id, expected }, { id: "invalid", expected }];
    expect((await purge({ criteria, apply: true, objects })).status).toBe(400);
    expect((await purge({ criteria, apply: "true", objects: objects.slice(0, 1) })).status).toBe(400);
    expect((await call("GET", path, { key })).status).toBe(200);
    expect(await (await purge({ criteria, apply: true, objects: [{ id: candidateId, expected }] })).json()).toEqual({ purged: 0 });
    expect(JSON.parse((await state()).data).version).toBe(1);
  });

  it("skips a reviewed list when its stored bytes change", async () => {
    const { id, criteria, edit, state } = await ageList();
    const { id: candidateId, ...expected } = (await preview(id, criteria)).candidates[0]!;
    await edit((m) => { m.storedBytes += 1; });
    const changed = await state();
    expect((await preview(id, criteria)).candidates).toEqual([{ id, ...expected, storedBytes: expected.storedBytes + 1 }]);
    expect(await (await purge({ criteria, apply: true, objects: [{ id: candidateId, expected }] })).json()).toEqual({ purged: 0 });
    expect(await state()).toEqual(changed);
  });

  it("fails closed when stored byte metadata is missing without changing storage", async () => {
    const { id, criteria, edit, state } = await ageList();
    await edit((m) => { delete m.storedBytes; });
    const before = await state();
    expect(await preview(id, criteria)).toEqual({ candidates: [] });
    expect(await state()).toEqual(before);
  });

  it.each(["renewal", "release"] as const)("excludes a list with pending %s work at preview and rechecks it at apply", async (pending) => {
    const { id, stub, criteria, state } = await ageList();
    const [candidate] = (await preview(id, criteria)).candidates;
    const { id: candidateId, ...expected } = candidate!;
    const setPending = () => runInDurableObject(stub, (_o, s) => {
      if (pending === "renewal") {
        s.storage.sql.exec("INSERT INTO resource (name, data) VALUES ('renewal', ?) ON CONFLICT(name) DO UPDATE SET data = excluded.data", JSON.stringify({
          operationId: "pending", plan: null, reservation: null, recovery: null, barrier: null,
          abortion: null, ready: null, preparation: null, confirmation: null,
          acknowledgements: {}, transfers: {}, exclusions: {},
        }));
      } else {
        s.storage.sql.exec("CREATE TABLE IF NOT EXISTS pending_release (data TEXT PRIMARY KEY)");
        s.storage.sql.exec("INSERT INTO pending_release (data) VALUES (?)", JSON.stringify({ id: "pending" }));
      }
    });

    await setPending();
    expect(await preview(id, criteria)).toEqual({ candidates: [] });
    expect(await (await purge({ criteria, apply: true, objects: [{ id: candidateId, expected }] })).json()).toEqual({ purged: 0 });
    expect(JSON.parse((await state()).data).retired).toBeUndefined();
  });

  it("reports pending invitations and skips a reviewed list when an invitation expires", async () => {
    const { id, stub, path, key, criteria, lastActivity, edit, state } = await ageList();
    expect((await call("POST", `${path}/invites`, {
      key, body: { offer: { v: 2, host: { d: "nora" }, c: b64u(rand(32)) } },
    })).status).toBe(201);
    await edit((m) => {
      m.lastAccess = lastActivity;
      m.credentials[0].lastRequest = lastActivity;
    });
    const { id: candidateId, ...expected } = (await preview(id, criteria)).candidates[0]!;
    expect(expected.pendingInvites).toBe(1);
    await runInDurableObject(stub, (_o, s) => s.storage.sql.exec("UPDATE invite SET expires_at = ?", Date.now() - 1).toArray());
    const changed = await state();
    expect((await preview(id, criteria)).candidates).toEqual([{ id, ...expected, pendingInvites: 0 }]);
    expect(await (await purge({ criteria, apply: true, objects: [{ id: candidateId, expected }] })).json()).toEqual({ purged: 0 });
    expect(await state()).toEqual(changed);
  });

  it("rejects inactivity shorter than 30 days for both preview and apply", async () => {
    const { id, criteria, state } = await ageList();
    const before = await state();
    const { id: candidateId, ...expected } = (await preview(id, criteria)).candidates[0]!;
    const tooRecent = { ...criteria, inactiveBefore: Date.now() - 29 * DAY };
    expect((await purge({ criteria: tooRecent, objects: [{ id }] })).status).toBe(400);
    expect((await purge({ criteria: tooRecent, apply: true, objects: [{ id: candidateId, expected }] })).status).toBe(400);
    expect(await state()).toEqual(before);
  });

  it("skips lists outside the date or activity cutoffs, and lists with revoked credential history", async () => {
    const { id, criteria, createdAt, lastActivity, edit } = await ageList();
    expect(await preview(id, { ...criteria, createdFrom: createdAt + 1 })).toEqual({ candidates: [] });
    expect(await preview(id, { ...criteria, createdFrom: createdAt - DAY, createdBefore: createdAt })).toEqual({ candidates: [] });
    expect(await preview(id, { ...criteria, inactiveBefore: lastActivity - 1 })).toEqual({ candidates: [] });
    await edit((m) => { m.credentials.push({ ...m.credentials[0], deviceId: "leo", verifier: null, revoked: true }); });
    expect(await preview(id, criteria)).toEqual({ candidates: [] });
  });

  it("requires an undated list's entire possible creation range to fit the window", async () => {
    const { id, criteria, lastActivity, edit } = await ageList();
    const { candidates: [dated] } = await preview(id, criteria);
    await edit((m) => { delete m.createdAt; });
    expect(await preview(id, criteria)).toEqual({ candidates: [] });
    expect(await preview(id, { ...criteria, createdFrom: 0, createdBefore: lastActivity })).toEqual({ candidates: [] });
    const epoch = { ...criteria, createdFrom: 0 };
    expect(await preview(id, epoch)).toEqual({ candidates: [{ ...dated, createdAt: null }] });
    expect((await purge({ criteria: { ...epoch, includeLegacy: undefined }, objects: [{ id }] })).status).toBe(400);
    const historical = { ...criteria, createdFrom: Date.UTC(2026, 10, 19), includeLegacy: undefined };
    expect((await purge({ criteria: historical, objects: [{ id }] })).status).toBe(400);
  });
});
