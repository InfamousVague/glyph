import { describe, expect, it } from 'vitest';
import { API_BASE, ApiError } from '../../tauri/src/app/core/account/api.ts';
import { fakeService, FAST } from '../../tauri/src/test/fakeService.ts';
import { ClipperAccount, DEVICE_LABEL } from '../src/core/account.ts';
import { keeper, memoryRooms } from '../src/core/keep.ts';

/**
 * Where a signed-in clipper is kept: in the browser's memory unless the person ticks "Stay signed in", and then
 * sealed on the disk with keys no script can read (core/keep.ts). A browser restart is a new memory area over the
 * same disk and the same keys.
 */

async function signedIn(stay: boolean) {
  const service = await fakeService({ handle: 'matt', password: 'correct horse' });
  const rooms = memoryRooms();
  const deps = { keeper: keeper({ ...rooms, api: API_BASE }), rounds: FAST, fetcher: service.fetcher };
  const account = await ClipperAccount.signIn('matt', 'correct horse', { stay, ...deps });
  return { service, rooms, deps, account };
}

/** The same browser after a restart: its memory empty, its disk and keys as they were. */
function restarted(rooms: ReturnType<typeof memoryRooms>) {
  const fresh = memoryRooms();
  return { memory: fresh.memory, disk: rooms.disk, keys: rooms.keys };
}

describe('signed in for this browser session', () => {
  it('keeps the session in memory only, writes nothing to the disk, and registers no device', async () => {
    const { service, rooms, account } = await signedIn(false);
    expect(account.handle).toBe('matt');
    expect(rooms.disk.data.size).toBe(0);
    expect(rooms.keys.data.size).toBe(0);
    const held = rooms.memory.data.get('ghost-session') as Record<string, unknown>;
    expect(held).toMatchObject({ v: 1, api: API_BASE, handle: 'matt', stay: false });
    expect(typeof held.accountKey).toBe('string');
    expect(JSON.stringify(held)).not.toContain('correct horse');
    expect(service.calls.filter((c) => c === 'POST device')).toHaveLength(0);
  });

  it('is gone after the browser closes', async () => {
    const { rooms, deps } = await signedIn(false);
    expect(await ClipperAccount.kept({ ...deps, keeper: keeper({ ...restarted(rooms), api: API_BASE }) })).toBeNull();
  });

  it('asks for the password again once the token lapses, and forgets the session', async () => {
    const { service, rooms, account } = await signedIn(false);
    service.expireAllTokens();
    await expect(account.readPrefs()).rejects.toMatchObject({ status: 401 });
    expect(rooms.memory.data.size).toBe(0);
  });
});

describe('staying signed in', () => {
  it('seals the session on the disk, keeps the keys as keys, and registers the clipper as a device', async () => {
    const { service, rooms } = await signedIn(true);
    const sealed = rooms.disk.data.get('ghost-session-sealed');
    expect(typeof sealed).toBe('string');
    expect(String(sealed)).not.toMatch(/matt|token/);
    const key = rooms.keys.data.get('account') as CryptoKey;
    expect(key.extractable).toBe(false);
    expect((rooms.keys.data.get('device') as CryptoKeyPair).privateKey.extractable).toBe(false);
    expect(service.calls).toContain('POST device');
    expect(DEVICE_LABEL).toBe('Web clipper');
  });

  it('is still signed in after a restart, and renews a lapsed token with its own key, without the password', async () => {
    const { service, rooms, deps } = await signedIn(true);
    const again = await ClipperAccount.kept({ ...deps, keeper: keeper({ ...restarted(rooms), api: API_BASE }) });
    expect(again?.handle).toBe('matt');
    service.expireAllTokens();
    await expect(again!.readPrefs()).resolves.toMatchObject({ rev: 0 });
    expect(service.calls).toContain('POST login/device');
  });

  it('is a session of one service only: a build for another one does not use it', async () => {
    const { rooms, deps } = await signedIn(true);
    expect(await ClipperAccount.kept({ ...deps, keeper: keeper({ ...restarted(rooms), api: 'https://elsewhere.example/api' }) })).toBeNull();
  });
});

describe('signing in and out', () => {
  it('says the service’s own words for a wrong password, and keeps nothing', async () => {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    const rooms = memoryRooms();
    const attempt = ClipperAccount.signIn('matt', 'wrong horse', { stay: true, keeper: keeper({ ...rooms, api: API_BASE }), rounds: FAST, fetcher: service.fetcher });
    await expect(attempt).rejects.toBeInstanceOf(ApiError);
    await expect(attempt).rejects.toThrow('Wrong handle or password.');
    expect(rooms.memory.data.size + rooms.disk.data.size + rooms.keys.data.size).toBe(0);
  });

  it('signing out takes the session and every key off this browser', async () => {
    const { rooms, account } = await signedIn(true);
    await account.signOut();
    expect(rooms.memory.data.size + rooms.disk.data.size + rooms.keys.data.size).toBe(0);
  });
});
