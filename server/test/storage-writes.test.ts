import { expect, it } from "vitest";
import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { b64u, call, newList } from "./helpers";

const snapshot = () => ({ common: "AAAA", registry: { v: 2, l: "family", records: [{ d: "aritz", e: b64u(new Uint8Array(32).fill(7)) }], vouches: [], revocations: [] }, keyPackages: [], slots: [] });

it("measures SQL rows written by routine sync and public requests", async () => {
  const id = newList(), path = `/v2/lists/${id.syncId}`;
  const list = env.LISTS_V2.get(env.LISTS_V2.idFromName(id.syncId));
  const stubs = [list,
    env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:new:${id.ip}`)),
    env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:rows:${id.ip}`)),
    env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:guard:${id.ip}`)),
    env.LIMITER_V2.get(env.LIMITER_V2.idFromName(`v2:recovery:${id.ip}`)),
  ];
  stubs.push(env.STORAGE_LEDGER.get(env.STORAGE_LEDGER.idFromName("v2:storage")) as unknown as typeof list);
  if (env.CREATION_BUDGET) stubs.push(env.CREATION_BUDGET.get(env.CREATION_BUDGET.idFromName("v2:new-lists")) as unknown as typeof list);
  for (const stub of stubs) await runInDurableObject(stub, (o, state) => {
    const counted = o as unknown as { written: number };
    counted.written = 0;
    const sql = state.storage.sql, exec = sql.exec.bind(sql);
    sql.exec = ((...args: Parameters<SqlStorage["exec"]>) => {
      const cursor = exec(...args);
      counted.written += cursor.rowsWritten;
      return cursor;
    }) as SqlStorage["exec"];
  });
  const total = async () => (await Promise.all(stubs.map((stub) => runInDurableObject(stub, (o) => (o as unknown as { written: number }).written)))).reduce((a, b) => a + b, 0);
  const measured = async (run: () => Promise<unknown>) => { const before = await total(); await run(); return await total() - before; };
  const create = await measured(async () => expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"0"' }, body: { ...snapshot(), deviceId: "aritz" } })).status).toBe(201));
  // Prime activity metadata; subsequent unchanged reads must cost zero rows.
  await call("GET", path, { key: id.key });
  const get = await measured(async () => { for (let n = 0; n < 16; n++) expect((await call("GET", path, { key: id.key })).status).toBe(200); });
  const ping = await measured(() => runInDurableObject(list, async (o, state) => {
    const verifier = JSON.parse(state.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data).credentials[0].verifier;
    const socket = { deserializeAttachment: () => ({ deviceId: "aritz", credentialVerifier: verifier }), send: (text: string) => expect(text).toBe("pong"), close: () => { throw new Error("Unexpected close"); } } as unknown as WebSocket;
    await o.webSocketMessage(socket, "ping");
  }));
  const guard = await measured(async () => expect((await call("POST", `${path}/guards/nora/open`, { ip: id.ip, body: { proofs: [{ version: 1, guardToken: b64u(new Uint8Array(32).fill(2)), prueba: b64u(new Uint8Array(32).fill(3)) }] } })).status).toBe(404));
  const recovery = await measured(async () => { await call("GET", `/v2/recoveries/${b64u(new Uint8Array(32).fill(6))}`, { ip: id.ip, headers: { "X-Recovery-Cap": b64u(new Uint8Array(32).fill(8)) } }); });
  const put = await measured(async () => expect((await call("PUT", path, { key: id.key, ip: id.ip, headers: { "If-Match": '"1"' }, body: { ...snapshot(), common: "BBBB" } })).status).toBe(200));
  const falseBearer = await measured(async () => expect((await call("GET", path, { key: b64u(new Uint8Array(32).fill(9)), ip: id.ip })).status).toBe(401));
  await runInDurableObject(list, (_o, s) => {
    const m = JSON.parse(s.storage.sql.exec<{ data: string }>("SELECT data FROM state").one().data);
    m.rowBudget.written = 6000;
    s.storage.sql.exec("UPDATE state SET data = ?", JSON.stringify(m));
  });
  const rejection = await measured(async () => {
    for (let n = 0; n < 3; n++) expect((await call("PUT", `${path}/common`, { key: id.key, ip: id.ip, headers: { "If-Match": '\"2\"' }, body: { common: "CCCC" } })).status).toBe(429);
  });
  // Cold creation queries row counters without creating schemas or prepaying rows.
  expect({ create, get, ping, guard, recovery, put, falseBearer, rejection }).toEqual({ create: 30, get: 0, ping: 0, guard: 0, recovery: 0, put: 2, falseBearer: 0, rejection: 0 });
  expect(get).toBe(0); expect(ping).toBe(0);
});
