import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react';
import { markOf } from './comments.ts';
import type { Canvas } from './jsonCanvas.ts';
import styles from './CanvasView.module.css';

const stop = (event: ReactPointerEvent | { stopPropagation: () => void }) => event.stopPropagation();

/**
 * The rounds on the cards that have threads: at each card's top-left corner, in the colour of who started the first
 * open thread (or the first, when all are resolved, drawn hollow), with how many are open. In the world, scaled back
 * by the view so they are one size on the screen, and taking their own taps.
 */
export function CommentMarks({ canvas, scale, colour, onOpen }: { canvas: Canvas; scale: number; colour: (handle: string) => string; onOpen: (nodeId: string) => void }) {
  const marks = canvas.nodes.map((node) => ({ node, mark: markOf(canvas, node.id) })).filter((each) => each.mark !== null);
  if (marks.length === 0) return null;
  return (
    <>
      {marks.map(({ node, mark }) => (
        <button
          key={node.id}
          type="button"
          className={styles.commentRound}
          style={{ left: node.x, top: node.y, transform: `translate(-40%, -40%) scale(${1 / scale})` } as CSSProperties}
          data-hue={colour(mark!.by)}
          data-open={mark!.open > 0 || undefined}
          data-comment-round={node.id}
          aria-label={`${mark!.count === 1 ? 'A comment' : `${mark!.count} comments`} on this card${mark!.open ? `, ${mark!.open} open` : ', resolved'}`}
          onPointerDown={stop}
          onClick={(event) => {
            event.stopPropagation();
            onOpen(node.id);
          }}
        >
          {mark!.open || '✓'}
        </button>
      ))}
    </>
  );
}
