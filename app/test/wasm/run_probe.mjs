// node test/wasm/run_probe.mjs <dir with probe.wasm + probe.mjs> [timeoutSec] [chunkBytes]
// Runs the dart2wasm pairing probe in V8 (Node 24) with real WebCrypto and
// real fetch/streams: an echo server sends each fake-Worker response back in
// small chunks through WebSyncTransport. Prints the PROBE lines.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const dir = process.argv[2];
const chunk = Number(process.argv[4] ?? 700);
let requests = 0;
const server = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (d) => raw += d);
  req.on('end', async () => {
    requests++;
    const { s, h, b } = JSON.parse(raw);
    const bytes = Buffer.from(b, 'base64');
    res.writeHead(s, { ...h, 'Content-Type': 'application/json' });
    if (s === 204 || s === 304) { res.end(); return; }
    for (let i = 0; i < bytes.length; i += chunk) {
      res.write(bytes.subarray(i, i + chunk));
      await new Promise(r => setImmediate(r));
    }
    res.end();
  });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
globalThis.window = globalThis; globalThis.isSecureContext = true; globalThis.self = globalThis;
globalThis.PROBE_ECHO = `http://127.0.0.1:${server.address().port}`;
// Exit code: 0 only if every scenario passed and nothing escaped; 1 if a
// scenario failed or an error/rejection was uncaught (a wasm trap included);
// 2 on timeout.
let uncaught = 0;
const escaped = (kind) => (e) => {
  uncaught++;
  process.exitCode = 1; // whatever happens next, this run failed
  console.log(`[${kind}]`, e?.constructor?.name, String(e?.stack ?? e).slice(0, 4000));
};
process.on('uncaughtException', escaped('uncaughtException'));
process.on('unhandledRejection', escaped('unhandledRejection'));
const origLog = console.log;
console.log = (...a) => {
  origLog(...a);
  const done = /PROBE DONE ok=(\d+) fail=(\d+)/.exec(String(a[0]));
  if (done) {
    // Node reports a rejection left unhandled in this turn only after it:
    // let it (and anything queued) arrive before deciding the exit code.
    setTimeout(() => {
      origLog('echo requests', requests, 'uncaught', uncaught);
      server.close();
      process.exit(Number(done[2]) > 0 || uncaught > 0 ? 1 : 0);
    }, 50);
  }
};
const mod = await import(pathToFileURL(path.join(dir, 'probe.mjs')).href);
const app = await mod.compile(fs.readFileSync(path.join(dir, 'probe.wasm')));
const instance = await app.instantiate({});
try {
  instance.invokeMain();
} catch (e) {
  uncaught++;
  origLog('[main threw]', e?.constructor?.name, String(e?.stack ?? e).slice(0, 4000));
}
setTimeout(() => { origLog('NODE TIMEOUT, echo requests', requests, 'uncaught', uncaught); process.exit(uncaught > 0 ? 1 : 2); }, Number(process.argv[3] ?? 240) * 1000).unref();
