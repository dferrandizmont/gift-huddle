import { ListStorageBudget } from "../src/list-storage-budget";
import { describe, expect, it, vi } from "vitest";
import { env, exports } from "cloudflare:workers";
import { runInDurableObject, runDurableObjectAlarm } from "cloudflare:test";
import worker from "../src/index";
import { ListV2Object } from "../src/list-v2-object";
import { InviteV2Object } from "../src/invite-v2-object";
import * as encoding from "../src/encoding";
import type { Env } from "../src/env";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";
import {
  MAX_ENVELOPE_BYTES,
  V2_MAX_BODY_BYTES,
  V2_MAX_CREATE_BODY_BYTES,
  V2_MAX_PACKAGES_PER_WRITER,
  V2_MAX_PACKAGE_BYTES_PER_WRITER,
  V2_MAX_REGISTRY_BYTES,
  V2_MAX_SLOT_BYTES,
  V2_MAX_SLOTS,
  V2_MAX_SLOTS_PER_PUT,
  V2_WARN_SLOTS,
  V2_LEGACY_MAX_SLOTS,
  V2_LEGACY_WARN_SLOTS,
  V2_CREDENTIAL_REQUESTS,
  V2_INVITE_REQUESTS_PER_INVITE,
  V2_INVITE_REQUESTS_PER_IP,
  V2_NEW_LISTS_PER_HOUR,
} from "../src/limits";
import { canonicalJson, slotIds, validateSnapshot } from "../src/v2-contract";
import { b64u, call, envelope, json, newList, rand, randomIp } from "./helpers";

type Setup = Awaited<ReturnType<typeof setup>>;

const registry = () => ({ v: 2, l: "family", records: [] as unknown[], vouches: [] as unknown[], revocations: [] as unknown[] });
const snapshot = (slots: unknown[] = []) => ({ common: "AAAA", registry: registry(), keyPackages: [] as unknown[], slots });

// A creator credential now requires an immutable key at registration.
const creation = (deviceId: string, content = snapshot()) => ({ ...content,
  registry: { ...content.registry, records: [...content.registry.records, { d: deviceId, e: b64u(new Uint8Array(32).fill(7)) }] } });

/** Nonce, 128 KiB of ciphertext, GCM tag and signature: the fixed tail of a real slot. */
const SLOT_TAIL = 12 + 128 * 1024 + 16 + 64;
/**
 * A slot with the header layout of `protected_envelope.dart` (format 2) and an
 * opaque tail of the exact size (`SealedSlot.parse` would accept its layout).
 * `fill` varies the tail; `flags` and `revisionHigh` corrupt the header.
 */
function sealed(personId: string, writer: string, { listId = "family", tail = SLOT_TAIL, fill = 0, flags = 0, revisionHigh = 0 } = {}): string {
  const ids = [listId, personId, writer].map((s) => new TextEncoder().encode(s));
  const out = new Uint8Array(33 + ids.reduce((n, b) => n + 1 + b.length, 0) + tail);
  out.set([0x47, 0x48, 0x53, 0x02]);
  const view = new DataView(out.buffer);
  view.setUint32(8, revisionHigh);
  out[16] = flags;
  let at = 33;
  for (const b of ids) {
    out[at++] = b.length;
    out.set(b, at);
    at += b.length;
  }
  out.fill(fill, at);
  return b64u(out);
}
const slot = (n: number, deviceId = "aritz", data: string | null = sealed(`person${n}`, deviceId)) => ({ personId: `person${n}`, deviceId, data });

const setup = async (deviceId = "aritz", inviteCopy = false) => {
  const id = { ...newList(), deviceId };
  const path = `/v2/lists/${id.syncId}`;
  const res = await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: { ...creation(deviceId), deviceId, ...(inviteCopy ? { inviteCopy } : {}) } });
  expect(res.status).toBe(201);
  expect(res.headers.get("ETag")).toBe('"1"');
  return { ...id, path };
};
const digest = async (key: string) => encodeB64Url(await sha256(decodeB64Url(key, 32)!));
const listStub = (syncId: string) => {
  const ns = env.LISTS_V2.jurisdiction("eu");
  return ns.get(ns.idFromName(syncId));
};
/** Puts slot rows straight into storage, as an old server or a long-gone writer left them. */
const plant = (id: { syncId: string }, rows: [personId: string, deviceId: string][], ver = 1) =>
  runInDurableObject(listStub(id.syncId), (o, s) => {
    (o as unknown as { budget: unknown }).budget = new ListStorageBudget(s.storage);
    for (const [personId, deviceId] of rows) {
      s.storage.sql.exec("INSERT INTO slot (person, device, ver, data) VALUES (?, ?, ?, ?)", personId, deviceId, ver, sealed(personId, deviceId));
    }
    const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
    delete m.storedBytes;
    s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
  });
/** Every text the list object stores, in every table. */
const everythingStored = (syncId: string) =>
  runInDurableObject(listStub(syncId), (_o, state) => {
    const tables = state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '\\_%' ESCAPE '\\' AND name NOT LIKE 'sqlite%'").toArray();
    return tables.map(({ name }) => JSON.stringify(state.storage.sql.exec(`SELECT * FROM ${name}`).toArray())).join("\n");
  });
const put = (id: Setup, body: unknown, version: number, key = id.key) => call("PUT", id.path, { key, headers: { "If-Match": `"${version}"` }, body });

async function invite(id: Setup, guest = "nora", guestKey = b64u(rand(32)), key = id.key, host = id.deviceId) {
  const created = await call("POST", `${id.path}/invites`, { key, body: { offer: { v: 2, host: { d: host }, c: b64u(rand(32)) } } });
  expect(created.status).toBe(201);
  const { inviteId } = await json<{ inviteId: string }>(created);
  const publicPath = `/v2/invites/${inviteId}`;
  const privatePath = `${id.path}/invites/${inviteId}`;
  const answer = { v: 2, guest: { d: guest, e: b64u(rand(32)) }, vouch: {} };
  return { inviteId, publicPath, privatePath, guestKey, answer, answerBody: { answer, serviceCredentialVerifier: await digest(guestKey) } };
}
/** An invitation the guest answered and the host revealed: ready to approve. */
async function answered(id: Setup, guest = "nora") {
  const i = await invite(id, guest);
  expect((await call("POST", `${i.publicPath}/answer`, { body: i.answerBody })).status).toBe(201);
  expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
  return i;
}
const approve = (id: Setup, i: { privatePath: string }, version: number) =>
  call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": `"${version}"` }, body: { package: { c: "opaque" } } });
async function pair(id: Setup, guest = "nora", version = 1) {
  const i = await answered(id, guest);
  expect((await approve(id, i, version)).status).toBe(200);
  return i;
}

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
type State = {
  lastAccess: number;
  credentials: { deviceId: string; verifier: string | null; revoked: boolean; records: number[]; approvedBy?: string; createdAt?: number; slotsExpireAt?: number }[];
  knownRecords: string[];
  recordTimes: number[];
  approvals: number[];
};
const readState = (id: Setup) =>
  runInDurableObject(listStub(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as State);
/** Everything a retired list keeps: one state row with the bare marker. */
const MARKER = JSON.stringify([{ id: 1, data: JSON.stringify({ retired: true }) }]);
/** Rewrites the state row of a live list (to place quota stamps in the past). */
const editState = (id: Setup, edit: (m: State) => void) =>
  runInDurableObject(listStub(id.syncId), (_o, s) => {
    const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as State;
    edit(m);
    s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
  });
/** The server only erases a list from its last live credential: the others are marked revoked. */
const lastPhone = (id: Setup) => editState(id, (m) => {
  for (const a of m.credentials) if (a.deviceId !== id.deviceId) a.revoked = true;
});
const byteCapacity = (id: Setup, count: number) => editState(id, (m) => {
  while (m.credentials.length < count) m.credentials.push({ deviceId: `capacity${m.credentials.length}`, verifier: b64u(rand(32)), revoked: false, records: [], createdAt: Date.now() - 8 * DAY });
});
const capacity = (credentials: number, records: number, renew: boolean, slots = 0) => ({
  credentials: { used: credentials, warn: 48, max: 64 },
  records: { used: records, warn: 384, max: 512 },
  // One phone that never announced slotCapacity: the 1.0.5 cap.
  slots: { used: slots, warn: V2_LEGACY_WARN_SLOTS, max: V2_LEGACY_MAX_SLOTS },
  renew,
});
/** A registry holding the record declarations `from` to `to - 1`. */
const withRecords = (from: number, to: number) => {
  const s = snapshot();
  s.registry.records = Array.from({ length: to - from }, (_, n) => ({ d: `device${from + n}` }));
  return s;
};
function openSocket(id: Setup, key: string) {
  return exports.default.fetch(new Request(`https://sync.test${id.path}/ws`, { headers: { Upgrade: "websocket", "Sec-WebSocket-Protocol": `gift-huddle.v2, bearer.${key}` } }));
}

async function webPair(id: Setup, deviceId = "nora", version = 1) {
  const i = await invite(id, deviceId);
  const answer = { ...i.answer, guest: { ...i.answer.guest, d: deviceId, k: "web", p: "nora" } };
  expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, answer } })).status).toBe(201);
  expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
  expect((await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": `"${version}"` }, body: { package: { c: "opaque" }, role: "web" } })).status).toBe(200);
  // The public result is still deliverable after approval registers the web role.
  expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
  return { ...i, deviceId, guardPath: `${id.path}/guards/${deviceId}` };
}

async function guardMaterial(version = 1) {
  const guardToken = b64u(rand(32));
  const prueba = b64u(rand(32));
  const secret = b64u(rand(32));
  return { prepare: { version, tokenHash: await digest(guardToken), verifier: await digest(prueba), secret }, proof: { version, guardToken, prueba } };
}

async function guarded() {
  const id = await setup();
  const web = await webPair(id);
  const material = await guardMaterial();
  expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: material.prepare })).status).toBe(200);
  expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: { version: 1 } })).status).toBe(200);
  return { id, web, ...material };
}

/** Move only the guard's clock, keeping its persisted attempt counter. */
const allowAttempt = (id: Setup, device = "nora") => runInDurableObject(listStub(id.syncId), (_o, state) => {
  const row = state.storage.sql.exec<{ data: string }>("SELECT data FROM guard WHERE device = ?", device).one();
  const g = JSON.parse(row.data) as { nextAttemptAt: number };
  g.nextAttemptAt = 0;
  state.storage.sql.exec("UPDATE guard SET data = ? WHERE device = ?", JSON.stringify(g), device);
});

describe("web inbox slots (1.0.6, ADR 0009)", () => {
  const inbox = (id: Setup, person: string, device: string, key: string, version: number | null, data: unknown) =>
    call("PUT", `${id.path}/slots/${person}/${device}`, { key, headers: version === null ? {} : { "If-Match": `"${version}"` }, body: { data } });
  const manifest = async (id: Setup) => (await json<{ slots: { personId: string; deviceId: string; version: number }[] }>(await call("GET", id.path, { key: id.key }))).slots;

  it("lets a web write, replace and remove only its own slot, under the global ETag", async () => {
    const id = await setup();
    const web = await webPair(id);
    expect((await inbox(id, "person0", "nora", web.guestKey, null, sealed("person0", "nora"))).status).toBe(428);
    expect((await inbox(id, "person0", "nora", web.guestKey, 1, sealed("person0", "nora"))).status).toBe(412);
    const first = await inbox(id, "person0", "nora", web.guestKey, 2, sealed("person0", "nora"));
    expect(first.status).toBe(200);
    expect(await json(first)).toEqual({ version: 3 });
    expect(await manifest(id)).toEqual([{ personId: "person0", deviceId: "nora", version: 3 }]);
    // The phone reads it like any other slot.
    const read = await call("GET", `${id.path}/slots/person0/nora`, { key: id.key, headers: { "If-Match": '"3"' } });
    expect((await json(read)).data).toBe(sealed("person0", "nora"));
    expect((await inbox(id, "person0", "nora", web.guestKey, 3, sealed("person0", "nora", { fill: 1 }))).status).toBe(200);
    expect(await manifest(id)).toEqual([{ personId: "person0", deviceId: "nora", version: 4 }]);
    expect((await inbox(id, "person0", "nora", web.guestKey, 4, null)).status).toBe(200);
    expect(await manifest(id)).toEqual([]);
    // Removing what is not there changes nothing.
    const again = await inbox(id, "person0", "nora", web.guestKey, 5, null);
    expect(await json(again)).toEqual({ version: 5 });
  });

  it("refuses other writers, phones and malformed slots", async () => {
    const id = await setup();
    const web = await webPair(id);
    const other = await inbox(id, "person0", "aritz", web.guestKey, 2, sealed("person0", "aritz"));
    expect(other.status).toBe(403);
    expect(await json(other)).toEqual({ error: "forbidden_role" });
    const phone = await inbox(id, "person0", "aritz", id.key, 2, sealed("person0", "aritz"));
    expect(phone.status).toBe(403);
    expect(await json(phone)).toEqual({ error: "forbidden_role" });
    // The header must name the resource, with the exact size.
    expect((await inbox(id, "person0", "nora", web.guestKey, 2, sealed("person1", "nora"))).status).toBe(400);
    expect((await inbox(id, "person0", "nora", web.guestKey, 2, sealed("person0", "nora", { tail: SLOT_TAIL - 3 }))).status).toBe(400);
    expect((await inbox(id, "person0", "nora", web.guestKey, 2, 7)).status).toBe(400);
    const extra = await call("PUT", `${id.path}/slots/person0/nora`, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { data: null, role: "device" } });
    expect(extra.status).toBe(400);
    // A web still cannot write a full snapshot, not even with only its slot.
    expect((await put(id, snapshot([slot(0, "nora")]), 2, web.guestKey)).status).toBe(403);
    expect(await manifest(id)).toEqual([]);
  });

  it("caps a web at V2_MAX_WEB_SLOTS and counts its slots in V2_MAX_SLOTS", async () => {
    const id = await setup();
    const web = await webPair(id);
    let version = 2;
    for (let n = 0; n < 8; n++) {
      expect((await inbox(id, `person${n}`, "nora", web.guestKey, version, sealed(`person${n}`, "nora"))).status).toBe(200);
      version++;
    }
    const ninth = await inbox(id, "person8", "nora", web.guestKey, version, sealed("person8", "nora"));
    expect(ninth.status).toBe(413);
    expect(await json(ninth)).toEqual({ error: "too_many_writer_slots" });
    // Replacing one of its own still fits.
    expect((await inbox(id, "person0", "nora", web.guestKey, version, sealed("person0", "nora", { fill: 2 }))).status).toBe(200);
    version++;
    // The list cap counts the web's rows too.
    const full = await setup();
    const fullWeb = await webPair(full);
    await plant(full, Array.from({ length: V2_MAX_SLOTS }, (_, n) => [`p${n}`, `w${n % 60}`] as [string, string]));
    const over = await inbox(full, "person0", "nora", fullWeb.guestKey, 2, sealed("person0", "nora"));
    expect(over.status).toBe(413);
    expect(await json(over)).toEqual({ error: "too_many_slots" });
  });

  it("M1: with a phone that has not announced slotCapacity, the web inbox respects the 1.0.5 cap of 64", async () => {
    const id = await setup();
    const web = await webPair(id);
    // Enough phones for the bytes; none has announced slotCapacity.
    await editState(id, (m) => {
      while (m.credentials.length < 12) m.credentials.push({ deviceId: `w${m.credentials.length}`, verifier: b64u(rand(32)), revoked: false, records: [], createdAt: Date.now() - 8 * DAY });
    });
    await plant(id, Array.from({ length: V2_LEGACY_MAX_SLOTS - 1 }, (_, n) => [`p${n}`, `w${2 + (n % 10)}`] as [string, string]));
    expect((await inbox(id, "person0", "nora", web.guestKey, 2, sealed("person0", "nora"))).status).toBe(200);
    const over = await inbox(id, "person1", "nora", web.guestKey, 3, sealed("person1", "nora"));
    expect(over.status).toBe(413);
    expect(await json(over)).toEqual({ error: "too_many_slots" });
    // Once every phone announces it, the web gets the larger cap.
    await editState(id, (m) => {
      for (const a of m.credentials) (a as { slotCapacity?: number }).slotCapacity = 2;
    });
    expect((await inbox(id, "person1", "nora", web.guestKey, 3, sealed("person1", "nora"))).status).toBe(200);
  });

  it("erases a web's slots at once when it is revoked, by a phone or by itself", async () => {
    for (const self of [false, true]) {
      const id = await setup();
      expect((await put(id, snapshot([slot(0)]), 1)).status).toBe(200);
      const web = await webPair(id, "nora", 2);
      expect((await inbox(id, "person0", "nora", web.guestKey, 3, sealed("person0", "nora"))).status).toBe(200);
      expect((await inbox(id, "person1", "nora", web.guestKey, 4, sealed("person1", "nora"))).status).toBe(200);
      const revoked = await call("POST", `${id.path}/revoke`, { key: self ? web.guestKey : id.key, body: { deviceId: "nora" } });
      expect(revoked.status).toBe(200);
      expect(await manifest(id)).toEqual([{ personId: "person0", deviceId: "aritz", version: 2 }]);
      const state = await readState(id);
      expect(state.credentials.find((c) => c.deviceId === "nora")!.slotsExpireAt).toBeUndefined();
      expect((await everythingStored(id.syncId)).includes(sealed("person1", "nora"))).toBe(false);
    }
  });
});

