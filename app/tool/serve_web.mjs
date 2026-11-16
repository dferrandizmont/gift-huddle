// Minimal Cloudflare Pages static hosting for local CSP checks. No dependencies.
import { createServer } from 'node:http';
import { readFile, realpath, stat } from 'node:fs/promises';
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const appDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
let root = resolve(appDir, 'build/web');
let port = 8790;
for (let i = 2; i < process.argv.length; i++) {
  const flag = process.argv[i];
  if (flag === '--dir' && process.argv[i + 1]) root = resolve(appDir, process.argv[++i]);
  else if (flag === '--port' && process.argv[i + 1]) port = Number(process.argv[++i]);
  else throw new Error('Usage: node app/tool/serve_web.mjs [--dir build/web_probe] [--port 8790]');
}
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
root = await realpath(root);

function patternMatches(pattern, pathname) {
  const regex = pattern.split('*').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*');
  return new RegExp(`^${regex}$`).test(pathname);
}

const headerRules = [];
let current;
for (const line of (await readFile(resolve(root, '_headers'), 'utf8')).split(/\r?\n/)) {
  if (!line.trim() || line.trimStart().startsWith('#')) continue;
  if (!/^\s/.test(line)) {
    current = { pattern: line.trim(), headers: {} };
    headerRules.push(current);
  } else {
    const colon = line.indexOf(':');
    if (!current || colon < 0) throw new Error('Invalid _headers rule');
    current.headers[line.slice(0, colon).trim()] = line.slice(colon + 1).trim();
  }
}
// Without _redirects (and without 404.html) Pages serves index.html for
// unknown paths: the SPA fallback. Emulate that when the file is absent.
const redirectsText = await readFile(resolve(root, '_redirects'), 'utf8')
  .catch(error => (error.code === 'ENOENT' ? '/* /index.html 200' : Promise.reject(error)));
const redirectRules = redirectsText.split(/\r?\n/)
  .map(line => line.trim()).filter(line => line && !line.startsWith('#'))
  .map(line => {
    const [pattern, target, status = '302'] = line.split(/\s+/);
    if (!target.startsWith('/') || status !== '200') throw new Error('Only local 200 rewrites are supported');
    return { pattern, target };
  });

const mime = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json',
  '.wasm': 'application/wasm', '.css': 'text/css; charset=utf-8',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon', '.svg': 'image/svg+xml', '.txt': 'text/plain; charset=utf-8',
};
function insideRoot(path) {
  const rel = relative(root, path);
  return rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}
async function findFile(pathname) {
  const candidate = resolve(root, `.${pathname}`);
  if (!insideRoot(candidate)) return null;
  try {
    const canonical = await realpath(candidate);
    if (!insideRoot(canonical)) return null;
    const info = await stat(canonical);
    return info.isFile() ? { path: canonical, size: info.size } : null;
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return null;
    throw error;
  }
}

const server = createServer(async (req, res) => {
  let pathname = '';
  let served = '';
  res.on('finish', () => console.log(`${new Date().toISOString()} ${req.method} ${pathname} ${res.statusCode} ${served}`));
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (pathname.includes('\0') || pathname.includes('\\')) {
      res.writeHead(400).end();
      return;
    }
    // Pages applies header patterns to the requested URL, including SPA routes.
    for (const rule of headerRules) {
      if (patternMatches(rule.pattern, pathname)) {
        for (const [name, value] of Object.entries(rule.headers)) res.setHeader(name, value);
      }
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { Allow: 'GET, HEAD' }).end();
      return;
    }
    // Pages configuration files are not public assets.
    if (pathname === '/_headers' || pathname === '/_redirects') {
      res.writeHead(404).end();
      return;
    }
    let file = await findFile(pathname.endsWith('/') ? `${pathname}index.html` : pathname);
    served = pathname;
    if (!file) {
      const rewrite = redirectRules.find(rule => patternMatches(rule.pattern, pathname));
      if (rewrite) {
        served = rewrite.target;
        file = await findFile(served);
      }
    }
    if (!file) {
      res.writeHead(404).end();
      return;
    }
    res.setHeader('Content-Type', mime[extname(file.path)] ?? 'application/octet-stream');
    res.setHeader('Content-Length', file.size);
    if (req.method === 'HEAD') res.writeHead(200).end();
    else res.writeHead(200).end(await readFile(file.path));
  } catch (error) {
    console.error(error.message);
    res.writeHead(error instanceof URIError ? 400 : 500).end();
  }
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => {
  console.log(`Serving ${root} at http://localhost:${port} (PID ${process.pid})`);
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
