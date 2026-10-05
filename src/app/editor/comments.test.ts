import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { MARKS } from '../plugins/marks/index.tsx';
import { formatLooks } from './formatLooks.ts';
import { glyphMarkdown } from './language.ts';
import { noteComments, refreshComments, type CommentHooks } from './comments.ts';

/**
 * Comments drawn in the note (editor/comments.ts; docs/SHARED.md, S8): each anchor a round in its author's colour that
 * opens its thread, the words round a selection washed in that colour by the highlight's own token, a resolved thread
 * a ring with no wash, the fence drawn as the threads, and the text as written wherever the caret is on it.
 */

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const NOTE = [
  '# Barn dance',
  '',
  'The ==venue==[^c1] is booked. Call the band[^c2]',
  '',
  '```comments',
  'c1 sam 2026-10-04T19:00:12Z',
  'The hall or the barn?',
  '  matt 2026-10-04T19:05:40Z',
  '  The hall.',
  'c2 matt 2026-10-04T19:10:00Z',
  'Which band?',
  '  resolved sam 2026-10-04T19:12:00Z',
  '```',
  '',
].join('\n');

const views: EditorView[] = [];
afterEach(() => {
  for (const view of views.splice(0)) act(() => view.destroy());
});

function hooksFor(colours: Record<string, string> = { sam: 'sea', matt: 'rose' }) {
  return { open: vi.fn<(id: string) => void>(), colour: (handle: string) => colours[handle] ?? 'ink', me: () => 'matt' } satisfies CommentHooks;
}

async function open(doc: string, hooks: CommentHooks | null, selection?: number) {
  let view!: EditorView;
  await act(async () => {
    view = new EditorView({
      state: EditorState.create({ doc, selection: selection === undefined ? undefined : { anchor: selection }, extensions: [glyphMarkdown(MARKS), formatLooks(MARKS), noteComments(() => hooks)] }),
      parent: document.body,
    });
  });
  views.push(view);
  return view;
}

const rounds = (view: EditorView) => [...view.dom.querySelectorAll<HTMLElement>('.cm-commentRound')];

describe('comments in a note', () => {
  it('draws each anchor as a round in its author’s colour, a resolved one as a ring', async () => {
    const view = await open(NOTE, hooksFor());
    const [venue, band] = rounds(view);
    expect(venue?.dataset.hue).toBe('sea');
    expect(venue?.hasAttribute('data-resolved')).toBe(false);
    expect(venue?.getAttribute('aria-label')).toBe('Comment by sam, 1 reply');
    expect(band?.dataset.hue).toBe('rose');
    expect(band?.hasAttribute('data-resolved')).toBe(true);
    expect(band?.getAttribute('aria-label')).toBe('Comment by You, resolved');
    // The anchor's text is drawn over: the round stands in for `[^c1]`.
    expect(view.contentDOM.querySelector('.cm-line:nth-child(3)')?.textContent).not.toContain('[^c1]');
  });

  it('opens the thread on a tap of its round, and leaves the caret where it was', async () => {
    const hooks = hooksFor();
    const view = await open(NOTE, hooks);
    const before = view.state.selection.main.head;
    act(() => rounds(view)[0]!.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })));
    expect(hooks.open).toHaveBeenCalledWith('c1');
    expect(view.state.selection.main.head).toBe(before);
  });

  it('washes the words round a selection by setting the highlight’s colour around it, and none once resolved', async () => {
    const view = await open(NOTE, hooksFor());
    const wash = view.dom.querySelector<HTMLElement>('.cm-commentWash')!;
    expect(wash.dataset.hue).toBe('sea');
    expect(wash.hasAttribute('data-resolved')).toBe(false);
    // The highlight's own span is inside it, so it reads `--app-mark` from the wash.
    expect(wash.querySelector('.cm-formatLook')?.textContent).toBe('venue');
    const resolved = NOTE.replace('  The hall.', '  The hall.\n  resolved matt 2026-10-04T19:06:00Z');
    const after = await open(resolved, hooksFor());
    expect(after.dom.querySelector<HTMLElement>('.cm-commentWash')!.hasAttribute('data-resolved')).toBe(true);
  });

  it('shows the anchor as written while the caret is on it, in a focused editor', async () => {
    const at = NOTE.indexOf('[^c1]') + 2;
    const view = await open(NOTE, hooksFor(), at);
    // Not focused: the caret on it still leaves the round, since nobody is typing.
    expect(rounds(view)).toHaveLength(2);
    view.focus();
    // CodeMirror tells the state of a focus change a moment after the DOM's own event (editor/tables.test.ts).
    await vi.waitFor(() => expect(rounds(view)).toHaveLength(1));
    expect(view.contentDOM.textContent).toContain('==venue==[^c1]');
    view.contentDOM.blur();
    await vi.waitFor(() => expect(rounds(view)).toHaveLength(2));
  });

  it('draws the fence as the list of threads, open ones first, and a tap opens one and brings its anchor in', async () => {
    const hooks = hooksFor();
    const view = await open(NOTE, hooks);
    const list = view.dom.querySelector<HTMLElement>('.cm-commentList')!;
    expect(list).not.toBeNull();
    expect(list.textContent).toContain('2 comments, 1 open');
    const rows = [...list.querySelectorAll<HTMLButtonElement>('li > button')];
    expect(rows.map((row) => row.textContent)).toEqual([expect.stringContaining('The hall or the barn?'), expect.stringContaining('Which band?')]);
    expect(rows[0]!.textContent).toContain('1 reply');
    expect(rows[1]!.textContent).toContain('Resolved');
    expect(view.contentDOM.textContent).not.toContain('c1 sam 2026');
    const scroll = vi.spyOn(view, 'dispatch');
    act(() => rows[0]!.click());
    expect(hooks.open).toHaveBeenCalledWith('c1');
    expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ effects: expect.anything() }));
  });

  it('puts the caret in the fence from its pencil, which shows its lines', async () => {
    const view = await open(NOTE, hooksFor());
    const pencil = view.dom.querySelector<HTMLButtonElement>('.cm-commentList button[aria-label="Show the comments as written"]')!;
    act(() => pencil.click());
    expect(view.state.doc.lineAt(view.state.selection.main.head).text).toBe('c1 sam 2026-10-04T19:00:12Z');
  });

  it('draws again in the new colours when told', async () => {
    const colours: Record<string, string> = { sam: 'sea' };
    const view = await open(NOTE, { open: vi.fn(), colour: (handle) => colours[handle] ?? 'ink', me: () => 'matt' });
    expect(rounds(view)[0]!.dataset.hue).toBe('sea');
    colours.sam = 'moss';
    act(() => view.dispatch({ effects: refreshComments.of(null) }));
    expect(rounds(view)[0]!.dataset.hue).toBe('moss');
  });

  it('draws nothing without hooks, and nothing for a note with no fence', async () => {
    const bare = await open(NOTE, null);
    expect(rounds(bare)).toHaveLength(0);
    expect(bare.dom.querySelector('.cm-commentList')).toBeNull();
    expect(bare.contentDOM.textContent).toContain('[^c1]');
    const plain = await open('Words[^c1]\n', hooksFor());
    expect(rounds(plain)).toHaveLength(0);
  });

  it('tells the hooks when the note changes, so an open card reads its thread again', async () => {
    const changed = vi.fn();
    const view = await open(NOTE, { ...hooksFor(), changed });
    act(() => view.dispatch({ changes: { from: 0, insert: 'x' } }));
    expect(changed).toHaveBeenCalledTimes(1);
  });
});
