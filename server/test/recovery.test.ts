import { afterEach, describe, expect, it, vi } from "vitest";
import { env, exports } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import worker from "../src/index";
import type { Env } from "../src/env";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";
import { RecoveryLocatorObject } from "../src/recovery-locator-object";
import { ListV2Object } from "../src/list-v2-object";
import { RecoveryStore, type RecoveryRow } from "../src/recovery-store";
import { recoveryReadVerifier, validateCapsule } from "../src/recovery-contract";
import { routeV2 } from "../src/v2-router";
import { canonicalJson } from "../src/v2-contract";
import { RECOVERY_MAX_BODY_BYTES, RECOVERY_MAX_BYTES, RECOVERY_RESERVATION_MS } from "../src/limits";
import { b64u, call, json, newList, rand, randomIp } from "./helpers";

const key = () => b64u(rand(32));
const op = () => b64u(rand(16));
const digest = async (s: string) => encodeB64Url(await sha256(decodeB64Url(s, 32)!));
const listStub = (sid: string) => { const ns = env.LISTS_V2.jurisdiction("eu"); return ns.get(ns.idFromName(sid)); };
const locator = (rid: string) => { const ns = env.RECOVERIES_V2.jurisdiction("eu"); return ns.get(ns.idFromName(rid)); };
const snapshot = (deviceId = "aritz") => ({ deviceId, common: "AAAA", registry: { v: 2, l: "family", records: [{ d: deviceId, e: key() }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
const setup = async (inviteCopy = false) => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"0"' }, body: { ...snapshot(), ...(inviteCopy ? { inviteCopy } : {}) } })).status).toBe(201);
  return { ...id, path };
};
type Setup = Awaited<ReturnType<typeof setup>>;
type Meta = { version: number; lastAccess: number; denied: string[]; credentials: { deviceId: string; verifier: string | null; revoked: boolean; role?: string; records: number[] }[] };
const state = (id: Setup) => runInDurableObject(listStub(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as Meta);
const editState = (id: Setup, edit: (m: Meta) => void) => runInDurableObject(listStub(id.syncId), (_o, s) => {
  const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as Meta;
  edit(m); s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
});
const rows = (id: Setup) => runInDurableObject(listStub(id.syncId), (_o, s) => new RecoveryStore(s.storage.sql).rows());
const quota = (id: Setup) => runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.sql.exec<{ data: string }>("SELECT data FROM recovery_quota").one().data);
const reopen = async (id: Setup, rid?: string) => { await evictDurableObject(listStub(id.syncId)); if (rid) await evictDurableObject(locator(rid)); };

/** Opaque ciphertext, but exact normative binary header. */
function capsule(rid: string, r: number, options: { header?: Record<string, unknown>; size?: number; magic?: number[]; text?: string } = {}): string {
  const h = { k: "capsule", kdf: { a: "argon2id", m: 19456, p: 1, t: 2 }, rid, r, s: b64u(new Uint8Array(16).fill(3)), v: 2, ...options.header };
  const header = new TextEncoder().encode(options.text ?? canonicalJson(h));
  const bin = new Uint8Array(options.size ?? (6 + header.length + 12 + 17 + 16));
  bin.set(options.magic ?? [0x47, 0x48, 0x52, 2]); bin[4] = header.length >> 8; bin[5] = header.length & 255;
  bin.set(header, 6);
  return b64u(bin);
}
async function recovery(id: Setup, deviceId = "aritz", credential = id.key) {
  const rid = key(), cap = key(), operationId = op();
  const body = { v: 2, deviceId, readVerifier: await recoveryReadVerifier(cap), capsule: capsule(rid, 1) };
  const path = `${id.path}/recoveries/${rid}`, publicPath = `/v2/recoveries/${rid}`;
  const create = () => call("PUT", path, { key: credential, headers: { "If-Match": '"0"', "X-Recovery-Operation": operationId }, body });
  const response = await create(); expect(response.status).toBe(201);
  return { rid, cap, operationId, body, path, publicPath, create, response };
}
type Recovery = Awaited<ReturnType<typeof recovery>>;
type PublicRecovery = Pick<Recovery, "rid" | "cap" | "publicPath">;
const get = (r: PublicRecovery, cap = r.cap) => call("GET", r.publicPath, { headers: { "X-Recovery-Cap": cap } });
const claimBody = async (r: Pick<Recovery, "rid">, revision = 2, newKey = key()) => ({ newKey, body: { v: 2, operationId: op(), newCredentialVerifier: await digest(newKey), capsule: capsule(r.rid, revision) } });
const claim = (id: Setup, r: PublicRecovery, body: unknown, match: string | null = '"1"', credential = id.key, cap = r.cap) => call("POST", `${r.publicPath}/claim`, { key: credential, headers: { "X-Recovery-Cap": cap, ...(match === null ? {} : { "If-Match": match }) }, body });
const replace = (id: Setup, r: Recovery, n = 1, credential = id.key) => call("PUT", r.path, { key: credential, headers: { "If-Match": `"${n}"`, ...(n === 0 ? { "X-Recovery-Operation": op() } : {}) }, body: { ...r.body, capsule: capsule(r.rid, n + 1) } });
const remove = (id: Setup, r: Recovery, n = 1, credential = id.key) => call("DELETE", r.path, { key: credential, headers: { "If-Match": `"${n}"` } });
const error = async (res: Response, status: number, code: string) => { expect(res.status).toBe(status); expect(await json(res)).toEqual({ error: code }); };

async function invite(id: Setup, guest = "nora", host = "aritz", credential = id.key) {
  const created = await call("POST", `${id.path}/invites`, { key: credential, body: { offer: { v: 2, host: { d: host }, c: key() } } });
  expect(created.status).toBe(201);
  const { inviteId } = await json<{ inviteId: string }>(created);
  const guestKey = key();
  return { inviteId, guestKey, privatePath: `${id.path}/invites/${inviteId}`, publicPath: `/v2/invites/${inviteId}`, body: { answer: { v: 2, guest: { d: guest, e: key() }, vouch: {} }, serviceCredentialVerifier: await digest(guestKey) } };
}
async function pair(id: Setup, guest = "nora", host = "aritz", credential = id.key) {
  const i = await invite(id, guest, host, credential);
  expect((await call("POST", `${i.publicPath}/answer`, { body: i.body })).status).toBe(201);
  expect((await call("POST", `${i.privatePath}/reveal`, { key: credential, body: { reveal: { v: 2, n: key() } } })).status).toBe(200);
  const current = await json<{ version: number; common: string; registry: unknown }>(await call("GET", id.path, { key: credential }));
  const hash = async (part: string, text: string) => b64u(await sha256(new TextEncoder().encode(`gift-huddle-pairing-checkpoint-${part}-v1\0${text}`)));
  const checkpoint = { common: await hash("common", current.common), registry: await hash("registry", canonicalJson(current.registry)) };
  expect((await call("POST", `${i.privatePath}/approve`, { key: credential, headers: { "If-Match": `"${current.version}"` }, body: { package: { c: "opaque" }, checkpoint } })).status).toBe(200);
  return i;
}
async function prepare(id: Setup, r: Recovery, expected = 1) {
  const rid = key(), cap = key(), operationId = op();
  const body = { v: 2, operationId, newRecoveryId: rid, readVerifier: await recoveryReadVerifier(cap), capsule: capsule(rid, 1) };
  const send = () => call("POST", `${r.path}/rotation`, { key: id.key, headers: { "If-Match": `"${expected}"` }, body });
  const response = await send(); expect(response.status).toBe(201);
  const commit = () => call("POST", `${r.path}/rotation/${operationId}/commit`, { key: id.key, headers: { "If-Match": `"${expected}"` }, body: { v: 2 } });
  return { ...r, rid, cap, operationId, body, publicPath: `/v2/recoveries/${rid}`, path: `${id.path}/recoveries/${rid}`, send, commit, response };
}

afterEach(() => vi.restoreAllMocks());

it("excludes a single-device list with a published recovery capsule from purge preview and apply", async () => {
  const id = await setup(), r = await recovery(id);
  const stub = listStub(id.syncId);
  const day = 86_400_000, now = Date.now(), createdAt = now - 90 * day, lastActivity = createdAt + day;
  await editState(id, (m) => {
    m.lastAccess = lastActivity;
    Object.assign(m, { createdAt });
    Object.assign(m.credentials[0]!, { lastRequest: lastActivity });
  });
  const before = await state(id);
  expect(before.credentials).toHaveLength(1);
  expect(await rows(id)).toMatchObject([{ state: "active", published: true }]);
  const criteria = { createdFrom: createdAt, createdBefore: now - day, inactiveBefore: now - 30 * day, includeLegacy: true };
  const objectId = stub.id.toString();
  const maintenance = (env as unknown as { MAINTENANCE: Fetcher }).MAINTENANCE;
  const purge = (body: object) => maintenance.fetch("http://127.0.0.1:8791/purge-inactive", {
    method: "POST", headers: { Host: "127.0.0.1:8791", "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  expect(await json(await purge({ criteria, objects: [{ id: objectId }] }))).toEqual({ candidates: [] });

  const expected = {
    createdAt, lastActivity, version: before.version, pendingInvites: 0, hasRecovery: false,
    storedBytes: (before as Meta & { storedBytes: number }).storedBytes,
  };
  expect(await json(await purge({ criteria, apply: true, objects: [{ id: objectId, expected }] }))).toEqual({ purged: 0 });
  expect(await state(id)).toEqual(before);
  expect(await json(await get(r))).toMatchObject({ capsule: r.body.capsule });
});

describe("recovery envelopes and HTTP bounds", () => {
  it.each([false, true])("rejects cheap malformed headers without reading the body (existing=%s)", async (existing) => {
    const id = await setup(), r = existing ? await recovery(id) : { publicPath: `/v2/recoveries/${key()}` };
    const cases: Record<string, string>[] = [
      { "X-Recovery-Cap": "!", "If-Match": '"1"' },
      { "X-Recovery-Cap": key(), "If-Match": "*" },
      { "X-Recovery-Cap": key(), "If-Match": '"1"', "X-Recovery-Operation": "!" },
    ];
    for (const headers of cases) {
      const req = new Request(`https://sync.test${r.publicPath}/claim`, { method: "POST", headers, body: "unread" });
      const read = vi.spyOn(req.body!, "getReader");
      await error(await routeV2(req, env), 400, "invalid_recovery");
      expect(read).not.toHaveBeenCalled(); expect(req.bodyUsed).toBe(false);
    }
  });
  it("rejects ciphertext alphabet and noncanonical trailing bits beyond the header", () => {
    const rid = key(), text = capsule(rid, 1, { size: 1000 }); // remainder 2
    expect(validateCapsule(text.slice(0, -1) + "B", rid, 1)?.status).toBe(400);
    expect(validateCapsule(text.slice(0, -10) + "!" + text.slice(-9), rid, 1)?.status).toBe(400);
  });
  it("matches the fixed read-verifier domain and accepts exactly 1 MiB including the header", async () => {
    const cap = b64u(new Uint8Array(32));
    expect(await recoveryReadVerifier(cap)).toBe(b64u(await sha256(new Uint8Array([...new TextEncoder().encode("gift-huddle-recovery-read-verifier-v2"), 0, ...new Uint8Array(32)]))));
    const rid = key();
    expect(validateCapsule(capsule(rid, 1, { size: RECOVERY_MAX_BYTES }), rid, 1)).toBeNull();
    expect(validateCapsule(capsule(rid, 1, { size: RECOVERY_MAX_BYTES + 1 }), rid, 1)?.status).toBe(413);
  });
  it.each([
    { header: { v: 1 } }, { header: { r: 0 } }, { header: { r: 1.5 } }, { header: { rid: key() } },
    { header: { extra: true } }, { header: { s: "AA" } }, { header: { k: "backup" } },
    ...[{ a: "argon2id", m: 19455, p: 1, t: 2 }, { a: "argon2id", m: 19456, p: 2, t: 2 }, { a: "argon2id", m: 19456, p: 1, t: 1 }, { a: "argon2id", m: 19456, p: 1, t: 2, extra: 1 }].map((kdf) => ({ header: { kdf } })),
    { magic: [0x47, 0x48, 0x52, 1] }, { magic: [0x47, 0x48, 0x52, 3] },
    { text: " ".repeat(1025) }, { text: "{}" },
  ])("rejects incompatible headers %j", (options) => {
    const rid = key(); expect(validateCapsule(capsule(rid, 1, options), rid, 1)?.status).toBe(400);
  });
  it("rejects noncanonical JSON, base64 padding, wrong revision and truncation", () => {
    const rid = key(), good = capsule(rid, 1), bin = decodeB64Url(good)!;
    const h = JSON.parse(new TextDecoder().decode(bin.subarray(6, 6 + bin[4]! * 256 + bin[5]!)));
    for (const text of [capsule(rid, 1, { text: JSON.stringify(h, null, 1) }), good + "=", "AAAA", b64u(bin.subarray(0, bin.length - 40))]) expect(validateCapsule(text, rid, 1)?.status).toBe(400);
    expect(validateCapsule(good, rid, 2)?.status).toBe(400);
  });
  it.each(["put", "claim", "prepare", "commit"])("streams the %s body limit before discovery/authentication", async (kind) => {
    const id = await setup(), rid = key();
    const path = kind === "put" ? `${id.path}/recoveries/${rid}` : kind === "claim" ? `/v2/recoveries/${rid}/claim` : kind === "prepare" ? `${id.path}/recoveries/${rid}/rotation` : `${id.path}/recoveries/${rid}/rotation/${op()}/commit`;
    const limit = kind === "commit" ? 4096 : RECOVERY_MAX_BODY_BYTES;
    await error(await call(kind === "put" ? "PUT" : "POST", path, { key: id.key, rawBody: " ".repeat(limit + 1), headers: { "X-Recovery-Cap": key(), "If-Match": '"0"', "X-Recovery-Operation": op() } }), 413, "recovery_too_large");
  });
  it.each(["GET", "DELETE"])("rejects every body byte on %s", async (method) => {
    const id = await setup(), r = await recovery(id);
    // Request disallows GET bodies; retain the stream of a POST for direct dispatch.
    const req = new Request(`https://sync.test${method === "GET" ? r.publicPath : r.path}`, { method: "POST", body: "x", headers: { Authorization: `Bearer ${id.key}`, "X-Recovery-Cap": r.cap } });
    Object.defineProperty(req, "method", { value: method });
    await error(await worker.fetch(req, env as unknown as Env), 400, "invalid_recovery");
  });
});

describe("recovery CRUD, CAS and emergency metadata", () => {
  it("stores separately from snapshots, preserves creation receipts and never reuses a retired id", async () => {
    const id = await setup(), before = await json(await call("GET", id.path, { key: id.key })), r = await recovery(id);
    const firstBody = await json(r.response);
    expect(await json(await get(r))).toEqual({ ...firstBody, capsule: r.body.capsule });
    expect((await get(r)).headers.get("ETag")).toBe('"1"');
    expect((await get(r)).headers.get("Cache-Control")).toContain("no-store");
    expect(await json(await call("GET", id.path, { key: id.key }))).toEqual(before);
    await reopen(id, r.rid);
    expect(await json(await r.create())).toEqual(firstBody);
    expect((await replace(id, r)).status).toBe(200);
    expect((await r.create()).status).toBe(201);
    expect((await get(r)).headers.get("ETag")).toBe('"2"');
    expect((await remove(id, r, 2)).status).toBe(204);
    await reopen(id, r.rid);
    expect((await r.create()).status).toBe(201); // receipt cannot revive the code
    await error(await get(r), 404, "not_found");
    await error(await call("PUT", r.path, { key: id.key, headers: { "If-Match": '"0"', "X-Recovery-Operation": op() }, body: r.body }), 409, "recovery_retired");
  });
  it("distinguishes missing/stale CAS and rejects revision, verifier and owner changes atomically", async () => {
    const id = await setup(), r = await recovery(id);
    await error(await call("PUT", r.path, { key: id.key, body: r.body }), 428, "precondition_required");
    await error(await replace(id, r, 0), 412, "precondition_failed");
    await error(await call("PUT", r.path, { key: id.key, headers: { "If-Match": '"1"' }, body: { ...r.body, capsule: capsule(r.rid, 3) } }), 400, "invalid_recovery");
    await error(await call("PUT", r.path, { key: id.key, headers: { "If-Match": '"1"' }, body: { ...r.body, readVerifier: key(), capsule: capsule(r.rid, 2) } }), 400, "invalid_recovery");
    const other = await pair(id);
    await error(await replace(id, r, 1, other.guestKey), 403, "forbidden_role");
    expect((await get(r)).headers.get("ETag")).toBe('"1"');
    await error(await call("PUT", r.path, { key: id.key, headers: { "If-Match": '"0"', "X-Recovery-Operation": r.operationId }, body: { ...r.body, capsule: capsule(r.rid, 1, { size: 300 }) } }), 409, "recovery_operation_conflict");
  });
  it("Nora discovers and deletes another mobile's code without words; deletion replay is bound to her original CAS", async () => {
    const id = await setup(), r = await recovery(id), nora = await pair(id);
    const metadata = await call("GET", `${id.path}/recoveries`, { key: nora.guestKey });
    expect(metadata.headers.has("ETag")).toBe(false);
    expect(await json(metadata)).toEqual({ v: 2, recoveries: [{ deviceId: "aritz", recoveryId: r.rid, revision: 1, state: "active" }] });
    expect((await replace(id, r)).status).toBe(200);
    await error(await remove(id, r, 1, nora.guestKey), 412, "precondition_failed");
    expect((await remove(id, r, 2, nora.guestKey)).status).toBe(204);
    await reopen(id, r.rid);
    const replay = await remove(id, r, 2, nora.guestKey);
    expect(replay.status).toBe(204); expect(replay.headers.has("ETag")).toBe(false);
    await error(await remove(id, r, 1, nora.guestKey), 412, "precondition_failed");
    await error(await remove(id, r, 2), 404, "not_found");
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
  });
  it("blocks visitors, web credentials and revoked identities before metadata or CAS", async () => {
    const id = await setup(), r = await recovery(id), nora = await pair(id);
    await editState(id, (m) => { m.credentials.find((a) => a.deviceId === "nora")!.role = "web"; });
    for (const [method, path] of [["GET", `${id.path}/recoveries`], ["DELETE", r.path]]) {
      await error(await call(method!, path!, { key: nora.guestKey }), 403, "mobile_required");
      await error(await call(method!, path!), 401, "unauthorized");
    }
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("GET", `${id.path}/recoveries`, { key: nora.guestKey })).status).toBe(403);
  });
  it("enforces one code per identity and four active identities per list", async () => {
    const id = await setup(); await recovery(id);
    const rid = key();
    await error(await call("PUT", `${id.path}/recoveries/${rid}`, { key: id.key, headers: { "If-Match": '"0"', "X-Recovery-Operation": op() }, body: { v: 2, deviceId: "aritz", readVerifier: key(), capsule: capsule(rid, 1) } }), 409, "recovery_exists");
    // Populate service identities without spending the unrelated pairing quotas.
    for (const deviceId of ["nora", "leo", "aritz2", "nora2"]) {
      const credential = key(), verifier = await digest(credential);
      await editState(id, (m) => m.credentials.push({ deviceId, verifier, revoked: false, records: [] }));
      if (deviceId !== "nora2") await recovery(id, deviceId, credential);
      else {
        const rid = key();
        await error(await call("PUT", `${id.path}/recoveries/${rid}`, { key: credential, headers: { "If-Match": '"0"', "X-Recovery-Operation": op() }, body: { v: 2, deviceId, readVerifier: key(), capsule: capsule(rid, 1) } }), 409, "recovery_limit");
      }
    }
  });
});

describe("atomic claim and credential fence", () => {
  it("forgets the slot list capacity of the old install, so the receiving one announces it again (1.0.6)", async () => {
    const id = await setup(), r = await recovery(id);
    expect((await call("POST", `${id.path}/capability`, { key: id.key, body: { slotCapacity: 2 } })).status).toBe(200);
    const devices = async (key: string) => (await json<{ devices: { deviceId: string; slotCapacity?: number }[] }>(await call("GET", id.path, { key }))).devices;
    expect((await devices(id.key)).find((d) => d.deviceId === "aritz")!.slotCapacity).toBe(2);
    const next = await claimBody(r);
    expect((await claim(id, r, next.body)).status).toBe(200);
    expect((await devices(next.newKey)).find((d) => d.deviceId === "aritz")!.slotCapacity).toBeUndefined();
    expect((await call("POST", `${id.path}/capability`, { key: next.newKey, body: { slotCapacity: 2 } })).status).toBe(200);
    expect((await devices(next.newKey)).find((d) => d.deviceId === "aritz")!.slotCapacity).toBe(2);
  });
  it("a lost response replays exactly after eviction and ordinary updates; altered bytes/CAS conflict and another operation is replaced", async () => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    const response = await claim(id, r, next.body), result = await json(response);
    expect(response.status).toBe(200); expect(result).toMatchObject({ revision: 2, operationId: next.body.operationId, deviceId: "aritz" });
    expect((await state(id)).version).toBe(2);
    await reopen(id, r.rid);
    const beforeQuota = await quota(id);
    const replay = await claim(id, r, next.body);
    expect(await json(replay)).toEqual(result); expect(replay.headers.get("ETag")).toBe(response.headers.get("ETag"));
    expect(await quota(id)).toBe(beforeQuota);
    await error(await claim(id, r, { ...next.body, newCredentialVerifier: key() }), 409, "recovery_operation_conflict");
    await error(await claim(id, r, next.body, '"2"'), 409, "recovery_operation_conflict");
    await error(await claim(id, r, { ...next.body, newCredentialVerifier: key() }, '"2"', next.newKey), 409, "recovery_operation_conflict");
    await error(await claim(id, r, { ...next.body, operationId: op() }), 403, "credential_replaced");
    expect((await replace(id, r, 2, next.newKey)).status).toBe(200);
    expect(await json(await claim(id, r, next.body))).toEqual(result);
    expect((await get(r)).headers.get("ETag")).toBe('"3"');
    const second = await claimBody(r, 4);
    expect((await claim(id, r, second.body, '"3"', next.newKey)).status).toBe(200);
    await error(await claim(id, r, next.body), 403, "credential_replaced");
  });
  it("serializes competing claims, replacing credential and capsule only once", async () => {
    const id = await setup(), r = await recovery(id), a = await claimBody(r), b = await claimBody(r);
    const results = await Promise.all([claim(id, r, a.body), claim(id, r, b.body)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 403]);
    expect((await get(r)).headers.get("ETag")).toBe('"2"');
    expect((await state(id)).version).toBe(2);
    const winner = results[0]!.status === 200 ? a : b;
    expect((await call("GET", id.path, { key: winner.newKey })).status).toBe(200);
  });
  it("rejects the old credential on every list, guard, renewal, invitation and WebSocket route", async () => {
    const id = await setup(), r = await recovery(id), i = await invite(id), next = await claimBody(r);
    expect((await claim(id, r, next.body)).status).toBe(200);
    const cases: [string, string, unknown?][] = [
      ["GET", id.path], ["PUT", id.path, snapshot()], ["DELETE", id.path], ["PUT", `${id.path}/common`, { common: "AAAA" }],
      ["GET", `${id.path}/slots/nora/aritz`], ["POST", `${id.path}/capability`, { commonFormat: 2 }], ["POST", `${id.path}/revoke`, { deviceId: "nora" }],
      ["GET", `${id.path}/renewal`], ["PUT", `${id.path}/renewal`, { action: "reserve" }],
      ["POST", `${id.path}/invites`, { offer: {} }], ["GET", i.privatePath], ["DELETE", i.privatePath], ["POST", `${i.privatePath}/reveal`, {}], ["POST", `${i.privatePath}/approve`, {}],
      ["GET", `${i.publicPath}/offer`], ["POST", `${i.publicPath}/answer`, i.body], ["GET", `${i.publicPath}/result`], ["GET", `${i.publicPath}/checkpoint`], ["DELETE", `${i.publicPath}/checkpoint`],
      ["GET", `${id.path}/recoveries`], ["PUT", r.path, { ...r.body, capsule: capsule(r.rid, 3) }], ["DELETE", r.path],
      ["POST", `${r.path}/rotation`, { v: 2, operationId: op(), newRecoveryId: key(), readVerifier: key(), capsule: "AAAA" }], ["POST", `${r.path}/rotation/${op()}/commit`, { v: 2 }],
      ...["prepare", "commit", "cancel", "open", "resume"].map((action): [string, string, unknown] => [action === "prepare" ? "PUT" : "POST", `${id.path}/guards/aritz/${action}`, {}]),
    ];
    for (const [method, path, body] of cases) {
      const res = await call(method, path, { key: id.key, body, headers: { "If-Match": '"2"' } });
      expect([res.status, await json(res), res.headers.get("ETag")], `${method} ${path}`).toEqual([403, { error: "credential_replaced" }, null]);
    }
    await error(await exports.default.fetch(new Request(`https://sync.test${id.path}/ws`, { headers: { Upgrade: "websocket", Authorization: `Bearer ${id.key}` } })), 403, "credential_replaced");
    const disabled = (credential: string) => routeV2(new Request(`https://sync.test${id.path}/renewal`, { method: "PUT", headers: { Authorization: `Bearer ${credential}`, "Content-Type": "application/json" }, body: JSON.stringify({ action: "reserve" }) }), { ...env, RENEWAL_ENABLED: "false" });
    await error(await disabled(id.key), 403, "credential_replaced");
    await error(await disabled(next.newKey), 409, "renewal_disabled");
  });
  it("invalidates approved host AND guest invitations, pending results and their checkpoints in the claim transaction", async () => {
    const id = await setup(), joined = await pair(id), hosted = await pair(id, "leo", "nora", joined.guestKey);
    const pending = await invite(id, "leo2", "nora", joined.guestKey);
    const r = await recovery(id, "nora", joined.guestKey), next = await claimBody(r);
    expect((await call("GET", `${joined.publicPath}/checkpoint`, { key: joined.guestKey })).status).toBe(200);
    expect((await call("GET", `${hosted.publicPath}/checkpoint`, { key: hosted.guestKey })).status).toBe(200);
    expect((await claim(id, r, next.body, '"1"', joined.guestKey)).status).toBe(200);
    for (const i of [joined, hosted, pending]) {
      expect((await call("GET", `${i.publicPath}/offer`)).status).toBe(404);
      expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey === joined.guestKey ? next.newKey : i.guestKey })).status).toBe(404);
      expect((await call("GET", `${i.publicPath}/checkpoint`, { key: i.guestKey === joined.guestKey ? next.newKey : i.guestKey })).status).toBe(404);
    }
    expect(await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM checkpoint").one().n)).toBe(0);
    const fresh = await invite(id, "nora2");
    await error(await call("POST", `${fresh.publicPath}/answer`, { body: { ...fresh.body, serviceCredentialVerifier: await digest(joined.guestKey) } }), 401, "unauthorized");
    // Even an old pending answer cannot be approved after its proposed verifier was retired.
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const row = s.storage.sql.exec<{ data: string }>("SELECT data FROM invite WHERE id = ?", fresh.inviteId).one();
      const i = JSON.parse(row.data); Object.assign(i, { answer: fresh.body.answer, guest: "nora2", verifier: joined.body.serviceCredentialVerifier, reveal: { v: 2, n: key() } });
      s.storage.sql.exec("UPDATE invite SET data = ? WHERE id = ?", JSON.stringify(i), fresh.inviteId);
    });
    await error(await call("POST", `${fresh.privatePath}/approve`, { key: id.key, headers: { "If-Match": `"${(await state(id)).version}"` }, body: { package: {} } }), 409, "credential_exists");
  });
});