describe("web credentials and common-only writes", () => {
  const forbidden = [
    ["PUT", "", snapshot()],
    ["PUT", "", { ...snapshot(), registry: { ...registry(), records: [{ d: "leo" }] } }],
    ["PUT", "", { ...snapshot(), keyPackages: [{ c: "replace" }] }],
    ["PUT", "", snapshot([slot(0, "nora")])],
    ["PUT", "", snapshot([slot(0, "aritz", null)])],
    ["DELETE", "", undefined],
    ["POST", "/invites", { offer: { v: 2 } }],
    ["GET", "/invites/INVITE", undefined],
    ["DELETE", "/invites/INVITE", undefined],
    ["POST", "/invites/INVITE/reveal", { reveal: {} }],
    ["POST", "/invites/INVITE/approve", { package: {} }],
    ["POST", "/revoke", { deviceId: "aritz" }],
    ["POST", "/guards/nora/resume", {}],
    ["PUT", "/guards/aritz/prepare", {}],
    ["POST", "/guards/aritz/commit", { version: 1 }],
    ["POST", "/guards/aritz/cancel", { version: 1 }],
    ["POST", "/guards/aritz/resume", {}],
  ] as const;

  it.each(forbidden)("denies the web attack %s %s", async (method, suffix, body) => {
    const id = await setup();
    const web = await webPair(id);
    const path = `${id.path}${suffix.replace("INVITE", web.inviteId)}`;
    const r = await call(method, path, { key: web.guestKey, body, headers: { "If-Match": '"2"' } });
    expect(r.status).toBe(403);
    expect(await json(r)).toEqual({ error: "forbidden_role" });
    expect((await json(await call("GET", id.path, { key: id.key }))).version).toBe(2);
  });

  it("allows web snapshot/slot reads, sockets and self-revocation", async () => {
    const id = await setup();
    expect((await put(id, snapshot([slot(0)]), 1)).status).toBe(200);
    const web = await webPair(id, "nora", 2);
    const r = await call("GET", id.path, { key: web.guestKey });
    expect(r.status).toBe(200);
    expect((await json<{ devices: unknown[] }>(r)).devices).toEqual([
      { deviceId: "aritz", revoked: false, role: "device" },
      { deviceId: "nora", revoked: false, role: "web", approvedBy: "aritz" },
    ]);
    expect((await call("GET", `${id.path}/slots/person0/aritz`, { key: web.guestKey, headers: { "If-Match": '"3"' } })).status).toBe(200);
    const socket = await openSocket(id, web.guestKey);
    expect(socket.status).toBe(101);
    socket.webSocket!.accept(); socket.webSocket!.close();
    expect((await call("POST", `${id.path}/revoke`, { key: web.guestKey, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(401);
  });

  it("notifies an open browser and a phone after either role writes", async () => {
    const id = await setup();
    const web = await webPair(id);
    const browserResponse = await exports.default.fetch(new Request(`https://sync.test${id.path}/ws`, {
      headers: { Upgrade: "websocket", Origin: "https://web.gifthuddle.app", "Sec-WebSocket-Protocol": `gift-huddle.v2, bearer.${web.guestKey}` },
    }));
    expect(browserResponse.status).toBe(101);
    expect(browserResponse.headers.get("Sec-WebSocket-Protocol")).toBe("gift-huddle.v2");
    const browser = browserResponse.webSocket!;
    const phone = (await openSocket(id, id.key)).webSocket!;
    browser.accept();
    phone.accept();
    const next = (ws: WebSocket) => new Promise<string>((resolve) => ws.addEventListener("message", (event) => resolve(String(event.data)), { once: true }));
    try {
      let received = Promise.all([next(browser), next(phone)]);
      expect((await put(id, snapshot(), 2)).status).toBe(200);
      expect(await received).toEqual(Array(2).fill(JSON.stringify({ type: "version", version: 3 })));
      received = Promise.all([next(browser), next(phone)]);
      expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"3"' }, body: { common: "BBBB" } })).status).toBe(200);
      expect(await received).toEqual(Array(2).fill(JSON.stringify({ type: "version", version: 4 })));
    } finally {
      browser.close();
      phone.close();
    }
  });

  it("cannot recreate an existing list or promote the web with extra role fields", async () => {
    const id = await setup();
    const web = await webPair(id);
    const before = await json(await call("GET", id.path, { key: id.key }));
    for (const version of [0, 2]) {
      const r = await put(id, { ...snapshot([slot(0, "nora")]), deviceId: "nora", role: "device", devices: [{ deviceId: "nora", role: "device" }] }, version, web.guestKey);
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_role" });
    }
    for (const extra of [{ role: "device" }, { devices: [{ deviceId: "nora", role: "device" }] }]) {
      const r = await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { common: "BBBB", ...extra } });
      expect(r.status).toBe(400);
    }
    // Even a device's full snapshot cannot change the service role.
    expect((await put(id, { ...snapshot(), role: "device", devices: [{ deviceId: "nora", role: "device" }] }, 2)).status).toBe(200);
    expect(await json(await call("GET", id.path, { key: web.guestKey }))).toEqual({ ...before, registry: registry(), version: 3 });
    expect((await put(id, snapshot(), 3, web.guestKey)).status).toBe(403);
  });

  it("orders concurrent common and full PUTs against the same global ETag", async () => {
    for (const commonFirst of [true, false]) {
      const id = await setup();
      const original = { ...snapshot([slot(0)]), keyPackages: [{ v: 3, from: "aritz", c: "keep" }] };
      expect((await put(id, original, 1)).status).toBe(200);
      const web = await webPair(id, "nora", 2);
      const before = await json(await call("GET", id.path, { key: id.key }));
      const full = { ...snapshot([slot(1)]), common: "CCCC", registry: { ...registry(), records: [{ d: "aritz" }] }, keyPackages: [{ v: 3, from: "aritz", c: "new" }] };
      const commonWrite = () => call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"3"' }, body: { common: "BBBB" } });
      const fullWrite = () => put(id, full, 3);
      const writes = commonFirst ? [commonWrite, fullWrite] : [fullWrite, commonWrite];
      const responses = await Promise.all(writes.map((write) => write()));
      expect(responses.map((r) => r.status).sort()).toEqual([200, 412]);
      for (const r of responses) expect(r.headers.get("ETag")).toBe('"4"');
      const commonWon = responses[commonFirst ? 0 : 1]!.status === 200;
      const after = await json(await call("GET", id.path, { key: id.key }));
      expect(after).toEqual(commonWon ? { ...before, common: "BBBB", version: 4 } : {
        ...before, common: full.common, registry: full.registry, keyPackages: full.keyPackages, version: 4,
        slots: [...before.slots as unknown[], { personId: "person1", deviceId: "aritz", version: 4 }],
        capacity: capacity(2, 2, false, 2),
      });
      expect((await json(await call("GET", `${id.path}/slots/person0/aritz`, { key: id.key, headers: { "If-Match": '"4"' } }))).data).toBe(slot(0).data);
    }
  });

  it.each([true, false])("rejects approval role mismatch (web record: %s)", async (webRecord) => {
    const id = await setup();
    const i = await invite(id);
    const answer = { ...i.answer, guest: { ...i.answer.guest, d: "nora", ...(webRecord ? { k: "web" } : {}) } };
    expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, answer } })).status).toBe(201);
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
    const r = await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: {}, ...(webRecord ? {} : { role: "web" }) } });
    expect(r.status).toBe(400); expect(await json(r)).toEqual({ error: "role_mismatch" });
  });

  it("rejects unknown kinds in answers, offers and registry records", async () => {
    const id = await setup();
    const i = await invite(id);
    for (const k of ["device", "other", null, 1]) {
      expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, answer: { ...i.answer, guest: { ...i.answer.guest, d: "nora", k } } } })).status).toBe(400);
      expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer: { v: 2, host: { d: "aritz", k }, c: b64u(rand(32)) } } })).status).toBe(400);
      expect((await put(id, { ...snapshot(), registry: { ...registry(), records: [{ d: "nora", k }] } }, 1)).status).toBe(400);
    }
  });

  it("reads an actual pre-role state row as live device credentials", async () => {
    const id = await setup();
    const i = await pair(id);
    await runInDurableObject(listStub(id.syncId), (_o, state) => {
      const m = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as { credentials: { role?: string }[] };
      for (const c of m.credentials) delete c.role;
      state.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
    });
    const r = await call("GET", id.path, { key: i.guestKey });
    expect(r.status).toBe(200);
    expect((await json<{ devices: { role: string }[] }>(r)).devices.map((d) => d.role)).toEqual(["device", "device"]);
    expect((await put(id, snapshot(), 2, i.guestKey)).status).toBe(200);
  });

  it("updates only common with a global ETag and notifies the web socket", async () => {
    const id = await setup();
    const original = { ...snapshot([slot(0)]), registry: { ...registry(), records: [{ d: "aritz" }] }, keyPackages: [{ v: 3, from: "aritz", c: "keep" }] };
    expect((await put(id, original, 1)).status).toBe(200);
    const web = await webPair(id, "nora", 2);
    const before = await json(await call("GET", id.path, { key: id.key }));
    const path = `${id.path}/common`;
    expect((await call("PUT", path, { key: web.guestKey, body: { common: "BBBB" } })).status).toBe(428);
    const stale = await call("PUT", path, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { common: "BBBB" } });
    expect(stale.status).toBe(412); expect(stale.headers.get("ETag")).toBe('"3"');
    for (const extra of ["registry", "keyPackages", "slots", "deviceId", "other"]) {
      expect((await call("PUT", path, { key: web.guestKey, headers: { "If-Match": '"3"' }, body: { common: "BBBB", [extra]: [] } })).status).toBe(400);
    }
    const socket = (await openSocket(id, web.guestKey)).webSocket!;
    socket.accept();
    const message = new Promise<string>((resolve) => socket.addEventListener("message", (event) => resolve(event.data as string), { once: true }));
    const write = await call("PUT", path, { key: web.guestKey, headers: { "If-Match": '"3"' }, body: { common: "BBBB" } });
    expect(write.status).toBe(200); expect(write.headers.get("ETag")).toBe('"4"'); expect(await json(write)).toEqual({ version: 4 });
    expect(JSON.parse(await message)).toEqual({ type: "version", version: 4 }); socket.close();
    expect(await json(await call("GET", id.path, { key: id.key }))).toEqual({ ...before, common: "BBBB", version: 4 });
    expect((await json(await call("GET", `${id.path}/slots/person0/aritz`, { key: id.key, headers: { "If-Match": '"4"' } }))).data).toBe(slot(0).data);
    // Device role can use the same endpoint too.
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"4"' }, body: { common: "CCCC" } })).status).toBe(200);
    for (const common of ["bad=", "a", "", 42]) expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"5"' }, body: { common } })).status).toBe(400);
    expect((await call("PUT", path, { key: id.key, headers: { "If-Match": '"5"' }, body: { common: b64u(new Uint8Array(MAX_ENVELOPE_BYTES + 1)) } })).status).toBe(413);
  });

  it("shares the per-credential write budget with full PUTs", async () => {
    const id = await setup();
    for (let v = 1; v <= 30; v++) expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": `"${v}"` }, body: { common: "BBBB" } })).status).toBe(200);
    expect((await put(id, snapshot(), 31)).status).toBe(429);
  });

  it("shares the list write budget across credentials and both PUT routes", async () => {
    const id = await setup();
    const nora = await pair(id);
    const leo = await pair(id, "leo", 2);
    // Each pairing spent three list mutations (create invite, reveal, approve).
    for (let n = 0; n < 54; n++) {
      const key = n < 27 ? nora.guestKey : leo.guestKey;
      expect((await call("PUT", `${id.path}/common`, { key, headers: { "If-Match": `"${n + 3}"` }, body: { common: "BBBB" } })).status).toBe(200);
    }
    expect((await put(id, snapshot(), 57)).status).toBe(429);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"57"' }, body: { common: "CCCC" } })).status).toBe(429);
  });
});

describe("public offer pending opt-in", () => {
  it.each(["", "?pending=204", "?pending=200", "?pending=0204", "?pending="])("preserves offer and absence semantics for %s", async (query) => {
    const pending = query === "?pending=204";
    const checkAbsent = async (path: string) => {
      const response = await call("GET", `${path}/offer${query}`);
      expect(response.status).toBe(pending ? 204 : 404);
      expect(response.headers.get("Cache-Control")).toBe("no-store, no-transform");
      if (pending) {
        expect(response.body).toBeNull();
        expect(await response.text()).toBe("");
        expect(response.headers.get("Content-Type")).toBeNull();
      } else expect(await json(response)).toEqual({ error: "not_found" });
    };
    // No locator at all.
    await checkAbsent(`/v2/invites/${b64u(rand(16))}`);
    const id = await setup();
    const i = await invite(id);
    const original = await json(await call("GET", `${i.publicPath}/offer`));
    const available = await call("GET", `${i.publicPath}/offer${query}`);
    expect(available.status).toBe(200);
    expect(await json(available)).toEqual(original);
    expect((await call("DELETE", i.privatePath, { key: id.key })).status).toBe(204);
    // Cancellation retains a routing stub: the list, not the locator, says absent.
    const ns = env.INVITES_V2.jurisdiction("eu");
    expect(await ns.get(ns.idFromName(i.inviteId)).locate()).toBe(id.syncId);
    await checkAbsent(i.publicPath);
    // The opt-in does not change any other public invitation route.
    expect((await call("GET", `${i.publicPath}/result${query}`)).status).toBe(404);
  });

  it.each(["", "?pending=204"])("preserves revoked-Bearer and Origin errors for %s", async (query) => {
    const id = await setup();
    const nora = await pair(id);
    const i = await invite(id, "leo");
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    const unauthorized = await call("GET", `${i.publicPath}/offer${query}`, { key: nora.guestKey });
    expect(unauthorized.status).toBe(401);
    expect(await json(unauthorized)).toEqual({ error: "unauthorized" });
    const forbidden = await call("GET", `${i.publicPath}/offer${query}`, { headers: { Origin: "https://untrusted.example" } });
    expect(forbidden.status).toBe(403);
    expect(await json(forbidden)).toEqual({ error: "forbidden" });
  });

  it("keeps the same invitation budget across both query forms and does not count absent offers", async () => {
    const id = await setup();
    const i = await invite(id);
    expect((await call("DELETE", i.privatePath, { key: id.key })).status).toBe(204);
    for (let n = 0; n <= V2_INVITE_REQUESTS_PER_INVITE; n++) {
      expect((await call("GET", `${i.publicPath}/offer?pending=204`)).status).toBe(204);
    }
    const offer = { v: 2, host: { d: id.deviceId }, c: b64u(rand(32)) };
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { inviteId: i.inviteId, offer } })).status).toBe(201);
    for (let n = 0; n < V2_INVITE_REQUESTS_PER_INVITE; n++) {
      expect((await call("GET", `${i.publicPath}/offer${n % 2 ? "?pending=204" : ""}`)).status).toBe(200);
    }
    for (const query of ["", "?pending=204"]) {
      const response = await call("GET", `${i.publicPath}/offer${query}`);
      expect(response.status).toBe(429);
      expect(await json(response)).toEqual({ error: "rate_limited" });
      expect(response.headers.get("Retry-After")).toBeTruthy();
    }
  });

  it.each(["IP_LIMITER", "INVITE_IP_LIMITER", "INVITE_IP48_LIMITER"] as const)("preserves %s admission and Retry-After with pending=204", async (binding) => {
    const limits = {
      IP_LIMITER: { limit: vi.fn(async () => ({ success: binding !== "IP_LIMITER" })) },
      INVITE_IP_LIMITER: { limit: vi.fn(async () => ({ success: binding !== "INVITE_IP_LIMITER" })) },
      INVITE_IP48_LIMITER: { limit: vi.fn(async () => ({ success: binding !== "INVITE_IP48_LIMITER" })) },
    };
    const fake = { ...env, ...limits } as Env;
    const response = await worker.fetch(new Request(`https://sync.test/v2/invites/${b64u(rand(16))}/offer?pending=204`), fake);
    expect(response.status).toBe(429);
    expect(await json(response)).toEqual({ error: "rate_limited" });
    expect(response.headers.get("Retry-After")).toBe("60");
    expect(limits[binding].limit).toHaveBeenCalledOnce();
  });

  it("preserves discovery failures as 500 with pending=204", async () => {
    const ns = { jurisdiction: () => { throw new Error("unavailable"); } };
    const fake = { ...env, INVITES_V2: ns } as unknown as Env;
    const response = await worker.fetch(new Request(`https://sync.test/v2/invites/${b64u(rand(16))}/offer?pending=204`), fake);
    expect(response.status).toBe(500);
    expect(await json(response)).toEqual({ error: "internal" });
  });
});

describe("global client invitation reservations", () => {
  it("never overwrites another list, and retries are idempotent", async () => {
    const a = await setup(); const b = await setup();
    const inviteId = b64u(rand(16));
    const offer = { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) };
    const body = { inviteId, offer, guestPerson: "nora" };
    const create = (id: Setup, payload = body) => call("POST", `${id.path}/invites`, { key: id.key, body: payload });
    const first = await create(a); expect(first.status).toBe(201);
    const firstBody = await json(first);
    const again = await create(a); expect(again.status).toBe(201); expect(await json(again)).toEqual(firstBody);
    for (const [id, payload] of [[b, body], [a, { ...body, guestPerson: "leo" }], [a, { ...body, offer: { ...offer, c: b64u(rand(32)) } }]] as const) {
      const r = await create(id, payload); expect(r.status).toBe(409); expect(await json(r)).toEqual({ error: "invite_exists" });
    }
    expect(await json(await call("GET", `/v2/invites/${inviteId}/offer`))).toEqual({ offer, guestPerson: "nora", expiresAt: firstBody.expiresAt });
    const answer = { v: 2, guest: { d: "nora", e: b64u(rand(32)), k: "web", p: "leo" }, vouch: {} };
    const answerBody = { answer, serviceCredentialVerifier: await digest(b64u(rand(32))) };
    const wrong = await call("POST", `/v2/invites/${inviteId}/answer`, { body: answerBody });
    expect(wrong.status).toBe(400); expect(await json(wrong)).toEqual({ error: "person_mismatch" });
    expect((await call("POST", `/v2/invites/${inviteId}/answer`, { body: { ...answerBody, answer: { ...answer, guest: { ...answer.guest, p: "nora" } } } })).status).toBe(201);
    const hostView = await call("GET", `${a.path}/invites/${inviteId}`, { key: a.key });
    expect(hostView.status).toBe(200);
    expect((await json<{ answer: { guest: { p?: string | null } } }>(hostView)).answer.guest.p).toBe("nora");
    expect((await call("DELETE", `${a.path}/invites/${inviteId}`, { key: a.key })).status).toBe(204);
    expect((await create(b)).status).toBe(201);
  });

  it("QA 1.0.6 m1: an answer without a person reaches the host; another person is still rejected", async () => {
    for (const absent of ["missing", "null"] as const) {
      const a = await setup();
      const inviteId = b64u(rand(16));
      const offer = { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) };
      expect((await call("POST", `${a.path}/invites`, { key: a.key, body: { inviteId, offer, guestPerson: "nora" } })).status).toBe(201);
      const guest: Record<string, unknown> = { d: "movil-105", e: b64u(rand(32)) };
      if (absent === "null") guest.p = null; // A 1.0.5 guest sends "p": null.
      const verifier = await digest(b64u(rand(32)));
      const answerBody = (g: Record<string, unknown>) => ({ answer: { v: 2, guest: g, vouch: {} }, serviceCredentialVerifier: verifier });
      const other = await call("POST", `/v2/invites/${inviteId}/answer`, { body: answerBody({ ...guest, p: "leo" }) });
      expect(other.status).toBe(400); expect(await json(other)).toEqual({ error: "person_mismatch" });
      expect((await call("POST", `/v2/invites/${inviteId}/answer`, { body: answerBody(guest) })).status).toBe(201);
      const hostView = await call("GET", `${a.path}/invites/${inviteId}`, { key: a.key });
      expect(hostView.status).toBe(200);
      const received = (await json<{ answer: { guest: { d: string; p?: string | null } } }>(hostView)).answer;
      expect(received.guest.d).toBe("movil-105");
      expect(received.guest.p ?? null).toBeNull();
      expect((await call("DELETE", `${a.path}/invites/${inviteId}`, { key: a.key })).status).toBe(204);
    }
  });

  it("orders simultaneous reservations from two lists with exactly one winner", async () => {
    const a = await setup(); const b = await setup();
    const inviteId = b64u(rand(16));
    const responses = await Promise.all([a, b].map((id) => call("POST", `${id.path}/invites`, { key: id.key, body: { inviteId, offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } } })));
    expect(responses.map((r) => r.status).sort()).toEqual([201, 409]);
    const winner = responses[0]!.status === 201 ? a : b;
    expect((await call("GET", `${winner.path}/invites/${inviteId}`, { key: winner.key })).status).toBe(200);
  });

  it("releases an expired reservation even before its alarm", async () => {
    const a = await setup(); const b = await setup();
    const inviteId = b64u(rand(16));
    const body = { inviteId, offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } };
    expect((await call("POST", `${a.path}/invites`, { key: a.key, body })).status).toBe(201);
    const ns = env.INVITES_V2.jurisdiction("eu");
    await runInDurableObject(ns.get(ns.idFromName(inviteId)), async (_o, state) => {
      const r = await state.storage.get<Record<string, unknown>>("locator");
      await state.storage.put("locator", { ...r, expiresAt: Date.now() - 1 });
    });
    expect((await call("POST", `${b.path}/invites`, { key: b.key, body })).status).toBe(201);
    const publicOffer = await json(await call("GET", `/v2/invites/${inviteId}/offer`));
    expect(publicOffer.guestPerson).toBeNull();
    // Cleanup of the old list cannot remove the newer reservation.
    expect((await call("DELETE", `${a.path}/invites/${inviteId}`, { key: a.key })).status).toBe(204);
    expect((await call("GET", `/v2/invites/${inviteId}/offer`)).status).toBe(200);
  });

  it("validates canonical invite ids and person ids", async () => {
    const id = await setup();
    const offer = { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) };
    for (const inviteId of ["bad", `${b64u(rand(16))}=`, b64u(rand(15)), null]) expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer, inviteId } })).status).toBe(400);
    for (const guestPerson of ["", "a/b", "n".repeat(129), null]) expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer, guestPerson } })).status).toBe(400);
  });

  it("reuses an expired id in the same list before either alarm and keeps the new exchange alive", async () => {
    const id = await setup();
    const i = await invite(id);
    const ns = env.INVITES_V2.jurisdiction("eu");
    const locator = ns.get(ns.idFromName(i.inviteId));
    const expired = Date.now() - 1;
    await runInDurableObject(locator, async (_o, state) => {
      const old = await state.storage.get<Record<string, unknown>>("locator");
      await state.storage.put("locator", { ...old, expiresAt: expired });
      await state.storage.setAlarm(Date.now() + DAY);
    });
    await runInDurableObject(listStub(id.syncId), async (_o, state) => {
      const row = state.storage.sql.exec<{ data: string }>("SELECT data FROM invite WHERE id = ?", i.inviteId).one();
      state.storage.sql.exec("UPDATE invite SET expires_at = ?, data = ? WHERE id = ?", expired, JSON.stringify({ ...JSON.parse(row.data), expiresAt: expired }), i.inviteId);
      await state.storage.setAlarm(Date.now() + DAY);
    });
    const offer = { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) };
    const created = await call("POST", `${id.path}/invites`, { key: id.key, body: { inviteId: i.inviteId, offer, guestPerson: "nora" } });
    expect(created.status).toBe(201);
    const { expiresAt } = await json<{ expiresAt: number }>(created);
    expect(expiresAt).toBeGreaterThan(Date.now());
    expect(await json(await call("GET", `${i.publicPath}/offer`))).toEqual({ offer, guestPerson: "nora", expiresAt });
    expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, answer: { ...i.answer, guest: { ...i.answer.guest, d: "nora", p: "nora" } } } })).status).toBe(201);
    for (const stub of [listStub(id.syncId), locator]) {
      await runInDurableObject(stub, (_o, state) => state.storage.setAlarm(Date.now() + DAY));
      expect(await runDurableObjectAlarm(stub)).toBe(true);
      // The list may wake earlier to erase an expired rate window.
      expect(await runInDurableObject(stub, (_o, state) => state.storage.getAlarm())).toBeLessThanOrEqual(expiresAt);
    }
    const retained = await json(await call("GET", i.privatePath, { key: id.key }));
    expect(retained.offer).toEqual(offer);
    expect(retained.answer).toEqual({ ...i.answer, guest: { ...i.answer.guest, d: "nora", p: "nora" } });
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
    expect((await approve(id, i, 1)).status).toBe(200);
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
  });

  it("limits the revoked-Bearer 401 guarantee to the released locator before reuse", async () => {
    const id = await setup();
    const nora = await pair(id);
    const i = await invite(id, "leo", b64u(rand(32)), nora.guestKey, "nora");
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("GET", `${i.publicPath}/offer`, { key: nora.guestKey })).status).toBe(401);
    const other = await setup();
    const offer = { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) };
    expect((await call("POST", `${other.path}/invites`, { key: other.key, body: { inviteId: i.inviteId, offer } })).status).toBe(201);
    const reused = await call("GET", `${i.publicPath}/offer`, { key: nora.guestKey });
    expect(reused.status).toBe(200);
    expect((await json(reused)).offer).toEqual(offer);
    expect((await call("GET", id.path, { key: nora.guestKey })).status).toBe(401);
    expect((await call("GET", other.path, { key: nora.guestKey })).status).toBe(401);
  });

  it.each(["cancel", "revoke", "delete", "expiry"] as const)("recovers a failed %s release from SQLite after reconstruction", async (action) => {
    const id = await setup();
    const nora = await pair(id);
    const i = await invite(id, "leo", b64u(rand(32)), nora.guestKey, "nora");
    const ns = env.INVITES_V2.jurisdiction("eu");
    const locator = ns.get(ns.idFromName(i.inviteId));
    if (action === "delete") await lastPhone(id);
    const release = InviteV2Object.prototype.release;
    await runInDurableObject(locator, (instance) => {
      Object.getPrototypeOf(instance).release = async () => { throw new Error("injected release failure"); };
    });
    try {
      let failed: Response;
      if (action === "cancel") failed = await call("DELETE", i.privatePath, { key: nora.guestKey });
      else if (action === "revoke") failed = await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } });
      else if (action === "delete") failed = await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } });
      else {
        await editState(id, (m) => { m.lastAccess = Date.now() - 401 * DAY; });
        failed = await call("GET", id.path, { key: id.key });
      }
      expect(failed.status).toBe(action === "expiry" ? 404 : 500);
      const stored = await everythingStored(id.syncId);
      expect(stored).toContain(i.inviteId);
      if (action === "delete" || action === "expiry") expect(stored).toContain("retiring");
      if (action === "revoke") expect((await call("GET", id.path, { key: nora.guestKey })).status).toBe(401);
      const other = await setup();
      const body = { inviteId: i.inviteId, offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } };
      expect((await call("POST", `${other.path}/invites`, { key: other.key, body })).status).toBe(409);
      await runInDurableObject(locator, (instance) => { Object.getPrototypeOf(instance).release = release; });
      await runInDurableObject(listStub(id.syncId), async (_old, state) => {
        const recreated = new ListV2Object(state, env);
        await recreated.alarm();
      });
      const recovered = await everythingStored(id.syncId);
      expect(recovered).not.toContain(i.inviteId);
      if (action === "delete" || action === "expiry") expect(recovered).toBe(MARKER);
      expect((await call("POST", `${other.path}/invites`, { key: other.key, body })).status).toBe(201);
      expect((await call("GET", `${i.publicPath}/offer`)).status).toBe(200);
    } finally {
      await runInDurableObject(locator, (instance) => { Object.getPrototypeOf(instance).release = release; });
    }
  });

  it("retries a lost release acknowledgement without erasing a later reservation with identical list and expiry", async () => {
    const id = await setup();
    const i = await invite(id);
    const ns = env.INVITES_V2.jurisdiction("eu");
    const locator = ns.get(ns.idFromName(i.inviteId));
    const old = await runInDurableObject(locator, (_o, state) => state.storage.get<{ syncId: string; owner: string; offerHash: string; guestPerson: string | null; expiresAt: number; reservationId: string }>("locator"));
    await runInDurableObject(locator, (instance) => {
      const prototype = Object.getPrototypeOf(instance) as InviteV2Object;
      const original = prototype.release;
      prototype.release = async function (...args) {
        await original.call(this, ...args);
        prototype.release = original;
        throw new Error("injected lost acknowledgement");
      };
    });
    expect((await call("DELETE", i.privatePath, { key: id.key })).status).toBe(500);
    const reservationId = b64u(rand(16));
    expect((await locator.reserve({ ...old!, reservationId })).ok).toBe(true);
    // This repeated request recovers the queued release before returning 404.
    expect((await call("DELETE", i.privatePath, { key: id.key })).status).toBe(404);
    expect((await everythingStored(id.syncId))).not.toContain(i.inviteId);
    const retained = await runInDurableObject(locator, (_o, state) => state.storage.get<Record<string, unknown>>("locator"));
    expect(retained).toEqual({ ...old, reservationId });
    expect((await locator.reserve({ ...old!, syncId: b64u(rand(16)), reservationId: b64u(rand(16)) })).ok).toBe(false);
  });
});

