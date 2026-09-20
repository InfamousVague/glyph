import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Editor } from '../editor/Editor.tsx';
import { NotePeek } from '../notes/NotePeek.tsx';
import { openLink } from '../core/linkPreview.ts';
import { shortUrl } from '../core/shortUrl.ts';
import { edgePath, fileTitle, isImageFile, movedNode, newTextNode, NEW_CARD, paintOf, withNode, withoutNode, type Canvas, type CanvasNode } from './jsonCanvas.ts';
import { clampScale, FIT_ROOM, fitted, zoomedAt, type View } from './viewport.ts';
import styles from './CanvasView.module.css';

/**
 * A canvas drawn (docs/CANVAS.md): cards where the file puts them, lines between them, an infinite page under it all
 * that two fingers or a trackpad move and pinch. The first slice (Matt, 2026-09-20: "read and draw an Obsidian file"
 * first, editing second), so nothing here changes the canvas: it reads it faithfully, and a card that is a note or a
 * link opens on a tap.
 *
 * The drawing is one element, the world, moved and scaled with a transform: the cards sit at their own pixel
 * positions inside it, and the lines are one SVG laid over them in the same pixels, so a pinch scales everything at
 * once and nothing is laid out twice. The transform is written straight to the element as the fingers move, not
 * through React, so a pan is a style change and nothing else.
 *
 * A card of words is the note's own editor, read-only and in its peek mode, the way a home card draws a note
 * (notes/NotePeek.tsx) - so a card draws the same way a note does, and an editor is only made once a card is near the
 * screen, since a canvas may hold fifty and each costs a frame.
 *
 * The second slice edits (Matt: "continue progress on canvases"). A double-tap on the page makes a card of words
 * there, open with the keyboard up (Matt's choice, docs/CANVAS.md: "double-tap empty space ... Obsidian's move"), and
 * the + tool makes one mid-screen. A press held on a card lifts it, and it goes where the finger goes - the way a
 * board's card and a tab are moved (editor/boards.ts, notes/NoteTabs.tsx), so one habit serves the whole app; a plain
 * drag still pans, so a finger on a card never moves it by mistake. A double-tap on a card of words opens it to be
 * written in, its editor in the note's own mode and the words going straight into the canvas; a card open that way
 * can be taken off. Moving, opening and taking off were not put to Matt, so those are the app's conventions, not his
 * choices. Every change is the whole canvas handed back (`onChange`), which the note writes into its body as the
 * spec's JSON, so a canvas edited here still opens in Obsidian. Without `onChange` the canvas is read-only, as the
 * first slice was.
 *
 * Nothing is captured until a press has become a drag, so a tap still reaches the card it landed on; two fingers
 * move the page whatever they are on.
 */

export interface CanvasWiki {
  /** Whether a note by that title exists: a note card is drawn as a note, or as one waiting to be written. */
  known: (title: string) => boolean;
  /** Opens the note by that title, at an anchor when the card names one. */
  open: (title: string, at?: string) => void;
  /** The note's body by title, for drawing it small on its card; null where the note is not there. */
  body?: (title: string) => string | null;
}

export interface CanvasViewProps {
  canvas: Canvas;
  dark: boolean;
  wiki?: CanvasWiki;
  className?: string;
  /** The canvas after a change - a card moved, made, written in or taken off. Absent, the canvas cannot be changed. */
  onChange?: (canvas: Canvas) => void;
}

/** How far off the screen a card's editor is made, in screen pixels. */
const NEAR_PX = 300;
/** How far a finger moves before a press is a drag rather than a tap, in screen pixels. */
const SLOP_PX = 4;
/** Two taps this close in time and place are a double-tap: a new card on the page, or a card of words opened. */
const DOUBLE_MS = 350;
const DOUBLE_PX = 24;
/** How long a press stays put before it lifts the card under it rather than panning the page: the boards' own wait. */
const HOLD_MS = 220;

/** Where two fingers are, as one point between them and the distance apart; one finger is its point and no distance. */
function grip(pointers: Map<number, { x: number; y: number }>): { x: number; y: number; distance: number } {
  const [a, b] = [...pointers.values()];
  if (!a) return { x: 0, y: 0, distance: 0 };
  if (!b) return { x: a.x, y: a.y, distance: 0 };
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, distance: Math.hypot(a.x - b.x, a.y - b.y) };
}

