import { RangeSetBuilder, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { syntaxTree } from '@codemirror/language';
import { itemWords, markOf } from '../core/itemLinks.ts';
import { AFTER_MARK } from '../core/itemSyntax.ts';
import { hasMarkDetails } from '../core/markDetails.ts';
import { shortUrl } from '../core/shortUrl.ts';
import { capitalise } from '../core/text.ts';
import { selectedLines } from './lines.ts';
import { detailsArrived, markReads } from './markReads.ts';

/**
 * Links, shortened: `notion.so/att…b3c` in place of the whole address.
 *
 * Matt: "For formatted links in the app don't show the full link path just
 * show the first 3 chars after the tld then a ... and the last 3 chars". A
 * Notion task's address is a hundred characters of slug and id, and set in the
 * note's own type it pushed every other word off the line.
 *
 * The first thing the editor shows in place of what is written, which the
 * rest of it never does (glyphLines.ts), so it is kept to the one case and it
 * steps aside whenever the address might be edited: on the line the caret is
 * on, the address is written out in full, exactly as it is stored. Everywhere
 * else a link's address, in `[words](address)` or said bare, shows as its
 * host, three characters, an ellipsis and three characters, with the whole
 * address as its title for a long press to read. Nothing about the text
 * changes, and a read-only view (the Formatted note) shows every link short.
 *
 * The item mark is the other case (core/itemLinks.ts): a list item that ends
 * with `[notion](address)` is linked to a Notion task, and the whole mark is
 * drawn as one small solid pill with the name on it - the done twin of the
 * outlined suggestion pill (suggestions.ts), so a note reads at a glance:
 * outlined could be a task, solid is one. On the caret's line it, too, is
 * written out in full.
 *
 * Where the mark's plugin reads what it links to (core/markDetails.ts), the
 * mark itself steps aside: the item's row of pills under it says what it is
 * linked to and what that is doing, and opens its menu (editor/linkedRows.ts).
 * The pill here is for a mark whose plugin is off, or one that reads nothing.
 * Either way the details of every linked thing in view are asked for, and
 * their answers drawn, by editor/markReads.ts, which `shortLinks` installs
 * beside it.
 */

/**
 * The mark as one pill with its name on it, for a mark whose plugin is off or reads nothing: where one reads it, the
 * row under the line carries the mark instead (`HiddenMark`, editor/linkedRows.ts), so what the plugin knows is never
 * drawn here. The whole address is its title, for a long press to read.
 */
class ItemMark extends WidgetType {
  constructor(
    readonly name: string,
    readonly url: string,
  ) {
    super();
  }

  eq(other: ItemMark): boolean {
    return other.name === this.name && other.url === this.url;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-itemMark';
    const name = document.createElement('span');
    name.className = 'cm-itemMark-name';
    name.textContent = capitalise(this.name);
    span.append(name);
    span.title = this.url;
    return span;
  }

  /** A tap lands the caret here, which writes the mark out in full for editing. */
  ignoreEvent(): boolean {
    return false;
  }
}

/** Where the row under the item carries the mark, the mark itself draws nothing. */
class HiddenMark extends WidgetType {
  eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-itemMarkHidden';
    return span;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

class ShortLink extends WidgetType {
  constructor(readonly url: string) {
    super();
  }

  eq(other: ShortLink): boolean {
    return other.url === this.url;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-shortLink';
    span.textContent = shortUrl(this.url);
    span.title = this.url;
    return span;
  }

  /** A tap lands the caret here, which writes the address out in full for editing. */
  ignoreEvent(): boolean {
    return false;
  }
}

/** Whether what follows a link is nothing, or only a board's anchor (core/boards.ts): the link is then the item's mark. */
function lastOnLine(after: string): boolean {
  return AFTER_MARK.test(after);
}

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const editable = view.state.facet(EditorView.editable);
  // The lines the selection touches show their links whole, while the note is being written.
  const active = editable && view.hasFocus ? selectedLines(view.state) : new Set<number>();
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter: (node) => {
        if (node.name === 'Link') {
          // A mark: the link is the last thing on an item's line and its words are one name.
          const text = view.state.sliceDoc(node.from, node.to);
          const mark = markOf(text);
          const line = view.state.doc.lineAt(node.from);
          if (mark && text === `[${mark.name}](${mark.url})` && lastOnLine(line.text.slice(node.to - line.from)) && itemWords(line.text) !== null) {
            if (!active.has(line.number)) {
              const widget = hasMarkDetails(mark.name) ? new HiddenMark() : new ItemMark(mark.name, mark.url);
              builder.add(node.from, node.to, Decoration.replace({ widget }));
            }
            return false;
          }
          return;
        }
        if (node.name !== 'URL') return;
        const url = view.state.sliceDoc(node.from, node.to);
        if (shortUrl(url).length >= url.length - 1) return;
        if (active.has(view.state.doc.lineAt(node.from).number)) return;
        builder.add(node.from, node.to, Decoration.replace({ widget: new ShortLink(url) }));
      },
    });
  }
  return builder.finish();
}

/** Addresses shown short and marks as pills, drawn again whenever what they show may have moved. */
const shortLinksPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(readonly view: EditorView) {
      this.decorations = decorate(view);
    }

    update(update: ViewUpdate) {
      // While an IME composes, the line's DOM must not be replaced (glyphLines.ts).
      if (update.view.composing) {
        if (update.docChanged) this.decorations = this.decorations.map(update.changes);
        return;
      }
      const arrived = update.transactions.some((tr) => tr.effects.some((effect) => effect.is(detailsArrived)));
      if (arrived || update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        this.decorations = decorate(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

const shortLinksTheme = EditorView.baseTheme({
  '.cm-shortLink': {
    color: 'var(--glacier-text-muted)',
    textDecoration: 'none',
    whiteSpace: 'nowrap',
  },
  /* The mark: a solid pill, the same size and place as the suggestion it grew from. */
  '.cm-itemMark': {
    display: 'inline-block',
    // An item line hangs its wrapped lines with a negative text-indent, which an
    // inline-block inherits and applies to its own first line: the pill shrank to
    // three pixels and its word spilled out to the left. Not here.
    textIndent: '0',
    marginInlineStart: '0.6em',
    padding: '0 0.6em',
    borderRadius: '999px',
    background: 'var(--app-ink, currentColor)',
    color: 'var(--app-paper, #fff)',
    fontSize: '0.68em',
    lineHeight: '1.7',
    verticalAlign: '0.15em',
    whiteSpace: 'nowrap',
    userSelect: 'none',
  },
  '.cm-itemMark-name': {
    opacity: '0.72',
  },
});

/**
 * Link addresses shown short, and item marks as pills, away from the caret's line; and the reads that keep the rows
 * under linked lines current (editor/markReads.ts), which `still` stops - a note drawn small on a card is drawn from
 * what is known.
 */
export function shortLinks({ still = false }: { still?: boolean } = {}): Extension {
  return [shortLinksPlugin, markReads({ still }), shortLinksTheme];
}
