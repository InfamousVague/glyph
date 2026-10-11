import { afterEach, describe, expect, it, vi } from 'vitest';
import { isShortId, randomId, shortId, SHORT_ID_LENGTH } from './ids.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

describe('a fresh id', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('is a UUID where the context is secure, whatever the prefix', () => {
    expect(randomId()).toMatch(UUID);
    expect(randomId('img')).toMatch(UUID);
    expect(randomId()).not.toBe(randomId());
  });

  it('is the prefix, the time and eight random characters on an http:// dev server, which has no randomUUID', () => {
    vi.stubGlobal('crypto', {});
    expect(randomId()).toMatch(/^n-[0-9a-z]+-[0-9a-z]{1,8}$/);
    expect(randomId('img')).toMatch(/^img-[0-9a-z]+-[0-9a-z]{1,8}$/);
    expect(randomId()).not.toBe(randomId());
  });

  it('still answers where there is no crypto at all', () => {
    vi.stubGlobal('crypto', undefined);
    expect(randomId()).toMatch(/^n-[0-9a-z]+-[0-9a-z]{1,8}$/);
  });
});

describe('a short id', () => {
  it('is twenty-two base64url characters, and never the same twice', () => {
    const made = shortId();
    expect(made).toHaveLength(SHORT_ID_LENGTH);
    expect(made).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(isShortId(made)).toBe(true);
    expect(shortId()).not.toBe(made);
    // Shorter, longer, or holding a character base64url does not: not one.
    expect(isShortId(made.slice(1))).toBe(false);
    expect(isShortId(`${made}A`)).toBe(false);
    expect(isShortId(`${made.slice(1)}+`)).toBe(false);
  });
});
