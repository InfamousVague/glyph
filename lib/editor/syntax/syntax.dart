/// Asking the parse what a position is inside. A port of `src/app/editor/syntax.ts`.
///
/// The haptics ask whether a mark has just closed around the caret; the marks drawn in words - a tag, a counter -
/// ask whether they are in text that is never one.
///
/// What differs: the web's functions take the editor state and read `syntaxTree(state)` unless handed a tree; these
/// take the [Tree], which is all they read, so they stand apart from the editor's state (lib/editor/state).
library;

import 'tree.dart';

/// The nearest node around [pos] whose name passes [test], walking out from the innermost; null when none does.
/// [side] is which way a position between two nodes leans: -1 into the one before it, 1 into the one after.
SyntaxNode? enclosing(Tree tree, int pos, bool Function(String name) test, [int side = -1]) {
  for (SyntaxNode? node = tree.resolveInner(pos, side); node != null; node = node.parent) {
    if (test(node.name)) return node;
  }
  return null;
}

/// Text whose words are never a tag or a counter: code, an address, front matter, HTML, a comment, maths.
final RegExp _quiet = RegExp(r'Code|URL|FrontMatter|HTML|Comment|Math');

/// Whether the text starting at [pos] is quiet: inside code, an address, front matter, HTML, a comment or maths.
bool inQuietText(Tree tree, int pos) => enclosing(tree, pos, _quiet.hasMatch, 1) != null;
