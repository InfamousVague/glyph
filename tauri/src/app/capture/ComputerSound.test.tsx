import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, show, unmount, waitUntil } from '../../test/render.tsx';

/**
 * The Mac's own sound in the meeting recorder (capture/ComputerSound.tsx): the tap opened only once the capture runs
 * and the switch is on, closed when either goes, and the one line when nothing comes through it.
 */

const tap = vi.hoisted(() => ({
  support: { supported: true, reason: null } as { supported: boolean; reason: string | null } | null,
  started: 0,
  stopped: 0,
  start: { capturing: true, reason: null } as { capturing: boolean; reason: string | null },
  heard: false,
}));
vi.mock('./systemSound.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./systemSound.ts')>()),
  useMeetingSoundSupport: () => tap.support,
  startComputerSound: async () => {
    tap.started += 1;
    return tap.start;
  },
  stopComputerSound: async () => {
    tap.stopped += 1;
  },
  computerSoundStatus: async () => ({ capturing: tap.start.capturing, heard: tap.heard }),
}));

const { ComputerSound } = await import('./ComputerSound.tsx');
const { preferences, setPreferences } = await import('../core/preferences.ts');
const { NOTHING_FROM_THE_MAC } = await import('./systemSound.ts');

beforeEach(() => {
  tap.support = { supported: true, reason: null };
  tap.started = 0;
  tap.stopped = 0;
  tap.start = { capturing: true, reason: null };
  tap.heard = false;
  setPreferences({ meetingSound: false });
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
});

describe("the Mac's sound in a meeting", () => {
  it('draws nothing on a Mac that cannot', () => {
    tap.support = { supported: false, reason: 'Recording the computer’s sound needs macOS 14.2 or later.' };
    const host = show(<ComputerSound live onSay={() => undefined} />);
    expect(host.textContent).toBe('');
  });

  it('opens the tap only once the capture runs with the switch on, and closes it when the switch goes off', async () => {
    const host = show(<ComputerSound live={false} onSay={() => undefined} />);
    expect(host.textContent).toContain("This Mac's sound: off");
    act(() => buttonSaying(host, "This Mac's sound: off")!.click());
    expect(preferences().meetingSound).toBe(true);
    expect(tap.started).toBe(0);
    unmount();
    const live = show(<ComputerSound live onSay={() => undefined} />);
    await waitUntil(() => expect(live.textContent).toContain("With this Mac's sound"));
    expect(tap.started).toBe(1);
    act(() => buttonSaying(live, "With this Mac's sound")!.click());
    expect(preferences().meetingSound).toBe(false);
    await waitUntil(() => expect(tap.stopped).toBe(1));
  });

  it('says why when the tap would not open, and where the switch is when nothing comes through', async () => {
    setPreferences({ meetingSound: true });
    tap.start = { capturing: false, reason: 'The computer’s sound could not be opened.' };
    const said: string[] = [];
    show(<ComputerSound live onSay={(text) => said.push(text)} />);
    await waitUntil(() => expect(said).toEqual(['The computer’s sound could not be opened.']));
    unmount();
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval', 'Date'] });
    tap.start = { capturing: true, reason: null };
    const quiet: string[] = [];
    show(<ComputerSound live onSay={(text) => quiet.push(text)} />);
    await act(async () => {
      await Promise.resolve();
    });
    for (let i = 0; i < 8; i += 1) {
      await act(async () => {
        vi.advanceTimersByTime(1_500);
        await Promise.resolve();
      });
    }
    expect(quiet).toEqual([NOTHING_FROM_THE_MAC]);
  });
});
