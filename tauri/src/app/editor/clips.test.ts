import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { clips, tapeSource, type Tape } from './clips.ts';

const MEMO = '![voice 0:12](tape:12000-24000@k3f9x2)';
const doc = ['Before the memo', `- ${MEMO}`, `and one said mid-sentence ![voice 0:03](tape:30000-33000@k3f9x2) here`].join('\n');
const TAPE: Tape = { src: 'rec://note.wav', id: 'k3f9x2' };
/** Where line `n` of the note starts. */
const lineStart = (n: number) => doc.split('\n').slice(0, n - 1).join('\n').length + (n > 1 ? 1 : 0);

let view: EditorView | null = null;
/** Every recording played, in order: jsdom has no media, so playing and pausing are said here, as a browser says them. */
let played: HTMLMediaElement[] = [];
let refuse = false;

beforeEach(() => {
  played = [];
  refuse = false;
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(function (this: HTMLMediaElement) {
    if (refuse) return Promise.reject(new Error('NotAllowedError'));
    played.push(this);
    this.dispatchEvent(new Event('play'));
    return Promise.resolve();
  });
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(function (this: HTMLMediaElement) {
    this.dispatchEvent(new Event('pause'));
  });
});

afterEach(() => {
  view?.destroy();
  view = null;
  vi.restoreAllMocks();
});

function open(tape: Tape = TAPE, caret = 0): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [clips(), tapeSource.of(tape)] }), parent: document.body });
  return view;
}
const players = (on: EditorView) => [...on.dom.querySelectorAll<HTMLButtonElement>('button.cm-clip')];
const line = (on: EditorView, n: number) => on.contentDOM.querySelectorAll('.cm-line')[n - 1]!;
const press = (button: HTMLElement) => button.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));

describe('a voice memo in a note', () => {
  it('is a player in place of its mark, on a line of its own or in the middle of a sentence', () => {
    const on = open();
    expect(players(on).map((player) => player.getAttribute('aria-label'))).toEqual(['Play this voice memo, 0:12', 'Play this voice memo, 0:03']);
    expect(on.contentDOM.textContent).not.toContain('![voice');
    expect(line(on, 3).textContent).toBe('and one said mid-sentence 0:03 here');
  });

  it('shows its mark as written on the caret’s line, the player beside it, so it can be edited', () => {
    const on = open(TAPE, lineStart(2));
    expect(line(on, 2).textContent).toContain(MEMO);
    expect(line(on, 2).querySelector('button.cm-clip')).not.toBeNull();
    expect(line(on, 3).textContent).not.toContain('![voice');
  });

  it('is a quiet mark with nothing to press where the note has no recording, or another one', () => {
    for (const tape of [{ src: null, id: null }, { src: 'rec://other.wav', id: 'zz9' }]) {
      const on = open(tape);
      expect(players(on)).toEqual([]);
      expect([...on.dom.querySelectorAll('.cm-clipQuiet')].map((quiet) => quiet.textContent)).toEqual(['voice 0:12', 'voice 0:03']);
      view?.destroy();
      view = null;
    }
  });

  it('plays its stretch of the recording, and stops at its end', () => {
    const on = open();
    const [first] = players(on);
    press(first!);
    expect(played).toHaveLength(1);
    const audio = played[0]!;
    expect(audio.src).toContain('rec://note.wav');
    expect(audio.currentTime).toBe(12);
    expect(first!.dataset.state).toBe('playing');
    audio.currentTime = 24.1;
    audio.dispatchEvent(new Event('timeupdate'));
    expect(first!.dataset.state).toBe('still');
    // Set back to its start, for the next press.
    expect(audio.currentTime).toBe(12);
  });

  it('plays one at a time: a second memo stops the first, and a second press stops its own', () => {
    const on = open();
    const [first, second] = players(on);
    press(first!);
    press(second!);
    expect(first!.dataset.state).toBe('still');
    expect(second!.dataset.state).toBe('playing');
    press(second!);
    expect(second!.dataset.state).toBe('still');
  });

  it('says so when the recording will not play', async () => {
    refuse = true;
    const on = open();
    const [first] = players(on);
    press(first!);
    await vi.waitFor(() => expect(first!.title).toBe('This voice memo couldn’t be played.'));
    expect(first!.dataset.state).toBe('still');
  });
});
