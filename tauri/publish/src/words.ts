import { withoutAnchors } from '../../src/app/core/comments/format.ts';
import { anchorSpan, withoutAnchor } from '../../src/app/core/itemSyntax.ts';

/**
 * A note's words as a page draws them: the app's own bookkeeping in the prose taken out, which the editor hides and a
 * static page would otherwise print. A comment's anchor, `[^c1]`, goes (core/comments/format.ts; the thread itself is
 * drawn from the fence, fences.tsx); a list item's anchor, ` ^venue` at its end (core/itemSyntax.ts), goes too, since
 * a board's lanes name it by it and a reader never sees it in the app. Fenced lines are left as they are: a fence is
 * code, or a fence the site reads itself.
 */
export function forDrawing(body: string): string {
  const out: string[] = [];
  let fence: string | null = null;
  for (const line of body.split('\n')) {
    const marker = /^\s*(```|~~~)/.exec(line);
    if (marker) {
      fence = fence === null ? marker[1]! : fence === marker[1] ? null : fence;
      out.push(line);
      continue;
    }
    if (fence !== null) {
      out.push(line);
      continue;
    }
    let drawn = withoutAnchors(line);
    const span = anchorSpan(drawn);
    if (span && /^\s*(?:[-*+]|\d+[.)])\s/.test(drawn)) drawn = withoutAnchor(drawn, span);
    out.push(drawn);
  }
  return out.join('\n');
}