describe("public authorization precedence and rotation", () => {
  it.each(["unknown", "active", "retired", "revoked", "web"] as const)("GET/claim matrix for %s: no CAS, credential or operation oracle before the capability", async (kind) => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    if (kind === "unknown") { r.rid = key(); r.publicPath = `/v2/recoveries/${r.rid}`; }
    if (kind === "retired") expect((await remove(id, r)).status).toBe(204);
    if (kind === "revoked") expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "aritz" } })).status).toBe(200);
    if (kind === "web") await editState(id, (m) => { m.credentials[0]!.role = "web"; });
    for (const cap of [key(), r.cap]) {
      const visible = kind === "active" && cap === r.cap;
      const got = await get(r, cap);
      expect(got.status).toBe(visible ? 200 : 404);
      if (!visible) { expect(await json(got)).toEqual({ error: "not_found" }); expect(got.headers.has("ETag")).toBe(false); }
      for (const [credential, match, body, status, code] of [
        [key(), null, next.body, 401, "unauthorized"],
        [id.key, null, next.body, 428, "precondition_required"],
        [id.key, '"99"', next.body, 412, "precondition_failed"],
        [id.key, '"1"', { ...next.body, operationId: "!" }, 400, "invalid_recovery"],
      ] as const) {
        const res = await claim(id, r, body, match, credential, cap);
        expect(res.status).toBe(visible ? status : 404);
        expect(await json(res)).toEqual({ error: visible ? code : "not_found" });
        if (!visible) { expect(res.headers.has("ETag")).toBe(false); expect(res.headers.has("Retry-After")).toBe(false); }
      }
    }
  });
  it.each(["unknown", "active"])("syntax is uniform before discovery for %s rid", async (kind) => {
    const id = await setup(), r = await recovery(id);
    if (kind === "unknown") r.publicPath = `/v2/recoveries/${key()}`;
    for (const body of [{}, { v: 1 }, { v: 2, operationId: 9 }, { v: 2, operationId: op(), newCredentialVerifier: key(), capsule: "AAAA", extra: true }]) await error(await claim(id, r, body), 400, "invalid_recovery");
    await error(await claim(id, r, (await claimBody(r)).body, 'W/"1"'), 400, "invalid_recovery");
    await error(await get(r, "not-canonical"), 400, "invalid_recovery");
  });
  it.each(["revoke", "delete", "retire"] as const)("%s prevails over exact, altered and unrelated claim replays", async (kind) => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    expect((await claim(id, r, next.body)).status).toBe(200);
    if (kind === "revoke") expect((await call("POST", `${id.path}/revoke`, { key: next.newKey, body: { deviceId: "aritz" } })).status).toBe(200);
    if (kind === "delete") expect((await remove(id, r, 2, next.newKey)).status).toBe(204);
    if (kind === "retire") expect((await call("DELETE", id.path, { key: next.newKey, headers: { "If-Match": '"2"' } })).status).toBe(204);
    for (const body of [next.body, { ...next.body, newCredentialVerifier: key() }, { ...next.body, operationId: op() }]) {
      const res = await claim(id, r, body); await error(res, 404, "not_found"); expect(res.headers.has("ETag")).toBe(false);
    }
    if (kind === "revoke") await error(await call("GET", id.path, { key: id.key }), 404, "not_found");
    if (kind === "delete") await error(await call("GET", id.path, { key: id.key }), 403, "credential_replaced");
  });
  it("a candidate is GET 200 / claim 409 only with its capability; prepare/commit replay exactly after reopen", async () => {
    const id = await setup(), r = await recovery(id), candidate = await prepare(id, r);
    expect(await json(await call("GET", `${id.path}/recoveries`, { key: id.key }))).toEqual({ v: 2, recoveries: [{ deviceId: "aritz", recoveryId: r.rid, revision: 1, state: "rotationPending" }] });
    for (const cap of [candidate.cap, key()]) {
      const good = cap === candidate.cap;
      expect((await get(candidate, cap)).status).toBe(good ? 200 : 404);
      await error(await claim(id, candidate, (await claimBody(candidate)).body, null, key(), cap), good ? 409 : 404, good ? "recovery_not_active" : "not_found");
    }
    const beforeQuota = await quota(id);
    await reopen(id, candidate.rid);
    expect((await candidate.send()).status).toBe(201);
    expect(await quota(id)).toBe(beforeQuota);
    const committed = await candidate.commit(), body = await json(committed);
    expect(committed.status).toBe(200); expect(body).toMatchObject({ recoveryId: candidate.rid, revision: 1, operationId: candidate.operationId });
    expect((await get(r)).status).toBe(404); expect((await get(candidate)).status).toBe(200);
    const committedQuota = await quota(id);
    await reopen(id, candidate.rid);
    for (const response of [await candidate.commit(), await candidate.send()]) { expect(response.status).toBe(200); expect(await json(response)).toEqual(body); expect(response.headers.get("ETag")).toBe('"1"'); }
    expect(await quota(id)).toBe(committedQuota);
    await error(await call("POST", `${r.path}/rotation`, { key: id.key, headers: { "If-Match": '"2"' }, body: candidate.body }), 409, "recovery_operation_conflict");
    expect((await state(id)).credentials[0]!.verifier).toBe(await digest(id.key));
  });
  it.each(["put", "claim", "delete", "expiry"] as const)("%s closes a candidate without reviving it through prepare/commit replays", async (kind) => {
    const id = await setup(), r = await recovery(id), candidate = await prepare(id, r);
    let credential = id.key;
    if (kind === "put") expect((await replace(id, r)).status).toBe(200);
    if (kind === "claim") { const next = await claimBody(r); expect((await claim(id, r, next.body)).status).toBe(200); credential = next.newKey; }
    if (kind === "delete") expect((await remove(id, r)).status).toBe(204);
    if (kind === "expiry") {
      await runInDurableObject(listStub(id.syncId), (_o, s) => { const store = new RecoveryStore(s.storage.sql), row = store.get(candidate.rid)!; row.expiresAt = Date.now() - 1; store.save(row); });
      await runDurableObjectAlarm(listStub(id.syncId));
    }
    await reopen(id, candidate.rid);
    const code = kind === "expiry" ? "recovery_rotation_expired" : "recovery_rotation_cancelled";
    for (const [path, body] of [[`${r.path}/rotation`, candidate.body], [`${r.path}/rotation/${candidate.operationId}/commit`, { v: 2 }]] as const) await error(await call("POST", path, { key: credential, headers: { "If-Match": '"1"' }, body }), 409, code);
    await error(await get(candidate), 404, "not_found");
    expect((await get(r)).status).toBe(kind === "delete" ? 404 : 200);
    if (kind === "delete") expect((await remove(id, r)).status).toBe(204);
  });
  it("allows only one temporary candidate across the list and closes both resources on revocation", async () => {
    const id = await setup(), r = await recovery(id), candidate = await prepare(id, r), nora = await pair(id), second = await recovery(id, "nora", nora.guestKey);
    const fresh = key();
    await error(await call("POST", `${second.path}/rotation`, { key: nora.guestKey, headers: { "If-Match": '"1"' }, body: { v: 2, operationId: op(), newRecoveryId: fresh, readVerifier: key(), capsule: capsule(fresh, 1) } }), 409, "recovery_exists");
    expect((await call("POST", `${id.path}/revoke`, { key: nora.guestKey, body: { deviceId: "aritz" } })).status).toBe(200);
    await error(await get(r), 404, "not_found"); await error(await get(candidate), 404, "not_found");
    expect(await json(await call("GET", `${id.path}/recoveries`, { key: nora.guestKey }))).toMatchObject({ recoveries: [{ deviceId: "nora" }] });
  });
});

