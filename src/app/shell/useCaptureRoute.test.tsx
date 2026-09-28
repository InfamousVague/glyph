import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useEffect, useState } from 'react';

/** The summary queue, which runs only in the app: what a meeting asked of it, and what an undo dropped. */
const summaries = vi.hoisted(() => ({ queued: [] as [string, string, { native?: boolean }][], dropped: [] as string[] }));
vi.mock('../ai/summaries.ts', () => ({
  enqueueSummary: (id: string, kind: string, options: { native?: boolean } = {}) => void summaries.queued.push([id, kind, options]),
  dropSummary: (id: string) => void summaries.dropped.push(id),
}));

import { setMeetingStateForTests } from '../capture/meetingLive.ts';
import { tapeId } from '../core/clips.ts';
import { createNote, getNote, listNotes, updateNote } from '../core/store.ts';
import { preferences, reloadPreferences, setPreferences } from '../core/preferences.ts';
import { autoTagRefusal, pendingTag, watchTag } from '../core/location.ts';
import { addWorkspace, chooseWorkspace, workspaceOf } from '../core/workspaces.ts';
import { show, waitUntil } from '../../test/render.tsx';
import { MEETING_FAILED, MICROPHONE_REFUSED, useCaptureRoute, type CaptureRoute } from './useCaptureRoute.ts';
import type { Screen } from './screen.ts';

/**
 * Where a capture comes back to, and how the side key reads the moment it is pressed in: every ending a person can
 * meet, from the note with its run on it to a locked phone that shows nothing of what was said.
 */

let route: CaptureRoute;
let screen: Screen;
const refresh = vi.fn(async () => undefined);
const flushDeletes = vi.fn(async () => undefined);
/** What the route said to the person: why a meeting did not start. */
const said: string[] = [];

/** A note's screen as far as its tag goes: it watches the tag once mounted (editor/NoteScreen.tsx), and hears what comes. */
const heardOnScreen: string[] = [];
function NoteWatch({ id }: { id: string }) {
  useEffect(() => watchTag(id, (event) => void heardOnScreen.push(`${id}:${event.kind}`)), [id]);
  return null;
}

function Probe({
  from,
  tooSoon = false,
  sayTooSoon = () => undefined,
  clearStage = () => undefined,
  atBoot = false,
  introduceLocation,
}: {
  from: Screen;
  tooSoon?: boolean;
  sayTooSoon?: () => void;
  clearStage?: () => void;
  atBoot?: boolean;
  introduceLocation?: (allow: () => void) => void;
}) {
  const [now, setNow] = useState<Screen>(from);
  screen = now;
  route = useCaptureRoute({ screen: now, setScreen: setNow, refresh, flushDeletes, atBoot, tooSoon: () => tooSoon, sayTooSoon, clearStage, say: (message) => void said.push(message), introduceLocation });
  return now.name === 'note' ? <NoteWatch id={now.note.id} /> : null;
}

/** The phone's service, as the activity's bridge hands it to the page. */
const service = { answer: 'started', state: null as Record<string, unknown> | null, started: [] as [string, string][], forgotten: [] as string[] };
function installService(): void {
  window.GlyphHost = {
    startMeeting: (id: string, title: string) => {
      service.started.push([id, title]);
      return service.answer;
    },
    meetingState: () => JSON.stringify(service.state ?? { recording: false, noteId: null }),
    forgetDiscarded: (id: string) => void service.forgotten.push(id),
    isLocked: () => false,
    endCapture: () => undefined,
  } as unknown as Window['GlyphHost'];
}
/** What the service says, as the activity pushes it. */
const push = (event: Record<string, unknown>) => act(() => window.__glyph!.meeting!(JSON.stringify(event)));

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  refresh.mockClear();
  flushDeletes.mockClear();
  said.length = 0;
  // The route's own answer is taken away; the meeting store's, registered as it loaded, stays.
  delete window.__glyph?.capture;
  service.answer = 'started';
  service.state = null;
  service.started = [];
  service.forgotten = [];
  summaries.queued = [];
  summaries.dropped = [];
  setMeetingStateForTests(null);
});

