import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import type { MeetingEvent, MeetingEventName } from './meetingLive.ts';

/**
 * The one store of the meeting being recorded (capture/meetingLive.ts): what the service's JSON becomes, what a push
 * from it does to the state and to whoever asked to hear it, and the poll that runs once a second while the page is
 * visible and someone is listening, and only on a binary with a service to ask.
 */

const jobs = vi.hoisted(() => ({ running: false }));
vi.mock('../core/recordings.ts', () => ({ writeUpRunningNow: () => jobs.running }));

const { canNotifyNow, meetingStateNow, onMeetingEvent, parseMeetingEvent, parseMeetingState, readMeetingState, setMeetingStateForTests, useMeetingState, writeUpRunning } = await import('./meetingLive.ts');

const RECORDING = { recording: true, noteId: 'm1', title: 'Meeting, 26 Sep 14:05', startedAt: 1_000, elapsedMs: 5_000, silenced: false, writingUp: null, discarded: [] };

/** A host with the service, answering `state` and `canNotify`; `asked` counts the reads. */
function host(state: unknown, canNotify = true): { asked: number } {
  const counts = { asked: 0 };
  window.GlyphHost = {
    meetingState: () => {
      counts.asked += 1;
      return JSON.stringify(state);
    },
    canNotify: () => canNotify,
  } as unknown as Window['GlyphHost'];
  return counts;
}

const visible = (state: 'visible' | 'hidden') => Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state });

let seen: ReturnType<typeof useMeetingState> = null;
function Probe() {
  seen = useMeetingState();
  return null;
}

beforeEach(() => {
  setMeetingStateForTests(null);
  jobs.running = false;
  visible('visible');
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
  delete window.GlyphHost;
});

describe('what the service says', () => {
  it('is read as a state, whole, and anything else is nothing', () => {
    expect(parseMeetingState(RECORDING)).toEqual(RECORDING);
    // The fields a build may lack are answered with their quiet values; one without `recording` is not a state.
    expect(parseMeetingState({ recording: false })).toEqual({ recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: null, discarded: [] });
    expect(parseMeetingState({ recording: true, noteId: 'm', discarded: ['a', 3, 'b'] })).toMatchObject({ discarded: ['a', 'b'] });
    expect(parseMeetingState('recording')).toBeNull();
    expect(parseMeetingState({ noteId: 'm' })).toBeNull();
    expect(parseMeetingState(null)).toBeNull();
  });

  it('is read as an event, with the extras each kind carries, and not without its name or, but for two, its note', () => {
    expect(parseMeetingEvent(JSON.stringify({ event: 'stopped', noteId: 'm1', elapsedMs: 9, reason: 'cap' }))).toEqual({ event: 'stopped', noteId: 'm1', elapsedMs: 9, reason: 'cap' });
    expect(parseMeetingEvent(JSON.stringify({ event: 'permission', noteId: 'm1', granted: false }))).toEqual({ event: 'permission', noteId: 'm1', elapsedMs: 0, granted: false });
    expect(parseMeetingEvent(JSON.stringify({ event: 'failed', noteId: 'm1', message: 'The meeting could not start.' }))).toEqual({ event: 'failed', noteId: 'm1', elapsedMs: 0, message: 'The meeting could not start.' });
    expect(parseMeetingEvent(JSON.stringify({ event: 'started' }))).toBeNull();
    // The activity says these two with no note in hand: the microphone's answer and a tap on the notification.
    expect(parseMeetingEvent(JSON.stringify({ event: 'permission', noteId: null, elapsedMs: 0, granted: true }))).toEqual({ event: 'permission', noteId: null, elapsedMs: 0, granted: true });
    expect(parseMeetingEvent(JSON.stringify({ event: 'open', noteId: null, elapsedMs: 0 }))).toEqual({ event: 'open', noteId: null, elapsedMs: 0 });
    expect(parseMeetingEvent(JSON.stringify({ event: 'discarded', noteId: null }))).toBeNull();
    expect(parseMeetingEvent(JSON.stringify({ noteId: 'm1' }))).toBeNull();
    expect(parseMeetingEvent('not json')).toBeNull();
  });
});

