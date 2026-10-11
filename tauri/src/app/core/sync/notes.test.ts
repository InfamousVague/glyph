// @vitest-environment node
import { afterEach, describe, expect, it } from 'vitest';
import { fakeService } from '../../../test/fakeService.ts';
import { makeNote } from '../../../test/notes.ts';
import { syncDevice, type SyncDevice } from '../../../test/syncDevice.ts';
import { withSummary } from '../../ai/summaryText.ts';
import { markShared } from '../live/shared.ts';
import type { Note } from '../store.ts';
import { readFile, withVersion } from '../versions/file.ts';
import { fileId, mark, mergedIndex, RECORDING_SYNC_LIMIT, recordingBytes, recordingStaysHere, stayedHere } from './notes.ts';

/*
 * The note sync pass (notes.ts) between two devices on the service in memory: the rules a person would feel break -
 * a note typed on one arriving on the other, an edit made on both kept twice rather than lost, a deletion never
 * taking words written since, a push that lost a race merged and sent again, a blank note not sent, a note live on
 * two devices left to the live session, and a recording sent once and fetched by the other. Until this file they ran
 * only in sync.e2e.test.ts, against a real glyph-api behind an environment variable.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };

/** Two devices on one account. */
async function pair(): Promise<{ phone: SyncDevice; mac: SyncDevice; api: Awaited<ReturnType<typeof fakeService>> }> {
  const api = await fakeService(ACCOUNT);
  return { api, phone: syncDevice(api), mac: syncDevice(api) };
}

/** A note as a device edits it: new words, a later time. */
function edited(note: Note, body: string, at: number): Note {
  return { ...note, body, updatedAt: at };
}

afterEach(() => {
  markShared('a', false);
});

describe('a note on two devices', () => {
  it('arrives on the other device, and so does an edit to it', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', '# Groceries\n\nmilk', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    expect(await mac.sync()).toEqual({ changed: 1, conflicts: 0, unsent: 0, reason: null });
    expect(mac.notes.get('a')).toEqual(note);

    mac.notes.set('a', edited(note, '# Groceries\n\nmilk\neggs', 2));
    await mac.sync();
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('# Groceries\n\nmilk\neggs');
  });

  it('does not come back to the device that wrote it as a change', async () => {
    const { phone } = await pair();
    phone.notes.set('a', makeNote('a', 'words'));
    await phone.sync();
    expect(await phone.sync()).toEqual({ changed: 0, conflicts: 0, unsent: 0, reason: null });
  });

  it('keeps both versions when both devices changed the words, the other device’s keeping the id', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'shared', { createdAt: 1, updatedAt: 1, path: 'Inbox/shared.md', recordingMs: 900 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, 'the phone’s words', 2));
    mac.notes.set('a', edited(note, 'the Mac’s words', 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });

    expect(mac.notes.get('a')?.body).toBe('the phone’s words');
    const copy = [...mac.notes.values()].find((n) => n.id !== 'a');
    expect(copy?.body).toBe('the Mac’s words');
    // The copy is the words: its recording is filed under the note's id, which the other version keeps.
    expect(copy).toMatchObject({ recordingMs: null, segments: null, path: undefined });
    // And the copy reaches the phone too, so neither device loses a word.
    await phone.sync();
    expect([...phone.notes.values()].map((n) => n.body).sort()).toEqual(['the Mac’s words', 'the phone’s words']);
  });

  it('takes the other device’s pin or archive without a copy, when only those changed on both', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', { ...note, starred: true });
    mac.notes.set('a', { ...note, archivedAt: 5 });
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 0 });
    expect(mac.notes.size).toBe(1);
    expect(mac.notes.get('a')).toMatchObject({ starred: true });
  });
});

describe('a deletion', () => {
  it('takes the note off the other device when it had not changed there', async () => {
    const { phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', 'words'));
    await phone.sync();
    await mac.sync();
    phone.notes.delete('a');
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ changed: 1 });
    expect(mac.notes.has('a')).toBe(false);
  });

  it('never takes words written since on the other device: they stand, and come back to the first', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.delete('a');
    await phone.sync();
    mac.notes.set('a', edited(note, 'words written after', 4));
    await mac.sync();
    expect(mac.notes.get('a')?.body).toBe('words written after');
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('words written after');
  });
});

