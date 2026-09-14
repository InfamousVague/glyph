import { RangeSetBuilder, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { syntaxTree } from '@codemirror/language';
import { shortUrl } from '../core/shortUrl.ts';

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
 */

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

/** The lines the selection touches: their links are shown whole. */
function activeLines(view: EditorView): Set<number> {
  const lines = new Set<number>();
  for (const range of view.state.selection.ranges) {
    const first = view.state.doc.lineAt(range.from).number;
    const last = view.state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n += 1) lines.add(n);
  }
  return lines;
}

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const editable = view.state.facet(EditorView.editable);
  const active = editable && view.hasFocus ? activeLines(view) : new Set<number>();
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter: (node) => {
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

const shortLinksPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = decorate(view);
    }

    update(update: ViewUpdate) {
      // While an IME composes, the line's DOM must not be replaced (glyphLines.ts).
      if (update.view.composing) {
        if (update.docChanged) this.decorations = this.decorations.map(update.changes);
        return;
      }
      if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
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
});

export { shortUrl };

/** Link addresses shown short away from the caret's line. */
export function shortLinks(): Extension {
  return [shortLinksPlugin, shortLinksTheme];
}
