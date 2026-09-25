// @vitest-environment node
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { rustU32Const } from './otaRs.mjs';

/*
 * The two generations the build and the deploy stamp, read from the Rust that
 * defines them - and the refusal when the Rust stops declaring one as a plain
 * literal, which is the build's own error today (vite.config.ts).
 */

describe('reading a u32 constant out of ota.rs', () => {
  const dir = mkdtempSync(join(tmpdir(), 'glyph-ota-rs-'));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  const rust = (text) => {
    const path = join(dir, `${Math.random().toString(36).slice(2)}.rs`);
    writeFileSync(path, text);
    return path;
  };

  it('reads both generations from the real file, and the page never needs more than its own binary provides', () => {
    const native = rustU32Const('NATIVE_GENERATION');
    const requires = rustU32Const('BUNDLE_REQUIRES');
    expect(Number.isInteger(native) && native > 0).toBe(true);
    expect(Number.isInteger(requires) && requires > 0).toBe(true);
    // The same promise ota.rs makes at compile time: `assert!(BUNDLE_REQUIRES <= NATIVE_GENERATION)`.
    expect(requires).toBeLessThanOrEqual(native);
  });

  it('matches the name whole: BUNDLE is not BUNDLE_REQUIRES', () => {
    const path = rust('/// What the page needs.\npub const BUNDLE_REQUIRES: u32 = 7;\n');
    expect(rustU32Const('BUNDLE_REQUIRES', path)).toBe(7);
    expect(() => rustU32Const('BUNDLE', path)).toThrow('no longer declares BUNDLE as a literal');
  });

  it('refuses when the constant is gone, or no longer a u32 literal, naming it', () => {
    expect(() => rustU32Const('NO_SUCH_GENERATION')).toThrow('src-tauri/src/ota.rs no longer declares NO_SUCH_GENERATION as a literal');
    const path = rust('pub const BUNDLE_REQUIRES: u64 = 7;\npub const NATIVE_GENERATION: u32 = NEXT;\n');
    expect(() => rustU32Const('BUNDLE_REQUIRES', path)).toThrow(`${path} no longer declares BUNDLE_REQUIRES as a literal`);
    expect(() => rustU32Const('NATIVE_GENERATION', path)).toThrow('no longer declares NATIVE_GENERATION');
  });

  it('refuses a name that is not a Rust constant, rather than building a pattern out of it', () => {
    expect(() => rustU32Const('BUNDLE_REQUIRES|NATIVE_GENERATION')).toThrow('is not the name of a Rust constant');
  });
});
