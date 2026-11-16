import { describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { runInDurableObject, runDurableObjectAlarm } from "cloudflare:test";
import { b64u, call, json, newList, rand } from "./helpers";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";
import { canonicalJson } from "../src/v2-contract";
import { transitionRenewal, renewalHash, verifyRenewalSignature, type RenewalCommand, type RenewalState } from "../src/renewal";
import * as limits from "../src/limits";
import { routeV2 } from "../src/v2-router";
import { ListV2Object } from "../src/list-v2-object";

const key = () => b64u(rand(32));
const signing = new Map<string, CryptoKeyPair>();
const publicKeys = new Map<string, string>();
async function prepareSigning(deviceId: string) {
  if (!signing.has(deviceId)) {
    const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]) as CryptoKeyPair;
    signing.set(deviceId, pair);
    publicKeys.set(deviceId, b64u(new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer)));
  }
}
const publicKey = (deviceId: string) => publicKeys.get(deviceId)!;
async function signed(c: RenewalCommand): Promise<RenewalCommand> {
  await prepareSigning(c.signerDeviceId);
  const { signature: _signature, ...unsigned } = c;
  return { ...c, signature: b64u(new Uint8Array(await crypto.subtle.sign("Ed25519", signing.get(c.signerDeviceId)!.privateKey,
    new TextEncoder().encode(`gift-huddle-renewal-control-v2\0${canonicalJson(unsigned)}`)))) };
}
const snapshot = () => ({ common: "AAAA", registry: { records: [], vouches: [], revocations: [] }, keyPackages: [], slots: [] });
async function setup() {
  await prepareSigning("aritz");
  const id = newList();
  const result = { ...id, deviceId: "aritz", operationId: b64u(rand(16)), targetSyncId: b64u(rand(16)), path: `/v2/lists/${id.syncId}` };
  expect((await call("PUT", result.path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: { ...snapshot(), deviceId: result.deviceId, registry: { ...snapshot().registry, records: [{ d: result.deviceId, e: publicKey(result.deviceId) }] } } })).status).toBe(201);
  // Most protocol tests start with an already announced, capable credential.
  await edit(result, (m) => { m.credentials[0].renewalProtocol = 1; });
  return result;
}
type Setup = Awaited<ReturnType<typeof setup>>;
const stub = (id: Setup) => {
  const ns = env.LISTS_V2.jurisdiction("eu");
  return ns.get(ns.idFromName(id.syncId));
};
const edit = (id: Setup, change: (state: any) => void) => runInDurableObject(stub(id), (_o, s) => {
  const state = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
  change(state);
  s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(state));
});
const verifier = async (credential: string) => encodeB64Url(await sha256(decodeB64Url(credential, 32)!));
async function add(id: Setup, deviceId = "nora", role = "device") {
  await prepareSigning(deviceId);
  const credential = key();
  const hash = await verifier(credential);
  await edit(id, (s) => s.credentials.push({ deviceId, verifier: hash, revoked: false, role, records: [], signingKey: publicKey(deviceId), renewalProtocol: 1 }));
  return { ...id, deviceId, key: credential };
}
const heads = new Map<string, string | null>();
const get = async (id: Setup) => {
  const response = await call("GET", `${id.path}/renewal`, { key: id.key });
  expect(response.status).toBe(200);
  const result = await json<{ version: number; renewal: any }>(response);
  if (!result.renewal) return result as { version: number; renewal: RenewalState | null };
  const p = result.renewal;
  heads.set(id.syncId, p.head);
  const commands: RenewalCommand[] = [];
  let after: number | null = 0;
  while (after !== null) {
    const page: { commands: RenewalCommand[]; next: number | null } = await json(await call("GET", `${id.path}/renewal/log/${p.operationId}/${p.head}/${after}`, { key: id.key }));
    commands.push(...page.commands); after = page.next;
  }
  const byHash = new Map(await Promise.all(commands.map(async (c) => [await renewalHash(c), c] as const)));
  for (const k of ["plan", "reservation", "recovery", "barrier", "abortion", "ready", "preparation", "confirmation"]) p[k] = p[k] === null ? null : byHash.get(p[k]);
  for (const k of ["acknowledgements", "transfers", "exclusions"]) p[k] = Object.fromEntries(Object.entries(p[k]).map(([id, h]) => [id, byHash.get(h as string)]));
  p.identities = commands.filter((c) => c.newDeviceId !== undefined);
  p.revokedIdentities = {};
  const revoked = commands.filter((c) => c.action === "revoke").map((c) => c.participantDeviceId);
  for (const c of p.identities as RenewalCommand[]) if (revoked.includes(c.signerDeviceId)) {
    const existing = Object.entries(p.revokedIdentities).find(([, old]: any) => old.targetSyncId === c.targetSyncId && old.newDeviceId === c.newDeviceId);
    const k = existing?.[0] ?? (p.revokedIdentities[c.signerDeviceId] ? `${c.signerDeviceId}.${c.targetSyncId}.${c.newDeviceId}` : c.signerDeviceId);
    p.revokedIdentities[k] = c;
  }
  return result as { version: number; renewal: RenewalState | null };

};
async function command(id: Setup, sourceVersion: number, action: RenewalCommand["action"], extra: Record<string, unknown> = {}): Promise<RenewalCommand> {
  return signed({ v: 1, action, operationId: id.operationId, sourceSyncId: id.syncId, targetSyncId: id.targetSyncId, revision: 1,
    sourceVersion, signerDeviceId: id.deviceId, prev: heads.get(id.syncId) ?? null, signature: b64u(new Uint8Array(64)), ...extra });
}
async function createTarget(c: RenewalCommand) {
  const fresh = newList();
  return call("PUT", `/v2/lists/${c.targetSyncId}`, { key: fresh.key, ip: fresh.ip, headers: { "If-Match": '"0"' },
    body: { ...snapshot(), deviceId: c.newDeviceId, registry: { records: [{ d: c.newDeviceId, e: c.newSigningKey }], vouches: [], revocations: [] } } });
}
const send = async (id: Setup, c: RenewalCommand, match: string | null = `"${c.sourceVersion}"`) => {
  if (["reserve", "replace", "recover"].includes(c.action)) await createTarget(c);
  const result = await call("PUT", `${id.path}/renewal`, { key: id.key, headers: match === null ? {} : { "If-Match": match }, body: c });
  if (result.status === 200) {
    const body = await json<{ renewal: { head: string } }>(result.clone()); heads.set(id.syncId, body.renewal.head);
  }
  return result;
};
const reserve = async (id: Setup, version = 1, participants = [id.deviceId]) => await command(id, version, "reserve", {
  participants, newDeviceId: "aritz-new", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key(),
});
async function step(id: Setup, action: RenewalCommand["action"], extra: Record<string, unknown> = {}) {
  const before = await get(id);
  const c = await command(id, before.version, action, { revision: before.renewal?.revision ?? 1, ...extra });
  const response = await send(id, c);
  expect(response.status, await response.clone().text()).toBe(200);
  return { c, ...await get(id) } as { c: RenewalCommand; version: number; renewal: RenewalState };
}
async function revoke(id: Setup, deviceId: string): Promise<Response> {
  const before = await get(id);
  const c = await command({ ...id, targetSyncId: before.renewal!.targetSyncId }, before.version, "revoke", {
    revision: before.renewal!.revision, participantDeviceId: deviceId });
  return send(id, c);
}

it("privacy: signed renewal revocation also expires secret slots after 30 days", async () => {
  const id = await setup();
  await add(id);
  await migrated(id, ["aritz", "nora"]);
  await runInDurableObject(stub(id), (_o, s) => {
    s.storage.sql.exec("INSERT INTO slot (person, device, ver, data) VALUES ('leo', 'nora', 1, 'ciphertext')");
  });
  const now = Date.now();
  vi.useFakeTimers({ toFake: ["Date"] });
  try {
    vi.setSystemTime(now);
    expect((await revoke(id, "nora")).status).toBe(200);
    vi.setSystemTime(now + limits.V2_REVOKED_SLOTS_GRACE_MS - 1);
    await runDurableObjectAlarm(stub(id));
    expect(await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("SELECT * FROM slot").toArray())).toHaveLength(1);
    vi.setSystemTime(now + limits.V2_REVOKED_SLOTS_GRACE_MS);
    await runDurableObjectAlarm(stub(id));
    expect(await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("SELECT * FROM slot").toArray())).toEqual([]);
  } finally { vi.useRealTimers(); }
});
async function capability(id: Setup): Promise<Response> {
  const before = await get(id);
  return send(id, await command({ ...id, targetSyncId: before.renewal!.targetSyncId }, before.version, "capability", {
    revision: before.renewal!.revision, commonFormat: 2 }));
}
async function migrated(id: Setup, participants = [id.deviceId]) {
  const plan = await reserve(id, 1, participants);
  expect((await send(id, plan)).status).toBe(200);
  await step(id, "ready", { destinationVersion: 1 });
  await step(id, "ack", { newDeviceId: plan.newDeviceId, newSigningKey: plan.newSigningKey, destinationVersion: 2, receipt: key() });
  return plan;
}