describe("pending release queue", () => {
  const locatorOf = (inviteId: string) => {
    const ns = env.INVITES_V2.jurisdiction("eu");
    return ns.get(ns.idFromName(inviteId));
  };
  /** Makes `release` throw (for one locator, or for all) until the returned restore runs. */
  const failReleases = async (probe: ReturnType<typeof locatorOf>, only = false) => {
    const original = InviteV2Object.prototype.release;
    const failId = probe.id;
    await runInDurableObject(probe, (instance) => {
      const prototype = Object.getPrototypeOf(instance) as InviteV2Object;
      prototype.release = async function (this: InviteV2Object, ...args: Parameters<InviteV2Object["release"]>) {
        if (!only || (this as unknown as { ctx: DurableObjectState }).ctx.id.equals(failId)) throw new Error("injected release failure");
        return original.apply(this, args);
      };
    });
    return () => runInDurableObject(probe, (instance) => { Object.getPrototypeOf(instance).release = original; });
  };
  const expireQueue = (id: Setup) =>
    runInDurableObject(listStub(id.syncId), (_o, state) => {
      for (const row of state.storage.sql.exec<{ data: string }>("SELECT data FROM pending_release").toArray()) {
        state.storage.sql.exec("UPDATE pending_release SET data = ? WHERE data = ?", JSON.stringify({ ...JSON.parse(row.data), expiresAt: Date.now() - 1 }), row.data);
      }
    });
  const queued = (id: Setup) =>
    runInDurableObject(listStub(id.syncId), (_o, state) =>
      state.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pending_release'").toArray().length
        ? state.storage.sql.exec("SELECT data FROM pending_release").toArray().length : 0);
  const alarm = (id: Setup) => runInDurableObject(listStub(id.syncId), async (_old, state) => { await new ListV2Object(state, env).alarm(); });
  const offerBody = (inviteId?: string) => ({ inviteId, offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } });

  it("never lets a pending release free a recreated invitation", async () => {
    const id = await setup();
    const other = await setup();
    const inviteId = b64u(rand(16));
    const body = offerBody(inviteId);
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body })).status).toBe(201);
    const locator = locatorOf(inviteId);
    const restore = await failReleases(locator, true);
    try {
      expect((await call("DELETE", `${id.path}/invites/${inviteId}`, { key: id.key })).status).toBe(500);
      // Same id, owner and offer while the release keeps failing: refused, not adopted.
      const again = await call("POST", `${id.path}/invites`, { key: id.key, body });
      expect(again.status).toBe(409);
      expect((await json(again)).error).toBe("invite_exists");
      expect((await call("GET", `${id.path}/invites/${inviteId}`, { key: id.key })).status).toBe(404);
      // Another list cannot take it either.
      expect((await call("POST", `${other.path}/invites`, { key: other.key, body })).status).toBe(409);
    } finally {
      await restore();
    }
    // Once the release is confirmed, a fresh reservation (new identity) is created and sticks.
    const before = await runInDurableObject(locator, (_o, state) => state.storage.get<{ reservationId?: string }>("locator"));
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body })).status).toBe(201);
    const after = await runInDurableObject(locator, (_o, state) => state.storage.get<{ reservationId?: string }>("locator"));
    expect(after!.reservationId).not.toBe(before!.reservationId);
    expect(await queued(id)).toBe(0);
    await alarm(id);
    expect((await call("GET", `/v2/invites/${inviteId}/offer`)).status).toBe(200);
    expect((await call("POST", `${other.path}/invites`, { key: other.key, body })).status).toBe(409);
  });

  it("keeps draining the other releases when one fails", async () => {
    const id = await setup();
    const a = await invite(id);
    const b = await invite(id);
    const c = await invite(id);
    const restore = await failReleases(locatorOf(a.inviteId), true);
    try {
      expect((await call("DELETE", a.privatePath, { key: id.key })).status).toBe(500);
      // The failing one does not stop the rest from being released (the request
      // still reports 500 while anything remains pending).
      expect((await call("DELETE", b.privatePath, { key: id.key })).status).toBe(500);
      expect((await call("DELETE", c.privatePath, { key: id.key })).status).toBe(500);
      expect(await queued(id)).toBe(1);
      expect((await call("GET", `${b.publicPath}/offer`)).status).toBe(404);
      expect((await call("GET", `${c.publicPath}/offer`)).status).toBe(404);
      expect((await call("POST", `${id.path}/invites`, { key: id.key, body: offerBody(a.inviteId) })).status).toBe(409);
    } finally {
      await restore();
    }
  });

  it("drops pending releases whose reservation has expired", async () => {
    const id = await setup();
    const i = await invite(id);
    const restore = await failReleases(locatorOf(i.inviteId));
    try {
      expect((await call("DELETE", i.privatePath, { key: id.key })).status).toBe(500);
      expect(await queued(id)).toBe(1);
      await expireQueue(id);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      expect(await queued(id)).toBe(0);
      expect(await everythingStored(id.syncId)).not.toContain("pending_release");
    } finally {
      await restore();
    }
  });

  it("answers 429 with Retry-After when the queue is full", async () => {
    const id = await setup();
    const ids: string[] = [];
    for (let n = 0; n < 10; n++) ids.push((await invite(id)).inviteId);
    const restore = await failReleases(locatorOf(ids[0]!));
    try {
      for (const inviteId of ids.slice(0, 9)) expect((await call("DELETE", `${id.path}/invites/${inviteId}`, { key: id.key })).status).toBe(500);
      const last = await invite(id);
      const spare = await invite(id);
      expect((await call("DELETE", last.privatePath, { key: id.key })).status).toBe(500);
      expect(await queued(id)).toBe(10);
      const refusedCancel = await call("DELETE", spare.privatePath, { key: id.key });
      expect(refusedCancel.status).toBe(429);
      expect(refusedCancel.headers.get("Retry-After")).toBe("60");
      const refusedCreate = await call("POST", `${id.path}/invites`, { key: id.key, body: offerBody() });
      expect(refusedCreate.status).toBe(429);
      expect(refusedCreate.headers.get("Retry-After")).toBe("60");
      // The refused cancellation changed nothing: the invitation is still there.
      expect((await call("GET", spare.privatePath, { key: id.key })).status).toBe(200);
      await expireQueue(id);
      expect((await call("POST", `${id.path}/invites`, { key: id.key, body: offerBody() })).status).toBe(201);
      expect(await queued(id)).toBe(0);
    } finally {
      await restore();
    }
  }, 20_000);

  it("leaves a retired list with only the bare marker once persistent failures expire", async () => {
    const id = await setup();
    const a = await invite(id);
    const b = await invite(id);
    const restore = await failReleases(locatorOf(a.inviteId));
    try {
      expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(500);
      const stored = await everythingStored(id.syncId);
      expect(stored).toContain("retiring");
      expect(stored).toContain(a.inviteId);
      expect(stored).toContain(b.inviteId);
      // Still failing and not yet expired: the retry keeps the queue.
      await alarm(id);
      expect(await queued(id)).toBe(2);
      await expireQueue(id);
      await alarm(id);
      expect(await everythingStored(id.syncId)).toBe(MARKER);
    } finally {
      await restore();
    }
  });
});

describe("persistent PIN guards", () => {
  it.each([1, 10])("clears %s failures from the old capability when promoting a guard", async (failures) => {
    const { id, web, proof } = await guarded();
    const next = await guardMaterial(2);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    const bad = { ...proof, prueba: b64u(rand(32)) };
    for (let n = 1; n <= failures; n++) {
      await allowAttempt(id);
      expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [bad] } })).status).toBe(n === 10 ? 423 : 403);
    }

    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
    const counters = await runInDurableObject(listStub(id.syncId), (_o, state) => {
      const row = state.storage.sql.exec<{ data: string }>("SELECT data FROM guard WHERE device = ?", web.deviceId).one();
      const { failures, failedSince, suspended, nextAttemptAt } = JSON.parse(row.data);
      return { failures, failedSince, suspended, nextAttemptAt };
    });
    expect(counters).toEqual({ failures: 0, failedSince: 0, suspended: false, nextAttemptAt: 0 });
    // No cooldown or resume: the new capability has a fresh attempt budget.
    const opened = await call("POST", `${web.guardPath}/open`, { body: { proofs: [next.proof] } });
    expect(opened.status).toBe(200);
    expect(await json(opened)).toEqual({ version: 2, b: next.prepare.secret, failedSince: 0, mustRotate: false });
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } })).status).toBe(404);

    // An idempotent commit must not reset failures or delay on the current guard.
    await allowAttempt(id);
    const wrongNext = { ...next.proof, prueba: b64u(rand(32)) };
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [wrongNext] } }))).toEqual({ error: "wrong_pin", left: 9 });
    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [wrongNext] } })).status).toBe(429);
    await allowAttempt(id);
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [wrongNext] } }))).toEqual({ error: "wrong_pin", left: 8 });
  });

  it("rejects preparation reusing the current guard token hash", async () => {
    const { web, prepare } = await guarded();
    const next = await guardMaterial(2);
    const reused = await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: { ...next.prepare, tokenHash: prepare.tokenHash } });
    expect(reused.status).toBe(409);
    expect(await json(reused)).toEqual({ error: "invalid_state" });
    for (let n = 0; n < 2; n++) {
      expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    }
  });

  it("rejects web sockets until required guard rotation commits", async () => {
    const { id, web, proof } = await guarded();
    const connect = async (key: string) => {
      const response = await openSocket(id, key);
      if (response.webSocket) {
        response.webSocket.accept();
        response.webSocket.close();
      }
      return response;
    };
    expect((await connect(web.guestKey)).status).toBe(101);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [{ ...proof, prueba: b64u(rand(32)) }] } })).status).toBe(403);
    await allowAttempt(id);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } })).status).toBe(200);
    const blocked = await connect(web.guestKey);
    expect(blocked.status).toBe(401);
    expect(await json(blocked)).toEqual({ error: "unauthorized" });
    expect((await connect(id.key)).status).toBe(101);
    const next = await guardMaterial(2);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    expect((await connect(web.guestKey)).status).toBe(401);
    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
    expect((await connect(web.guestKey)).status).toBe(101);
  });

  it("does the same hashes and fixed-size comparisons for every guard 404", async () => {
    const { id, web, proof } = await guarded();
    const next = await guardMaterial(2);
    const unknown = { ...proof, guardToken: b64u(rand(32)) };
    const second = { ...unknown, version: 2 };
    const measure = (syncId: string, deviceId: string, proofs: unknown[]) => runInDurableObject(listStub(syncId), async (_old, state) => {
      const recreated = new ListV2Object(state, env);
      const hashes = vi.spyOn(crypto.subtle, "digest");
      const comparisons = vi.spyOn(encoding, "timingSafeEqual");
      try {
        const result = await recreated.handle({ route: { syncId, resource: "guard", action: "open", deviceId, methods: ["POST"] }, method: "POST", verifier: null, client: "test", match: null, none: null, body: { proofs } });
        expect(result).toEqual({ status: 404, body: { error: "not_found" } });
        return {
          hashes: hashes.mock.calls.map((args) => (args[1] as Uint8Array).byteLength),
          comparisons: comparisons.mock.calls.map(([a, b]) => [a.byteLength, b.byteLength]),
        };
      } finally {
        hashes.mockRestore(); comparisons.mockRestore();
      }
    });
    const before = await everythingStored(id.syncId);
    const missing = newList();
    for (const proofs of [[unknown], [unknown, second]]) {
      const expected = { hashes: Array(proofs.length * 2).fill(32), comparisons: Array.from({ length: proofs.length * 4 }, () => [32, 32]) };
      expect(await measure(id.syncId, "nora", proofs)).toEqual(expected);
      expect(await measure(id.syncId, "leo", proofs)).toEqual(expected);
      expect(await measure(missing.syncId, "nora", proofs)).toEqual(expected);
    }
    expect(await everythingStored(id.syncId)).toBe(before);
    expect(await everythingStored(missing.syncId)).toBe("");
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    expect(await measure(id.syncId, "nora", [unknown, second])).toEqual({ hashes: [32, 32, 32, 32], comparisons: Array.from({ length: 8 }, () => [32, 32]) });
    await lastPhone(id);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(204);
    for (const proofs of [[proof], [proof, next.proof]]) {
      expect(await measure(id.syncId, "nora", proofs)).toEqual({ hashes: Array(proofs.length * 2).fill(32), comparisons: Array.from({ length: proofs.length * 4 }, () => [32, 32]) });
    }
    expect(await everythingStored(id.syncId)).toBe(MARKER);
  });

  it("validates malformed proofs equally for live, absent and retired lists", async () => {
    const { id, web, proof } = await guarded();
    const retired = await setup();
    expect((await call("DELETE", retired.path, { key: retired.key, headers: { "If-Match": '"1"' } })).status).toBe(204);
    const missing = newList();
    for (const body of [{}, { proofs: [] }, { proofs: [proof, proof] }, { proofs: [{ ...proof, guardToken: "bad" }] }, { proofs: [proof], role: "device" }]) {
      for (const path of [web.guardPath, `${id.path}/guards/leo`, `/v2/lists/${missing.syncId}/guards/nora`, `${retired.path}/guards/nora`]) {
        const r = await call("POST", `${path}/open`, { body });
        expect(r.status).toBe(400);
        expect(await json(r)).toEqual({ error: "bad_request" });
        expect(r.headers.get("Retry-After")).toBeNull();
      }
    }
    expect(await everythingStored(missing.syncId)).toBe("");
    expect(await everythingStored(retired.syncId)).toBe(MARKER);
  });

  it("protects another web's existing guard and never lets a phone replace its secrets", async () => {
    const { id, web } = await guarded();
    const other = await webPair(id, "leo", 2);
    const material = await guardMaterial();
    expect((await call("PUT", `${other.guardPath}/prepare`, { key: other.guestKey, body: material.prepare })).status).toBe(200);
    for (const key of [web.guestKey, id.key]) {
      for (const [method, action, body] of [["PUT", "prepare", material.prepare], ["POST", "commit", { version: 1 }], ["POST", "cancel", { version: 1 }]] as const) {
        const attack = await call(method, `${other.guardPath}/${action}`, { key, body });
        expect(attack.status).toBe(403); expect(await json(attack)).toEqual({ error: "forbidden_role" });
      }
    }
    expect(await json(await call("POST", `${other.guardPath}/open`, { body: { proofs: [material.proof] } }))).toEqual({ version: 1, b: material.prepare.secret, failedSince: 0, mustRotate: false });
    expect((await call("POST", `${id.path}/guards/missing/resume`, { key: id.key })).status).toBe(404);
  });

  it("counts two proofs once, throttles without spending and suspends on failure ten", async () => {
    const { id, web, proof } = await guarded();
    const next = await guardMaterial(2);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    const body = { proofs: [{ ...proof, prueba: b64u(rand(32)) }, { ...next.proof, prueba: b64u(rand(32)) }] };
    const first = await call("POST", `${web.guardPath}/open`, { body });
    expect(first.status).toBe(403); expect(await json(first)).toEqual({ error: "wrong_pin", left: 9 });
    const tooFast = await call("POST", `${web.guardPath}/open`, { body });
    expect(tooFast.status).toBe(429);
    expect(Number(tooFast.headers.get("Retry-After"))).toBeGreaterThan(0);
    expect(Number(tooFast.headers.get("Retry-After"))).toBeLessThanOrEqual(2);
    for (let n = 2; n <= 10; n++) {
      await allowAttempt(id);
      const r = await call("POST", `${web.guardPath}/open`, { body });
      expect(r.status).toBe(n === 10 ? 423 : 403);
      expect(await json(r)).toEqual(n === 10 ? { error: "guard_suspended" } : { error: "wrong_pin", left: 10 - n });
    }
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } })).status).toBe(423);
    const webResume = await call("POST", `${web.guardPath}/resume`, { key: web.guestKey, body: {} });
    expect(webResume.status).toBe(403); expect(await json(webResume)).toEqual({ error: "forbidden_role" });
    const other = await setup();
    expect((await call("POST", `${web.guardPath}/resume`, { key: other.key })).status).toBe(401);
    expect((await call("POST", `${web.guardPath}/resume`, { key: id.key })).status).toBe(200);
    const open = await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } });
    expect(open.status).toBe(200); expect(await json(open)).toMatchObject({version: 1, failedSince: 10, mustRotate: true});
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(409);
    expect((await call("POST", `${web.guardPath}/cancel`, { key: web.guestKey, body: {version: 2} })).status).toBe(200);
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(409);
    const rotated = await guardMaterial(2);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: rotated.prepare })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: {version: 2} })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/open`, { body: {proofs: [proof]} })).status).toBe(404);
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(200);
  });

  it("returns identical 404s for unknown token, missing guard and retired list", async () => {
    const { id, web, proof } = await guarded();
    const results = [
      await call("POST", `${web.guardPath}/open`, { body: { proofs: [{ ...proof, guardToken: b64u(rand(32)) }] } }),
      await call("POST", `${id.path}/guards/leo/open`, { body: { proofs: [proof] } }),
    ];
    await lastPhone(id);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(204);
    results.push(await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } }));
    for (const r of results) { expect(r.status).toBe(404); expect(await r.text()).toBe('{"error":"not_found"}'); expect(r.headers.get("Retry-After")).toBeNull(); }
    for (const action of ["prepare", "commit", "cancel", "resume"]) {
      const r = await call(action === "prepare" ? "PUT" : "POST", `${web.guardPath}/${action}`, { key: web.guestKey, body: {} });
      expect(r.status).toBe(410); expect(await json(r)).toEqual({ error: "retired" });
    }
    const common = await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { common: "AAAA" } });
    expect(common.status).toBe(410); expect(await json(common)).toEqual({ error: "retired" });
    expect(await everythingStored(id.syncId)).toBe(MARKER);
  });

  it("keeps token misses outside the attempt budget", async () => {
    const { web, proof, prepare } = await guarded();
    for (let n = 0; n < 11; n++) expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [{ ...proof, guardToken: b64u(rand(32)) }] } })).status).toBe(404);
    const r = await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } });
    expect(r.status).toBe(200); expect(await json(r)).toEqual({ version: 1, b: prepare.secret, failedSince: 0, mustRotate: false });
  });

  it("reports failures once and gates copied tokens until rotation commits", async () => {
    const { id, web, proof, prepare } = await guarded();
    const bad = { ...proof, prueba: b64u(rand(32)) };
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [bad] } }))).toEqual({ error: "wrong_pin", left: 9 });
    await allowAttempt(id);
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } }))).toEqual({ version: 1, b: prepare.secret, failedSince: 1, mustRotate: true });
    await allowAttempt(id);
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } }))).toEqual({ version: 1, b: prepare.secret, failedSince: 0, mustRotate: true });
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(409);
    expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, body: {common: "AAAA"}, headers: {"If-Match": '"2"'} })).status).toBe(409);
    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: {version: 1} })).status).toBe(200);
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(409);
    const next = await guardMaterial(2);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: {version: 2} })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [bad] } })).status).toBe(404);
    expect((await call("GET", id.path, { key: web.guestKey })).status).toBe(200);
  });

  it("handles a pending PIN change, repeated prepare/commit and cancellation", async () => {
    const { id, web, proof, prepare } = await guarded();
    const next = await guardMaterial(2);
    const change = () => call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: next.prepare });
    expect((await change()).status).toBe(200); expect((await change()).status).toBe(200);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: { ...next.prepare, secret: b64u(rand(32)) } })).status).toBe(409);
    expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: { ...next.prepare, version: 3 } })).status).toBe(409);
    // Pending opens before commit, including recovery after IndexedDB saved the new box.
    const pending = await call("POST", `${web.guardPath}/open`, { body: { proofs: [{ ...proof, prueba: b64u(rand(32)) }, next.proof] } });
    expect(await json(pending)).toEqual({ version: 2, b: next.prepare.secret, failedSince: 0, mustRotate: false });
    expect((await call("POST", `${web.guardPath}/cancel`, { key: web.guestKey, body: { version: 1 } })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/cancel`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [next.proof] } })).status).toBe(404);
    await allowAttempt(id);
    expect(await json(await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } }))).toEqual({ version: 1, b: prepare.secret, failedSince: 0, mustRotate: false });
    expect((await change()).status).toBe(200);
    for (let n = 0; n < 2; n++) expect((await call("POST", `${web.guardPath}/commit`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } })).status).toBe(404);
    const stored = await everythingStored(id.syncId);
    expect(stored).not.toContain(proof.guardToken); expect(stored).not.toContain(proof.prueba);
    expect(stored).not.toContain(prepare.secret); expect(stored).not.toContain(next.proof.guardToken); expect(stored).not.toContain(next.proof.prueba);
    expect(stored).toContain(next.prepare.secret); expect(stored).toContain(next.prepare.tokenHash); expect(stored).toContain(next.prepare.verifier);
    expect((await json(await call("GET", id.path, { key: id.key }))).version).toBe(2);
  });

  it("preserves failures when the list object is constructed again over its storage", async () => {
    const { id, web, proof } = await guarded();
    const badProof = { ...proof, prueba: b64u(rand(32)) };
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [badProof] } })).status).toBe(403);
    await allowAttempt(id);
    const result = await runInDurableObject(listStub(id.syncId), async (_old, state) => {
      const recreated = new ListV2Object(state, env);
      return recreated.handle({ route: { syncId: id.syncId, resource: "guard", action: "open", deviceId: "nora", methods: ["POST"] }, method: "POST", verifier: null, client: "test", match: null, none: null, body: { proofs: [badProof] } });
    });
    expect(result.status).toBe(403); expect(result.body).toEqual({ error: "wrong_pin", left: 8 });
  });

  it.each(["revoke", "delete", "expiry"])("erases guard secrets on %s", async (action) => {
    const { id, web, proof, prepare } = await guarded();
    if (action === "revoke") expect((await call("POST", `${id.path}/revoke`, { key: web.guestKey, body: { deviceId: "nora" } })).status).toBe(200);
    if (action === "delete") await lastPhone(id);
    if (action === "delete") expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(204);
    if (action === "expiry") {
      await editState(id, (m) => { m.lastAccess = Date.now() - 401 * DAY; });
      expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    }
    expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [proof] } })).status).toBe(404);
    const stored = await everythingStored(id.syncId);
    for (const s of [prepare.secret, prepare.tokenHash, prepare.verifier]) expect(stored).not.toContain(s);
    if (action !== "revoke") expect(stored).toBe(MARKER);
  });

  it("enforces a 2 KiB streaming body cap and a separate 30/min/IP budget", async () => {
    const id = await setup();
    const path = `${id.path}/guards/nora/open`;
    expect((await call("POST", path, { rawBody: JSON.stringify({ pad: "x".repeat(2048) }) })).status).toBe(413);
    const body = { proofs: [(await guardMaterial()).proof] };
    const ip = randomIp();
    expect((await call("POST", path, { ip, body })).status).toBe(404);
    // Fill the real edge binding without slow list RPCs crossing a UTC minute.
    for (let n = 1; n < 30; n++) expect((await env.GUARD_IP_LIMITER.limit({ key: ip })).success).toBe(true);
    const limited = await call("POST", path, { ip, body });
    expect(limited.status).toBe(429); expect(Number(limited.headers.get("Retry-After"))).toBeGreaterThan(0);
    expect((await call("GET", id.path, { key: id.key, ip })).status).toBe(200);
    expect((await call("POST", `${id.path}/invites`, { key: id.key, ip, body: { offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } } })).status).toBe(201);
  });

  it("rejects malformed versions and noncanonical 32-byte guard fields", async () => {
    const { web, prepare, proof } = await guarded();
    for (const field of ["tokenHash", "verifier", "secret"]) {
      for (const value of [b64u(rand(31)), `${b64u(rand(32))}=`, "x", null]) {
        expect((await call("PUT", `${web.guardPath}/prepare`, { key: web.guestKey, body: { ...prepare, version: 2, [field]: value } })).status).toBe(400);
      }
    }
    for (const body of [
      { proofs: [] }, { proofs: [proof, proof] }, { proofs: [proof, proof, proof] },
      { proofs: [{ ...proof, version: 0 }] }, { proofs: [{ ...proof, guardToken: `${proof.guardToken}=` }] },
      { proofs: [{ ...proof, prueba: b64u(rand(31)) }] },
    ]) expect((await call("POST", `${web.guardPath}/open`, { body })).status).toBe(400);
  });

  it("does not spend family writes on guard attempts or guard management", async () => {
    const { id, web, proof } = await guarded();
    for (let n = 0; n < 35; n++) {
      expect((await call("POST", `${web.guardPath}/cancel`, { key: web.guestKey, body: { version: 2 } })).status).toBe(200);
      expect((await call("POST", `${web.guardPath}/open`, { body: { proofs: [{ ...proof, guardToken: b64u(rand(32)) }] } })).status).toBe(404);
    }
    expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { common: "BBBB" } })).status).toBe(200);
  });
});

