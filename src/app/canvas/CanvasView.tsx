import { Ghost } from '../art/Ghost.tsx';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { LocateFixed, Maximize, Plus, Spline } from '@glacier/icons';
import { IMAGE_READY, pickImage, saveImageFile } from '../core/images.ts';
import { useRedraw } from '../core/useRedraw.ts';
import { AddSheet, type AddStep } from './AddSheet.tsx';
import { useCamera } from './camera.ts';
import { Card } from './Card.tsx';
import { ownPicture } from './cardLooks.ts';
import {
  CHART_CARD,
  joined,
  labelledEdge,
  labelledGroup,
  NEW_CARD,
  newEdge,
  newFileNode,
  newLinkNode,
  newPictureNode,
  newTextNode,
  resizedNode,
  TABLE_CARD,
  withEdge,
  withNode,
  withoutEdge,
  withoutNode,
} from './edits.ts';
import type { Point } from './geometry.ts';
import { useGestures } from './gestures.ts';
import type { Canvas, CanvasEdge, CanvasNode } from './jsonCanvas.ts';
import { LineLayer } from './LineLayer.tsx';
import { edgePaths, type EdgePath } from './lines.ts';
import { LineWords } from './LineWords.tsx';
import { Minimap } from './Minimap.tsx';
import styles from './CanvasView.module.css';

/**
 * A canvas drawn (docs/CANVAS.md): cards where the file puts them, lines between them, an infinite page under it all
 * that two fingers or a trackpad move and pinch. The first slice (Matt, 2026-09-20: "read and draw an Obsidian file"
 * first, editing second) read the file faithfully and opened a note card or a link on a tap; without `onChange` the
 * canvas is still that, read-only, as a note's `![[Title]]` frame and the reader page draw it.
 *
 * The drawing is one element, the world, moved and scaled with a transform: the cards sit at their own pixel
 * positions inside it (canvas/Card.tsx), and the lines are one SVG laid over them in the same pixels (LineLayer.tsx),
 * so a pinch scales everything at once and nothing is laid out twice. Where the screen is, and what moves it, is the
 * camera (camera.ts); what the fingers do is the gestures (gestures.ts). This file holds the canvas as it is being
 * changed, the edits, and the page they are drawn on.
 *
 * The second slice edits (Matt: "continue progress on canvases"). A double-tap on the page makes a card of words
 * there, open with the keyboard up (Matt's choice, docs/CANVAS.md: "double-tap empty space ... Obsidian's move"), and
 * the + tool makes one mid-screen. A press held on a card lifts it, and it goes where the finger goes. A double-tap on
 * a card of words opens it to be written in, its editor in the note's own mode and the words going straight into the
 * canvas; a card open that way can be taken off. Moving, opening and taking off were not put to Matt, so those are
 * the app's conventions, not his choices. Every change is the whole canvas handed back (`onChange`), which the note
 * writes into its body as the spec's JSON, so a canvas edited here still opens in Obsidian.
 *
 * Lines (the third slice, Matt's first pick): the Line tool turns the next two taps into a line, from the first
 * card tapped to the second, with an arrow at its end and its sides worked out from where the cards are; a tap on a
 * line picks it, and a picked line shows its words to be written and a cross to take it off (LineWords.tsx). A tool
 * rather than a drag from a card's edge, because a finger has no hover to find an edge dot by, and the two taps read
 * the same on a phone and with a mouse.
 *
 * Sizes and groups (the fourth slice): a card open to be written in has a corner to drag that resizes it, no smaller
 * than a word and a cross; a held press on a group lifts it with everything wholly inside it (choice 5); a double-tap
 * on a group opens its name to be written, and a cross there takes the group off - the cards in it stay.
 *
 * More ways to add (the fifth slice, choice 8, and the seventh): the + is a sheet (AddSheet.tsx) - words, a note
 * chosen by its title, a web address, a picture from the phone or the computer kept by the picture store the notes
 * use (core/images.ts), a chart that starts as a Mermaid diagram, and a table - and a note dragged in from the
 * sidebar, or a picture file dropped from the computer, lands as a card where it is dropped. The tools are a floating
 * toolbar of icons at the bottom left, and the map sits at the bottom right.
 *
 * Navigation (the sixth, choice 10): a tap on a card's title zooms to the card, Shift+1 fits the whole canvas and
 * Shift+2 zooms to the card open or picked, both as buttons too, and a minimap in the corner (Minimap.tsx) draws
 * every card small with the screen's box over them; a tap on it goes there.
 */

