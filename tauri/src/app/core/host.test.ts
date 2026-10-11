import { afterEach, describe, expect, it } from 'vitest';
import {
  answerHost,
  cancelWriteUpOnHost,
  cancelWriteUpsOnHost,
  canNotify,
  discardMeetingOnHost,
  endCapture,
  forgetDiscardedOnHost,
  isLocked,
  meetingStateJson,
  NO_MEETING_SERVICE,
  requestNotifications,
  setCapturing,
  startMeetingOnHost,
  meetingSoundOnHost,
  stopMeetingOnHost,
  takeCaptureLaunch,
  takeHostLink,
  writeUpOnHost,
} from './host.ts';

/*
 * The page's line to the Android activity (host.ts). `window.__glyph` is one object every module answers on, and
 * the reason the file exists is that one answer must never wipe another: a side key that does nothing while the app
 * is open is the failure, and no desktop test would otherwise see it.
 */

afterEach(() => {
  delete window.__glyph;
  delete window.GlyphHost;
  delete window.__glyphLaunch;
  window.history.replaceState(null, '', '/');
});

describe('what the activity calls on the page', () => {
  it('reaches every module that answers, each under its own name', () => {
    const heard: string[] = [];
    const offRefresh = answerHost('refresh', () => heard.push('refresh'));
    const offCapture = answerHost('capture', () => heard.push('capture'));
    window.__glyph?.refresh?.();
    window.__glyph?.capture?.();
    expect(heard).toEqual(['refresh', 'capture']);
    offRefresh();
    offCapture();
  });

  it('takes one answer away without touching the others', () => {
    const offRefresh = answerHost('refresh', () => undefined);
    const capture = () => undefined;
    answerHost('capture', capture);
    offRefresh();
    expect(window.__glyph?.refresh).toBeUndefined();
    expect(window.__glyph?.capture).toBe(capture);
  });

  it('leaves a newer answer in place when an older one is taken away', () => {
    const offFirst = answerHost('refresh', () => undefined);
    const second = () => undefined;
    answerHost('refresh', second);
    offFirst();
    expect(window.__glyph?.refresh).toBe(second);
  });
});

describe('what the page asks the activity', () => {
  it('reads a side-key launch once from the host and keeps it for a second mount in the same page', () => {
    let reads = 0;
    window.GlyphHost = {
      takeLaunch: () => {
        reads += 1;
        return reads === 1 ? 'capture' : '';
      },
    } as unknown as Window['GlyphHost'];
    expect(takeCaptureLaunch()).toBe(true);
    expect(takeCaptureLaunch()).toBe(true);
    expect(reads).toBe(1);
  });

  it('stands a ?capture address in for the side key in a browser', () => {
    expect(takeCaptureLaunch()).toBe(false);
    window.history.replaceState(null, '', '/?capture');
    expect(takeCaptureLaunch()).toBe(true);
  });

  it('answers safely with no host, or a host from before a method existed', () => {
    expect(isLocked()).toBe(false);
    expect(() => endCapture(true)).not.toThrow();
    expect(setCapturing(true)).toBe(false);
    window.GlyphHost = {
      isLocked: () => {
        throw new Error('old build');
      },
      endCapture: () => {
        throw new Error('old build');
      },
    } as unknown as Window['GlyphHost'];
    expect(isLocked()).toBe(false);
    expect(() => endCapture(false)).not.toThrow();
    expect(setCapturing(true)).toBe(false);
  });

  it('tells a host that can keep the screen on that a recording started, and says it can', () => {
    const told: boolean[] = [];
    let left: boolean | null = null;
    window.GlyphHost = {
      isLocked: () => true,
      endCapture: (leave: boolean) => {
        left = leave;
      },
      setCapturing: (on: boolean) => told.push(on),
    } as unknown as Window['GlyphHost'];
    expect(isLocked()).toBe(true);
    expect(setCapturing(true)).toBe(true);
    expect(setCapturing(false)).toBe(true);
    expect(told).toEqual([true, false]);
    endCapture(true);
    expect(left).toBe(true);
  });
});

