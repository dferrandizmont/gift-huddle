import { describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import worker from "../src/index";
import type { Env } from "../src/env";
import { canonicalJson, matchV2 } from "../src/v2-contract";
import { euNamespace } from "../src/eu-namespace";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";
import { V2_INVITE_REQUESTS_PER_INVITE } from "../src/limits";
import { b64u, call, json, newList, rand } from "./helpers";

async function setup(answered = true) {
  const id = newList();
  const path = `/v2/lists/${id.syncId}`;
  expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: {
    deviceId: "aritz", common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: b64u(new Uint8Array(32).fill(7)) }], vouches: [], revocations: [] }, keyPackages: [], slots: [],
  } })).status).toBe(201);
  const inviteId = b64u(rand(16));
  expect((await call("POST", `${path}/invites`, { key: id.key, body: { inviteId, offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) } } })).status).toBe(201);
  const publicPath = `/v2/invites/${inviteId}`;
  const privatePath = `${path}/invites/${inviteId}`;
  const guestKey = b64u(rand(32));
  const answer = async () => call("POST", `${publicPath}/answer`, { body: {
    answer: { v: 2, guest: { d: "web-nora", e: b64u(rand(32)), k: "web" }, vouch: {} },
    serviceCredentialVerifier: encodeB64Url(await sha256(decodeB64Url(guestKey, 32)!)),
  } });
  if (answered) expect((await answer()).status).toBe(201);
  const withdraw = (key: string | null = guestKey) => call("POST", `${publicPath}/withdraw`, { key, body: {} });
  const reveal = () => call("POST", `${privatePath}/reveal`, { key: id.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } });
  const approve = () => call("POST", `${privatePath}/approve`, { key: id.key, headers: { "If-Match": '"1"' }, body: { package: { c: "opaque" }, role: "web" } });
  return { ...id, path, publicPath, privatePath, guestKey, answer, withdraw, reveal, approve };
}

