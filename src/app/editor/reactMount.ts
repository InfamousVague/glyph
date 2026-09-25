import type { ReactNode } from 'react';
import { createRoot } from 'react-dom/client';

/**
 * A React root of its own in an element over or inside the note - a linked line's drawer (editor/markMenuMount.tsx),
 * a canvas's frame (editor/canvasFrames.ts) - with `element` drawn in it; answers how to take it down again.
 *
 * Taken down after CodeMirror's own update has finished, never in the middle of a React render: a widget is destroyed
 * during an update, and one that holds a root may be destroyed while React is drawing.
 */
export function mountReact(host: HTMLElement, element: ReactNode): () => void {
  const root = createRoot(host);
  root.render(element);
  return () => queueMicrotask(() => root.unmount());
}
