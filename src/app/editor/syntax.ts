import { syntaxTree } from '@codemirror/language';
import type { EditorState } from '@codemirror/state';
import type { SyntaxNode } from '@lezer/common';

/**
 * Asking the parse what a position is inside. The haptics ask whether a mark has just closed around the caret
 * (editor/feel.ts); the marks drawn in words - a tag, a counter - ask whether they are in text that is never one.
 */

/**
 * The nearest node around `pos` whose name passes `test`, walking out from the innermost; null when none does. `side`
 * is which way a position between two nodes leans: -1 into the one before it, 1 into the one after.
 */
export function enclosing(state: EditorState, pos: number, test: (name: string) => boolean, side: -1 | 1 = -1): SyntaxNode | null {
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(pos, side); node; node = node.parent) {
    if (test(node.name)) return node;
  }
  return null;
}

/** Text whose words are never a tag or a counter: code, an address, front matter, HTML, a comment, maths. */
const QUIET = /Code|URL|FrontMatter|HTML|Comment|Math/;

/** Whether the text starting at `pos` is quiet: inside code, an address, front matter, HTML, a comment or maths. */
export function inQuietText(state: EditorState, pos: number): boolean {
  return enclosing(state, pos, (name) => QUIET.test(name), 1) !== null;
}
