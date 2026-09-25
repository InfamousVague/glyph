import { useEffect, useRef, type CSSProperties, type RefObject } from 'react';
import { imageUrl } from '../core/images.ts';
import { openLink } from '../core/linkPreview.ts';
import { shortUrl } from '../core/shortUrl.ts';
import { Editor } from '../editor/Editor.tsx';
import { NotePeek } from '../notes/NotePeek.tsx';
import { fileTitle, isImageFile, isOnlyTable, ownPicture, paintProps, type CanvasHue } from './cards.ts';
import type { CanvasWiki } from './CanvasView.tsx';
import type { CanvasNode } from './jsonCanvas.ts';
import { Near } from './Near.tsx';
import { Remove } from './Remove.tsx';
import type { View } from './viewport.ts';
import styles from './CanvasView.module.css';

/**
 * One card on the canvas (canvas/CanvasView.tsx), drawn by its kind where the file puts it, in the canvas's own
 * pixels: a group's dashed box and name; a card of words, which is the note's own editor; a link; one of Ghost.md's
 * own pictures; or a note by its file, drawn small. Every card carries its id as `data-card`, which is how the
 * canvas's gestures find the card a press landed on, and its title as `data-card-title`, which a tap zooms to.
 *
 * Opened to be written in (`editing`), a card takes every tap and key: a card of words becomes the note's editor in
 * its own mode with the words going straight into the canvas, and a group's name becomes a field. An open card has
 * a cross that takes it off and, but for a group, a corner that resizes it.
 */

export interface CardProps {
  node: CanvasNode;
  dark: boolean;
  wiki?: CanvasWiki;
  /** The canvas, which is what "near the screen" is measured against. */
  root: RefObject<HTMLDivElement | null>;
  /** Open to be written in: a card of words shows its editor as the note does, taking every tap and key. */
  editing?: boolean;
  /** Lifted by a held press and following the finger. */
  lifted?: boolean;
  /** The card a line being drawn starts from. */
  lineFrom?: boolean;
  onWrite?: (id: string, text: string) => void;
  onRemove?: (id: string) => void;
  /** The card made this size when its corner is let go, and drawn at each size on the way. */
  onResize?: (id: string, width: number, height: number) => void;
  onPreviewSize?: (id: string, width: number, height: number) => void;
  /** A group's name written. */
  onName?: (id: string, label: string) => void;
  /** The view's scale, read when a corner is dragged: screen pixels into the canvas's own. */
  scale?: RefObject<View>;
}

type NodeOf<K extends CanvasNode['type']> = Extract<CanvasNode, { type: K }>;

/** What each kind of card is drawn with: the card's props, its own node, and where it sits and what hue it wears. */
type KindProps<K extends CanvasNode['type']> = Omit<CardProps, 'node'> & { node: NodeOf<K>; hue: CanvasHue | undefined; place: CSSProperties };

export function Card(props: CardProps) {
  const { node } = props;
  const paint = paintProps(node.color);
  // Where the card sits, in the canvas's pixels, and a chosen hex as its own colour (CanvasView.module.css `.card`).
  const place: CSSProperties = { left: node.x, top: node.y, width: node.width, height: node.height, ...paint.style };
  const kind = { ...props, hue: paint.hue, place };
  if (node.type === 'group') return <GroupCard {...kind} node={node} />;
  if (node.type === 'text') return <TextCard {...kind} node={node} />;
  if (node.type === 'link') return <LinkCard {...kind} node={node} />;
  // A picture of Ghost.md's own is drawn once the picture store has an address for it; until then, a browser's
  // picture still arriving from storage, it is drawn as a file is.
  const own = ownPicture(node);
  const url = own ? imageUrl(own) : null;
  return url ? <PictureCard {...kind} node={node} url={url} /> : <FileCard {...kind} node={node} />;
}

/** A group: its dashed box, and its name above - a field to write it in while the group is open, with the cross. */
function GroupCard({ node, hue, place, editing = false, lifted = false, onName, onRemove }: KindProps<'group'>) {
  return (
    <div className={styles.group} style={place} data-hue={hue} data-card={node.id} data-lifted={lifted || undefined} data-editing={editing || undefined}>
      {editing && onName ? (
        <span className={styles.groupLabel} data-editing>
          <input
            ref={(el) => el?.focus()}
            className={styles.groupField}
            defaultValue={node.label ?? ''}
            placeholder="Name this group"
            aria-label="The group's name"
            onBlur={(event) => onName(node.id, event.currentTarget.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') event.currentTarget.blur();
            }}
            onPointerDown={(event) => event.stopPropagation()}
          />
          {onRemove ? <Remove label="Take this group off the canvas; its cards stay" onPress={() => onRemove(node.id)} /> : null}
        </span>
      ) : node.label ? (
        <span className={styles.groupLabel}>{node.label}</span>
      ) : null}
    </div>
  );
}

/** The corner of an open card: dragged, it resizes the card, in the canvas's pixels whatever the zoom. */
function Corner({ node, onResize, onPreviewSize, scale }: Pick<CardProps, 'node' | 'onPreviewSize' | 'scale'> & { onResize: NonNullable<CardProps['onResize']> }) {
  return (
    <span
      className={styles.corner}
      aria-label="Drag to resize this card"
      onPointerDown={(event) => {
        event.stopPropagation();
        event.preventDefault();
        const at = { x: event.clientX, y: event.clientY };
        const size = { width: node.width, height: node.height };
        const zoom = scale?.current.scale ?? 1;
        const move = (moved: PointerEvent) => onPreviewSize?.(node.id, size.width + (moved.clientX - at.x) / zoom, size.height + (moved.clientY - at.y) / zoom);
        const done = (moved: PointerEvent) => {
          window.removeEventListener('pointermove', move);
          window.removeEventListener('pointerup', done);
          window.removeEventListener('pointercancel', done);
          onResize(node.id, size.width + (moved.clientX - at.x) / zoom, size.height + (moved.clientY - at.y) / zoom);
        };
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', done);
        window.addEventListener('pointercancel', done);
      }}
    />
  );
}

