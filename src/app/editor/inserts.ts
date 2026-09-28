import { StateEffect, StateField, type ChangeSpec, type EditorState, type Line } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { historyField, isolateHistory, redoDepth, undoDepth } from '@codemirror/commands';
import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import type { SyntaxNode } from '@lezer/common';
import { anchorSpan, lineWords, listLead, withoutBookmark } from '../core/itemSyntax.ts';

/**
 * Where a thing put into a note goes: the rules the + beside the line keeps (editor/AddList.tsx), and with it press
 * and hold's Add image, a pasted picture and Style's table and rule, which used to keep a looser copy each.
 *
 * Three kinds of insert, by what they are (docs/DESIGN.md §141):
 *
 * - **A thing drawn on a line of its own**, a picture, a place, a film, a canvas's frame: it takes the caret's line
 *   when that line says nothing (`givesWay`), or goes on a new line after it, so a line is never split. A blank line
 *   goes before it when the line above is a list item, a quote or a table row, or the thing would be read as part of
 *   that block: `- [ ] ` then a picture was a to-do whose words were the picture, and a picture on the empty line
 *   under a table was a row of it. A place, a film and a frame are links, so they keep apart from a paragraph above
 *   too (`apart`): under `Lunch at the harbour` a place would be read, by any other reader, as the end of the
 *   sentence, "Lunch at the harbour Cais do Sodré", and sat in the app like the paragraph's second line. A picture
 *   under a paragraph stays as it was, which every reader draws as a picture of its own. The caret is left on a fresh
 *   line after it, so typing carries on underneath.
 * - **A block**, a table, a rule, a fence: the same, and a blank line on either side where the line there has words.
 *   Without the one after, a table took the next line of words as a row. Without the one before, a rule under a
 *   paragraph reads as a heading in Obsidian and GitHub, though never in the app, whose parser has no setext headings
 *   (editor/language.ts).
 * - **Words at the caret**, the time, a link to a note: a space either side where a sentence needs one.
 *
 * And a line's lead, for a to-do, a list or a heading: an empty item's lead becomes the new one, keeping its indent,
 * and a line of words gets a new line under it, since the + adds and never rewrites what a line says (that is Style's).
 *
 * Every insert is one transaction with its history isolated, so one Undo takes back exactly it. The plans are pure,
 * over a state, so each is a test (editor/inserts.test.ts); `apply` dispatches one.
 *
 * Some writes land late: a place waits for its fix and its name, a picture for the picker. The place they go is kept
 * from the tap (`reserveSpot`) and mapped through every change made meanwhile, and a write that lands after the person
 * has gone to another field does not take the focus back to the note (`focusToken`).
 */

/** What an insert changes, and where the caret or the selection goes after. */
export interface Plan {
  changes: ChangeSpec;
  selection?: { anchor: number; head?: number };
}

/** Where the caret goes in a block: an offset into its text (a range, to select a word to write over), or a fresh line after it. */
export type BlockSelect = { from: number; to?: number } | 'after';

/**
 * Whether a line may be taken whole by an insert: it says nothing (`lineWords`), and holds no bookmark or anchor
 * that taking it would lose. `- [ ] ^ship` names a card on a board; it is kept, and the insert goes under it.
 */
export function givesWay(text: string): boolean {
  return lineWords(text) === '' && withoutBookmark(text) === text && anchorSpan(text) === null;
}

/** The syntax nodes a line inside which lazily takes the next line in. */
const HOLDING = new Set(['ListItem', 'BulletList', 'OrderedList', 'Blockquote', 'Table', 'TableRow', 'TableHeader']);

/**
 * Whether a line is part of a list, a quote or a table, which a line of its own under it would join: read from the
 * app's parser where the view has one, and from the line's own lead where it has none (a detached view in a test).
 */
function holds(state: EditorState, line: Line | null): boolean {
  if (!line || !line.text.trim()) return false;
  if (listLead(line.text) || /^\s*>/.test(line.text) || /^\s*\|/.test(line.text)) return true;
  const tree = ensureSyntaxTree(state, line.to, 50) ?? syntaxTree(state);
  for (let node: SyntaxNode | null = tree.resolveInner(line.to, -1); node; node = node.parent) {
    if (HOLDING.has(node.name)) return true;
  }
  return false;
}

