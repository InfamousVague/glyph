import { useEffect, useRef, useState } from 'react';
import type { Point } from './geometry.ts';
import type { CanvasEdge } from './jsonCanvas.ts';
import { Remove } from './Remove.tsx';
import styles from './CanvasView.module.css';

/**
 * A picked line's words, written in place over its middle, and the cross that takes the line off (canvas/
 * CanvasView.tsx). The words are handed on when the field is left or Enter is pressed, and only when they changed,
 * so picking a line and letting it go writes nothing. It sits in the world, in the canvas's own pixels, so it stays
 * on its line as the canvas pans.
 */
export function LineWords({ edge, at, onLabel, onRemove }: { edge: CanvasEdge; at: Point; onLabel: (id: string, words: string) => void; onRemove: (id: string) => void }) {
  const [words, setWords] = useState(edge.label ?? '');
  const field = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const timer = window.setTimeout(() => field.current?.focus(), 0);
    return () => window.clearTimeout(timer);
  }, []);
  const commit = () => {
    if (words.trim() !== (edge.label ?? '')) onLabel(edge.id, words);
  };
  return (
    <div className={styles.lineWords} style={{ left: at.x, top: at.y }} data-line-words onPointerDown={(event) => event.stopPropagation()}>
      <input
        ref={field}
        className={styles.lineField}
        value={words}
        placeholder="Words on the line"
        aria-label="Words on the line"
        onChange={(event) => setWords(event.currentTarget.value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') {
            commit();
            event.currentTarget.blur();
          }
        }}
      />
      <Remove label="Take this line off the canvas" onPress={() => onRemove(edge.id)} />
    </div>
  );
}