describe("recovery quotas and atomic rejection", () => {
  it("isolates daily writes and lifetime ids per identity, and reserves claims after ordinary exhaustion", async () => {
    const id = await setup(), r = await recovery(id), nora = await pair(id), nr = await recovery(id, "nora", nora.guestKey);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      s.storage.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify({ minute: 0, mutations: 0, day: Math.floor(Date.now() / 86400000), writes: 6, devices: { aritz: { writes: 6, claims: 0 } } }));
    });
    await reopen(id);
    expect((await replace(id, r)).status).toBe(429);
    expect((await replace(id, nr, 1, nora.guestKey)).status).toBe(200);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const store = new RecoveryStore(s.storage.sql), row = store.get(r.rid)!;
      for (let n = 0; n < 31; n++) store.save({ ...row, rid: key(), state: "retired" });
      const fresh = { ...row, rid: key(), state: "intention" as const };
      expect(store.history([...store.rows(), fresh])?.status).toBe(409);
      expect(store.history([...store.rows(), { ...fresh, deviceId: "nora" }])).toBeNull();
      const q = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM recovery_quota").one().data);
      q.writes = 24; q.minute = 0; s.storage.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify(q));
    });
    const rid = key(), beforeHistory = await quota(id);
    await error(await call("POST", `${r.path}/rotation`, { key: id.key, headers: { "If-Match": '"1"' }, body: { v: 2, operationId: op(), newRecoveryId: rid, readVerifier: key(), capsule: capsule(rid, 1) } }), 409, "recovery_history_full");
    expect((await rows(id)).some((row) => row.rid === rid)).toBe(false); expect(await quota(id)).toBe(beforeHistory);
    const next = await claimBody(r);
    expect((await claim(id, r, next.body)).status).toBe(200);
    expect((await replace(id, nr, 2, nora.guestKey)).status).toBe(429);
    await reopen(id);
    const again = await claimBody(r, 3);
    expect((await claim(id, r, again.body, '"2"', next.newKey)).status).toBe(200);
    const third = await claimBody(r, 4);
    const before = await quota(id);
    expect((await claim(id, r, third.body, '"3"', again.newKey)).status).toBe(429);
    expect(await quota(id)).toBe(before);
  }, 20_000);
  it.each(["active", "revoked", "retired", "invitation"] as const)("rejects a new verifier colliding with %s state without changing the claim", async (kind) => {
    const id = await setup(), r = await recovery(id);
    let collision = await digest(id.key);
    if (kind === "revoked") { const nora = await pair(id); collision = await digest(nora.guestKey); await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } }); }
    if (kind === "retired") { collision = key(); await runInDurableObject(listStub(id.syncId), (_o, s) => new RecoveryStore(s.storage.sql).retireVerifier(collision, "nora")); }
    if (kind === "invitation") { const i = await invite(id); collision = i.body.serviceCredentialVerifier; expect((await call("POST", `${i.publicPath}/answer`, { body: i.body })).status).toBe(201); }
    const before = await state(id), beforeQuota = await quota(id), next = await claimBody(r);
    await error(await claim(id, r, { ...next.body, newCredentialVerifier: collision }), 409, "recovery_credential_conflict");
    expect(await state(id)).toEqual(before); expect(await quota(id)).toBe(beforeQuota);
    expect((await get(r)).headers.get("ETag")).toBe('"1"');
  });
  it("checks all mutation budgets without charging failed/conflicting operations; exact replay remains exempt", async () => {
    const id = await setup(), r = await recovery(id);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      s.storage.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify({ minute: Math.floor(Date.now() / 60000), mutations: 6, day: Math.floor(Date.now() / 86400000), writes: 1 }));
    });
    const before = await quota(id);
    expect((await r.create()).status).toBe(201);
    for (const res of [await replace(id, r), await claim(id, r, (await claimBody(r)).body), await remove(id, r)]) { expect(res.status).toBe(429); expect(Number(res.headers.get("Retry-After"))).toBeGreaterThan(0); }
    expect(await quota(id)).toBe(before);
    expect((await get(r)).headers.get("ETag")).toBe('"1"');
    await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify({ minute: 0, mutations: 0, day: Math.floor(Date.now() / 86400000), writes: 24, claims: 8 })));
    expect((await replace(id, r)).status).toBe(429);
    expect((await claim(id, r, (await claimBody(r)).body)).status).toBe(429);
    const rid = key();
    expect((await call("POST", `${r.path}/rotation`, { key: id.key, headers: { "If-Match": '"1"' }, body: { v: 2, operationId: op(), newRecoveryId: rid, readVerifier: key(), capsule: capsule(rid, 1) } })).status).toBe(429);
    expect((await remove(id, r)).status).toBe(204); // emergency delete has no daily write cost
  });
  it.each(["ids", "receipts", "verifiers", "metadata", "receiptBytes"] as const)("reserves %s capacity before accepting a write; terminal DELETE remains available", async (limit) => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const store = new RecoveryStore(s.storage.sql), row = store.get(r.rid)!;
      if (limit === "verifiers") for (let n = 0; n < 256; n++) store.retireVerifier(b64u(new Uint8Array(32).fill(n)), "nora");
      if (limit === "ids" || limit === "receipts") for (let n = 0; n < 255; n++) store.save({ ...row, rid: b64u(new Uint8Array(32).fill(n)), state: "retired" });
      if (limit === "metadata") for (let n = 0; n < 40; n++) store.save({ ...row, rid: b64u(new Uint8Array(32).fill(n)), state: "retired", padding: "x".repeat(110000) } as RecoveryRow);
      if (limit === "receiptBytes") { row.initial.response.body = { padding: "x".repeat(4096) }; store.save(row); }
    });
    const before = await state(id), beforeQuota = await quota(id);
    if (limit === "ids") {
      // Another principal can attempt an allocation; the active one stays untouched.
      const credential = key(), verifier = await digest(credential), rid = key();
      await editState(id, (m) => m.credentials.push({ deviceId: "nora", verifier, revoked: false, records: [] }));
      await error(await call("PUT", `${id.path}/recoveries/${rid}`, { key: credential, headers: { "If-Match": '"0"', "X-Recovery-Operation": op() }, body: { v: 2, deviceId: "nora", readVerifier: key(), capsule: capsule(rid, 1) } }), 409, "recovery_history_full");
    } else await error(await claim(id, r, next.body), 409, "recovery_history_full");
    expect((await state(id)).credentials[0]).toEqual(before.credentials[0]); expect(await quota(id)).toBe(beforeQuota);
    expect((await get(r)).headers.get("ETag")).toBe('"1"');
    expect((await remove(id, r)).status).toBe(204);
  });
  it("publishing recovery promotes an invitation-only copy to permanent sync retention", async () => {
    const id = await setup(true), r = await recovery(id);
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(Date.now() + 2 * 86400000);
      await runDurableObjectAlarm(listStub(id.syncId));
      expect((await get(r)).status).toBe(200);
      // Removing recovery never reintroduces the invitation-only deadline.
      expect((await remove(id, r)).status).toBe(204);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    } finally { vi.useRealTimers(); }
  });

  it.each([false, true])("retired locators expire after 400 days, including legacy rows (%s)", async (legacy) => {
    const id = await setup(), r = await recovery(id);
    const token = await runInDurableObject(locator(r.rid), async (_o, s) => (await s.storage.get<{ reservationId: string }>("locator"))!.reservationId);
    expect((await remove(id, r)).status).toBe(204);
    if (legacy) await runInDurableObject(locator(r.rid), async (_o, s) => {
      const row = (await s.storage.get<Record<string, unknown>>("locator"))!;
      delete row.retiredUntil;
      await s.storage.put("locator", row);
      await s.storage.deleteAlarm();
    });
    expect(await locator(r.rid).locate()).toBeNull();
    const deadline = await runInDurableObject(locator(r.rid), (_o, s) => s.storage.getAlarm());
    expect(deadline).toBeGreaterThan(Date.now() + 399 * 86400000);
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(deadline! - 1);
      expect(await runDurableObjectAlarm(locator(r.rid))).toBe(true);
      expect(await locator(r.rid).confirm(id.syncId, token)).toBe(false);
      expect(await locator(r.rid).reserve(newList().syncId, op())).toBe(false);
      await locator(r.rid).retire(id.syncId, token);
      expect(await runInDurableObject(locator(r.rid), (_o, s) => s.storage.getAlarm())).toBe(deadline);
      vi.setSystemTime(deadline!);
      expect(await runDurableObjectAlarm(locator(r.rid))).toBe(true);
      expect(await runInDurableObject(locator(r.rid), async (_o, s) => ({ size: (await s.storage.list()).size, alarm: await s.storage.getAlarm() }))).toEqual({ size: 0, alarm: null });
      expect(await locator(r.rid).reserve(newList().syncId, op())).toBe(true);
    } finally { vi.useRealTimers(); }
  });

  it("limits discovery to 30 per IP before obtaining locators; unknown reads leave no rows or alarms", async () => {
    const rid = key(), ip = randomIp();
    for (let n = 0; n < 30; n++) expect((await call("GET", `/v2/recoveries/${rid}`, { ip, headers: { "X-Recovery-Cap": key() } })).status).toBe(404);
    expect((await call("GET", `/v2/recoveries/${rid}`, { ip, headers: { "X-Recovery-Cap": key() } })).status).toBe(429);
    expect(await runInDurableObject(locator(rid), async (_o, s) => ({ size: (await s.storage.list()).size, alarm: await s.storage.getAlarm() }))).toEqual({ size: 0, alarm: null });
  });
  it("rejects exhausted capsule revisions without wrapping or changing credentials", async () => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    await runInDurableObject(listStub(id.syncId), (_o, s) => { const store = new RecoveryStore(s.storage.sql), row = store.get(r.rid)!; row.revision = Number.MAX_SAFE_INTEGER; store.save(row); });
    await error(await claim(id, r, next.body, `"${Number.MAX_SAFE_INTEGER}"`), 409, "recovery_limit");
    await error(await replace(id, r, Number.MAX_SAFE_INTEGER), 409, "recovery_limit");
    expect((await state(id)).credentials[0]!.verifier).toBe(await digest(id.key));
  });
  it("accepts four full-size blobs plus exactly one full-size temporary candidate", async () => {
    const id = await setup();
    // Full recovery resource caps also require enough aggregate list capacity.
    await editState(id, (m) => {
      for (let n = 0; n < 4; n++) m.credentials.push({ deviceId: `capacity${n}`, verifier: key(), revoked: false, records: [], createdAt: Date.now() - 8 * 86400000 } as Meta["credentials"][number]);
    });
    const active: Recovery[] = [];
    for (const deviceId of ["aritz", "nora", "leo", "aritz2"]) {
      const credential = deviceId === "aritz" ? id.key : key(), verifier = await digest(credential);
      if (deviceId !== "aritz") await editState(id, (m) => m.credentials.push({ deviceId, verifier, revoked: false, records: [] }));
      const r = await recovery(id, deviceId, credential);
      // Reset only the recovery minute budget; all four full-size writes still spend the daily budget.
      await runInDurableObject(listStub(id.syncId), (_o, s) => {
        const q = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM recovery_quota").one().data); q.minute = 0; s.storage.sql.exec("UPDATE recovery_quota SET data = ?", JSON.stringify(q));
      });
      expect((await call("PUT", r.path, { key: credential, headers: { "If-Match": '"1"' }, body: { ...r.body, capsule: capsule(r.rid, 2, { size: RECOVERY_MAX_BYTES }) } })).status).toBe(200);
      active.push(r);
    }
    const rid = key();
    expect((await call("POST", `${active[0]!.path}/rotation`, { key: id.key, headers: { "If-Match": '"2"' }, body: { v: 2, operationId: op(), newRecoveryId: rid, readVerifier: key(), capsule: capsule(rid, 1, { size: RECOVERY_MAX_BYTES }) } })).status).toBe(201);
    const stored = await rows(id);
    expect(stored.filter((r) => r.state === "active").reduce((n, r) => n + r.size, 0)).toBe(4 * RECOVERY_MAX_BYTES);
    expect(stored.filter((r) => r.state === "candidate").reduce((n, r) => n + r.size, 0)).toBe(RECOVERY_MAX_BYTES);
  });
});

