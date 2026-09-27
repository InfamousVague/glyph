import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { syntaxTree } from '@codemirror/language';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseWhole } from '../../../test/syntaxTree.ts';
import { glyphMarkdown } from '../../editor/language.ts';
import { formatLooks, styledRanges, type StyleLook } from '../../editor/formatLooks.ts';
import { shortLinks } from '../../editor/links.ts';
import { noteView } from '../../editor/viewMode.ts';
import { BUILT_IN } from '../registry.ts';
import { isMarkColour, MARK_COLOURS, MARKS, marksPlugin, washFor } from './index.tsx';

const formats = MARKS;

function nodes(doc: string): string[] {
  const state = EditorState.create({ doc, extensions: [glyphMarkdown(formats)] });
  const names: string[] = [];
  syntaxTree(state).iterate({ enter: (node) => void names.push(node.name) });
  return names;
}

/** The plugin's style looks as the editor keeps them (editor/formatLooks.ts `formatLooks`). */
const looks = new Map<string, StyleLook>(
  formats.flatMap((f) => (f.look.kind === 'style' ? [[f.name, { length: f.delimiter.length, css: f.look.css, clearAtCaret: f.look.clearAtCaret, tint: f.tint }]] : [])),
);

describe("Ghost.md's own marks", () => {
  it('are one plugin, with one switch, each mark carrying its own icon', () => {
    expect(marksPlugin.manifest.id).toBe('marks');
    expect(marksPlugin.formats).toBe(MARKS);
    expect(marksPlugin.manifest.permissions).toEqual([]);
    for (const format of MARKS) expect(format.icon, format.name).toBeTruthy();
    expect(MARKS.map((format) => format.name)).toContain('Spoiler');
  });

  it('each parses between its own delimiter, with a cue and a line for the guide', () => {
    for (const format of formats) {
      const doc = `say ${format.delimiter}these words${format.delimiter} now`;
      expect(nodes(doc), format.name).toContain(format.name);
      expect(format.cue, format.name).toBeTruthy();
      expect(format.about, format.name).toBeTruthy();
    }
  });

  it('shares no delimiter or node name with any other plugin', () => {
    const all = BUILT_IN.flatMap((plugin) => plugin.formats ?? []);
    expect(new Set(all.map((f) => f.delimiter)).size).toBe(all.length);
    expect(new Set(all.map((f) => f.name)).size).toBe(all.length);
  });

  it('leaves prose alone: a question, a comparison, a list marker', () => {
    expect(nodes('Really?? Sure?? Not that ??')).not.toContain('Unsure');
    expect(nodes('x == y and a == b')).not.toContain('Highlight');
    expect(nodes('+ an item\n+ another')).toContain('ListItem');
    expect(nodes('+ an item\n+ another')).not.toContain('Added');
  });

  it('lifts a redaction while the caret is in it, and keeps the rest lit', () => {
    const doc = 'name: @@Sam Ortiz@@ and ==keep==';
    const inside = EditorState.create({ doc, extensions: [glyphMarkdown(formats)], selection: { anchor: 10 } });
    const words = (state: EditorState, atCaret: boolean) =>
      styledRanges(state, looks, { from: 0, to: doc.length }, atCaret).map((r) => doc.slice(r.from, r.to));
    expect(words(inside, true)).toEqual(['keep']);
    expect(words(inside, false)).toEqual(['Sam Ortiz', 'keep']);
    const outside = EditorState.create({ doc, extensions: [glyphMarkdown(formats)], selection: { anchor: 0 } });
    expect(words(outside, true)).toEqual(['Sam Ortiz', 'keep']);
    // Only the redaction lifts: the other looks stay while the caret is in their words.
    expect([...looks.entries()].filter(([, look]) => look.clearAtCaret).map(([name]) => name)).toEqual(['Redact']);
  });
});

