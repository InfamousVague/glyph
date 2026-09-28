import { RangeSetBuilder, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { svgElement } from '../art/svg.ts';
import { onBack } from '../core/back.ts';
import { IMAGE_READY, imageUrl } from '../core/images.ts';
import { lengthText, videoOfLine, type VideoLine } from '../core/videoRefs.ts';
import { filmGone, filmHere, filmsPlay, videoUrl, type FilmHere } from '../core/videos.ts';
import { forEachLineOutsideFences, selectedLines } from './lines.ts';
import styles from './videos.module.css';

/**
 * A film in the words, drawn (core/videoRefs.ts): its card under a line that is only a poster linked to a film, and the
 * line folded to its words, "video 0:12", away from the caret.
 *
 *   [![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)
 *
 * The line keeps its Markdown, as a picture's and a place's do, and the card is a block widget under it. The card is
 * the poster, the film's own frame, so it has the film's shape, with the length in a chip at its foot. Where the film
 * can play, a paper disc sits in the middle and a Full screen chip in the corner; a tap plays it with sound, over the
 * poster, the same size, and another tap pauses it; a line of ink along the foot says how far it has played. It never
 * plays by itself, loops or plays under a hovering pointer, and one film plays at a time. There are no native controls:
 * the generated WebView client refuses the platform's full screen, so Full screen is a layer of the page, black in both
 * themes, which the back gesture closes, handing the time back.
 *
 * Who is reading decides what else is said (editor/Editor.tsx `videos`, read once):
 *
 * - `play`, the note screen: one HEAD asks whether the film is on this phone (core/videos.ts `filmHere`) before the
 *   disc is drawn. Not here, "This video isn’t on this phone." takes the disc's place, before anyone taps; a binary
 *   older than the films says to update; any device but an Android phone says the film stays on the phone it was
 *   added on.
 * - `still`, everywhere else the owner reads (a notebook read straight through, a note drawn small): the poster and
 *   its length, and the same words for another device or an older binary, and nothing asked.
 * - `shared`, a shared page: "Only a still from it is shared.", since the reader never had the film.
 *
 * The picture widget steps aside for these lines (editor/images.ts), so the poster is drawn once.
 */

export type VideoMode = 'play' | 'still' | 'shared';

/**
 * What a card knows of its film: where it stands (core/videos.ts `filmHere`), `shared` on a shared page, and `quiet`
 * while nothing needs saying (the film is here to play, or the question is still out).
 */
export type CardState = Exclude<FilmHere, 'here'> | 'shared' | 'quiet';

/** The words under a card, for whoever reads it; none while all is well. */
export function videoWords(mode: VideoMode, state: CardState, ms: number | null): string {
  const length = ms === null ? '' : ` of ${lengthText(ms)}`;
  if (mode === 'shared' || state === 'shared') return `A video${length}. Only a still from it is shared.`;
  if (state === 'missing') return 'This video isn’t on this phone.';
  if (state === 'update') return 'Update Ghost.md to play this video.';
  if (state === 'elsewhere') return `A video${length}. It stays on the phone it was added on.`;
  return '';
}

/** How tall a poster is for its width, learned as each is drawn: a card drawn again is laid out at its own shape. */
const shapes = new Map<string, number>();

/** A film just picked says its shape before its poster has loaded (NoteScreen's `addVideo`). */
export function rememberShape(poster: string, width: number, height: number): void {
  if (width > 0 && height > 0) shapes.set(poster, height / width);
}

/** The film playing now, anywhere on the page: starting another pauses it. */
let playing: HTMLVideoElement | null = null;

function play(film: HTMLVideoElement): void {
  if (playing && playing !== film) playing.pause();
  playing = film;
  void film.play().catch(() => undefined);
}

/** Lucide's marks, in the app's strokes: play, maximise and close. */
function mark(name: 'play' | 'full' | 'close', size: string): SVGSVGElement {
  const paths = {
    play: ['M6 3 20 12 6 21z'],
    full: ['M15 3h6v6', 'M9 21H3v-6', 'M21 3l-7 7', 'M3 21l7-7'],
    close: ['M18 6 6 18', 'm6 6 12 12'],
  }[name];
  const svg = svgElement<SVGSVGElement>(
    'svg',
    {
      viewBox: '0 0 24 24',
      'aria-hidden': 'true',
      fill: name === 'play' ? 'currentColor' : 'none',
      stroke: 'currentColor',
      'stroke-width': 2,
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    },
    ...paths.map((d) => svgElement('path', { d })),
  );
  svg.style.inlineSize = size;
  svg.style.blockSize = size;
  return svg;
}

function button(className: string, label: string, ...children: Element[]): HTMLButtonElement {
  const element = document.createElement('button');
  element.type = 'button';
  element.className = className;
  element.setAttribute('aria-label', label);
  element.append(...children);
  return element;
}

/** How far a film has played, as the line along the foot. */
function follow(film: HTMLVideoElement, line: HTMLElement): () => void {
  const move = () => {
    const done = film.duration > 0 ? film.currentTime / film.duration : 0;
    line.style.transform = `scaleX(${Math.min(1, Math.max(0, done))})`;
  };
  film.addEventListener('timeupdate', move);
  film.addEventListener('seeked', move);
  move();
  return () => {
    film.removeEventListener('timeupdate', move);
    film.removeEventListener('seeked', move);
  };
}

/**
 * The film full screen: a layer of the page, black, the film contained in it from where the card's had got to, a tap
 * to pause or play, and a white close. The back gesture (and Escape) closes it, and the time goes back to the card.
 */
export function openFullScreen(name: string, from: number, label: string, done: (time: number) => void): () => void {
  const layer = document.createElement('div');
  layer.className = styles.layer ?? '';
  layer.setAttribute('role', 'dialog');
  layer.setAttribute('aria-modal', 'true');
  layer.setAttribute('aria-label', label);
  const film = document.createElement('video');
  film.className = styles.film ?? '';
  film.playsInline = true;
  film.preload = 'metadata';
  film.src = videoUrl(name);
  if (from > 0) film.currentTime = from;
  const line = document.createElement('span');
  line.className = styles.progress ?? '';
  const close = button(styles.close ?? '', 'Close', mark('close', '1.5rem'));
  layer.append(film, close, line);
  const unfollow = follow(film, line);
  let open = true;
  const shut = () => {
    if (!open) return;
    open = false;
    off();
    unfollow();
    film.pause();
    if (playing === film) playing = null;
    done(film.currentTime);
    film.removeAttribute('src');
    film.load();
    layer.remove();
  };
  const off = onBack(() => {
    shut();
    return true;
  });
  film.addEventListener('click', () => (film.paused ? play(film) : film.pause()));
  close.addEventListener('click', shut);
  document.body.append(layer);
  close.focus({ preventScroll: true });
  play(film);
  return shut;
}

const cleanups = new WeakMap<HTMLElement, () => void>();

class VideoWidget extends WidgetType {
  constructor(
    readonly film: VideoLine,
    readonly mode: VideoMode,
  ) {
    super();
  }

  eq(other: VideoWidget): boolean {
    return other.film.poster === this.film.poster && other.film.video === this.film.video && other.film.ms === this.film.ms && other.mode === this.mode;
  }

  /** The poster's own height at the page's width where it is known, and a wide film's where it is not, and the words. */
  get estimatedHeight(): number {
    if (typeof window === 'undefined') return 240;
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    const shape = shapes.get(this.film.poster) ?? 9 / 16;
    return Math.min(window.innerHeight * 0.6, (window.innerWidth - 3 * rem) * shape) + 3 * rem;
  }

  toDOM(): HTMLElement {
    const { poster, video, ms } = this.film;
    const length = ms === null ? '' : lengthText(ms);
    const card = document.createElement('div');
    card.className = `cm-videoCard ${styles.card ?? ''}`;
    card.dataset.mode = this.mode;
    const frame = document.createElement('div');
    frame.className = styles.frame ?? '';
    const still = document.createElement('img');
    still.className = styles.poster ?? '';
    still.alt = length ? `A video of ${length}` : 'A video';
    still.decoding = 'async';
    const learn = () => {
      if (still.naturalWidth) rememberShape(poster, still.naturalWidth, still.naturalHeight);
    };
    still.addEventListener('load', learn);
    const draw = () => {
      const url = imageUrl(poster);
      if (url && still.getAttribute('src') !== url) still.src = url;
    };
    draw();
    // A browser's pictures arrive from storage after the first draw (core/images.ts).
    window.addEventListener(IMAGE_READY, draw);
    frame.append(still);
    if (length) {
      const chip = document.createElement('span');
      chip.className = styles.length ?? '';
      chip.textContent = length;
      chip.setAttribute('aria-hidden', 'true');
      frame.append(chip);
    }
    const words = document.createElement('p');
    words.className = styles.words ?? '';
    card.append(frame, words);

    let film: HTMLVideoElement | null = null;
    let unfollow: () => void = () => undefined;
    let alive = true;
    const say = (state: CardState) => {
      card.dataset.film = state;
      words.textContent = videoWords(this.mode, state, ms);
    };
    /** The card's film let go: paused, emptied so the WebView stops reading it, and gone from the frame. */
    const letGo = () => {
      unfollow();
      if (!film) return;
      film.pause();
      if (playing === film) playing = null;
      film.removeAttribute('src');
      film.load();
      film.remove();
      film = null;
    };
    cleanups.set(card, () => {
      alive = false;
      window.removeEventListener(IMAGE_READY, draw);
      letGo();
    });

    if (this.mode !== 'play') {
      // Nothing is asked of a still or a shared page but which device this is.
      say(this.mode === 'shared' ? 'shared' : 'quiet');
      if (this.mode === 'still') {
        void filmsPlay().then((where) => {
          if (alive && where !== 'phone') say(where);
        });
      }
      return card;
    }

    say('quiet');
    const line = document.createElement('span');
    line.className = styles.progress ?? '';
    const label = length ? `Play the video, ${length}` : 'Play the video';
    const disc = document.createElement('span');
    disc.className = styles.disc ?? '';
    disc.append(mark('play', '1.35rem'));
    const toggle = button(styles.toggle ?? '', label, disc);
    const full = button(styles.full ?? '', 'Full screen', mark('full', '1.05rem'));

    /**
     * The film went since it was asked about: the card says so, and plays nothing. Only the card's own film, while it
     * is the card's: one let go is emptied, which a WebView may answer with an error of its own.
     */
    const gone = (event: Event) => {
      if (!film || event.target !== film) return;
      filmGone(video);
      letGo();
      toggle.remove();
      full.remove();
      line.remove();
      delete card.dataset.playing;
      delete card.dataset.started;
      say('missing');
    };

    const filmNow = (): HTMLVideoElement => {
      if (film) return film;
      const made = document.createElement('video');
      made.className = styles.film ?? '';
      made.preload = 'metadata';
      made.playsInline = true;
      made.src = videoUrl(video);
      made.addEventListener('play', () => {
        card.dataset.playing = '';
        card.dataset.started = '';
        toggle.setAttribute('aria-label', 'Pause');
      });
      made.addEventListener('pause', () => {
        delete card.dataset.playing;
        toggle.setAttribute('aria-label', label);
      });
      made.addEventListener('error', gone);
      frame.insertBefore(made, toggle);
      unfollow = follow(made, line);
      film = made;
      return made;
    };

    toggle.addEventListener('click', () => {
      const now = filmNow();
      if (now.paused) play(now);
      else now.pause();
    });
    full.addEventListener('click', () => {
      const from = film?.currentTime ?? 0;
      film?.pause();
      openFullScreen(video, from, length ? `The video, ${length}, full screen` : 'The video, full screen', (time) => {
        if (!alive) return;
        filmNow().currentTime = time;
        card.dataset.started = '';
      });
    });

    void filmHere(video).then((where) => {
      if (!alive) return;
      say(where === 'here' ? 'quiet' : where);
      if (where === 'here') frame.append(toggle, full, line);
    });
    return card;
  }

  destroy(dom: HTMLElement): void {
    cleanups.get(dom)?.();
    cleanups.delete(dom);
  }

  /** The card's taps are its own: the editor does not move the caret under them. */
  ignoreEvent(): boolean {
    return true;
  }
}

function cardsOf(state: EditorState, mode: VideoMode): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  forEachLineOutsideFences(state.doc, (line) => {
    const film = videoOfLine(line.text);
    if (film) builder.add(line.to, line.to, Decoration.widget({ widget: new VideoWidget(film, mode), block: true, side: 1 }));
  });
  return builder.finish();
}