describe("v2 snapshots with v1 retired", () => {
  it("creates an atomic snapshot through the EU list RPC", async () => {
    const id = newList();
    const result = await listStub(id.syncId).handle({
      route: { syncId: id.syncId, resource: "list", methods: ["PUT"] },
      method: "PUT",
      verifier: await digest(id.key),
      client: id.ip,
      match: '"0"',
      none: null,
      body: { ...creation("aritz"), deviceId: "aritz" },
    });
    expect(result).toMatchObject({ status: 201, body: { version: 1 } });
  });

  it("stores only the SHA-256 of each credential and leaves v1 retired", async () => {
    const id = await setup();
    const i = await pair(id);
    const r = await call("GET", id.path, { key: id.key });
    expect(r.headers.get("ETag")).toBe('"2"');
    expect(await json(r)).toEqual({
      ...creation("aritz"),
      version: 2,
      devices: [
        { deviceId: "aritz", revoked: false, role: "device" },
        { deviceId: "nora", revoked: false, role: "device", approvedBy: "aritz" },
      ],
      capacity: capacity(2, 1, false),
      slotCapacity: 2,
    });
    expect((await call("GET", id.path, { key: id.key, headers: { "If-None-Match": '"2"' } })).status).toBe(304);
    const stored = await everythingStored(id.syncId);
    for (const key of [id.key, i.guestKey]) {
      expect(stored).not.toContain(key);
      expect(stored).toContain(await digest(key));
    }
    expect((await call("GET", id.path, { key: b64u(rand(32)) })).status).toBe(401);
    expect((await call("GET", id.path)).status).toBe(401);
    // Retired v1 paths cannot affect the v2 object with the same id.
    for (const method of ["GET", "PUT", "DELETE"]) {
      expect((await call(method, `/v1/lists/${id.syncId}`, { key: id.key })).status).toBe(410);
    }
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
  });

  it("requires an exact If-Match on creation, PUT and DELETE", async () => {
    const id = await setup();
    for (const method of ["PUT", "DELETE"]) {
      for (const [match, status] of [[undefined, 428], ['"0"', 412], ['"2"', 412], ["*", 412], ['W/"1"', 412], ['"1", "2"', 412]] as const) {
        const res = await call(method, id.path, { key: id.key, headers: match ? { "If-Match": match } : {}, ...(method === "PUT" ? { body: snapshot() } : {}) });
        expect(res.status).toBe(status);
        if (status === 412) expect(res.headers.get("ETag")).toBe('"1"');
      }
    }
    const fresh = newList();
    const create = (headers: Record<string, string>) => call("PUT", `/v2/lists/${fresh.syncId}`, { key: fresh.key, headers, body: { ...creation("aritz"), deviceId: "aritz" } });
    expect((await create({})).status).toBe(428);
    expect((await create({ "If-Match": '"1"' })).status).toBe(412);
    expect((await create({ "If-Match": "*" })).status).toBe(412);
    expect((await put(id, snapshot(), 1)).status).toBe(200);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(412);
    expect((await json(await call("GET", id.path, { key: id.key }))).version).toBe(2);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(204);
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    // A deleted syncId is never created again (only its retirement marker remains).
    const again = await call("PUT", id.path, { key: id.key, headers: { "If-Match": '"0"' }, body: { ...creation("aritz"), deviceId: "aritz" } });
    expect(again.status).toBe(410);
    expect(await json(again)).toEqual({ error: "retired" });
  });

  it("stores slots as separate resources read under one snapshot version", async () => {
    const id = await setup();
    expect((await put(id, snapshot([slot(0)]), 1)).status).toBe(200);
    const s = `${id.path}/slots/person0/aritz`;
    expect((await call("GET", s, { key: id.key })).status).toBe(428);
    expect((await call("GET", s, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(412);
    const current = await call("GET", s, { key: id.key, headers: { "If-Match": '"2"' } });
    expect(await json(current)).toEqual({ data: sealed("person0", "aritz"), version: 2, slotVersion: 2 });
    // Unchanged slots keep the version that wrote them, so a phone fetches only what changed.
    expect((await put(id, { ...snapshot([slot(0)]), common: "BBBB", keyPackages: [{ v: 3, from: "aritz", c: "x" }] }, 2)).status).toBe(200);
    expect((await call("GET", s, { key: id.key, headers: { "If-Match": '"2"' } })).status).toBe(412);
    const state = await json<{ common: string; slots: unknown[]; keyPackages: unknown[] }>(await call("GET", id.path, { key: id.key }));
    expect(state.common).toBe("BBBB");
    expect(state.keyPackages).toEqual([{ v: 3, from: "aritz", c: "x" }]);
    expect(state.slots).toEqual([{ personId: "person0", deviceId: "aritz", version: 2 }]);
    expect((await put(id, snapshot([slot(0, "aritz", null)]), 3)).status).toBe(200);
    expect((await call("GET", s, { key: id.key, headers: { "If-Match": '"4"' } })).status).toBe(404);
  });

  it("binds each slot to its writer's credential and to its own header", async () => {
    const id = await setup();
    const i = await pair(id);
    // Nora may not write a slot under Aritz's name, nor smuggle one under hers.
    expect((await put(id, snapshot([slot(0)]), 2, i.guestKey)).status).toBe(403);
    expect((await put(id, snapshot([{ personId: "person0", deviceId: "nora", data: sealed("person0", "aritz") }]), 2, i.guestKey)).status).toBe(400);
    expect((await put(id, snapshot([{ personId: "person1", deviceId: "nora", data: sealed("person0", "nora") }]), 2, i.guestKey)).status).toBe(400);
    expect((await put(id, snapshot([{ personId: "person0", deviceId: "nora", data: b64u(rand(64)) }]), 2, i.guestKey)).status).toBe(400);
    expect((await put(id, snapshot([{ personId: "person0", deviceId: "nora", data: { c: "json" } }]), 2, i.guestKey)).status).toBe(400);
    expect((await put(id, snapshot([slot(0, "nora")]), 2, i.guestKey)).status).toBe(200);
    expect((await put(id, snapshot([slot(0)]), 3)).status).toBe(200);
    // Nobody removes another writer's slot (B2); its own writer may.
    const foreign = await put(id, snapshot([slot(0, "aritz", null)]), 4, i.guestKey);
    expect(foreign.status).toBe(403);
    expect(await json(foreign)).toEqual({ error: "forbidden_slot" });
    expect((await put(id, snapshot([slot(0, "aritz", null)]), 4)).status).toBe(200);
    const state = await json<{ slots: unknown[] }>(await call("GET", id.path, { key: id.key }));
    expect(state.slots).toEqual([{ personId: "person0", deviceId: "nora", version: 3 }]);
  });

  it("accepts a slot of exactly 131,584 bytes with the longest ids and rejects one more byte", async () => {
    const long = (c: string) => c.repeat(128);
    const id = await setup(long("d"));
    const max = sealed(long("p"), long("d"), { listId: long("l"), tail: SLOT_TAIL });
    expect(decodeB64Url(max)!.length).toBe(V2_MAX_SLOT_BYTES);
    expect(slotIds(decodeB64Url(max)!)).toEqual({ personId: long("p"), writer: long("d"), headerBytes: 420 });
    const body = (data: string) => snapshot([{ personId: long("p"), deviceId: long("d"), data }]);
    expect((await put(id, body(max), 1)).status).toBe(200);
    const over = sealed(long("p"), long("d"), { listId: long("l"), tail: SLOT_TAIL + 1 });
    expect((await put(id, body(over), 2)).status).toBe(413);
    const read = await call("GET", `${id.path}/slots/${long("p")}/${long("d")}`, { key: id.key, headers: { "If-Match": '"2"' } });
    expect((await json<{ data: string }>(read)).data).toBe(max);
  });

  /** [count] phones that all announced `slotCapacity` 2 (Aritz included), and the stored rows to fill [total] slots between them. */
  const announcedFamily = async (id: Setup, count: number, total: number) => {
    await editState(id, (m) => {
      while (m.credentials.length < count) m.credentials.push({ deviceId: `capacity${m.credentials.length}`, verifier: b64u(rand(32)), revoked: false, records: [], createdAt: Date.now() - 8 * DAY });
      for (const a of m.credentials) (a as { slotCapacity?: number }).slotCapacity = 2;
    });
    const writers = Array.from({ length: count - 1 }, (_, n) => `capacity${n + 1}`);
    await plant(id, Array.from({ length: total }, (_, n) => [`person${n}`, writers[n % writers.length]!] as [string, string]));
  };

  it("checks the slot cap (V2_MAX_SLOTS) once every phone announced it, counting stored slots, before writing anything", async () => {
    const id = await setup();
    // 12 phones: 127 stored slots (at most 11 per writer, all paid by the slot supplement) and one of Aritz.
    await announcedFamily(id, 12, V2_MAX_SLOTS - 1);
    // One entry too many is refused even when malformed: the count comes first.
    expect(validateSnapshot(snapshot(Array.from({ length: V2_MAX_SLOTS + 1 }, () => "not a slot")))).toBe(413);
    expect((await put(id, snapshot([slot(200)]), 1)).status).toBe(200);
    const full = await put(id, { ...snapshot([slot(201)]), common: "BBBB" }, 2);
    expect(full.status).toBe(413);
    expect(await json(full)).toEqual({ error: "too_many_slots" });
    const state = await json<{ version: number; common: string; slots: unknown[]; capacity: { slots: unknown } }>(await call("GET", id.path, { key: id.key }));
    expect(state.version).toBe(2);
    expect(state.common).toBe("AAAA");
    expect(state.slots).toHaveLength(V2_MAX_SLOTS);
    expect(state.capacity.slots).toEqual({ used: V2_MAX_SLOTS, warn: V2_WARN_SLOTS, max: V2_MAX_SLOTS });
    // Full: replacing its own slot still works, and so does swapping one for another.
    const replaced = { personId: "person200", deviceId: "aritz", data: sealed("person200", "aritz", { fill: 1 }) };
    expect((await put(id, snapshot([replaced]), 2)).status).toBe(200);
    expect((await put(id, snapshot([slot(200, "aritz", null), slot(201)]), 3)).status).toBe(200);
  });

  it("keeps the 1.0.5 cap of 64 slots while one active phone has not announced slotCapacity; webs and revoked ones do not count", async () => {
    const id = await setup();
    await announcedFamily(id, 12, V2_LEGACY_MAX_SLOTS - 1);
    // One phone (as if still on 1.0.5) never announced.
    await editState(id, (m) => { delete (m.credentials[3] as { slotCapacity?: number }).slotCapacity; });
    expect((await put(id, snapshot([slot(200)]), 1)).status).toBe(200);
    const read = async () => (await json<{ capacity: { slots: unknown }; slotCapacity: number; devices: { deviceId: string; slotCapacity?: number }[] }>(await call("GET", id.path, { key: id.key })));
    const before = await read();
    expect(before.capacity.slots).toEqual({ used: V2_LEGACY_MAX_SLOTS, warn: V2_LEGACY_WARN_SLOTS, max: V2_LEGACY_MAX_SLOTS });
    expect(before.slotCapacity).toBe(2);
    expect(before.devices.find((d) => d.deviceId === "aritz")!.slotCapacity).toBe(2);
    expect(before.devices.find((d) => d.deviceId === "capacity3")!.slotCapacity).toBeUndefined();
    const full = await put(id, snapshot([slot(201)]), 2);
    expect(full.status).toBe(413);
    expect(await json(full)).toEqual({ error: "too_many_slots" });
    // Replacing stays possible at the cap.
    const replaced = { personId: "person200", deviceId: "aritz", data: sealed("person200", "aritz", { fill: 1 }) };
    expect((await put(id, snapshot([replaced]), 2)).status).toBe(200);
    // A revoked phone or a web that never announced does not hold the list back.
    await editState(id, (m) => {
      m.credentials[3]!.revoked = true;
      m.credentials.push({ deviceId: "the-web", verifier: b64u(rand(32)), revoked: false, records: [], role: "web", createdAt: Date.now() } as State["credentials"][number]);
    });
    expect((await put(id, snapshot([slot(201)]), 3)).status).toBe(200);
  });

  it("only the slotCapacity announcement that lifts the cap moves the version", async () => {
    const id = await setup();
    const leoKey = b64u(rand(32)), leoVerifier = await digest(leoKey);
    await editState(id, (m) => { m.credentials.push({ deviceId: "leo", verifier: leoVerifier, revoked: false, records: [], createdAt: Date.now() }); });
    const announce = (key: string) => call("POST", `${id.path}/capability`, { key, body: { slotCapacity: 2 } });
    // Leo has not announced: Aritz's announcement changes no cap, so no new version.
    expect((await announce(id.key)).headers.get("ETag")).toBe('"1"');
    expect((await call("GET", id.path, { key: id.key, headers: { "If-None-Match": '"1"' } })).status).toBe(304);
    // Leo's lifts it from 64 to 128: new version, and a repeat changes nothing.
    expect((await announce(leoKey)).headers.get("ETag")).toBe('"2"');
    expect((await announce(leoKey)).headers.get("ETag")).toBe('"2"');
    const after = await json<{ capacity: { slots: { max: number } } }>(await call("GET", id.path, { key: id.key, headers: { "If-None-Match": '"1"' } }));
    expect(after.capacity.slots.max).toBe(V2_MAX_SLOTS);
  });

  it("POST S/capability {slotCapacity: 2} announces it once; anything else is refused", async () => {
    const id = await setup();
    const announce = (body: unknown) => call("POST", `${id.path}/capability`, { key: id.key, body });
    for (const bad of [{ slotCapacity: 3 }, { slotCapacity: "2" }, { slotCapacity: 1 }, { slotCapacity: 2, other: 1 }]) {
      expect((await announce(bad)).status, JSON.stringify(bad)).toBe(400);
    }
    // Aritz is the only phone: his announcement moves the cap from 64 to 128,
    // so the version moves (readers must not get a 304 with the old cap).
    const first = await announce({ slotCapacity: 2 });
    expect(first.status).toBe(200);
    expect(first.headers.get("ETag")).toBe('"2"');
    const again = await announce({ slotCapacity: 2 });
    expect(again.headers.get("ETag")).toBe('"2"');
    expect((await call("GET", id.path, { key: id.key, headers: { "If-None-Match": '"1"' } })).status).toBe(200);
    const both = await announce({ commonFormat: 2, slotCapacity: 2 });
    expect(both.status).toBe(200);
    const devices = (await json<{ devices: { deviceId: string; slotCapacity?: number; commonFormat?: number }[] }>(await call("GET", id.path, { key: id.key }))).devices;
    expect(devices.find((d) => d.deviceId === "aritz")).toMatchObject({ slotCapacity: 2, commonFormat: 2 });
  });

  it("caps the slots of one writer at 32; above it a writer may still replace and remove", async () => {
    const id = await setup();
    await byteCapacity(id, 7);
    await plant(id, Array.from({ length: 31 }, (_, n) => [`person${n}`, "aritz"] as [string, string]));
    expect((await put(id, snapshot([slot(31)]), 1)).status).toBe(200);
    const over = await put(id, snapshot([slot(32)]), 2);
    expect(over.status).toBe(413);
    expect(await json(over)).toEqual({ error: "too_many_writer_slots" });
    expect((await put(id, snapshot([slot(0, "aritz", null), slot(32)]), 2)).status).toBe(200);
    // Another writer keeps its own budget.
    const i = await pair(id, "nora", 3);
    expect((await put(id, snapshot([slot(0, "nora")]), 4, i.guestKey)).status).toBe(200);
    // A writer left above the cap (older server) may replace or remove, never add.
    await plant(id, [["person40", "aritz"], ["person41", "aritz"]], 5);
    expect((await put(id, snapshot([slot(42)]), 5)).status).toBe(413);
    expect((await put(id, snapshot([{ personId: "person40", deviceId: "aritz", data: sealed("person40", "aritz", { fill: 2 }) }]), 5)).status).toBe(200);
    expect((await put(id, snapshot([slot(41, "aritz", null)]), 6)).status).toBe(200);
  });

  it("refuses a slot no phone could parse: wrong size, policy flags or revision range", async () => {
    const id = await setup();
    const at = (data: string) => put(id, snapshot([{ personId: "person0", deviceId: "aritz", data }]), 1);
    for (const data of [
      sealed("person0", "aritz", { tail: SLOT_TAIL - 1 }),
      sealed("person0", "aritz", { tail: SLOT_TAIL - 300 }),
      sealed("person0", "aritz", { tail: 16 }),
      sealed("person0", "aritz", { flags: 2 }),
      sealed("person0", "aritz", { revisionHigh: 0x200000 }),
    ]) {
      const r = await at(data);
      expect(r.status).toBe(400);
      expect(await json(r)).toEqual({ error: "bad_request" });
    }
    expect((await at(sealed("person0", "aritz", { flags: 1, revisionHigh: 0x1fffff }))).status).toBe(200);
  });

  it("caps registry counts and bytes before reading any declaration", async () => {
    for (const [field, max] of [["records", 64], ["vouches", 256], ["revocations", 64]] as const) {
      const s = snapshot();
      s.registry[field] = Array(max + 1).fill(null);
      expect(validateSnapshot(s)).toBe(413);
      s.registry[field] = Array(max).fill(null);
      expect(validateSnapshot(s)).toBeNull();
    }
    expect(validateSnapshot({ ...snapshot(), registry: { ...registry(), pad: "x".repeat(V2_MAX_REGISTRY_BYTES) } })).toBe(413);
    expect(validateSnapshot({ ...snapshot(), registry: { ...registry(), records: {} } })).toBe(400);
    expect(validateSnapshot({ ...snapshot(), keyPackages: Array(513).fill(null) })).toBe(413);
    const id = await setup();
    const s = snapshot();
    s.registry.records = Array(65).fill(null);
    expect((await put(id, s, 1)).status).toBe(413);
    expect((await json(await call("GET", id.path, { key: id.key }))).version).toBe(1);
  });

  it("limits new device records per credential per day", async () => {
    const id = await setup();
    const s = snapshot();
    s.registry.records = Array.from({ length: 9 }, (_, n) => ({ d: `device${n}` }));
    const r = await put(id, s, 1);
    expect(r.status).toBe(429);
    expect(Number(r.headers.get("Retry-After"))).toBeGreaterThan(80_000);
    s.registry.records = s.registry.records.slice(0, 8);
    expect((await put(id, s, 1)).status).toBe(200);
    // Records already seen cost nothing; a new one does.
    expect((await put(id, s, 2)).status).toBe(200);
    s.registry.records.push({ d: "device8" });
    expect((await put(id, s, 3)).status).toBe(429);
  });

  it("allows exactly one concurrent update for an ETag", async () => {
    const id = await setup();
    const results = await Promise.all(["BBBB", "CCCC"].map((common) => put(id, { ...snapshot(), common }, 1)));
    expect(results.map((r) => r.status).sort()).toEqual([200, 412]);
    expect((await json(await call("GET", id.path, { key: id.key }))).version).toBe(2);
  });
});

describe("v2 pairing and revoke wins", () => {
  it("refuses registration of a new credential without a signing key", async () => {
    const id = await setup();
    const i = await invite(id);
    const answer = { ...i.answer, guest: { d: "nora" } };
    expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, answer } })).status).toBe(201);
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
    const response = await approve(id, i, 1);
    expect(response.status).toBe(400);
    expect(await json(response)).toEqual({ error: "renewal_key_binding_required" });
    expect((await readState(id)).credentials.map((c) => c.deviceId)).toEqual(["aritz"]);
  });
  it("transports an immutable offer, one answer, the reveal and the approval", async () => {
    const id = await setup();
    const i = await invite(id);
    expect((await call("GET", `${i.publicPath}/offer`)).status).toBe(200);
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(409);
    expect((await call("POST", `${i.publicPath}/answer`, { body: i.answerBody })).status).toBe(201);
    expect((await call("POST", `${i.publicPath}/answer`, { body: { ...i.answerBody, serviceCredentialVerifier: await digest(b64u(rand(32))) } })).status).toBe(409);
    expect((await call("GET", `${i.publicPath}/result`, { key: b64u(rand(32)) })).status).toBe(404);
    expect((await call("GET", `${i.publicPath}/result`)).status).toBe(404);
    const pending = await call("GET", `${i.publicPath}/result`, { key: i.guestKey });
    expect(pending.status).toBe(202);
    expect(await json(pending)).toEqual({ status: "pending", reveal: null });
    expect((await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: {} } })).status).toBe(409);
    const reveal = { v: 2, n: b64u(rand(32)) };
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal } })).status).toBe(200);
    expect((await call("POST", `${i.privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(409);
    expect(await json(await call("GET", `${i.publicPath}/result`, { key: i.guestKey }))).toEqual({ status: "pending", reveal });
    expect((await call("GET", id.path, { key: i.guestKey })).status).toBe(401);
    expect((await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"0"' }, body: { package: {} } })).status).toBe(412);
    expect((await call("POST", `${i.privatePath}/approve`, { key: id.key, body: { package: {} } })).status).toBe(428);
    const approved = await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: { c: "opaque" } } });
    expect(approved.status).toBe(200);
    expect(approved.headers.get("ETag")).toBe('"2"');
    const result = await json(await call("GET", `${i.publicPath}/result`, { key: i.guestKey }));
    expect(result).toEqual({ reveal, package: { c: "opaque" }, minVersion: 2, syncId: id.syncId });
    // A lost response is recoverable: the same guest credential can ask again.
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
    expect((await call("GET", id.path, { key: i.guestKey })).status).toBe(200);
    expect((await call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": '"2"' }, body: { package: {} } })).status).toBe(409);
  });

  it("only the owner manages an invitation and the host record must be its own", async () => {
    const id = await setup();
    const i = await pair(id);
    expect((await call("POST", `${id.path}/invites`, { key: i.guestKey, body: { offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } } })).status).toBe(400);
    const own = await invite(id, "leo");
    expect((await call("GET", own.privatePath, { key: i.guestKey })).status).toBe(403);
    expect((await call("DELETE", own.privatePath, { key: i.guestKey })).status).toBe(403);
    expect((await call("DELETE", own.privatePath, { key: id.key })).status).toBe(204);
    expect((await call("GET", `${own.publicPath}/offer`)).status).toBe(404);
    // A device id already in the list cannot be answered again.
    const again = await invite(id, "nora");
    expect((await call("POST", `${again.publicPath}/answer`, { body: again.answerBody })).status).toBe(409);
  });

  it("rejects a revoked credential on every route, closes its socket and cancels its invitations", async () => {
    const id = await setup();
    const i = await pair(id);
    const socket = await exports.default.fetch(
      new Request(`https://sync.test${id.path}/ws`, {
        headers: { Upgrade: "websocket", "Sec-WebSocket-Protocol": `gift-huddle.v2, bearer.${i.guestKey}`, Cookie: "secret", "x-verifier": await digest(id.key) },
      }),
    );
    expect(socket.status).toBe(101);
    expect(socket.headers.get("Sec-WebSocket-Protocol")).toBe("gift-huddle.v2");
    const ws = socket.webSocket!;
    ws.accept();
    const closed = new Promise<CloseEvent>((resolve) => ws.addEventListener("close", resolve));
    ws.addEventListener("close", () => ws.close());
    const hostSocket = (await openSocket(id, id.key)).webSocket!;
    hostSocket.accept();
    const announced = new Promise<string>((resolve) => hostSocket.addEventListener("message", (e) => resolve(e.data as string)));

    const owned = await invite(id, "leo", undefined, i.guestKey, "nora");
    const hosted = await invite(id, "leo");
    expect((await call("POST", `${hosted.publicPath}/answer`, { body: hosted.answerBody })).status).toBe(201);

    const revoked = await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } });
    expect(revoked.status).toBe(200);
    expect(revoked.headers.get("ETag")).toBe('"3"');
    expect((await closed).code).toBe(4401);
    expect(JSON.parse(await announced)).toEqual({ type: "version", version: 3 });

    const cases: [string, string, unknown?][] = [
      ["GET", id.path],
      ["PUT", id.path, snapshot()],
      ["PUT", id.path, { ...snapshot(), registry: { ...registry(), revocations: [{ d: "aritz" }] } }],
      ["DELETE", id.path],
      ["GET", `${id.path}/slots/person0/aritz`],
      ["POST", `${id.path}/revoke`, { deviceId: "aritz" }],
      ["POST", `${id.path}/invites`, { offer: { v: 2, host: { d: "nora" }, c: b64u(rand(32)) } }],
      ["GET", i.privatePath],
      ["DELETE", i.privatePath],
      ["POST", `${i.privatePath}/reveal`, {}],
      ["POST", `${i.privatePath}/approve`, {}],
      ["GET", `${hosted.publicPath}/offer`],
      ["GET", `${i.publicPath}/result`],
      ["POST", `${hosted.publicPath}/answer`, hosted.answerBody],
    ];
    for (const [method, path, body] of cases) {
      expect((await call(method, path, { key: i.guestKey, body, headers: { "If-Match": '"3"' } })).status, `${method} ${path}`).toBe(401);
    }
    expect((await exports.default.fetch(new Request(`https://sync.test${id.path}/ws`, { headers: { Upgrade: "websocket", Authorization: `Bearer ${i.guestKey}` } }))).status).toBe(401);
    expect((await openSocket(id, i.guestKey)).status).toBe(401);
    // Her own invitation is gone; others' invitations survive.
    expect((await call("GET", `${owned.publicPath}/offer`)).status).toBe(404);
    expect((await call("GET", `${hosted.publicPath}/offer`)).status).toBe(200);
    // She cannot come back with the same credential, even under another id.
    const retry = await invite(id, "nora-again", i.guestKey);
    expect((await call("POST", `${retry.publicPath}/answer`, { body: retry.answerBody })).status).toBe(401);
    const meta = await runInDurableObject(listStub(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data) as { credentials: { deviceId: string; verifier: string | null; revoked: boolean }[] });
    expect(meta.credentials.find((c) => c.deviceId === "nora")).toMatchObject({ verifier: null, revoked: true });
    // Idempotent: revoking again changes nothing.
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).headers.get("ETag")).toBe('"3"');
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nobody" } })).status).toBe(404);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"3"' } })).status).toBe(204);
    expect((await call("PUT", id.path, { key: i.guestKey, headers: { "If-Match": '"0"' }, body: { ...creation("nora"), deviceId: "nora" } })).status).toBe(410);
  });

  it("keeps pre.22 credentials without approvedBy readable", async () => {
    const id = await setup();
    const i = await pair(id);
    await editState(id, (m) => { delete m.credentials[1]!.approvedBy; });
    const r = await call("GET", id.path, { key: i.guestKey });
    expect(r.status).toBe(200);
    expect((await json<{ devices: unknown[] }>(r)).devices).toEqual([
      { deviceId: "aritz", revoked: false, role: "device" },
      { deviceId: "nora", revoked: false, role: "device" },
    ]);
  });

  it("4: preserves the approver of a hidden credential after revoking its host and cancelling the invitation", async () => {
    const id = await setup();
    const i = await pair(id);
    const viaNora = await invite(id, "leo", undefined, i.guestKey, "nora");
    expect((await call("POST", `${viaNora.publicPath}/answer`, { body: viaNora.answerBody })).status).toBe(201);
    expect((await call("POST", `${viaNora.privatePath}/reveal`, { key: i.guestKey, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
    expect((await call("POST", `${viaNora.privatePath}/approve`, { key: i.guestKey, headers: { "If-Match": '"2"' }, body: { package: { c: "x" } } })).status).toBe(200);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("GET", `${viaNora.publicPath}/result`, { key: viaNora.guestKey })).status).toBe(404);
    // Leo's credential stays (the server does not decide trust), but the family sees it and can revoke it.
    const { devices } = await json<{ devices: unknown[] }>(await call("GET", id.path, { key: id.key }));
    expect(devices).toEqual([
      { deviceId: "aritz", revoked: false, role: "device" },
      { deviceId: "nora", revoked: true, role: "device", approvedBy: "aritz" },
      { deviceId: "leo", revoked: false, role: "device", approvedBy: "nora" },
    ]);
  });

  it("orders a concurrent write and revocation; nothing is accepted after the revocation", async () => {
    const id = await setup();
    const i = await pair(id);
    const [write, revoke] = await Promise.all([
      put(id, { ...snapshot(), common: "BBBB" }, 2, i.guestKey),
      call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } }),
    ]);
    expect(revoke.status).toBe(200);
    expect([200, 401]).toContain(write.status);
    const state = await json<{ version: number }>(await call("GET", id.path, { key: id.key }));
    expect(state.version).toBe(write.status === 200 ? 4 : 3);
    expect((await put(id, snapshot(), state.version, i.guestKey)).status).toBe(401);
  });

  it("allows revocation when another writer has exhausted the list budget", async () => {
    const id = await setup();
    await pair(id);
    await runInDurableObject(listStub(id.syncId), (instance) => {
      (instance as unknown as { rate: Map<string, { start: number; count: number }> }).rate.set("list", { start: Date.now(), count: 60 });
    });
    expect((await put(id, snapshot(), 2)).status).toBe(429);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
  });

  it("caps credentials of a generation at 64, revoked ones included, with generation_full", async () => {
    const id = await setup();
    await editState(id, (m) => {
      for (let n = 1; n < 64; n++) m.credentials.push({ deviceId: `old${n}`, verifier: null, revoked: true, records: [] });
    });
    const r = await approve(id, await answered(id), 1);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "generation_full" });
  });

  it("expires invitations even when the alarm is late", async () => {
    const id = await setup();
    const i = await invite(id);
    const stub = listStub(id.syncId);
    await runInDurableObject(stub, (_o, state) => {
      state.storage.sql.exec("UPDATE invite SET expires_at = ?", Date.now() - 1);
    });
    expect((await call("GET", `${i.publicPath}/offer`)).status).toBe(404);
    expect((await call("GET", i.privatePath, { key: id.key })).status).toBe(404);
    await runInDurableObject(stub, (_o, state) => state.storage.setAlarm(Date.now() + DAY));
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    const left = await runInDurableObject(stub, (_o, state) => state.storage.sql.exec("SELECT COUNT(*) AS n FROM invite").one().n);
    expect(left).toBe(0);
    const ns = env.INVITES_V2.jurisdiction("eu");
    const locator = ns.get(ns.idFromName(i.inviteId));
    await runInDurableObject(locator, async (_o, state) => {
      const r = await state.storage.get<Record<string, unknown>>("locator");
      await state.storage.put("locator", { ...r, expiresAt: Date.now() - 1 });
      await state.storage.setAlarm(Date.now() + DAY);
    });
    expect(await runDurableObjectAlarm(locator)).toBe(true);
    expect(await runInDurableObject(locator, (_o, state) => state.storage.get("locator"))).toBeUndefined();
    expect((await call("GET", `${i.publicPath}/offer`)).status).toBe(404);
  });
});

