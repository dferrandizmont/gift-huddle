import { expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/env";

it("privacy: every v1 route and method returns gone without touching storage or limiters", async () => {
  const env = {} as Env;
  for (const path of ["/v1/", "/v1/lists/invalid", "/v1/invites/old/result", "/v1/unknown"]) {
    for (const method of ["GET", "PUT", "POST", "DELETE", "OPTIONS", "PATCH"]) {
      const response = await worker.fetch(new Request(`https://sync.test${path}`, { method }), env);
      expect(response.status).toBe(410);
      expect(await response.json()).toEqual({ error: "gone" });
    }
  }
});