/** A block widget's height has to be known before layout, so the cards come from a field, as pictures do. */
function cardField(mode: VideoMode) {
  return StateField.define<DecorationSet>({
    create: (state) => cardsOf(state, mode),
    update(value, tr) {
      return tr.docChanged ? cardsOf(tr.state, mode) : value;
    },
    provide: (field) => EditorView.decorations.from(field),
  });
}

/** The `[![` and the `](image/…)](video/…)` of a video line, as ranges of the document: the alt is what reads. */
function foldsOf(from: number, text: string): { from: number; to: number }[] {
  const found = /\[!\[([^\]\n]*)\]\(image\/[^)\s]*\)\]\(video\/[^)\s]*\)/.exec(text);
  if (!found) return [];
  const open = from + found.index;
  const close = open + 3 + (found[1]?.length ?? 0);
  return [
    { from: open, to: open + 3 },
    { from: close, to: open + found[0].length },
  ];
}

const hidden = Decoration.replace({});

function foldAll(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const editable = view.state.facet(EditorView.editable);
  // The lines the selection touches show their films whole, while the note is being written (editor/links.ts).
  const active = editable && view.hasFocus ? selectedLines(view.state) : new Set<number>();
  const doc = view.state.doc;
  for (const { from, to } of view.visibleRanges) {
    for (let line = doc.lineAt(from); ; line = doc.line(line.number + 1)) {
      if (!active.has(line.number) && videoOfLine(line.text)) for (const fold of foldsOf(line.from, line.text)) builder.add(fold.from, fold.to, hidden);
      if (line.to >= to || line.number >= doc.lines) break;
    }
  }
  return builder.finish();
}

/** The video lines folded to their words off the caret, looked at again whenever what they show may have moved. */
const folds = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = foldAll(view);
    }
    update(update: ViewUpdate) {
      // While an IME composes, a line's DOM must not be replaced (editor/glyphLines.ts).
      if (update.view.composing) {
        if (update.docChanged) this.decorations = this.decorations.map(update.changes);
        return;
      }
      if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) this.decorations = foldAll(update.view);
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

/** Films in the words: a card under each line as `mode` says, and the lines folded to their words. Read once. */
export function videoCards(mode: VideoMode): Extension {
  return [cardField(mode), folds];
}