describe("v2 daily quotas and generations", () => {
  it("slides the per-credential window of 8 new records over any 24 h", async () => {
    const id = await setup();
    const now = Date.now();
    // Four stamps from 23 h ago and four from 1 h ago: the window is full.
    await editState(id, (m) => {
      m.credentials[0]!.records = [...Array<number>(4).fill(now - 23 * HOUR), ...Array<number>(4).fill(now - HOUR)];
    });
    const r = await put(id, withRecords(0, 1), 1);
    expect(r.status).toBe(429);
    expect(await json(r)).toEqual({ error: "too_many_records" });
    // A fixed window would wait a whole day; the sliding one frees a token in about an hour.
    const wait = Number(r.headers.get("Retry-After"));
    expect(wait).toBeGreaterThan(HOUR / 1000 - 60);
    expect(wait).toBeLessThanOrEqual(HOUR / 1000);
    await editState(id, (m) => {
      m.credentials[0]!.records = [...Array<number>(4).fill(now - 25 * HOUR), ...Array<number>(4).fill(now - HOUR)];
    });
    expect((await put(id, withRecords(0, 5), 1)).status).toBe(429);
    expect((await put(id, withRecords(0, 4), 1)).status).toBe(200);
    // Stamps outside the window are dropped: at most 8 per credential in the row.
    expect((await readState(id)).credentials[0]!.records).toHaveLength(8);
  });

  it("shares 16 new records per 24 h among every credential: extra credentials do not multiply it", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    const leo = await pair(id, "leo", 2);
    expect((await put(id, withRecords(0, 8), 3)).status).toBe(200);
    expect((await put(id, withRecords(0, 16), 4, nora.guestKey)).status).toBe(200);
    // Leo has spent none of his own 8, but the list has spent its 16.
    const r = await put(id, withRecords(0, 17), 5, leo.guestKey);
    expect(r.status).toBe(429);
    expect(await json(r)).toEqual({ error: "too_many_records" });
    expect(Number(r.headers.get("Retry-After"))).toBeGreaterThan(DAY / 1000 - 60);
    // Records already seen stay free for anyone.
    expect((await put(id, withRecords(0, 16), 5, leo.guestKey)).status).toBe(200);
    const state = await readState(id);
    expect(state.recordTimes).toHaveLength(16);
    expect(state.knownRecords).toHaveLength(17);
  });

  it("registers at most 8 credentials per list in any 24 h", async () => {
    const id = await setup();
    const now = Date.now();
    await editState(id, (m) => {
      m.approvals = [now - 25 * HOUR, ...Array<number>(7).fill(now - 2 * HOUR)];
    });
    // The stamp from 25 h ago no longer counts, so this is the 8th of the window.
    await pair(id, "nora", 1);
    const leo = await answered(id, "leo");
    const r = await approve(id, leo, 2);
    expect(r.status).toBe(429);
    expect(await json(r)).toEqual({ error: "too_many_approvals" });
    const wait = Number(r.headers.get("Retry-After"));
    expect(wait).toBeGreaterThan(22 * 3600 - 60);
    expect(wait).toBeLessThanOrEqual(22 * 3600);
    // Nothing was registered and the same invitation can be approved once there is room.
    expect((await readState(id)).credentials.map((c) => c.deviceId)).toEqual(["aritz", "nora"]);
    await editState(id, (m) => {
      m.approvals = m.approvals.map((t) => t - DAY);
    });
    expect((await approve(id, leo, 2)).status).toBe(200);
  });

  it("reports the capacity of the generation in the GET and refuses past its caps with generation_full", async () => {
    const id = await setup();
    const read = async () => (await json<{ capacity: unknown }>(await call("GET", id.path, { key: id.key }))).capacity;
    expect(await read()).toEqual(capacity(1, 1, false));
    // 48 credentials ever (revoked included) or 384 record declarations ask to renew.
    await editState(id, (m) => {
      for (let n = 1; n < 47; n++) m.credentials.push({ deviceId: `old${n}`, verifier: null, revoked: true, records: [] });
      m.knownRecords = Array.from({ length: 383 }, (_, n) => `hash${n}`);
    });
    expect(await read()).toEqual(capacity(47, 383, false));
    await editState(id, (m) => {
      m.credentials.push({ deviceId: "old47", verifier: null, revoked: true, records: [] });
    });
    expect(await read()).toEqual(capacity(48, 383, true));
    await editState(id, (m) => {
      m.credentials.pop();
      m.knownRecords.push("hash383");
    });
    expect(await read()).toEqual(capacity(47, 384, true));
    // At 512 the generation is full: a new declaration is refused, a known one is not.
    await editState(id, (m) => {
      m.knownRecords = Array.from({ length: 511 }, (_, n) => `hash${n}`);
    });
    expect((await put(id, withRecords(0, 1), 1)).status).toBe(200);
    const full = await put(id, withRecords(0, 2), 2);
    expect(full.status).toBe(409);
    expect(await json(full)).toEqual({ error: "generation_full" });
    expect((await put(id, withRecords(0, 1), 2)).status).toBe(200);
    expect(await read()).toEqual(capacity(47, 512, true));
  });
});