function lineBefore(state: EditorState, line: Line): Line | null {
  return line.number > 1 ? state.doc.line(line.number - 1) : null;
}

function lineAfter(state: EditorState, line: Line): Line | null {
  return line.number < state.doc.lines ? state.doc.line(line.number + 1) : null;
}

function lineAtPos(state: EditorState, at: number): Line {
  return state.doc.lineAt(Math.max(0, Math.min(at, state.doc.length)));
}

/**
 * A thing drawn on a line of its own, at the caret's line `at` (see the header). `apart`, for a link drawn as a card
 * (a place, a film, a frame), keeps a blank line from any words above as well as from a block.
 */
export function ownLinePlan(state: EditorState, at: number, text: string, { apart = false }: { apart?: boolean } = {}): Plan {
  const line = lineAtPos(state, at);
  const take = givesWay(line.text);
  const above = take ? lineBefore(state, line) : line;
  const gap = holds(state, above) || (apart && Boolean(above?.text.trim())) ? '\n' : '';
  const insert = take ? `${gap}${text}\n` : `\n${gap}${text}\n`;
  const from = take ? line.from : line.to;
  return { changes: { from, to: line.to, insert }, selection: { anchor: from + insert.length } };
}

/** A block at the caret's line `at`, with `select` saying where the caret goes in it (see the header). */
export function blockPlan(state: EditorState, at: number, text: string, select: BlockSelect): Plan {
  const line = lineAtPos(state, at);
  const take = givesWay(line.text);
  const above = take ? lineBefore(state, line) : line;
  const before = take ? (above?.text.trim() ? '\n' : '') : '\n\n';
  const next = lineAfter(state, line);
  const after = select === 'after' ? '\n' : next?.text.trim() ? '\n' : '';
  const insert = `${before}${text}${after}`;
  const from = take ? line.from : line.to;
  const start = from + before.length;
  const selection = select === 'after' ? { anchor: from + insert.length } : { anchor: start + select.from, head: start + (select.to ?? select.from) };
  return { changes: { from, to: line.to, insert }, selection };
}

/** What a word before the caret ends with that wants a space after it: a letter, a digit, or closing punctuation. */
const SPACE_AFTER = /[\p{L}\p{N}.,:;!?)\]]/u;
/** What a word after the caret starts with that wants a space before it. */
const SPACE_BEFORE = /[\p{L}\p{N}]/u;

/** Words at the caret, spaced from the words either side; the caret after them, or `select` within them. */
export function wordsPlan(state: EditorState, at: number, words: string, select?: { from: number; to?: number }): Plan {
  const before = state.doc.sliceString(Math.max(0, at - 1), at);
  const after = state.doc.sliceString(at, at + 1);
  const lead = SPACE_AFTER.test(before) ? ' ' : '';
  const tail = SPACE_BEFORE.test(after) ? ' ' : '';
  const start = at + lead.length;
  const selection = select ? { anchor: start + select.from, head: start + (select.to ?? select.from) } : { anchor: start + words.length };
  return { changes: { from: at, insert: `${lead}${words}${tail}` }, selection };
}

/** A quote's markers at the start of a line, and the spaces after them. */
const QUOTED = /^\s*(?:>[ \t]*)+/;

/** A line's quote, and a space after it where it has none, for a lead that goes inside it. */
function quoteOf(text: string): string {
  const quote = QUOTED.exec(text)?.[0] ?? '';
  return quote && !/\s$/.test(quote) ? `${quote} ` : quote;
}

/** The kinds of item the + can start. */
export type ItemKind = 'todo' | 'choice' | 'bullet' | 'number';

/** The number of the next step after `line`, when it is a numbered item; 1 otherwise. */
function nextNumber(line: Line | null): number {
  const lead = line ? listLead(line.text) : null;
  const n = lead ? /^(\d+)[.)]$/.exec(lead.marker)?.[1] : undefined;
  return n ? Number(n) + 1 : 1;
}

/** An item's whole lead for `kind`, with `indent` before it and `marker` as the list's own where the kind allows. */
function leadFor(kind: ItemKind, indent: string, marker: string | null, number: number): string {
  const bullet = marker && /^[-*+]$/.test(marker) ? marker : '-';
  if (kind === 'todo') return `${indent}${marker ?? '-'} [ ] `;
  if (kind === 'choice') return `${indent}${bullet} ( ) `;
  if (kind === 'bullet') return `${indent}${bullet} `;
  const numbered = marker && /^\d+[.)]$/.test(marker) ? marker : `${number}.`;
  return `${indent}${numbered} `;
}

