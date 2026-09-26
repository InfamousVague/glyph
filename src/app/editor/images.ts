import { RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet } from '@codemirror/view';
import { failureText } from '../core/failure.ts';
import { IMAGE_READY, IMAGE_REF, imageMarkdown, imageUrl, saveImageFile } from '../core/images.ts';
import styles from './markdown.module.css';

/**
 * Pictures shown in the editor.
 *
 * A line holding `![caption](image/<name>)` keeps its markdown - dimmed, like
 * every other mark, and editable - and the picture itself is a block widget
 * under the line. Nothing is hidden or replaced, so the caret behaves as it
 * does on any line, deleting the line removes the picture, and the source a
 * person sees is the source that is saved.
 *
 * A state field rather than a view plugin: CodeMirror only takes block
 * widgets from a field, because a plugin's decorations may depend on the
 * viewport and a block's height has to be known before layout. The whole
 * document is scanned; pictures are rare and notes are short.
 */

class ImageWidget extends WidgetType {
  constructor(
    readonly name: string,
    readonly caption: string,
    /** Bumped when a picture becomes loadable, so the widget is rebuilt. */
    readonly generation: number,
  ) {
    super();
  }

  eq(other: ImageWidget): boolean {
    return other.name === this.name && other.caption === this.caption && other.generation === this.generation;
  }

  toDOM(): HTMLElement {
    const figure = document.createElement('figure');
    figure.className = styles.figure ?? '';
    const img = document.createElement('img');
    img.alt = this.caption;
    img.loading = 'lazy';
    img.decoding = 'async';
    const url = imageUrl(this.name);
    if (url) img.src = url;
    else figure.dataset.waiting = '';
    figure.appendChild(img);
    return figure;
  }

  ignoreEvent(): boolean {
    return false;
  }
}

/** A picture became loadable (browser storage answered): rebuild the widgets. */
const refreshImages = StateEffect.define<null>();
let generation = 0;

function decorate(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (let n = 1; n <= state.doc.lines; n += 1) {
    const line = state.doc.line(n);
    for (const match of line.text.matchAll(IMAGE_REF)) {
      const name = match[2] ?? '';
      if (!name) continue;
      builder.add(line.to, line.to, Decoration.widget({ widget: new ImageWidget(name, match[1] ?? '', generation), block: true, side: 1 }));
      break;
    }
  }
  return builder.finish();
}

const imageField = StateField.define<DecorationSet>({
  create: decorate,
  update(decorations, tr) {
    if (tr.docChanged || tr.effects.some((e) => e.is(refreshImages))) return decorate(tr.state);
    return decorations;
  },
  provide: (field) => EditorView.decorations.from(field),
});

/** Hears a browser picture arrive from storage and asks the field to look again. */
const imageReady = ViewPlugin.fromClass(
  class {
    private readonly onReady = () => {
      generation += 1;
      this.view.dispatch({ effects: refreshImages.of(null) });
    };
    constructor(readonly view: EditorView) {
      window.addEventListener(IMAGE_READY, this.onReady);
    }
    destroy() {
      window.removeEventListener(IMAGE_READY, this.onReady);
    }
  },
);

/**
 * Where pictures still being saved will go, kept in step with every edit made
 * meanwhile. Saving takes a moment (shrinking, then a trip to Rust), and on
 * Android the caret can move under it - the paste bubble closing moved it into
 * another line on the emulator - so the place is taken when the paste or the
 * pick happens, not when the picture is ready.
 */
const markSpot = StateEffect.define<{ id: number; pos: number }>();
const clearSpot = StateEffect.define<number>();
const spots = StateField.define<Map<number, number>>({
  create: () => new Map(),
  update(value, tr) {
    let next = value;
    if (tr.docChanged && value.size) {
      next = new Map([...value].map(([id, pos]) => [id, tr.changes.mapPos(pos, 1)]));
    }
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
let spotIds = 0;

/** Remembers the caret now, for a picture that will arrive later. Answers a handle for `insertImageAt`. */
export function reserveImageSpot(view: EditorView): number {
  const id = (spotIds += 1);
  view.dispatch({ effects: markSpot.of({ id, pos: view.state.selection.main.head }) });
  return id;
}

/** Puts a picture where `reserveImageSpot` was called, however the note changed since. */
export function insertImageAt(view: EditorView, spot: number, name: string): void {
  const pos = view.state.field(spots).get(spot) ?? view.state.selection.main.head;
  insertImage(view, name, pos);
  view.dispatch({ effects: clearSpot.of(spot) });
}

/** Forgets a reserved place, when the picture never came. */
export function releaseImageSpot(view: EditorView, spot: number): void {
  view.dispatch({ effects: clearSpot.of(spot) });
}

/**
 * A pasted picture: taken out of the paste before CodeMirror sees it, kept, and
 * put in at the caret the same way Photo does. Text in the same paste (a
 * picture copied from a web page often carries its URL as text too) is
 * dropped: the picture is what was meant. A paste with no picture is left to
 * CodeMirror as usual. What goes wrong is reported through `onImageError`.
 */
function pasteImages(onError: (message: string) => void): Extension {
  return EditorView.domEventHandlers({
    paste(event, view) {
      const files = [...(event.clipboardData?.files ?? [])].filter((file) => file.type.startsWith('image/'));
      if (!files.length) {
        // Some keyboards put a picture on the clipboard as an item rather than a file.
        const items = [...(event.clipboardData?.items ?? [])].filter((item) => item.kind === 'file' && item.type.startsWith('image/'));
        for (const item of items) {
          const file = item.getAsFile();
          if (file) files.push(file);
        }
      }
      if (!files.length) return false;
      event.preventDefault();
      const spot = reserveImageSpot(view);
      void (async () => {
        for (const file of files) {
          try {
            insertImageAt(view, spot, await saveImageFile(file));
            // A second picture in the same paste goes after the first.
            view.dispatch({ effects: markSpot.of({ id: spot, pos: view.state.selection.main.head }) });
          } catch (failure) {
            onError(failureText(failure));
          }
        }
        releaseImageSpot(view, spot);
      })();
      return true;
    },
  });
}

/** Pictures in the editor: shown under their lines, and pasted in from the clipboard. */
export function inlineImages(onImageError: (message: string) => void = () => undefined): Extension {
  return [imageField, imageReady, spots, pasteImages(onImageError)];
}

/**
 * Puts a picture into the note on a line of its own, under the line holding
 * `at` (the caret by default), and leaves the caret on the line after it so
 * typing carries on below the picture. A line is never split: a caret in the
 * middle of a sentence - or of another picture's markdown - puts the picture
 * after that whole line. On an empty line it takes the line.
 */
export function insertImage(view: EditorView, name: string, at = view.state.selection.main.head): void {
  const line = view.state.doc.lineAt(Math.min(at, view.state.doc.length));
  const empty = !line.text.trim();
  const from = empty ? line.from : line.to;
  const text = `${empty ? '' : '\n'}${imageMarkdown(name)}\n`;
  view.dispatch({
    changes: { from, to: empty ? line.to : line.to, insert: text },
    selection: { anchor: from + text.length },
    scrollIntoView: true,
  });
  view.focus();
}
