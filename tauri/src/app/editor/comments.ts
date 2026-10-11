import { StateEffect, StateField, type EditorState, type Extension, type Range } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { Pencil } from '@glacier/icons';
import { countWords, readComments, threadOf, type NoteComments, type Thread } from '../core/comments/format.ts';
import { CommentList } from './CommentCard.tsx';
import { nameOf, type CardPeople } from './commentWords.ts';
import { caretIn, focusMoved, trackFocus } from './drawnBlock.ts';
import styles from './CommentCard.module.css';

/**
 * Comments drawn in the note (docs/SHARED.md, S8; core/comments/format.ts is the format). Matt: "make sure comments
 * were added to the app like we discussed previously".
 *
 * - **The anchor**, `[^c1]`, is drawn as a small round in its author's colour where it sits; a tap on it opens the
 *   thread's card (`CommentHooks.open`). A resolved thread's round is a ring. The caret on the anchor shows it as
 *   written, so it can be edited or taken out by hand, as a drawn block steps aside for its lines (editor/drawnBlock.ts).
 * - **The words round a selection**, `==the words==`, are a highlight already (plugins/marks: the Highlight mark); an
 *   open thread's are washed in its author's colour instead of the highlighter's blue, by setting the highlight's own
 *   colour, `--app-mark`, on a mark around it, and a resolved thread's lose their wash.
 * - **The ```comments fence** is drawn as the list of threads, as a ```query fence is drawn as what it finds
 *   (editor/queries.ts): a tap on a thread opens its card and brings its anchor into view, and the pencil at its head
 *   puts the caret in the fence to show its lines. The caret in the fence shows the lines.
 *
 * Where the editor is given no hooks - a note drawn small on a card, a shared page - none of this is installed, and
 * the anchor and the fence read as the text they are, a footnote's marker and a block of lines.
 */

export interface CommentHooks {
  /** Opens a thread's card. */
  open: (id: string) => void;
  /** Whose colour a handle wears here: a workspace hue, `ink` for none (core/comments/colours.ts). */
  colour: (handle: string) => string;
  /** This person's handle, for "You". */
  me: () => string;
  /** The note's words changed: a card that is open reads its thread again. */
  changed?: () => void;
}

/** The colours changed, or anything else the drawing reads from outside the note: everything is drawn again. */
export const refreshComments = StateEffect.define<null>();

/** A thread's round, where its anchor is. */
class RoundWidget extends WidgetType {
  constructor(
    readonly id: string,
    readonly hue: string,
    readonly resolved: boolean,
    readonly label: string,
    readonly hooks: () => CommentHooks | null,
  ) {
    super();
  }

  eq(other: RoundWidget): boolean {
    return other.id === this.id && other.hue === this.hue && other.resolved === this.resolved && other.label === this.label;
  }

  toDOM(): HTMLElement {
    const round = document.createElement('span');
    round.className = 'cm-commentRound';
    round.dataset.hue = this.hue;
    if (this.resolved) round.dataset.resolved = '';
    round.dataset.comment = this.id;
    round.setAttribute('role', 'button');
    round.setAttribute('aria-label', this.label);
    round.title = this.label;
    // The press is the round's: no caret lands on the anchor under it, which would show it as written.
    round.addEventListener('mousedown', (event) => event.preventDefault());
    round.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.hooks()?.open(this.id);
    });
    return round;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

/** The React roots the drawn fences are in, by their element, so a change redraws the same root. */
const roots = new WeakMap<HTMLElement, Root>();

/** What the drawn list shows, as data: compared to decide whether to draw again. */
interface ListThread {
  id: string;
  head: { by: string; at: string; words: string };
  replies: { by: string; at: string; words: string }[];
  resolved: { by: string; at: string } | null;
}

const asListThread = (thread: Thread): ListThread => ({
  id: thread.id,
  head: { by: thread.head.by, at: thread.head.at, words: thread.head.words },
  replies: thread.replies.map((reply) => ({ by: reply.by, at: reply.at, words: reply.words })),
  resolved: thread.resolved ? { by: thread.resolved.by, at: thread.resolved.at } : null,
});