afterEach(() => {
  delete window.GlyphHost;
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

describe('a meeting on the phone', () => {
  it('makes the note, its tape, its place among the meetings and its native write-up, then asks the service and opens its screen', async () => {
    installService();
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    const notes = await listNotes();
    expect(notes).toHaveLength(1);
    const note = notes[0]!;
    expect(note.body).toMatch(/^# Meeting, .+ \d\d:\d\d\n$/);
    expect(note.source).toBe('capture');
    expect(tapeId(note.id)).not.toBeNull();
    expect(preferences().meetings[note.id]).toEqual(expect.any(Number));
    expect(summaries.queued).toEqual([[note.id, 'meeting', { native: true }]]);
    expect(service.started).toEqual([[note.id, note.body.slice(2).trim()]]);
    expect(screen).toMatchObject({ name: 'meeting', noteId: note.id, fromAssistant: false });
    // The list is read again, so the shelf has the note, recording, when Back leaves the meeting screen.
    expect(refresh).toHaveBeenCalled();
  });

  it('files the meeting where the list is looking, as any new note is', async () => {
    installService();
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    const [note] = await listNotes();
    expect(workspaceOf(note!.id)?.id).toBe(work.id);
  });

  it('takes its new note back without a word when the service answers that a meeting is already recording', async () => {
    installService();
    show(<Probe from={{ name: 'list' }} />);
    // The page's last read said none was (a poll a second old): the service knows better.
    service.answer = 'recording';
    await act(async () => route.meeting(false));
    expect(service.started).toHaveLength(1);
    await waitUntil(async () => expect(await listNotes()).toEqual([]));
    expect(preferences().meetings).toEqual({});
    expect(summaries.dropped).toHaveLength(1);
    expect(said).toEqual([]);
  });

  it('says the service’s line when the last meeting is still being put away, and keeps nothing', async () => {
    installService();
    service.answer = 'The last meeting is still stopping. Try again in a moment.';
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    expect(said).toEqual(['The last meeting is still stopping. Try again in a moment.']);
    expect(await listNotes()).toEqual([]);
    expect(preferences().meetings).toEqual({});
    expect(screen).toEqual({ name: 'list' });
  });

  it('queues no write-up with summaries off: the transcript still comes', async () => {
    installService();
    setPreferences({ summaries: 'off' });
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    expect(summaries.queued).toEqual([]);
    expect(screen).toMatchObject({ name: 'meeting' });
  });

  it('waits for the microphone when the service asks for it, and asks again once it is granted', async () => {
    installService();
    service.answer = 'permission';
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(true));
    expect(screen).toEqual({ name: 'list' });
    const [id, title] = service.started[0]!;
    service.answer = 'started';
    push({ event: 'permission', noteId: id, granted: true });
    await waitUntil(() => expect(service.started).toEqual([[id, title], [id, title]]));
    expect(screen).toMatchObject({ name: 'meeting', noteId: id, fromAssistant: true });
    expect(await getNote(id)).not.toBeNull();
  });

  it('takes the microphone\'s answer as the waiting meeting\'s when the push names no note', async () => {
    installService();
    service.answer = 'permission';
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    const [id, title] = service.started[0]!;
    service.answer = 'started';
    push({ event: 'permission', noteId: null, elapsedMs: 0, granted: true });
    await waitUntil(() => expect(service.started).toEqual([[id, title], [id, title]]));
    expect(screen).toMatchObject({ name: 'meeting', noteId: id });
  });

  it('opens the meeting screen on a tap of the recording notification that names no note', async () => {
    installService();
    show(<Probe from={{ name: 'list' }} />);
    service.state = { recording: true, noteId: 'live', title: 'Meeting, 26 Sep 14:05', startedAt: 0, elapsedMs: 9, silenced: false, writingUp: null, discarded: [] };
    push({ event: 'open', noteId: null, elapsedMs: 0 });
    expect(screen).toMatchObject({ name: 'meeting', noteId: 'live', fromAssistant: false });
  });

  it('takes everything back when the microphone is refused, and says so', async () => {
    installService();
    service.answer = 'permission';
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    const [id] = service.started[0]!;
    push({ event: 'permission', noteId: id, granted: false });
    await waitUntil(() => expect(said).toEqual([MICROPHONE_REFUSED]));
    expect(await getNote(id)).toBeNull();
    expect(preferences().meetings).toEqual({});
    expect(summaries.dropped).toEqual([id]);
    expect(screen).toEqual({ name: 'list' });
  });

  it('takes everything back and says why when the service could not start, or fails after saying it had', async () => {
    installService();
    service.answer = 'The microphone is in use.';
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    expect(said).toEqual(['The microphone is in use.']);
    expect(await listNotes()).toEqual([]);
    expect(screen).toEqual({ name: 'list' });
    // Started, then lost: the same undo, with the service's own line, or the app's when it has none.
    service.answer = 'started';
    await act(async () => route.meeting(false));
    const [id] = service.started[1]!;
    expect(screen).toMatchObject({ name: 'meeting', noteId: id });
    push({ event: 'failed', noteId: id, message: 'The recording could not be kept.' });
    await waitUntil(() => expect(said).toEqual(['The microphone is in use.', 'The recording could not be kept.']));
    expect(await getNote(id)).toBeNull();
    expect(screen).toEqual({ name: 'list' });
    await act(async () => route.meeting(false));
    const [again] = service.started[2]!;
    push({ event: 'failed', noteId: again });
    await waitUntil(() => expect(said.at(-1)).toBe(MEETING_FAILED));
    // A failure for a meeting this page did not start is not this page's to undo.
    await createNote('theirs', '# Meeting, 26 Sep 14:05\n', 'capture');
    push({ event: 'failed', noteId: 'theirs', message: 'Not ours.' });
    await act(async () => undefined);
    expect(await getNote('theirs')).not.toBeNull();
    expect(said).toHaveLength(3);
  });

  it('opens the meeting already being recorded rather than a second one: from Speak, from the side key, and at launch', async () => {
    installService();
    service.state = { recording: true, noteId: 'live', title: 'Meeting, 26 Sep 14:05', startedAt: 0, elapsedMs: 9, silenced: false, writingUp: null, discarded: [] };
    // At launch: the meeting screen, before anything is asked for.
    show(<Probe from={{ name: 'list' }} />);
    await waitUntil(() => expect(screen).toMatchObject({ name: 'meeting', noteId: 'live', fromAssistant: false }));
    // From Speak: no capture, since the microphone is taken.
    show(<Probe from={{ name: 'note', note: await createNote('n', '# Said') }} />);
    await act(async () => route.start(false, 'n'));
    expect(screen).toMatchObject({ name: 'meeting', noteId: 'live' });
    expect(flushDeletes).not.toHaveBeenCalled();
    // From the + sheet: the one being recorded, and no second note.
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.meeting(false));
    expect(service.started).toEqual([]);
    expect((await listNotes()).map((n) => n.id)).toEqual(['n']);
    // From the side key, while the app shows the list: the same screen, with the lock screen's leave in hand.
    service.state = null;
    setMeetingStateForTests(null);
    show(<Probe from={{ name: 'list' }} />);
    expect(screen).toEqual({ name: 'list' });
    service.state = { recording: true, noteId: 'live', title: 'Meeting, 26 Sep 14:05', startedAt: 0, elapsedMs: 9, silenced: false, writingUp: null, discarded: [] };
    await act(async () => window.__glyph!.capture!());
    expect(screen).toMatchObject({ name: 'meeting', noteId: 'live', fromAssistant: true });
  });

  it('leaves the meeting screen when the service says the meeting stopped or was discarded, and the side key does nothing on it', async () => {
    installService();
    show(<Probe from={{ name: 'meeting', noteId: 'live', fromAssistant: false, key: 1 }} />);
    await act(async () => window.__glyph!.capture!());
    expect(screen).toMatchObject({ name: 'meeting', noteId: 'live' });
    push({ event: 'stopped', noteId: 'other', elapsedMs: 5, reason: 'done' });
    expect(screen).toMatchObject({ name: 'meeting', noteId: 'live' });
    push({ event: 'stopped', noteId: 'live', elapsedMs: 5, reason: 'done' });
    expect(screen).toEqual({ name: 'list' });
    expect(refresh).toHaveBeenCalled();
    show(<Probe from={{ name: 'meeting', noteId: 'live', fromAssistant: false, key: 2 }} />);
    push({ event: 'discarded', noteId: 'live', elapsedMs: 5 });
    expect(screen).toEqual({ name: 'list' });
  });

  it('deletes a note the notification’s Discard threw away with the app closed, forgets it as a meeting, and tells the service', async () => {
    installService();
    await createNote('gone', '# Meeting, 26 Sep 14:05\n', 'capture');
    setPreferences({ meetings: { gone: 1 } });
    service.state = { recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: null, discarded: ['gone'] };
    show(<Probe from={{ name: 'list' }} />);
    await waitUntil(() => expect(service.forgotten).toEqual(['gone']));
    expect(await getNote('gone')).toBeNull();
    expect(preferences().meetings).toEqual({});
    expect(said).toEqual([]);
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

  it('tags the take’s own new note after the screen has changed, and not a note it only wrote into nor one a command made', async () => {
    const calls = fixAt(51.50741, -0.12776);
    const house = await createNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n');
    await createNote('made', '# Eggs\n');
    show(<Probe from={into()} />);
    const landing = { noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: ['made'] };
    await updateNote('house', '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', house.revision ?? 1);
    await act(async () => route.finished(house, false, undefined, undefined, landing));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'house' } });
    await settle();
    // Nothing of the take's own was new: the device is not asked.
    expect(calls).toHaveLength(0);
    expect((await getNote('made'))?.body).toBe('# Eggs\n');
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
    // A list a command made, opened on its card: the app's doing, so not tagged either.
    const list = await createNote('list', '# Groceries\n');
    await act(async () => route.finished(list, false, undefined, undefined, { noteId: 'list', title: 'Groceries', blocks: [], others: [], made: ['list'] }));
    await settle();
    expect(calls).toHaveLength(0);
    // A new note of the take's own: tagged once the list is showing.
    const said = await createNote('said', '# Said\n');
    await act(async () => route.finished(said, false));
    await settle();
    expect(calls).toHaveLength(1);
    expect((await getNote('said'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Said\n');
  });

  it('leaves a note spoken into from its own mic as it was: untagged, and filed where it was or nowhere', async () => {
    const calls = fixAt(51.5074, -0.1278);
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    const note = await createNote('n', '# Kept\n');
    show(<Probe from={into('n')} />);
    // The take went on its end (capture/CaptureScreen.tsx), and nothing a command made: no landing to say so.
    const grown = await updateNote('n', '# Kept\n\nMore words.\n', note.revision ?? 1);
    await act(async () => route.finished(grown, false));
    await settle();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'n' } });
    // docs/DESIGN.md §134: existing notes are never tagged.
    expect(calls).toHaveLength(0);
    expect(pendingTag('n')).toBeNull();
    expect(workspaceOf('n')).toBeNull();
    // Its review after the recording is no different.
    show(<Probe from={into('n')} />);
    await act(async () => route.finished(grown, false, { noteId: 'n', job: null, heard: 'more words', commands: [], touched: [] }));
    await settle();
    expect(calls).toHaveLength(0);
    expect(workspaceOf('n')).toBeNull();
  });

  it('asks where a journal’s entry was written once the recorder has gone, never at its start, and quietly over a lock', async () => {
    const { rememberEntry } = await import('../book/entryDrafts.ts');
    const words = '# Monday 28 September\n';
    const made = `---\ntitle: "2026-09-28 14.05"\n---\n${words}`;
    rememberEntry('entry', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
    await createNote('entry', made);
    const asked: { reviewing: boolean; locked: boolean; on: string }[] = [];
    const nothing = vi.fn(async (): Promise<Screen> => ({ name: 'list' }));
    // What was on screen as it was asked: never the recorder, whose microphone prompt shares the one listener.
    const aim = { id: 'entry', placing: { kind: 'end', lead: '**14:05** ' } as const, tag: (held: { reviewing: boolean }, locked: boolean) => void asked.push({ ...held, locked, on: screen.name }), nothing };
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.start(false, 'entry', aim));
    expect(screen).toMatchObject({ name: 'capture', noteId: 'entry', placing: { kind: 'end', lead: '**14:05** ' } });
    // Nothing asked at the start: the recorder's microphone prompt comes first.
    expect(asked).toEqual([]);
    const said = await updateNote('entry', `${made}\n**14:05** Walked.`, 1);
    await act(async () => route.finished(said, false));
    await settle();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'entry' } });
    expect(asked).toEqual([{ reviewing: false, locked: false, on: 'note' }]);
    expect(nothing).not.toHaveBeenCalled();
    // Over a locked phone: asked quietly, and home.
    await act(async () => route.start(false, 'entry', aim));
    const again = await updateNote('entry', `${said.body} Again.`, said.revision ?? 2);
    await act(async () => route.finished(again, true));
    await settle();
    expect(asked.at(-1)).toEqual({ reviewing: false, locked: true, on: 'list' });
    expect(screen).toEqual({ name: 'list' });
  });

  it('lands where a journal’s entry says when nothing was kept for it, and asks nothing', async () => {
    const { rememberEntry } = await import('../book/entryDrafts.ts');
    const words = '# Monday 28 September\n';
    const made = await createNote('entry', `---\ntitle: "2026-09-28 14.05"\n---\n${words}`);
    await createNote('diary', '---\nbook: true\njournal: true\n---\n');
    rememberEntry('entry', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
    const tag = vi.fn();
    const journal = (await getNote('diary'))!;
    const aim = { id: 'entry', placing: { kind: 'end', lead: '**14:05** ' } as const, tag, nothing: async (): Promise<Screen> => ({ name: 'note', note: journal }) };
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.start(false, 'entry', aim));
    await act(async () => route.finished(null, false));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'diary' } });
    // The take left the entry as it was made: nothing kept for it, and nothing asked.
    await act(async () => route.start(false, 'entry', aim));
    await act(async () => route.finished(made, false));
    await settle();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'diary' } });
    expect(tag).not.toHaveBeenCalled();
  });

  it('hands the tag to the note’s screen when it opens, rather than writing under its editor', async () => {
    fixAt(51.5074, -0.1278);
    const note = await createNote('n', '# Said\n');
    // The note's screen, as it watches its tag once mounted (editor/NoteScreen.tsx).
    const told: string[] = [];
    const off = watchTag('n', (event) => told.push(event.kind));
    // The take's own new note: a note spoken into from its own mic is not tagged at all (the test above).
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false));
    await settle();
    off();
    expect(told).toEqual(['pending']);
    expect((await getNote('n'))?.body).toBe('# Said\n');
    expect(pendingTag('n')).toEqual({ lat: 51.5074, lon: -0.1278, place: null, rough: false });
  });

  it('asks only once the note’s own screen is up, so the tag goes through it and never under its editor', async () => {
    heardOnScreen.length = 0;
    fixAt(40.7128, -74.006);
    const note = await createNote('fresh', '# Said\n');
    show(<Probe from={into()} />);
    // A take that opens its note (an instruction said into it, here; a review does too).
    await act(async () => route.finished(note, false, undefined, { kind: 'fix' }));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'fresh' } });
    await settle();
    // The screen mounted with the route change and was watching before the fix was asked for: it was handed the tag.
    expect(heardOnScreen).toEqual(['fresh:pending']);
    expect((await getNote('fresh'))?.body).toBe('# Said\n');
    expect(pendingTag('fresh')).toMatchObject({ lat: 40.7128, lon: -74.006 });
  });

  it('introduces the first ask on a device that never answered the prompt, and asks on the press', async () => {
    const calls = fixAt(40.7128, -74.006);
    const note = await createNote('first', '# Said\n');
    let allow: (() => void) | null = null;
    show(<Probe from={into()} introduceLocation={(press) => (allow = press)} />);
    await act(async () => route.finished(note, false));
    await settle();
    expect(allow).not.toBeNull();
    expect(calls).toHaveLength(0);
    await act(async () => allow!());
    await settle();
    expect(calls).toHaveLength(1);
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