describe("v2 privacy retention", () => {
  it("B2 a new invitation extends its copy for 24 hours, capped at seven days from creation", async () => {
    const born = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(born);
      const id = await setup("aritz", true);
      const deadline = () => runInDurableObject(listStub(id.syncId), (_o, s) =>
        JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data).inviteCopyExpiresAt as number);
      for (let hour = 23; hour < 7 * 24; hour += 23) {
        const now = born + hour * HOUR;
        vi.setSystemTime(now);
        await invite(id);
        expect(await deadline()).toBe(Math.min(now + DAY, born + 7 * DAY));
      }
      vi.setSystemTime(born + 7 * DAY - 1);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      vi.setSystemTime(born + 7 * DAY);
      expect(await runDurableObjectAlarm(listStub(id.syncId))).toBe(true);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
      expect(await everythingStored(id.syncId)).toBe(MARKER);
    } finally { vi.useRealTimers(); }
  });

  it("stores activity only as an hourly upper bound, including legacy exact values", async () => {
    const id = await setup();
    await pair(id);
    const now = Math.floor(Date.now() / HOUR) * HOUR + 17 * 60_000;
    await editState(id, (m) => {
      (m.credentials[1] as unknown as { lastRequest: number }).lastRequest = now - 72 * HOUR;
    });
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(now);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      const m = await readState(id) as unknown as { credentials: { lastRequest: number }[] };
      expect(m.credentials.map((c) => c.lastRequest)).toEqual([Math.ceil(now / HOUR) * HOUR, Math.ceil(now / HOUR) * HOUR - 72 * HOUR]);
      // At 72 real hours, the rounded value still refuses premature exclusion.
      expect(now - m.credentials[1]!.lastRequest).toBeLessThan(72 * HOUR);
    } finally { vi.useRealTimers(); }
  });

  it.each([false, true])("privacy: removes revoked slots after 30 days without further requests (self=%s)", async (self) => {
    const id = await setup(), guest = await pair(id);
    await plant(id, [["person0", "nora"], ["person1", "aritz"]], 2);
    const now = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(now);
      expect((await call("POST", `${id.path}/revoke`, { key: self ? guest.guestKey : id.key, body: { deviceId: "nora" } })).status).toBe(200);
      const stub = listStub(id.syncId);
      const rows = () => runInDurableObject(stub, (_o, s) => s.storage.sql.exec<{ device: string }>("SELECT device FROM slot ORDER BY device").toArray());
      vi.setSystemTime(now + 30 * DAY - 1);
      await runDurableObjectAlarm(stub);
      expect(await rows()).toEqual([{ device: "aritz" }, { device: "nora" }]);
      expect(await runInDurableObject(stub, (_o, s) => s.storage.getAlarm())).toBe(now + 30 * DAY);
      vi.setSystemTime(now + 30 * DAY);
      await runDurableObjectAlarm(stub);
      expect(await rows()).toEqual([{ device: "aritz" }]);
      const response = await call("GET", id.path, { key: id.key });
      expect(response.status).toBe(200);
      expect(response.headers.get("ETag")).toBe('"4"');
      expect((await call("GET", `${id.path}/slots/person1/aritz`, { key: id.key, headers: { "If-Match": '"4"' } })).status).toBe(200);
    } finally { vi.useRealTimers(); }
  });

  it("keeps minute counters in memory without rate rows or short alarms", async () => {
    const id = await setup();
    expect((await put(id, snapshot(), 1)).status).toBe(200);
    await runInDurableObject(listStub(id.syncId), async (_o, state) => {
      expect(state.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'rate'").toArray()).toEqual([]);
      expect(await state.storage.getAlarm()).toBeGreaterThan(Date.now() + HOUR);
    });
  });

  it("privacy: dates legacy revoked slots on first wake without extending the grace", async () => {
    const id = await setup();
    await pair(id);
    await plant(id, [["person0", "nora"]], 2);
    await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } });
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      delete m.credentials[1].slotsExpireAt;
      s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
    });
    const now = Date.now();
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(now);
      await call("GET", id.path, { key: id.key });
      vi.setSystemTime(now + 30 * DAY - 1);
      await runDurableObjectAlarm(listStub(id.syncId));
      expect(await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.getAlarm())).toBe(now + 30 * DAY);
      vi.setSystemTime(now + 30 * DAY);
      await runDurableObjectAlarm(listStub(id.syncId));
      expect(await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.sql.exec("SELECT * FROM slot").toArray())).toEqual([]);
    } finally { vi.useRealTimers(); }
  });

  it("preserves a revoked writer's shared slots for surviving readers", async () => {
    const id = await setup(), guest = await pair(id);
    await plant(id, [["person0", "nora"], ["person1", "aritz"]], 2);
    const before = await call("GET", `${id.path}/slots/person0/nora`, { key: id.key, headers: { "If-Match": '"2"' } });
    expect(before.status).toBe(200);
    const data = (await json(before)).data;
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    const after = await call("GET", `${id.path}/slots/person0/nora`, { key: id.key, headers: { "If-Match": '"3"' } });
    expect(after.status).toBe(200);
    expect((await json(after)).data).toBe(data);
    expect((await call("GET", `${id.path}/slots/person0/nora`, { key: guest.guestKey, headers: { "If-Match": '"3"' } })).status).toBe(401);
  });

  it.each([false, true])("expires an invitation copy after its last invitation, or creation without one (%s)", async (open) => {
    const id = await setup("aritz", true);
    if (open) await invite(id);
    const deadline = await runInDurableObject(listStub(id.syncId), (_o, s) =>
      JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data).inviteCopyExpiresAt as number);
    expect(deadline).toBeLessThanOrEqual(Date.now() + DAY);
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(deadline! - 1);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      vi.setSystemTime(deadline!);
      expect(await runDurableObjectAlarm(listStub(id.syncId))).toBe(true);
      expect(await everythingStored(id.syncId)).toBe(MARKER);
      expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    } finally { vi.useRealTimers(); }
  });

  it("approval promotes an invitation copy; omitted flags preserve old clients' retention", async () => {
    for (const provisional of [false, true]) {
      const id = await setup("aritz", provisional);
      if (provisional) await pair(id);
      vi.useFakeTimers({ toFake: ["Date"] });
      try {
        vi.setSystemTime(Date.now() + 2 * DAY);
        expect(await runDurableObjectAlarm(listStub(id.syncId))).toBe(true);
        expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
      } finally { vi.useRealTimers(); }
    }
  });

  it("dates a legacy bare retirement marker on first wake without reviving it", async () => {
    const id = await setup();
    await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } });
    await runInDurableObject(listStub(id.syncId), async (_o, s) => { await s.storage.delete("retiredUntil"); await s.storage.deleteAlarm(); });
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    const deadline = await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.getAlarm());
    expect(deadline).toBeGreaterThan(Date.now() + 399 * DAY);
    expect(await everythingStored(id.syncId)).toBe(MARKER);
  });
});

describe("v2 deletion retires the syncId", () => {
  it("erases everything on DELETE and refuses create for exactly 400 days", async () => {
    const id = await setup();
    const nora = await pair(id);
    expect((await put(id, { ...withRecords(0, 2), keyPackages: [{ v: 3, from: "aritz", c: "x" }], slots: [slot(0)] }, 2)).status).toBe(200);
    const pending = await invite(id, "leo");
    await lastPhone(id);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"3"' } })).status).toBe(204);

    // Content, registry, packages, slots, invitations, credentials, tombstones and hashes: gone.
    const stored = await everythingStored(id.syncId);
    expect(stored).toBe(MARKER);
    for (const kept of [await digest(id.key), await digest(nora.guestKey), "aritz", "nora", "device0", id.syncId]) expect(stored).not.toContain(kept);
    const stub = listStub(id.syncId);
    const deadline = await runInDurableObject(stub, (_o, s) => s.storage.getAlarm());
    expect(deadline).toBeGreaterThan(Date.now() + 399 * DAY);

    // Every route answers as for an unknown list; creating it again is 410, with any credential.
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    expect((await openSocket(id, id.key)).status).toBe(404);
    expect((await call("GET", `${pending.publicPath}/offer`)).status).toBe(404);
    const create = (key: string) => call("PUT", id.path, { key, headers: { "If-Match": '"0"' }, body: { ...creation("aritz"), deviceId: "aritz" } });
    for (const key of [id.key, nora.guestKey, b64u(rand(32))]) {
      const r = await create(key);
      expect(r.status).toBe(410);
      expect(await json(r)).toEqual({ error: "retired" });
    }

    // Reads, rejected creates and an early alarm never extend the deadline.
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(deadline! - 1);
      expect(await runDurableObjectAlarm(stub)).toBe(true);
      expect((await create(b64u(rand(32)))).status).toBe(410);
      expect(await runInDurableObject(stub, (_o, s) => s.storage.getAlarm())).toBe(deadline);
      vi.setSystemTime(deadline!);
      expect(await runDurableObjectAlarm(stub)).toBe(true);
      expect(await everythingStored(id.syncId)).toBe("");
      expect(await runInDurableObject(stub, async (_o, s) => ({ size: (await s.storage.list()).size, alarm: await s.storage.getAlarm() }))).toEqual({ size: 0, alarm: null });
      expect((await create(b64u(rand(32)))).status).toBe(201);
    } finally {
      vi.useRealTimers();
    }
  });

  it("retires a list after 400 days without access, on a request or on its alarm", async () => {
    for (const via of ["request", "alarm"] as const) {
      const id = await setup();
      await pair(id);
      await editState(id, (m) => {
        m.lastAccess = Date.now() - 400 * DAY;
      });
      if (via === "alarm") {
        const stub = listStub(id.syncId);
        await runInDurableObject(stub, (_o, s) => s.storage.setAlarm(Date.now() + DAY));
        expect(await runDurableObjectAlarm(stub)).toBe(true);
      } else {
        expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
      }
      expect(await everythingStored(id.syncId), via).toBe(MARKER);
      const again = await call("PUT", id.path, { key: id.key, headers: { "If-Match": '"0"' }, body: { ...creation("aritz"), deviceId: "aritz" } });
      expect(again.status, via).toBe(410);
    }
  });

  it("treats a legacy `deleted` row, or one missing a field of this format, as retired (finding 17)", async () => {
    const variants: [string, (m: State & Record<string, unknown>) => void][] = [
      ["deleted marker", (m) => void (m.deleted = true)],
      ["no recordTimes", (m) => void delete (m as Partial<State>).recordTimes],
      ["no approvals", (m) => void delete (m as Partial<State>).approvals],
      ["credential without records", (m) => void delete (m.credentials[0] as Partial<State["credentials"][0]>).records],
    ];
    for (const [name, edit] of variants) {
      const id = await setup();
      const nora = await pair(id);
      expect((await put(id, { ...snapshot([slot(0)]), keyPackages: [{ v: 3, from: "aritz", c: "x" }] }, 2)).status, name).toBe(200);
      await editState(id, edit as (m: State) => void);
      // Neither the old credential nor a guest gets anything; the content is wiped.
      expect((await call("GET", id.path, { key: id.key })).status, name).toBe(404);
      expect((await call("GET", id.path, { key: nora.guestKey })).status, name).toBe(404);
      expect(await everythingStored(id.syncId), name).toBe(MARKER);
      const again = await call("PUT", id.path, { key: b64u(rand(32)), headers: { "If-Match": '"0"' }, body: { ...creation("leo"), deviceId: "leo" } });
      expect(again.status, name).toBe(410);
      expect(await json(again), name).toEqual({ error: "retired" });
    }
    // A row that is not even JSON is retired too, on the socket route as well.
    const id = await setup();
    await runInDurableObject(listStub(id.syncId), (_o, s) => void s.storage.sql.exec("UPDATE state SET data = ?", "{not json"));
    expect((await openSocket(id, id.key)).status).toBe(404);
    expect(await everythingStored(id.syncId)).toBe(MARKER);
  });
});

describe("v2 jurisdiction, quotas and HTTP boundary", () => {
  it("selects the EU jurisdiction for list, invitation and limiter namespaces", async () => {
    const id = await setup();
    const i = await invite(id);
    const seen: string[] = [];
    const ns = <T extends { jurisdiction: (j: DurableObjectJurisdiction) => unknown }>(name: string, binding: T) => ({
      jurisdiction: vi.fn((j: DurableObjectJurisdiction) => {
        seen.push(`${name}:${j}`);
        return binding.jurisdiction(j);
      }),
      idFromName: () => {
        throw new Error(`${name} used without a jurisdiction`);
      },
    });
    const fake = { ...env, LISTS_V2: ns("list", env.LISTS_V2), INVITES_V2: ns("invite", env.INVITES_V2), LIMITER_V2: ns("limiter", env.LIMITER_V2) } as unknown as Env;
    expect((await worker.fetch(new Request(`https://sync.test${i.publicPath}/offer`), fake)).status).toBe(200);
    // The per-IP invitation limit is a rate limit binding now (no object, no row).
    expect(seen).toEqual(["invite:eu", "list:eu"]);
    seen.length = 0;
    const fresh = newList();
    const created = await worker.fetch(
      new Request(`https://sync.test/v2/lists/${fresh.syncId}`, {
        method: "PUT",
        headers: { Authorization: `Bearer ${fresh.key}`, "If-Match": '"0"', "Content-Type": "application/json", "CF-Connecting-IP": fresh.ip },
        body: JSON.stringify({ ...creation("aritz"), deviceId: "aritz" }),
      }),
      fake,
    );
    expect(created.status).toBe(201);
    expect(seen).toEqual(["list:eu"]);
  });

  it("limits requests per credential and invitation requests per IP, with Retry-After", async () => {
    const id = await setup();
    for (let n = 0; n < 120; n++) expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    const r = await call("GET", id.path, { key: id.key });
    expect(r.status).toBe(429);
    expect(r.headers.get("Retry-After")).toBeTruthy();
    const other = await setup();
    const i = await invite(other);
    for (let n = 0; n < 30; n++) expect((await call("GET", `${i.publicPath}/offer`, { ip: other.ip })).status).toBe(200);
    const q = await call("GET", `${i.publicPath}/offer`, { ip: other.ip });
    expect(q.status).toBe(429);
    expect(q.headers.get("Retry-After")).toBeTruthy();
  });

  it("limits mutations per credential and new lists per IP, and keeps first uploads small", async () => {
    const id = await setup();
    for (let n = 1; n <= 30; n++) expect((await put(id, snapshot(), n)).status).toBe(200);
    expect((await put(id, snapshot(), 31)).status).toBe(429);
    const fresh = newList();
    const create = (body: unknown) => call("PUT", `/v2/lists/${b64u(rand(16))}`, { key: fresh.key, ip: fresh.ip, headers: { "If-Match": '"0"' }, body });
    expect((await create({ ...creation("aritz"), deviceId: "aritz", common: "A".repeat(300000) })).status).toBe(413);
    // The rejected oversized creation already spent one IP attempt.
    for (let n = 0; n < V2_NEW_LISTS_PER_HOUR - 1; n++) expect((await create({ ...creation("aritz"), deviceId: "aritz" })).status).toBe(201);
    expect((await create({ ...creation("aritz"), deviceId: "aritz" })).status).toBe(429);
  });

  it("resets minute counters after a restart without persisting any row", async () => {
    const id = await setup();
    for (let n = 0; n < V2_CREDENTIAL_REQUESTS; n++) expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect((await call("GET", id.path, { key: id.key })).status).toBe(429);
    await runInDurableObject(listStub(id.syncId), async (instance, state) => {
      const fresh = new ListV2Object(state, env) as unknown as { hit(key: string, max: number): Promise<boolean> };
      expect(await fresh.hit("r:aritz", V2_CREDENTIAL_REQUESTS)).toBe(true);
      (instance as unknown as { rate: Map<string, unknown> }).rate.clear();
      expect(state.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE name = 'rate'").toArray()).toEqual([]);
    });
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
  }, 20_000);

  it("retains mutation limits in memory and resets them on restart", async () => {
    const id = await setup();
    for (let v = 1; v <= 30; v++) expect((await put(id, snapshot(), v)).status).toBe(200);
    expect((await put(id, snapshot(), 31)).status).toBe(429);
    await runInDurableObject(listStub(id.syncId), (instance) => {
      (instance as unknown as { rate: Map<string, unknown> }).rate.clear();
    });
    expect((await put(id, snapshot(), 31)).status).toBe(200);
  }, 30_000);

  it("DELETE is refused with 409 while another credential is live (server guard)", async () => {
    const id = await setup();
    await pair(id);
    const refused = await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"2"' } });
    expect(refused.status).toBe(409);
    expect((await json(refused)).error).toBe("devices_active");
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"3"' } })).status).toBe(204);
  });

  it("finding 16: phones behind one NAT can pair at once; each invitation keeps its own budget", async () => {
    const ip = randomIp();
    const a = await setup();
    const b = await setup();
    const ia = await invite(a);
    const ib = await invite(b);
    // Two families, same address: more than v1's 30/min per IP in total.
    for (let n = 0; n < V2_INVITE_REQUESTS_PER_INVITE; n++) {
      expect((await call("GET", `${ia.publicPath}/offer`, { ip })).status).toBe(200);
      expect((await call("GET", `${ib.publicPath}/offer`, { ip })).status).toBe(200);
    }
    // One invitation cannot go past its own budget, from any address.
    expect((await call("GET", `${ia.publicPath}/offer`, { ip: randomIp() })).status).toBe(429);
    // A third family on that address still gets in.
    const ic = await invite(await setup());
    expect((await call("GET", `${ic.publicPath}/offer`, { ip })).status).toBe(200);
  }, 20_000);

  it("finding 16: the per-IP ceiling on v2 invitation routes still holds", async () => {
    const ip = randomIp();
    const fresh = await invite(await setup());
    // The real edge binding has UTC minute windows. Fill it directly so this
    // admission test is independent of the duration of 120 list-object RPCs.
    for (let n = 0; n < V2_INVITE_REQUESTS_PER_IP - 1; n++) expect((await env.INVITE_IP_LIMITER.limit({ key: ip })).success).toBe(true);
    expect((await call("GET", `${fresh.publicPath}/offer`, { ip })).status).toBe(200);
    const refused = await call("GET", `${fresh.publicPath}/offer`, { ip });
    expect(refused.status).toBe(429);
    expect(refused.headers.get("Retry-After")).toBeTruthy();
  }, 20_000);

  it("authenticates a large PUT before consuming its body", async () => {
    const id = await setup();
    for (const suffix of ["", "/common"]) {
      const pull = vi.fn(() => { throw new Error("Unauthenticated body consumed"); });
      const body = new ReadableStream<Uint8Array>({ pull }, { highWaterMark: 0 });
      const response = await worker.fetch(new Request(`https://sync.test${id.path}${suffix}`, {
        method: "PUT", headers: { Authorization: `Bearer ${b64u(rand(32))}`, "If-Match": '\"1\"', "Content-Type": "application/json" }, body,
      }), env);
      expect(response.status).toBe(401);
      expect(pull).not.toHaveBeenCalled();
    }
    expect((await put(id, { ...snapshot(), common: "A".repeat(V2_MAX_BODY_BYTES) }, 1)).status).toBe(413);
    const fresh = newList();
    expect((await call("PUT", `/v2/lists/${fresh.syncId}`, { key: fresh.key, headers: { "If-Match": '\"0\"' }, body: { ...creation("aritz"), deviceId: "aritz", common: "A".repeat(V2_MAX_CREATE_BODY_BYTES) } })).status).toBe(413);
  });

  it("accepts the largest real PUT: full common, registry and packages and 10 full own slots", async () => {
    const long = (c: string, n = 0) => `${c}${n}`.padEnd(128, c);
    const id = await setup(long("d"));
    await byteCapacity(id, 5);
    const slots = Array.from({ length: V2_MAX_SLOTS_PER_PUT }, (_, n) => ({
      personId: long("p", n),
      deviceId: long("d"),
      data: sealed(long("p", n), long("d"), { listId: long("l"), tail: SLOT_TAIL }),
    }));
    for (const s of slots) expect(decodeB64Url(s.data)!.length).toBe(V2_MAX_SLOT_BYTES);
    const largest = Math.floor((MAX_ENVELOPE_BYTES * 4) / 3);
    const body = {
      ...snapshot(slots),
      common: "A".repeat(largest),
      registry: { ...registry(), pad: "x".repeat(V2_MAX_REGISTRY_BYTES - 200) },
      keyPackages: Array.from({ length: V2_MAX_PACKAGES_PER_WRITER }, (_, n) => ({ v: 3, from: long("d"), n, c: "x".repeat(300) })),
    };
    expect(validateSnapshot(body)).toBeNull();
    const size = new TextEncoder().encode(JSON.stringify(body)).length;
    // One writer carries at most a quarter of the packages (B3).
    expect(size).toBeGreaterThan(4.6 * 1024 * 1024);
    expect(size).toBeLessThanOrEqual(V2_MAX_BODY_BYTES);
    expect((await put(id, body, 1)).status).toBe(200);
  });

  it("refuses a body over the streaming limit before parsing it", async () => {
    const id = await setup();
    const r = await call("POST", `${id.path}/revoke`, { key: id.key, rawBody: JSON.stringify({ deviceId: "nora", pad: "x".repeat(2048) }) });
    expect(r.status).toBe(413);
  });

  it("forwards only internal headers to the socket and closes a read-only channel", async () => {
    const id = await setup();
    const stub = listStub(id.syncId);
    await runInDurableObject(stub, (instance) => {
      const original = instance.fetch.bind(instance);
      instance.fetch = async (request: Request) => {
        (instance as unknown as { seen: string[] }).seen = [...request.headers.keys()];
        return original(request);
      };
    });
    const response = await exports.default.fetch(
      new Request(`https://sync.test${id.path}/ws`, {
        headers: { Upgrade: "websocket", Authorization: `Bearer ${id.key}`, Cookie: "secret", "X-Private": "secret", "Sec-WebSocket-Protocol": `gift-huddle.v2, bearer.${id.key}` },
      }),
    );
    expect(response.status).toBe(101);
    const seen = await runInDurableObject(stub, (instance) => (instance as unknown as { seen: string[] }).seen);
    expect(seen.sort()).toEqual(["upgrade", "x-verifier", "x-ws-protocol"]);
    const ws = response.webSocket!;
    ws.accept();
    const closed = new Promise<CloseEvent>((resolve) => ws.addEventListener("close", resolve));
    ws.addEventListener("close", () => ws.close());
    ws.send("write");
    expect((await closed).code).toBe(1008);
  });

  it("closes every socket with 4404 when the list is deleted", async () => {
    const id = await setup();
    const ws = (await openSocket(id, id.key)).webSocket!;
    ws.accept();
    const closed = new Promise<CloseEvent>((resolve) => ws.addEventListener("close", resolve));
    ws.addEventListener("close", () => ws.close());
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"1"' } })).status).toBe(204);
    expect((await closed).code).toBe(4404);
    expect((await openSocket(id, id.key)).status).toBe(404);
  });

  it("preflights If-Match without touching bindings and rejects foreign origins", async () => {
    const id = newList();
    const touch = vi.fn(() => {
      throw Error("binding used");
    });
    const fake = { IP_LIMITER: { limit: touch } } as unknown as Env;
    const res = await worker.fetch(
      new Request(`https://sync.test/v2/lists/${id.syncId}`, {
        method: "OPTIONS",
        headers: { Origin: "https://gifthuddle.app", "Access-Control-Request-Method": "PUT", "Access-Control-Request-Headers": "authorization,if-match,content-type" },
      }),
      fake,
    );
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("If-Match");
    expect(touch).not.toHaveBeenCalled();
    // gifthuddle.app is now allowed; lookalikes and explicit ports are not.
    for (const Origin of ["https://evil.example", "https://gifthuddle.app.example.com", "https://gifthuddle.retired.example.example.com", "https://gifthuddle.app:443", "https://gifthuddle.retired.example:443"]) {
      for (const method of ["OPTIONS", "GET"]) {
        const blocked = await worker.fetch(new Request(`https://sync.test/v2/lists/${id.syncId}`, {
          method,
          headers: { Origin, "Access-Control-Request-Method": "PUT", "Access-Control-Request-Headers": "authorization,if-match,content-type" },
        }), fake);
        expect(blocked.status).toBe(403);
        expect(blocked.headers.get("Access-Control-Allow-Origin")).toBeNull();
      }
    }
    expect(touch).not.toHaveBeenCalled();
  });
});

describe("B2: no device touches another writer's slot", () => {
  const manifest = async (id: Setup) => (await json<{ slots: unknown[] }>(await call("GET", id.path, { key: id.key }))).slots;
  const version = async (id: Setup) => (await json<{ version: number }>(await call("GET", id.path, { key: id.key }))).version;

  /**
   * Aritz (the creator) writes person0/aritz, Leo writes person1/leo, Nora is
   * the would-be attacker. The server knows nothing of persons or epochs: a
   * deleted person's or an old epoch's slot is just another writer's resource.
   */
  async function family() {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    const leo = await pair(id, "leo", 2);
    expect((await put(id, snapshot([slot(0)]), 3)).status).toBe(200);
    expect((await put(id, snapshot([slot(1, "leo")]), 4, leo.guestKey)).status).toBe(200);
    return { id, nora, leo };
  }

  const cases = [
    ["an active writer", "person0", "aritz"],
    ["a revoked writer", "person1", "leo"],
    ["an orphan writer with no credential", "person2", "ghost"],
    ["a deleted person", "deleted-person", "aritz"],
    ["an old epoch", "person3", "aritz"],
  ] as const;

  it.each(cases.flatMap(([what, personId, deviceId]) => [
    [what, personId, deviceId, "data: null"],
    [what, personId, deviceId, "data"],
  ] as const))("refuses a delta on the slot of %s (%s/%s) with %s", async (what, personId, deviceId, kind) => {
    const { id, nora } = await family();
    if (what === "a revoked writer") {
      expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "leo" } })).status).toBe(200);
    } else if (what !== "an active writer") {
      await plant(id, [[personId, deviceId]], await version(id));
    }
    const v = await version(id);
    const before = await manifest(id);
    const data = kind === "data" ? sealed(personId, deviceId) : null;
    const r = await put(id, snapshot([{ personId, deviceId, data }]), v, nora.guestKey);
    expect(r.status).toBe(403);
    expect(await json(r)).toEqual({ error: "forbidden_slot" });
    expect(await version(id)).toBe(v);
    expect(await manifest(id)).toEqual(before);
  });

  it("refuses a mixed delta (own plus foreign) with no partial effect", async () => {
    const { id, nora } = await family();
    const v = await version(id);
    const before = await json(await call("GET", id.path, { key: id.key }));
    for (const foreign of [slot(0, "aritz", null), slot(0, "aritz")]) {
      const r = await put(id, { ...snapshot([slot(5, "nora"), foreign]), common: "BBBB" }, v, nora.guestKey);
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_slot" });
      // Order does not matter either: the whole delta is checked first.
      expect((await put(id, { ...snapshot([foreign, slot(5, "nora")]), common: "BBBB" }, v, nora.guestKey)).status).toBe(403);
    }
    expect(await json(await call("GET", id.path, { key: id.key }))).toEqual(before);
  });

  it("refuses duplicated resources in one delta before writing anything", async () => {
    const { id, nora } = await family();
    const v = await version(id);
    const before = await manifest(id);
    for (const pair of [
      [slot(5, "nora"), slot(5, "nora")],
      [slot(5, "nora"), slot(5, "nora", null)],
      [slot(5, "nora", null), slot(5, "nora")],
    ]) {
      const r = await put(id, snapshot(pair), v, nora.guestKey);
      expect(r.status).toBe(400);
      expect(await json(r)).toEqual({ error: "bad_request" });
    }
    expect(await version(id)).toBe(v);
    expect(await manifest(id)).toEqual(before);
  });

  it("replaces its own slot atomically: a refused write keeps the old one, an accepted one swaps it in place", async () => {
    const { id } = await family();
    const v = await version(id);
    const old = sealed("person0", "aritz");
    const fresh = sealed("person0", "aritz", { fill: 7 });
    // The replacement fails a later check (a new record over the daily budget): nothing changes.
    const s = { ...snapshot([{ personId: "person0", deviceId: "aritz", data: fresh }]) };
    s.registry.records = Array.from({ length: 9 }, (_, n) => ({ d: `device${n}` }));
    expect((await put(id, s, v)).status).toBe(429);
    const kept = await call("GET", `${id.path}/slots/person0/aritz`, { key: id.key, headers: { "If-Match": `"${v}"` } });
    expect((await json<{ data: string }>(kept)).data).toBe(old);
    // An accepted replacement is one row update: the slot is never missing.
    expect((await put(id, snapshot([{ personId: "person0", deviceId: "aritz", data: fresh }]), v)).status).toBe(200);
    const swapped = await call("GET", `${id.path}/slots/person0/aritz`, { key: id.key, headers: { "If-Match": `"${v + 1}"` } });
    expect(await json(swapped)).toEqual({ version: v + 1, slotVersion: v + 1, data: fresh });
  });

  it("applies the same rule when creating a list", async () => {
    for (const foreign of [slot(0, "nora", null), slot(0, "nora")]) {
      const id = { ...newList(), deviceId: "aritz" };
      const r = await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: { ...snapshot([slot(1), foreign]), deviceId: "aritz" } });
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_slot" });
      expect((await call("GET", `/v2/lists/${id.syncId}`, { key: id.key })).status).toBe(404);
    }
    const id = { ...newList(), deviceId: "aritz" };
    const own = await call("PUT", `/v2/lists/${id.syncId}`, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: { ...creation("aritz", snapshot([slot(1), slot(2, "aritz", null)])), deviceId: "aritz" } });
    expect(own.status).toBe(201);
  });

  it("treats a deviceId that differs only in case as another writer", async () => {
    const { id, nora } = await family();
    const v = await version(id);
    for (const change of [slot(0, "Nora"), slot(0, "Nora", null), slot(0, "ARITZ", null)]) {
      const r = await put(id, snapshot([change]), v, nora.guestKey);
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_slot" });
    }
  });

  it("a revoked credential cannot remove even its own slot (401)", async () => {
    const { id, leo } = await family();
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "leo" } })).status).toBe(200);
    const v = await version(id);
    expect((await put(id, snapshot([slot(1, "leo", null)]), v, leo.guestKey)).status).toBe(401);
    expect(await manifest(id)).toContainEqual({ personId: "person1", deviceId: "leo", version: 5 });
  });

  it("refuses to approve a device id that already has slot rows", async () => {
    const id = await setup();
    await plant(id, [["person0", "nora"]]);
    const i = await answered(id, "nora");
    const r = await approve(id, i, 1);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "credential_exists" });
  });

  it("never lets a web credential write a slot, not even under its own name", async () => {
    const id = await setup();
    const web = await webPair(id);
    for (const change of [slot(0, "nora"), slot(0, "nora", null), slot(0, "aritz", null)]) {
      const r = await put(id, snapshot([change]), 2, web.guestKey);
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_role" });
    }
    expect(await version(id)).toBe(2);
  });

  it("reports slot pressure in capacity: abandoned slots still count and ask to renew from the warning", async () => {
    const id = await setup();
    const read = async () => (await json<{ capacity: unknown }>(await call("GET", id.path, { key: id.key }))).capacity;
    const below = V2_LEGACY_WARN_SLOTS - 1;
    await plant(id, Array.from({ length: below }, (_, n) => [`person${n}`, `gone${n}`] as [string, string]));
    expect(await read()).toEqual(capacity(1, 1, false, below));
    await plant(id, [[`person${below}`, `gone${below}`]]);
    expect(await read()).toEqual(capacity(1, 1, true, V2_LEGACY_WARN_SLOTS));
  });
});