describe("guest invitation withdrawal", () => {
  it("before an answer has no authority; wrong/missing credentials and unknown ids have the same shape", async () => {
    const i = await setup(false);
    const unknown = await call("POST", `/v2/invites/${b64u(rand(16))}/withdraw`, { key: i.guestKey, body: {} });
    expect(unknown.status).toBe(404);
    const shape = await json(unknown);
    expect(await json(await i.withdraw())).toEqual(shape);
    expect((await i.answer()).status).toBe(201);
    for (const key of [null, b64u(rand(32))]) {
      const r = await i.withdraw(key);
      expect(r.status).toBe(404); expect(await json(r)).toEqual(shape);
    }
    expect((await call("GET", i.privatePath, { key: i.key })).status).toBe(200);
  });

  it("withdraws after answer/reveal, refuses approval and leaves no credential/checkpoint; repeats are harmless", async () => {
    const i = await setup();
    expect((await i.reveal()).status).toBe(200);
    expect((await i.withdraw()).status).toBe(204);
    expect((await i.withdraw()).status).toBe(404);
    expect((await call("GET", i.privatePath, { key: i.key })).status).toBe(404);
    expect((await i.approve()).status).toBe(404);
    for (const route of ["offer", "result", "checkpoint"]) {
      expect((await call("GET", `${i.publicPath}/${route}`, { key: i.guestKey })).status).toBe(404);
    }
    const state = await json(await call("GET", i.path, { key: i.key }));
    expect(state.version).toBe(1); expect(state.devices).toHaveLength(1);
    expect((await call("GET", i.path, { key: i.guestKey })).status).toBe(401);
  });

  it("also withdraws before reveal", async () => {
    const i = await setup();
    expect((await i.withdraw()).status).toBe(204);
    expect((await i.reveal()).status).toBe(404);
  });

  it("accepts only an empty object after guest authentication, without revealing invitation existence", async () => {
    const i = await setup();
    const unknown = `/v2/invites/${b64u(rand(16))}/withdraw`;
    for (const path of [`${i.publicPath}/withdraw`, unknown]) {
      for (const key of [null, b64u(rand(32))]) {
        const r = await call("POST", path, { key, body: { x: true } });
        expect(r.status).toBe(404); expect(await json(r)).toEqual({ error: "not_found" });
      }
    }
    const invalid = await call("POST", `${i.publicPath}/withdraw`, { key: i.guestKey, body: { x: true } });
    expect(invalid.status).toBe(400); expect(await json(invalid)).toEqual({ error: "bad_request" });
    expect((await call("GET", i.privatePath, { key: i.key })).status).toBe(200);
    expect((await call("POST", `${i.publicPath}/withdraw`, { key: i.guestKey, rawBody: " ".repeat(62) + "{}" })).status).toBe(204);
  });

  it("caps withdrawal at 64 streamed bytes before discovery or authentication", async () => {
    const i = await setup();
    for (const path of [`${i.publicPath}/withdraw`, `/v2/invites/${b64u(rand(16))}/withdraw`]) {
      for (const key of [null, i.guestKey]) {
        const r = await call("POST", path, { key, rawBody: " ".repeat(63) + "{}" });
        expect(r.status).toBe(413); expect(await json(r)).toEqual({ error: "too_large" });
      }
    }
    expect((await i.withdraw()).status).toBe(204);
  });

  it("approval wins: reports already_approved and preserves the repeatable package and credential", async () => {
    const i = await setup(); await i.reveal();
    const state = await json(await call("GET", i.path, { key: i.key }));
    const common = state.common as string;
    const registry = canonicalJson(state.registry);
    const hash = async (part: string, value: string) => encodeB64Url(await sha256(
      new TextEncoder().encode(`gift-huddle-pairing-checkpoint-${part}-v1\0${value}`),
    ));
    expect((await call("POST", `${i.privatePath}/approve`, {
      key: i.key, headers: { "If-Match": '"1"' }, body: {
        package: { c: "opaque" }, role: "web",
        checkpoint: { common: await hash("common", common), registry: await hash("registry", registry) },
      },
    })).status).toBe(200);
    for (let n = 0; n < 2; n++) {
      const r = await i.withdraw(); expect(r.status).toBe(409);
      expect(await json(r)).toEqual({ error: "already_approved" });
    }
    expect((await call("GET", `${i.publicPath}/result`, { key: i.guestKey })).status).toBe(200);
    expect((await call("GET", i.path, { key: i.guestKey })).status).toBe(200);
    expect(await json(await call("GET", `${i.publicPath}/checkpoint`, { key: i.guestKey }))).toEqual({ common, registry });
  });

  it("concurrent approval/withdrawal has exactly one winner", async () => {
    for (const withdrawFirst of [true, false]) {
      const i = await setup(); await i.reveal();
      const results = await Promise.all(withdrawFirst ? [i.withdraw(), i.approve()] : [i.approve(), i.withdraw()]);
      const statuses = results.map((r) => r.status).sort();
      expect([[200, 409], [204, 404]]).toContainEqual(statuses);
      const state = await json(await call("GET", i.path, { key: i.key }));
      expect(state.devices).toHaveLength(statuses[0] === 200 ? 2 : 1);
    }
  });

  it("shares the invitation quota even for wrong credentials and bounds the body", async () => {
    const i = await setup();
    const large = await call("POST", `${i.publicPath}/withdraw`, { key: i.guestKey, rawBody: JSON.stringify({ x: "x".repeat(64) }) });
    expect(large.status).toBe(413);
    // Answer has already consumed one request; every failed auth consumes one.
    for (let n = 1; n < V2_INVITE_REQUESTS_PER_INVITE; n++) expect((await i.withdraw(null)).status).toBe(404);
    const limited = await i.withdraw(); expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBeTruthy();
    expect((await call("GET", i.privatePath, { key: i.key })).status).toBe(200);
  });

  it("uses the shared per-IP limiter before discovery", async () => {
    const limit = vi.fn(async () => ({ success: false }));
    const fake = { ...env, INVITE_IP_LIMITER: { limit } } as unknown as Env;
    const r = await worker.fetch(new Request(`https://sync.test/v2/invites/${b64u(rand(16))}/withdraw`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
    }), fake);
    expect(r.status).toBe(429); expect(limit).toHaveBeenCalledOnce();
  });

  it("pending result has no hint that would slow the client's 1-2 s cadence", async () => {
    const i = await setup();
    const r = await call("GET", `${i.publicPath}/result`, { key: i.guestKey });
    expect(r.status).toBe(202); expect(r.headers.get("Retry-After")).toBeNull();
  });
});

