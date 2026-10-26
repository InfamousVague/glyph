// build/web served as the box serves it (docs/WEB.md): under a base path, `/glyph/` by default, with the types and
// the cache rule scripts/deploy-flutter-web.mjs asks of the box, so what is checked in the browser pane here is
// what a returning visitor gets there. Nothing but the folder is served; nothing is proxied.
//
//   node tool/serve_web.mjs [port] [base] [dir]       8790, /glyph/, build/web
//
// Nothing is cached without asking: Flutter's files keep their names from build to build (main.dart.wasm,
// main.dart.mjs, the core), so a browser that kept one for an hour would run last hour's app over this hour's
// index. Every answer is `no-cache` with its time, and a browser that has the file already is told 304.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.argv[2] || 8790);
const base = process.argv[3] || '/glyph/';
const dir = resolve(root, process.argv[4] || 'build/web');

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.frag': 'application/octet-stream',
  '.bin': 'application/octet-stream',
};

createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname === '/' || url.pathname + '/' === base) {
    response.writeHead(302, { location: base });
    return response.end();
  }
  if (!url.pathname.startsWith(base)) {
    response.writeHead(404);
    return response.end('not here');
  }
  let rel = decodeURIComponent(url.pathname.slice(base.length)) || 'index.html';
  let file = normalize(join(dir, rel));
  if (!file.startsWith(dir)) {
    response.writeHead(403);
    return response.end();
  }
  try {
    if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
  } catch {
    // An address of the app's own (a note's link): the page, as the box's file server answers it.
    file = join(dir, 'index.html');
    rel = 'index.html';
  }
  try {
    const modified = (await stat(file)).mtime;
    modified.setMilliseconds(0);
    const since = Date.parse(request.headers['if-modified-since'] || '');
    const headers = { 'cache-control': 'no-cache', 'last-modified': modified.toUTCString(), 'x-content-type-options': 'nosniff' };
    if (!Number.isNaN(since) && since >= modified.getTime()) {
      response.writeHead(304, headers);
      return response.end();
    }
    const body = await readFile(file);
    response.writeHead(200, { ...headers, 'content-type': types[extname(file)] || 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end('not found');
  }
}).listen(port, '127.0.0.1', () => console.log(`build/web at http://localhost:${port}${base}`));
