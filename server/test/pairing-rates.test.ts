// 1.0.2: the web and the phones poll an invitation while their pairing screens
// are open. This simulates normal, slow web pairings from one home IP at the
// app's client rates (seeded jitter) and checks that the Worker limits as
// configured (`limits.ts`, `wrangler.toml`) never answer 429:
//  - the web polling for the offer every 1-2 s for the first 2 minutes, then
//    every 3-4 s (those 404s count in the per-IP invitation limit),
//  - the phone creating the invitation and polling it every 1-2 s, at most 30
//    requests a minute, until answered, then revealing,
//  - the web reading the offer, answering and polling the result with the
//    app's client budget (at most 25 requests to the invitation in any rolling
//    60 s, counting two per poll), the person confirming after ~10 s and the
//    phone approving ~60 s after the scan, then the checkpoint read and release.
// Time is simulated with fake `Date` (the list object reads `Date.now()`); the
// two rate limit bindings are replaced by wall-clock fixed windows with the
// configured limits, because the local binding keeps real time.
import { afterEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import worker from "../src/index";
import type { Env } from "../src/env";
import { V2_CREDENTIAL_REQUESTS, V2_INVITE_REQUESTS_PER_INVITE, V2_INVITE_REQUESTS_PER_IP, WINDOW_MS } from "../src/limits";
import { b64u, newList, rand } from "./helpers";
import { decodeB64Url, encodeB64Url, sha256 } from "../src/encoding";

/** Wall-clock aligned fixed window per key, like the `ratelimits.simple` binding. */
function windowLimiter(limit: number) {
  const buckets = new Map<string, { epoch: number; count: number }>();
  return {
    async limit({ key }: { key: string }) {
      const epoch = Math.floor(Date.now() / WINDOW_MS);
      const b = buckets.get(key);
      if (!b || b.epoch !== epoch) {
        buckets.set(key, { epoch, count: 1 });
        return { success: true };
      }
      if (b.count >= limit) return { success: false };
      b.count++;
      return { success: true };
    },
  };
}

/** Deterministic jitter (mulberry32). */
function seeded(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The app's `InvitePollPacer`: base + up to `spread` of jitter, within the budget. */
class Pacer {
  sent: number[] = [];
  constructor(readonly random: () => number, readonly budget: number, readonly perPoll = 2) {}
  note(now: number) { this.sent.push(now); }
  next(now: number, base = 1000, spread = 1000): number {
    const wait = now + base + Math.floor(this.random() * (spread + 1));
    this.sent = this.sent.filter((t) => now - t < WINDOW_MS);
    const room = this.budget - this.perPoll;
    if (this.sent.length <= room) return wait;
    const oldest = this.sent[this.sent.length - room - 1]!;
    return Math.max(wait, oldest + WINDOW_MS + 1);
  }
}

const digest = async (key: string) => encodeB64Url(await sha256(decodeB64Url(key, 32)!));

interface Plan { scanAt: number; approveAfter: number; confirmAfter: number }
type Entry = { at: number; path: string; invite: boolean; publicInvite: boolean; inviteId: string | null; listPath: string | null; status: number };

/** Runs one or more pairings behind one IP; resolves with the request log. */
async function simulate(plans: Plan[], seed: number): Promise<{ log: Entry[]; start: number; end: number }> {
  vi.useFakeTimers({ toFake: ["Date"] });
  let now = Date.UTC(2026, 10, 16, 12, 0, 30);
  vi.setSystemTime(now);
  const start = now;
  const random = seeded(seed);
  const fake = {
    ...env,
    IP_LIMITER: windowLimiter(200),
    INVITE_IP_LIMITER: windowLimiter(V2_INVITE_REQUESTS_PER_IP),
  } as unknown as Env;
  const ip = newList().ip;
  const log: Entry[] = [];
  const send = async (method: string, path: string, opts: { key?: string; body?: unknown; headers?: Record<string, string>; inviteId?: string; listPath?: string } = {}) => {
    const headers = new Headers(opts.headers);
    headers.set("CF-Connecting-IP", ip);
    if (opts.key) headers.set("Authorization", `Bearer ${opts.key}`);
    if (opts.body !== undefined) headers.set("Content-Type", "application/json");
    const res = await worker.fetch(new Request(`https://sync.test${path}`, { method, headers, body: opts.body === undefined ? undefined : JSON.stringify(opts.body) }), fake);
    log.push({ at: now, path, invite: /\/invites/.test(path), publicInvite: path.startsWith("/v2/invites/"), inviteId: opts.inviteId ?? null, listPath: opts.listPath ?? null, status: res.status });
    expect(res.status, `${method} ${path} at +${(now - start) / 1000}s`).not.toBe(429);
    return res;
  };

  const pairings = [];
  for (const plan of plans) {
    const home = newList();
    const listPath = `/v2/lists/${home.syncId}`;
    // The phone's family list (created long before; not part of the pairing).
    const created = await send("PUT", listPath, { key: home.key, headers: { "If-Match": '"0"' }, body: { common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: b64u(new Uint8Array(32).fill(7)) }], vouches: [], revocations: [] }, keyPackages: [], slots: [], deviceId: "aritz" } });
    expect(created.status).toBe(201);
    const inviteId = b64u(rand(16));
    pairings.push({
      plan, home, listPath, inviteId,
      publicPath: `/v2/invites/${inviteId}`,
      privatePath: `${listPath}/invites/${inviteId}`,
      guestKey: b64u(rand(32)),
      web: "offer" as "offer" | "result" | "code" | "approved" | "done",
      webAt: start + Math.floor(random() * 1000),
      webPacer: new Pacer(random, 25),
      host: "idle" as "idle" | "waiting" | "compare" | "approved",
      hostAt: start + plan.scanAt,
      hostPacer: new Pacer(random, 30),
      approveAt: Infinity,
    });
  }
  log.length = 0;

  while (pairings.some((p) => p.web !== "done")) {
    const live = pairings.filter((p) => p.web !== "done");
    now = Math.min(...live.flatMap((p) => [p.webAt, p.hostAt, p.approveAt]));
    vi.setSystemTime(now);
    const p = live.find((q) => q.approveAt === now || q.hostAt === now || q.webAt === now)!;
    const own = { inviteId: p.inviteId, listPath: p.listPath };
    if (now === p.approveAt) {
      p.approveAt = Infinity;
      const r = await send("POST", `${p.privatePath}/approve`, { ...own, key: p.home.key, headers: { "If-Match": '"1"' }, body: { package: { c: "opaque" }, role: "web" } });
      expect(r.status).toBe(200);
      p.host = "approved";
      continue;
    }
    if (now === p.hostAt) {
      if (p.host === "idle") {
        const r = await send("POST", `${p.listPath}/invites`, { ...own, key: p.home.key, body: { offer: { v: 2, host: { d: "aritz" }, c: b64u(rand(32)) }, inviteId: p.inviteId, guestPerson: "nora" } });
        expect(r.status).toBe(201);
        p.host = "waiting";
        p.hostAt = p.hostPacer.next(now);
      } else if (p.host === "waiting") {
        const r = await send("GET", p.privatePath, { ...own, key: p.home.key });
        p.hostPacer.note(now);
        const state = await r.json() as { answer?: unknown };
        if (state.answer) {
          expect((await send("POST", `${p.privatePath}/reveal`, { ...own, key: p.home.key, body: { reveal: { v: 2, n: b64u(rand(32)) } } })).status).toBe(200);
          p.host = "compare"; // the phone shows the code: no more polling
          p.hostAt = Infinity;
          p.approveAt = now + p.plan.approveAfter;
        } else {
          p.hostAt = p.hostPacer.next(now);
        }
      }
      continue;
    }
    // The web.
    if (p.web === "offer") {
      const r = await send("GET", `${p.publicPath}/offer`, own);
      if (r.status === 404) {
        // 1-2 s for the first 2 minutes, then 3-4 s (they count per IP).
        p.webAt = now - start < 120_000 ? p.webPacer.next(now) : p.webPacer.next(now, 3000, 1000);
        continue;
      }
      expect(r.status).toBe(200);
      p.webPacer.note(now);
      const answer = { v: 2, guest: { d: `web-${p.inviteId}`, e: b64u(rand(32)), k: "web", p: "nora" }, vouch: {} };
      expect((await send("POST", `${p.publicPath}/answer`, { ...own, body: { answer, serviceCredentialVerifier: await digest(p.guestKey) } })).status).toBe(201);
      p.webPacer.note(now);
      p.web = "result";
      p.webAt = p.webPacer.next(now);
    } else if (p.web === "result" || p.web === "approved") {
      const r = await send("GET", `${p.publicPath}/result`, { ...own, key: p.guestKey });
      p.webPacer.note(now);
      const body = await r.json() as { reveal?: unknown };
      if (r.status === 200) {
        await send("GET", `${p.publicPath}/checkpoint`, { ...own, key: p.guestKey });
        p.webPacer.note(now);
        await send("DELETE", `${p.publicPath}/checkpoint`, { ...own, key: p.guestKey });
        p.web = "done";
      } else if (p.web === "result" && body.reveal) {
        p.web = "code"; // the code is on screen: no polling until confirmed
        p.webAt = now + p.plan.confirmAfter;
      } else {
        p.webAt = p.webPacer.next(now);
      }
    } else if (p.web === "code") {
      p.web = "approved";
      p.webAt = now; // "They match": poll at once
    }
  }
  return { log, start, end: now };
}