describe("recovery interruption, durable discovery and retirement", () => {
  it("looks up only the requested rid and expires candidates on recovery routes rather than ordinary v2 reads", async () => {
    const id = await setup(), r = await recovery(id), candidate = await prepare(id, r);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const store = new RecoveryStore(s.storage.sql);
      const scan = vi.spyOn(store, "rows").mockImplementation(() => { throw new Error("get must use the primary key"); });
      try { expect(store.get(candidate.rid)?.rid).toBe(candidate.rid); expect(store.get(key())).toBeUndefined(); }
      finally { scan.mockRestore(); }
      const row = store.get(candidate.rid)!; row.expiresAt = Date.now() - 1; store.save(row);
    });
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect((await rows(id)).find((row) => row.rid === candidate.rid)?.state).toBe("candidate");
    expect((await get(candidate)).status).toBe(404);
    expect((await rows(id)).find((row) => row.rid === candidate.rid)?.terminal).toBe("expired");
  });
  async function draft(id: Setup) {
    const rid = key(), cap = key(), operationId = op();
    const body = { v: 2, deviceId: "aritz", readVerifier: await recoveryReadVerifier(cap), capsule: capsule(rid, 1) };
    const path = `${id.path}/recoveries/${rid}`, publicPath = `/v2/recoveries/${rid}`;
    return { rid, cap, operationId, body, path, publicPath, send: () => call("PUT", path, { key: id.key, headers: { "If-Match": '"0"', "X-Recovery-Operation": operationId }, body }) };
  }
  it.each(["intention", "reserved"] as const)("repairs an interrupted %s using the same token and one quota charge after reopening both objects", async (phase) => {
    const id = await setup(), r = await draft(id), original = RecoveryLocatorObject.prototype.reserve;
    await runInDurableObject(locator(r.rid), (instance) => {
      Object.getPrototypeOf(instance).reserve = async function(this: RecoveryLocatorObject, sid: string, token: string) {
        if (phase === "reserved") await original.call(this, sid, token);
        throw new Error("injected reservation interruption");
      };
    });
    try { const response = await r.send(); expect(response.status).toBe(503); expect(response.headers.get("Retry-After")).toBe("60"); }
    finally { await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).reserve = original; }); }
    const intent = (await rows(id))[0]!, beforeQuota = await quota(id);
    expect(intent.state).toBe("intention"); expect((await get(r)).status).toBe(404);
    await reopen(id, r.rid);
    expect((await r.send()).status).toBe(201); expect((await get(r)).status).toBe(200);
    expect((await rows(id))[0]!.reservationId).toBe(intent.reservationId); expect(await quota(id)).toBe(beforeQuota);
  });
  it("a committed blob remains readable through reserved discovery beyond 24 h, even if confirm was lost", async () => {
    const id = await setup(), r = await draft(id), original = RecoveryLocatorObject.prototype.confirm;
    await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).confirm = async () => { throw new Error("injected lost confirm"); }; });
    try {
      expect((await r.send()).status).toBe(201);
      expect((await get(r)).status).toBe(200);
    } finally { await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).confirm = original; }); }
    await reopen(id, r.rid);
    const now = Date.now(); vi.spyOn(Date, "now").mockReturnValue(now + RECOVERY_RESERVATION_MS + 1000);
    expect(await runDurableObjectAlarm(locator(r.rid))).toBe(true);
    expect((await get(r)).status).toBe(200);
    expect(await runInDurableObject(locator(r.rid), async (_o, s) => (await s.storage.get<{ state: string }>("locator"))!.state)).toBe("linked");
  });
  it("cancels an abandoned intention before retiring its locator; late/foreign confirmations cannot revive the id", async () => {
    const id = await setup(), r = await draft(id), original = RecoveryLocatorObject.prototype.reserve;
    await runInDurableObject(locator(r.rid), (instance) => {
      Object.getPrototypeOf(instance).reserve = async function(this: RecoveryLocatorObject, sid: string, token: string) { await original.call(this, sid, token); throw new Error("injected post-reserve failure"); };
    });
    try { const response = await r.send(); expect(response.status).toBe(503); expect(response.headers.get("Retry-After")).toBe("60"); }
    finally { await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).reserve = original; }); }
    const token = (await rows(id))[0]!.reservationId;
    await reopen(id, r.rid);
    const now = Date.now(); vi.spyOn(Date, "now").mockReturnValue(now + RECOVERY_RESERVATION_MS + 1000);
    await Promise.all([runDurableObjectAlarm(locator(r.rid)), r.send()]);
    expect((await rows(id))[0]!.state).toBe("retired");
    await error(await r.send(), 409, "recovery_retired");
    expect(await locator(r.rid).confirm(id.syncId, token)).toBe(false);
    expect(await locator(r.rid).confirm(id.syncId, op())).toBe(false);
    expect(await locator(r.rid).reserve(newList().syncId, op())).toBe(false);
    expect((await get(r)).status).toBe(404);
  });
  it("an unavailable authoritative list retains the reservation and alarm instead of releasing it by age", async () => {
    const id = await setup(), rid = key(), token = op();
    expect(await locator(rid).reserve(id.syncId, token)).toBe(true);
    const original = ListV2Object.prototype.recoveryReconcile;
    await runInDurableObject(listStub(id.syncId), (instance) => { Object.getPrototypeOf(instance).recoveryReconcile = async () => { throw new Error("injected list unavailable"); }; });
    try {
      const now = Date.now(); vi.spyOn(Date, "now").mockReturnValue(now + 2 * RECOVERY_RESERVATION_MS);
      await evictDurableObject(locator(rid));
      expect(await runDurableObjectAlarm(locator(rid))).toBe(true);
      expect(await locator(rid).locate()).toBe(id.syncId);
      expect(await locator(rid).reserve(newList().syncId, op())).toBe(false);
      expect(await runInDurableObject(locator(rid), async (_o, s) => (await s.storage.getAlarm())! > Date.now())).toBe(true);
    } finally { await runInDurableObject(listStub(id.syncId), (instance) => { Object.getPrototypeOf(instance).recoveryReconcile = original; }); }
  });
  it("serializes the same global rid across lists without relocating the winning reservation", async () => {
    const a = await setup(), b = await setup(), r = await draft(a);
    const sendB = () => call("PUT", `${b.path}/recoveries/${r.rid}`, { key: b.key, headers: { "If-Match": '"0"', "X-Recovery-Operation": op() }, body: r.body });
    const results = await Promise.all([r.send(), sendB()]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    const winner = results[0]!.status === 201 ? a : b;
    const loser = winner === a ? b : a;
    expect(await rows(loser)).toEqual([]);
    expect(JSON.parse(await quota(loser))).toMatchObject({ mutations: 0, writes: 0 });
    expect(await locator(r.rid).locate()).toBe(winner.syncId);
    expect((await get(r)).status).toBe(200);
    const token = (await rows(winner))[0]!.reservationId;
    expect(await locator(r.rid).confirm(winner.syncId, op())).toBe(false);
    expect(await locator(r.rid).confirm(winner.syncId, token)).toBe(true);
  });
  it.each(["delete", "revoke", "retire", "expiry"] as const)("%s denies stale locators immediately and retries failed cleanup after eviction", async (kind) => {
    const id = await setup(), r = await recovery(id), original = RecoveryLocatorObject.prototype.retire;
    await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).retire = async () => { throw new Error("injected locator cleanup failure"); }; });
    try {
      if (kind === "delete") expect((await remove(id, r)).status).toBe(204);
      if (kind === "revoke") expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "aritz" } })).status).toBe(500);
      if (kind === "retire") expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(500);
      if (kind === "expiry") { await editState(id, (m) => { m.lastAccess = Date.now() - 401 * 86400000; }); expect((await get(r)).status).toBe(404); }
      expect(await locator(r.rid).locate()).toBe(id.syncId);
      expect((await get(r)).status).toBe(404);
    } finally { await runInDurableObject(locator(r.rid), (instance) => { Object.getPrototypeOf(instance).retire = original; }); }
    await reopen(id, r.rid);
    await runDurableObjectAlarm(listStub(id.syncId));
    expect(await locator(r.rid).locate()).toBeNull();
    if (kind === "retire" || kind === "expiry" || kind === "revoke") {
      expect(await runInDurableObject(listStub(id.syncId), (_o, s) => ({ state: s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data, tables: s.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'recovery%'").toArray() }))).toEqual({ state: '{"retired":true}', tables: [] });
    }
  });
  it("a recovery GET does not extend the list lifetime", async () => {
    const id = await setup(), r = await recovery(id);
    await editState(id, (m) => { m.lastAccess = Date.now() - 399 * 86400000; });
    const before = (await state(id)).lastAccess;
    expect((await get(r)).status).toBe(200); expect((await state(id)).lastAccess).toBe(before);
    await editState(id, (m) => { m.lastAccess = Date.now() - 401 * 86400000; });
    expect((await get(r)).status).toBe(404);
    expect((await rows(id)).length).toBe(0);
  });
});

