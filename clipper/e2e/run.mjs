#!/usr/bin/env node
// The clipper end to end, on this computer and nowhere else: a real glyph-api (server/, built by
// tool/local-server.sh build) on 127.0.0.1 with a data folder made for the run, the fixture pages served at
// localhost and a second "site" at [::1], the extension built for that service, and Playwright's own Chromium with
// the extension loaded unpacked. The pages are not on the service's host, so the extension reads them only by the
// `activeTab` grant its toolbar button gives, as it would anywhere: the proof presses that button through Chrome's
// own DevTools command for it (`Extensions.triggerAction`). Then e2e/clip.e2e.test.ts signs up a made-up account with the app's sign-up
// code, clips every mode through the popup, and reads the notes back through the connector's GlyphAccount.
//
//   node e2e/run.mjs                    headless; pictures of the popup and of what was saved go to e2e/out/shots
//   GLYPH_API_BIN=<glyph-api> node e2e/run.mjs     a binary built elsewhere (default: the repo's build/local-server)
//
// Nothing here reaches ghostmarkdown.com: the build refuses a service that is not https or on this computer, the
// test's own requests are refused for any host but 127.0.0.1, and everything it started is stopped by its PID.
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const clipper = join(here, '..');
const repo = join(clipper, '..');
const out = join(here, 'out');
const PNGJS = process.env.PNGJS ?? '/Users/matt/.npm/_npx/249ca9fcd30c476a/node_modules/pngjs/lib/png.js';

const started = [];
const stopAll = () => {
  for (const child of started) if (child.exitCode === null) child.kill('SIGTERM');
};
process.on('exit', stopAll);
process.on('SIGINT', () => process.exit(130));

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

async function freePort() {
  const server = createServer();
  const port = await listen(server);
  await new Promise((done) => server.close(done));
  return port;
}

// --- the service ---------------------------------------------------------------------------
const binary = process.env.GLYPH_API_BIN ?? join(repo, 'build/local-server/target/debug/glyph-api');
if (!existsSync(binary)) {
  console.error(`e2e: no glyph-api at ${binary}. Build it with tool/local-server.sh build, or name one with GLYPH_API_BIN.`);
  process.exit(2);
}
const apiPort = await freePort();
const data = mkdtempSync(join(tmpdir(), 'clipper-e2e-data.'));
const api = `http://127.0.0.1:${apiPort}/api`;
const service = spawn(binary, [], {
  env: { ...process.env, GLYPH_API_TOKEN: randomBytes(32).toString('hex'), GLYPH_API_DATA: data, GLYPH_API_BIND: `127.0.0.1:${apiPort}`, OLLAMA_URL: 'http://127.0.0.1:9' },
  stdio: ['ignore', 'pipe', 'pipe'],
});
started.push(service);
let serviceLog = '';
service.stdout.on('data', (b) => (serviceLog += b));
service.stderr.on('data', (b) => (serviceLog += b));
for (let tries = 0; ; tries += 1) {
  const up = await fetch(`${api}/health`).then((r) => r.ok).catch(() => false);
  if (up) break;
  if (tries > 100 || service.exitCode !== null) {
    console.error(`e2e: the service did not come up:\n${serviceLog}`);
    process.exit(1);
  }
  await new Promise((r) => setTimeout(r, 100));
}

// --- the sites -------------------------------------------------------------------------------
const { PNG } = await import(PNGJS);
function picture(width, height) {
  const png = new PNG({ width, height });
  for (let y = 0; y < height; y += 1)
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const ink = ((x >> 6) + (y >> 6)) % 2 ? 40 : 220;
      png.data[i] = ink;
      png.data[i + 1] = ink;
      png.data[i + 2] = ink;
      png.data[i + 3] = 255;
    }
  return PNG.sync.write(png);
}
const media = join(repo, 'test/editor/media/fixtures');
const files = {
  '/pictures/beds.png': readFileSync(join(media, 'porch.png')),
  '/pictures/shed.png': readFileSync(join(media, 'tall.png')),
  '/pictures/garden-wide.png': readFileSync(join(media, 'poster.png')),
  '/pictures/big.png': picture(2400, 1200),
  // Past the clipper's limit (15 MB): never kept, a link.
  '/pictures/huge.png': Buffer.concat([readFileSync(join(media, 'upright.png')), Buffer.alloc(16 * 1024 * 1024)]),
};
const pages = { '/article.html': join(clipper, 'test/fixtures/article.html'), '/table-code.html': join(clipper, 'test/fixtures/table-code.html'), '/selection.html': join(clipper, 'test/fixtures/selection.html'), '/pictures.html': join(here, 'site/pictures.html') };
const cdnPort = await freePort();
const site = createServer((req, res) => {
  const path = new URL(req.url, 'http://x').pathname;
  if (pages[path]) {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(readFileSync(pages[path], 'utf8').replaceAll('{{CDN}}', String(cdnPort)));
    return;
  }
  const bytes = files[path];
  if (!bytes) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'content-type': extname(path) === '.png' ? 'image/png' : 'application/octet-stream', 'content-length': bytes.length });
  res.end(bytes);
});
const sitePort = await listen(site);
// The other site: one picture any page may read (CORS), one only its own pages may.
const cdn = createServer((req, res) => {
  // [::1] is another site to the page at localhost, and to the clipper, whose one host is 127.0.0.1.
  const path = new URL(req.url, 'http://x').pathname;
  const bytes = readFileSync(join(media, path === '/open.png' ? 'porch.png' : 'poster.png'));
  res.writeHead(200, { 'content-type': 'image/png', ...(path === '/open.png' ? { 'access-control-allow-origin': '*' } : {}) });
  res.end(bytes);
});
await new Promise((resolve) => cdn.listen(cdnPort, '::1', resolve));

// --- the extension, for this service --------------------------------------------------------------
rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, 'shots'), { recursive: true });
const ext = join(out, 'ext');
await new Promise((resolve, reject) => {
  const build = spawn(process.execPath, [join(clipper, 'build.mjs'), 'chrome', `--api=${api}`, `--out=${ext}`], { cwd: clipper, stdio: 'inherit' });
  build.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`build exited ${code}`))));
});

// --- the proof ---------------------------------------------------------------------------------------
const env = {
  ...process.env,
  CLIPPER_E2E: '1',
  VITE_GLYPH_API: api,
  E2E_SITE: `http://localhost:${sitePort}`,
  E2E_CDN: `http://[::1]:${cdnPort}`,
  E2E_DEBUG_PORT: String(await freePort()),
  E2E_EXT: join(ext, 'chrome'),
  E2E_OUT: out,
};
const vitest = spawn(join(clipper, 'node_modules/.bin/vitest'), ['run', 'e2e/clip.e2e.test.ts', ...process.argv.slice(2)], { cwd: clipper, env, stdio: 'inherit' });
started.push(vitest);
const code = await new Promise((resolve) => vitest.on('exit', resolve));
writeFileSync(join(out, 'service.log'), serviceLog);
stopAll();
site.close();
cdn.close();
rmSync(data, { recursive: true, force: true });
process.exit(code ?? 1);
