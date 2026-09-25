import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { fakeService, FAST, type FakeService } from '../../../test/fakeService.ts';
import { makeNote } from '../../../test/notes.ts';
import { newDeviceKey, open } from '../sync/crypto.ts';
import { accountState, changePassword, deleteAccount, newRecoveryCodes, recover, resume, signIn, signOut, signUp, type Deps } from './account.ts';
import { ApiError } from './api.ts';
import { memoryKeys } from './keystore.ts';

/**
 * The account on this device, against the service in memory (src/test/fakeService.ts): making one, the three ways
 * in, the two changes that need the password, what launch does with a session it finds, and the two ways out. Until
 * this file half of these ran only in sync.e2e.test.ts, against a real glyph-api and behind an environment variable,
 * so a change to one was tried only by someone who started a server first; resume, newRecoveryCodes and signOut
 * were not tried at all.
 */

const HANDLE = 'matt';
const PASSWORD = 'correct horse';

/** A device: its own keys, and the service it talks to. */
const deviceOf = (service: FakeService): Deps => ({ keys: memoryKeys(), rounds: FAST, fetcher: service.fetcher });

/** A refusal's status, or what went wrong instead. */
const statusOf = (attempt: Promise<unknown>) =>
  attempt.then(
    () => 'no refusal',
    (failure: unknown) => (failure instanceof ApiError ? failure.status : failure),
  );

beforeEach(() => localStorage.clear());
// The account's state is the module's own, as it is for the page: each test leaves the device signed out.
afterEach(() => signOut({ keys: memoryKeys(), rounds: FAST }));

describe('signing up', () => {
  it('makes the account, hands back a sheet of eight codes, and leaves this device signed in and unlocked', async () => {
    const service = await fakeService();
    const phone = deviceOf(service);
    const { codes } = await signUp(HANDLE, PASSWORD, phone);
    expect(codes).toHaveLength(8);
    expect(new Set(codes).size).toBe(8);
    expect(accountState()).toMatchObject({ session: { handle: HANDLE, accountId: 7 }, unlocked: true });
    expect(await phone.keys.accountKey()).not.toBeNull();
    expect(await phone.keys.deviceKey()).not.toBeNull();
    // Signed up with the device key, so no second call to register it.
    expect(service.calls).toEqual(['POST signup']);
  });

  it('says what is wrong with a handle or a password before asking the service anything', async () => {
    const service = await fakeService();
    expect(await statusOf(signUp('m', PASSWORD, deviceOf(service)))).toBe(400);
    expect(await statusOf(signUp(HANDLE, 'short', deviceOf(service)))).toBe(400);
    expect(service.calls).toEqual([]);
  });

  it('is refused for a handle already taken', async () => {
    const service = await fakeService();
    await signUp(HANDLE, PASSWORD, deviceOf(service));
    expect(await statusOf(signUp(HANDLE, 'another horse', deviceOf(service)))).toBe(409);
  });
});

describe('signing in with the password', () => {
  it('comes away with the account’s own key, and registers this device once', async () => {
    const service = await fakeService({ handle: HANDLE, password: PASSWORD });
    await service.deviceWrites(makeNote('n1', '# Groceries'));
    const desk = deviceOf(service);
    await signIn(HANDLE, PASSWORD, desk);
    expect(accountState()).toMatchObject({ session: { handle: HANDLE }, unlocked: true });
    // The key this device kept opens what another device sealed.
    const key = (await desk.keys.accountKey())!;
    expect(await open<{ note: { body: string } }>(key, service.notes.get('n1')!.blob!, 'note:n1')).toMatchObject({ note: { body: '# Groceries' } });
    expect(service.calls).toEqual(['POST login', 'POST device']);
    await signIn(HANDLE, PASSWORD, desk);
    expect(service.calls.filter((call) => call === 'POST device')).toHaveLength(1);
  });

  it('is refused on the wrong password, and leaves the device as it was', async () => {
    const service = await fakeService({ handle: HANDLE, password: PASSWORD });
    const desk = deviceOf(service);
    expect(await statusOf(signIn(HANDLE, 'wrong horse', desk))).toBe(401);
    expect(await desk.keys.accountKey()).toBeNull();
    expect(accountState().session).toBeNull();
  });
});

