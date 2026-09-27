import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useState } from 'react';
import { createNote, getNote, updateNote } from '../core/store.ts';
import { autoTagRefusal, pendingTag } from '../core/location.ts';
import { reloadPreferences, setPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, workspaceOf } from '../core/workspaces.ts';
import { show } from '../../test/render.tsx';
import { useCaptureRoute, type CaptureRoute } from './useCaptureRoute.ts';
import type { Screen } from './screen.ts';

/**
 * Where a capture comes back to, and how the side key reads the moment it is pressed in: every ending a person can
 * meet, from the note with its run on it to a locked phone that shows nothing of what was said.
 */

let route: CaptureRoute;
let screen: Screen;
const refresh = vi.fn(async () => undefined);
const flushDeletes = vi.fn(async () => undefined);

function Probe({ from, tooSoon = false, sayTooSoon = () => undefined, clearStage = () => undefined }: { from: Screen; tooSoon?: boolean; sayTooSoon?: () => void; clearStage?: () => void }) {
  const [now, setNow] = useState<Screen>(from);
  screen = now;
  route = useCaptureRoute({ screen: now, setScreen: setNow, refresh, flushDeletes, atBoot: false, tooSoon: () => tooSoon, sayTooSoon, clearStage });
  return null;
}

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  refresh.mockClear();
  flushDeletes.mockClear();
  delete window.__glyph;
});

const into = (noteId?: string): Screen => ({ name: 'capture', key: 1, fromAssistant: false, stop: 0, ...(noteId ? { noteId } : {}) });

describe('a capture ending', () => {
  it('files the note in the workspace being looked at, and opens it with the instruction said into it', async () => {
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    const note = await createNote('n', '# Said');
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false, undefined, { kind: 'fix' }));
    expect(workspaceOf('n')?.id).toBe(work.id);
    expect(refresh).toHaveBeenCalled();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'n' }, ask: { kind: 'fix' } });
  });

  it('opens the note read fresh for its review', async () => {
    const note = await createNote('n', '# Said');
    await updateNote('n', '# Said, better', note.revision ?? 1);
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false, { noteId: 'n', job: null, heard: 'said', commands: [], touched: [] }));
    expect(screen).toMatchObject({ name: 'note', note: { body: '# Said, better' }, review: { noteId: 'n', heard: 'said' } });
  });

  it('goes home from a locked phone, even from a note spoken into, so nothing of it shows', async () => {
    const note = await createNote('n', '# Said');
    show(<Probe from={into('n')} />);
    await act(async () => route.finished(note, true));
    expect(screen).toEqual({ name: 'list' });
  });

  it('goes back to the note spoken into when nothing new was made, and home when that note has gone', async () => {
    await createNote('n', '# Kept');
    show(<Probe from={into('n')} />);
    await act(async () => route.finished(null, false));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'n' } });
    show(<Probe from={into('missing')} />);
    await act(async () => route.finished(null, false));
    expect(screen).toEqual({ name: 'list' });
  });
});

describe('a capture that wrote into a note', () => {
  it('opens that note with what went in, and files the notes it made', async () => {
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    const note = await createNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    await createNote('made', '# Eggs');
    show(<Probe from={into()} />);
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: ['made'] };
    await act(async () => route.finished(note, false, undefined, undefined, landing));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'house' }, landing: { ...landing, key: expect.any(Number) } });
    expect(workspaceOf('made')?.id).toBe(work.id);
  });

  it('leaves a note that was there already where it was filed, and opens it with an ask said after it', async () => {
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    const note = await createNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n');
    show(<Probe from={into()} />);
    await updateNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', note.revision ?? 1);
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: [] };
    await act(async () => route.finished(note, false, undefined, { kind: 'fix' }, landing));
    expect(workspaceOf('house')).toBeNull();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'house', body: '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n' }, ask: { kind: 'fix', key: expect.any(Number) }, landing: { noteId: 'house' } });
  });

  it('shows nothing of it over a locked phone', async () => {
    const note = await createNote('house', '# House TODOs');
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, true, undefined, undefined, { noteId: 'house', title: 'House TODOs', blocks: [], others: [], made: [] }));
    expect(screen).toEqual({ name: 'list' });
  });
});

describe('a capture starting', () => {
  it('waits for the deferred deletes, then mounts afresh', async () => {
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.start(false, 'n'));
    expect(flushDeletes).toHaveBeenCalledTimes(1);
    expect(screen).toMatchObject({ name: 'capture', fromAssistant: false, stop: 0, noteId: 'n' });
  });
});