describe("recovery WebSocket credential epochs", () => {
  async function open(id: Setup, credential = id.key) {
    const response = await exports.default.fetch(new Request(`https://sync.test${id.path}/ws`, { headers: { Upgrade: "websocket", "Sec-WebSocket-Protocol": `gift-huddle.v2, bearer.${credential}` } }));
    expect(response.status).toBe(101);
    const ws = response.webSocket!; ws.accept();
    const closed = new Promise<CloseEvent>((resolve) => ws.addEventListener("close", (e) => { resolve(e); ws.close(); }));
    const messages: unknown[] = []; ws.addEventListener("message", (e) => messages.push(e.data));
    return { ws, closed, messages };
  }
  it("shares the 12 text pings/minute budget across sockets and resets on hibernation", async () => {
    const id = await setup(), first = await open(id);
    const pong = new Promise<void>((resolve) => first.ws.addEventListener("message", () => { if (first.messages.length === 6) resolve(); }));
    for (let n = 0; n < 6; n++) first.ws.send("ping");
    await pong;
    await evictDurableObject(listStub(id.syncId));
    const second = await open(id);
    for (let n = 0; n < 13; n++) second.ws.send("ping");
    expect((await second.closed).code).toBe(1008);
    expect(second.messages.every((m) => m === "pong")).toBe(true);
    expect(second.messages.length).toBe(12);
    first.ws.close();
  });
  it("closes other messages before storage and does not perform live maintenance on ping", async () => {
    const id = await setup(), verifier = await digest(id.key);
    await runInDurableObject(listStub(id.syncId), async (instance) => {
      const internal = instance as unknown as { stored(): unknown; live(): Promise<unknown> };
      const stored = vi.spyOn(internal, "stored");
      const live = vi.spyOn(internal, "live").mockRejectedValue(new Error("must not run maintenance"));
      const ws = { close: vi.fn(), send: vi.fn(), deserializeAttachment: () => ({ deviceId: "aritz", credentialVerifier: verifier }) } as unknown as WebSocket;
      try {
        await instance.webSocketMessage(ws, "unexpected");
        expect(stored).not.toHaveBeenCalled(); expect(ws.close).toHaveBeenCalledWith(1008, "read only");
        await instance.webSocketMessage(ws, "ping");
        expect(ws.send).toHaveBeenCalledWith("pong"); expect(live).not.toHaveBeenCalled();
      } finally { stored.mockRestore(); live.mockRestore(); }
    });
  });
  it.each([false, true])("closes replaced sockets with 4410 before sending versions (hibernated=%s)", async (hibernate) => {
    const id = await setup(), r = await recovery(id), socket = await open(id);
    if (hibernate) await evictDurableObject(listStub(id.syncId));
    const next = await claimBody(r); expect((await claim(id, r, next.body)).status).toBe(200);
    expect(await socket.closed).toMatchObject({ code: 4410, reason: "credential_replaced" }); expect(socket.messages).toEqual([]);
  });
  it.each(["notify", "receive"] as const)("revalidates a hibernated attachment on %s even after interruption between commit and explicit close", async (trigger) => {
    const id = await setup(), r = await recovery(id), socket = await open(id);
    type Internals = { closeSockets(code: number, device?: string): void; notify(m: unknown): void };
    const proto = ListV2Object.prototype as unknown as Internals;
    const close = proto.closeSockets, notify = proto.notify;
    await runInDurableObject(listStub(id.syncId), (instance) => {
      const p = Object.getPrototypeOf(instance) as Internals;
      p.closeSockets = () => {}; p.notify = () => {}; // model loss of all post-commit work
    });
    const next = await claimBody(r);
    try { expect((await claim(id, r, next.body)).status).toBe(200); }
    finally { await runInDurableObject(listStub(id.syncId), (instance) => { const p = Object.getPrototypeOf(instance) as Internals; p.closeSockets = close; p.notify = notify; }); }
    await evictDurableObject(listStub(id.syncId));
    if (trigger === "notify") expect((await call("PUT", `${id.path}/common`, { key: next.newKey, headers: { "If-Match": '"2"' }, body: { common: "BBBB" } })).status).toBe(200);
    else socket.ws.send("ping");
    expect(await socket.closed).toMatchObject({ code: 4410, reason: "credential_replaced" }); expect(socket.messages).toEqual([]);
  });
  it("a crash immediately after the claim commit leaves an exact durable receipt and one live credential", async () => {
    const id = await setup(), r = await recovery(id), next = await claimBody(r);
    type Internals = { closeSockets(code: number, device?: string): void };
    const original = (ListV2Object.prototype as unknown as Internals).closeSockets;
    await runInDurableObject(listStub(id.syncId), (instance) => { (Object.getPrototypeOf(instance) as Internals).closeSockets = () => { throw new Error("injected post-commit crash"); }; });
    try { expect((await claim(id, r, next.body)).status).toBe(500); }
    finally { await runInDurableObject(listStub(id.syncId), (instance) => { (Object.getPrototypeOf(instance) as Internals).closeSockets = original; }); }
    await reopen(id, r.rid);
    expect((await claim(id, r, next.body)).status).toBe(200);
    expect((await get(r)).headers.get("ETag")).toBe('"2"');
    expect((await state(id)).version).toBe(2);
    expect((await call("GET", id.path, { key: next.newKey })).status).toBe(200);
    await error(await call("GET", id.path, { key: id.key }), 403, "credential_replaced");
  });
  it("closes legacy attachments without a verifier instead of trusting their device id", async () => {
    const id = await setup(), socket = await open(id);
    await runInDurableObject(listStub(id.syncId), (_o, s) => { for (const ws of s.getWebSockets()) ws.serializeAttachment({ device: "aritz", t: Date.now() }); });
    await evictDurableObject(listStub(id.syncId));
    socket.ws.send("ping"); expect((await socket.closed).code).toBe(1008); expect(socket.messages).toEqual([]);
  });
  it("closes an unknown attachment verifier as policy failure without claiming a transfer", async () => {
    const id = await setup(), socket = await open(id);
    await runInDurableObject(listStub(id.syncId), (_o, s) => { for (const ws of s.getWebSockets()) ws.serializeAttachment({ deviceId: "aritz", credentialVerifier: key() }); });
    socket.ws.send("ping"); expect((await socket.closed).code).toBe(1008);
  });
});

