import { Ghost } from '../art/Ghost.tsx';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { LocateFixed, Magnet, Maximize, Plus, Spline, ZoomIn, ZoomOut } from '@glacier/icons';
import { IMAGE_READY, pickImage, saveImageFile } from '../core/images.ts';
import { openLink } from '../core/linkPreview.ts';
import { useCommentColours } from '../core/comments/colours.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { useRedraw } from '../core/useRedraw.ts';
import type { Spot } from '../core/live/presence.ts';
import type { TeamBinding } from '../editor/useTeamNote.ts';
import type { VideoMode } from '../editor/videos.ts';
import { AddSheet, type AddStep } from './AddSheet.tsx';
import { useCamera } from './camera.ts';
import { Card } from './Card.tsx';
import { Pointers } from './Pointers.tsx';
import { CommentMarks, useCanvasComments } from './useCanvasComments.tsx';
import { useOthers, useSaying, useTeamCanvas } from './useTeamCanvas.ts';
import { fileTitle } from './cardLooks.ts';
import {
  atDot,
  CHART_CARD,
  clearSpot,
  colouredNode,
  duplicated,
  joined,
  labelledEdge,
  labelledGroup,
  GRID,
  movedWithHeld,
  NEW_CARD,
  NEW_GROUP,
  newEdge,
  newFileNode,
  newGroupNode,
  newLinkNode,
  newPictureNode,
  newTextNode,
  TABLE_CARD,
  withEdge,
  withGroup,
  withNode,
  onGrid,
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
import { CardBar, Handles } from './Selection.tsx';
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
 *
 * Picking (the eighth; Matt: "spend some time reworking the controls and creation aspects of canvases, navigating it
 * and resizing things are not easy especially on mobile resizing containers is near to impossible"). On a canvas that
 * can change, a tap picks a card, of any kind, and the picked card wears a ring, a handle at each corner and side to
 * resize it by, and a bar of what can be done to it: write in it or open it, draw a line from it, colour it, copy
 * it, take it off (Selection.tsx). A second tap on the picked card opens it - a card of words to be written in, a
 * note or an address where it goes - so a double-tap still does what it did, and a note card no longer leaves the
 * canvas under a finger that was only reaching for it. A group is a box like any other now: made from the +, about
 * the picked card when there is one, resized by its handles, named from its bar or by a tap on its name; its ground
 * is the page's, so a double-tap inside it makes a card there. A canvas that cannot change opens its cards on a tap,
 * as it did. The keys: Delete takes the picked card off, the arrows nudge it, Escape lets it go, and Ctrl or Cmd+D
 * copies it. Zooming has buttons beside Fit.
 *
 * Snapping (Matt: "Add the option for snapping to the grid dots on by default on canvases"): with the magnet on, as
 * it is until it is turned off (the preference `canvasSnap`), a card moved, resized, nudged or made lands with its
 * corner and its sides on the dots under the cards, 24px apart (edits.ts `GRID`), and the phone ticks as it does. A
 * card already off the grid stays where it is until it is next moved. Alt with an arrow still nudges by one pixel.
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
  /** Whose film cards its cards of words draw (editor/videos.ts): a shared page's say only a still is shared. */
  videos?: VideoMode;
  className?: string;
  /** The canvas after a change - a card moved, made, written in or taken off. Absent, the canvas cannot be changed. */
  onChange?: (canvas: Canvas) => void;
  /**
   * A team's canvas (docs/SHARED.md, S9; editor/useTeamNote.ts): drawn from and edited through its structure in the
   * team's document, with the other members' pointers and open cards drawn from the note's room.
   */
  team?: TeamBinding | null;
  /** A spot to centre on, from an organization's dashboard's Jump to cursor: a member's pointer. */
  goTo?: Spot;
  /** The note this canvas is, for its comments' colours (core/comments/colours.ts); absent, nobody wears one. */
  noteId?: string;
}

/** Two taps this close in time and place are a double-tap: a new card on the page, or a card of words opened. */
const DOUBLE_MS = 350;
const DOUBLE_PX = 24;
/** How much closer, or further, one press of a zoom button goes. */
const ZOOM_STEP = 1.3;
/** The room a picked card's bar needs over the card, in screen pixels; with less, the bar goes under the card. */
const BAR_ROOM = 64;

export function CanvasView({ canvas: given, dark, wiki, videos, className, onChange: tell, team, goTo, noteId }: CanvasViewProps) {
  const host = useRef<HTMLDivElement>(null);
  // A team's canvas is its structure in the team's document; any other is the one handed in (useTeamCanvas.ts).
  const { canvas, onChange } = useTeamCanvas(team, given, tell);
  /*
   * The canvas as it is being changed: the one handed in, with a card part-way through a drag on top of it. Every
   * change goes out through `onChange` and comes back as the next `canvas`; between the two, and while a finger is
   * still moving a card, this is what is drawn.
   */
  const [live, setLive] = useState(canvas);
  useEffect(() => setLive(canvas), [canvas]);
  const editable = !!onChange;
  /** The card of words open to be written in, or the group whose name is, by id. */
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
  /** The card picked, by id: it wears the ring, the handles and the bar, and is what Shift+2 and the zoom button go to. */
  const [chosen, setChosen] = useState<string | null>(null);
  const change = useCallback(
    (next: Canvas) => {
      setLive(next);
      onChange?.(next);
    },
    [onChange],
  );
  // The camera fits the canvas as it opened, and again when the note reloads it; a team's structure changes with
  // every member's edit, and a view is not refitted for a card moved.
  const [opened, setOpened] = useState(canvas);
  useEffect(() => {
    if (!team) setOpened(canvas);
  }, [team, canvas]);
  const camera = useCamera(host, opened);
  /** Whether what is moved, resized or made lands on the grid's dots: the magnet, on until it is turned off. */
  const snap = usePreferences().canvasSnap;
  /** The minimap grown, from a press on it, until a press lands on the canvas itself. */
  const [mapBig, setMapBig] = useState(false);
  const gestures = useGestures({
    host,
    camera,
    live,
    editable,
    editing: editing !== null,
    selected: chosen,
    snap,
    onPress: () => setMapBig(false),
    onCarry: setLive,
    // A card put down is the card picked: carried by a hold or by a drag, it is the one in hand. One that was only
    // held and let go where it was is picked and nothing is written.
    onPutDown: (next, id, moved) => {
      if (moved) change(next);
      else setLive(canvas);
      setChosen(id);
      setPicked(null);
    },
  });
  // The other members on this canvas, and what this device says of itself: its pointer and the card it has open.
  const others = useOthers(team?.room);
  const say = useSaying(team?.room, editing);
  const editedBy = (id: string) => {
    const by = others.find((other) => other.card === id);
    return by ? { name: by.name, color: by.color } : undefined;
  };
  // The threads on the cards (docs/SHARED.md, S9; useCanvasComments.tsx), and the colour each one's round wears.
  const comments = useCanvasComments(live, noteId, editable ? change : undefined);
  const commentColours = useCommentColours(noteId ?? '');
  // Jump to cursor from the dashboard: the screen centred on the member's pointer.
  const centre = useRef(camera.centreOn);
  centre.current = camera.centreOn;
  useEffect(() => {
    if (goTo) centre.current(goTo);
  }, [goTo]);
  /** The last tap, and what it was on, for telling a double-tap. */
  const lastTap = useRef<{ at: number; x: number; y: number; on: string | null } | null>(null);
  const picking = chosen ? live.nodes.find((n) => n.id === chosen) : undefined;

  /** Open what a card stands for: a note by its title, an address in the phone's browser. */
  const openCard = (node: CanvasNode) => {
    if (node.type === 'link') void openLink(node.url);
    else if (node.type === 'file') wiki?.open(fileTitle(node.file), node.subpath ? node.subpath.slice(1) : undefined);
  };

  /*
   * A tap picks the card under it and lets go of whatever was open. A tap on the card already picked opens it: a
   * card of words to be written in, a group's name when the tap was on the name; a note and an address open
   * themselves (`Card`), having been let through by `onClickCapture`. A second tap close on the heels of the first,
   * on the page or on a group's ground, makes a new card of words there, open to be written in.
   */
  const onClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (gestures.dragged.current) return;
    const target = event.target as HTMLElement;
    if (target.closest('[data-editing]') || target.closest('button') || target.closest('[data-line-words]')) return;
    const id = target.closest<HTMLElement>('[data-card]')?.dataset.card;
    const node = id ? live.nodes.find((n) => n.id === id) : undefined;
    if (!editable) {
      // A canvas to read: the card last tapped is what Shift+2 goes to, and a tap on its title zooms to it (choice 10).
      if (node && node.id !== chosen) setChosen(node.id);
      if (node && target.closest('[data-card-title]')) zoomTo(node.id);
      return;
    }
    const was = chosen;
    if ((node?.id ?? null) !== chosen) setChosen(node?.id ?? null);
    if (editing && editing !== node?.id) setEditing(null);
    // A tap on a line picks it; a tap anywhere else lets it go.
    const lineId = target.closest<Element>('[data-line]')?.getAttribute('data-line') ?? null;
    if (lineId !== picked) setPicked(lineId);
    if (lineId) return;
    if (node && node.id === was) {
      // The picked card, tapped again. Its title zooms to it (choice 10); the rest of it opens it.
      if (target.closest('[data-card-title]')) zoomTo(node.id);
      else if (node.type === 'text') setEditing(node.id);
      else if (node.type === 'group' && target.closest('[data-group-grip]')) setEditing(node.id);
    }
    // A double-tap makes a card: on the page, and on a group's ground, which is the page's.
    if (node && node.type !== 'group') {
      lastTap.current = null;
      return;
    }
    if (target.closest('[data-group-grip]')) return;
    const now = performance.now();
    const last = lastTap.current;
    const again = !!last && now - last.at < DOUBLE_MS && Math.hypot(event.clientX - last.x, event.clientY - last.y) < DOUBLE_PX;
    if (again) {
      lastTap.current = null;
      addCard(camera.under(event.clientX, event.clientY));
      return;
    }
    lastTap.current = { at: now, x: event.clientX, y: event.clientY, on: null };
  };

  /** A new card on the canvas, picked, and open to be written in when it is one to write in. Nothing for no card. */
  const place = (card: CanvasNode | null, open: boolean) => {
    if (!card) return;
    // On a dot, with the magnet on; and never exactly on a card already there: two added one after the other used
    // to sit one on the other. A step aside is one square of the grid, so a card stepped aside is still on it.
    const dot = snap ? atDot(card.x, card.y) : card;
    const at = clearSpot(live, dot.x, dot.y);
    const set = { ...card, x: at.x, y: at.y };
    change(withNode(live, set));
    setChosen(set.id);
    setPicked(null);
    setEditing(open ? set.id : null);
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
  /** A new group: about the picked card when there is one, else a box mid-screen. Its name is open to be written. */
  const addGroup = () => {
    const about = picking && picking.type !== 'group' ? picking : null;
    const middle = camera.middle();
    const corner = { x: middle.x - NEW_GROUP.width / 2, y: middle.y - NEW_GROUP.height / 2 };
    const at = snap ? atDot(corner.x, corner.y) : corner;
    const group = newGroupNode(about, at.x, at.y);
    change(withGroup(live, group));
    setChosen(group.id);
    setPicked(null);
    setEditing(group.id);
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

  const removeCard = useCallback(
    (id: string) => {
      setEditing((was) => (was === id ? null : was));
      setChosen((was) => (was === id ? null : was));
      change(withoutNode(live, id));
    },
    [live, change],
  );

  const copyCard = useCallback(
    (id: string) => {
      const node = live.nodes.find((n) => n.id === id);
      if (!node) return;
      const copy = duplicated(live, node);
      change(node.type === 'group' ? withGroup(live, copy) : withNode(live, copy));
      setEditing(null);
      setChosen(copy.id);
    },
    [live, change],
  );

  /*
   * The keys, while nothing is being typed. Shift+1 fits the whole canvas and Shift+2 zooms to the picked card
   * (choice 10), as in Obsidian. Delete takes the picked card off, the arrows nudge it - ten pixels, one with Alt -
   * and Ctrl or Cmd+D copies it.
   */
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.target instanceof Element && event.target.closest('input, textarea, [contenteditable]')) return;
      const at = editing ?? chosen;
      if (event.shiftKey && (event.key === '!' || event.code === 'Digit1')) fit();
      else if (event.shiftKey && (event.key === '@' || event.code === 'Digit2') && at) zoomTo(at);
      else if (editable && chosen && !editing && (event.key === 'Delete' || event.key === 'Backspace')) removeCard(chosen);
      else if (editable && chosen && !editing && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'd') copyCard(chosen);
      else if (editable && chosen && !editing && event.key.startsWith('Arrow')) {
        const node = live.nodes.find((n) => n.id === chosen);
        if (!node) return;
        // With the magnet on, an arrow is one dot along, from the nearest dot; Alt is always one pixel, off the grid.
        const gridded = snap && !event.altKey;
        const step = event.altKey ? 1 : gridded ? GRID : 10;
        const dx = event.key === 'ArrowLeft' ? -step : event.key === 'ArrowRight' ? step : 0;
        const dy = event.key === 'ArrowUp' ? -step : event.key === 'ArrowDown' ? step : 0;
        const from = gridded ? { x: dx ? onGrid(node.x) : node.x, y: dy ? onGrid(node.y) : node.y } : node;
        change(movedWithHeld(live, node, from.x + dx, from.y + dy));
      } else return;
      event.preventDefault();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [fit, zoomTo, editing, chosen, editable, live, change, removeCard, copyCard, snap]);

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

  /** While a handle is dragged the card is drawn at its size; the canvas is handed on when the handle is let go. */
  const previewSize = (sized: CanvasNode) => setLive((was) => (was.nodes.some((n) => n.id === sized.id) ? withNode(was, sized) : was));
  const resizeCard = (sized: CanvasNode) => {
    if (live.nodes.some((n) => n.id === sized.id)) change(withNode(live, sized));
  };
  const nameGroup = (id: string, label: string) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node?.type === 'group' && (node.label ?? '') !== label.trim()) change(withNode(live, labelledGroup(node, label)));
  };
  const colourCard = (id: string, color: string | null) => {
    const node = live.nodes.find((n) => n.id === id);
    if (node && (node.color ?? null) !== color) change(withNode(live, colouredNode(node, color)));
  };

  const labelLine = (id: string, words: string) => {
    const line = live.edges.find((e) => e.id === id);
    if (line) change(withEdge(live, labelledEdge(line, words)));
  };

  const removeLine = (id: string) => {
    if (picked === id) setPicked(null);
    change(withoutEdge(live, id));
  };

  // Escape lets go, one thing at a time: the card being written in, the line tool, a picked line, then the picked card.
  useEffect(() => {
    if (!editing && !picked && !lining && !chosen) return undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (editing || picked || lining) {
        setEditing(null);
        setPicked(null);
        setLining(null);
      } else setChosen(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editing, picked, lining, chosen]);

  /*
   * Before any card sees a tap: the click at the end of a drag is the drag's and goes no further; while a line is
   * being drawn, a tap on a card is the line's, so a note card or a link card must not open (a link card did, and
   * the page left for its address); and on a canvas that can change, the first tap on a card picks it, so a note
   * or an address only opens from the card already picked.
   */
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (gestures.dragged.current) {
      event.stopPropagation();
      event.preventDefault();
      return;
    }
    const target = event.target as HTMLElement;
    if (target.closest('button') || target.closest('[data-line-words]') || target.closest('[data-card-bar]')) return;
    const id = target.closest<HTMLElement>('[data-card]')?.dataset.card;
    const node = id ? live.nodes.find((n) => n.id === id) : undefined;
    if (!lining) {
      if (editable && node && node.id !== chosen && (node.type === 'link' || node.type === 'file')) {
        event.stopPropagation();
        event.preventDefault();
        setChosen(node.id);
        setEditing(null);
        setPicked(null);
        lastTap.current = null;
      }
      return;
    }
    event.stopPropagation();
    event.preventDefault();
    if (!node || node.type === 'group') return;
    if (!lining.from) setLining({ from: node.id });
    else if (node.id !== lining.from && !joined(live, lining.from, node.id)) {
      const line = newEdge(lining.from, node.id);
      change(withEdge(live, line));
      setLining(null);
      setPicked(line.id);
      setChosen(null);
    }
  };

  // Drawn together: where one line's end sits depends on the others' (lines.ts `edgePaths`).
  const lines = useMemo(() => {
    const paths = edgePaths(live);
    return live.edges.map((edge) => ({ edge, path: paths.get(edge.id) })).filter((line): line is { edge: CanvasEdge; path: EdgePath } => !!line.path);
  }, [live]);
  const pickedLine = picked ? lines.find((line) => line.edge.id === picked) : undefined;
  // The picked card's ring, handles and bar: not while it is carried, nor while a line is being drawn from it.
  const wearing = editable && picking && !lining && gestures.lifted !== picking.id ? picking : null;
  // Its bar goes under it when its top is too near the top of the screen for a bar to fit over it.
  const barBelow = wearing ? wearing.y * camera.shown.scale + camera.shown.y < BAR_ROOM : false;

  return (
    <div
      ref={host}
      className={className ? `${styles.canvas} ${className}` : styles.canvas}
      onPointerDown={gestures.onPointerDown}
      onPointerMove={(event) => {
        gestures.onPointerMove(event);
        if (team?.room) say(camera.under(event.clientX, event.clientY));
      }}
      onPointerLeave={team?.room ? () => say(null) : undefined}
      onPointerUp={gestures.onPointerUp}
      onPointerCancel={gestures.onPointerUp}
      onClickCapture={onClickCapture}
      onClick={onClick}
      role={editable ? undefined : 'img'}
      aria-label={`A canvas of ${live.nodes.length} cards`}
      data-editable={editable || undefined}
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
            videos={videos}
            root={host}
            editing={editing === node.id}
            lifted={gestures.lifted === node.id}
            selected={editable && chosen === node.id}
            lineFrom={lining?.from === node.id}
            editedBy={editedBy(node.id)}
            onWrite={editable ? writeCard : undefined}
            onName={editable ? nameGroup : undefined}
          />
        ))}
        <LineLayer lines={lines} editable={editable} picked={picked} />
        {/* The threads' rounds on the cards' corners, and the other members' pointers in their colours (docs/SHARED.md, S9). */}
        {editable ? <CommentMarks canvas={live} scale={camera.shown.scale} colour={commentColours.of} onOpen={comments.open} /> : null}
        <Pointers others={others} scale={camera.shown.scale} />
        {/* The picked line's words and its cross, over the line's middle, in the canvas's own pixels. */}
        {pickedLine ? <LineWords key={pickedLine.edge.id} edge={pickedLine.edge} at={pickedLine.path.mid} onLabel={labelLine} onRemove={removeLine} /> : null}
        {/* The picked card's ring and handles, and its bar, over everything else in the world (Selection.tsx). */}
        {wearing ? <Handles node={wearing} scale={camera.view} snap={snap} onPreview={previewSize} onResize={resizeCard} /> : null}
        {wearing ? (
          <CardBar
            key={wearing.id}
            node={wearing}
            editing={editing === wearing.id}
            below={barBelow}
            onEdit={() => setEditing(wearing.id)}
            onDone={() => setEditing(null)}
            onOpen={wearing.type === 'link' || (wearing.type === 'file' && wiki) ? () => openCard(wearing) : undefined}
            onComment={() => comments.start(wearing.id)}
            onLine={() => {
              setEditing(null);
              setPicked(null);
              setLining({ from: wearing.id });
            }}
            onColour={(color) => colourCard(wearing.id, color)}
            onDuplicate={() => copyCard(wearing.id)}
            onRemove={() => removeCard(wearing.id)}
          />
        ) : null}
      </div>
      {/* The toolbar: icons, floating at the bottom left (Matt: "a floating bottom left aligned toolbar and use
          iconography instead of text"). What a line needs next is said beside it while one is being drawn. */}
      <div className={styles.tools} role="toolbar" aria-label="Canvas tools" onPointerDown={(event) => event.stopPropagation()}>
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
            <button
              type="button"
              className={styles.tool}
              data-held={snap ? '' : undefined}
              aria-pressed={snap}
              onClick={() => setPreferences({ canvasSnap: !snap })}
              aria-label="Snap to the grid"
              title={snap ? 'Snapping to the grid: on' : 'Snapping to the grid: off'}
            >
              <Magnet size={18} strokeWidth={2.2} aria-hidden="true" />
            </button>
            <span className={styles.toolRule} aria-hidden="true" />
          </>
        ) : null}
        <button type="button" className={`${styles.tool} ${styles.zoomTool}`} onClick={() => camera.zoomBy(1 / ZOOM_STEP)} aria-label="Zoom out" title="Zoom out">
          <ZoomOut size={18} strokeWidth={2.2} aria-hidden="true" />
        </button>
        <button type="button" className={`${styles.tool} ${styles.zoomTool}`} onClick={() => camera.zoomBy(ZOOM_STEP)} aria-label="Zoom in" title="Zoom in">
          <ZoomIn size={18} strokeWidth={2.2} aria-hidden="true" />
        </button>
        <button type="button" className={styles.tool} onClick={fit} aria-label="Fit the whole canvas on the screen (Shift+1)" title="Fit (Shift+1)">
          <Maximize size={18} strokeWidth={2.2} aria-hidden="true" />
        </button>
        {editing ?? chosen ? (
          <button type="button" className={`${styles.tool} ${styles.toCardTool}`} onClick={() => zoomTo((editing ?? chosen)!)} aria-label="Zoom to the card (Shift+2)" title="To card (Shift+2)">
            <LocateFixed size={18} strokeWidth={2.2} aria-hidden="true" />
          </button>
        ) : null}
        {lining ? <span className={styles.hint}>{lining.from ? 'Tap the card it goes to' : 'Tap the card it starts from'}</span> : null}
      </div>
      <Minimap
        canvas={live}
        lines={lines}
        view={camera.shown}
        host={host}
        big={mapBig}
        onBig={() => setMapBig(true)}
        onGo={(x, y) => camera.centreOn({ x, y })}
        onMove={camera.panBy}
      />
      {/* A thread's card, a new comment, or a card's threads as a list (useCanvasComments.tsx), in the app's sheet. */}
      {comments.sheet}
      {adding ? (
        <AddSheet
          step={adding}
          titles={wiki?.titles?.() ?? []}
          aboutCard={!!picking && picking.type !== 'group'}
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
          onGroup={() => {
            setAdding(null);
            addGroup();
          }}
          onStep={setAdding}
        />
      ) : null}
    </div>
  );
}