describe('recovering with a code', () => {
  it('spends the code, sets the new password, and answers a fresh sheet in place of the old', async () => {
    const service = await fakeService();
    const { codes } = await signUp(HANDLE, PASSWORD, deviceOf(service));
    // That phone is gone, and the password with it: a new one starts from the sheet.
    await signOut(deviceOf(service));
    const lost = deviceOf(service);
    // Typed as a person types it off the sheet: case and dashes do not matter.
    const fresh = await recover(HANDLE, codes[0]!.toLowerCase(), 'a new horse', lost);
    expect(fresh.codes).toHaveLength(8);
    expect(fresh.codes.filter((code) => codes.includes(code))).toEqual([]);
    expect(accountState()).toMatchObject({ session: { handle: HANDLE }, unlocked: true });
    expect(await lost.keys.deviceKey()).not.toBeNull();
    // The password is the new one, the spent code is gone, and so is the rest of the old sheet.
    expect(await statusOf(signIn(HANDLE, PASSWORD, deviceOf(service)))).toBe(401);
    await signIn(HANDLE, 'a new horse', deviceOf(service));
    expect(await statusOf(recover(HANDLE, codes[0]!, 'third horse', deviceOf(service)))).toBe(401);
    expect(await statusOf(recover(HANDLE, codes[1]!, 'third horse', deviceOf(service)))).toBe(401);
    await recover(HANDLE, fresh.codes[3]!, 'third horse', deviceOf(service));
    expect(service.codesLeft()).toBe(8);
  });

  it('will not set a password too short to keep, and asks nothing of the service for it', async () => {
    const service = await fakeService();
    expect(await statusOf(recover(HANDLE, 'ABCD-EFGH', 'short', deviceOf(service)))).toBe(400);
    expect(service.calls).toEqual([]);
  });
});

describe('what needs the password on a signed-in device', () => {
  it('changes the password, once the current one has opened the key', async () => {
    const service = await fakeService();
    const phone = deviceOf(service);
    await signUp(HANDLE, PASSWORD, phone);
    expect(await statusOf(changePassword('wrong horse', 'a new horse', phone))).toBe(401);
    expect(await statusOf(changePassword(PASSWORD, 'short', phone))).toBe(400);
    await changePassword(PASSWORD, 'a new horse', phone);
    expect(await statusOf(signIn(HANDLE, PASSWORD, deviceOf(service)))).toBe(401);
    await signIn(HANDLE, 'a new horse', deviceOf(service));
  });

  it('makes a new recovery sheet, and the old one stops working', async () => {
    const service = await fakeService();
    const phone = deviceOf(service);
    const { codes } = await signUp(HANDLE, PASSWORD, phone);
    expect(await statusOf(newRecoveryCodes('wrong horse', phone))).toBe(401);
    const next = await newRecoveryCodes(PASSWORD, phone);
    expect(next.codes).toHaveLength(8);
    expect(await statusOf(recover(HANDLE, codes[0]!, 'a new horse', deviceOf(service)))).toBe(401);
    await recover(HANDLE, next.codes[0]!, 'a new horse', deviceOf(service));
  });

  it('asks for a session before either', async () => {
    const service = await fakeService();
    expect(await statusOf(changePassword(PASSWORD, 'a new horse', deviceOf(service)))).toBe(401);
    expect(await statusOf(newRecoveryCodes(PASSWORD, deviceOf(service)))).toBe(401);
    expect(service.calls).toEqual([]);
  });
});

