import { useState, type PointerEvent as ReactPointerEvent, type ReactNode, type RefObject, type SyntheticEvent } from 'react';
import { Ban, Check, CopyPlus, ExternalLink, Palette, Pencil, Spline, Trash2 } from '@glacier/icons';
import { ownPicture, paintOf, type CanvasHue } from './cardLooks.ts';
import { HANDLES, resizedBy, type Handle } from './edits.ts';
import type { CanvasNode } from './jsonCanvas.ts';
import type { View } from './viewport.ts';
import styles from './Selection.module.css';

/**
 * What the picked card wears (canvas/CanvasView.tsx): a ring with a handle at each corner and the middle of each
 * side, and a small bar of what can be done to it. Matt: "navigating it and resizing things are not easy especially
 * on mobile resizing containers is near to impossible" - a card could only be resized while it was open to be
 * written in, by a 22px wedge in one corner, and a group not at all.
 *
 * Both are drawn in the world, at the card's own place, so they pan and zoom with it without being laid out again;
 * and both are scaled back by the view's scale (`--canvas-scale`, which camera.ts writes on the page), so a handle is
 * a finger's width and the bar a thumb's height at any zoom. A handle's dot is small; what takes the press is the
 * 44px round it. A press on either is theirs alone and never reaches the page's gestures.
 */

const stop = (event: SyntheticEvent) => event.stopPropagation();

const HANDLE_NAMES: Record<Handle, string> = { nw: 'top left corner', n: 'top side', ne: 'top right corner', e: 'right side', se: 'bottom right corner', s: 'bottom side', sw: 'bottom left corner', w: 'left side' };

interface HandlesProps {
  node: CanvasNode;
  /** The view's scale, read when a handle is taken: screen pixels into the canvas's own. */
  scale: RefObject<View>;
  /** The card at each size on the way, drawn but not yet handed on. */
  onPreview: (node: CanvasNode) => void;
  /** The card at the size it was let go at. */
  onResize: (node: CanvasNode) => void;
}

export function Handles({ node, scale, onPreview, onResize }: HandlesProps) {
  const take = (handle: Handle) => (event: ReactPointerEvent<HTMLSpanElement>) => {
    event.stopPropagation();
    event.preventDefault();
    const at = { x: event.clientX, y: event.clientY };
    const zoom = scale.current.scale || 1;
    const sized = (moved: PointerEvent) => resizedBy(node, handle, (moved.clientX - at.x) / zoom, (moved.clientY - at.y) / zoom);
    const move = (moved: PointerEvent) => onPreview(sized(moved));
    const done = (moved: PointerEvent) => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', done);
      window.removeEventListener('pointercancel', done);
      onResize(sized(moved));
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', done);
    window.addEventListener('pointercancel', done);
  };
  return (
    <div className={styles.handles} style={{ left: node.x, top: node.y, width: node.width, height: node.height }} data-handles={node.id} data-kind={node.type}>
      {HANDLES.map((handle) => (
        <span key={handle} className={styles.handle} data-handle={handle} role="separator" aria-label={`Drag the ${HANDLE_NAMES[handle]} to resize`} onPointerDown={take(handle)} onClick={stop} />
      ))}
    </div>
  );
}

/** The spec's presets in the order the page's hues run (cardLooks.ts `paintOf`). */
const HUES: readonly { color: string; hue: CanvasHue; name: string }[] = [
  { color: '1', hue: 'rose', name: 'Rose' },
  { color: '2', hue: 'ember', name: 'Ember' },
  { color: '3', hue: 'amber', name: 'Amber' },
  { color: '4', hue: 'moss', name: 'Moss' },
  { color: '5', hue: 'sea', name: 'Sea' },
  { color: '6', hue: 'violet', name: 'Violet' },
];

interface CardBarProps {
  node: CanvasNode;
  /** Open to be written in, or a group's name being written: the first button closes it. */
  editing: boolean;
  /** Under the card rather than over it: the card's top is at the top of the screen. */
  below: boolean;
  /** Write in a card of words, or name a group. */
  onEdit: () => void;
  onDone: () => void;
  /** Open the note or the address a card stands for. */
  onOpen?: () => void;
  /** Start a line from this card. */
  onLine: () => void;
  onColour: (color: string | null) => void;
  onDuplicate: () => void;
  onRemove: () => void;
}

function BarButton({ label, onPress, on, children }: { label: string; onPress: () => void; on?: boolean; children: ReactNode }) {
  return (
    <button type="button" className={styles.barButton} aria-label={label} title={label} aria-pressed={on} data-on={on ? '' : undefined} onClick={onPress}>
      {children}
    </button>
  );
}

export function CardBar({ node, editing, below, onEdit, onDone, onOpen, onLine, onColour, onDuplicate, onRemove }: CardBarProps) {
  const [colouring, setColouring] = useState(false);
  const paint = paintOf(node.color);
  const worn = paint && 'hue' in paint ? paint.hue : null;
  const group = node.type === 'group';
  const writes = node.type === 'text' || group;
  return (
    <div
      className={styles.bar}
      style={{ left: node.x + node.width / 2, top: below ? node.y + node.height : node.y }}
      data-below={below || undefined}
      data-card-bar={node.id}
      role="toolbar"
      aria-label={group ? 'This group' : 'This card'}
      onPointerDown={stop}
      onClick={stop}
      onDoubleClick={stop}
    >
      {colouring ? (
        <>
          <BarButton label="No colour" onPress={() => onColour(null)} on={!node.color}>
            <Ban size={17} strokeWidth={2.2} aria-hidden="true" />
          </BarButton>
          {HUES.map(({ color, hue, name }) => (
            <button key={color} type="button" className={styles.swatch} data-hue={hue} aria-label={name} title={name} aria-pressed={worn === hue} onClick={() => onColour(color)} />
          ))}
          <BarButton label="Done with the colour" onPress={() => setColouring(false)}>
            <Check size={17} strokeWidth={2.4} aria-hidden="true" />
          </BarButton>
        </>
      ) : (
        <>
          {writes ? (
            editing ? (
              <BarButton label={group ? 'Done naming' : 'Done writing'} onPress={onDone} on>
                <Check size={17} strokeWidth={2.4} aria-hidden="true" />
              </BarButton>
            ) : (
              <BarButton label={group ? 'Name this group' : 'Write in this card'} onPress={onEdit}>
                <Pencil size={17} strokeWidth={2.2} aria-hidden="true" />
              </BarButton>
            )
          ) : onOpen && !ownPicture(node) ? (
            <BarButton label={node.type === 'link' ? 'Open the address' : 'Open the note'} onPress={onOpen}>
              <ExternalLink size={17} strokeWidth={2.2} aria-hidden="true" />
            </BarButton>
          ) : null}
          {group ? null : (
            <BarButton label="Draw a line from this card" onPress={onLine}>
              <Spline size={17} strokeWidth={2.2} aria-hidden="true" />
            </BarButton>
          )}
          <BarButton label="Colour" onPress={() => setColouring(true)}>
            <Palette size={17} strokeWidth={2.2} aria-hidden="true" />
          </BarButton>
          <BarButton label={group ? 'Copy this group’s box' : 'Make a copy'} onPress={onDuplicate}>
            <CopyPlus size={17} strokeWidth={2.2} aria-hidden="true" />
          </BarButton>
          <BarButton label={group ? 'Take this group off the canvas; its cards stay' : 'Take this card off the canvas'} onPress={onRemove}>
            <Trash2 size={17} strokeWidth={2.2} aria-hidden="true" />
          </BarButton>
        </>
      )}
    </div>
  );
}
