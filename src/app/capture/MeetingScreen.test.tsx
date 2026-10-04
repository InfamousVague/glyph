import { afterEach, beforeEach, describe, expect, it, onTestFinished, vi } from 'vitest';
import { act } from 'react';
import { createNote, getNote } from '../core/store.ts';
import { installBack } from '../core/back.ts';
import { preferences, reloadPreferences, setPreferences } from '../core/preferences.ts';
import { button, buttonSaying, show, unmount } from '../../test/render.tsx';
import { stubMatchMedia, stubResizeObserver } from '../../test/stubs.ts';

/**
 * The meeting screen (capture/MeetingScreen.tsx): the cassette turning and the counter, the lines it says, and its
 * two words to the service. Done stops the recording and leaves; Discard stops it, deletes the note and its place in
 * the preferences, and leaves; Back only leaves, with the recording going on. The service is a stand-in on the
 * window, as the activity puts it there.
 */

// The kit asks the window's resolution as it loads; the tape's reels watch their box.
stubMatchMedia();
stubResizeObserver();

const summaries = vi.hoisted(() => ({ dropped: [] as string[] }));
vi.mock('../ai/summaries.ts', () => ({ dropSummary: (id: string) => void summaries.dropped.push(id) }));

const { MeetingScreen } = await import('./MeetingScreen.tsx');
const { readMeetingState, setMeetingStateForTests } = await import('./meetingLive.ts');

/** The service, as the activity's bridge hands it to the page. */
const service = vi.hoisted(() => ({
  state: { recording: true, noteId: 'm1', title: 'Meeting, 26 Sep 14:05', startedAt: 0, elapsedMs: 754_000, silenced: false, writingUp: null, discarded: [] as string[] },
  stopped: 0,
  discarded: 0,
  locked: false,
  ended: [] as boolean[],
  canNotify: false,
  asked: 0,
  answer: 'asked' as 'allowed' | 'asked' | 'blocked',
}));

function install(): void {
  window.GlyphHost = {
    meetingState: () => JSON.stringify(service.state),
    stopMeeting: () => {
      service.stopped += 1;
    },
    discardMeeting: () => {
      service.discarded += 1;
    },
    isLocked: () => service.locked,
    endCapture: (leave: boolean) => void service.ended.push(leave),
    canNotify: () => service.canNotify,
    requestNotifications: () => {
      service.asked += 1;
      return service.answer;
    },
  } as unknown as Window['GlyphHost'];
}

let uninstallBack: () => void = () => undefined;

beforeEach(async () => {
  localStorage.clear();
  reloadPreferences();
  // Twelve and a half minutes in: the counter runs from when the service says the meeting began.
  service.state = { ...service.state, recording: true, noteId: 'm1', silenced: false, startedAt: Date.now() - 754_000, elapsedMs: 754_000 };
  service.stopped = 0;
  service.discarded = 0;
  service.locked = false;
  service.ended = [];
  service.canNotify = false;
  service.asked = 0;
  service.answer = 'asked';
  summaries.dropped = [];
  install();
  setMeetingStateForTests(null);
  readMeetingState();
  await createNote('m1', '# Meeting, 26 Sep 14:05\n', 'capture');
  setPreferences({ meetings: { m1: 0 } });
  uninstallBack = installBack();
});

afterEach(() => {
  unmount();
  uninstallBack();
  delete window.GlyphHost;
});

const screen = (over: { fromAssistant?: boolean; onLeave?: () => void } = {}) => show(<MeetingScreen noteId="m1" fromAssistant={over.fromAssistant ?? false} onLeave={over.onLeave ?? (() => undefined)} />);