describe("explicit local EU namespace adapter", () => {
  it("production and calls without local request proof always select eu", () => {
    const selected = { jurisdiction: vi.fn() };
    const ns = { jurisdiction: vi.fn(() => selected) };
    for (const LOCAL_DEV of [undefined, "false", "TRUE", "1"]) {
      expect(euNamespace(ns, { LOCAL_DEV })).toBe(selected);
    }
    expect(ns.jurisdiction).toHaveBeenCalledTimes(4);
    expect(ns.jurisdiction.mock.calls).toEqual([["eu"], ["eu"], ["eu"], ["eu"]]);
    ns.jurisdiction.mockClear();
    expect(euNamespace(ns, { LOCAL_DEV: "true" })).toBe(selected);
    expect(euNamespace(ns, {}, true)).toBe(selected);
    expect(ns.jurisdiction.mock.calls).toEqual([["eu"], ["eu"]]);
    ns.jurisdiction.mockClear();
    expect(euNamespace(ns, { LOCAL_DEV: "true" }, true)).toBe(ns);
    expect(ns.jurisdiction).not.toHaveBeenCalled();
  });

  it("fails closed off localhost, including upgrades and preflight, before quotas or object access", async () => {
    const touch = vi.fn(() => { throw new Error("must not touch a binding"); });
    const ns = { jurisdiction: touch, idFromName: touch, get: touch };
    const fake = { ...env, LOCAL_DEV: "true", LISTS_V2: ns, INVITES_V2: ns, LIMITER_V2: ns, RECOVERIES_V2: ns,
      IP_LIMITER: { limit: touch }, INVITE_IP_LIMITER: { limit: touch } } as unknown as Env;
    for (const host of ["sync.gifthuddle.app", "localhost.example.com", "127.0.0.2", "[::2]"]) {
      for (const method of ["GET", "POST", "OPTIONS"]) {
        const r = await worker.fetch(new Request(`https://${host}/v2/lists/${b64u(rand(16))}/ws`, {
          method, headers: { Upgrade: "websocket", "X-Local-Request": "true", "X-Forwarded-Host": "localhost" },
        }), fake);
        expect(r.status).toBe(500); expect(await json(r)).toEqual({ error: "internal" });
      }
    }
    expect(touch).not.toHaveBeenCalled();
  });
  it("routes a local public invitation with namespaces that cannot select jurisdiction", async () => {
    const i = await setup();
    const plain = <T extends Rpc.DurableObjectBranded | undefined>(binding: DurableObjectNamespace<T>) => ({
      jurisdiction() { throw new Error("local workerd has no jurisdiction"); },
      idFromName: binding.idFromName.bind(binding),
      get: binding.get.bind(binding),
    });
    const fake = { ...env, LOCAL_DEV: "true", LISTS_V2: plain(env.LISTS_V2), INVITES_V2: plain(env.INVITES_V2) } as unknown as Env;
    for (const host of ["localhost", "127.0.0.1", "[::1]"]) {
      expect((await worker.fetch(new Request(`http://${host}:8787${i.publicPath}/offer`), fake)).status).toBe(200);
    }
  });

  it("scopes local RPC proof to one locked request; the following alarm keeps EU", async () => {
    const i = await setup();
    const verifier = encodeB64Url(await sha256(decodeB64Url(i.guestKey, 32)!));
    const stub = env.LISTS_V2.get(env.LISTS_V2.idFromName(i.syncId));
    await runInDurableObject(stub, async (o, state) => {
      const internal = o as unknown as { env: Env };
      const original = internal.env;
      const jurisdiction = vi.fn(() => original.INVITES_V2);
      internal.env = { ...original, LOCAL_DEV: "true", INVITES_V2: {
        jurisdiction,
        idFromName: original.INVITES_V2.idFromName.bind(original.INVITES_V2),
        get: original.INVITES_V2.get.bind(original.INVITES_V2),
      } as unknown as Env["INVITES_V2"] };
      try {
        const invite = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM invite").one().data);
        const result = await o.handle({ localRequest: true, route: matchV2(`${i.publicPath}/withdraw`)!, method: "POST",
          verifier, client: i.ip, match: null, none: null, body: {} });
        expect(result.status).toBe(204); expect(jurisdiction).not.toHaveBeenCalled();
        // Simulate a release retry left behind by a lost response.
        state.storage.sql.exec("CREATE TABLE IF NOT EXISTS pending_release (data TEXT PRIMARY KEY)");
        state.storage.sql.exec("INSERT INTO pending_release (data) VALUES (?)", JSON.stringify({
          id: invite.id, syncId: i.syncId, expiresAt: invite.expiresAt, reservationId: invite.reservationId,
        }));
        await o.alarm();
        expect(jurisdiction).toHaveBeenCalledWith("eu");
        expect(state.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pending_release'").toArray()).toHaveLength(0);
        expect((await o.fetch(new Request("https://internal/ws"))).status).toBe(500);
      } finally {
        internal.env = original;
      }
    });
  });
  it("does not fall back when production jurisdiction fails", () => {
    const ns = { jurisdiction() { throw new Error("unavailable"); } };
    expect(() => euNamespace(ns, {})).toThrow("unavailable");
  });
});