/** Whether a lead already is what `kind` would write, so nothing is written and no second box is added. */
function already(kind: ItemKind, lead: NonNullable<ReturnType<typeof listLead>>): boolean {
  const bullet = /^[-*+]$/.test(lead.marker);
  if (kind === 'todo') return lead.done !== null;
  if (kind === 'choice') return lead.picked !== null;
  if (kind === 'bullet') return bullet && lead.done === null && lead.picked === null;
  return !bullet && lead.done === null && lead.picked === null;
}

/**
 * An item started at the caret's line (the + never changes what a line says, which is Style's job):
 *
 * - on an empty item, its lead becomes the kind's, keeping its indent and, where it can, its marker; an item that is
 *   that kind already is left as it is, and the caret goes to its end;
 * - on an empty quote line, the item goes inside the quote;
 * - on an empty line, the item takes the indent of an item above it;
 * - under a line of words, a new line carries it, with the line's quote and, for an item, its indent.
 */
export function itemPlan(state: EditorState, at: number, kind: ItemKind): Plan {
  const line = lineAtPos(state, at);
  const quote = quoteOf(line.text);
  const rest = line.text.slice(Math.min(line.text.length, (QUOTED.exec(line.text)?.[0] ?? '').length));
  const lead = listLead(rest);
  const above = lineBefore(state, line);
  if (lineWords(line.text)) {
    const own = lead ? leadFor(kind, lead.indent, kind === 'number' ? null : lead.marker, nextNumber(line)) : leadFor(kind, '', null, 1);
    const insert = `\n${quote}${own}`;
    return { changes: { from: line.to, insert }, selection: { anchor: line.to + insert.length } };
  }
  if (lead) {
    const leadFrom = line.from + (line.text.length - rest.length);
    if (already(kind, lead)) return { changes: [], selection: { anchor: line.to } };
    const own = leadFor(kind, lead.indent, kind === 'number' ? null : lead.marker, nextNumber(above));
    return { changes: { from: leadFrom, to: leadFrom + lead.wordsAt, insert: own }, selection: { anchor: leadFrom + own.length + (line.to - leadFrom - lead.wordsAt) } };
  }
  if (quote) {
    const own = leadFor(kind, '', null, 1);
    return { changes: { from: line.from, to: line.to, insert: `${quote}${own}` }, selection: { anchor: line.from + quote.length + own.length } };
  }
  const aboveLead = above ? listLead(above.text) : null;
  const own = leadFor(kind, aboveLead?.indent ?? '', null, nextNumber(above));
  return { changes: { from: line.from, to: line.to, insert: own }, selection: { anchor: line.from + own.length } };
}

/** The forms a line takes that are not a list: a heading, a quote, a sum (editor/sums.ts). */
export type LineForm = 'heading' | 'quote' | 'sum';

const FORM_LEADS: Record<LineForm, string> = { heading: '## ', quote: '> ', sum: '= ' };

/**
 * A line's form at the caret's line. On an empty line it is written there; inside a quote it stays inside; an empty
 * item's lead gives way to a heading or a quote, and stays before a sum, which a list item may be. Under a line of
 * words, a new line carries it.
 */
export function formPlan(state: EditorState, at: number, form: LineForm): Plan {
  const line = lineAtPos(state, at);
  const prefix = FORM_LEADS[form];
  const quote = quoteOf(line.text);
  if (lineWords(line.text)) {
    const insert = `\n${form === 'quote' ? '' : quote}${prefix}`;
    return { changes: { from: line.to, insert }, selection: { anchor: line.to + insert.length } };
  }
  const rest = line.text.slice((QUOTED.exec(line.text)?.[0] ?? '').length);
  const lead = listLead(rest);
  if (form === 'quote' && quote) return { changes: [], selection: { anchor: line.to } };
  let insert: string;
  if (form === 'sum' && lead) insert = `${quote}${lead.indent}${lead.marker} ${prefix}`;
  else insert = `${quote}${prefix}`;
  return { changes: { from: line.from, to: line.to, insert }, selection: { anchor: line.from + insert.length } };
}

