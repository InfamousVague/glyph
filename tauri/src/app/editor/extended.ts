import { Facet, RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { shortcodesIn } from '../core/emoji.ts';
import { FENCE, FRONT_MATTER_LINES, frontMatterEnd } from '../core/frontMatter.ts';
import { mathsIn } from '../core/maths.ts';

/**
 * The extended markdown Glyph draws but had no look for.
 *
 * The language already parses more than the app drew (editor/language.ts takes GFM plus subscript, superscript and
 * emoji): `x^2^` and `H~2~O` were plain words with their marks showing, and a GitHub callout - a quote whose first
 * line is `[!NOTE]` - was an ordinary quote. Both are ordinary markdown anywhere else, so a note written in Glyph
 * reads the same in GitHub, Obsidian or a plain text editor, which is the whole point of the format.
 *
 * Nothing is hidden, as everywhere else in the editor: the marks stay, and the words between them take the look. The
 * one exception is a shortcode, which is replaced by its emoji the way a table is replaced by a table - the drawn
 * thing being unmistakably the written thing - and comes back as words while the caret is on its line.
 *
 * What is drawn here, all of it ordinary markdown elsewhere (docs/MARKDOWN.md):
 *
 *   x^2^  H~2~O            raised and lowered runs
 *   > [!NOTE]              a callout, GitHub's own spelling
 *   Term / : the meaning   a definition list, as PHP Markdown Extra writes it; the colon hidden off the caret's line
 *   ---\ntitle: …\n---     front matter, which read as a horizontal rule before
 *   $x^2$  $$ … $$         maths, set as code rather than drawn: a renderer is 280 KB the phone does not need
 *   :tada:                 a shortcode, drawn as its emoji (core/emoji.ts)
 *
 * The front matter is drawn folded as well (`frontMatterFold`): one quiet line naming its keys, "title · authors ·
 * location · place", while the editor is not focused with the caret in the block. A note that says where it was
 * written (core/geotag.ts) carries two more lines above its words, which is where §95's "Not yet" for the visible
 * `authors:` line came due. The caret entering the block, or a tap on the folded line, opens it to the lines as
 * they are; leaving folds it again. A block decoration cannot come from a view plugin (it changes the vertical
 * layout), so the fold is a state field, told of the editor's focus through `focusChangeEffect`. Only where the
 * words can be edited: a read-only page (the shared reader, a note being dictated) shows the lines as they are,
 * since a stranger has no caret to open the fold with. Goal 2 says nothing is folded; DESIGN §134 says why this is,
 * and that it is Matt's to keep or take back.
 *
 * `look:` is not named in the folded line (docs/DESIGN.md §144): it is how the note is drawn, and the drawing says it,
 * so a new reading note would otherwise open on a band that says "look" over its display title. A block that holds only
 * `look` folds to nothing at all, and the note opens on its title; the caret moved into it still opens it.
 *
 * A ticket's front matter is not folded but drawn as its properties, by editor/tickets.ts, which says so through
 * `frontMatterDrawn` (docs/DESIGN.md §157); the caret in it opens it to its lines the same way.
 */

/** The words of a raised or lowered run, by node name: the highlighter gives both the same tag. */
const SCRIPTS: Record<string, string | undefined> = { Superscript: 'cm-sup', Subscript: 'cm-sub' };

/** A definition's line: `: the meaning`, under the term it belongs to. */
const DEFINITION = /^(\s{0,3}:)(\s+\S.*)$/;
/**
 * Which lines the note's front matter covers, as line numbers, or null: what core/frontMatter.ts counts as front
 * matter, so the keys drawn quiet here are the ones the list takes the note's name from. Only the lines the rule can
 * reach are read, and only when the first is a fence.
 */
export function frontMatter(doc: { line: (n: number) => { text: string }; lines: number }): { from: number; to: number } | null {
  if (!FENCE.test(doc.line(1).text)) return null;
  const head = Array.from({ length: Math.min(doc.lines, FRONT_MATTER_LINES) }, (_, n) => doc.line(n + 1).text);
  const end = frontMatterEnd(head);
  return end ? { from: 1, to: end } : null;
}

/** A callout's kind, as GitHub writes it: `> [!NOTE]` on the quote's first line. */
const CALLOUT = /^\s*>\s*\[!(note|tip|important|warning|caution)\]\s*(.*)$/i;

/** The kind of callout a blockquote is, or null for an ordinary quote. */
export function calloutKind(firstLine: string): string | null {
  const found = CALLOUT.exec(firstLine);
  return found ? (found[1] ?? '').toLowerCase() : null;
}

/** A shortcode, drawn as its emoji. The words come back the moment the caret is on the line. */
class EmojiWidget extends WidgetType {
  constructor(
    readonly emoji: string,
    readonly name: string,
  ) {
    super();
  }

  eq(other: EmojiWidget): boolean {
    return other.emoji === this.emoji;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-emoji';
    span.textContent = this.emoji;
    span.title = this.name;
    return span;
  }
}

/** Keys the folded line never names, since the note's own drawing says them: its look. */
const UNSAID = new Set(['look']);

/** The names of the keys a front matter block holds, in order, less the unsaid ones: what the folded line says. */
function keyNames(state: EditorState, front: { from: number; to: number }): string[] {
  const names: string[] = [];
  for (let n = front.from + 1; n < front.to; n += 1) {
    const found = /^\s*([\w.-]+)\s*:/.exec(state.doc.line(n).text);
    if (found && !UNSAID.has(found[1]!.toLowerCase())) names.push(found[1]!);
  }
  return names;
}

/** Whether the block holds keys and every one of them is unsaid: it folds to nothing, not to a line. */
function onlyUnsaid(state: EditorState, front: { from: number; to: number }): boolean {
  let any = false;
  for (let n = front.from + 1; n < front.to; n += 1) {
    const found = /^\s*([\w.-]+)\s*:/.exec(state.doc.line(n).text);
    if (!found) continue;
    if (!UNSAID.has(found[1]!.toLowerCase())) return false;
    any = true;
  }
  return any;
}

/** Whether a selection head sits on one of the block's lines. */
function caretIn(state: EditorState, front: { from: number; to: number }): boolean {
  return state.selection.ranges.some((range) => {
    const n = state.doc.lineAt(range.head).number;
    return n >= front.from && n <= front.to;
  });
}

/** The front matter folded to one line: its keys' names. A tap opens it, by putting the caret on its first key. */
class FrontWidget extends WidgetType {
  constructor(
    readonly keys: readonly string[],
    /** Where the caret goes on a tap: the first key's line. */
    readonly at: number,
  ) {
    super();
  }

  eq(other: FrontWidget): boolean {
    return other.at === this.at && other.keys.length === this.keys.length && other.keys.every((key, i) => key === this.keys[i]);
  }

  toDOM(view: EditorView): HTMLElement {
    const div = document.createElement('div');
    div.className = 'cm-frontFold';
    // The band on a span inside, so it keeps to the gutter as the card above it does; the widget's own box stays
    // margin-free, which is how CodeMirror measures a block widget's height.
    const band = document.createElement('span');
    band.textContent = this.keys.length ? this.keys.join(' · ') : 'front matter';
    div.append(band);
    div.title = 'Front matter. Tap to open it.';
    div.addEventListener('mousedown', (event) => {
      event.preventDefault();
      view.dispatch({ selection: { anchor: this.at }, effects: focusEffect.of(true) });
      view.focus();
    });
    return div;
  }
}

/**
 * A block that holds only unsaid keys, folded to nothing: an empty mark in its place, so the stylesheet can set the
 * title under it as a note's first line (markdown.module.css), with no room above it.
 */
class NoFrontWidget extends WidgetType {
  eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const div = document.createElement('div');
    div.className = 'cm-frontNone';
    div.setAttribute('aria-hidden', 'true');
    return div;
  }
}