/** The corner, on an open card that can be resized; nothing on any other. */
function cornerOf({ node, editing, onResize, onPreviewSize, scale }: Pick<CardProps, 'node' | 'editing' | 'onResize' | 'onPreviewSize' | 'scale'>) {
  return editing && onResize ? <Corner node={node} onResize={onResize} onPreviewSize={onPreviewSize} scale={scale} /> : null;
}

/** A card of words: the note's own editor, read-only in its peek until opened, then live in the note's mode. */
function TextCard(props: KindProps<'text'>) {
  const { node, hue, place, dark, root, editing = false, lifted = false, lineFrom = false, onWrite, onRemove } = props;
  // Opened to be written in: the keyboard comes up with it (Matt: "a text card appears under the fingers, keyboard up").
  const opened = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!editing) return undefined;
    const timer = window.setTimeout(() => opened.current?.querySelector<HTMLElement>('.cm-content')?.focus(), 0);
    return () => window.clearTimeout(timer);
  }, [editing]);
  return (
    <div
      className={styles.card}
      style={place}
      data-hue={hue}
      data-card={node.id}
      data-editing={editing || undefined}
      data-lifted={lifted || undefined}
      data-line-from={lineFrom || undefined}
      // A card that is only a table draws the table edge to edge (Matt: "make the table fill the card").
      data-only={!editing && isOnlyTable(node.text) ? 'table' : undefined}
    >
      {editing ? (
        // Open: the note's own editor in its own mode, the words going straight into the canvas as they are typed.
        <div ref={opened} className={styles.words}>
          <Editor value={node.text} onChange={(text) => onWrite?.(node.id, text)} dark={dark} assist display="mixed" placeholder="Write something." grow diagrams />
        </div>
      ) : (
        <Near root={root} className={styles.words}>
          <Editor value={node.text} onChange={noop} dark={dark} assist={false} readOnly display="formatted" peek diagrams grow />
        </Near>
      )}
      {editing && onRemove ? <Remove label="Take this card off the canvas" onPress={() => onRemove(node.id)} /> : null}
      {cornerOf(props)}
    </div>
  );
}

/** A web address, opened the way a link in a note is (core/linkPreview.ts): the phone's browser, not a window of ours. */
function LinkCard({ node, hue, place, lifted = false, lineFrom = false }: KindProps<'link'>) {
  return (
    <a
      className={`${styles.card} ${styles.linkCard}`}
      style={place}
      data-hue={hue}
      data-card={node.id}
      data-lifted={lifted || undefined}
      data-line-from={lineFrom || undefined}
      href={node.url}
      onClick={(event) => {
        event.preventDefault();
        // The title is the way to zoom to the card (choice 10), so a tap there does not open the address.
        if ((event.target as HTMLElement).closest('[data-card-title]')) return;
        void openLink(node.url);
      }}
    >
      <span className={styles.cardTitle} data-card-title>
        {shortUrl(node.url)}
      </span>
      <span className={styles.cardHint}>{node.url}</span>
    </a>
  );
}

/** One of Ghost.md's own pictures, by the name the store keeps it under (core/images.ts): the whole card is the picture. */
function PictureCard(props: KindProps<'file'> & { url: string }) {
  const { node, hue, place, url, editing = false, lifted = false, onRemove } = props;
  return (
    <div className={`${styles.card} ${styles.pictureCard}`} style={place} data-hue={hue} data-card={node.id} data-lifted={lifted || undefined} data-editing={editing || undefined}>
      <img className={styles.picture} src={url} alt="" draggable={false} />
      {editing && onRemove ? <Remove label="Take this picture off the canvas" onPress={() => onRemove(node.id)} /> : null}
      {cornerOf(props)}
    </div>
  );
}

/**
 * A file: a note by that name in Ghost.md, drawn small and opened on a tap; one it does not have yet, said to be
 * waiting; or a picture from the vault it came from, which it has no copy of.
 */
function FileCard({ node, hue, place, wiki, root, lifted = false, lineFrom = false }: KindProps<'file'>) {
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
      data-line-from={lineFrom || undefined}
      data-waiting={known || picture ? undefined : ''}
      role={picture ? undefined : 'button'}
      tabIndex={picture ? undefined : 0}
      // A tap on the title zooms to the card (choice 10) rather than opening the note; the rest of the card opens it.
      onClick={picture ? undefined : (event) => !(event.target as HTMLElement).closest('[data-card-title]') && wiki?.open(title, at)}
      onKeyDown={picture ? undefined : (event) => (event.key === 'Enter' || event.key === ' ') && wiki?.open(title, at)}
    >
      <span className={styles.cardTitle} data-card-title>
        {title}
      </span>
      {body ? (
        <Near root={root}>
          <NotePeek body={body} className={styles.cardPeek} />
        </Near>
      ) : (
        <span className={styles.cardHint}>{picture ? 'A picture, in the vault it came from' : known ? '' : 'Not in Ghost.md yet'}</span>
      )}
    </div>
  );
}

function noop(): void {
  // Read-only: nothing typed comes back.
}