describe("pairing reservation retries", () => {
  it("releases a pending answer only for the same guest and verifier; cancellation frees the replacement", async () => {
    const id = await setup(), old = await invite(id), fresh = await invite(id);
    expect((await call("POST", `${old.publicPath}/answer`, { body: old.body })).status).toBe(201);
    await error(await call("POST", `${fresh.publicPath}/answer`, { body: { ...old.body, answer: { ...old.body.answer, guest: { ...old.body.answer.guest, d: "leo" } } } }), 409, "credential_exists");
    expect((await call("POST", `${fresh.publicPath}/answer`, { body: old.body })).status).toBe(201);
    expect((await call("GET", `${old.publicPath}/offer`)).status).toBe(404);
    await reopen(id);
    expect((await call("POST", `${fresh.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: key() } } })).status).toBe(200);
    expect((await call("POST", `${fresh.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: {} } })).status).toBe(200);
    expect((await call("DELETE", fresh.privatePath, { key: id.key })).status).toBe(204);
    const active = await invite(id);
    await error(await call("POST", `${active.publicPath}/answer`, { body: old.body }), 409, "credential_exists");
  });
  it("cancelling an unapproved invitation permits the same guest verifier on a new invitation", async () => {
    const id = await setup(), old = await invite(id);
    expect((await call("POST", `${old.publicPath}/answer`, { body: old.body })).status).toBe(201);
    expect((await call("DELETE", old.privatePath, { key: id.key })).status).toBe(204);
    const fresh = await invite(id);
    expect((await call("POST", `${fresh.publicPath}/answer`, { body: old.body })).status).toBe(201);
  });
});