describe('the side key with the app open', () => {
  it('clears the stage and records, and during a recording asks it to stop', async () => {
    const clearStage = vi.fn();
    show(<Probe from={{ name: 'list' }} clearStage={clearStage} />);
    await act(async () => window.__glyph!.capture!());
    expect(clearStage).toHaveBeenCalledTimes(1);
    expect(screen).toMatchObject({ name: 'capture', fromAssistant: true, stop: 0 });
    await act(async () => window.__glyph!.capture!());
    expect(screen).toMatchObject({ name: 'capture', stop: 1 });
  });

  it('on a page of the guide still to be read says "not yet" and records nothing', async () => {
    const sayTooSoon = vi.fn();
    show(<Probe from={{ name: 'list' }} tooSoon sayTooSoon={sayTooSoon} />);
    await act(async () => window.__glyph!.capture!());
    expect(sayTooSoon).toHaveBeenCalledTimes(1);
    expect(screen).toEqual({ name: 'list' });
  });
});

describe('where a capture’s new notes were made', () => {
  /** The device answers a fix, or refuses (jsdom has no geolocation). */
  const fixAt = (lat: number, lon: number, code?: number) => {
    const calls: PositionOptions[] = [];
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (ok: PositionCallback, fail: PositionErrorCallback, options: PositionOptions) => {
          calls.push(options);
          if (code) fail({ code, message: '' } as GeolocationPositionError);
          else ok({ coords: { latitude: lat, longitude: lon, accuracy: 15 }, timestamp: 1 } as GeolocationPosition);
        },
      },
    });
    return calls;
  };
  /** Lets the fix, the write and the ask for a name land. */
  const settle = () =>
    act(async () => {
      for (let i = 0; i < 12; i += 1) await Promise.resolve();
    });

  beforeEach(() => {
    // The name would be asked of Nominatim: not in a test.
    setPreferences({ placeNames: false });
  });
  afterEach(() => Reflect.deleteProperty(navigator, 'geolocation'));

  it('tags the note a take made and the notes it made, after the screen has changed, and not a note it only wrote into', async () => {
    const calls = fixAt(51.50741, -0.12776);
    const house = await createNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n');
    await createNote('made', '# Eggs\n');
    show(<Probe from={into()} />);
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: ['made'] };
    await updateNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', house.revision ?? 1);
    await act(async () => route.finished(house, false, undefined, undefined, landing));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'house' } });
    await settle();
    expect(calls).toHaveLength(1);
    expect((await getNote('made'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Eggs\n');
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    // A new note of the take's own, with nothing else made: tagged once the list is showing.
    const said = await createNote('said', '# Said\n');
    await act(async () => route.finished(said, false));
    await settle();
    expect((await getNote('said'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Said\n');
  });

  it('keeps the tag aside while a review with a job is live for the note, and never asks at start', async () => {
    const calls = fixAt(51.5074, -0.1278);
    const note = await createNote('n', '# Said\n');
    show(<Probe from={into()} />);
    const job = { id: 'n', fromMs: 0, recordingMs: 4000, baseBody: '', savedBody: '# Said', titled: true, priorSegments: [], promptTail: '' };
    await act(async () => route.finished(note, false, { noteId: 'n', job, heard: 'said', commands: [], touched: [] }));
    await settle();
    expect(calls).toHaveLength(1);
    expect((await getNote('n'))?.body).toBe('# Said\n');
    expect(pendingTag('n')).toEqual({ lat: 51.5074, lon: -0.1278, place: null, rough: false });
    // Starting a capture asks nothing of the device.
    await act(async () => route.start(false));
    await settle();
    expect(calls).toHaveLength(1);
  });

  it('asks nothing with the switch off, under Local only, or over a locked phone whose permission is not held', async () => {
    const calls = fixAt(51.5074, -0.1278);
    const note = await createNote('n', '# Said\n');
    setPreferences({ tagNewNotes: false });
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false));
    await settle();
    setPreferences({ tagNewNotes: true, localOnly: true });
    await act(async () => route.finished(note, false));
    await settle();
    expect(calls).toHaveLength(0);
    expect((await getNote('n'))?.body).toBe('# Said\n');
    // Locked: the fix is taken quietly, which in a browser (no bridge to ask) is a fix without a dialog.
    setPreferences({ localOnly: false });
    await act(async () => route.finished(note, true));
    await settle();
    expect(calls).toHaveLength(1);
  });

  it('remembers a refusal, so the device is asked once and the note is left untagged', async () => {
    const calls = fixAt(0, 0, 1);
    const one = await createNote('one', '# One\n');
    const two = await createNote('two', '# Two\n');
    show(<Probe from={into()} />);
    await act(async () => route.finished(one, false));
    await settle();
    await act(async () => route.finished(two, false));
    await settle();
    expect(calls).toHaveLength(1);
    expect(autoTagRefusal()).toBe('refused');
    expect((await getNote('one'))?.body).toBe('# One\n');
    expect((await getNote('two'))?.body).toBe('# Two\n');
  });
});
