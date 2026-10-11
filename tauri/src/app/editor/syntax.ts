import { syntaxTree } from '@codemirror/language';
import type { EditorState } from '@codemirror/state';
import type { SyntaxNode, Tree } from '@lezer/common';

/**
 * Asking the parse what a position is inside. The haptics ask whether a mark has just closed around the caret
 * (editor/feel.ts); the marks drawn in words - a tag, a counter - ask whether they are in text that is never one.
 */

/**
 * The nearest node around `pos` whose name passes `test`, walking out from the innermost; null when none does. `side`
 * is which way a position between two nodes leans: -1 into the one before it, 1 into the one after. `tree` is the
 * state's own unless a caller parsed further (ensureSyntaxTree answers a fuller tree than the state holds).
 */
export function enclosing(state: EditorState, pos: number, test: (name: string) => boolean, side: -1 | 1 = -1, tree: Tree = syntaxTree(state)): SyntaxNode | null {
  for (let node: SyntaxNode | null = tree.resolveInner(pos, side); node; node = node.parent) {
    if (test(node.name)) return node;
  }
  return null;
}

/** Text whose words are never a tag or a counter: code, an address, front matter, HTML, a comment, maths. */
const QUIET = /Code|URL|FrontMatter|HTML|Comment|Math/;

/** Whether the text starting at `pos` is quiet: inside code, an address, front matter, HTML, a comment or maths. */
export function inQuietText(state: EditorState, pos: number, tree: Tree = syntaxTree(state)): boolean {
  return enclosing(state, pos, (name) => QUIET.test(name), 1, tree) !== null;
}