describe('the state', () => {
  it('is null where there is no service to ask, and the service’s answer where there is', () => {
    expect(meetingStateNow()).toBeNull();
    expect(readMeetingState()).toBeNull();
    host(RECORDING);
    expect(readMeetingState()).toEqual(RECORDING);
    expect(meetingStateNow()).toEqual(RECORDING);
  });

  it('keeps the same object while the service says the same thing, so a read a second does not wake every listener', () => {
    host(RECORDING);
    const first = readMeetingState();
    expect(readMeetingState()).toBe(first);
    host({ ...RECORDING, elapsedMs: 6_000 });
    expect(readMeetingState()).not.toBe(first);
    expect(readMeetingState()?.elapsedMs).toBe(6_000);
  });

  it('is nothing recording, not null, when the service answers something this build cannot read', () => {
    host({ something: 'else' });
    expect(readMeetingState()).toMatchObject({ recording: false, noteId: null });
  });
});

describe('a push from the service', () => {
  it('moves the state before the service is asked again, and reaches everyone who asked to hear it', () => {
    const heard: string[] = [];
    const off = onMeetingEvent((event) => heard.push(event.event));
    // No service on this host: the push alone is what the page knows.
    window.__glyph!.meeting!(JSON.stringify({ event: 'started', noteId: 'm1', elapsedMs: 0 }));
    expect(meetingStateNow()).toMatchObject({ recording: true, noteId: 'm1', silenced: false });
    window.__glyph!.meeting!(JSON.stringify({ event: 'silenced', noteId: 'm1', elapsedMs: 100 }));
    expect(meetingStateNow()).toMatchObject({ recording: true, silenced: true, elapsedMs: 100 });
    window.__glyph!.meeting!(JSON.stringify({ event: 'sounding', noteId: 'm1', elapsedMs: 200 }));
    expect(meetingStateNow()).toMatchObject({ recording: true, silenced: false });
    window.__glyph!.meeting!(JSON.stringify({ event: 'stopped', noteId: 'm1', elapsedMs: 300, reason: 'done' }));
    expect(meetingStateNow()).toMatchObject({ recording: false, noteId: null, writingUp: 'm1' });
    window.__glyph!.meeting!(JSON.stringify({ event: 'started', noteId: 'm2', elapsedMs: 0 }));
    window.__glyph!.meeting!(JSON.stringify({ event: 'discarded', noteId: 'm2', elapsedMs: 50 }));
    expect(meetingStateNow()).toMatchObject({ recording: false, discarded: ['m2'] });
    window.__glyph!.meeting!(JSON.stringify({ event: 'started', noteId: 'm3', elapsedMs: 0 }));
    window.__glyph!.meeting!(JSON.stringify({ event: 'failed', noteId: 'm3', message: 'The meeting could not start.' }));
    expect(meetingStateNow()).toMatchObject({ recording: false, noteId: null });
    expect(heard).toEqual(['started', 'silenced', 'sounding', 'stopped', 'started', 'discarded', 'started', 'failed']);
    off();
    window.__glyph!.meeting!(JSON.stringify({ event: 'open', noteId: 'm1', elapsedMs: 0 }));
    expect(heard).toHaveLength(8);
    // A push this build cannot read is dropped whole.
    expect(() => window.__glyph!.meeting!('{')).not.toThrow();
  });

  it('asks the service again after a push, where there is one, so the state is the service’s and not the guess', () => {
    host({ ...RECORDING, elapsedMs: 42 });
    window.__glyph!.meeting!(JSON.stringify({ event: 'started', noteId: 'm1', elapsedMs: 0 }));
    expect(meetingStateNow()).toMatchObject({ recording: true, elapsedMs: 42, title: 'Meeting, 26 Sep 14:05' });
  });
});

describe('whether the phone may notify', () => {
  it('is read from the host, kept, and read again when the prompt is answered', () => {
    expect(canNotifyNow()).toBe(false);
    host(RECORDING, true);
    expect(canNotifyNow()).toBe(true);
    host(RECORDING, false);
    window.__glyph!.notified!();
    expect(canNotifyNow()).toBe(false);
  });
});

describe('the poll', () => {
  it('asks the service once a second while someone listens and the page is visible, and stops when the last listener goes', () => {
    vi.useFakeTimers();
    const counts = host(RECORDING);
    show(<Probe />);
    expect(counts.asked).toBe(1);
    expect(seen).toEqual(RECORDING);
    vi.advanceTimersByTime(3_000);
    expect(counts.asked).toBe(4);
    // Hidden, the poll waits; visible again, it reads at once.
    visible('hidden');
    vi.advanceTimersByTime(2_000);
    expect(counts.asked).toBe(4);
    visible('visible');
    document.dispatchEvent(new Event('visibilitychange'));
    expect(counts.asked).toBe(5);
    unmount();
    vi.advanceTimersByTime(3_000);
    expect(counts.asked).toBe(5);
  });

  it('asks again when the activity’s refresh reaches the page, as the notes store echoes it', async () => {
    const counts = host(RECORDING);
    const { announceNotesChanged } = await import('../core/store.ts');
    expect(counts.asked).toBe(0);
    announceNotesChanged();
    expect(counts.asked).toBe(1);
  });

  it('asks nothing of a host without the service', () => {
    vi.useFakeTimers();
    window.GlyphHost = { isLocked: () => false } as unknown as Window['GlyphHost'];
    show(<Probe />);
    vi.advanceTimersByTime(3_000);
    expect(seen).toBeNull();
  });
});

