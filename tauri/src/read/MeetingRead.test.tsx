import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, waitUntil } from '../test/render.tsx';
import type { Meeting } from './meeting.ts';

/*
 * The shared meeting's page (MeetingRead.tsx): Summary first, Transcript a tap away, the cassette where the share
 * carries a recording and none where it does not, a tap on a phrase playing from it, and the phrase being heard lit
 * as the tape moves. The sound itself is stood in for (shareAudio.ts has its own test): jsdom plays nothing, so the
 * element's events are sent by hand.
 */

await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

/** What fetching the recording did: the parts arriving at once, the sound so far always the whole of it. */
const fetched = vi.hoisted(() => ({ loads: 0, rest: null as null | Promise<void> }));
vi.mock('./shareAudio.ts', () => ({
  SharedRecording: class {
    done = false;
    progress = 0;
    loadedMs = 0;
    constructor(
      readonly id: string,
      readonly key: string,
      readonly audio: { ms: number },
    ) {}
    async load(onPart: () => void) {
      fetched.loads += 1;
      // Where a test holds the rest back: half a minute comes first, the rest when it lets go.
      if (fetched.rest) {
        this.progress = 0.5;
        this.loadedMs = 30_000;
        onPart();
        await fetched.rest;
      }
      this.done = true;
      this.progress = 1;
      this.loadedMs = this.audio.ms;
      onPart();
    }
    sound() {
      return this.done ? { blob: new Blob(['wav'], { type: 'audio/wav' }), ms: this.audio.ms } : null;
    }
  },
}));

/** The element's play and pause, which jsdom has none of: each says so as a browser would. */
const played = vi.fn(function (this: HTMLMediaElement) {
  Object.defineProperty(this, 'paused', { configurable: true, value: false });
  this.dispatchEvent(new Event('play'));
  return Promise.resolve();
});
HTMLMediaElement.prototype.play = played;
HTMLMediaElement.prototype.pause = function (this: HTMLMediaElement) {
  Object.defineProperty(this, 'paused', { configurable: true, value: true });
  this.dispatchEvent(new Event('pause'));
};
HTMLMediaElement.prototype.load = function () {};
URL.createObjectURL = vi.fn(() => 'blob:sound');
URL.revokeObjectURL = vi.fn();

const { MeetingRead } = await import('./MeetingRead.tsx');

const meeting: Meeting = {
  ms: 60_000,
  hue: 'teal',
  at: Date.UTC(2026, 9, 18, 14),
  speakers: ['Sam Lee', 'Ana'],
  turns: [
    { s: 0, p: [[0, 2000, 'Good morning everyone.'], [2000, 4800, 'The checklist is first.']] },
    { s: 1, p: [[5000, 7000, 'Thanks, the pricing page is drafted.']] },
  ],
  audio: { upload: 'up', parts: 2, bytes: 1_920_044, mime: 'audio/wav', ms: 60_000, chunk: 1 << 20 },
};
const link = { id: 'ShareId0123456789abcd', key: 'k'.repeat(43) };

const button = (text: string) => [...document.querySelectorAll('button')].find((b) => b.textContent?.trim() === text);
const radio = (label: string) => [...document.querySelectorAll<HTMLElement>('[role="radio"], label, button')].find((el) => el.textContent?.trim() === label);

afterEach(() => {
  played.mockClear();
});

