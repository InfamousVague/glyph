import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';

/**
 * A link from one note to another, written the way every notes app writes it (docs/MARKDOWN.md):
 *
 *   The deposit is in [[The cabin trip]].
 *
 * This is the piece that makes a pile of notes into something you can walk through, and it is the one bit of
 * formatting that is really a feature. A name that matches a note's title opens it; a name that matches nothing is
 * drawn as a name waiting to be written, and tapping it makes that note and opens it. Either way the words are the
 * title, so the note reads the same anywhere else.
 *
 * Matching is by the title as a person would say it: case and punctuation aside, so "the cabin trip" finds "The
 * cabin trip." Nothing is stored: the link IS the title, and renaming a note is a matter of the words in it.
 */

/** `[[Another note]]`: the brackets, and the title between them. */
const WIKI = /\[\[([^\]\n]{1,120})\]\]/g;

export interface WikiLink {
  /** The whole thing, brackets included. */
  from: number;
  to: number;
  /** The title as it is written in the note. */
  title: string;
}

/** Every wiki link in the text, counting positions from `offset`. */
export function wikiLinksIn(text: string, offset = 0): WikiLink[] {
  const found: WikiLink[] = [];
  WIKI.lastIndex = 0;
  for (let match = WIKI.exec(text); match; match = WIKI.exec(text)) {
    const title = (match[1] ?? '').trim();
    if (title) found.push({ from: offset + match.index, to: offset + match.index + match[0].length, title });
  }
  return found;
}

/** A title as it is matched: what a person said, not what they typed. */
export function sameTitle(one: string, two: string): boolean {
  const plain = (text: string) =>
    text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  return plain(one) === plain(two) && plain(one) !== '';
}

export interface WikiOptions {
  /** Whether a note by that title exists; a link to one that does not is drawn as waiting. */
  known: (title: string) => boolean;
  /** Opens the note by that title, making it first where there is none. */
  open: (title: string) => void;
}

function decorate(state: EditorState, known: (title: string) => boolean): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const link of wikiLinksIn(state.doc.toString())) {
    builder.add(link.from, link.to, Decoration.mark({ class: known(link.title) ? 'cm-wiki' : 'cm-wiki cm-wikiNew', attributes: { title: link.title } }));
  }
  return builder.finish();
}

const theme = EditorView.baseTheme({
  '.cm-wiki, .cm-wiki *': {
    textDecoration: 'underline',
    textDecorationStyle: 'solid',
    textUnderlineOffset: '0.2em',
    textDecorationThickness: '0.06em',
    textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)',
    cursor: 'pointer',
  },
  // A note that is not written yet: the same words, dashed, so it reads as a place to go rather than a mistake.
  '.cm-wikiNew, .cm-wikiNew *': { textDecorationStyle: 'dashed', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
});

/** Links between notes: `[[Title]]` opens that note, or makes it. */
export function wikiLinks(given: WikiOptions | null): Extension {
  if (!given) return [];
  const options: WikiOptions = given;
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;

        constructor(view: EditorView) {
          this.decorations = decorate(view.state, options.known);
        }

        update(update: ViewUpdate) {
          if (update.docChanged || update.viewportChanged) this.decorations = decorate(update.state, options.known);
        }
      },
      {
        decorations: (value) => value.decorations,
        eventHandlers: {
          mousedown(event, view) {
            const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
            if (pos === null) return false;
            const line = view.state.doc.lineAt(pos);
            const link = wikiLinksIn(line.text, line.from).find((found) => pos >= found.from && pos <= found.to);
            if (!link) return false;
            // The press does not reach the editor, so the caret stays where it was and the note simply opens.
            event.preventDefault();
            options.open(link.title);
            return true;
          },
        },
      },
    ),
    theme,
  ];
}