class ListWidget extends WidgetType {
  readonly key: string;

  constructor(
    readonly threads: readonly ListThread[],
    /** Where the caret goes to show the fence's lines: its first line inside. */
    readonly at: number,
    readonly colours: string,
    readonly hooks: () => CommentHooks | null,
  ) {
    super();
    this.key = `${colours}|${JSON.stringify(threads)}`;
  }

  eq(other: ListWidget): boolean {
    return other.key === this.key && other.at === this.at;
  }

  get estimatedHeight(): number {
    return 60 + this.threads.length * 56;
  }

  toDOM(view: EditorView): HTMLElement {
    const dom = document.createElement('div');
    dom.className = 'cm-commentList';
    // A press in the drawing is the drawing's, as a query's is: no caret lands in the fence under it.
    dom.addEventListener('mousedown', (event) => event.preventDefault());
    const root = createRoot(dom);
    roots.set(dom, root);
    this.draw(root, view);
    return dom;
  }

  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    const root = roots.get(dom);
    if (!root) return false;
    this.draw(root, view);
    return true;
  }

  draw(root: Root, view: EditorView): void {
    const hooks = this.hooks();
    const people: CardPeople = { colour: (handle) => hooks?.colour(handle) ?? 'ink', me: hooks?.me() ?? 'me' };
    root.render(
      createElement(
        'section',
        { className: styles.drawn, 'aria-label': 'Comments' },
        createElement(
          'p',
          { className: styles.drawnHead },
          createElement('span', null, countWords(this.threads)),
          view.state.facet(EditorView.editable)
            ? createElement(
                'button',
                {
                  type: 'button',
                  className: styles.edit,
                  'aria-label': 'Show the comments as written',
                  title: 'Show as written',
                  onClick: () => {
                    view.focus();
                    view.dispatch({ selection: { anchor: this.at }, scrollIntoView: true });
                  },
                },
                createElement(Pencil, { size: 16, strokeWidth: 2.2, 'aria-hidden': true }),
              )
            : null,
        ),
        createElement(CommentList, {
          threads: this.threads,
          people,
          onOpen: (id: string) => {
            // The card, and the anchor brought into view under it: the list is at the foot of the note, the words
            // it is about are not.
            const anchor = readComments(view.state.doc.toString()).anchors.find((each) => each.id === id);
            if (anchor) view.dispatch({ effects: EditorView.scrollIntoView(anchor.from, { y: 'center' }) });
            this.hooks()?.open(id);
          },
        }),
      ),
    );
  }

  destroy(dom: HTMLElement): void {
    const root = roots.get(dom);
    roots.delete(dom);
    // Never in the middle of CodeMirror's update, which may be inside a React render (editor/reactMount.ts).
    if (root) queueMicrotask(() => root.unmount());
  }

  ignoreEvent(): boolean {
    return true;
  }
}

/** The words a thread's anchor is round, delimiters aside; null for an anchor after a line's words, or none. */
export function quoteOf(state: EditorState, comments: NoteComments, id: string): string | null {
  const anchor = comments.anchors.find((each) => each.id === id && each.wash);
  return anchor?.wash ? state.sliceDoc(anchor.wash.from + 2, anchor.wash.to - 2) : null;
}