/** Any rolling 60 s stays under each limit, independent of window alignment. */
function expectWithinLimits(log: Entry[]) {
  for (const l of log) {
    const window = log.filter((o) => o.at >= l.at && o.at - l.at < WINDOW_MS);
    expect(window.filter((o) => o.invite).length).toBeLessThanOrEqual(V2_INVITE_REQUESTS_PER_IP);
    for (const id of new Set(window.map((o) => o.inviteId))) {
      if (id === null) continue;
      // The Worker counts public requests once the invitation exists.
      const counted = window.filter((o) => o.inviteId === id && o.publicInvite && !(o.path.endsWith("/offer") && o.status === 404));
      expect(counted.length).toBeLessThanOrEqual(V2_INVITE_REQUESTS_PER_INVITE);
    }
    for (const list of new Set(window.map((o) => o.listPath))) {
      if (list === null) continue;
      expect(window.filter((o) => o.path.startsWith(list)).length).toBeLessThanOrEqual(V2_CREDENTIAL_REQUESTS);
    }
  }
  return Math.max(...log.map((l) => log.filter((o) => o.invite && o.at >= l.at && o.at - l.at < WINDOW_MS).length));
}

afterEach(() => { vi.useRealTimers(); });

describe("pairing at the 1.0.2 client rates", () => {
  it("a slow web pairing from one IP never gets a 429", async () => {
    const { log, start, end } = await simulate([{ scanAt: 60_000, approveAfter: 60_000, confirmAfter: 10_000 }], 1);
    // A minute before the scan and a minute on the phone: two minutes in all.
    expect(end - start).toBeGreaterThan(115_000);
    expect(log.some((l) => l.status === 429)).toBe(false);
    const peak = expectWithinLimits(log);
    console.log(`one pairing: ${log.length} requests, peak ${peak}/min on invitation routes from one IP`);
  }, 60_000);

  it("two web pairings behind one IP, with a long wait for the scan, never get a 429", async () => {
    const { log, end, start } = await simulate([
      // Both webs wait 2.5 minutes for their phones (past the 1-2 s phase).
      { scanAt: 150_000, approveAfter: 60_000, confirmAfter: 10_000 },
      { scanAt: 160_000, approveAfter: 45_000, confirmAfter: 5_000 },
    ], 2);
    expect(end - start).toBeGreaterThan(200_000);
    expect(log.some((l) => l.status === 429)).toBe(false);
    const peak = expectWithinLimits(log);
    console.log(`two pairings: ${log.length} requests, peak ${peak}/min on invitation routes from one IP`);
  }, 60_000);
});