describe('the meeting screen', () => {
  it('lets the screen go off: none of the recorder’s keep-awake, screen-off or refine holds', async () => {
    const setCapturing = vi.fn();
    window.GlyphHost = { ...window.GlyphHost, setCapturing } as unknown as Window['GlyphHost'];
    const refine = await import('./refine.ts');
    const live = vi.spyOn(refine, 'setRecorderLive');
    const before = window.__glyph?.screenOff;
    screen();
    await act(async () => undefined);
    // FLAG_KEEP_SCREEN_ON and the SCREEN_OFF receiver are the dictation's; the screen going off is this one's point.
    expect(setCapturing).not.toHaveBeenCalled();
    expect(window.__glyph?.screenOff).toBe(before);
    expect(live).not.toHaveBeenCalled();
    live.mockRestore();
  });

  it('shows the cassette turning, the counter and the line that says the screen can go off', () => {
    const host = screen();
    expect(host.textContent).toContain('Meeting');
    expect(host.textContent).toContain('12:34');
    expect(host.textContent).toContain('Recording. The screen can go off and you can leave. Stop here or from the notification.');
    expect(host.querySelector('[data-recording]')).not.toBeNull();
    // Nothing of the note: the side key can open this over the lock screen.
    expect(host.textContent).not.toContain('26 Sep');
  });

  it('says when another app has muted the microphone', () => {
    expect(screen().textContent).not.toContain('Muted by another app.');
    unmount();
    service.state = { ...service.state, silenced: true };
    readMeetingState();
    expect(screen().textContent).toContain('Muted by another app.');
  });

  it('says when other apps\u2019 sound is in the meeting, that calls are not, and when it is the microphone alone', () => {
    // A binary before generation 25 says nothing of it, and nothing is drawn.
    const before = service.state;
    onTestFinished(() => {
      service.state = before;
    });
    expect(screen().textContent).not.toContain('other apps');
    unmount();
    service.state = { ...service.state, otherApps: true, otherAppsHeard: false, otherAppsNote: null } as typeof service.state;
    readMeetingState();
    expect(screen().textContent).toContain('Listening for sound from other apps too. Media and games, never calls.');
    unmount();
    service.state = { ...service.state, otherAppsHeard: true } as typeof service.state;
    readMeetingState();
    expect(screen().textContent).toContain('Recording sound from other apps too. Media and games, never calls.');
    unmount();
    const declined = 'Sharing was not allowed, so only the microphone is recording.';
    service.state = { ...service.state, otherApps: false, otherAppsHeard: false, otherAppsNote: declined } as typeof service.state;
    readMeetingState();
    expect(screen().textContent).toContain(declined);
  });

  it('on Done asks the service to stop and carry on as the write-up, and leaves', () => {
    const onLeave = vi.fn();
    const host = screen({ onLeave });
    act(() => button('Stop and write up', host).click());
    expect(service.stopped).toBe(1);
    expect(service.discarded).toBe(0);
    expect(onLeave).toHaveBeenCalledTimes(1);
    // Not opened by the side key: nothing is said to the activity about the lock screen.
    expect(service.ended).toEqual([]);
  });

  it('on Discard asks the service to throw the recording away, deletes the note itself, forgets it as a meeting, drops its write-up and leaves', async () => {
    const onLeave = vi.fn();
    const host = screen({ onLeave });
    await act(async () => button('Discard', host).click());
    expect(service.discarded).toBe(1);
    expect(service.stopped).toBe(0);
    expect(await getNote('m1')).toBeNull();
    expect(preferences().meetings).toEqual({});
    expect(summaries.dropped).toEqual(['m1']);
    expect(onLeave).toHaveBeenCalledTimes(1);
  });

  it('on Back only leaves: the recording goes on, stoppable here again or from the notification', () => {
    const onLeave = vi.fn();
    screen({ onLeave });
    act(() => void window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(onLeave).toHaveBeenCalledTimes(1);
    expect(service.stopped).toBe(0);
    expect(service.discarded).toBe(0);
  });

  it('opened by the side key, hands a locked phone back to its lock screen as it leaves, however it leaves', () => {
    service.locked = true;
    const onLeave = vi.fn();
    const host = screen({ fromAssistant: true, onLeave });
    act(() => button('Stop and write up', host).click());
    expect(service.ended).toEqual([true]);
    expect(onLeave).toHaveBeenCalledTimes(1);
  });

  it('offers to be told when the meeting is written up, once, and says so only once the phone has answered no', () => {
    let host = screen();
    expect(host.textContent).toContain('Let Ghost.md tell you when it is written up.');
    act(() => button('Allow', host).click());
    expect(service.asked).toBe(1);
    // Asked: the offer goes, and nothing is said until the phone answers.
    expect(host.textContent).not.toContain('Let Ghost.md tell you');
    expect(host.textContent).not.toContain('Notifications are off');
    // Answered no: the notification's Stop is not coming, and the screen says where to stop.
    act(() => window.__glyph!.notified!());
    expect(host.textContent).toContain('Notifications are off for Ghost.md, so stop it here.');
    unmount();
    // Remembered on this device: the next meeting is not asked again, and a no that stands is said at once.
    host = screen();
    expect(host.textContent).not.toContain('Let Ghost.md tell you');
    expect(host.textContent).toContain('Notifications are off for Ghost.md, so stop it here.');
    unmount();
    // Allowed since, in the phone's settings: nothing to say.
    service.canNotify = true;
    host = screen();
    expect(host.textContent).not.toContain('Let Ghost.md tell you');
    expect(host.textContent).not.toContain('Notifications are off');
  });

  it('says yes at once when the phone answers yes', () => {
    const host = screen();
    act(() => button('Allow', host).click());
    service.canNotify = true;
    act(() => window.__glyph!.notified!());
    expect(host.textContent).not.toContain('Notifications are off');
    expect(host.textContent).not.toContain('Let Ghost.md tell you');
  });

  it('says the notification’s Stop is not coming when the phone blocks the prompt outright', () => {
    localStorage.clear();
    service.answer = 'blocked';
    const host = screen();
    act(() => button('Allow', host).click());
    expect(host.textContent).toContain('Notifications are off for Ghost.md, so stop it here.');
    expect(buttonSaying(host, 'Allow')).toBeUndefined();
  });
});
