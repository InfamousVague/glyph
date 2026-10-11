import { type EditorState, type Extension, type Line } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { frontMatter } from './extended.ts';
import styles from './markdown.module.css';

/**
 * What goes in a note's open first heading, said in it (docs/DESIGN.md §144): `A name`, quiet, at the heading's own
 * size, after its marks, gone at the first letter. A note started from a template whose name is the person's to write
 * opens on `# ` with the caret in it (notes/noteTemplates.ts), and an empty heading draws nothing formatted and a lone
 * `#` in Markdown: four of the six templates' cards read as blank at the top. It is the per-line cousin of the editor's
 * own placeholder, which says `Write something.` on an empty note.
 *
 * Only the note's first line of words, the one that names it: an empty `## ` further down is a heading being written,
 * and says nothing. Nothing is written into the note: the words are a widget, and not in the file.
 *
 * And a reading note's lead line (`leadLine`, `look: reading`, core/look.ts): the first paragraph after its title set a
 * step larger, in the second ink, with a little less leading, as a magazine sets its standfirst. Being a ratio of
 * `--app-body` it scales on a template's card as it does in the note. While the line under the title is empty and
 * nothing below it has words, that line says `A line that says what it is about.`, quiet, so the card shows the
 * typography and the note starts with nothing to delete.
 */

/** The hint in an open first heading. */
export const OPEN_HEADING_HINT = 'A name';
/** The hint on a reading note's empty lead line. */
export const LEAD_HINT = 'A line that says what it is about.';

const HEADING_SIZE = [styles.h1, styles.h1, styles.h2, styles.h3, styles.h4, styles.h5, styles.h6];

/** The note's first line of words: the first line after its front matter with anything on it. */
export function firstWordsLine(state: EditorState): Line | null {
  const front = frontMatter(state.doc);
  for (let n = front ? front.to + 1 : 1; n <= state.doc.lines; n += 1) {
    const line = state.doc.line(n);
    if (line.text.trim()) return line;
  }
  return null;
}

/** The first line of words when it is a heading with no words (`# `, `##`), and its level; else null. */
export function openFirstHeading(state: EditorState): { line: Line; level: number } | null {
  const line = firstWordsLine(state);
  const open = line ? /^ {0,3}(#{1,6})\s*$/.exec(line.text) : null;
  return line && open ? { line, level: open[1]!.length } : null;
}

/**
 * Whether the caret is on the line that names the note: its first line of words, with no words of its own yet. A blank
 * note's line 1, or an open first heading (`# `). The + beside the line writes the minute's name there, not the
 * stamp (editor/addRows.ts), since what goes there is the note's name and its file's.
 */
export function onNamingLine(state: EditorState): boolean {
  const { main } = state.selection;
  if (!main.empty) return false;
  const line = state.doc.lineAt(main.head);
  if (line.text.trim() && !/^ {0,3}#{1,6}\s*$/.test(line.text)) return false;
  const front = frontMatter(state.doc);
  if (front && line.number <= front.to) return false;
  const words = firstWordsLine(state);
  return words === null || words.number >= line.number;
}

class HintWidget extends WidgetType {
  constructor(
    readonly words: string,
    readonly size: string,
  ) {
    super();
  }

  eq(other: HintWidget): boolean {
    return other.words === this.words && other.size === this.size;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = `cm-openHint ${this.size}`;
    span.textContent = this.words;
    span.setAttribute('aria-hidden', 'true');
    return span;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

function hints(state: EditorState): DecorationSet {
  const open = openFirstHeading(state);
  if (!open) return Decoration.none;
  const size = HEADING_SIZE[open.level] ?? styles.h1 ?? '';
  return Decoration.set(Decoration.widget({ widget: new HintWidget(OPEN_HEADING_HINT, size), side: 1 }).range(open.line.to));
}

const theme = EditorView.baseTheme({
  // As quiet as the editor's own placeholder, and never in the way of a tap on the line.
  '.cm-openHint': {
    color: 'var(--glacier-text-subtle)',
    pointerEvents: 'none',
    userSelect: 'none',
  },
});

/** `A name` in an open first heading. */
export function openHeading(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;

        constructor(view: EditorView) {
          this.decorations = hints(view.state);
        }

        update(update: ViewUpdate) {
          if (update.docChanged) this.decorations = hints(update.state);
        }
      },
      { decorations: (value) => value.decorations },
    ),
    theme,
  ];
}

/** A line a lead paragraph cannot be: a heading, a list, a quote, a fence, a table, a rule or a picture. */
const NOT_PROSE = /^\s*(#{1,6}(\s|$)|[-*+]\s|\d+[.)]\s|>|```|~~~|\||(-{3,}|\*{3,}|_{3,})\s*$|!\[)/;

/**
 * The lead: the first paragraph after the note's first line of words when that is a heading, as the lines it covers;
 * and the line under the title that says what goes there, when that line is empty and nothing below it has words.
 */
export function leadOf(state: EditorState): { lines: Line[]; hint: Line | null } {
  const title = firstWordsLine(state);
  if (!title || !/^ {0,3}#{1,6}(\s|$)/.test(title.text)) return { lines: [], hint: null };
  let n = title.number + 1;
  while (n <= state.doc.lines && !state.doc.line(n).text.trim()) n += 1;
  if (n > state.doc.lines) {
    // Nothing under the title yet: the line under it, where the caret goes after Enter, says what goes there.
    return { lines: [], hint: title.number < state.doc.lines ? state.doc.line(title.number + 1) : null };
  }
  const lines: Line[] = [];
  for (; n <= state.doc.lines; n += 1) {
    const line = state.doc.line(n);
    if (!line.text.trim() || NOT_PROSE.test(line.text)) break;
    lines.push(line);
  }
  return { lines, hint: null };
}

const leadMark = Decoration.line({ class: 'cm-lead' });

function leads(state: EditorState): DecorationSet {
  const { lines, hint } = leadOf(state);
  if (hint) return Decoration.set([leadMark.range(hint.from), Decoration.widget({ widget: new HintWidget(LEAD_HINT, ''), side: 1 }).range(hint.from)], true);
  return Decoration.set(lines.map((line) => leadMark.range(line.from)));
}

const leadTheme = EditorView.baseTheme({
  // A step up from the words, the kit's xl over its lg, in the second ink.
  '.cm-line.cm-lead': {
    fontSize: 'calc(var(--app-body) * 1.2)',
    lineHeight: '1.4',
    color: 'var(--app-ink-2, var(--glacier-text))',
  },
});

/** A reading note's lead line under its title, and what it says while it is empty. */
export function leadLine(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;

        constructor(view: EditorView) {
          this.decorations = leads(view.state);
        }

        update(update: ViewUpdate) {
          if (update.docChanged) this.decorations = leads(update.state);
        }
      },
      { decorations: (value) => value.decorations },
    ),
    leadTheme,
    theme,
  ];
}