describe("renewal control", () => {
  it("disabled reserve changes neither list, invitations, counters, log nor alarms", async () => {
    const id = await setup();
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer: { v: 2, host: { d: "aritz" }, c: key() } } })).status).toBe(201);
    const plan = await reserve(id, (await get(id)).version);
    await createTarget(plan);
    const target = { ...id, syncId: plan.targetSyncId };
    const stored = (list: Setup) => runInDurableObject(stub(list), async (_o, s) => ({
      tables: s.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name").toArray()
        .map(({ name }) => ({ name, rows: s.storage.sql.exec(`SELECT * FROM ${name}`).toArray() })),
      alarm: await s.storage.getAlarm(),
    }));
    const before = await stored(id), targetBefore = await stored(target);
    for (const enabled of [undefined, "false", "TRUE"]) {
      const response = await routeV2(new Request(`https://sync.test${id.path}/renewal`, { method: "PUT",
        headers: { Authorization: `Bearer ${id.key}`, "Content-Type": "application/json", "If-Match": `"${plan.sourceVersion}"` }, body: JSON.stringify(plan) }),
        { ...env, RENEWAL_ENABLED: enabled });
      expect(response.status).toBe(409);
      expect(await json(response)).toEqual({ error: "renewal_disabled" });
      const direct = await runInDurableObject(stub(id), (_o, s) => new ListV2Object(s, { ...env, RENEWAL_ENABLED: enabled }).handle({
        route: { resource: "renewal", syncId: id.syncId, methods: ["GET", "PUT"] }, method: "PUT", verifier: null,
        client: "test", match: `"${plan.sourceVersion}"`, none: null, body: plan, destinationCreated: true,
      }));
      expect(direct).toMatchObject({ status: 409, body: { error: "renewal_disabled" } });
    }
    expect(await stored(id)).toEqual(before);
    expect(await stored(target)).toEqual(targetBefore);
  });

  it.each(["device", "web"])("requires immutable binding and explicit renewal support from every active %s", async (role) => {
    const id = await setup(), nora = await add(id, "nora", role);
    await edit(id, (m) => { delete m.credentials[1].signingKey; });
    const participants = [id.deviceId, nora.deviceId];
    expect(await json(await send(id, await reserve(id, 1, participants)))).toEqual({ error: "renewal_key_binding_required" });
    await edit(id, (m) => { m.credentials[1].signingKey = publicKey("nora"); delete m.credentials[1].renewalProtocol; });
    expect((await call("POST", `${id.path}/capability`, { key: nora.key, body: { commonFormat: 2 } })).status).toBe(200);
    const version = (await get(id)).version;
    expect(await json(await send(id, await reserve(id, version, participants)))).toEqual({ error: "renewal_capability_required" });
    expect((await get(id)).renewal).toBeNull();
    const announce = () => call("POST", `${id.path}/capability`, { key: nora.key, body: { commonFormat: 2, renewalProtocol: 1 } });
    const response = await announce();
    expect(response.status).toBe(200);
    const announcedVersion = (await get(id)).version;
    expect(announcedVersion).toBe(version + 1);
    expect((await announce()).status).toBe(200);
    expect((await get(id)).version).toBe(announcedVersion);
    const accepted = await send(id, await reserve({ ...id, targetSyncId: b64u(rand(16)) }, announcedVersion, participants));
    expect(accepted.status, await accepted.clone().text()).toBe(200);
  });

  it("requires the initiator announcement and ignores revoked incapable credentials", async () => {
    const id = await setup(); await add(id);
    await edit(id, (m) => { delete m.credentials[0].renewalProtocol; m.credentials[1].revoked = true; delete m.credentials[1].renewalProtocol; delete m.credentials[1].signingKey; });
    expect(await json(await send(id, await reserve(id)))).toEqual({ error: "renewal_capability_required" });
    expect((await call("POST", `${id.path}/capability`, { key: id.key, body: { commonFormat: 2, renewalProtocol: 2 } })).status).toBe(400);
    expect((await call("POST", `${id.path}/capability`, { key: id.key, body: { commonFormat: 2, renewalProtocol: 1 } })).status).toBe(200);
    const accepted = await send(id, await reserve({ ...id, targetSyncId: b64u(rand(16)) }, (await get(id)).version));
    expect(accepted.status, await accepted.clone().text()).toBe(200);
  });

  it("canonical command hash matches the independent Node Ed25519/Dart vector", async () => {
    const fixed = (n: number, length = 32) => b64u(new Uint8Array(length).fill(n));
    const c: RenewalCommand = { v: 1, action: "reserve", operationId: fixed(2, 16), sourceSyncId: fixed(1, 16), targetSyncId: fixed(3, 16),
      revision: 1, sourceVersion: 1, signerDeviceId: "aritz-phone", prev: null,
      participants: ["aritz-phone", "nora-phone"], newDeviceId: "destination-1", newSigningKey: fixed(21), targetCommitment: fixed(4), inventoryCommitment: fixed(5),
      signature: "T6VkENaIBE0JSqV-VDe-_5kad3RpiMiNZ8sAI0pkeAVT42de9G4Ma5Fdc_60xgu-WkwjXzTDSkpMNm4gRnBKAA" };
    expect(await renewalHash(c)).toBe("JARBEPfhMR4dg2vmD8oyaQixMms_uj5i7bm7sG6WWZw");
  });

  it("persists the Dart integer capability interoperability vector with its signature intact", async () => {
    const fixed = (n: number, length = 32) => b64u(new Uint8Array(length).fill(n));
    const fresh = newList(); const path = `/v2/lists/${fixed(1, 16)}`;
    const pub = "1i8Bah79Hk_feT60LNhEceG6nwzwTRKHtcxx9hYofLg";
    expect((await call("PUT", path, { key: fresh.key, ip: fresh.ip, headers: { "If-Match": '"0"' }, body: { ...snapshot(), deviceId: "aritz-phone", registry: { records: [{ d: "aritz-phone", e: pub }], vouches: [], revocations: [] } } })).status).toBe(201);
    await edit({ ...fresh, syncId: fixed(1, 16) } as Setup, (m) => { m.credentials[0].renewalProtocol = 1; });
    const c: RenewalCommand = { v: 1, action: "reserve", operationId: fixed(2, 16), sourceSyncId: fixed(1, 16), targetSyncId: fixed(3, 16), revision: 1, sourceVersion: 1, signerDeviceId: "aritz-phone", prev: null,
      participants: ["aritz-phone", "nora-phone"], newDeviceId: "destination-1", newSigningKey: fixed(21), targetCommitment: fixed(4), inventoryCommitment: fixed(5),
      signature: "T6VkENaIBE0JSqV-VDe-_5kad3RpiMiNZ8sAI0pkeAVT42de9G4Ma5Fdc_60xgu-WkwjXzTDSkpMNm4gRnBKAA" };
    await createTarget(c);
    expect((await call("PUT", `${path}/renewal`, { key: fresh.key, headers: { "If-Match": '"1"' }, body: c })).status).toBe(200);
    const capability: RenewalCommand = { v: 1, action: "capability", operationId: c.operationId, sourceSyncId: c.sourceSyncId, targetSyncId: c.targetSyncId,
      revision: 1, sourceVersion: 2, signerDeviceId: c.signerDeviceId, prev: await renewalHash(c), commonFormat: 2,
      signature: "pXSqudZTFRbfF4RSEPq8GsgHx7eJWm-UuguGEhrmWSt06cREtUqkQ1wqZ2UMQDhd1ABN9uZSS6OkfaeQ6mFCAw" };
    const response = await call("PUT", `${path}/renewal`, { key: fresh.key, headers: { "If-Match": '"2"' }, body: JSON.parse(JSON.stringify(capability)) });
    expect(response.status).toBe(200);
    const p = await json<any>(response);
    const page = await json<{ commands: RenewalCommand[] }>(await call("GET", `${path}/renewal/log/${c.operationId}/${p.renewal.head}/0`, { key: fresh.key }));
    expect(page.commands[1]).toEqual(capability);
    expect(await verifyRenewalSignature(page.commands[1]!, pub)).toBe(true);
  });

  it("rejects garbage/foreign signatures before append, using the pinned credential key", async () => {
    const id = await setup(); const plan = await reserve(id);
    await createTarget(plan);
    const raw = (c: RenewalCommand) => call("PUT", `${id.path}/renewal`, { key: id.key, headers: { "If-Match": '"1"' }, body: c });
    expect((await raw({ ...plan, signature: b64u(rand(64)) })).status).toBe(403);
    const foreign = await signed({ ...plan, signerDeviceId: "nora" });
    expect((await raw({ ...plan, signature: foreign.signature })).status).toBe(403);
    expect((await get(id)).renewal).toBeNull();
    expect(await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("SELECT hash FROM renewal_command").toArray())).toEqual([]);
    await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("UPDATE resource SET data = ? WHERE name = 'registry'", JSON.stringify({ records: [{ d: "aritz", e: publicKey("nora") }], vouches: [], revocations: [] })));
    expect((await raw({ ...plan, signature: foreign.signature })).status).toBe(403);
    expect((await raw(plan)).status).toBe(200);
    expect((await get(id)).renewal!.height).toBe(1);
  });

  it("review: 32 participants, exhausted Nora rescue, revoke and complete close", async () => {
    const aritz = await setup(); const nora = await add(aritz);
    const participants = ["aritz", "nora", ...Array.from({ length: 30 }, (_, i) => `local-${i}-` + "x".repeat(118))];
    let now = Date.now(), version = 1, revision = 1;
    const clock = vi.spyOn(Date, "now").mockImplementation(() => now);
    let projection: any; let reservation: RenewalCommand;
    const issue = async (actor: Setup, action: RenewalCommand["action"], fields: Record<string, unknown> = {}, expected = 200) => {
      now += 61000;
      const c = await command(actor, version, action, { revision, ...fields });
      const r = await send(actor, c);
      expect(r.status, await r.clone().text()).toBe(expected);
      if (r.status === 200) { const body = await json<{ version: number; renewal: any }>(r); version = body.version; projection = body.renewal; }
      return c;
    };
    const resolve = async () => {
      await issue(nora, "ready", { destinationVersion: 1 });
      await issue(nora, "ack", { newDeviceId: reservation.newDeviceId, newSigningKey: reservation.newSigningKey, destinationVersion: 2, receipt: key() });
      now += 74 * 3600000;
      for (const participantDeviceId of participants.filter((id) => id !== "nora")) await issue(nora, "exclude", { participantDeviceId, loss: true, receipt: key() });
      await issue(nora, "prepare", { pendingResources: 0, coverageCommitment: key() });
      await issue(nora, "confirm", { snapshotVersion: projection.barrierVersion, pendingResources: 0, coverageCommitment: key() });
    };
    try {
      reservation = await issue(nora, "reserve", { participants, newDeviceId: "nora-new", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
      while (projection.logBytes < 512 * 1024 - 8000) {
        revision++; await issue(aritz, "revise", { participants, inventoryCommitment: key() });
      }
      while (true) {
        const c = await command(aritz, version, "revise", { revision: revision + 1, participants, inventoryCommitment: key() });
        now += 61000; const r = await send(aritz, c);
        if (r.status === 409) { expect(await json(r)).toEqual({ error: "renewal_log_full" }); break; }
        expect(r.status).toBe(200); const body = await json<any>(r); version = body.version; projection = body.renewal; revision++;
      }
      await resolve();
      while (true) {
        now += 61000;
        const c = await command(nora, version, "confirm", { revision, snapshotVersion: projection.barrierVersion, pendingResources: 0, coverageCommitment: key() });
        const r = await send(nora, c);
        if (r.status === 409) { expect(await json(r)).toEqual({ error: "renewal_log_full" }); break; }
        expect(r.status).toBe(200); const body = await json<any>(r); version = body.version; projection = body.renewal;
      }
      await issue(nora, "revoke", { participantDeviceId: "aritz" });
      const rescueHeight = projection.height, rescueBytes = projection.logBytes;
      revision++; await issue(nora, "revise", { participants, inventoryCommitment: key() });
      await resolve();
      expect(projection.height - rescueHeight).toBe(36);
      expect(projection.logBytes - rescueBytes).toBeLessThanOrEqual(limits.V2_RENEWAL_REFILL_BYTES);
      expect((await call("DELETE", nora.path, { key: nora.key, headers: { "If-Match": `"${version}"` } })).status).toBe(204);
    } finally { clock.mockRestore(); }
  }, 120000);

  it("review: twice-excluded Nora revokes Aritz after using resume and closes alone", async () => {
    const aritz = await setup(), nora = await add(aritz);
    const participants = ["aritz", "nora"];
    await migrated(aritz, participants);
    const excludeNora = async () => {
      await edit(aritz, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
      await step(aritz, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    };
    await excludeNora();
    await step(nora, "resume");
    await step(aritz, "revise", { revision: 2, participants, inventoryCommitment: key() });
    await step(aritz, "ready", { destinationVersion: 1 });
    const plan = (await get(aritz)).renewal!.reservation;
    await step(aritz, "ack", { newDeviceId: plan.newDeviceId, newSigningKey: plan.newSigningKey, destinationVersion: 2, receipt: key() });
    await excludeNora();
    const prepared = await step(aritz, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const before = await get(nora);
    expect(await json(await send(nora, await command(nora, before.version, "resume", { revision: 2 })))).toEqual({ error: "renewal_resume_used" });
    expect((await revoke(nora, "aritz")).status).toBe(200);
    const freed = (await get(nora)).renewal!;
    expect(freed.exclusions.nora).toBeUndefined();
    expect(freed.transfers.nora).toBeUndefined();
    expect(freed.acknowledgements.nora).toBeUndefined();
    expect(freed.barrierVersion).toBe(prepared.version);
    expect(freed.needsRevalidation).toBe(true);
    const next = { ...nora, targetSyncId: b64u(rand(16)) };
    const recovered = await step(next, "recover", { revision: 3, previousTargetSyncId: aritz.targetSyncId,
      participants, newDeviceId: "nora-final", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    await step(next, "ready", { destinationVersion: 1 });
    await step(next, "ack", { newDeviceId: recovered.c.newDeviceId, newSigningKey: recovered.c.newSigningKey, destinationVersion: 2, receipt: key() });
    await step(next, "exclude", { participantDeviceId: "aritz", loss: true, receipt: key() });
    const close = await step(next, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const confirmed = await step(next, "confirm", { snapshotVersion: close.version, pendingResources: 0, coverageCommitment: key() });
    expect((await call("DELETE", next.path, { key: next.key, headers: { "If-Match": `"${confirmed.version}"` } })).status).toBe(204);
  });

  it("GET-only activity fences once per operation, independently of signed resume", async () => {
    const aritz = await setup(), nora = await add(aritz);
    await migrated(aritz, ["aritz", "nora"]);
    for (let round = 0; round < 2; round++) {
      await edit(aritz, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
      const excluded = await step(aritz, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
      const observed = await get(nora);
      expect(observed.version).toBe(excluded.version + (round === 0 ? 1 : 0));
      expect((await get(nora)).version).toBe(observed.version);
      if (round === 0) {
        await step(aritz, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() });
        await step(aritz, "ready", { destinationVersion: 1 });
        const plan = (await get(aritz)).renewal!.reservation;
        await step(aritz, "ack", { newDeviceId: plan.newDeviceId, newSigningKey: plan.newSigningKey, destinationVersion: 2, receipt: key() });
      }
    }
    const durable = await runInDurableObject(stub(aritz), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data));
    expect(durable.renewalActivityUsed).toEqual(["nora"]);
    expect(durable.renewalReturned).toEqual([]);
    expect(await runInDurableObject(stub(aritz), (_o, s) => s.storage.sql.exec("SELECT 1 FROM renewal_command WHERE action = 'resume'").toArray())).toEqual([]);
    expect((await step(aritz, "prepare", { pendingResources: 0, coverageCommitment: key() })).renewal.preparation).not.toBeNull();
  });

  it("legacy credentials cannot acquire a renewal binding from a mutable registry PUT", async () => {
    const id = await setup(); await prepareSigning("nora");
    await edit(id, (m) => { delete m.credentials[0].signingKey; });
    expect((await call("PUT", id.path, { key: id.key, headers: { "If-Match": '"1"' }, body: {
      ...snapshot(), registry: { ...snapshot().registry, records: [{ d: "aritz", e: publicKey("nora") }] },
    } })).status).toBe(200);
    const plan = await reserve(id, 2);
    const foreign = await signed({ ...plan, signerDeviceId: "nora" });
    const r = await send(id, { ...plan, signature: foreign.signature });
    expect(r.status).toBe(409);
    expect(await json(r)).toEqual({ error: "renewal_key_binding_required" });
    expect((await get(id)).renewal).toBeNull();
  });

  it("requires a unique creator key and rejects 33 participants without truncation", async () => {
    const fresh = newList();
    const create = (records: unknown[]) => call("PUT", `/v2/lists/${fresh.syncId}`, { key: fresh.key, ip: fresh.ip,
      headers: { "If-Match": '"0"' }, body: { ...snapshot(), deviceId: "aritz", registry: { ...snapshot().registry, records } } });
    expect(await json(await create([]))).toEqual({ error: "renewal_key_binding_required" });
    expect(await json(await create([{ d: "aritz", e: key() }, { d: "aritz", e: key() }]))).toEqual({ error: "renewal_key_binding_required" });
    const id = await setup();
    for (let i = 0; i < 32; i++) await add(id, `participant-${i}`, i === 31 ? "web" : "device");
    const omittedWeb = await reserve(id, 1, ["aritz", ...Array.from({ length: 31 }, (_, i) => `participant-${i}`)]);
    expect(await json(await send(id, omittedWeb))).toEqual({ error: "renewal_participants_missing" });
    const full = await reserve(id, 1, ["aritz", ...Array.from({ length: 32 }, (_, i) => `participant-${i}`)]);
    expect((await send(id, full)).status).toBe(400);
    expect((await get(id)).renewal).toBeNull();
  });

  it("global command, byte and page limits contain every participant's entire rescue reserve", () => {
    const n = limits.V2_MAX_RENEWAL_PARTICIPANTS;
    const epochs = n * (n - 1) / 2;
    const rows = limits.V2_RENEWAL_LOG_COMMANDS + n * limits.V2_RENEWAL_RESCUE_COMMANDS_PER_SIGNER + epochs * limits.V2_RENEWAL_REFILL_COMMANDS + 2 * n + 1;
    const bytes = limits.V2_RENEWAL_LOG_BYTES + n * limits.V2_RENEWAL_RESCUE_BYTES_PER_SIGNER + epochs * limits.V2_RENEWAL_REFILL_BYTES + (2 * n + 1) * limits.V2_MAX_RENEWAL_BODY_BYTES;
    expect(rows).toBe(22465); expect(bytes).toBe(22920 * 1024);
    expect(rows).toBeLessThan(limits.V2_RENEWAL_LOG_MAX_COMMANDS);
    expect(bytes).toBeLessThan(limits.V2_RENEWAL_LOG_MAX_BYTES);
    // Each nonfinal page is count-full or has less than one command of slack.
    expect(Math.ceil(rows / limits.V2_RENEWAL_LOG_PAGE_COMMANDS) + Math.ceil(bytes / (limits.V2_RENEWAL_LOG_PAGE_BYTES - limits.V2_MAX_RENEWAL_BODY_BYTES - 512))).toBeLessThan(limits.V2_RENEWAL_LOG_MAX_PAGES);
  });

  it("commits the entire active epoch and enforces prev with atomic append", async () => {
    const id = await setup();
    const plan = await reserve(id);
    expect((await send(id, plan)).status).toBe(200);
    const before = await get(id);
    const wrong = await command(id, before.version, "ready", { prev: null, destinationVersion: 1 });
    expect(await json(await send(id, wrong))).toEqual({ error: "renewal_prev_mismatch" });
    expect((await get(id)).renewal!.height).toBe(1);
    const ready = await step(id, "ready", { destinationVersion: 1 });
    expect(ready.c.prev).toBe(await renewalHash(plan));
    expect(ready.renewal.head).toBe(await renewalHash(ready.c));
    const page = await json<{ commands: RenewalCommand[]; next: null }>(await call("GET", `${id.path}/renewal/log/${id.operationId}/${ready.renewal.head}/0`, { key: id.key }));
    expect(page.commands).toEqual([plan, ready.c]);
    expect(page.next).toBeNull();
    const malformed = { ...await command(id, ready.version, "abort") } as Record<string, unknown>;
    delete malformed.prev;
    expect((await call("PUT", `${id.path}/renewal`, { key: id.key, headers: { "If-Match": `"${ready.version}"` }, body: malformed })).status).toBe(400);
  });

  it("recovers after eight self-acknowledged branches and revocation without deleting history or other work", async () => {
    let id = await setup();
    const nora = await add(id);
    const initialPlan = await migrated(id, ["aritz", "nora"]);
    const targets = [id.targetSyncId];
    let now = Date.now();
    const clock = vi.spyOn(Date, "now").mockImplementation(() => now);
    try {
      for (let revision = 2; revision <= 9; revision++) {
        now += 61000; // Exercise history, without exceeding per-minute budgets.
        const previous = id.targetSyncId;
        id = { ...id, targetSyncId: b64u(rand(16)) };
        const replaced = await step(id, "replace", { revision, previousTargetSyncId: previous,
          participants: ["aritz", "nora"], newDeviceId: `aritz-${revision}`, newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
        await step(id, "ready", { destinationVersion: 1 });
        await step(id, "ack", { newDeviceId: replaced.c.newDeviceId, newSigningKey: replaced.c.newSigningKey, destinationVersion: 2, receipt: key() });
        targets.push(id.targetSyncId);
      }
      // Legitimate work in the last branch must keep the barrier across recovery.
      await step({ ...nora, targetSyncId: id.targetSyncId }, "ack", { newDeviceId: "nora-old", newSigningKey: key(), destinationVersion: 2, receipt: key() });
      const prepared = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
      expect((await revoke(nora, "aritz")).status).toBe(200);
      const before = await get(nora);
      expect(before.renewal!.branches).toHaveLength(8);
      let next = { ...nora, targetSyncId: b64u(rand(16)) };
      const recovered = await step(next, "recover", { revision: 10, previousTargetSyncId: id.targetSyncId,
        participants: ["aritz", "nora"], newDeviceId: "nora-fresh", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
      expect(recovered.renewal.branches).toEqual([]);
      expect(recovered.renewal.barrierVersion).toBe(prepared.version);
      const archive = await call("GET", `${id.path}/renewal/log/${id.operationId}/${before.renewal!.head}/0`, { key: nora.key });
      expect(archive.status).toBe(200);
      expect((await json<{ commands: RenewalCommand[] }>(archive)).commands[0]).toEqual(initialPlan);
      expect([before.renewal!.targetSyncId, ...before.renewal!.branches].sort()).toEqual(targets.sort());
      expect((await send(next, recovered.c)).status).toBe(200);
      const recycled = await command({ ...next, targetSyncId: targets[0]! }, recovered.version, "replace", {
        revision: 11, previousTargetSyncId: next.targetSyncId, participants: ["aritz", "nora"],
        newDeviceId: initialPlan.newDeviceId, newSigningKey: initialPlan.newSigningKey, targetCommitment: key(), inventoryCommitment: key(),
      });
      expect(await json(await send(next, recycled))).toEqual({ error: "renewal_identity_reused" });
      const recoveryTarget = next.targetSyncId;
      next = { ...next, targetSyncId: b64u(rand(16)) };
      const replacement = await step(next, "replace", { revision: 11, previousTargetSyncId: recoveryTarget,
        participants: ["aritz", "nora"], newDeviceId: "nora-final", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
      expect(replacement.renewal.barrier).toEqual(prepared.c);
      await step(next, "ready", { destinationVersion: 1 });
      await step(next, "ack", { newDeviceId: replacement.c.newDeviceId, newSigningKey: replacement.c.newSigningKey, destinationVersion: 2, receipt: key() });
      await step(next, "exclude", { participantDeviceId: "aritz", loss: true, receipt: key() });
      const prep = await step(next, "prepare", { pendingResources: 0, coverageCommitment: key() });
      const final = await step(next, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
      expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${final.version}"` } })).status).toBe(204);
    } finally { clock.mockRestore(); }
  });

  it("pinned multi-page log equals all rows and stays immutable across later appends", async () => {
    let id = await setup(); const accepted: RenewalCommand[] = [];
    let now = Date.now(); const clock = vi.spyOn(Date, "now").mockImplementation(() => now);
    try {
      accepted.push((await step(id, "reserve", { participants: ["aritz"], newDeviceId: "aritz-initial", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() })).c);
      for (let revision = 2; revision <= 280; revision++) {
        now += 61000; const previousTargetSyncId = id.targetSyncId; id = { ...id, targetSyncId: b64u(rand(16)) };
        accepted.push((await step(id, "replace", { revision, previousTargetSyncId, participants: ["aritz"], newDeviceId: `aritz-${revision}`, newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() })).c);
      }
      const tip = await get(id); const head = tip.renewal!.head;
      const first = await json<{ commands: RenewalCommand[]; next: number; height: number }>(await call("GET", `${id.path}/renewal/log/${id.operationId}/${head}/0`, { key: id.key }));
      expect(first.commands).toHaveLength(256); expect(first.next).toBe(256); expect(first.height).toBe(280);
      now += 61000; await step(id, "ready", { destinationVersion: 1 });
      const second = await json<{ commands: RenewalCommand[]; next: null; height: number }>(await call("GET", `${id.path}/renewal/log/${id.operationId}/${head}/${first.next}`, { key: id.key }));
      expect(second.next).toBeNull(); expect(second.height).toBe(280);
      const paged = [...first.commands, ...second.commands]; expect(paged).toEqual(accepted);
      const rows = await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec<{ data: string }>("SELECT data FROM renewal_command ORDER BY height LIMIT 280").toArray().map((r) => JSON.parse(r.data)));
      expect(paged).toEqual(rows);
      let previous: string | null = null;
      for (const c of paged) { expect(c.prev).toBe(previous); previous = await renewalHash(c); }
      expect(previous).toBe(head);
    } finally { clock.mockRestore(); }
  }, 120000);

  it("M1 by bytes: saturation cannot overflow revocation or spend the survivor's recovery/close budget", async () => {
    let id = await setup(); const nora = await add(id);
    const participants = ["aritz", "nora", ...Array.from({ length: 30 }, (_, i) => `local-${i}-` + "x".repeat(118))];
    let now = Date.now(); const clock = vi.spyOn(Date, "now").mockImplementation(() => now);
    try {
      await step(id, "reserve", { participants, newDeviceId: "aritz-initial", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
      let rejected = false;
      for (let revision = 2; revision < 200; revision++) {
        now += 61000;
        const before = await get(id); const old = id.targetSyncId;
        const target = { ...id, targetSyncId: b64u(rand(16)) };
        const c = await command(target, before.version, "replace", { revision, previousTargetSyncId: old,
          participants, newDeviceId: `aritz-${revision}`, newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
        const response = await send(target, c);
        if (response.status === 409) { expect(await json(response)).toEqual({ error: "renewal_log_full" }); rejected = true; break; }
        expect(response.status).toBe(200); id = target;
      }
      expect(rejected).toBe(true);
      const full = await get(nora);
      expect(full.renewal!.logBytes).toBeGreaterThan(256 * 1024);
      expect(full.renewal!.height).toBeLessThan(1024); // bytes, rather than count, stopped the attacker
      now += 61000;
      expect((await revoke(nora, "aritz")).status).toBe(200);
      const target = { ...nora, targetSyncId: b64u(rand(16)) };
      const recovered = await step(target, "recover", { revision: full.renewal!.revision + 1,
        previousTargetSyncId: id.targetSyncId, participants, newDeviceId: "nora-final", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
      await step(target, "ready", { destinationVersion: 1 });
      await step(target, "ack", { newDeviceId: recovered.c.newDeviceId, newSigningKey: recovered.c.newSigningKey, destinationVersion: 2, receipt: key() });
      now += 74 * 3600000;
      for (const participantDeviceId of participants.filter((p) => p !== "nora")) {
        now += 61000; await step(target, "exclude", { participantDeviceId, loss: true, receipt: key() });
      }
      const stored = await runInDurableObject(stub(nora), (_o, s) => s.storage.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = 'renewal'").one().data);
      expect(new TextEncoder().encode(stored).length).toBeLessThan(256 * 1024);
      expect(stored).not.toContain('"identities"'); expect(stored).not.toContain('"revokedIdentities"');
      const prep = await step(target, "prepare", { pendingResources: 0, coverageCommitment: key() });
      const confirmed = await step(target, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
      expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${confirmed.version}"` } })).status).toBe(204);
    } finally { clock.mockRestore(); }
  }, 120000);

  it("an extinguished barrier stays extinct after a later valid ack and replacement", async () => {
    const id = await setup(); const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    await step(nora, "resume"); expect((await revoke(nora, "aritz")).status).toBe(200);
    const b = { ...nora, targetSyncId: b64u(rand(16)) };
    const recovered = await step(b, "recover", { revision: 2, previousTargetSyncId: id.targetSyncId,
      participants: ["aritz", "nora"], newDeviceId: "nora-b", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    expect(recovered.renewal.barrier).toBeNull(); await step(b, "ready", { destinationVersion: 1 });
    await step(b, "ack", { newDeviceId: recovered.c.newDeviceId, newSigningKey: recovered.c.newSigningKey, destinationVersion: 2, receipt: key() });
    const c = { ...nora, targetSyncId: b64u(rand(16)) };
    const replaced = await step(c, "replace", { revision: 3, previousTargetSyncId: b.targetSyncId,
      participants: ["aritz", "nora"], newDeviceId: "nora-c", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    expect(replaced.renewal.barrier).toBeNull(); expect(replaced.renewal.barrierVersion).toBeNull();
  });

  it("returning after a stale confirmation cancels exclusion and blocks reconfirmation and DELETE", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    const prep = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    await step(id, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect((await capability(id)).status).toBe(200);
    await get(nora);
    await step(nora, "resume");
    const returned = await get(id);
    expect(returned.renewal!.exclusions).toEqual({});
    expect(returned.renewal!.confirmation).toBeNull();
    const confirm = await command(id, returned.version, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect(await json(await send(id, confirm))).toEqual({ error: "renewal_revalidation_required" });
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${returned.version}"` } })).status).toBe(409);
    await step(id, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() });
    await step(id, "ready", { destinationVersion: 3 });
    const reservation = returned.renewal!.reservation;
    await step(id, "ack", { newDeviceId: reservation.newDeviceId, newSigningKey: reservation.newSigningKey, destinationVersion: 3, receipt: key() });
    const pending = await get(id);
    expect(await json(await send(id, await command(id, pending.version, "prepare", { revision: 2, pendingResources: 0, coverageCommitment: key() })))).toEqual({ error: "renewal_participants_pending" });
  });

  it("replaces a revoked initiator before any destination record is received and closes", async () => {
    const id = await setup();
    const nora = await add(id);
    await step(id, "reserve", { participants: ["aritz", "nora"], newDeviceId: "aritz-unseen", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    expect((await revoke(nora, "aritz")).status).toBe(200);
    const next = { ...nora, targetSyncId: b64u(rand(16)) };
    const replaced = await step(next, "replace", { revision: 2, previousTargetSyncId: id.targetSyncId,
      participants: ["aritz", "nora"], newDeviceId: "nora-fresh", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    expect(replaced.renewal.revokedIdentities.aritz!.newDeviceId).toBe("aritz-unseen");
    await step(next, "ready", { destinationVersion: 1 });
    await step(next, "ack", { newDeviceId: replaced.c.newDeviceId, newSigningKey: replaced.c.newSigningKey, destinationVersion: 2, receipt: key() });
    await step(next, "exclude", { participantDeviceId: "aritz", loss: true, receipt: key() });
    const prep = await step(next, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const final = await step(next, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${final.version}"` } })).status).toBe(204);
  });

  it("web and revoked aborts cannot cancel or delete a source with another live credential", async () => {
    const id = await setup();
    const nora = await add(id);
    const web = await add(id, "web", "web");
    const plan = await reserve(id, 1, ["aritz", "nora", "web"]);
    expect((await send(id, plan)).status).toBe(200);
    expect((await send(web, await command(web, 2, "abort"))).status).toBe(403);
    expect((await revoke(id, "nora")).status).toBe(200);
    const before = await get(id);
    expect((await send(nora, await command(nora, before.version, "abort"))).status).toBe(401);
    expect((await get(id)).renewal!.abortion).toBeNull();
    const aborted = await step(id, "abort");
    expect((await call("GET", id.path, { key: id.key })).status).toBe(200);
    expect(await json(await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${aborted.version}"` } }))).toEqual({ error: "devices_active" });
  });
  it("CAS chooses one initiator; winner retries recover the same durable reservation", async () => {
    const id = await setup();
    const nora = await add(id);
    const first = await reserve(id, 1, ["aritz", "nora"]);
    const other = await reserve({ ...nora, operationId: b64u(rand(16)), targetSyncId: b64u(rand(16)) }, 1, ["aritz", "nora"]);
    const results = await Promise.all([send(id, first), send(nora, other)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 412]);
    const state = await get(id);
    const winner = state.renewal!.operationId === first.operationId ? first : other;
    const owner = winner === first ? id : nora;
    expect((await send(owner, winner)).status).toBe(200);
    expect((await get(id)).version).toBe(2);
    const recovered = await runInDurableObject(stub(id), (_o, s) => JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM resource WHERE name = 'renewal'").one().data));
    expect(recovered.plan).toEqual(await renewalHash(winner));
  });

  it("requires a strong signed CAS, correct source/caller and bounded commands", async () => {
    const id = await setup();
    const c = await reserve(id);
    expect((await send(id, c, null)).status).toBe(428);
    for (const tag of ['*', 'W/"1"', '"0"', '"1", "2"']) expect((await send(id, c, tag)).status).toBe(412);
    expect((await send(id, { ...c, signerDeviceId: "nora" })).status).toBe(403);
    expect((await send(id, { ...c, sourceSyncId: b64u(rand(16)) })).status).toBe(403);
    expect((await send(id, { ...c, signature: "AAAA" })).status).toBe(400);
    expect((await send(id, { ...c, secret: "not-allowed" })).status).toBe(400);
    expect((await call("PUT", `${id.path}/renewal`, { key: id.key, headers: { "If-Match": '"1"' }, body: { ...c, padding: "a".repeat(32 * 1024) } })).status).toBe(413);
  });

  it("works with all generation/daily/content quotas full; has its own request limit", async () => {
    const id = await setup();
    await edit(id, (m) => {
      m.knownRecords = Array.from({ length: 512 }, (_, i) => `record${i}`);
      while (m.credentials.length < 64) m.credentials.push({ deviceId: `gone${m.credentials.length}`, verifier: null, revoked: true, records: [] });
      m.recordTimes = Array(16).fill(Date.now()); m.approvals = Array(8).fill(Date.now());
    });
    await runInDurableObject(stub(id), (_o, s) => {
      s.storage.sql.exec("CREATE TABLE IF NOT EXISTS rate (key TEXT PRIMARY KEY, start INTEGER NOT NULL, count INTEGER NOT NULL) WITHOUT ROWID");
      for (const name of ["list", "r:aritz", "w:aritz"]) s.storage.sql.exec("INSERT INTO rate VALUES (?, ?, ?)", name, Date.now(), 10000);
      for (let i = 0; i < 64; i++) s.storage.sql.exec("INSERT INTO slot VALUES (?, ?, 1, 'opaque')", `person${i}`, `writer${i}`);
    });
    const plan = await reserve(id);
    expect((await send(id, plan)).status).toBe(200);
    expect((await get(id)).renewal!.plan).toEqual(plan);
    let last: Response | undefined;
    for (let i = 0; i < 62; i++) {
      last = await call("GET", `${id.path}/renewal`, { key: id.key });
      if (last.status === 429) break;
    }
    expect(last!.status).toBe(429);
    expect(Number(last!.headers.get("Retry-After"))).toBeGreaterThan(0);
  });

  it("includes every live phone/web; old identities and signing keys cannot be reused", async () => {
    const id = await setup();
    await add(id, "web", "web");
    expect((await send(id, await reserve(id))).status).toBe(409);
    const c = await reserve(id, 1, ["aritz", "web"]);
    expect((await send(id, await signed({ ...c, newDeviceId: "aritz" }))).status).toBe(409);
    await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("UPDATE resource SET data = ? WHERE name = 'registry'", JSON.stringify({ records: [{ d: "aritz", e: c.newSigningKey }], vouches: [], revocations: [] })));
    expect((await send(id, c)).status).toBe(409);
    expect((await send(id, await signed({ ...c, targetSyncId: b64u(rand(16)), newSigningKey: key() }))).status).toBe(200);
  });

  it("cancels unfinished invitations durably, blocks new invites/approvals and keeps approved recovery", async () => {
    await prepareSigning("nora");
    const id = await setup();
    const offer = { v: 2, host: { d: "aritz" }, c: key() };
    const created = await call("POST", `${id.path}/invites`, { key: id.key, body: { offer } });
    const { inviteId } = await json<{ inviteId: string }>(created);
    const approved = await json<{ inviteId: string }>(await call("POST", `${id.path}/invites`, { key: id.key, body: { offer } }));
    const guestKey = key();
    const publicPath = `/v2/invites/${approved.inviteId}`;
    const privatePath = `${id.path}/invites/${approved.inviteId}`;
    expect((await call("POST", `${publicPath}/answer`, { body: { answer: { v: 2, guest: { d: "nora", e: publicKey("nora") }, vouch: {} }, serviceCredentialVerifier: await verifier(guestKey) } })).status).toBe(201);
    expect((await call("POST", `${privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: key() } } })).status).toBe(200);
    const hash = async (part: string, text: string) => encodeB64Url(await sha256(new TextEncoder().encode(`gift-huddle-pairing-checkpoint-${part}-v1\0${text}`)));
    expect((await call("POST", `${privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: { c: "opaque" }, checkpoint: { common: await hash("common", "AAAA"), registry: await hash("registry", canonicalJson({ ...snapshot().registry, records: [{ d: id.deviceId, e: publicKey(id.deviceId) }] })) } } })).status).toBe(200);
    expect((await call("POST", `${id.path}/capability`, { key: guestKey, body: { commonFormat: 2, renewalProtocol: 1 } })).status).toBe(200);
    expect((await send(id, await reserve(id, 3, ["aritz", "nora"]))).status).toBe(200);
    expect((await call("GET", `/v2/invites/${inviteId}/offer`)).status).toBe(404);
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer } })).status).toBe(409);
    expect((await call("POST", `${id.path}/invites/${inviteId}/approve`, { key: id.key, headers: { "If-Match": '"2"' }, body: { package: {} } })).status).toBe(409);
    expect((await call("GET", `${publicPath}/result`, { key: guestKey })).status).toBe(200);
    expect((await call("GET", `${publicPath}/checkpoint`, { key: guestKey })).status).toBe(200);
    const state = await json<{ canApprove: boolean }>(await call("GET", privatePath, { key: id.key }));
    expect(state.canApprove).toBe(false);
    expect(await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("SELECT id FROM invite").toArray())).toEqual([{ id: approved.inviteId }]);
  });

  it("web may read and ack itself, but cannot reserve/ready/exclude/prepare/confirm/replace/delete", async () => {
    const id = await setup();
    const web = await add(id, "web", "web");
    // Send only the forbidden request: send() would also create the destination
    // with a different signing key from the phone's subsequent reservation.
    expect((await call("PUT", `${web.path}/renewal`, { key: web.key, headers: { "If-Match": '"1"' },
      body: await reserve(web, 1, ["aritz", "web"]) })).status).toBe(403);
    expect(await get(web)).toEqual({ version: 1, renewal: null });
    await migrated(id, ["aritz", "web"]);
    for (const action of ["ready", "exclude", "prepare", "confirm", "replace", "revise"] as const) {
      expect((await send(web, await command(web, 4, action))).status).toBe(403);
    }
    await step(web, "ack", { newDeviceId: "web-new", newSigningKey: key(), receipt: key(), destinationVersion: 3 });
    expect((await call("DELETE", id.path, { key: web.key, headers: { "If-Match": '"5"' } })).status).toBe(403);
  });

  it("does not equate pairing or readiness with transfer; pending participants block the barrier and DELETE", async () => {
    const id = await setup();
    await add(id);
    await migrated(id, ["aritz", "nora"]);
    expect((await send(id, await command(id, 4, "prepare", { pendingResources: 0, coverageCommitment: key() }))).status).toBe(409);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": '"4"' } })).status).toBe(409);
    await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    expect((await send(id, await command(id, 5, "prepare", { pendingResources: 1, coverageCommitment: key() }))).status).toBe(400);
    const prepared = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    expect(prepared.renewal.barrierVersion).toBe(6);
  });

  it("orders old-source edits and the barrier, including the web; reads and slots remain available", async () => {
    const id = await setup();
    const web = await add(id, "web", "web");
    await migrated(id, ["aritz", "web"]);
    await step(web, "ack", { newDeviceId: "web-new", newSigningKey: key(), receipt: key(), destinationVersion: 3 });
    expect((await call("PUT", `${id.path}/common`, { key: web.key, headers: { "If-Match": '"5"' }, body: { common: "BBBB" } })).status).toBe(200);
    expect((await send(id, await command(id, 5, "prepare", { pendingResources: 0, coverageCommitment: key() }))).status).toBe(412);
    const prepared = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const frozen = prepared.version;
    for (const caller of [id, web]) {
      const res = await call("PUT", `${id.path}/common`, { key: caller.key, headers: { "If-Match": `"${frozen}"` }, body: { common: "CCCC" } });
      expect(await json(res)).toEqual({ error: "renewal_frozen" });
    }
    expect((await call("PUT", id.path, { key: id.key, headers: { "If-Match": `"${frozen}"` }, body: snapshot() })).status).toBe(409);
    const read = await json<{ common: string }>(await call("GET", id.path, { key: web.key }));
    expect(read.common).toBe("BBBB");
    const repeated = await send(id, prepared.c);
    expect(repeated.status).toBe(200);
    expect((await get(id)).version).toBe(frozen);
  });

  it("any migrated active phone continues; exact final snapshot and latest ETag are required for retirement", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    await step(nora, "ack", { newDeviceId: "nora-new", newSigningKey: key(), receipt: key(), destinationVersion: 3 });
    const prep = await step(nora, "prepare", { pendingResources: 0, coverageCommitment: key() });
    expect((await send(nora, await command(nora, prep.version, "confirm", { snapshotVersion: prep.version - 1, pendingResources: 0, coverageCommitment: key() }))).status).toBe(409);
    expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${prep.version}"` } })).status).toBe(409);
    const final = await step(nora, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${prep.version}"` } })).status).toBe(412);
    expect((await call("DELETE", id.path, { key: nora.key, headers: { "If-Match": `"${final.version}"` } })).status).toBe(204);
    expect((await call("GET", `${id.path}/renewal`, { key: nora.key })).status).toBe(410);
    expect((await call("PUT", id.path, { key: id.key, headers: { "If-Match": '"0"' }, body: { ...snapshot(), deviceId: "aritz" } })).status).toBe(410);
    const rows = await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec<{ data: string }>("SELECT data FROM state").toArray());
    expect(rows).toEqual([{ data: '{"retired":true}' }]);
    expect(await runInDurableObject(stub(id), (_o, s) => s.storage.sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('resource','slot','invite')").toArray())).toEqual([]);
  });

  it("revocation invalidates receipts/close but never unfreezes content; signed revise and explicit loss recover", async () => {
    const id = await setup();
    const nora = await add(id);
    const originalPlan = await migrated(id, ["aritz", "nora"]);
    await step(nora, "ack", { newDeviceId: "nora-new", newSigningKey: key(), receipt: key(), destinationVersion: 3 });
    const prep = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    expect((await revoke(id, "nora")).status).toBe(200);
    expect((await get(id)).renewal!.needsRevalidation).toBe(true);
    expect((await get(id)).renewal!.revokedIdentities.nora!.newDeviceId).toBe("nora-new");
    expect((await send(id, await command(id, prep.version + 1, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() }))).status).toBe(409);
    await step(id, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() });
    expect((await get(id)).renewal!.revokedIdentities.nora!.newDeviceId).toBe("nora-new");
    expect((await call("PUT", `${id.path}/common`, { key: id.key, headers: { "If-Match": '"8"' }, body: { common: "CCCC" } })).status).toBe(409);
    await step(id, "ready", { destinationVersion: 4 });
    await step(id, "ack", { newDeviceId: "aritz-new", newSigningKey: originalPlan.newSigningKey, receipt: key(), destinationVersion: 4 });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    const last = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const final = await step(id, "confirm", { snapshotVersion: last.version, pendingResources: 0, coverageCommitment: key() });
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${final.version}"` } })).status).toBe(204);
  });

  it("rejects cross-operation, cross-destination/revision receipt replay and identity substitution", async () => {
    const id = await setup();
    const plan = await migrated(id);
    const state = await get(id);
    const ack = state.renewal!.acknowledgements.aritz!;
    for (const change of [{ operationId: b64u(rand(16)) }, { targetSyncId: b64u(rand(16)) }, { revision: 2 }]) {
      expect((await send(id, await signed({ ...ack, sourceVersion: state.version, ...change }))).status).toBe(409);
    }
    expect((await send(id, await signed({ ...ack, sourceVersion: state.version, newDeviceId: "substituted", newSigningKey: plan.newSigningKey }))).status).toBe(409);
    expect((await send(id, ack)).status).toBe(200);
  });

  it("reservation does not expire; explicit replacement retains the old branch and requires fresh receipts", async () => {
    const id = await setup();
    await migrated(id);
    const prep = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const before = await get(id);
    const now = Date.now();
    const clock = vi.spyOn(Date, "now").mockReturnValue(now + 30 * 86400000);
    try {
      expect((await get(id)).renewal!.targetSyncId).toBe(id.targetSyncId);
    } finally { clock.mockRestore(); }
    const target = b64u(rand(16));
    const nextId = { ...id, targetSyncId: target };
    const replacement = await command(nextId, before.version, "replace", { revision: 2, participants: ["aritz"], newDeviceId: "aritz-next", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key(), previousTargetSyncId: id.targetSyncId });
    expect((await send(nextId, replacement)).status).toBe(200);
    const next = await get(id);
    expect(next.renewal!.branches).toEqual([id.targetSyncId]);
    expect(next.renewal!.acknowledgements).toEqual({});
    expect(next.renewal!.ready).toBeNull();
    expect(next.renewal!.barrierVersion).toBe(prep.version);
    expect(next.renewal!.barrier).toEqual(prep.c);
  });

  it("a revoked reservation signer requires replacement and its last identity survives replace/revise", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    expect((await revoke(nora, "aritz")).status).toBe(200);
    const state = await get(nora);
    const revise = await command(nora, state.version, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() });
    expect(await json(await send(nora, revise))).toEqual({ error: "renewal_replace_required" });
    const recycled = await command({ ...nora, targetSyncId: b64u(rand(16)) }, state.version, "replace", {
      revision: 2, previousTargetSyncId: id.targetSyncId, participants: ["aritz", "nora"],
      newDeviceId: state.renewal!.reservation.newDeviceId, newSigningKey: state.renewal!.reservation.newSigningKey,
      targetCommitment: key(), inventoryCommitment: key(),
    });
    expect(await json(await send(nora, recycled))).toEqual({ error: "renewal_identity_reused" });
    const next = { ...nora, targetSyncId: b64u(rand(16)) };
    await step(next, "replace", { revision: 2, previousTargetSyncId: id.targetSyncId, participants: ["aritz", "nora"], newDeviceId: "nora-new", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    const replaced = await get(nora);
    expect(replaced.renewal!.revokedIdentities.aritz!.newDeviceId).toBe("aritz-new");
    expect(replaced.renewal!.branches).toEqual([id.targetSyncId]);
    await step(next, "revise", { revision: 3, participants: ["aritz", "nora"], inventoryCommitment: key() });
    expect((await get(nora)).renewal!.revokedIdentities).toEqual(replaced.renewal!.revokedIdentities);
  });

  it("hourly activity never permits loss before 72 hours and permits it by the next hour", async () => {
    const hour = 3600000, now = Math.floor(Date.now() / hour) * hour + 17 * 60000;
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(now);
      const id = await setup();
      await add(id);
      const plan = await reserve(id, 1, ["aritz", "nora"]);
      expect((await send(id, plan)).status).toBe(200);
      await step(id, "ready", { destinationVersion: 1 });
      await step(id, "ack", { newDeviceId: plan.newDeviceId, newSigningKey: plan.newSigningKey, receipt: key(), destinationVersion: 2 });
      // Legacy exact timestamp, rounded by the next authenticated command.
      await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = now - 72 * hour; });
      const exclusion = await command(id, 4, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
      expect(await json(await send(id, exclusion))).toEqual({ error: "renewal_participant_active" });
      vi.setSystemTime(Math.ceil(now / hour) * hour);
      expect((await send(id, exclusion)).status).toBe(200);
    } finally { vi.useRealTimers(); }
  });

  it("ready requires the reservation signer and acknowledged participants cannot be excluded", async () => {
    const id = await setup();
    const nora = await add(id);
    const plan = await reserve(id, 1, ["aritz", "nora"]);
    expect((await send(id, plan)).status).toBe(200);
    expect((await send(nora, await command(nora, 2, "ready", { destinationVersion: 1 }))).status).toBe(403);
    await step(id, "ready", { destinationVersion: 1 });
    await step(id, "ack", { newDeviceId: plan.newDeviceId, newSigningKey: plan.newSigningKey, receipt: key(), destinationVersion: 2 });
    expect(await json(await send(id, await command(id, 4, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() })))).toEqual({ error: "renewal_participant_active" });
    await step(nora, "ack", { newDeviceId: "nora-new", newSigningKey: key(), receipt: key(), destinationVersion: 2 });
    expect(await json(await send(id, await command(id, 5, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() })))).toEqual({ error: "renewal_already_migrated" });
    const replacement = await command({ ...nora, targetSyncId: b64u(rand(16)) }, 5, "replace", { revision: 2, previousTargetSyncId: id.targetSyncId,
      participants: ["aritz", "nora"], newDeviceId: "nora-next", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    // Nora is migrated here; a separate non-migrated participant cannot replace.
    const leo = await add(id, "leo");
    expect((await send(leo, await signed({ ...replacement, signerDeviceId: "leo", participants: ["aritz", "nora", "leo"] }))).status).toBe(403);
  });

  it("an authenticated excluded participant cancels its exclusion and cannot revise it away", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    const prep = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    expect((await send(nora, await command(nora, prep.version, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() }))).status).toBe(403);
    await step(nora, "resume");
    const state = await get(id);
    expect(state.renewal!.exclusions).toEqual({});
    expect(state.renewal!.preparation).toBeNull();
    expect(state.renewal!.needsRevalidation).toBe(true);
    expect(state.renewal!.barrierVersion).toBe(prep.version);
  });

  it("empty destinations never consume the permanent branch budget and abort leaves a signed tombstone", async () => {
    const id = await setup();
    const caller = { deviceId: "aritz", revoked: false, role: "device" as const };
    const ctx = { syncId: id.syncId, version: 1, caller, devices: [caller], signingKeys: [] };
    let outcome = transitionRenewal(null, await reserve(id), ctx);
    for (let revision = 2; revision <= 12; revision++) {
      if (!outcome.ok) throw new Error("unexpected transition failure");
      const before = outcome.state;
      outcome = transitionRenewal(before, { ...await reserve(id, revision), action: "replace", revision, newDeviceId: `aritz-${revision}`, targetSyncId: b64u(rand(16)), previousTargetSyncId: before.targetSyncId }, { ...ctx, version: revision });
      expect(outcome.ok).toBe(true);
      if (outcome.ok) expect(outcome.state.branches).toEqual([]);
    }
    const plan = await reserve(id);
    expect((await send(id, plan)).status).toBe(200);
    const aborted = await step(id, "abort");
    expect(aborted.renewal.abortion).toEqual(aborted.c);
    expect((await send(id, aborted.c)).status).toBe(200);
    expect((await get(id)).renewal!.abortion).toEqual(aborted.c);
    expect((await call("POST", `${id.path}/invites`, { key: id.key, body: { offer: { v: 2, host: { d: "aritz" }, c: key() } } })).status).toBe(201);
    const next = { ...id, operationId: b64u(rand(16)), targetSyncId: b64u(rand(16)) };
    expect((await send(next, await signed({ ...await reserve(next, aborted.version), prev: null }))).status).toBe(200);
  });

  it("refuses publication until the destination exists with the committed creator", async () => {
    const id = await setup();
    const plan = await reserve(id);
    expect(await json(await call("PUT", `${id.path}/renewal`, { key: id.key, headers: { "If-Match": '"1"' }, body: plan }))).toEqual({ error: "renewal_destination_missing" });
    await createTarget({ ...plan, newSigningKey: key() });
    expect((await send(id, plan)).status).toBe(409);
    expect((await get(id)).renewal).toBeNull();
  });

  it.each([false, true])("rejects a destination with mutable K2 and a %s missing immutable binding", async (missing) => {
    const id = await setup(), target = newList();
    const plan = await reserve({ ...id, targetSyncId: target.syncId });
    const path = `/v2/lists/${target.syncId}`;
    const body = (e: string) => ({ ...snapshot(), deviceId: plan.newDeviceId, registry: { ...snapshot().registry, records: [{ d: plan.newDeviceId, e }] } });
    expect((await call("PUT", path, { key: target.key, ip: target.ip, headers: { "If-Match": '"0"' }, body: body(key()) })).status).toBe(201);
    expect((await call("PUT", path, { key: target.key, headers: { "If-Match": '"1"' }, body: body(plan.newSigningKey as string) })).status).toBe(200);
    if (missing) await edit({ ...id, syncId: target.syncId }, (m) => { delete m.credentials[0].signingKey; });
    const response = await send(id, plan);
    expect(response.status).toBe(409);
    expect(await json(response)).toEqual({ error: "renewal_destination_missing" });
    expect((await get(id)).renewal).toBeNull();
  });

  it("revise retains transferred callers, branch evidence and mappings for a later revocation", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    const ack = await step(nora, "ack", { newDeviceId: "nora-new", newSigningKey: key(), receipt: key(), destinationVersion: 2 });
    await step(nora, "revise", { revision: 2, participants: ["aritz", "nora"], inventoryCommitment: key() });
    await step(nora, "ready", { destinationVersion: 2 });
    expect((await send(id, await command(id, 7, "abort", { revision: 2 }))).status).toBe(409);
    expect((await revoke(id, "nora")).status).toBe(200);
    expect((await get(id)).renewal!.revokedIdentities.nora).toEqual(ack.c);
    const next = { ...id, targetSyncId: b64u(rand(16)) };
    await step(next, "replace", { revision: 3, previousTargetSyncId: id.targetSyncId, participants: ["aritz", "nora"],
      newDeviceId: "aritz-next", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    expect((await get(id)).renewal!.branches).toEqual([id.targetSyncId]);
  });

  it("signed replacement lifts a barrier only when no legitimate transferred participant remains", async () => {
    const id = await setup();
    const nora = await add(id);
    await migrated(id, ["aritz", "nora"]);
    await edit(id, (m) => { m.credentials.find((d: any) => d.deviceId === "nora").lastRequest = Date.now() - 73 * 3600000; });
    await step(id, "exclude", { participantDeviceId: "nora", loss: true, receipt: key() });
    const prepared = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    expect((await revoke(nora, "aritz")).status).toBe(200);
    expect((await get(nora)).renewal!.exclusions.nora).toBeUndefined();
    const invalidated = await get(nora);
    expect(invalidated.renewal!.barrierVersion).toBe(prepared.version);
    const next = { ...nora, targetSyncId: b64u(rand(16)) };
    await step(next, "replace", { revision: 2, previousTargetSyncId: id.targetSyncId, participants: ["aritz", "nora"],
      newDeviceId: "nora-next", newSigningKey: key(), targetCommitment: key(), inventoryCommitment: key() });
    const replaced = await get(nora);
    expect(replaced.renewal!.barrierVersion).toBeNull();
    expect(replaced.renewal!.barrier).toBeNull();
    expect((await call("PUT", `${id.path}/common`, { key: nora.key, headers: { "If-Match": `"${replaced.version}"` }, body: { common: "BBBB" } })).status).toBe(200);
  });

  it("a repeated confirmation after a later mutation does not renew the deletion permission", async () => {
    const id = await setup();
    await migrated(id);
    const prep = await step(id, "prepare", { pendingResources: 0, coverageCommitment: key() });
    const final = await step(id, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect((await capability(id)).status).toBe(200);
    expect((await send(id, final.c)).status).toBe(200);
    const stale = await get(id);
    expect(stale.renewal!.confirmedVersion).toBe(final.version);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${stale.version}"` } })).status).toBe(409);
    const confirmed = await step(id, "confirm", { snapshotVersion: prep.version, pendingResources: 0, coverageCommitment: key() });
    expect((await send(id, confirmed.c)).status).toBe(200);
    expect((await call("DELETE", id.path, { key: id.key, headers: { "If-Match": `"${confirmed.version}"` } })).status).toBe(204);
  });

  it("bounds replacement history and participant list before persistence", async () => {
    const id = await setup();
    const c = await reserve(id);
    const ctx = { syncId: id.syncId, version: 1, caller: { deviceId: "aritz", revoked: false, role: "device" as const }, devices: [{ deviceId: "aritz", revoked: false, role: "device" as const }], signingKeys: [] };
    const initial = transitionRenewal(null, c, ctx);
    expect(initial.ok).toBe(true);
    if (!initial.ok) return;
    const state = initial.state;
    state.transfers.aritz = await command(id, 1, "ack", { newDeviceId: c.newDeviceId, newSigningKey: c.newSigningKey, receipt: key(), destinationVersion: 1 });
    state.branches = Array.from({ length: 8 }, () => b64u(rand(16)));
    const next = { ...c, action: "replace", sourceVersion: 2, revision: 2, newDeviceId: "aritz-next", newSigningKey: key(), targetSyncId: b64u(rand(16)), previousTargetSyncId: id.targetSyncId };
    const outcome = transitionRenewal(state, next, { ...ctx, version: 2 });
    expect(!outcome.ok && outcome.error.body).toEqual({ error: "renewal_branches_full" });
    expect(canonicalJson(state)).toContain(id.targetSyncId);
    expect((await send(id, { ...c, participants: Array.from({ length: 65 }, (_, i) => `device${i}`) })).status).toBe(400);
  });
});