describe('a shared meeting’s page', () => {
  it('opens on the summary, with the cassette, and goes to the transcript by the toggle', async () => {
    show(<MeetingRead title="Launch sync" meeting={meeting} link={link} dark={false} summary={<p>The summary’s words.</p>} />);
    expect(document.querySelector('h1')?.textContent).toBe('Launch sync');
    expect(document.body.textContent).toContain('The summary’s words.');
    expect(document.querySelector('[aria-label="Play the recording"] svg[data-hue="teal"]')).toBeTruthy();
    expect(document.querySelector('[aria-label="Transcript"]')).toBeNull();
    act(() => radio('Transcript')!.click());
    await waitUntil(() => expect(document.querySelector('[aria-label="Transcript"]')).toBeTruthy());
    expect(document.body.textContent).not.toContain('The summary’s words.');
    expect([...document.querySelectorAll('li strong')].map((s) => s.textContent)).toEqual(['Sam Lee', 'Ana']);
    expect(fetched.loads).toBe(0);
  });

  it('plays from a phrase tapped, and lights the phrase being heard as the tape moves', async () => {
    show(<MeetingRead title="Launch sync" meeting={meeting} link={link} dark={false} summary={<p>Summary.</p>} />);
    act(() => radio('Transcript')!.click());
    await waitUntil(() => expect(button('Thanks, the pricing page is drafted.')).toBeTruthy());
    // Nothing lit on a tape nobody has played.
    expect(document.querySelector('button[data-current]')).toBeNull();
    act(() => button('Thanks, the pricing page is drafted.')!.click());
    await waitUntil(() => expect(fetched.loads).toBeGreaterThan(0));
    // The sound is given: once it has loaded, the tape is put at the phrase and played.
    const audio = document.querySelector('audio') ?? (await waitForElement());
    act(() => void audio.dispatchEvent(new Event('loadedmetadata')));
    expect(audio.currentTime).toBe(5);
    expect(played).toHaveBeenCalled();
    act(() => {
      audio.currentTime = 5.5;
      audio.dispatchEvent(new Event('timeupdate'));
    });
    expect(document.querySelector('button[data-current]')?.textContent?.trim()).toBe('Thanks, the pricing page is drafted.');
    expect([...document.querySelectorAll('button[data-past]')].map((b) => b.textContent?.trim())).toEqual(['Good morning everyone.', 'The checklist is first.']);
    // Further on, the light moves; earlier, it goes back.
    act(() => {
      audio.currentTime = 2.5;
      audio.dispatchEvent(new Event('timeupdate'));
    });
    expect(document.querySelector('button[data-current]')?.textContent?.trim()).toBe('The checklist is first.');
    expect(document.body.textContent).toContain('0:02 / 1:00');
  });

  it('waits for the sound of a line tapped past what has come, and plays it from that line', async () => {
    const late: Meeting = { ...meeting, turns: [...meeting.turns, { s: 0, p: [[45_000, 48_000, 'Last thing.']] }] };
    let letGo = () => {};
    fetched.rest = new Promise<void>((resolve) => (letGo = resolve));
    try {
      show(<MeetingRead title="Launch sync" meeting={late} link={link} dark={false} summary={<p>Summary.</p>} />);
      act(() => radio('Transcript')!.click());
      await waitUntil(() => expect(button('Last thing.')).toBeTruthy());
      audioMade.length = 0;
      act(() => button('Last thing.')!.click());
      await waitUntil(() => expect(document.body.textContent).toContain('Loading the recording… 50%'));
      // The first half minute is in, and is not played from its end in place of the line.
      expect(audioMade).toHaveLength(0);
      await act(async () => letGo());
      const audio = await waitForElement();
      act(() => void audio.dispatchEvent(new Event('loadedmetadata')));
      expect(audio.currentTime).toBe(45);
      expect(played).toHaveBeenCalled();
    } finally {
      fetched.rest = null;
    }
  });

  it('stops following when the reader scrolls away, and Back to now takes it back', async () => {
    show(<MeetingRead title="Launch sync" meeting={meeting} link={link} dark={false} summary={<p>Summary.</p>} />);
    act(() => radio('Transcript')!.click());
    await waitUntil(() => expect(button('Good morning everyone.')).toBeTruthy());
    const scrolled = vi.fn();
    Element.prototype.scrollIntoView = scrolled;
    act(() => button('Good morning everyone.')!.click());
    await waitUntil(() => expect(fetched.loads).toBeGreaterThan(0));
    const audio = await waitForElement();
    act(() => void audio.dispatchEvent(new Event('loadedmetadata')));
    act(() => {
      audio.currentTime = 2.2;
      audio.dispatchEvent(new Event('timeupdate'));
    });
    expect(scrolled).toHaveBeenCalled();
    expect(button('Back to now')).toBeUndefined();
    act(() => void window.dispatchEvent(new Event('wheel')));
    expect(button('Back to now')).toBeTruthy();
    scrolled.mockClear();
    act(() => {
      audio.currentTime = 5.2;
      audio.dispatchEvent(new Event('timeupdate'));
    });
    expect(scrolled).not.toHaveBeenCalled();
    act(() => button('Back to now')!.click());
    expect(scrolled).toHaveBeenCalled();
    expect(button('Back to now')).toBeUndefined();
  });

  it('plays and pauses with the space bar', async () => {
    show(<MeetingRead title="Launch sync" meeting={meeting} link={link} dark={false} summary={<p>Summary.</p>} />);
    act(() => void document.body.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true })));
    await waitUntil(() => expect(fetched.loads).toBeGreaterThan(0));
    const audio = await waitForElement();
    act(() => void audio.dispatchEvent(new Event('loadedmetadata')));
    expect(played).toHaveBeenCalled();
    expect(document.querySelector('[aria-label="Pause the recording"]')).toBeTruthy();
    act(() => void document.body.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true })));
    expect(document.querySelector('[aria-label="Play the recording"]')).toBeTruthy();
  });

  it('without a recording, has no cassette, and its transcript is read but not played', () => {
    const { audio: _audio, ...words } = meeting;
    show(<MeetingRead title="Launch sync" meeting={words} link={link} dark={false} summary={<p>Summary.</p>} />);
    expect(document.querySelector('[aria-label="The recording"]')).toBeNull();
    act(() => radio('Transcript')!.click());
    expect(document.body.textContent).toContain('Thanks, the pricing page is drafted.');
    expect(button('Thanks, the pricing page is drafted.')).toBeUndefined();
  });
});

/** The `<audio>` the page's tape made: it is never put in the document, so it is caught from its `src` being set. */
async function waitForElement(): Promise<HTMLMediaElement> {
  await waitUntil(() => expect(audioMade.at(-1)).toBeTruthy());
  return audioMade.at(-1)!;
}

const audioMade: HTMLMediaElement[] = [];
const describedSrc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src')!;
Object.defineProperty(HTMLMediaElement.prototype, 'src', {
  configurable: true,
  get() {
    return describedSrc.get!.call(this);
  },
  set(value: string) {
    audioMade.push(this as HTMLMediaElement);
    describedSrc.set!.call(this, value);
  },
});
