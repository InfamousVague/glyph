import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { fromBase64Url } from '../sync/crypto.ts';
import { importEncryptionKey, publicKeyOf, unwrapWith, wrapFor } from './wrap.ts';

/*
 * An incoming hook's post, sealed by glyph-api (server/src/hooks.rs, docs/INTEGRATIONS.md) to the account's encryption
 * key with the service's own ECIES, opened here by `unwrapWith`; and the reverse, a payload `wrapFor` wrapped, which
 * the service's test (server/src/hooks_tests.rs `hook_seal_fixture`) opens. The fixture beside this file is both
 * halves, to one fixed key. With GLYPH_WRITE_HOOK_FIXTURE=1 this writes wrap.ts's half; the service's half is written
 * by its own test with the same variable.
 */

const FIXTURE = join(__dirname, 'hookSeal.fixture.json');
const decoder = new TextDecoder();
const encoder = new TextEncoder();

interface Half {
  hook: string;
  context: string;
  sealed: string;
  payload: Record<string, unknown>;
}

interface Fixture {
  jwk: JsonWebKey;
  public: string;
  rust: Half;
  typescript?: Half;
}

const read = (): Fixture => JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

describe("an incoming hook's seal, across languages", () => {
  it('opens what the service sealed with the account key alone, in its hook’s context alone', async () => {
    const fixture = read();
    const pair = await importEncryptionKey(fixture.jwk);
    expect(await publicKeyOf(pair)).toBe(fixture.public);
    const { rust } = fixture;
    expect(rust.context).toBe(`hook:${rust.hook}`);
    const opened = JSON.parse(decoder.decode(await unwrapWith(pair, rust.sealed, rust.context))) as Record<string, unknown>;
    expect(opened).toEqual(rust.payload);
    expect(opened).toMatchObject({ hook: rust.hook, note: 'Groceries', as: 'item', title: 'From Rust' });
    expect(opened.text).toBe('Pomegranate jam ✓, “quoted”, and a line\nbreak');
    // wrapFor's layout: the ephemeral point, the IV, the payload and its tag.
    expect(fromBase64Url(rust.sealed).length).toBe(65 + 12 + encoder.encode(JSON.stringify(rust.payload)).length + 16);
    await expect(unwrapWith(pair, rust.sealed, 'hook:another-hook')).rejects.toThrow();
    await expect(unwrapWith(pair, rust.sealed, `org-key:${rust.hook}:1`)).rejects.toThrow();
  });

  it('is what wrapFor makes, which the service opens', async () => {
    const fixture = read();
    if (process.env.GLYPH_WRITE_HOOK_FIXTURE === '1') {
      const hook = 'from-typescript';
      const payload = { hook, note: 'Trip', text: 'Passports, “both”, ✓', as: 'task', at: 1792275541000 };
      const sealed = await wrapFor(fixture.public, encoder.encode(JSON.stringify(payload)), `hook:${hook}`);
      fixture.typescript = { hook, context: `hook:${hook}`, sealed, payload };
      writeFileSync(FIXTURE, `${JSON.stringify(fixture, null, 2)}\n`);
    }
    const half = read().typescript;
    expect(half, 'the fixture has no wrapFor half: GLYPH_WRITE_HOOK_FIXTURE=1 npx vitest run src/app/core/orgs/hookSeal.test.ts').toBeDefined();
    if (!half) return;
    const pair = await importEncryptionKey(fixture.jwk);
    expect(JSON.parse(decoder.decode(await unwrapWith(pair, half.sealed, half.context)))).toEqual(half.payload);
  });
});
