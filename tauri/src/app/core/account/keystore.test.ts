import { beforeEach, describe, expect, it } from 'vitest';
import { newAccountKey, newDeviceKey, settle } from '../sync/crypto.ts';
import { deviceKeys, memoryKeys, readSession, writeSession } from './keystore.ts';

/*
 * What makes a device a signed-in one (keystore.ts): the session in localStorage, read back only when it is whole,
 * and the two keys. jsdom has no IndexedDB, which is the case a private window is in too, so the keys here are the
 * memory store's - the one a browser without IndexedDB gets.
 */

beforeEach(() => {
  localStorage.clear();
});

describe('the session', () => {
  it('is read back as it was written, and gone once signed out', () => {
    writeSession({ token: 't1', handle: 'matt', accountId: 7 });
    expect(readSession()).toEqual({ token: 't1', handle: 'matt', accountId: 7 });
    writeSession(null);
    expect(readSession()).toBeNull();
    expect(localStorage.getItem('glyph-account-session')).toBeNull();
  });

  it('is no session at all when any part is missing or the wrong kind, and keeps nothing extra', () => {
    const stored = (value: unknown) => {
      localStorage.setItem('glyph-account-session', JSON.stringify(value));
      return readSession();
    };
    expect(stored({ handle: 'matt', accountId: 7 })).toBeNull();
    expect(stored({ token: 't1', accountId: 7 })).toBeNull();
    expect(stored({ token: 't1', handle: 'matt', accountId: '7' })).toBeNull();
    expect(stored(null)).toBeNull();
    expect(stored({ token: 't1', handle: 'matt', accountId: 7, password: 'never' })).toEqual({ token: 't1', handle: 'matt', accountId: 7 });
    localStorage.setItem('glyph-account-session', '{half');
    expect(readSession()).toBeNull();
  });
});

describe('the keys', () => {
  it('are held and forgotten by a memory store, each store its own', async () => {
    const one = memoryKeys();
    const two = memoryKeys();
    const key = await settle(await newAccountKey());
    const pair = await newDeviceKey();
    await one.setAccountKey(key);
    await one.setDeviceKey(pair);
    expect(await one.accountKey()).toBe(key);
    expect(await one.deviceKey()).toBe(pair);
    expect(await two.accountKey()).toBeNull();
    await one.setAccountKey(null);
    expect(await one.accountKey()).toBeNull();
  });

  it('live in one memory store for the whole page where there is no IndexedDB', async () => {
    const key = await settle(await newAccountKey());
    await deviceKeys().setAccountKey(key);
    expect(await deviceKeys().accountKey()).toBe(key);
    await deviceKeys().setAccountKey(null);
  });
});