export function CanvasView({ canvas, dark, wiki, className, onChange }: CanvasViewProps) {
  const host = useRef<HTMLDivElement>(null);
  /*
   * The canvas as it is being changed: the one handed in, with a card part-way through a drag on top of it. Every
   * change goes out through `onChange` and comes back as the next `canvas`; between the two, and while a finger is
   * still moving a card, this is what is drawn.
   */
  const [live, setLive] = useState(canvas);
  useEffect(() => setLive(canvas), [canvas]);
  const editable = !!onChange;
  /** The card of words open to be written in, by id. */
  const [editing, setEditing] = useState<string | null>(null);
  const change = useCallback(
    (next: Canvas) => {
      setLive(next);
      onChange?.(next);
    },
    [onChange],
  );
  const world = useRef<HTMLDivElement>(null);
  const view = useRef<View>({ x: FIT_ROOM, y: FIT_ROOM, scale: 1 });
  /** Whether a finger or a wheel has moved the view: until then, a screen that changes size fits the canvas again. */
  const touched = useRef(false);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  /** Where the fingers took hold and what the view was then: every move is measured from here, not from the last. */
  const hold = useRef<{ view: View; x: number; y: number; distance: number } | null>(null);
  /** Whether this press became a drag: the tap that would follow it is not one, and no card opens. */
  const dragged = useRef(false);
  /** The card a held press lifted, and where the press was: the card follows the finger from there. */
  const carrying = useRef<{ node: CanvasNode; x: number; y: number } | null>(null);
  /** The wait for a press on a card to become a hold; cleared by movement or by letting go. */
  const holdTimer = useRef(0);
  /** The card lifted, for its look while it is carried. */
  const [lifted, setLifted] = useState<string | null>(null);
  /** The last tap, and what it was on, for telling a double-tap. */
  const lastTap = useRef<{ at: number; x: number; y: number; on: string | null } | null>(null);

  const apply = useCallback(() => {
    const el = world.current;
    if (!el) return;
    const { x, y, scale } = view.current;
    el.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
  }, []);

  const fit = useCallback(() => {
    const el = host.current;
    if (!el) return;
    view.current = fitted(canvas, el.clientWidth, el.clientHeight);
    touched.current = false;
    apply();
  }, [canvas, apply]);

  // The canvas opens fitted to the screen, and follows the screen's size until it has been moved by hand.
  useEffect(() => {
    fit();
    const el = host.current;
    if (!el || typeof ResizeObserver === 'undefined') return undefined;
    const watcher = new ResizeObserver(() => {
      if (!touched.current) fit();
    });
    watcher.observe(el);
    return () => watcher.disconnect();
  }, [fit]);

  const takeHold = () => {
    const at = grip(pointers.current);
    hold.current = { view: { ...view.current }, x: at.x, y: at.y, distance: at.distance };
  };

  /** The point of the canvas under a point of the screen. */
  const under = (clientX: number, clientY: number) => {
    const rect = host.current?.getBoundingClientRect();
    const { x, y, scale } = view.current;
    return { x: (clientX - (rect?.left ?? 0) - x) / scale, y: (clientY - (rect?.top ?? 0) - y) / scale };
  };

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement;
    // Typing in a card that is open: the press is the editor's, for its caret and its selection.
    if (editing && target.closest('[data-editing]')) return;
    // A press is a tap until it moves: a tap on a card that opens something is the card's, and taking the pointer
    // here would take its click with it. It is only captured once it has become a drag.
    window.clearTimeout(holdTimer.current);
    if (!pointers.current.size) {
      dragged.current = false;
      carrying.current = null;
      // One finger on a card, on a canvas that can change: held still for a moment, it lifts the card.
      const id = editable ? target.closest<HTMLElement>('[data-card]')?.dataset.card : undefined;
      const node = id ? live.nodes.find((n) => n.id === id) : undefined;
      if (node) {
        const at = { x: event.clientX, y: event.clientY };
        const pointerId = event.pointerId;
        holdTimer.current = window.setTimeout(() => {
          if (pointers.current.size !== 1 || !pointers.current.has(pointerId)) return;
          carrying.current = { node, x: at.x, y: at.y };
          dragged.current = true;
          setLifted(node.id);
          try {
            host.current?.setPointerCapture(pointerId);
          } catch {
            // Already gone: nothing to hold.
          }
        }, HOLD_MS);
      }
    } else carrying.current = null;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    takeHold();
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!pointers.current.has(event.pointerId) || !hold.current) return;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const start = hold.current;
    const now = grip(pointers.current);
    if (!dragged.current) {
      if (pointers.current.size < 2 && Math.hypot(now.x - start.x, now.y - start.y) < SLOP_PX) return;
      // Moved before the hold: a pan, and the card stays where it is.
      window.clearTimeout(holdTimer.current);
      dragged.current = true;
      // The drag is the page's now, wherever the pointer goes: off a card, out of the window and back.
      for (const id of pointers.current.keys()) {
        try {
          host.current?.setPointerCapture(id);
        } catch {
          // A pointer already gone: nothing to hold.
        }
      }
    }
    // A card being carried: it follows the finger in the canvas's own pixels, and the page stays put.
    const carried = carrying.current;
    if (carried && pointers.current.size < 2) {
      const scale = view.current.scale;
      const { node } = carried;
      setLive((was) => withNode(was, movedNode(node, node.x + (event.clientX - carried.x) / scale, node.y + (event.clientY - carried.y) / scale)));
      return;
    }
    touched.current = true;
    // The point of the canvas that was under the fingers stays under them, whatever they do: a second finger's
    // spread scales about that point, and one finger's move carries it along.
    const scale = start.distance > 0 && now.distance > 0 ? clampScale((start.view.scale * now.distance) / start.distance) : start.view.scale;
    const underX = (start.x - start.view.x) / start.view.scale;
    const underY = (start.y - start.view.y) / start.view.scale;
    view.current = { x: now.x - underX * scale, y: now.y - underY * scale, scale };
    apply();
  };

  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    window.clearTimeout(holdTimer.current);
    if (!pointers.current.delete(event.pointerId)) return;
    // A card let go where it was carried to: the canvas is handed on with it there.
    const carried = carrying.current;
    if (carried) {
      carrying.current = null;
      setLifted(null);
      const scale = view.current.scale;
      change(withNode(live, movedNode(carried.node, carried.node.x + (event.clientX - carried.x) / scale, carried.node.y + (event.clientY - carried.y) / scale)));
    }
    if (pointers.current.size) takeHold();
    else hold.current = null;
  };

  /*
   * A tap closes whatever card was open. A second tap close on the heels of the first, in the same place, is a
   * double-tap: on the page it makes a new card of words there, open to be written in; on a card of words it opens
   * that card. A note card and a link card open on a single tap, as they did (`Card`), so a double-tap is kept for
   * the two things a single tap cannot mean.
   */
  const onClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!editable || dragged.current) return;
    const target = event.target as HTMLElement;
    if (target.closest('[data-editing]') || target.closest('button')) return;
    if (editing) setEditing(null);
    const id = target.closest<HTMLElement>('[data-card]')?.dataset.card;
    const node = id ? live.nodes.find((n) => n.id === id) : undefined;
    if (node && node.type !== 'text') return;
    const now = performance.now();
    const last = lastTap.current;
    const again = !!last && last.on === (node?.id ?? null) && now - last.at < DOUBLE_MS && Math.hypot(event.clientX - last.x, event.clientY - last.y) < DOUBLE_PX;
    if (again) {
      lastTap.current = null;
      if (node) setEditing(node.id);
      else addCard(event.clientX, event.clientY);
      return;
    }
    lastTap.current = { at: now, x: event.clientX, y: event.clientY, on: node?.id ?? null };
  };

  /** A new card of words centred on a point of the screen, open to be written in. */
  const addCard = (clientX: number, clientY: number) => {
    const at = under(clientX, clientY);
    const card = newTextNode(at.x - NEW_CARD.width / 2, at.y - NEW_CARD.height / 2);
    change(withNode(live, card));
    setEditing(card.id);
  };

  /** A new card in the middle of the screen, from the + tool: for a mouse with no double-tap habit, and for a reader. */
  const addCardHere = () => {
    const el = host.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    addCard(rect.left + rect.width / 2, rect.top + rect.height / 2);
  };

  const writeCard = (id: string, text: string) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node?.type === 'text' && node.text !== text) change(withNode(live, { ...node, text }));
  };

  const removeCard = (id: string) => {
    if (editing === id) setEditing(null);
    change(withoutNode(live, id));
  };

  // Escape closes the card being written in.
  useEffect(() => {
    if (!editing) return undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setEditing(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editing]);

  // The click at the end of a drag is the drag's, not a card's: it goes no further.
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!dragged.current) return;
    event.stopPropagation();
    event.preventDefault();
  };

  // A wheel pans, as it does in Obsidian; with the modifier held - which is also what a trackpad pinch arrives as -
  // it zooms about the pointer. Attached by hand: React's wheel is passive, and the page must not scroll instead.
  useEffect(() => {
    const el = host.current;
    if (!el) return undefined;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      touched.current = true;
      const was = view.current;
      if (event.ctrlKey || event.metaKey) {
        const rect = el.getBoundingClientRect();
        view.current = zoomedAt(was, event.clientX - rect.left, event.clientY - rect.top, was.scale * Math.exp(-event.deltaY * 0.01));
      } else {
        view.current = { ...was, x: was.x - event.deltaX, y: was.y - event.deltaY };
      }
      apply();
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [apply]);

  const edges = useMemo(() => live.edges.map((edge) => ({ edge, path: edgePath(live, edge) })).filter((e) => e.path), [live]);

  return (
    <div
      ref={host}
      className={className ? `${styles.canvas} ${className}` : styles.canvas}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onClickCapture={onClickCapture}
      onClick={onClick}
      role={editable ? undefined : 'img'}
      aria-label={`A canvas of ${live.nodes.length} cards`}
      data-editable={editable || undefined}
    >
      <div ref={world} className={styles.world}>
        {live.nodes.map((node) => (
          <Card
            key={node.id}
            node={node}
            dark={dark}
            wiki={wiki}
            root={host}
            editing={editing === node.id}
            lifted={lifted === node.id}
            onWrite={editable ? writeCard : undefined}
            onRemove={editable ? removeCard : undefined}
          />
        ))}
        <svg className={styles.edges} aria-hidden="true">
          {edges.map(({ edge, path }) => {
            const paint = paintOf(edge.color);
            const style = paint && 'hex' in paint ? { '--app-space': paint.hex } : undefined;
            return (
              <g key={edge.id} className={styles.edge} data-hue={paint && 'hue' in paint ? paint.hue : undefined} style={style as React.CSSProperties}>
                <path className={styles.line} d={path!.d} />
                {path!.fromHead ? <path className={styles.head} d={path!.fromHead} /> : null}
                {path!.toHead ? <path className={styles.head} d={path!.toHead} /> : null}
                {edge.label ? (
                  <text className={styles.label} x={path!.mid.x} y={path!.mid.y}>
                    {edge.label}
                  </text>
                ) : null}
              </g>
            );
          })}
        </svg>
      </div>
      <div className={styles.tools}>
        {editable ? (
          <button type="button" className={`app-word ${styles.tool}`} onClick={addCardHere} aria-label="Add a card of words">
            + Card
          </button>
        ) : null}
        <button type="button" className={`app-word ${styles.tool}`} onClick={fit} aria-label="Fit the whole canvas on the screen">
          Fit
        </button>
      </div>
    </div>
  );
}