/** The editor gained or lost focus: the block is open only while it has it. */
const focusEffect = StateEffect.define<boolean>();

/**
 * Whether another hand draws the front matter, so it is not folded here: a ticket's properties panel
 * (editor/tickets.ts; docs/DESIGN.md §157), which steps aside for the lines itself.
 */
export const frontMatterDrawn = Facet.define<(state: EditorState) => boolean>();

interface Fold {
  focused: boolean;
  decorations: DecorationSet;
}

function foldOf(state: EditorState, focused: boolean): DecorationSet {
  const front = frontMatter(state.doc);
  if (!front || !state.facet(EditorView.editable) || (focused && caretIn(state, front))) return Decoration.none;
  if (state.facet(frontMatterDrawn).some((drawn) => drawn(state))) return Decoration.none;
  const from = state.doc.line(front.from).from;
  const to = state.doc.line(front.to).to;
  const at = state.doc.line(Math.min(front.from + 1, front.to)).from;
  if (onlyUnsaid(state, front)) return Decoration.set(Decoration.replace({ widget: new NoFrontWidget(), block: true }).range(from, to));
  return Decoration.set(Decoration.replace({ widget: new FrontWidget(keyNames(state, front), at), block: true }).range(from, to));
}

const frontFold = StateField.define<Fold>({
  create: (state) => ({ focused: false, decorations: foldOf(state, false) }),
  update(value, tr) {
    let focused = value.focused;
    for (const effect of tr.effects) if (effect.is(focusEffect)) focused = effect.value;
    if (!tr.docChanged && !tr.selection && !tr.reconfigured && focused === value.focused) return value;
    return { focused, decorations: foldOf(tr.state, focused) };
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

/** Whether the front matter is folded to its line now, for a test to ask. */
export function frontMatterFolded(state: EditorState): boolean {
  return state.field(frontFold).decorations.size > 0;
}

function decorate(state: EditorState, from: number, to: number, editing: boolean): DecorationSet {
  const marks: { from: number; to: number; deco: Decoration }[] = [];
  // The lines the caret is on, whose marks are shown as typed, to edit: none in a view nobody is typing in - a read-only
  // one, or one without the focus - whose caret sits at the top unseen. There a shortcode on the first line stayed
  // its name (Matt, of the Academy's emoji lesson: "it should appear when :smile: is done").
  const caretLines = new Set(editing ? state.selection.ranges.map((range) => state.doc.lineAt(range.head).number) : []);

  // The note's own front matter, which the parser reads as a rule and a run of words.
  const front = frontMatter(state.doc);
  if (front) {
    for (let n = front.from; n <= front.to; n += 1) {
      const line = state.doc.line(n);
      marks.push({ from: line.from, to: line.from, deco: Decoration.line({ class: 'cm-front' }) });
    }
  }

  const first = state.doc.lineAt(from).number;
  const last = state.doc.lineAt(to).number;
  for (let n = first; n <= last; n += 1) {
    const line = state.doc.line(n);
    if (front && n >= front.from && n <= front.to) continue;

    // A definition under its term: the meaning hangs under the term, which is set apart. Its colon is how it is
    // written, not how it reads, so off the caret's line it goes, as a heading's hashes do; on it, it is there to edit
    // (Matt, of the Academy's lesson: "Should the colon be after the label instead of on the next line?").
    const definition = DEFINITION.exec(line.text);
    if (definition) {
      marks.push({ from: line.from, to: line.from, deco: Decoration.line({ class: 'cm-definition' }) });
      if (!caretLines.has(n)) {
        const lead = (definition[1] ?? '').length + (/^\s+/.exec(definition[2] ?? '')?.[0].length ?? 0);
        marks.push({ from: line.from, to: line.from + lead, deco: Decoration.replace({}) });
      }
      const above = n > 1 ? state.doc.line(n - 1) : null;
      if (above && above.text.trim() && !DEFINITION.test(above.text)) {
        marks.push({ from: above.from, to: above.from, deco: Decoration.line({ class: 'cm-term' }) });
      }
    }

    // Maths, set as code: read as what it is without carrying a renderer for it. Found by Pandoc's rule (core/maths.ts),
    // so a line with two prices on it is prices.
    for (const maths of mathsIn(line.text, line.from)) marks.push({ from: maths.from, to: maths.to, deco: Decoration.mark({ class: 'cm-maths' }) });

    // A shortcode becomes its emoji, unless the caret is on that line, where the words are wanted.
    if (!caretLines.has(n)) {
      for (const code of shortcodesIn(line.text, line.from)) {
        marks.push({
          from: code.from,
          to: code.to,
          deco: Decoration.replace({ widget: new EmojiWidget(code.emoji, state.doc.sliceString(code.from, code.to)) }),
        });
      }
    }
  }

  syntaxTree(state).iterate({
    from,
    to,
    enter(node) {
      const script = SCRIPTS[node.name];
      if (script) {
        // The words, the delimiters aside: `^` and `~` are one character each.
        const words = { from: node.from + 1, to: node.to - 1 };
        if (words.to > words.from) marks.push({ ...words, deco: Decoration.mark({ class: script }) });
        return false;
      }
      if (node.name !== 'Blockquote') return undefined;
      const first = state.doc.lineAt(node.from);
      const kind = calloutKind(first.text);
      if (!kind) return undefined;
      // `[!NOTE]` is a link label to the parser, and was drawn as one: underlined, in the link's ink. It is the
      // callout's name, so it is drawn as a name.
      const at = first.text.indexOf('[!');
      const shut = first.text.indexOf(']', at);
      if (at >= 0 && shut > at) marks.push({ from: first.from + at, to: first.from + shut + 1, deco: Decoration.mark({ class: 'cm-calloutName' }) });
      const last = state.doc.lineAt(Math.max(node.from, node.to - 1));
      for (let n = first.number; n <= last.number; n += 1) {
        const line = state.doc.line(n);
        marks.push({
          from: line.from,
          to: line.from,
          deco: Decoration.line({ class: n === first.number ? 'cm-callout cm-calloutTop' : 'cm-callout', attributes: { 'data-callout': kind } }),
        });
      }
      return undefined;
    },
  });
  // A line decoration and a mark can start at the same place; the line one must be added first.
  marks.sort((a, b) => a.from - b.from || (a.to === a.from ? -1 : 1) - (b.to === b.from ? -1 : 1));
  const builder = new RangeSetBuilder<Decoration>();
  for (const mark of marks) builder.add(mark.from, mark.to, mark.deco);
  return builder.finish();
}

const theme = EditorView.baseTheme({
  '.cm-sup': { verticalAlign: 'super', fontSize: '0.75em', lineHeight: '1' },
  '.cm-sub': { verticalAlign: 'sub', fontSize: '0.75em', lineHeight: '1' },
  /*
   * A callout is the quote it already is, with its own band of ink down the side and a tinted ground, so the eye
   * takes it as an aside rather than a quotation. The kinds differ only in weight of tint: Glyph is ink and paper,
   * and a wall of coloured boxes is not what a note should look like.
   */
  '.cm-callout': {
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
    borderInlineStart: '3px solid color-mix(in oklch, currentColor 35%, transparent)',
    paddingInlineStart: '0.6em',
  },
  '.cm-callout[data-callout="warning"], .cm-callout[data-callout="caution"]': {
    background: 'color-mix(in oklch, currentColor 7%, transparent)',
    borderInlineStartColor: 'color-mix(in oklch, currentColor 60%, transparent)',
  },
  // The underline belongs to the link span inside, so the name's own children are cleared too.
  '.cm-calloutName, .cm-calloutName *': {
    textDecoration: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    fontSize: '0.82em',
    letterSpacing: '0.08em',
  },
  '.cm-calloutTop': { fontWeight: 'var(--glacier-font-weight-semibold, 600)', paddingBlockStart: '0.25em', borderStartStartRadius: '0.4em' },
  '.cm-callout:not(.cm-calloutTop):last-of-type': { paddingBlockEnd: '0.25em' },

  // Front matter: the note's keys, quiet and set in the note's mono face, and no longer a rule across the page.
  '.cm-front, .cm-front *': {
    fontFamily: 'var(--glacier-font-mono)',
    fontSize: '0.84em',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    textDecoration: 'none',
    fontWeight: 'inherit',
  },
  '.cm-front': { background: 'color-mix(in oklch, currentColor 3%, transparent)' },
  // The front matter folded: its keys' names on one line, in the same quiet face, and a hand for the tap that opens it.
  // A block widget sits outside `.cm-line`, so it takes the lines' side padding itself (markdown.module.css).
  '.cm-frontFold': {
    paddingInline: 'var(--app-gutter, 0)',
    fontFamily: 'var(--glacier-font-mono)',
    fontSize: '0.84em',
    lineHeight: '1.9',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    cursor: 'pointer',
    userSelect: 'none',
  },
  // A label the width of its words, so it reads as the card's and not a band across the page.
  '.cm-frontFold > span': {
    display: 'inline-block',
    maxInlineSize: '100%',
    paddingInline: 'var(--glacier-space-2, 8px)',
    borderRadius: 'var(--glacier-radius-sm, 4px)',
    background: 'color-mix(in oklch, currentColor 3%, transparent)',
  },

  // A definition hangs under its term, the way a glossary sets one.
  '.cm-term': { fontWeight: 'var(--glacier-font-weight-semibold, 600)' },
  // On the line itself, so a room that takes a line's padding away (guide/MarkExample.module.css `.room`) keeps the hang.
  '.cm-line.cm-definition': { paddingInlineStart: '1.2em' },

  // Maths, as code: the delimiters stay, because they are what makes it maths.
  '.cm-maths': { fontFamily: 'var(--glacier-font-mono)', fontSize: '0.92em', color: 'var(--app-ink-2, var(--glacier-text))' },

  '.cm-emoji': { fontSize: '1.05em', lineHeight: '1' },
});

/** The extended markdown drawn as what it is: raised and lowered runs, callouts, definitions, front matter, maths and shortcodes. */
export function extendedMarkdown(): Extension {
  return [
    frontFold,
    EditorView.focusChangeEffect.of((_state, focusing) => focusEffect.of(focusing)),
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;

        constructor(readonly view: EditorView) {
          this.decorations = this.build(view);
        }

        update(update: ViewUpdate) {
          if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) this.decorations = this.build(update.view);
        }

        private build(view: EditorView): DecorationSet {
          const { from, to } = view.viewport;
          return decorate(view.state, from, to, view.hasFocus && view.state.facet(EditorView.editable));
        }
      },
      { decorations: (value) => value.decorations },
    ),
    theme,
  ];
}
