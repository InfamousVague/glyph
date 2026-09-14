import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

const root = import.meta.dirname;
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')) as { version: string };

/*
 * One build id per `vite build`, UTC to the second: `20260912221530`. It is how
 * an installed app tells a newer frontend from an older one, so it has to be
 * monotonic and it has to be the SAME value in the page (`__GLYPH_BUILD__`) and
 * in `ota.json`. Digits only, because the phone uses it as a directory name.
 */
const build = new Date().toISOString().replace(/\D/g, '').slice(0, 14);

/*
 * The native generation this page needs, read out of the Rust that defines it
 * so the two cannot drift. BUNDLE_REQUIRES, never NATIVE_GENERATION - see the
 * header of src-tauri/src/ota.rs for the AttackFM release that learned why.
 */
function bundleRequires(): number {
  const source = readFileSync(join(root, 'src-tauri/src/ota.rs'), 'utf8');
  const match = /pub const BUNDLE_REQUIRES: u32 = (\d+);/.exec(source);
  if (!match) throw new Error('src-tauri/src/ota.rs no longer declares BUNDLE_REQUIRES as a literal');
  return Number(match[1]);
}

function* walk(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}

/**
 * Writes `dist/ota.json`: what an installed Glyph needs to run this build as
 * an over-the-air update. The entry and stylesheets are read back out of the
 * built index.html rather than from Rollup's bundle object, because index.html
 * is what the website serves and what the APK embeds - if the two ever
 * disagreed, the HTML is the one that is right.
 */
function otaManifest(): Plugin {
  let outDir = 'dist';
  return {
    name: 'glyph-ota-manifest',
    apply: 'build',
    configResolved(config) {
      outDir = join(config.root, config.build.outDir);
    },
    closeBundle() {
      const html = readFileSync(join(outDir, 'index.html'), 'utf8');
      const entry = /<script type="module"[^>]*src="\.\/([^"]+)"/.exec(html)?.[1];
      const styles = [...html.matchAll(/<link rel="stylesheet"[^>]*href="\.\/([^"]+)"/g)].map((m) => m[1]);
      if (!entry) throw new Error('ota.json: the built index.html has no relative module entry');
      const files = [...walk(join(outDir, 'assets'))].sort().map((path) => {
        const bytes = readFileSync(path);
        return {
          path: relative(outDir, path).split(sep).join('/'),
          sha256: createHash('sha256').update(bytes).digest('hex'),
          bytes: bytes.length,
        };
      });
      const manifest = { schema: 1, build, version: pkg.version, native: bundleRequires(), entry, styles, files };
      writeFileSync(join(outDir, 'ota.json'), `${JSON.stringify(manifest, null, 2)}\n`);
    },
  };
}

// A relative base so the built app works when Tauri serves it from a custom
// protocol rather than the server root - and, since OTA, so the same build runs
// from `ota.localhost` and from attack.fm/glyph/ unchanged. @glacier/react
// resolves from the vendored copy in node_modules (installed via the file:
// dependency).
export default defineConfig({
  base: './',
  plugins: [react(), otaManifest()],
  define: {
    __GLYPH_BUILD__: JSON.stringify(build),
    __GLYPH_VERSION__: JSON.stringify(pkg.version),
  },
  server: {
    // 5250, not the 5240 the other Glacier apps use: two of them are often
    // running side by side, and Tauri wants a fixed port it can rely on.
    port: Number(process.env.PORT) || 5250,
    strictPort: true,
  },
  clearScreen: false,
});