export interface CanvasWiki {
  /** Whether a note by that title exists: a note card is drawn as a note, or as one waiting to be written. */
  known: (title: string) => boolean;
  /** Opens the note by that title, at an anchor when the card names one. */
  open: (title: string, at?: string) => void;
  /** The note's body by title, for drawing it small on its card; null where the note is not there. */
  body?: (title: string) => string | null;
  /** Every note's title, for choosing one to put on the canvas as a card. */
  titles?: () => string[];
}

export interface CanvasViewProps {
  canvas: Canvas;
  dark: boolean;
  wiki?: CanvasWiki;
  className?: string;
  /** The canvas after a change - a card moved, made, written in or taken off. Absent, the canvas cannot be changed. */
  onChange?: (canvas: Canvas) => void;
}

/** Two taps this close in time and place are a double-tap: a new card on the page, or a card of words opened. */
const DOUBLE_MS = 350;
const DOUBLE_PX = 24;

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
  /** Drawing a line: waiting for its first card, or for its second with the first chosen. */
  const [lining, setLining] = useState<{ from: string | null } | null>(null);
  /** The line picked by a tap, by id: its words are shown to be written, and its cross to take it off. */
  const [picked, setPicked] = useState<string | null>(null);
  /** The + sheet, and the step it is at: choosing what to add, a note's title, or a web address. */
  const [adding, setAdding] = useState<AddStep | null>(null);
  /** A browser's pictures arrive from storage after the card is drawn: drawn again when one does (core/images.ts). */
  const pictureArrived = useRedraw();
  useEffect(() => {
    const again = () => pictureArrived();
    window.addEventListener(IMAGE_READY, again);
    return () => window.removeEventListener(IMAGE_READY, again);
  }, [pictureArrived]);
  /** The card last tapped or opened: what Shift+2 and the zoom button go to. */
  const [chosen, setChosen] = useState<string | null>(null);
  const change = useCallback(
    (next: Canvas) => {
      setLive(next);
      onChange?.(next);
    },
    [onChange],
  );
  const camera = useCamera(host, canvas);
  /** The minimap grown, from a press on it, until a press lands on the canvas itself. */
  const [mapBig, setMapBig] = useState(false);
  const gestures = useGestures({ host, camera, live, editable, editing: editing !== null, onPress: () => setMapBig(false), onCarry: setLive, onPutDown: change });
  /** The last tap, and what it was on, for telling a double-tap. */
  const lastTap = useRef<{ at: number; x: number; y: number; on: string | null } | null>(null);

  /*
   * A tap closes whatever card was open. A second tap close on the heels of the first, in the same place, is a
   * double-tap: on the page it makes a new card of words there, open to be written in; on a card of words it opens
   * that card. A note card and a link card open on a single tap, as they did (`Card`), so a double-tap is kept for
   * the two things a single tap cannot mean.
   */
  const onClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (gestures.dragged.current) return;
    const target = event.target as HTMLElement;
    if (target.closest('[data-editing]') || target.closest('button') || target.closest('[data-line-words]')) return;
    const id = target.closest<HTMLElement>('[data-card]')?.dataset.card;
    const node = id ? live.nodes.find((n) => n.id === id) : undefined;
    if (node && node.id !== chosen) setChosen(node.id);
    // A tap on a card's title zooms to the card (choice 10), on any canvas; the rest of the card does what it did.
    if (node && target.closest('[data-card-title]')) {
      zoomTo(node.id);
      return;
    }
    if (!editable) return;
    if (editing) setEditing(null);
    // A tap on a line picks it; a tap anywhere else lets it go.
    const lineId = target.closest<Element>('[data-line]')?.getAttribute('data-line') ?? null;
    if (lineId !== picked) setPicked(lineId);
    if (lineId) return;
    if (node && node.type !== 'text' && node.type !== 'group' && !ownPicture(node)) return;
    const now = performance.now();
    const last = lastTap.current;
    const again = !!last && last.on === (node?.id ?? null) && now - last.at < DOUBLE_MS && Math.hypot(event.clientX - last.x, event.clientY - last.y) < DOUBLE_PX;
    if (again) {
      lastTap.current = null;
      if (node) setEditing(node.id);
      else addCard(camera.under(event.clientX, event.clientY));
      return;
    }
    lastTap.current = { at: now, x: event.clientX, y: event.clientY, on: node?.id ?? null };
  };

  /** A new card on the canvas: open to be written in, or chosen, so Shift+2 goes to it. Nothing for no card. */
  const place = (card: CanvasNode | null, open: boolean) => {
    if (!card) return;
    change(withNode(live, card));
    if (open) setEditing(card.id);
    else setChosen(card.id);
  };
  /** A new card of words centred on a point of the canvas, open to be written in: the page's double-tap, and the +. */
  const addCard = (at: Point) => place(newTextNode(at.x - NEW_CARD.width / 2, at.y - NEW_CARD.height / 2), true);
  const addNoteCard = (title: string, at = camera.middle()) => place(newFileNode(title, at.x - NEW_CARD.width / 2, at.y - 80), false);
  /** A card of words that starts as something: a chart, a table. Open to be written in at once. */
  const addStartedCard = (text: string) => {
    const at = camera.middle();
    const card = { ...newTextNode(at.x - NEW_CARD.width / 2, at.y - 90), text, height: 180 };
    place(card, true);
  };
  const addPictureCard = (name: string, at = camera.middle()) => place(newPictureNode(name, at.x - NEW_CARD.width / 2, at.y - 100), false);
  /** A picture chosen from the phone or the computer, kept the way a note's pictures are kept, then a card of it. */
  const addPicture = async () => {
    const name = await pickImage();
    if (name) addPictureCard(name);
  };
  const addLinkCard = (url: string) => {
    const at = camera.middle();
    place(newLinkNode(url, at.x - NEW_CARD.width / 2, at.y - 50), false);
  };

  /** Zoom to a card: the view fitted to its box, no larger than life. */
  const { zoomToBox, fit } = camera;
  const zoomTo = useCallback(
    (id: string) => {
      const node = live.nodes.find((n) => n.id === id);
      if (node) zoomToBox(node);
    },
    [live, zoomToBox],
  );

  // Shift+1 fits the whole canvas, Shift+2 zooms to the card open or picked (choice 10), as in Obsidian.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (!event.shiftKey || (event.target instanceof Element && event.target.closest('input, textarea, [contenteditable]'))) return;
      if (event.key === '!' || event.code === 'Digit1') fit();
      else if ((event.key === '@' || event.code === 'Digit2') && (editing ?? chosen)) zoomTo((editing ?? chosen)!);
      else return;
      event.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [fit, zoomTo, editing, chosen]);

  /** A note dragged in from the sidebar (notes/NoteTree.tsx), or a picture file dropped from the computer: a card where it lands. */
  const onDrop = (event: React.DragEvent<HTMLDivElement>) => {
    if (!editable) return;
    const at = camera.under(event.clientX, event.clientY);
    const picture = [...(event.dataTransfer.files ?? [])].find((f) => f.type.startsWith('image/'));
    if (picture) {
      event.preventDefault();
      // A file the store cannot read (not a picture after all, or one it cannot decode) makes no card, and says why.
      void saveImageFile(picture)
        .then((name) => addPictureCard(name, at))
        .catch((error: unknown) => console.warn('[glyph] picture not kept:', error));
      return;
    }
    const title = event.dataTransfer.getData('application/x-glyph-note') ? event.dataTransfer.getData('text/plain') : '';
    if (!title) return;
    event.preventDefault();
    addNoteCard(title, at);
  };

  const writeCard = (id: string, text: string) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node?.type === 'text' && node.text !== text) change(withNode(live, { ...node, text }));
  };

  const resizeCard = (id: string, width: number, height: number) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node) change(withNode(live, resizedNode(node, width, height)));
  };
  /** While the corner is dragged the card is drawn at its size; the canvas is handed on when the corner is let go. */
  const previewSize = (id: string, width: number, height: number) => {
    setLive((was) => {
      const node = was.nodes.find((n) => n.id === id);
      return node ? withNode(was, resizedNode(node, width, height)) : was;
    });
  };
  const nameGroup = (id: string, label: string) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node?.type === 'group' && (node.label ?? '') !== label.trim()) change(withNode(live, labelledGroup(node, label)));
  };

  const removeCard = (id: string) => {
    if (editing === id) setEditing(null);
    change(withoutNode(live, id));
  };

  const labelLine = (id: string, words: string) => {
    const line = live.edges.find((e) => e.id === id);
    if (line) change(withEdge(live, labelledEdge(line, words)));
  };

  const removeLine = (id: string) => {
    if (picked === id) setPicked(null);
    change(withoutEdge(live, id));
  };

  // Escape closes the card being written in, lets a picked line go, and puts the Line tool down.
  useEffect(() => {
    if (!editing && !picked && !lining) return undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      setEditing(null);
      setPicked(null);
      setLining(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editing, picked, lining]);

  /*
   * Before any card sees a tap: the click at the end of a drag is the drag's and goes no further; and while a line is
   * being drawn, a tap on a card is the line's, so a note card or a link card must not open (a link card did, and
   * the page left for its address).
   */
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (gestures.dragged.current) {
      event.stopPropagation();
      event.preventDefault();
      return;
    }
    if (!lining) return;
    const target = event.target as HTMLElement;
    if (target.closest('button') || target.closest('[data-line-words]')) return;
    event.stopPropagation();
    event.preventDefault();
    const id = target.closest<HTMLElement>('[data-card]')?.dataset.card;
    const node = id ? live.nodes.find((n) => n.id === id) : undefined;
    if (!node || node.type === 'group') return;
    if (!lining.from) setLining({ from: node.id });
    else if (node.id !== lining.from && !joined(live, lining.from, node.id)) {
      const line = newEdge(lining.from, node.id);
      change(withEdge(live, line));
      setLining(null);
      setPicked(line.id);
    }
  };

  // Drawn together: where one line's end sits depends on the others' (lines.ts `edgePaths`).
  const lines = useMemo(() => {
    const paths = edgePaths(live);
    return live.edges.map((edge) => ({ edge, path: paths.get(edge.id) })).filter((line): line is { edge: CanvasEdge; path: EdgePath } => !!line.path);
  }, [live]);
  const pickedLine = picked ? lines.find((line) => line.edge.id === picked) : undefined;

  return (
    <div
      ref={host}
      className={className ? `${styles.canvas} ${className}` : styles.canvas}
      onPointerDown={gestures.onPointerDown}
      onPointerMove={gestures.onPointerMove}
      onPointerUp={gestures.onPointerUp}
      onPointerCancel={gestures.onPointerUp}
      onClickCapture={onClickCapture}
      onClick={onClick}
      role={editable ? undefined : 'img'}
      aria-label={`A canvas of ${live.nodes.length} cards`}
      data-lining={lining ? (lining.from ? 'to' : 'from') : undefined}
      onDragOver={editable ? (event) => event.preventDefault() : undefined}
      onDrop={editable ? onDrop : undefined}
    >
      {!live.nodes.length ? (
        <div className={styles.emptyCanvas}>
          <Ghost scene="empty-canvas" align="center" className={styles.emptyCanvasArt} />
          <p className={styles.emptyCanvasWords}>{editable ? 'Double-tap to add a card.' : 'An empty canvas.'}</p>
        </div>
      ) : null}
      <div ref={camera.world} className={styles.world}>
        {live.nodes.map((node) => (
          <Card
            key={node.id}
            node={node}
            dark={dark}
            wiki={wiki}
            root={host}
            editing={editing === node.id}
            lifted={gestures.lifted === node.id}
            lineFrom={lining?.from === node.id}
            onWrite={editable ? writeCard : undefined}
            onRemove={editable ? removeCard : undefined}
            onResize={editable ? resizeCard : undefined}
            onPreviewSize={editable ? previewSize : undefined}
            onName={editable ? nameGroup : undefined}
            scale={camera.view}
          />
        ))}
        <LineLayer lines={lines} editable={editable} picked={picked} />
        {/* The picked line's words and its cross, over the line's middle, in the canvas's own pixels. */}
        {pickedLine ? <LineWords key={pickedLine.edge.id} edge={pickedLine.edge} at={pickedLine.path.mid} onLabel={labelLine} onRemove={removeLine} /> : null}
      </div>
      {/* The toolbar: icons, floating at the bottom left (Matt: "a floating bottom left aligned toolbar and use
          iconography instead of text"). What a line needs next is said beside it while one is being drawn. */}
      <div className={styles.tools} role="toolbar" aria-label="Canvas tools">
        {editable ? (
          <>
            <button type="button" className={styles.tool} onClick={() => setAdding('what')} aria-label="Add a card" title="Add a card">
              <Plus size={18} strokeWidth={2.2} aria-hidden="true" />
            </button>
            <button
              type="button"
              className={styles.tool}
              data-on={lining ? '' : undefined}
              aria-pressed={!!lining}
              onClick={() => {
                setLining(lining ? null : { from: null });
                setPicked(null);
              }}
              aria-label={lining ? 'Stop drawing a line' : 'Draw a line: tap one card, then another'}
              title={lining ? 'Stop drawing a line' : 'Draw a line'}
            >
              <Spline size={18} strokeWidth={2.2} aria-hidden="true" />
            </button>
          </>
        ) : null}
        <button type="button" className={styles.tool} onClick={fit} aria-label="Fit the whole canvas on the screen (Shift+1)" title="Fit (Shift+1)">
          <Maximize size={18} strokeWidth={2.2} aria-hidden="true" />
        </button>
        {editing ?? chosen ? (
          <button type="button" className={styles.tool} onClick={() => zoomTo((editing ?? chosen)!)} aria-label="Zoom to the card (Shift+2)" title="To card (Shift+2)">
            <LocateFixed size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
        ) : null}
        {lining ? <span className={styles.hint}>{lining.from ? 'Tap the card it goes to' : 'Tap the card it starts from'}</span> : null}
      </div>
      <Minimap
        canvas={live}
        view={camera.shown}
        host={host}
        big={mapBig}
        onBig={() => setMapBig(true)}
        onGo={(x, y) => camera.centreOn({ x, y })}
        onMove={camera.panBy}
      />
      {adding ? (
        <AddSheet
          step={adding}
          titles={wiki?.titles?.() ?? []}
          onClose={() => setAdding(null)}
          onWords={() => {
            setAdding(null);
            addCard(camera.middle());
          }}
          onNote={(title) => {
            setAdding(null);
            addNoteCard(title);
          }}
          onLink={(url) => {
            setAdding(null);
            addLinkCard(url);
          }}
          onPicture={() => {
            setAdding(null);
            void addPicture();
          }}
          onChart={() => {
            setAdding(null);
            addStartedCard(CHART_CARD);
          }}
          onTable={() => {
            setAdding(null);
            addStartedCard(TABLE_CARD);
          }}
          onStep={setAdding}
        />
      ) : null}
    </div>
  );
}