it("privacy: retirement marker drops sid, reservation token and reservedAt, including legacy rows", async () => {
  const rid = key(), sid = op(), token = op();
  const stub = locator(rid);
  expect(await stub.reserve(sid, token)).toBe(true);
  await stub.retire(sid, token);
  const read = () => runInDurableObject(stub, (_o, s) => s.storage.get<Record<string, unknown>>("locator"));
  expect(await read()).toEqual({ state: "retired", alarmAt: expect.any(Number), retiredUntil: expect.any(Number) });
  await runInDurableObject(stub, (_o, s) => s.storage.put("locator", { state: "retired", sid, reservationId: token, reservedAt: 17, alarmAt: Date.now() + 100000 }));
  expect(await stub.locate()).toBeNull();
  expect(await read()).toEqual({ state: "retired", alarmAt: expect.any(Number), retiredUntil: expect.any(Number) });
});


describe("automatic list retirement", () => {
  it("protects active recovery while preserving explicit list deletion", async () => {
    const id = await setup(), r = await recovery(id);
    const snap = await json(await call("GET", id.path, { key: id.key }));
    const headers = { "If-Match": `"${snap.version}"`, "X-Automatic-Retirement": "true" };
    await error(await call("DELETE", id.path, { key: id.key, headers }), 409, "recovery_active");
    expect((await get(r)).status).toBe(200);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": headers["If-Match"] } })).status).toBe(204);
  });

  it("allows automatic retirement after recovery is removed", async () => {
    const id = await setup(), r = await recovery(id);
    expect((await remove(id, r)).status).toBe(204);
    const snap = await json(await call("GET", id.path, { key: id.key }));
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${snap.version}"`, "X-Automatic-Retirement": "true" } })).status).toBe(204);
  });
});