describe('resuming on launch', () => {
  /** A phone signed up on the service, with the session it would find in its storage at the next launch. */
  async function launched() {
    const service = await fakeService();
    const phone = deviceOf(service);
    await signUp(HANDLE, PASSWORD, phone);
    const before = accountState().session!;
    service.calls.length = 0;
    return { service, phone, before };
  }

  it('renews a live session', async () => {
    const { service, phone, before } = await launched();
    await resume(phone);
    expect(service.calls).toEqual(['POST refresh']);
    expect(accountState().session?.token).not.toBe(before.token);
    expect(accountState().unlocked).toBe(true);
  });

  it('keeps the session it had while the service cannot be reached', async () => {
    const { phone, before } = await launched();
    const offline: typeof fetch = () => Promise.reject(new TypeError('Failed to fetch'));
    await resume({ ...phone, fetcher: offline });
    expect(accountState()).toEqual({ session: before, unlocked: true });
  });

  it('signs in again with this device’s own key when the session has lapsed', async () => {
    const { service, phone, before } = await launched();
    service.expireAllTokens();
    await resume(phone);
    expect(service.calls).toEqual(['POST refresh', 'POST login/challenge', 'POST login/device']);
    expect(accountState().session).toMatchObject({ handle: HANDLE, accountId: 7 });
    expect(accountState().session?.token).not.toBe(before.token);
    // And the token it came away with works.
    service.calls.length = 0;
    await resume(phone);
    expect(service.calls).toEqual(['POST refresh']);
  });

  it('signs out, keys and all, when the session has lapsed and the device key cannot renew it', async () => {
    const { service, phone } = await launched();
    // A key the account never registered, as on a device the account has since been taken from.
    await phone.keys.setDeviceKey(await newDeviceKey());
    service.expireAllTokens();
    await resume(phone);
    expect(service.calls).toEqual(['POST refresh', 'POST login/challenge', 'POST login/device']);
    expect(accountState()).toEqual({ session: null, unlocked: false });
    expect(await phone.keys.accountKey()).toBeNull();
    expect(await phone.keys.deviceKey()).toBeNull();
  });

  it('signs out when the session has lapsed on a device with no key of its own', async () => {
    const { service, phone } = await launched();
    service.expireAllTokens();
    await phone.keys.setDeviceKey(null);
    await resume(phone);
    expect(accountState().session).toBeNull();
    expect(await phone.keys.accountKey()).toBeNull();
    expect(service.calls).toEqual(['POST refresh']);
  });

  it('settles signed out when there is no session to resume', async () => {
    const service = await fakeService();
    await resume(deviceOf(service));
    expect(accountState()).toEqual({ session: null, unlocked: false });
    expect(service.calls).toEqual([]);
  });
});

describe('the ways out', () => {
  it('deletes the account only with the password, then signs out and leaves the notes to the device', async () => {
    const service = await fakeService();
    const phone = deviceOf(service);
    await signUp(HANDLE, PASSWORD, phone);
    expect(await statusOf(deleteAccount('wrong horse', phone))).toBe(403);
    expect(service.hasAccount()).toBe(true);
    expect(accountState().session).not.toBeNull();
    await deleteAccount(PASSWORD, phone);
    expect(service.hasAccount()).toBe(false);
    expect(accountState()).toEqual({ session: null, unlocked: false });
    expect(await phone.keys.accountKey()).toBeNull();
    // Gone from the service too: the password no longer signs in anywhere.
    expect(await statusOf(signIn(HANDLE, PASSWORD, deviceOf(service)))).toBe(401);
  });

  it('signs out of this device alone: the session and both keys go, the account stays', async () => {
    const service = await fakeService();
    const phone = deviceOf(service);
    await signUp(HANDLE, PASSWORD, phone);
    await signOut(phone);
    expect(accountState()).toEqual({ session: null, unlocked: false });
    expect(await phone.keys.accountKey()).toBeNull();
    expect(await phone.keys.deviceKey()).toBeNull();
    expect(service.hasAccount()).toBe(true);
    expect(await statusOf(deleteAccount(PASSWORD, phone))).toBe(401);
  });
});
