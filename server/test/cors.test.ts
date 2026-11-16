import { describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:workers";
import worker from "../src/index";
import type { Env } from "../src/env";
import { b64u, call, rand } from "./helpers";

const origin = "https://gifthuddle.app";
const appOrigin = "https://web.gifthuddle.app";
const origins = [origin, appOrigin];
const headers = { Origin: origin };
const rejected = ["null", "https://evil.example", "https://gifthuddle-app.retired.example", "https://gifthuddle.retired.example", ...origins.flatMap((value) => [
  value.replace("https:", "http:"), `${value}.example.com`, value.replace("https://", "https://x"),
  `${value}:443`, `${value}:8443`, value.replace("https://", "https://usuario@"), `${value}/`,
])];
function cors(res: Response, expected: string | null = origin) {
  expect(res.headers.get("Access-Control-Allow-Origin")).toBe(expected);
  expect(res.headers.get("Vary")).toContain("Origin");
  expect(res.headers.get("Cache-Control")).toBe("no-store, no-transform");
  expect(res.headers.get("Access-Control-Allow-Credentials")).toBeNull();
  if (expected) expect(res.headers.get("Access-Control-Expose-Headers")).toBe("ETag, Retry-After");
}

describe("HTTP origins and retired v1", () => {
  it("allows the configured origins and rejects foreign origins before routing", async () => {
    for (const value of [undefined, ...origins, ...rejected]) {
      const res = await call("GET", "/unknown", { headers: value === undefined ? {} : { Origin: value } });
      expect(res.status).toBe(value === undefined || origins.includes(value) ? 404 : 403);
      cors(res, value !== undefined && origins.includes(value) ? value : null);
    }
  });
  it("adds CORS and no-store to every retired route, including preflight and upgrade", async () => {
    for (const method of ["GET", "OPTIONS", "PUT"]) {
      const res = await call(method, "/v1/lists/retired/ws", { headers: { ...headers, Upgrade: "websocket" } });
      expect(res.status).toBe(410); cors(res);
    }
  });
  it("keeps the same two defaults and honors the configured origin", async () => {
    for (const Origin of [...origins, ...rejected]) {
      const res = await worker.fetch(new Request("https://sync.test/unknown", { headers: { Origin } }), { ...env, ALLOWED_ORIGIN: undefined } as unknown as Env);
      expect(res.status).toBe(origins.includes(Origin) ? 404 : 403);
      cors(res, origins.includes(Origin) ? Origin : null);
    }
    const res = await worker.fetch(new Request("https://sync.test/unknown", { headers: { Origin: "https://other.example" } }), { ...env, ALLOWED_ORIGIN: "https://other.example" });
    expect(res.status).toBe(404); cors(res, "https://other.example");
  });
  it("wraps limiter and internal errors without disclosing details", async () => {
    for (const status of [429, 500]) {
      const limiter = { limit: vi.fn(async () => { if (status === 500) throw Error("private"); return { success: false }; }) };
      const res = await worker.fetch(new Request("https://sync.test/v2/lists/unknown", { headers }), { ...env, IP_LIMITER: limiter } as unknown as Env);
      expect(res.status).toBe(status); cors(res);
      expect(await res.text()).not.toContain("private");
    }
  });
});

describe("v2 common and guard CORS", () => {
  it.each([...origins, ...rejected])("checks and echoes exactly %s on all new routes", async (Origin) => {
    const id = b64u(rand(16));
    const allowed = origins.includes(Origin);
    const paths: [string, string][] = [
      [`/v2/lists/${id}/common`, "PUT"],
      ...["prepare", "commit", "cancel", "resume", "open"].map((action): [string, string] => [`/v2/lists/${id}/guards/nora/${action}`, action === "prepare" ? "PUT" : "POST"]),
    ];
    for (const [path, method] of paths) {
      const pre = await call("OPTIONS", path, { headers: { Origin, "Access-Control-Request-Method": method, "Access-Control-Request-Headers": "authorization,content-type,if-match" } });
      expect(pre.status).toBe(allowed ? 204 : 403); cors(pre, allowed ? Origin : null);
      const actual = await call(method, path, { headers: { Origin }, body: { proofs: [{ version: 1, guardToken: b64u(rand(32)), prueba: b64u(rand(32)) }] } });
      expect(actual.status).toBe(allowed ? path.endsWith("/open") ? 404 : 401 : 403);
      cors(actual, allowed ? Origin : null);
    }
  });
});