interface CardProps {
  node: CanvasNode;
  dark: boolean;
  wiki?: CanvasWiki;
  /** The canvas, which is what "near the screen" is measured against. */
  root: React.RefObject<HTMLDivElement | null>;
  /** Open to be written in: a card of words shows its editor as the note does, taking every tap and key. */
  editing?: boolean;
  /** Lifted by a held press and following the finger. */
  lifted?: boolean;
  onWrite?: (id: string, text: string) => void;
  onRemove?: (id: string) => void;
}

function Card({ node, dark, wiki, root, editing = false, lifted = false, onWrite, onRemove }: CardProps) {
  const paint = paintOf(node.color);
  // Opened to be written in: the keyboard comes up with it (Matt: "a text card appears under the fingers, keyboard up").
  const opened = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!editing) return undefined;
    const timer = window.setTimeout(() => opened.current?.querySelector<HTMLElement>('.cm-content')?.focus(), 0);
    return () => window.clearTimeout(timer);
  }, [editing]);
  const hue = paint && 'hue' in paint ? paint.hue : undefined;
  const place: React.CSSProperties = { left: node.x, top: node.y, width: node.width, height: node.height };
  if (paint && 'hex' in paint) (place as Record<string, string>)['--app-space'] = paint.hex;

  if (node.type === 'group') {
    return (
      <div className={styles.group} style={place} data-hue={hue} data-card={node.id} data-lifted={lifted || undefined}>
        {node.label ? <span className={styles.groupLabel}>{node.label}</span> : null}
      </div>
    );
  }

  if (node.type === 'text') {
    return (
      <div className={styles.card} style={place} data-hue={hue} data-card={node.id} data-editing={editing || undefined} data-lifted={lifted || undefined}>
        {editing ? (
          // Open: the note's own editor in its own mode, the words going straight into the canvas as they are typed.
          <div ref={opened} className={styles.words}>
            <Editor value={node.text} onChange={(text) => onWrite?.(node.id, text)} dark={dark} assist display="mixed" placeholder="Write something." grow />
          </div>
        ) : (
          <Near root={root} className={styles.words}>
            <Editor value={node.text} onChange={noop} dark={dark} assist={false} readOnly display="formatted" peek grow />
          </Near>
        )}
        {editing && onRemove ? (
          <button type="button" className={styles.remove} onClick={() => onRemove(node.id)} aria-label="Take this card off the canvas">
            ×
          </button>
        ) : null}
      </div>
    );
  }

  if (node.type === 'link') {
    // An address, opened the way a link in a note is (core/linkPreview.ts): the phone's browser, not a window of ours.
    return (
      <a
        className={`${styles.card} ${styles.linkCard}`}
        style={place}
        data-hue={hue}
        data-card={node.id}
        data-lifted={lifted || undefined}
        href={node.url}
        onClick={(event) => {
          event.preventDefault();
          void openLink(node.url);
        }}
      >
        <span className={styles.cardTitle}>{shortUrl(node.url)}</span>
        <span className={styles.cardHint}>{node.url}</span>
      </a>
    );
  }

  // A file: a note by that name in Glyph, or a picture, or a file Glyph does not have.
  const title = fileTitle(node.file);
  const picture = isImageFile(node.file);
  const known = !picture && !!wiki?.known(title);
  const body = known ? (wiki?.body?.(title) ?? null) : null;
  const at = node.subpath ? node.subpath.slice(1) : undefined;
  return (
    <div
      className={`${styles.card} ${styles.fileCard}`}
      style={place}
      data-hue={hue}
      data-card={node.id}
      data-lifted={lifted || undefined}
      data-waiting={known || picture ? undefined : ''}
      role={picture ? undefined : 'button'}
      tabIndex={picture ? undefined : 0}
      onClick={picture ? undefined : () => wiki?.open(title, at)}
      onKeyDown={picture ? undefined : (event) => (event.key === 'Enter' || event.key === ' ') && wiki?.open(title, at)}
    >
      <span className={styles.cardTitle}>{title}</span>
      {body ? (
        <Near root={root}>
          <NotePeek body={body} className={styles.cardPeek} />
        </Near>
      ) : (
        <span className={styles.cardHint}>{picture ? 'A picture, in the vault it came from' : known ? '' : 'Not in Glyph yet'}</span>
      )}
    </div>
  );
}

/** Its children once the card is near the screen, and a blank until then: an editor costs a frame, a blank nothing. */
function Near({ root, className, children }: { root: React.RefObject<HTMLDivElement | null>; className?: string; children: React.ReactNode }) {
  const el = useRef<HTMLDivElement>(null);
  const [near, setNear] = useState(() => typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const me = el.current;
    if (!me || near || typeof IntersectionObserver === 'undefined') return undefined;
    const watcher = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) setNear(true);
      },
      { root: root.current, rootMargin: `${NEAR_PX}px` },
    );
    watcher.observe(me);
    return () => watcher.disconnect();
  }, [near, root]);
  return (
    <div ref={el} className={className ? `${styles.near} ${className}` : styles.near}>
      {near ? children : null}
    </div>
  );
}

function noop(): void {
  // Read-only: nothing typed comes back.
}
