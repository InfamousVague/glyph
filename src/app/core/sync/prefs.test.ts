// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import { DEFAULT_PREFERENCES, type Preferences } from '../preferences.ts';
import { seal } from './crypto.ts';
import { syncPrefs, type PrefsContext, type PrefsState } from './prefs.ts';

/**
 * Settings on every device (prefs.ts), against the service in memory: one sealed blob, written from the revision
 * last seen. A device that changed nothing takes what another wrote; one that changed something sends it, and the
 * one sending now wins; a write that loses a race reads again, once.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };

/** A device's settings and what it remembers of the account's, synced through `service`. */
function device(service: FakeService, fetcher: typeof fetch = service.fetcher) {
  let prefs: Preferences = { ...DEFAULT_PREFERENCES };
  let state: PrefsState = { rev: 0, seen: null };
  const ctx = (): PrefsContext => ({
    token: service.signedIn(),
    key: service.accountKey,
    read: () => prefs,
    write: (next) => {
      prefs = { ...prefs, ...next };
    },
    state,
    save: (next) => {
      state = next;
    },
    fetcher,
  });
  return {
    get prefs() {
      return prefs;
    },
    set: (next: Partial<Preferences>) => {
      prefs = { ...prefs, ...next };
    },
    sync: () => syncPrefs(ctx()),
  };
}

describe('settings kept the same on every device', () => {
  it('are sent by the first device, and taken by the next one to sign in', async () => {
    const service = await fakeService(ACCOUNT);
    const phone = device(service);
    phone.set({ theme: 'ember', textSize: 'larger' });
    expect(await phone.sync()).toBe(false);
    expect(service.calls).toEqual(['GET prefs', 'PUT prefs']);
    const desk = device(service);
    expect(await desk.sync()).toBe(true);
    expect(desk.prefs).toMatchObject({ theme: 'ember', textSize: 'larger' });
    // Nothing more to say on either side.
    service.calls.length = 0;
    expect(await phone.sync()).toBe(false);
    expect(await desk.sync()).toBe(false);
    expect(service.calls).toEqual(['GET prefs', 'GET prefs']);
  });

  it('take a change from another device when this one changed nothing, and send this one’s when it did', async () => {
    const service = await fakeService(ACCOUNT);
    const phone = device(service);
    const desk = device(service);
    await phone.sync();
    await desk.sync();
    desk.set({ theme: 'dawn' });
    await desk.sync();
    expect(await phone.sync()).toBe(true);
    expect(phone.prefs.theme).toBe('dawn');
    // Both change: the one sending now wins, settings being chosen rather than typed.
    phone.set({ theme: 'boreal' });
    desk.set({ theme: 'ember' });
    await desk.sync();
    await phone.sync();
    expect(await desk.sync()).toBe(true);
    expect(desk.prefs.theme).toBe('boreal');
  });

  it('carry only what describes the person: which model a phone formats with, and whether it syncs, stay with it', async () => {
    const service = await fakeService(ACCOUNT);
    const phone = device(service);
    phone.set({ theme: 'ember', formatModel: 'qwen3.5-2b', localOnly: true });
    await phone.sync();
    const desk = device(service);
    await desk.sync();
    expect(desk.prefs).toMatchObject({ theme: 'ember', formatModel: DEFAULT_PREFERENCES.formatModel, localOnly: false });
  });

  it('ignore what a newer build wrote that this one does not know', async () => {
    const service = await fakeService(ACCOUNT);
    const token = service.signedIn();
    const blob = await seal(service.accountKey, { theme: 'dawn', fromTheFuture: true }, 'prefs');
    await service.fetcher('https://fake.test/glyph/api/v1/prefs', { method: 'PUT', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify({ base: 0, blob }) });
    const phone = device(service);
    expect(await phone.sync()).toBe(true);
    expect(phone.prefs.theme).toBe('dawn');
    expect('fromTheFuture' in phone.prefs).toBe(false);
  });

  it('read again, once, when another device wrote between the read and the write', async () => {
    const service = await fakeService(ACCOUNT);
    const desk = device(service);
    await desk.sync();
    const phone = device(service);
    await phone.sync();
    // The desk writes in the moment between the phone's read and its write.
    let raced = false;
    const racing: typeof fetch = async (input, init) => {
      if (init?.method === 'PUT' && !raced) {
        raced = true;
        desk.set({ theme: 'dawn' });
        await desk.sync();
      }
      return service.fetcher(input, init);
    };
    const late = device(service, racing);
    await late.sync();
    late.set({ theme: 'ember' });
    await late.sync();
    expect(raced).toBe(true);
    // Refused once, read again, and sent from the revision the desk's write made: the phone's choice stands.
    expect(service.calls.filter((call) => call === 'PUT prefs').length).toBeGreaterThanOrEqual(3);
    expect(await desk.sync()).toBe(true);
    expect(desk.prefs.theme).toBe('ember');
  });
});
