import { chmodSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { ROOT, TAURI } from './lib/paths.mjs';

/**
 * The MCP server as one file (tauri/docs/MCP.md): mcp/main.ts and everything it reaches - the app's own crypto and
 * list-placing rules under tauri/src/, and the MCP SDK - bundled for Node, so a person needs Node and this file and
 * nothing else. Written to mcp/dist/glyph-mcp.mjs; `tauri/scripts/deploy-ota.mjs --mcp` publishes it beside the app.
 */

/*
 * mcp/ is at the repository's root and has no packages of its own: esbuild, the MCP SDK and express are the Tauri
 * app's (tauri/package.json), installed by `npm ci` in tauri/. So esbuild is loaded from there, and it is told to look
 * there (`nodePaths`) for what the files under mcp/ import by name; what they import from the app, under tauri/src,
 * finds tauri/node_modules by itself.
 */
const MODULES = join(TAURI, 'node_modules');
if (!existsSync(join(MODULES, 'esbuild'))) {
  console.error(`x No esbuild in ${MODULES}: run \`npm ci\` in tauri/ first.`);
  process.exit(1);
}
const { build } = createRequire(join(TAURI, 'package.json'))('esbuild');

mkdirSync(join(ROOT, 'mcp/dist'), { recursive: true });

/** One file from one entry. `require` is defined for the CommonJS packages inside (express, the SDK's handlers). */
async function bundle(entry, name, target) {
  const out = join(ROOT, 'mcp/dist', name);
  await build({
    entryPoints: [join(ROOT, 'mcp', entry)],
    outfile: out,
    bundle: true,
    platform: 'node',
    nodePaths: [MODULES],
    format: 'esm',
    target,
    banner: { js: "#!/usr/bin/env node\nimport { createRequire as __createRequire } from 'node:module'; const require = __createRequire(import.meta.url);" },
    // The sign-in page's typeface rides inside the hosted bundle as a data URL (mcp/loginPage.ts).
    loader: { '.woff2': 'dataurl' },
    // `ws` (the relay's socket, mcp/live.ts) asks for these native speed-ups inside a try and does without them:
    // left out of the bundle, the ask fails at run time and is caught, as on a machine that never installed them.
    external: ['bufferutil', 'utf-8-validate'],
    legalComments: 'none',
    logLevel: 'warning',
  });
  chmodSync(out, 0o755);
  console.log(`ok mcp/dist/${name} (${Math.round(statSync(out).size / 1024)} KB)`);
}

// The local server, run by a person's own Node; and the hosted one, run by the box's Node 18 (tauri/docs/MCP.md).
await bundle('main.ts', 'glyph-mcp.mjs', 'node20');
await bundle('hosted-main.ts', 'glyph-mcp-hosted.mjs', 'node18');
