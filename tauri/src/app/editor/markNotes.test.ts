import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { MARKS } from '../plugins/marks/index.tsx';
import type { InlineFormat } from '../plugins/types.ts';
import { glyphMarkdown } from './language.ts';
import { isTint, markNotes, noteAt, notePattern, notesIn } from './markNotes.ts';

const pattern = () => notePattern(MARKS)!;

describe('a note written after a mark', () => {
  it('finds the words, the brackets and what the note says', () => {
    const line = 'The deposit is ??four hundred??(Sam said 400, the email says 450) and needs checking.';
    const [note] = notesIn(line, pattern());
    expect(note).toBeTruthy();
    expect(line.slice(note!.words.from, note!.words.to)).toBe('four hundred');
    expect(line.slice(note!.brackets.from, note!.brackets.to)).toBe('(Sam said 400, the email says 450)');
    expect(note!.text).toBe('Sam said 400, the email says 450');
  });

  it('works for every mark, not only a doubt', () => {
    const found = notesIn('==this==(why it matters) and ^^that^^(said twice) and ++new++(added Friday)', pattern());
    expect(found.map((note) => note.text)).toEqual(['why it matters', 'said twice', 'added Friday']);
  });

  it('leaves a mark with no brackets, and brackets with no mark, alone', () => {
    expect(notesIn('??just a doubt?? and (a plain aside)', pattern())).toEqual([]);
    expect(notesIn('nothing here at all', pattern())).toEqual([]);
  });

  it('counts positions from where the text starts in the note', () => {
    const [note] = notesIn('??x??(y)', pattern(), 100);
    expect(note?.from).toBe(100);
    expect(note?.words.from).toBe(102);
  });

  it('answers which note a tap landed in: its words or its hidden brackets, not the words before them', () => {
    const line = 'Ask ??Sam??(before Friday) today';
    const notes = notesIn(line, pattern());
    expect(noteAt(notes, line.indexOf('Sam') + 1)?.text).toBe('before Friday');
    expect(noteAt(notes, line.indexOf('(before') + 2)?.text).toBe('before Friday');
    expect(noteAt(notes, 1)).toBeNull();
    expect(noteAt(notes, line.length - 1)).toBeNull();
  });

  it('takes the shorter of two marks on a line rather than running them together', () => {
    const found = notesIn('??one??(first) then ??two??(second)', pattern());
    expect(found.map((note) => note.text)).toEqual(['first', 'second']);
  });

  it('has no pattern at all when every mark is switched off', () => {
    expect(notePattern([])).toBeNull();
  });
});

describe('brackets that name a colour', () => {
  const tinted: InlineFormat[] = [
    { name: 'Highlight', delimiter: '==', look: { kind: 'style', css: '' }, tint: (name) => (name === 'green' ? 'background: green;' : null) },
    { name: 'Unsure', delimiter: '??', look: { kind: 'style', css: '' } },
  ];

  it('are a colour on the mark that takes one, and a note anywhere else', () => {
    const pattern = notePattern(tinted)!;
    const [colour] = notesIn('the ==key==(green) is under the mat', pattern);
    expect(colour?.delimiter).toBe('==');
    expect(isTint(colour!, tinted)).toBe(true);
    // The same word on a mark that takes no colours is what it always was: a note.
    const [note] = notesIn('the ??key??(green) is under the mat', pattern);
    expect(isTint(note!, tinted)).toBe(false);
  });

  it('are still a note when the name is not one the mark knows', () => {
    const pattern = notePattern(tinted)!;
    const [note] = notesIn('the ==key==(Sam has one) is under the mat', pattern);
    expect(note?.text).toBe('Sam has one');
    expect(isTint(note!, tinted)).toBe(false);
  });
});

describe('a tap on noted words', () => {
  const line = 'The ??deposit??(Sam said 400) and the ==key==(green) are sorted.';
  let view: EditorView | null = null;

  afterEach(() => {
    view?.destroy();
    view = null;
    vi.restoreAllMocks();
  });

  /** A tap landing at `pos`; jsdom lays nothing out, so where the words are is said here. */
  function tapAt(pos: number): EditorView {
    view ??= new EditorView({ state: EditorState.create({ doc: line, extensions: [glyphMarkdown(MARKS), markNotes(MARKS)] }), parent: document.body });
    const on = view;
    vi.spyOn(on, 'posAtCoords').mockReturnValue(pos);
    vi.spyOn(on, 'coordsAtPos').mockReturnValue({ left: 40, right: 50, top: 0, bottom: 20 });
    on.contentDOM.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    return on;
  }
  const panel = (on: EditorView) => on.dom.querySelector('.cm-markNotePanel');

  it('shows what the note says, and a tap anywhere else closes it', () => {
    const on = tapAt(line.indexOf('deposit') + 2);
    expect(panel(on)?.textContent).toBe('Sam said 400');
    expect(panel(on)?.getAttribute('aria-label')).toBe('Note');
    tapAt(1);
    expect(panel(on)).toBeNull();
  });

  it('shows nothing for a colour named in the brackets, where there is nothing to say', () => {
    const on = tapAt(line.indexOf('deposit') + 2);
    tapAt(line.indexOf('key') + 1);
    expect(panel(on)).toBeNull();
  });
});