describe('what the page asks the activity about meetings', () => {
  it('answers safely with no host, or a host from before the service existed, or one that throws', () => {
    const quiet = () => {
      expect(startMeetingOnHost('m1', 'Meeting, 26 Sep 14:05')).toBe(NO_MEETING_SERVICE);
      expect(() => stopMeetingOnHost()).not.toThrow();
      expect(() => discardMeetingOnHost()).not.toThrow();
      expect(meetingStateJson()).toBeNull();
      expect(requestNotifications()).toBe('blocked');
      expect(canNotify()).toBe(false);
      expect(writeUpOnHost('m1', true)).toBe(false);
      expect(() => cancelWriteUpOnHost('m1')).not.toThrow();
      expect(() => cancelWriteUpsOnHost()).not.toThrow();
      expect(() => forgetDiscardedOnHost('m1')).not.toThrow();
      expect(takeHostLink()).toBe('');
    };
    quiet();
    window.GlyphHost = { isLocked: () => false } as unknown as Window['GlyphHost'];
    quiet();
    const old = () => {
      throw new Error('old build');
    };
    window.GlyphHost = {
      startMeeting: old,
      stopMeeting: old,
      discardMeeting: old,
      meetingState: old,
      requestNotifications: old,
      canNotify: old,
      writeUp: old,
      cancelWriteUp: old,
      cancelWriteUps: old,
      forgetDiscarded: old,
      takeLink: old,
    } as unknown as Window['GlyphHost'];
    quiet();
  });

  it('reaches a host that has the service, and reads its answers as the page’s own words', () => {
    const calls: unknown[][] = [];
    const record =
      (name: string, answer?: unknown) =>
      (...args: unknown[]) => {
        calls.push([name, ...args]);
        return answer;
      };
    window.GlyphHost = {
      startMeeting: record('startMeeting', 'started'),
      stopMeeting: record('stopMeeting'),
      discardMeeting: record('discardMeeting'),
      meetingState: record('meetingState', '{"recording":false}'),
      requestNotifications: record('requestNotifications', 'asked'),
      canNotify: record('canNotify', true),
      writeUp: record('writeUp', 'queued'),
      cancelWriteUp: record('cancelWriteUp'),
      cancelWriteUps: record('cancelWriteUps'),
      forgetDiscarded: record('forgetDiscarded'),
      takeLink: record('takeLink', 'ghostmd://note/m1'),
    } as unknown as Window['GlyphHost'];
    expect(startMeetingOnHost('m1', 'Meeting, 26 Sep 14:05')).toBe('started');
    stopMeetingOnHost();
    discardMeetingOnHost();
    expect(meetingStateJson()).toBe('{"recording":false}');
    expect(requestNotifications()).toBe('asked');
    expect(canNotify()).toBe(true);
    expect(writeUpOnHost('m1', false)).toBe(true);
    cancelWriteUpOnHost('m1');
    cancelWriteUpsOnHost();
    forgetDiscardedOnHost('m1');
    expect(takeHostLink()).toBe('ghostmd://note/m1');
    expect(calls).toEqual([
      ['startMeeting', 'm1', 'Meeting, 26 Sep 14:05'],
      ['stopMeeting'],
      ['discardMeeting'],
      ['meetingState'],
      ['requestNotifications'],
      ['canNotify'],
      ['writeUp', 'm1', false],
      ['cancelWriteUp', 'm1'],
      ['cancelWriteUps'],
      ['forgetDiscarded', 'm1'],
      ['takeLink'],
    ]);
    // An answer this build does not know is read as the safe one.
    window.GlyphHost = { requestNotifications: () => 'maybe', writeUp: () => 'busy' } as unknown as Window['GlyphHost'];
    expect(requestNotifications()).toBe('blocked');
    expect(writeUpOnHost('m1', true)).toBe(false);
  });

  it('asks for other apps\u2019 sound only of a binary that has it, and reads its answer whole or not at all', () => {
    const calls: unknown[][] = [];
    window.GlyphHost = {
      startMeeting: (...args: unknown[]) => (calls.push(['startMeeting', ...args]), 'started'),
    } as unknown as Window['GlyphHost'];
    // A binary before generation 25: the switch on still records the microphone, as that binary always has.
    expect(startMeetingOnHost('m1', 'Meeting', true)).toBe('started');
    expect(meetingSoundOnHost()).toBeNull();
    window.GlyphHost = {
      startMeeting: (...args: unknown[]) => (calls.push(['startMeeting', ...args]), 'started'),
      startMeetingWith: (...args: unknown[]) => (calls.push(['startMeetingWith', ...args]), 'started'),
      meetingSound: () => '{"supported":false,"reason":"Android 10 or later can record the sound of other apps."}',
    } as unknown as Window['GlyphHost'];
    expect(startMeetingOnHost('m2', 'Meeting', true)).toBe('started');
    expect(startMeetingOnHost('m3', 'Meeting')).toBe('started');
    expect(calls).toEqual([
      ['startMeeting', 'm1', 'Meeting'],
      ['startMeetingWith', 'm2', 'Meeting', true],
      ['startMeeting', 'm3', 'Meeting'],
    ]);
    expect(meetingSoundOnHost()).toEqual({ supported: false, reason: 'Android 10 or later can record the sound of other apps.' });
    window.GlyphHost = { meetingSound: () => '{"supported":"yes"}' } as unknown as Window['GlyphHost'];
    expect(meetingSoundOnHost()).toBeNull();
  });
});