describe('the redaction', () => {
  const redact = MARKS.find((mark) => mark.name === 'Redact')!;
  let view: EditorView | null = null;

  afterEach(() => {
    view?.destroy();
    view = null;
  });

  /** A note with a redaction, in the editor, drawn as the note screen draws it: the marks and their looks, in `shown`. */
  function open(doc: string, shown: 'mixed' | 'formatted' = 'mixed'): EditorView {
    view = parseWhole(new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(formats), formatLooks(formats), noteView(shown)] }), parent: document.body }));
    return view;
  }
  const bar = (on: EditorView) => on.contentDOM.querySelector<HTMLElement>('.cm-formatLook');

  it('is back, between two at signs, said as "redact … end redact" (Matt: "add redact formatting")', () => {
    expect(redact.delimiter).toBe('@@');
    expect(redact.cue).toBe('redact');
    expect(nodes('a @@bar@@ of ink')).toContain('Redact');
    // With the ink-and-paper marks, before the effects: the Style page and the guide show them in this order.
    const names = MARKS.map((mark) => mark.name);
    expect(names.indexOf('Redact')).toBe(names.indexOf('Unsure') + 1);
    expect(names.indexOf('Redact')).toBeLessThan(names.indexOf('Heat'));
  });

  it('is a bar of the page’s ink, the words the same ink, so nothing shows through on either side of the page', () => {
    const look = redact.look;
    expect(look.kind).toBe('style');
    if (look.kind !== 'style') return;
    const rule = (name: string) => new RegExp(`(?:^|;)\\s*${name}:\\s*([^;]+);`).exec(look.css)?.[1];
    // The bar, the words and their fill are one token, and it is the page's own ink, so a dark page draws a light bar.
    expect(rule('background')).toBe('var(--glacier-text)');
    expect(rule('color')).toBe(rule('background'));
    expect(rule('-webkit-text-fill-color')).toBe(rule('background'));
    expect(rule('box-shadow')).toContain('var(--glacier-text)');
    // An emoji takes neither the colour nor the fill, so the span is printed flat in the ink (app/ink.css).
    expect(rule('filter')).toBe('var(--app-ink-flat)');
    expect(look.clearAtCaret).toBe(true);
  });

  it('draws the bar over the words alone, with the at signs outside it as dimmed marks', () => {
    const on = open('the gate code is @@4417@@ today');
    expect(bar(on)?.textContent).toBe('4417');
    expect(bar(on)?.getAttribute('style')).toContain('background: var(--glacier-text)');
    expect(on.contentDOM.textContent).toBe('the gate code is @@4417@@ today');
  });

  it('keeps the bar in the Formatted view, where the at signs are hidden', () => {
    const on = open('the gate code is @@4417@@ today', 'formatted');
    expect(on.contentDOM.querySelector('.cm-line')?.textContent).toBe('the gate code is 4417 today');
    expect(bar(on)?.textContent).toBe('4417');
  });

  it('lifts while the caret is in the words, and comes back when it leaves', async () => {
    const on = open('the gate code is @@4417@@ today');
    on.focus();
    on.dispatch({ selection: { anchor: 'the gate code is @@44'.length } });
    await vi.waitFor(() => expect(bar(on)).toBeNull());
    on.dispatch({ selection: { anchor: 0 } });
    await vi.waitFor(() => expect(bar(on)?.textContent).toBe('4417'));
  });

  it('is drawn inside a highlight, a bar on the wash, and hides a highlight inside it', () => {
    // The review found the inner look skipped: the words sat in the wash, readable, in both views and both themes.
    const on = open('==a highlight with @@a bar@@ inside==');
    const bars = [...on.contentDOM.querySelectorAll<HTMLElement>('.cm-formatLook')].filter((mark) => mark.getAttribute('style')?.includes('var(--glacier-text)'));
    expect(bars.map((mark) => mark.textContent)).toEqual(['a bar']);
    expect(bars[0]?.parentElement?.closest('.cm-formatLook')?.getAttribute('style')).toContain('var(--app-mark');
    // A wash inside a bar would show the words through the ink, so under a bar nothing is drawn.
    const doc = '@@a ==wash== in a bar@@';
    const words = styledRanges(EditorState.create({ doc, extensions: [glyphMarkdown(formats)] }), looks, { from: 0, to: doc.length }).map((r) => doc.slice(r.from, r.to));
    expect(words).toEqual(['a ==wash== in a bar']);
  });

  it('keeps a link’s address under the bar, where one outside it is shortened beside its words', () => {
    // A short address is a widget (editor/links.ts), which sits beside the bar's span, not in it: "example.com" showed
    // in plain ink between two pieces of bar.
    const doc = '@@see [the plan](https://example.com/the/plan)@@ and [the rest](https://example.org/the/rest)';
    view = parseWhole(new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(formats), formatLooks(formats), shortLinks({ still: true })] }), parent: document.body }));
    expect([...view.contentDOM.querySelectorAll('.cm-shortLink')].map((short) => short.textContent)).toEqual(['example.org/the/rest']);
    expect(view.contentDOM.textContent).toContain('(https://example.com/the/plan)');
  });
});

describe('a highlight with a colour named after it', () => {
  const highlight = MARKS.find((mark) => mark.name === 'Highlight')!;

  it('takes the kit’s own colour names, and nothing else', () => {
    for (const name of MARK_COLOURS) expect(isMarkColour(name)).toBe(true);
    expect(isMarkColour('chartreuse')).toBe(false);
    // The wash names a token, never a colour: the kit can retune green without touching a note.
    expect(washFor('green')).toBe('color-mix(in oklch, var(--glacier-green-9) 34%, transparent)');
    expect(washFor('GREEN ')).toBe(washFor('green'));
    expect(washFor('chartreuse')).toBe('');
  });

  it('tints the words for a name it knows and leaves the rest to the note', () => {
    expect(highlight.tint?.('amber')).toContain('var(--glacier-amber-9)');
    expect(highlight.tint?.('amber')).toContain('box-shadow');
    // A name it does not know is not a colour: those brackets are still a note (editor/markNotes.ts).
    expect(highlight.tint?.('Sam said 400')).toBeNull();
    expect(highlight.tint?.('')).toBeNull();
  });

  it('is the only mark that takes one', () => {
    for (const mark of MARKS.filter((one) => one.name !== 'Highlight')) expect(mark.tint).toBeUndefined();
  });
});