function decorate(state: EditorState, comments: NoteComments, hooks: () => CommentHooks | null, colours: string): DecorationSet {
  const given = hooks();
  if (!given || !comments.fence) return Decoration.none;
  const decorations: Range<Decoration>[] = [];
  for (const anchor of comments.anchors) {
    const thread = threadOf(comments, anchor.id);
    if (!thread) continue;
    const hue = given.colour(thread.head.by);
    const resolved = thread.resolved !== null;
    if (anchor.wash) {
      decorations.push(
        Decoration.mark({ class: 'cm-commentWash', attributes: { 'data-hue': hue, ...(resolved ? { 'data-resolved': '' } : {}) } }).range(anchor.wash.from, anchor.wash.to),
      );
    }
    if (caretIn(state, anchor.from, anchor.to)) continue;
    const who = nameOf(thread.head.by, { colour: given.colour, me: given.me() });
    const replies = thread.replies.length;
    const label = `Comment by ${who}${replies ? `, ${replies === 1 ? '1 reply' : `${replies} replies`}` : ''}${resolved ? ', resolved' : ''}`;
    decorations.push(Decoration.replace({ widget: new RoundWidget(anchor.id, hue, resolved, label, hooks) }).range(anchor.from, anchor.to));
  }
  const fence = comments.fence;
  const editable = state.facet(EditorView.editable) && !state.readOnly;
  if (comments.threads.length && !(editable && caretIn(state, fence.from, fence.to))) {
    const at = state.doc.line(Math.min(fence.open + 1, state.doc.lines)).from;
    decorations.push(Decoration.replace({ widget: new ListWidget(comments.threads.map(asListThread), at, colours, hooks), block: true }).range(fence.from, fence.to));
  }
  return Decoration.set(decorations, true);
}

interface Drawn {
  comments: NoteComments;
  /** Moves with every refresh, so a colour arriving redraws the rounds. */
  stamp: number;
  decorations: DecorationSet;
}

const theme = EditorView.baseTheme({
  // A small round in the author's colour (`--app-space`, from `data-hue`), raised a little as a footnote's marker is:
  // drawn by its ::before, so the element round it is a box big enough for a thumb.
  '.cm-commentRound': {
    display: 'inline-block',
    padding: '0.22em',
    marginInline: '0.02em',
    verticalAlign: '0.28em',
    lineHeight: '0',
    cursor: 'pointer',
  },
  '.cm-commentRound::before': {
    content: '""',
    display: 'inline-block',
    inlineSize: '0.58em',
    blockSize: '0.58em',
    borderRadius: '50%',
    boxSizing: 'border-box',
    background: 'var(--app-space)',
  },
  // Resolved: a ring, its words kept and its wash gone.
  '.cm-commentRound[data-resolved]::before': {
    background: 'none',
    border: '0.1em solid var(--app-space)',
    opacity: '0.7',
  },
  // The highlight inside is drawn with `--app-mark` (plugins/marks `Highlight`): the author's colour for an open thread.
  '.cm-commentWash': { '--app-mark': 'color-mix(in oklch, var(--app-space) 30%, transparent)' },
  '.cm-commentWash[data-resolved]': { '--app-mark': 'transparent' },
  '.cm-commentList': {
    display: 'block',
    boxSizing: 'border-box',
    // As wide as the note, as a drawn query is (editor/queries.ts).
    inlineSize: 'var(--cm-board-room, 100%)',
    paddingBlock: '0.4em',
    paddingInline: 'var(--cm-board-bleed, var(--app-gutter, 1rem))',
    textIndent: '0',
    cursor: 'default',
  },
});

/**
 * Comments drawn: the anchors as rounds, the selections washed, the fence as the list, with `hooks` saying what a tap
 * opens and whose colour is whose. `hooks` is read when it is used, so the screen's callbacks can change without the
 * editor being made again; `refreshComments` draws everything again when the colours do.
 */
export function noteComments(hooks: () => CommentHooks | null): Extension {
  const field = StateField.define<Drawn>({
    create: (state) => {
      const comments = readComments(state.doc.toString());
      return { comments, stamp: 0, decorations: decorate(state, comments, hooks, '0') };
    },
    update(value, tr) {
      const refreshed = tr.effects.some((effect) => effect.is(refreshComments));
      if (!refreshed && !tr.docChanged && !tr.selection && !tr.reconfigured && !focusMoved(tr)) return value;
      const comments = tr.docChanged ? readComments(tr.state.doc.toString()) : value.comments;
      const stamp = value.stamp + (refreshed ? 1 : 0);
      return { comments, stamp, decorations: decorate(tr.state, comments, hooks, String(stamp)) };
    },
    provide: (state) => EditorView.decorations.from(state, (value) => value.decorations),
  });
  return [
    trackFocus,
    field,
    EditorView.updateListener.of((update) => {
      if (update.docChanged) hooks()?.changed?.();
    }),
    theme,
  ];
}