describe('a push that lost a race', () => {
  /**
   * The Mac, with `meanwhile` run by another device just before the Mac's first write of note `a` reaches the service:
   * after its pull, so the push is refused with what won.
   */
  async function racing(meanwhile: (api: Awaited<ReturnType<typeof fakeService>>) => Promise<unknown>) {
    const api = await fakeService(ACCOUNT);
    let raced = false;
    const fetcher: typeof fetch = async (input, init) => {
      if (!raced && init?.method === 'PUT' && String(input).endsWith('/v1/notes/a')) {
        raced = true;
        await meanwhile(api);
      }
      return api.fetcher(input, init);
    };
    return { api, phone: syncDevice(api), mac: syncDevice(api, { fetcher }) };
  }

  it('keeps its own words as a copy when what won changed them too, and sends the copy on the next pass', async () => {
    const note = makeNote('a', 'first', { createdAt: 1, updatedAt: 1 });
    const { api, phone, mac } = await racing((service) => service.deviceWrites(edited(note, 'written elsewhere', 2)));
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    mac.notes.set('a', edited(note, 'the Mac’s edit', 3));
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });
    expect(mac.notes.get('a')?.body).toBe('written elsewhere');
    expect([...mac.notes.values()].map((n) => n.body)).toContain('the Mac’s edit');
    await mac.sync();
    await phone.sync();
    expect([...phone.notes.values()].map((n) => n.body).sort()).toEqual(['the Mac’s edit', 'written elsewhere']);
    expect(api.notes.size).toBe(2);
  });

  it('sends its edit again from the deletion’s revision when what won was a deletion', async () => {
    const note = makeNote('a', 'first', { createdAt: 1, updatedAt: 1 });
    const { api, phone, mac } = await racing(async (service) => {
      const body = JSON.stringify({ base: service.notes.get('a')!.rev });
      await service.fetcher('https://glyph.test/v1/notes/a', { method: 'DELETE', headers: { Authorization: `Bearer ${service.signedIn()}` }, body });
    });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    mac.notes.set('a', edited(note, 'the Mac’s edit', 3));
    api.calls.length = 0;
    await mac.sync();
    expect(api.calls.filter((call) => call === 'PUT notes/a')).toHaveLength(2);
    expect((await api.stored('a'))?.note.body).toBe('the Mac’s edit');
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('the Mac’s edit');
  });
});

