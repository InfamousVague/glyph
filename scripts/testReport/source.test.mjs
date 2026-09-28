import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { REPORT_PATH, sourceHash } from './source.mjs';

/** The source fingerprint: what changes it, and what does not. */

let root = '';
const put = (path, text) => {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), text);
};

afterEach(() => {
  if (root) rmSync(root, { recursive: true, force: true });
  root = '';
});

describe('the source fingerprint', () => {
  it('changes with the code the tests test, the MCP server’s among it, and not with its bundle or the report', () => {
    root = mkdtempSync(join(tmpdir(), 'glyph-source-'));
    put('src/app/a.ts', 'export const a = 1;\n');
    put('mcp/server.ts', 'export const b = 1;\n');
    put('mcp/dist/main.js', 'bundled();\n');
    put(REPORT_PATH, '{}\n');
    const first = sourceHash(root);
    put('mcp/dist/main.js', 'bundled again();\n');
    put(REPORT_PATH, '{"ok":true}\n');
    expect(sourceHash(root)).toBe(first);
    put('mcp/server.ts', 'export const b = 2;\n');
    const second = sourceHash(root);
    expect(second).not.toBe(first);
    put('src/app/a.ts', 'export const a = 2;\n');
    expect(sourceHash(root)).not.toBe(second);
  });
});
