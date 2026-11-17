// node test/wasm/run_sync_socket_probe.mjs <directory with probe.wasm + probe.mjs>
// A loopback WebSocket server, with real text frames and the v2 subprotocol.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const server = http.createServer();
const sockets = new Set();
server.on('upgrade', (req, socket) => {
  sockets.add(socket);
  socket.on('close', () => sockets.delete(socket));
  socket.on('error', () => {});
  const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  const protocol = req.url === '/wrong-protocol' ? 'gift-huddle.v1' : 'gift-huddle.v2';
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\nSec-WebSocket-Protocol: ' + protocol + '\r\n\r\n');
  const text = (message) => {
    const bytes = Buffer.from(message);
    socket.write(Buffer.concat([Buffer.from([0x81, bytes.length]), bytes]));
  };
  setTimeout(() => {
    text('pong');
    text('{"type":"version","version":7}');
    text('{"type":"version","version":8}');
  }, 50);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
globalThis.window = globalThis;
globalThis.PROBE_SOCKET_BASE = `http://127.0.0.1:${server.address().port}`;
const dir = process.argv[2];
let failed = false;
let completed = false;
process.on('unhandledRejection', e => { failed = true; console.error(e); });
process.on('uncaughtException', e => { failed = true; console.error(e); });
const log = console.log;
console.log = (...args) => {
  log(...args);
  if (String(args[0]) === 'PROBE DONE ok=5 fail=0') completed = true;
};
try {
  const mod = await import(pathToFileURL(path.join(dir, 'probe.mjs')).href);
  const app = await mod.compile(fs.readFileSync(path.join(dir, 'probe.wasm')));
  const instance = await app.instantiate({});
  instance.invokeMain();
} catch (e) { failed = true; console.error(e); }
setTimeout(() => {
  for (const socket of sockets) socket.destroy();
  server.close();
  process.exit(completed && !failed ? 0 : 1);
}, 12000);
