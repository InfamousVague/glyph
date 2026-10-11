import { readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * What a module reaches when it runs: every file its value imports lead to, and every package among them. `import
 * type` is left out, since it is gone once compiled. For the modules the MCP server bundles for Node (mcp/server.ts):
 * a test says that none of them reaches React, the Tauri bridge, CodeMirror or the store, which a Node bundle cannot
 * take, rather than finding out at the server's next build.
 */

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** An import or a re-export, with `type` when it carries only types, and where it is from. */
const IMPORT = /(?:^|\n)\s*(?:import|export)\s+(type\s+)?(?:[^'";]*?\s+from\s+)?['"]([^'"]+)['"]/g;

export function valueImports(entry: string): { files: string[]; packages: string[] } {
  const files = new Set<string>();
  const packages = new Set<string>();
  const walk = (file: string) => {
    if (files.has(file)) return;
    files.add(file);
    for (const [, typeOnly, from] of readFileSync(file, 'utf8').matchAll(IMPORT)) {
      if (typeOnly || !from) continue;
      if (from.startsWith('.')) walk(resolve(dirname(file), from));
      else packages.add(from);
    }
  };
  walk(resolve(SRC, entry));
  return { files: [...files].map((file) => relative(SRC, file)).sort(), packages: [...packages].sort() };
}