describe('whether a write-up is running', () => {
  it('is so by the last look at the jobs, or by the service saying which note it is writing up', () => {
    expect(writeUpRunning()).toBe(false);
    jobs.running = true;
    expect(writeUpRunning()).toBe(true);
    jobs.running = false;
    setMeetingStateForTests({ ...RECORDING, recording: false, writingUp: 'm1' });
    expect(writeUpRunning()).toBe(true);
  });
});

/*
 * The two sides of the bridge are typed twice, once in Kotlin and once here, and a key misspelt in either is read as
 * nothing without a word. So what the service and the activity build is read out of their sources and held to what
 * this store parses (the Rust side does the same for the write-up's options and answers, write_up.rs).
 */
describe('what the Kotlin says, and what the page reads', () => {
  const android = join(process.cwd(), 'src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph');
  const service = readFileSync(join(android, 'capture/MeetingService.kt'), 'utf8');
  const activity = readFileSync(join(android, 'MainActivity.kt'), 'utf8');
  /** Every `.put("key"` in `text`. */
  const keys = (text: string) => new Set([...text.matchAll(/\.put\("([A-Za-z]+)"/g)].map((match) => match[1]!));
  /** The body of `fun <name>(` up to the next `fun ` at the same indent or deeper, roughly: enough for its puts. */
  const body = (text: string, name: string) => {
    const from = text.indexOf(`fun ${name}(`);
    expect(from, `fun ${name}`).toBeGreaterThan(-1);
    const next = text.indexOf('\n  fun ', from + 1);
    const nextPrivate = text.indexOf('\n  private fun ', from + 1);
    const ends = [next, nextPrivate, text.indexOf('\n    fun ', from + 1), text.indexOf('\n    private fun ', from + 1)].filter((at) => at > from);
    return text.slice(from, ends.length ? Math.min(...ends) : undefined);
  };

  it('has every key of the state the service answers, and no other', () => {
    const answered = keys(body(service, 'meetingState'));
    expect([...answered].sort()).toEqual(Object.keys(parseMeetingState({ recording: false })!).sort());
  });

  it('knows every event the service and the activity push, and every key they carry', () => {
    const known: MeetingEventName[] = ['started', 'silenced', 'sounding', 'stopped', 'discarded', 'failed', 'permission', 'asked', 'open'];
    const pushed = new Set([
      ...[...service.matchAll(/push\("([a-z]+)"/g)].map((match) => match[1]!),
      ...[...service.matchAll(/if \(now\) "([a-z]+)" else "([a-z]+)"/g)].flatMap((match) => [match[1]!, match[2]!]),
      ...[...`${service}${activity}`.matchAll(/\.put\("event", "([a-z]+)"\)/g)].map((match) => match[1]!),
    ]);
    expect(pushed.size).toBeGreaterThanOrEqual(8);
    for (const name of pushed) expect(known, `the page does not know "${name}"`).toContain(name);
    const carried = new Set([
      ...keys(body(service, 'push')),
      ...keys(body(service, 'pushStopped')),
      ...keys(body(service, 'pushFailed')),
      ...keys(body(service, 'offerDied')),
      ...[...activity.matchAll(/tell\("meeting", ([^\n]+)/g)].flatMap((match) => [...keys(match[1]!)]),
      ...keys(body(activity, 'deliverMeeting')),
    ]);
    const read: (keyof MeetingEvent)[] = ['event', 'noteId', 'elapsedMs', 'reason', 'granted', 'message'];
    expect([...carried].sort()).toEqual([...read].sort());
  });

  it('stops a meeting only for the reasons the page names', () => {
    const reasons = new Set([...service.matchAll(/requestStop\("([a-z]+)"\)/g)].map((match) => match[1]!));
    reasons.add('died');
    const named: NonNullable<MeetingEvent['reason']>[] = ['done', 'notification', 'cap', 'error', 'died'];
    for (const reason of reasons) expect(named).toContain(reason);
  });
});