describe('what is not sent', () => {
  it('a note opened and left empty, until it has words', async () => {
    const { api, phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', '   '));
    await phone.sync();
    expect(api.notes.has('a')).toBe(false);
    phone.notes.set('a', makeNote('a', 'now words'));
    await phone.sync();
    await mac.sync();
    expect(mac.notes.get('a')?.body).toBe('now words');
  });

  it('a note live on two devices right now, neither pushed nor merged until the session ends', async () => {
    const { api, phone, mac } = await pair();
    const note = makeNote('a', 'words', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    markShared('a', true);
    phone.notes.set('a', edited(note, 'typed live', 2));
    const before = api.notes.get('a')?.rev;
    await phone.sync();
    expect(api.notes.get('a')?.rev).toBe(before);
    await api.deviceWrites(edited(note, 'from a third device', 3));
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe('typed live');
    markShared('a', false);
    await phone.sync();
    expect(api.notes.get('a')?.rev).not.toBe(before);
  });
});

describe('a versions file', () => {
  const keep = (file: string | null, text: string, at: number, label?: string) => withVersion(file, 'a', text, { at, by: 'matt', ...(label ? { label } : {}) })!;
  const texts = (device: SyncDevice) => readFile(device.versions.get('a') ?? '')?.versions.map((v) => v.text) ?? [];

  it('goes with its note and is fetched by the other device', async () => {
    const { api, phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', 'one', { createdAt: 1, updatedAt: 1 }));
    phone.keepVersions('a', keep(null, 'one', 1));
    await phone.sync();
    expect(api.files.has(fileId('versions', 'a')!)).toBe(true);
    expect(phone.owed.size).toBe(0);
    await mac.sync();
    expect(texts(mac)).toEqual(['one']);
  });

  it('goes on its own when a version is named by hand, with no change to the words', async () => {
    const { phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', 'one', { createdAt: 1, updatedAt: 1 }));
    phone.keepVersions('a', keep(null, 'one', 1));
    await phone.sync();
    await mac.sync();
    phone.keepVersions('a', keep(phone.versions.get('a')!, 'one', 2, 'Sent to Sam'));
    await phone.sync();
    expect(phone.owed.size).toBe(0);
    // The words did not move, and the note went again with its file, so the Mac fetched the name with it.
    await mac.sync();
    expect(readFile(mac.versions.get('a')!)!.versions[0]!.label).toBe('Sent to Sam');
    phone.notes.set('a', edited(phone.notes.get('a')!, 'one\ntwo', 3));
    phone.keepVersions('a', keep(phone.versions.get('a')!, 'one\ntwo', 3));
    await phone.sync();
    await mac.sync();
    expect(readFile(mac.versions.get('a')!)!.versions.map((v) => [v.text, v.label])).toEqual([
      ['one', 'Sent to Sam'],
      ['one\ntwo', undefined],
    ]);
  });

  it('kept on both devices at once is one timeline on both, with every version of each', async () => {
    const { phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', 'one', { createdAt: 1, updatedAt: 1 }));
    phone.keepVersions('a', keep(null, 'one', 1));
    await phone.sync();
    await mac.sync();
    // Each keeps a version of its own before hearing of the other's.
    phone.keepVersions('a', keep(phone.versions.get('a')!, 'one\nphone', 5));
    mac.keepVersions('a', keep(mac.versions.get('a')!, 'one\nmac', 4));
    await phone.sync();
    await mac.sync();
    await phone.sync();
    expect(texts(mac)).toEqual(['one', 'one\nmac', 'one\nphone']);
    expect(texts(phone)).toEqual(texts(mac));
  });
});

describe('a recording', () => {
  it('goes with its note, once, and is fetched by the other device', async () => {
    const { api, phone, mac } = await pair();
    const tape = new Uint8Array([82, 73, 70, 70, 1, 2, 3]);
    const note = makeNote('a', 'spoken', { createdAt: 1, updatedAt: 1, recordingMs: 1_200 });
    phone.notes.set('a', note);
    phone.tapes.set('a', tape);
    await phone.sync();
    const id = fileId('recording', 'a')!;
    expect(api.files.has(id)).toBe(true);
    await mac.sync();
    expect(mac.tapes.get('a')).toEqual(tape);

    // An edit to the words sends the note again, and not the recording, whose bytes did not move.
    api.calls.length = 0;
    phone.notes.set('a', edited(note, 'spoken, and edited', 2));
    await phone.sync();
    expect(api.calls).toContain('PUT notes/a');
    expect(api.calls.some((call) => call.startsWith(`PUT recordings/${id}`))).toBe(false);
    expect(mark(phone.notes.get('a')!)).toBe(phone.state.notes.a?.mark);
  });
});

describe('a recording that stays on this device', () => {
  const tape = new Uint8Array([82, 73, 70, 70, 1, 2, 3]);

  it('is one over the service’s limit, decided from its length without reading a byte: the note goes with its phrases and no digest', async () => {
    const { api, phone, mac } = await pair();
    const forty = 40 * 60_000;
    expect(recordingBytes(forty)).toBeGreaterThan(RECORDING_SYNC_LIMIT);
    expect(recordingStaysHere({ id: 'a', recordingMs: forty }, {}, false)).toBe(true);
    expect(recordingStaysHere({ id: 'a', recordingMs: 30 * 60_000 }, {}, false)).toBe(false);
    const note = makeNote('a', 'a long one', { createdAt: 1, updatedAt: 1, recordingMs: forty, segments: [{ text: 'a long one', startMs: 0, endMs: 900 }] });
    phone.notes.set('a', note);
    let reads = 0;
    const get = phone.tapes.get.bind(phone.tapes);
    phone.tapes.get = (name: string) => {
      reads += 1;
      return get(name);
    };
    phone.tapes.set('a', tape);
    await phone.sync();
    expect(reads).toBe(0);
    expect(api.calls.some((call) => call.startsWith('PUT recordings/'))).toBe(false);
    await mac.sync();
    expect(mac.notes.get('a')).toMatchObject({ recordingMs: forty, segments: note.segments });
    expect(mac.tapes.has('a')).toBe(false);
  });

  it('is a meeting’s while meeting recordings stay on the phone, and goes once the setting says so', async () => {
    const { api, phone, mac } = await pair();
    phone.notes.set('m', makeNote('m', '# Meeting, 26 Sep 14:05', { createdAt: 1, updatedAt: 1, recordingMs: 60_000 }));
    phone.tapes.set('m', tape);
    await phone.sync({ meetings: { m: 1 }, syncMeetingRecordings: false });
    expect(api.files.has(fileId('recording', 'm')!)).toBe(false);
    await mac.sync();
    expect(mac.notes.get('m')?.recordingMs).toBe(60_000);
    expect(mac.tapes.has('m')).toBe(false);
    // Switched on: the next pass sends it, though the words did not change.
    await phone.sync({ meetings: { m: 1 }, syncMeetingRecordings: true });
    expect(api.files.has(fileId('recording', 'm')!)).toBe(true);
    await mac.sync();
    expect(mac.tapes.get('m')).toEqual(tape);
    // A recording that is not a meeting's goes as it always did, setting or no setting.
    expect(stayedHere([makeNote('m', '', { recordingMs: 60_000 }), makeNote('r', '', { recordingMs: 60_000 }), makeNote('big', '', { recordingMs: 40 * 60_000 })], { meetings: { m: 1 }, syncMeetingRecordings: false })).toBe(2);
  });

  it('is hashed once per length, not on every push: a ticked to-do no longer costs an hour’s audio read three times', async () => {
    const { phone } = await pair();
    const note = makeNote('a', 'spoken', { createdAt: 1, updatedAt: 1, recordingMs: 1_200 });
    phone.notes.set('a', note);
    let reads = 0;
    const get = phone.tapes.get.bind(phone.tapes);
    phone.tapes.get = (name: string) => {
      reads += 1;
      return get(name);
    };
    phone.tapes.set('a', tape);
    await phone.sync();
    expect(reads).toBe(1);
    expect(phone.state.files[fileId('recording', 'a')!]).toMatchObject({ forMs: 1_200, sha: expect.any(String) });
    phone.notes.set('a', edited(note, 'spoken, and edited', 2));
    await phone.sync();
    expect(reads).toBe(1);
    // The tape changed only when its length did: an Add to it.
    phone.notes.set('a', { ...note, body: 'spoken, and edited', updatedAt: 3, recordingMs: 2_400 });
    phone.tapes.set('a', new Uint8Array([...tape, 4, 5]));
    await phone.sync();
    expect(reads).toBe(2);
    expect(phone.state.files[fileId('recording', 'a')!]).toMatchObject({ forMs: 2_400 });
  });

  it('takes the phone’s own digest where there is one, reading the bytes only to send them, and remembers a tape that was not there', async () => {
    const { api } = await pair();
    const asked: string[] = [];
    let answer: string | null | undefined = 'abcd'.repeat(8);
    const phone = syncDevice(api, {
      digest: async (name) => {
        asked.push(name);
        return answer;
      },
    });
    const note = makeNote('a', 'spoken', { createdAt: 1, updatedAt: 1, recordingMs: 1_200 });
    phone.notes.set('a', note);
    let reads = 0;
    const get = phone.tapes.get.bind(phone.tapes);
    phone.tapes.get = (name: string) => {
      reads += 1;
      return get(name);
    };
    phone.tapes.set('a', tape);
    await phone.sync();
    expect(asked).toEqual(['a']);
    expect(reads).toBe(1);
    expect(api.files.has(fileId('recording', 'a')!)).toBe(true);
    // Hashed at this length: not asked again, not read again.
    phone.notes.set('a', edited(note, 'spoken, and edited', 2));
    await phone.sync();
    expect(asked).toEqual(['a']);
    expect(reads).toBe(1);
    // A tape the phone says is not there is remembered at this length, and not asked about on every push.
    answer = null;
    phone.notes.set('b', makeNote('b', 'gone', { createdAt: 1, updatedAt: 1, recordingMs: 900 }));
    await phone.sync();
    await phone.sync();
    expect(asked).toEqual(['a', 'b']);
    expect(phone.state.files[fileId('recording', 'b')!]).toEqual({ rev: 0, forMs: 900 });
    // A binary that cannot say: the bytes are read and hashed here, as before.
    answer = undefined;
    phone.notes.set('c', makeNote('c', 'here', { createdAt: 1, updatedAt: 1, recordingMs: 900 }));
    phone.tapes.set('c', tape);
    await phone.sync();
    expect(api.files.has(fileId('recording', 'c')!)).toBe(true);
  });
});

describe('one note that cannot be sent', () => {
  it('is counted with why, and the others still go; it is sent again next time', async () => {
    const { api } = await pair();
    let failing = true;
    const fetcher: typeof fetch = async (input, init) => {
      if (failing && init?.method === 'PUT' && String(input).endsWith('/notes/b')) return new Response(JSON.stringify({ error: 'That note is too big.' }), { status: 413, headers: { 'Content-Type': 'application/json' } });
      return api.fetcher(input, init);
    };
    const phone = syncDevice(api, { fetcher });
    for (const id of ['a', 'b', 'c']) phone.notes.set(id, makeNote(id, `words ${id}`, { createdAt: 1, updatedAt: 1 }));
    expect(await phone.sync()).toMatchObject({ unsent: 1, reason: 'That note is too big.' });
    // The refused one never reached the service; the ones after it did.
    expect(api.calls.filter((call) => call.startsWith('PUT notes/'))).toEqual(['PUT notes/a', 'PUT notes/c']);
    failing = false;
    expect(await phone.sync()).toMatchObject({ unsent: 0, reason: null });
    expect(api.calls.filter((call) => call.startsWith('PUT notes/')).at(-1)).toBe('PUT notes/b');
  });

  it('is not a lapsed session, which still ends the pass', async () => {
    const { api } = await pair();
    const fetcher: typeof fetch = async (input, init) => {
      if (init?.method === 'PUT' && String(input).includes('/notes/')) return new Response(JSON.stringify({ error: 'Sign in again.' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
      return api.fetcher(input, init);
    };
    const phone = syncDevice(api, { fetcher });
    phone.notes.set('a', makeNote('a', 'words', { createdAt: 1, updatedAt: 1 }));
    await expect(phone.sync()).rejects.toMatchObject({ status: 401 });
  });
});

describe('a summary on both devices', () => {
  it('keeps one note, this device’s section on the other’s words, and no copy', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', '# Plan\n\nwords', { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    const mine = '## Summary\nThe phone’s line.\n\n- One.';
    const theirs = '## Summary\nThe Mac’s line.\n\n- Two.';
    phone.notes.set('a', edited(note, withSummary(note.body, mine), 2));
    mac.notes.set('a', edited(note, withSummary(note.body, theirs), 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 0, changed: 1 });
    expect(mac.notes.size).toBe(1);
    expect(mac.notes.get('a')?.body).toBe(withSummary(note.body, theirs));
    // The merged note is what the Mac sends next, so the phone comes to hold it too.
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe(withSummary(note.body, theirs));
    expect(phone.notes.size).toBe(1);
  });
});

describe('a notebook on two devices', () => {
  const DIARY = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\nOn the train, mostly.\n\n- [[2026-09-27 21.40]]\n';

  it('keeps one note when both added a line to its index: theirs, and this device’s line after the one it followed', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', DIARY, { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, `${DIARY}- [[2026-09-28 08.10]]\n`, 2));
    mac.notes.set('a', edited(note, `${DIARY}- [[2026-09-28 14.05]]\n`, 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 0, changed: 1 });
    expect(mac.notes.size).toBe(1);
    // The Mac's line goes after the line it followed on the Mac; a journal's view orders by time whatever the lines say.
    const merged = `${DIARY.replace('- [[2026-09-27 21.40]]\n', '- [[2026-09-27 21.40]]\n- [[2026-09-28 14.05]]\n')}- [[2026-09-28 08.10]]\n`;
    expect(mac.notes.get('a')?.body).toBe(merged);
    // What the Mac merged is what it sends next, so the phone holds it too.
    await phone.sync();
    expect(phone.notes.get('a')?.body).toBe(merged);
    expect(phone.notes.size).toBe(1);
  });

  it('merges the first line two devices each added to an empty index too', async () => {
    const { phone, mac } = await pair();
    const empty = '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n';
    const note = makeNote('a', empty, { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, `${empty}- [[One]]\n`, 2));
    mac.notes.set('a', edited(note, `${empty}- [[Two]]\n`, 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 0 });
    expect(mac.notes.get('a')?.body).toBe(`${empty}- [[One]]\n- [[Two]]\n`);
  });

  it('still keeps a copy when the words around the index changed on both sides', async () => {
    const { phone, mac } = await pair();
    const note = makeNote('a', DIARY, { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, DIARY.replace('On the train, mostly.', 'On the bus.'), 2));
    mac.notes.set('a', edited(note, `${DIARY}- [[2026-09-28 14.05]]\n`, 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });
  });

  it('reads the blank lines round the index as one, however many a line taken out left', () => {
    const head = '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n';
    // Here a line was added; there the only line was taken out by hand, and the blank lines either side of it kept.
    const merged = mergedIndex(`${head}- [[A]]\n- [[B]]\n\nAfter the list.\n`, `${head}\n\n\nAfter the list.\n`);
    expect(merged).not.toBeNull();
    expect(merged).toContain('- [[B]]');
  });

  it('merges only notebooks: a note with a list of links changed on both sides is kept twice', async () => {
    const { phone, mac } = await pair();
    const list = '# Reading\n\n- [[One]]\n';
    const note = makeNote('a', list, { createdAt: 1, updatedAt: 1 });
    phone.notes.set('a', note);
    await phone.sync();
    await mac.sync();
    phone.notes.set('a', edited(note, `${list}- [[Two]]\n`, 2));
    mac.notes.set('a', edited(note, `${list}- [[Three]]\n`, 3));
    await phone.sync();
    expect(await mac.sync()).toMatchObject({ conflicts: 1 });
  });
});

/** A note filed in an organization's workspace is the team's (docs/SHARED.md, S1): the organization channel carries it, not this feed. */
describe('a team’s note and the account’s feed', () => {
  it('is deleted from the feed once it is the team’s, and a row of it in the feed is passed over', async () => {
    const { phone, mac } = await pair();
    phone.notes.set('a', makeNote('a', '# Roadmap'));
    await phone.sync();
    await mac.sync();
    expect(mac.notes.get('a')?.body).toBe('# Roadmap');
    // Filed in a team on the phone: the account's row goes, so the mac takes the note from the team instead.
    const team = new Set(['a']);
    phone.notes.set('a', edited(phone.notes.get('a')!, '# Roadmap\n- for the team', 5));
    await phone.sync({ teamNote: (id) => team.has(id) });
    expect(phone.state.notes.a).toBeUndefined();
    await mac.sync();
    expect(mac.notes.has('a')).toBe(false);
    // On the mac the note is the team's too now (the organization channel brought it): the deletion, and any row
    // of it the feed still holds, are passed over, and the note is not sent as the account's own.
    mac.notes.set('a', makeNote('a', '# Roadmap\n- for the team'));
    await mac.sync({ teamNote: (id) => team.has(id) });
    expect(mac.notes.get('a')?.body).toBe('# Roadmap\n- for the team');
    expect(mac.state.notes.a).toBeUndefined();
    // Nothing of it was sent again: the feed holds one row, the deletion.
    expect(phone.state.notes.a).toBeUndefined();
  });
});