/** A footnote's reference in words, and its definition's opening at the start of a line. */
const FOOTNOTE_REF = /\[\^(\d+)\]/g;
const FOOTNOTE_DEF = /^\s{0,3}\[\^[^\]\s]+\]:/;

/** A line a footnote's marker may close: words, and not a table's row, a fence or a footnote's own line. */
function annotatable(line: Line | null): line is Line {
  if (!line || !lineWords(line.text)) return false;
  return !/^\s*(\||```|~~~)/.test(line.text) && !FOOTNOTE_DEF.test(line.text);
}

/**
 * A footnote: the next free number, and its line at the end of the note, with the caret on it to write what it says
 * (editor/footnotes.ts draws it raised, with its words on a tap). The number goes where the caret is, as words are
 * put there; but on an empty line, which is where the + beside the line is, it closes the words just above instead,
 * as the Guide writes one (`four hundred[^1]`), since a marker alone on a line is a footnote to nothing.
 */
export function footnotePlan(state: EditorState, at: number): Plan {
  const doc = state.doc.toString();
  const taken = [...doc.matchAll(FOOTNOTE_REF)].map((found) => Number(found[1]));
  const number = Math.max(0, ...taken) + 1;
  const marker = `[^${number}]`;
  const line = lineAtPos(state, at);
  const above = lineWords(line.text) ? null : lineBefore(state, line);
  const words: Plan = annotatable(above) ? { changes: { from: above.from + above.text.trimEnd().length, insert: marker } } : wordsPlan(state, at, marker);
  const { from, insert: inserted } = words.changes as { from: number; insert: string };
  const text = from === doc.length ? `${doc}${inserted}` : doc;
  const last = text.slice(text.lastIndexOf('\n') + 1);
  const gap = !text ? '' : FOOTNOTE_DEF.test(last) ? '\n' : text.endsWith('\n\n') ? '' : text.endsWith('\n') ? '\n' : '\n\n';
  const definition = `${gap}[^${number}]: `;
  const shift = inserted.length;
  return {
    changes: [words.changes, { from: doc.length, insert: definition }],
    selection: { anchor: doc.length + shift + definition.length },
  };
}

/** Dispatches a plan as one step of its own, the caret kept in view while the note has focus. */
export function apply(view: EditorView, plan: Plan, userEvent = 'input.plus'): void {
  view.dispatch({
    changes: plan.changes,
    ...(plan.selection ? { selection: plan.selection } : {}),
    scrollIntoView: view.hasFocus,
    userEvent,
    annotations: isolateHistory.of('full'),
  });
}

// ---- the places kept for writes that come late ------------------------------------------------------------

/**
 * Where writes still coming will go, kept in step with every edit made meanwhile. Saving a picture takes a moment
 * (shrinking, then a trip to Rust), and on Android the caret can move under it - the paste bubble closing moved it
 * into another line on the emulator - and a place waits for its fix, so the place is taken when it is asked for, not
 * when the thing is ready.
 */
export const markSpot = StateEffect.define<{ id: number; pos: number }>();
const clearSpot = StateEffect.define<number>();
const spots = StateField.define<Map<number, number>>({
  create: () => new Map(),
  update(value, tr) {
    let next = value;
    if (tr.docChanged && value.size) next = new Map([...value].map(([id, pos]) => [id, tr.changes.mapPos(pos, 1)]));
    for (const effect of tr.effects) {
      if (effect.is(markSpot)) next = new Map(next).set(effect.value.id, effect.value.pos);
      else if (effect.is(clearSpot)) {
        next = new Map(next);
        next.delete(effect.value);
      }
    }
    return next;
  },
});

/** The kept places, for an editor that takes late writes: installed with the pictures (editor/images.ts). */
export const insertSpots = spots;

let spotIds = 0;

/** Remembers `pos` (the caret by default), for a write that will come later. Answers a handle for it. */
export function reserveSpot(view: EditorView, pos = view.state.selection.main.head): number {
  const id = (spotIds += 1);
  view.dispatch({ effects: markSpot.of({ id, pos }) });
  return id;
}

/** Where a kept place is now, or null when it was let go. */
export function spotAt(view: EditorView, spot: number): number | null {
  return view.state.field(spots, false)?.get(spot) ?? null;
}

/** Forgets a kept place, when the write never came or has landed. */
export function releaseSpot(view: EditorView, spot: number): void {
  if (!view.dom.isConnected && !view.state.field(spots, false)?.has(spot)) return;
  view.dispatch({ effects: clearSpot.of(spot) });
}

/**
 * Whether the person has gone somewhere else since a write was asked for: a focus anywhere outside the note (the Find
 * bar, a sheet's field) makes the token stale, and a write that lands then takes no selection, no scroll and no focus.
 * Focus falling to the page's body, as it does on the way back from a picker, is not somewhere else.
 */
export function focusToken(view: EditorView): { fresh: () => boolean; done: () => void } {
  let stale = false;
  const moved = (event: FocusEvent) => {
    if (event.target instanceof Node && view.dom.contains(event.target)) return;
    stale = true;
  };
  document.addEventListener('focusin', moved, true);
  return {
    fresh: () => !stale,
    done: () => document.removeEventListener('focusin', moved, true),
  };
}

/**
 * A line of its own at a kept place, by `ownLinePlan`, as one step. The caret goes after it only if it is still where
 * it was when the write was asked for; with a stale `token` nothing but the words moves, and no scroll or focus. A
 * caret left on the empty line the thing took is carried past it all the same, or the first letter typed on coming
 * back would go in front of the thing and break it. Answers a kept place at the new line's start, for a name that
 * follows it (`nameLater`); the caller lets it go.
 */
export function insertLineAt(
  view: EditorView,
  spot: number,
  text: string,
  { userEvent, token, apart }: { userEvent?: string; token?: { fresh: () => boolean }; apart?: boolean } = {},
): { spot: number } {
  const pos = spotAt(view, spot) ?? view.state.selection.main.head;
  const main = view.state.selection.main;
  const stayed = main.empty && main.head === pos;
  const fresh = token ? token.fresh() : true;
  const plan = ownLinePlan(view.state, pos, text, { apart });
  const change = plan.changes as { from: number; to: number; insert: string };
  const lineStart = change.from + change.insert.length - text.length - 1;
  const took = givesWay(lineAtPos(view.state, pos).text);
  const moved = fresh && stayed && plan.selection;
  view.dispatch({
    changes: plan.changes,
    ...(moved ? { selection: plan.selection, scrollIntoView: true } : took ? { selection: view.state.selection.map(view.state.changes(plan.changes), 1) } : {}),
    ...(userEvent ? { userEvent } : {}),
    annotations: isolateHistory.of('full'),
  });
  if (fresh && !view.hasFocus && view.dom.isConnected) view.focus();
  return { spot: reserveSpot(view, lineStart) };
}

/**
 * A place's name that came after its line was written with the coordinates: written over them only while that line
 * is still the newest change the note's history holds and nothing waits to be redone, so the first Undo gives back the
 * coordinates and the second takes the line. Anything the person did since - typing, an Undo - keeps the coordinates,
 * or the next Undo would take back a name instead of what they just did. A note live on two devices undoes with Yjs
 * (editor/undoSlot.ts), and there nothing is written. Answers whether it was.
 */
export function nameLater(view: EditorView, spot: number, depth: number, was: string, named: string): boolean {
  const state = view.state;
  if (state.field(historyField, false) === undefined) return false;
  if (undoDepth(state) !== depth || redoDepth(state) !== 0) return false;
  const pos = spotAt(view, spot);
  if (pos === null) return false;
  const line = state.doc.lineAt(Math.min(pos, state.doc.length));
  if (line.from !== pos || line.text !== was) return false;
  view.dispatch({ changes: { from: line.from, to: line.to, insert: named }, userEvent: 'input.plus.drawn', annotations: isolateHistory.of('full') });
  return true;
}

/**
 * Waits for the keyboard to finish the word it holds: CodeMirror keeps a composition only when a change leaves it
 * alone and sets no selection, and every insert sets one, so an insert written into a live composition can lose the
 * word. Resolves on the next `compositionend`, or after `ms`, whichever is first, and at once when nothing is composed.
 */
export function afterComposition(view: EditorView, ms = 300): Promise<void> {
  if (!view.composing) return Promise.resolve();
  return new Promise((resolve) => {
    const done = () => {
      window.clearTimeout(timer);
      view.contentDOM.removeEventListener('compositionend', done);
      resolve();
    };
    const timer = window.setTimeout(done, ms);
    view.contentDOM.addEventListener('compositionend', done);
  });
}
