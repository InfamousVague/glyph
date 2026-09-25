import { paintProps } from './cards.ts';
import type { CanvasEdge } from './jsonCanvas.ts';
import { LABEL_LINE, type EdgePath } from './lines.ts';
import styles from './CanvasView.module.css';

/**
 * The canvas's lines, one SVG over every card in the world's own pixels (canvas/CanvasView.tsx): each line's curve,
 * its heads and its label, as lines.ts placed them. The SVG takes no taps, so a card under a line is still a card; on
 * a canvas that can change, each line carries its id as `data-line` and a wide unseen stroke under it, so a finger
 * can pick it. A picked line's label is left off, since its words are being written over it (canvas/LineWords.tsx).
 */
export function LineLayer({ lines, editable, picked }: { lines: readonly { edge: CanvasEdge; path: EdgePath }[]; editable: boolean; picked: string | null }) {
  return (
    <svg className={styles.edges} aria-hidden="true">
      {lines.map(({ edge, path }) => {
        const paint = paintProps(edge.color);
        return (
          <g key={edge.id} className={styles.edge} data-hue={paint.hue} data-line={editable ? edge.id : undefined} data-picked={picked === edge.id || undefined} style={paint.style}>
            {/* A wide, unseen stroke under the line, so a finger can land on it. */}
            {editable ? <path className={styles.lineHit} d={path.d} /> : null}
            <path className={styles.line} d={path.d} />
            {path.fromHead ? <path className={styles.head} d={path.fromHead} /> : null}
            {path.toHead ? <path className={styles.head} d={path.toHead} /> : null}
            {edge.label && picked !== edge.id ? (
              // Its lines, one under another about the point: broken where one line would not fit between cards.
              <text className={styles.label} x={path.mid.x} y={path.mid.y}>
                {path.lines.map((line, i) => (
                  <tspan key={i} x={path.mid.x} dy={i === 0 ? -((path.lines.length - 1) * LABEL_LINE) / 2 : LABEL_LINE}>
                    {line}
                  </tspan>
                ))}
              </text>
            ) : null}
          </g>
        );
      })}
    </svg>
  );
}
