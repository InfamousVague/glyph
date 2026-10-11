import { MarkMenu, type MarkMenuProps } from './MarkMenu.tsx';
import { mountReact } from './reactMount.ts';

/**
 * Renders a linked line's drawer into a host over the page (editor/linkedRows.ts),
 * a React root of its own (editor/reactMount.ts); answers how to take it down again.
 */
export function mountMarkMenu(host: HTMLElement, props: MarkMenuProps): () => void {
  return mountReact(host, <MarkMenu {...props} />);
}