describe("B2: conditional revocation", () => {
  it("answers 412 to a stale If-Match and revokes with the current one", async () => {
    const id = await setup();
    await pair(id, "nora", 1);
    // Someone writes between the phone's GET (version 2) and its POST.
    expect((await put(id, { ...snapshot(), common: "BBBB" }, 2)).status).toBe(200);
    const stale = await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": '"2"' }, body: { deviceId: "nora" } });
    expect(stale.status).toBe(412);
    expect(stale.headers.get("ETag")).toBe('"3"');
    expect(await json(stale)).toEqual({ error: "precondition_failed" });
    const devices = async () => (await json<{ devices: { deviceId: string; revoked: boolean }[] }>(await call("GET", id.path, { key: id.key }))).devices;
    expect((await devices()).find((d) => d.deviceId === "nora")!.revoked).toBe(false);
    for (const bad of ["*", 'W/"3"', '"3", "4"']) {
      expect((await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": bad }, body: { deviceId: "nora" } })).status).toBe(412);
    }
    const ok = await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": '"3"' }, body: { deviceId: "nora" } });
    expect(ok.status).toBe(200);
    expect(ok.headers.get("ETag")).toBe('"4"');
    expect((await devices()).find((d) => d.deviceId === "nora")!.revoked).toBe(true);
  });

  it("with a current If-Match: an already revoked target is 200 with the same version, an unknown one 404", async () => {
    const id = await setup();
    await pair(id, "nora", 1);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": '"2"' }, body: { deviceId: "nora" } })).status).toBe(200);
    const again = await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": '"3"' }, body: { deviceId: "nora" } });
    expect(again.status).toBe(200);
    expect(again.headers.get("ETag")).toBe('"3"');
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, headers: { "If-Match": '"3"' }, body: { deviceId: "nobody" } })).status).toBe(404);
  });

  it("without a precondition revokes as before: unconditional and idempotent", async () => {
    const id = await setup();
    await pair(id, "nora", 1);
    expect((await put(id, { ...snapshot(), common: "BBBB" }, 2)).status).toBe(200);
    const r = await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } });
    expect(r.status).toBe(200);
    expect(r.headers.get("ETag")).toBe('"4"');
    const again = await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } });
    expect(again.status).toBe(200);
    expect(again.headers.get("ETag")).toBe('"4"');
  });
});

describe("B3: key packages belong to their writer", () => {
  const packages = async (id: Setup) => (await json<{ keyPackages: unknown[] }>(await call("GET", id.path, { key: id.key }))).keyPackages;
  const version = async (id: Setup) => (await json<{ version: number }>(await call("GET", id.path, { key: id.key }))).version;

  it("refuses a new entry in another device's name or without `from`, with no partial effect", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    expect((await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 1 }] }, 2)).status).toBe(200);
    const v = await version(id);
    for (const planted of [{ v: 3, from: "aritz", n: 2 }, { v: 3, from: "leo", n: 3 }, { n: 4 }, "junk"]) {
      const r = await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 1 }, { v: 3, from: "nora", n: 5 }, planted] }, v, nora.guestKey);
      expect(r.status).toBe(403);
      expect(await json(r)).toEqual({ error: "forbidden_package" });
    }
    expect(await version(id)).toBe(v);
    expect(await packages(id)).toEqual([{ v: 3, from: "aritz", n: 1 }]);
  });

  it("keeps stored entries of others forwarded unchanged and lets anyone drop entries", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    expect((await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 1 }] }, 2)).status).toBe(200);
    // Nora forwards Aritz's entry as it is and adds her own.
    expect((await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 1 }, { v: 3, from: "nora", n: 2 }] }, 3, nora.guestKey)).status).toBe(200);
    // Touching one byte of Aritz's entry makes it a new entry in his name.
    const r = await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 9 }, { v: 3, from: "nora", n: 2 }] }, 4, nora.guestKey);
    expect(r.status).toBe(403);
    // Dropping is allowed (an older app trims, a sender retires its own).
    expect((await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "nora", n: 2 }] }, 4)).status).toBe(200);
    expect(await packages(id)).toEqual([{ v: 3, from: "nora", n: 2 }]);
  });

  it("refuses new entries from a web credential", async () => {
    const id = await setup();
    const web = await webPair(id, "nora", 1);
    const r = await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "nora", n: 1 }] }, 2, web.guestKey);
    expect(r.status).toBe(403);
  });

  it("caps one writer's entries so a flood cannot fill the list", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    const own = (from: string, n: number, base = 0) => Array.from({ length: n }, (_, i) => ({ v: 4, from, n: base + i }));
    expect((await put(id, { ...snapshot(), keyPackages: own("aritz", 3) }, 2)).status).toBe(200);
    const flood = await put(id, { ...snapshot(), keyPackages: [...own("aritz", 3), ...own("nora", V2_MAX_PACKAGES_PER_WRITER + 1)] }, 3, nora.guestKey);
    expect(flood.status).toBe(413);
    expect(await json(flood)).toEqual({ error: "too_many_writer_packages" });
    expect((await put(id, { ...snapshot(), keyPackages: [...own("aritz", 3), ...own("nora", V2_MAX_PACKAGES_PER_WRITER)] }, 3, nora.guestKey)).status).toBe(200);
    // At the cap, a writer can still replace its own entries one for one.
    const swapped = [...own("aritz", 3), ...own("nora", V2_MAX_PACKAGES_PER_WRITER, 1000)];
    expect((await put(id, { ...snapshot(), keyPackages: swapped }, 4, nora.guestKey)).status).toBe(200);
    // Others still have room for their own: the rotation is not blocked.
    expect((await put(id, { ...snapshot(), keyPackages: [...swapped, ...own("aritz", 2, 50)] }, 5)).status).toBe(200);
  });

  it("refuses a new entry whose `v` is not 3 or 4", async () => {
    const id = await setup();
    for (const v of [undefined, 1, 2, 5, "4", 4.5]) {
      const r = await put(id, { ...snapshot(), keyPackages: [{ v, from: "aritz", n: 1 }] }, 1);
      expect(r.status, String(v)).toBe(400);
      expect(await json(r)).toEqual({ error: "bad_package" });
    }
    expect((await put(id, { ...snapshot(), keyPackages: [{ v: 3, from: "aritz", n: 1 }, { v: 4, from: "aritz", n: 2 }] }, 1)).status).toBe(200);
  });

  it("caps v3 and v4 together per writer, so two writers at the cap cannot block a third's rotation", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    const leo = await pair(id, "leo", 2);
    const own = (from: string, n: number, v = 3, base = 0) => Array.from({ length: n }, (_, i) => ({ v, from, n: base + i }));
    const half = V2_MAX_PACKAGES_PER_WRITER / 2;
    // Mixing kinds does not double the cap.
    const mixed = await put(id, { ...snapshot(), keyPackages: [...own("nora", half, 3), ...own("nora", half + 1, 4, 500)] }, 3, nora.guestKey);
    expect(mixed.status).toBe(413);
    expect(await json(mixed)).toEqual({ error: "too_many_writer_packages" });
    const n = own("nora", V2_MAX_PACKAGES_PER_WRITER);
    expect((await put(id, { ...snapshot(), keyPackages: n }, 3, nora.guestKey)).status).toBe(200);
    const l = own("leo", V2_MAX_PACKAGES_PER_WRITER, 4);
    expect((await put(id, { ...snapshot(), keyPackages: [...n, ...l] }, 4, leo.guestKey)).status).toBe(200);
    // Aritz still has his whole quarter for a rotation.
    const a = own("aritz", V2_MAX_PACKAGES_PER_WRITER, 4);
    expect((await put(id, { ...snapshot(), keyPackages: [...n, ...l, ...a] }, 5)).status).toBe(200);
    expect(await packages(id)).toHaveLength(3 * V2_MAX_PACKAGES_PER_WRITER);
  });

  it("caps the bytes of one writer's packages", async () => {
    const id = await setup();
    const big = (n: number, pad: number) => Array.from({ length: n }, (_, i) => ({ v: 4, from: "aritz", n: i, x: "x".repeat(pad) }));
    // 16 entries of ~4.1 KiB: few entries, over the writer's byte cap.
    const r = await put(id, { ...snapshot(), keyPackages: big(16, 4200) }, 1);
    expect(r.status).toBe(413);
    expect(await json(r)).toEqual({ error: "too_many_writer_packages" });
    expect((await put(id, { ...snapshot(), keyPackages: big(16, Math.floor(V2_MAX_PACKAGE_BYTES_PER_WRITER / 16) - 60) }, 1)).status).toBe(200);
  });

  it("refuses duplicated entries, of a stored foreign package or of one's own, before writing anything", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    const aritz = { v: 3, from: "aritz", n: 1 };
    expect((await put(id, { ...snapshot(), keyPackages: [aritz] }, 2)).status).toBe(200);
    const v = await version(id);
    // Copies of a stored entry would skip the `from` check and the cap.
    const copies = Array.from({ length: 500 }, () => aritz);
    for (const keyPackages of [copies, [aritz, { v: 3, from: "nora", n: 2 }, { v: 3, from: "nora", n: 2 }]]) {
      const r = await put(id, { ...snapshot(), keyPackages }, v, nora.guestKey);
      expect(r.status).toBe(400);
      expect(await json(r)).toEqual({ error: "duplicate_package" });
    }
    const own = await put(id, { ...snapshot(), keyPackages: [aritz, aritz] }, v);
    expect(own.status).toBe(400);
    expect(await version(id)).toBe(v);
    expect(await packages(id)).toEqual([aritz]);
  });

  it("refuses a create whose packages are not the creator's", async () => {
    const fresh = newList();
    const r = await call("PUT", `/v2/lists/${fresh.syncId}`, {
      key: fresh.key,
      ip: fresh.ip,
      headers: { "If-Match": '"0"' },
      body: { ...creation("aritz"), deviceId: "aritz", keyPackages: [{ v: 3, from: "leo", n: 1 }] },
    });
    expect(r.status).toBe(403);
    expect(await json(r)).toEqual({ error: "forbidden_package" });
  });
});

