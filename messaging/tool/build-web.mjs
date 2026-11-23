#!/usr/bin/env node
/**
 * Builds Ghost Messaging for a browser (Matt: "the full web client"; docs/OPEN_NETWORK.md, part 6): a folder of plain
 * files a relay serves under /app/ (relay/lib/web_app.dart). It builds and says how big the result is. It does not
 * put it anywhere.
 *
 *   node tool/build-web.mjs                   the release build, into build/web
 *   node tool/build-web.mjs --profile         names kept in the JavaScript, for reading what went wrong
 *   node tool/build-web.mjs --out <folder>    somewhere else
 *   node tool/build-web.mjs --base /app/      where it will be served from (/app/, as the relay serves it)
 *
 *   dart run relay/bin/relay.dart --web build/web      then: http://127.0.0.1:8787/app/
 *   node tool/web/e2e.mjs                               two people using it, in Chromium and WebKit
 *
 * WHAT IT DOES
 *   1. Checks web/argon2id.js is what tool/web/build-argon2.mjs builds, where the extension's packages are installed
 *      (it says so where they aren't, and goes on with the file as committed).
 *   2. `flutter build web -t lib/web/main.dart`, with:
 *        --no-web-resources-cdn   Flutter's engine (CanvasKit) from the build's own folder, not from www.gstatic.com
 *        --csp                    no code made from text at run time, so the page's own policy can forbid it
 *        --pwa-strategy=none      no service worker (web/flutter_bootstrap.js sets none up)
 *        --base-href              where the page is served from
 *   3. Takes the four emoji sets off the list of fonts a browser loads before its first frame (eleven megabytes):
 *      the app fetches the one in use when it starts, and another when it is chosen (lib/web/emoji.dart). The files
 *      stay in the build.
 *   4. Names main.dart.js by what is in it (main.dart.<hash>.js) and has the loader ask for that name: the relay
 *      lets a browser keep such a file for a year, and asks again for everything else.
 *   5. Packs every file a browser would unpack (.js, .wasm, .json, fonts) beside itself as .br and .gz, which the
 *      relay sends in the file's place to a browser that reads them.
 *   6. Says what a first visit fetches, and how big.
 *
 * NOTHING IS FETCHED FROM ANYONE ELSE by the page this builds: no engine from Google, no fonts from Google, no
 * analytics, no scripts but its own. web/index.html's policy says so to the browser, and tool/web/e2e.mjs fails if
 * the page asks any address but its own.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brotliCompressSync, constants, gzipSync } from 'node:zlib';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const at = args.indexOf(`--${name}`);
  return at >= 0 && at + 1 < args.length ? args[at + 1] : fallback;
};
const fail = (words) => {
  console.error(`build-web: ${words}`);
  process.exit(1);
};
const out = resolve(option('out', join(ROOT, 'build', 'web')));
const profile = args.includes('--profile');
const base = option('base', '/app/');
if (!base.startsWith('/') || !base.endsWith('/')) fail(`--base starts and ends with a slash (${base}).`);

// 1. The one file of JavaScript the app carries beside itself.
if (existsSync(join(ROOT, 'extension', 'node_modules', '@noble', 'hashes'))) {
  const checked = spawnSync('node', [join(ROOT, 'tool', 'web', 'build-argon2.mjs'), '--check'], { cwd: ROOT, stdio: 'inherit' });
  if (checked.status !== 0) fail('web/argon2id.js is not what its script builds. Run node tool/web/build-argon2.mjs and commit the file.');
} else {
  console.log('web/argon2id.js not checked against its script: the extension\'s packages are not installed (npm ci in extension/). Built with the file as it is.');
}

// 2. The app.
const version = /^version:\s*(\S+?)\+(\d+)/m.exec(readFileSync(join(ROOT, 'pubspec.yaml'), 'utf8'));
const built = spawnSync(
  'flutter',
  ['build', 'web', '-t', 'lib/web/main.dart', profile ? '--profile' : '--release', '--no-web-resources-cdn', '--csp', '--pwa-strategy=none', '--no-wasm-dry-run', `--base-href=${base}`, '-o', out],
  { cwd: ROOT, stdio: 'inherit' },
);
if (built.status !== 0) fail('flutter build web failed.');
for (const needed of ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'argon2id.js', 'assets/FontManifest.json', 'canvaskit/canvaskit.wasm']) {
  if (!existsSync(join(out, needed))) fail(`the build has no ${needed}.`);
}

// What a build before this one left beside the files: packed copies and a main.dart.js by another name.
const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));
for (const file of walk(out)) {
  if (/\.(br|gz)$/.test(file) || /^main\.dart\.[0-9a-f]{8,}\.js$/.test(relative(out, file))) rmSync(file);
}

// 3. The emoji sets: in the build, off the list of what is loaded before the first frame.
const manifestPath = join(out, 'assets', 'FontManifest.json');
const families = JSON.parse(readFileSync(manifestPath, 'utf8'));
const emoji = families.filter((f) => f.family.startsWith('Ghost Emoji '));
if (emoji.length !== 4) fail(`expected the four emoji sets in the font list, found ${emoji.length}: lib/emoji_sets.dart and pubspec.yaml have changed, and lib/web/emoji.dart with this script must follow.`);
for (const f of emoji) {
  for (const font of f.fonts) {
    if (!existsSync(join(out, 'assets', font.asset))) fail(`the build has no ${font.asset}.`);
  }
}
if (!families.some((f) => f.family === 'Roboto')) fail('the font list has no Roboto of the build\'s own: Flutter would fetch it from Google.');
writeFileSync(manifestPath, JSON.stringify(families.filter((f) => !emoji.includes(f))));

// 4. The app's JavaScript, named by what is in it.
const mainPath = join(out, 'main.dart.js');
const hash = createHash('sha256').update(readFileSync(mainPath)).digest('hex').slice(0, 16);
const named = `main.dart.${hash}.js`;
renameSync(mainPath, join(out, named));
const bootstrapPath = join(out, 'flutter_bootstrap.js');
const bootstrap = readFileSync(bootstrapPath, 'utf8');
if (bootstrap.split('"mainJsPath":"main.dart.js"').length !== 2) fail('flutter_bootstrap.js does not name main.dart.js once, as it did: Flutter\'s loader has changed.');
if (bootstrap.includes('gstatic.com') && !bootstrap.includes('"useLocalCanvasKit":true')) fail('flutter_bootstrap.js would fetch the engine from Google.');
writeFileSync(bootstrapPath, bootstrap.replace('"mainJsPath":"main.dart.js"', `"mainJsPath":"${named}"`));
// Source maps of a profile build name the file they belong to; a release build has none.
if (existsSync(`${mainPath}.map`)) renameSync(`${mainPath}.map`, join(out, `${named}.map`));

// 5. Packed beforehand, for the relay to send as they are.
const packable = /\.(js|mjs|wasm|json|html|css|ttf|otf|svg|map|txt|bin|frag)$|\/NOTICES$/;
const sizes = new Map();
for (const file of walk(out)) {
  const name = relative(out, file).split('\\').join('/');
  const bytes = readFileSync(file);
  let br = null;
  if (packable.test(`/${name}`) && bytes.length >= 1024) {
    br = brotliCompressSync(bytes, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_SIZE_HINT]: bytes.length } });
    const gz = gzipSync(bytes, { level: 9 });
    // Only where packing gains something: a font of pictures doesn't.
    if (br.length < bytes.length * 0.95) {
      writeFileSync(`${file}.br`, br);
      writeFileSync(`${file}.gz`, gz);
    } else {
      br = null;
    }
  }
  sizes.set(name, { raw: bytes.length, sent: br ? br.length : bytes.length });
}

// 6. How big.
const mb = (n) => `${(n / 1048576).toFixed(2)} MB`;
const kb = (n) => (n >= 1048576 ? mb(n) : `${(n / 1024).toFixed(0)} KB`);
const show = (name) => {
  const s = sizes.get(name);
  return s ? `${kb(s.raw).padStart(9)}  ${kb(s.sent).padStart(9)} sent  ${name}` : `        ?  ${name}`;
};
const kept = JSON.parse(readFileSync(manifestPath, 'utf8')).flatMap((f) => f.fonts.map((x) => `assets/${x.asset}`));
// What a browser asks for to draw the first screen: the page, the loader, the app, the engine (Chromium's build of
// it; other browsers take canvaskit/canvaskit.wasm, a little bigger), the fonts on the list, and the emoji set in use.
const first = ['index.html', 'flutter_bootstrap.js', named, 'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json', ...kept, 'assets/assets/css/ink.css', 'assets/assets/css/app.css', 'assets/assets/art/ghost-mark.png'].filter((n) => sizes.has(n));
const emojiInUse = 'assets/assets/emoji/NotoColor.ttf';
const sum = (names, key) => names.reduce((n, name) => n + (sizes.get(name)?.[key] ?? 0), 0);
const all = [...sizes.keys()];
console.log(`\nGhost Messaging for a browser${version ? ` ${version[1]} (${version[2]})` : ''}, ${profile ? 'profile' : 'release'}, to be served from ${base}: ${out}`);
console.log(`  the app's JavaScript   ${show(named)}`);
console.log(`  Argon2id, as a worker  ${show('argon2id.js')}`);
console.log('  a first visit fetches, before the first screen:');
for (const name of first) console.log(`    ${show(name)}`);
console.log(`    ${kb(sum(first, 'raw')).padStart(9)}  ${kb(sum(first, 'sent')).padStart(9)} sent  in all, ${first.length} files`);
console.log(`  then the emoji set in use (Noto where none was chosen):\n    ${show(emojiInUse)}`);
console.log(`  the whole folder: ${mb(sum(all, 'raw'))} in ${all.length} files (every engine variant, every emoji set, stickers, sounds), fetched only as wanted.`);
console.log(`  not on the font list any more: ${emoji.map((f) => f.family).join(', ')}.`);
console.log(`\nServe it: dart run relay/bin/relay.dart --web ${relative(process.cwd(), out) || '.'}    Try it: node tool/web/e2e.mjs${out === join(ROOT, 'build', 'web') ? '' : ` --web ${out}`}`);
