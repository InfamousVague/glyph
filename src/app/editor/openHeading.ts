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
 */

/** The hint in an open first heading. */
export const OPEN_HEADING_HINT = 'A name';

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