describe("B4: common format cut-over", () => {
  /** An "RG" envelope prefix with `format` and an opaque body. */
  const rg = (format: number, n = 32) => {
    const out = rand(n + 3);
    out.set([0x52, 0x47, format]);
    return b64u(out);
  };
  const snap = (format = 1) => ({ ...snapshot(), common: rg(format) });
  const state = async (id: Setup) =>
    json<{ version: number; common: string; minCommonFormat?: number; devices: { deviceId: string; commonFormat?: number }[] }>(
      await call("GET", id.path, { key: id.key }),
    );
  const announce = (id: Setup, key: string, body: unknown = { commonFormat: 2 }) => call("POST", `${id.path}/capability`, { key, body });

  it("announces a capability per credential, monotonic and idempotent, also from webs (B5)", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    expect((await state(id)).devices.every((d) => d.commonFormat === undefined)).toBe(true);
    for (const bad of [{}, { commonFormat: 1 }, { commonFormat: 3 }, { commonFormat: "2" }, { commonFormat: 2, x: 1 }]) {
      expect((await announce(id, nora.guestKey, bad)).status, JSON.stringify(bad)).toBe(400);
    }
    const first = await announce(id, nora.guestKey);
    expect(first.status).toBe(200);
    const v = (await json<{ version: number }>(first)).version;
    expect(v).toBe(3);
    // Again: nothing changes and the version stays.
    expect((await json<{ version: number }>(await announce(id, nora.guestKey))).version).toBe(v);
    const s = await state(id);
    expect(s.devices.find((d) => d.deviceId === "nora")!.commonFormat).toBe(2);
    expect(s.devices.find((d) => d.deviceId === "aritz")!.commonFormat).toBeUndefined();
    // B5: a web credential announces too (it reads and signs the common).
    const web = await webPair(id, "leo", v);
    for (const bad of [{}, { commonFormat: 1 }, { commonFormat: 3 }]) {
      expect((await announce(id, web.guestKey, bad)).status, JSON.stringify(bad)).toBe(400);
    }
    const w = await announce(id, web.guestKey);
    expect(w.status).toBe(200);
    const wv = (await json<{ version: number }>(w)).version;
    expect(wv).toBeGreaterThan(v);
    expect((await json<{ version: number }>(await announce(id, web.guestKey))).version).toBe(wv);
    expect((await state(id)).devices.find((d) => d.deviceId === "leo")!.commonFormat).toBe(2);
  });

  it("B5: a family with an announced web can raise the minimum; the web then writes only format 2", async () => {
    const id = await setup();
    const web = await webPair(id, "nora", 1);
    const v = (await state(id)).version;
    expect((await announce(id, web.guestKey)).status).toBe(200);
    expect((await announce(id, id.key)).status).toBe(200);
    // The web itself never raises the minimum (a PUT S is not open to it).
    expect((await put(id, { ...snap(2), minCommonFormat: 2 }, v + 2, web.guestKey)).status).toBe(403);
    expect((await put(id, { ...snap(2), minCommonFormat: 2 }, v + 2)).status).toBe(200);
    expect((await state(id)).minCommonFormat).toBe(2);
    const old = await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": `"${v + 3}"` }, body: { common: rg(1) } });
    expect(old.status).toBe(409);
    expect(await json(old)).toEqual({ error: "common_format_too_old" });
    const ok = await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": `"${v + 3}"` }, body: { common: rg(2) } });
    expect(ok.status).toBe(200);
  });

  it("validates the format byte before the cut: a later format is 400 everywhere", async () => {
    const id = await setup();
    const web = await webPair(id, "nora", 1);
    for (const f of [3, 4, 255]) {
      const r = await put(id, snap(f), 2);
      expect(r.status, String(f)).toBe(400);
      expect(await json(r)).toEqual({ error: "common_format_unknown" });
      expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"2"' }, body: { common: rg(f) } })).status).toBe(400);
    }
    const fresh = { ...newList(), deviceId: "aritz" };
    expect((await call("PUT", `/v2/lists/${fresh.syncId}`, { key: fresh.key, ip: fresh.ip, headers: { "If-Match": '"0"' }, body: { ...snap(3), deviceId: "aritz" } })).status).toBe(400);
    // Format 1 and 2 (and, as before, text that is not an envelope) still go.
    expect((await put(id, snap(1), 2)).status).toBe(200);
    expect((await put(id, snap(2), 3)).status).toBe(200);
    expect((await put(id, snapshot(), 4)).status).toBe(200);
    expect((await state(id)).minCommonFormat).toBeUndefined();
  });

  it("raises the minimum only when every live credential announced, in the same write as a format-2 common", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    // Nobody announced yet.
    let r = await put(id, { ...snap(2), minCommonFormat: 2 }, 2);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_unannounced" });
    expect((await announce(id, id.key)).status).toBe(200);
    // M1: the caller announced, another live credential did not.
    r = await put(id, { ...snap(2), minCommonFormat: 2 }, 3);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_unannounced" });
    expect((await announce(id, nora.guestKey)).status).toBe(200);
    for (const bad of [0, 3, "2", 1.5]) expect((await put(id, { ...snap(2), minCommonFormat: bad }, 4)).status, String(bad)).toBe(400);
    // The raise needs a common of that format.
    r = await put(id, { ...snap(1), minCommonFormat: 2 }, 4);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_too_old" });
    expect((await state(id)).minCommonFormat).toBeUndefined();
    expect((await put(id, { ...snap(2), minCommonFormat: 2 }, 4)).status).toBe(200);
    expect((await state(id)).minCommonFormat).toBe(2);
    // A lower value never lowers it.
    expect((await put(id, { ...snap(2), minCommonFormat: 1 }, 5)).status).toBe(200);
    expect((await state(id)).minCommonFormat).toBe(2);
  });

  it("M1: a live web credential (which cannot announce yet) blocks the raise; a revoked one does not", async () => {
    const id = await setup();
    const web = await webPair(id, "nora", 1);
    expect((await announce(id, id.key)).status).toBe(200);
    const r = await put(id, { ...snap(2), minCommonFormat: 2 }, 3);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_unannounced" });
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: web.deviceId } })).status).toBe(200);
    expect((await put(id, { ...snap(2), minCommonFormat: 2 }, 4)).status).toBe(200);
    expect((await state(id)).minCommonFormat).toBe(2);
  });

  it("after the cut an old client cannot write format 1, by PUT S or PUT S/common", async () => {
    const id = await setup();
    expect((await announce(id, id.key)).status).toBe(200);
    const cut = snap(2);
    expect((await put(id, { ...cut, minCommonFormat: 2 }, 2)).status).toBe(200);
    // Paired after the cut, by an old build that never announces.
    const nora = await pair(id, "nora", 3);
    const web = await webPair(id, "leo", 4);
    const before = await state(id);
    for (const old of [snap(1), snapshot()]) {
      const r = await put(id, old, 5, nora.guestKey);
      expect([400, 409]).toContain(r.status);
    }
    const r = await put(id, snap(1), 5, nora.guestKey);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_too_old" });
    const c = await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"5"' }, body: { common: rg(1) } });
    expect(c.status).toBe(409);
    expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"5"' }, body: { common: rg(3) } })).status).toBe(400);
    // Nothing changed; format 2 still goes, from anyone.
    expect(await state(id)).toEqual(before);
    expect((await put(id, snap(2), 5, nora.guestKey)).status).toBe(200);
    expect((await call("PUT", `${id.path}/common`, { key: web.guestKey, headers: { "If-Match": '"6"' }, body: { common: rg(2) } })).status).toBe(200);
  });

  it("a generation can be born in format 2; its creator counts as announced", async () => {
    const fresh = { ...newList(), deviceId: "aritz" };
    const path = `/v2/lists/${fresh.syncId}`;
    const create = (body: unknown) => call("PUT", path, { key: fresh.key, ip: fresh.ip, headers: { "If-Match": '"0"' }, body });
    expect((await create({ ...snap(1), deviceId: "aritz", minCommonFormat: 2 })).status).toBe(409);
    expect((await create({ ...snap(2), deviceId: "aritz", minCommonFormat: 3 })).status).toBe(400);
    expect((await create({ ...creation("aritz", snap(2)), deviceId: "aritz", minCommonFormat: 2 })).status).toBe(201);
    const s = await json<{ minCommonFormat?: number; devices: { commonFormat?: number }[] }>(await call("GET", path, { key: fresh.key }));
    expect(s.minCommonFormat).toBe(2);
    expect(s.devices[0]!.commonFormat).toBe(2);
  });

  it("the persisted minimum is part of the state row; a later one (rollback) refuses common writes without retiring", async () => {
    const id = await setup();
    expect((await announce(id, id.key)).status).toBe(200);
    expect((await put(id, { ...snap(2), minCommonFormat: 2 }, 2)).status).toBe(200);
    expect(((await readState(id)) as unknown as { minCommonFormat: number }).minCommonFormat).toBe(2);
    // As a newer Worker would have left it, read by this older code.
    await editState(id, (m) => {
      (m as unknown as { minCommonFormat: number }).minCommonFormat = 7;
      (m.credentials[0] as unknown as { commonFormat: number }).commonFormat = 7;
    });
    const s = await state(id);
    expect(s.minCommonFormat).toBe(7);
    let r = await put(id, snap(2), 3);
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "common_format_unsupported" });
    r = await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"3"' }, body: { common: rg(2) } });
    expect(r.status).toBe(409);
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    // Not an integer from 1: malformed, retired like any other field.
    await editState(id, (m) => {
      (m as unknown as { minCommonFormat: number }).minCommonFormat = 0;
    });
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
  });
});

describe("B7: pairing checkpoint", () => {
  /** What the app computes (`pairingCheckpointHash`). */
  const hash = async (part: string, text: string) => {
    const d = new TextEncoder().encode(`gift-huddle-pairing-checkpoint-${part}-v1`);
    const t = new TextEncoder().encode(text);
    const m = new Uint8Array(d.length + 1 + t.length);
    m.set(d);
    m.set(t, d.length + 1);
    return encodeB64Url(await sha256(m));
  };
  const current = async (id: Setup) => {
    const s = await json<{ version: number; common: string; registry: unknown }>(await call("GET", id.path, { key: id.key }));
    const registry = canonicalJson(s.registry);
    return { version: s.version, common: s.common, registry, claim: { common: await hash("common", s.common), registry: await hash("registry", registry) } };
  };
  const approveWith = (id: Setup, i: { privatePath: string }, version: number, checkpoint: unknown) =>
    call("POST", `${i.privatePath}/approve`, { key: id.key, headers: { "If-Match": `"${version}"` }, body: { package: { c: "opaque" }, checkpoint } });
  const checkpoint = (i: { publicPath: string; guestKey: string }, key: string | null = i.guestKey) =>
    call("GET", `${i.publicPath}/checkpoint`, { key });
  const rows = (id: Setup) => runInDurableObject(listStub(id.syncId), (_o, s) =>
    s.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'checkpoint'").toArray().length
      ? s.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM checkpoint").one().n : 0);

  it("counts the second credential before checking its approval checkpoint against the byte limit", async () => {
    const id = await setup();
    expect((await put(id, { ...snapshot(), common: "A".repeat(900000) }, 1)).status).toBe(200);
    const i = await answered(id), before = await current(id);
    expect((await approveWith(id, i, before.version, before.claim)).status).toBe(200);
    const stored = await runInDurableObject(listStub(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data));
    expect(stored.storedBytes).toBeGreaterThan(1.5 * 1048576);
    expect(stored.storedBytes).toBeLessThan(4 * 1048576);
    expect(stored.credentials).toHaveLength(2);
  });

  it("copies the approved common and registry at the host's If-Match and serves them, unchanged, only to the guest", async () => {
    const id = await setup();
    await byteCapacity(id, 5);
    const big = { ...snapshot(), common: b64u(new Uint8Array(1_500_000).fill(7)) };
    expect((await put(id, big, 1)).status).toBe(200);
    const i = await answered(id);
    expect((await checkpoint(i)).status).toBe(404);
    const before = await current(id);
    const r = await approveWith(id, i, before.version, before.claim);
    expect(r.status).toBe(200);
    // A later legitimate write does not touch the approved copy.
    expect((await put(id, { ...snapshot(), common: envelope(80) }, before.version + 1)).status).toBe(200);
    const got = await checkpoint(i);
    expect(got.status).toBe(200);
    const body = await json<{ common: string; registry: string }>(got);
    expect(body.common).toBe(before.common);
    expect(body.registry).toBe(before.registry);
    expect(await hash("common", body.common)).toBe(before.claim.common);
    // Repeatable, and only for the guest credential.
    expect((await checkpoint(i)).status).toBe(200);
    expect((await checkpoint(i, b64u(rand(32)))).status).toBe(404);
    expect((await checkpoint(i, null)).status).toBe(404);
    expect((await checkpoint(i, id.key)).status).toBe(404);
  });

  it("refuses a claim that does not match the current state, registering nothing", async () => {
    const id = await setup();
    const i = await answered(id);
    const s = await current(id);
    for (const claim of [
      { common: b64u(rand(32)), registry: s.claim.registry },
      { common: s.claim.common, registry: b64u(rand(32)) },
    ]) {
      const r = await approveWith(id, i, s.version, claim);
      expect(r.status).toBe(409);
      expect(await json(r)).toEqual({ error: "checkpoint_mismatch" });
    }
    for (const bad of [{}, { common: s.claim.common }, { ...s.claim, x: 1 }, { common: "x", registry: s.claim.registry }, "x", null]) {
      expect((await approveWith(id, i, s.version, bad)).status, JSON.stringify(bad)).toBe(400);
    }
    const after = await current(id);
    expect(after.version).toBe(s.version);
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(202);
    expect(await rows(id)).toBe(0);
    expect((await approveWith(id, i, s.version, s.claim)).status).toBe(200);
  });

  it("an approval without a claim (older host) has no checkpoint", async () => {
    const id = await setup();
    const i = await pair(id);
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
    expect((await checkpoint(i)).status).toBe(404);
  });

  it("goes away with its invitation: cancelled, owner revoked or expired", async () => {
    const id = await setup();
    const a = await answered(id, "nora");
    let s = await current(id);
    expect((await approveWith(id, a, s.version, s.claim)).status).toBe(200);
    const b = await answered(id, "leo");
    s = await current(id);
    expect((await approveWith(id, b, s.version, s.claim)).status).toBe(200);
    expect(await rows(id)).toBe(4);
    expect((await call("DELETE", a.privatePath, { key: id.key })).status).toBe(204);
    expect((await checkpoint(a)).status).toBe(404);
    expect((await checkpoint(b)).status).toBe(200);
    expect(await rows(id)).toBe(2);
    // Expiry: the alarm drops the rows of an invitation that is gone.
    await runInDurableObject(listStub(id.syncId), (_o, st) => {
      st.storage.sql.exec("UPDATE invite SET expires_at = ?", Date.now() - 1);
    });
    expect(await runDurableObjectAlarm(listStub(id.syncId))).toBe(true);
    expect((await checkpoint(b)).status).toBe(404);
    expect(await rows(id)).toBe(0);
    // Revoking the owner drops its invitations and their checkpoints.
    const nora = (await json<{ devices: unknown[] }>(await call("GET", id.path, { key: id.key }))).devices.length;
    expect(nora).toBe(3);
    const c = await answered(id, "zoe");
    s = await current(id);
    expect((await approveWith(id, c, s.version, s.claim)).status).toBe(200);
    expect(await rows(id)).toBe(2);
    expect((await call("POST", `${id.path}/revoke`, { key: b.guestKey, body: { deviceId: id.deviceId } })).status).toBe(200);
    expect(await rows(id)).toBe(0);
  });

  it("at most V2_MAX_CHECKPOINTS (8, the daily approvals) live checkpoints; GET I says when an approval would not fit", async () => {
    const id = await setup();
    const canApprove = async (i: { privatePath: string }) => (await json<{ canApprove: boolean }>(await call("GET", i.privatePath, { key: id.key }))).canApprove;
    for (const guest of ["g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8"]) {
      const i = await answered(id, guest);
      expect(await canApprove(i)).toBe(true);
      const s = await current(id);
      expect((await approveWith(id, i, s.version, s.claim)).status).toBe(200);
    }
    const i = await answered(id, "g9");
    expect(await canApprove(i)).toBe(false);
    const s = await current(id);
    const r = await approveWith(id, i, s.version, s.claim);
    expect(r.status).toBe(429);
    expect(await json(r)).toEqual({ error: "too_many_checkpoints" });
    expect((await current(id)).version).toBe(s.version);
  });

  it("the guest releases its checkpoint once installed (DELETE J/checkpoint)", async () => {
    const id = await setup();
    const i = await answered(id);
    const s = await current(id);
    expect((await approveWith(id, i, s.version, s.claim)).status).toBe(200);
    expect((await call("DELETE", `${i.publicPath}/checkpoint`, { key: id.key })).status).toBe(404);
    expect(await rows(id)).toBe(2);
    const first = await json(await call("GET", `${i.publicPath}/result`, { key: i.guestKey }));
    expect(await json(await call("GET", `${i.publicPath}/result`, { key: i.guestKey }))).toEqual(first);
    expect((await call("DELETE", `${i.publicPath}/checkpoint`, { key: i.guestKey })).status).toBe(204);
    expect(await rows(id)).toBe(0);
    expect((await checkpoint(i)).status).toBe(404);
    expect((await call("DELETE", `${i.publicPath}/checkpoint`, { key: i.guestKey })).status).toBe(404);
    // Installation acknowledgement removes the invitation and its opaque package.
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(404);
    expect((await call("GET", i.privatePath, { key: id.key })).status).toBe(404);
  });

  it("hashes like the app (vector shared with pairing_v2_checkpoint_test.dart)", async () => {
    const registry = { v: 2, l: "family", records: [{ d: "aritz", k: "web", n: "Ñandú" }], vouches: [], revocations: [], x: { "10": 1, "2": 9007199254740991, a: true, b: null } };
    const text = canonicalJson(registry);
    expect(text).toBe('{"l":"family","records":[{"d":"aritz","k":"web","n":"Ñandú"}],"revocations":[],"v":2,"vouches":[],"x":{"10":1,"2":9007199254740991,"a":true,"b":null}}');
    // Through an object the integer-like keys would move first.
    expect(JSON.stringify(registry.x)).toBe('{"2":9007199254740991,"10":1,"a":true,"b":null}');
    expect(await hash("registry", text)).toBe("Jbf9Hr-umQPirKpZKVLGe49T-uM7u3_O6Yvxi3ymXv0");
    expect(await hash("common", "UkcCAAA")).toBe("kaBsFU0H8fypGZFljR160Awkn3unXVz7VzKls73eid4");
  });

  it("the route is GET only and goes through the invitation limits", async () => {
    const id = await setup();
    const i = await pair(id);
    expect((await call("POST", `${i.publicPath}/checkpoint`, { key: i.guestKey, body: {} })).status).toBe(405);
    expect((await call("PUT", `${i.publicPath}/checkpoint`, { key: i.guestKey, body: {} })).status).toBe(405);
  });
});

describe("recovery credential-reservation regressions", () => {
  it("answer cannot reserve another unfinished invitation's verifier", async () => {
    const id = await setup(), first = await invite(id), second = await invite(id, "leo", first.guestKey);
    expect((await call("POST", `${first.publicPath}/answer`, { body: first.answerBody })).status).toBe(201);
    const rejected = await call("POST", `${second.publicPath}/answer`, { body: second.answerBody });
    expect(rejected.status).toBe(409); expect(await json(rejected)).toEqual({ error: "credential_exists" });
    expect((await call("GET", `${first.publicPath}/result`, { key: first.guestKey })).status).toBe(202);
  });
  it("approve also checks an existing reservation from an older pending answer", async () => {
    const id = await setup(), first = await answered(id), second = await invite(id, "leo");
    expect((await call("POST", `${second.publicPath}/answer`, { body: second.answerBody })).status).toBe(201);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const row = s.storage.sql.exec<{ data: string }>("SELECT data FROM invite WHERE id = ?", second.inviteId).one();
      const i = JSON.parse(row.data); i.verifier = first.answerBody.serviceCredentialVerifier;
      s.storage.sql.exec("UPDATE invite SET data = ? WHERE id = ?", JSON.stringify(i), second.inviteId);
    });
    const rejected = await approve(id, first, 1);
    expect(rejected.status).toBe(409); expect(await json(rejected)).toEqual({ error: "credential_exists" });
    expect((await readState(id)).credentials).toHaveLength(1);
  });
  it("ordinary mobile snapshots keep the existing protocol without creating recovery storage", async () => {
    const id = await setup();
    const before = await json(await call("GET", id.path, { key: id.key }));
    expect(before).toHaveProperty("version", 1); expect(before).not.toHaveProperty("recoveries");
    expect((await put(id, snapshot(), 1)).status).toBe(200);
    expect(await runInDurableObject(listStub(id.syncId), (_o, s) => s.storage.sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'recovery%'").toArray())).toEqual([]);
  });
});


describe("privacy second batch", () => {
  it("retires the whole list when the final phone revokes itself", async () => {
    const id = await setup();
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: id.deviceId } })).status).toBe(200);
    expect((await call("GET", id.path, { key: id.key })).status).toBe(404);
    expect((await call("PUT", id.path, { key: id.key, headers: { "If-Match": '\"0\"' }, body: { ...creation(id.deviceId), deviceId: id.deviceId } })).status).toBe(410);
  });
  it("retires the list when the last credential is a web", async () => {
    const id = await setup();
    const i = await webPair(id, "web");
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: id.deviceId } })).status).toBe(200);
    expect((await call("GET", id.path, { key: i.guestKey })).status).toBe(200);
    expect((await call("POST", `${id.path}/revoke`, { key: i.guestKey, body: { deviceId: "web" } })).status).toBe(200);
    expect((await call("GET", id.path, { key: i.guestKey })).status).toBe(404);
  });
  it("accepts installation acknowledgements for older hosts without a checkpoint", async () => {
    const id = await setup();
    const i = await pair(id);
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
    expect((await call("DELETE", `${i.publicPath}/checkpoint`, { key: i.guestKey })).status).toBe(204);
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(404);
    expect(await everythingStored(id.syncId)).not.toContain('"c":"opaque"');
  });
  it("rounds lastAccess on creation, writes and legacy reads to the hour", async () => {
    const id = await setup();
    const read = () => runInDurableObject(listStub(id.syncId), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data).lastAccess as number);
    expect((await read()) % HOUR).toBe(0);
    expect((await put(id, snapshot(), 1)).status).toBe(200);
    expect((await read()) % HOUR).toBe(0);
    await runInDurableObject(listStub(id.syncId), (_o, s) => {
      const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
      m.lastAccess = Date.now() - 123;
      s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
    });
    await call("GET", id.path, { key: id.key });
    expect((await read()) % HOUR).toBe(0);
  });
});


describe("credential-scaled list storage", () => {
  it("keeps a three-phone family with twelve full sealed slots and a large common", async () => {
    const id = await setup();
    const nora = await pair(id, "nora", 1);
    await pair(id, "leo", 2);
    const common = "A".repeat(200000);
    expect((await put(id, { ...snapshot(Array.from({ length: 6 }, (_, n) => slot(n))), common }, 3)).status).toBe(200);
    expect((await put(id, { ...snapshot(Array.from({ length: 6 }, (_, n) => slot(n, "nora"))), common }, 4, nora.guestKey)).status).toBe(200);
    expect((await json<{ slots: unknown[] }>(await call("GET", id.path, { key: id.key }))).slots).toHaveLength(12);
  });
  it("allows revocation and shrinking an over-budget list without losing its common", async () => {
    const id = await setup();
    await pair(id, "nora", 1);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '\"2\"' }, body: { common: "A".repeat(2 * 1048576) } })).status).toBe(200);
    expect((await call("POST", `${id.path}/revoke`, { key: id.key, body: { deviceId: "nora" } })).status).toBe(200);
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '\"4\"' }, body: { common: "A".repeat(2 * 1048576 - 400) } })).status).toBe(200);
    // A revoked second phone still grants 4 MiB throughout its slot grace.
    await editState(id, (m) => { m.credentials[1]!.slotsExpireAt = Date.now() - 1; });
    const denied = await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '\"5\"' }, body: { common: "A".repeat(2 * 1048576) } });
    expect(denied.status).toBe(413); expect(await json(denied)).toEqual({ error: "too_large" });
    expect((await call("GET", id.path, { key: id.key })).headers.get("ETag")).toBe('"5"');
  });
});
