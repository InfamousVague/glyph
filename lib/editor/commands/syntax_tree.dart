/// The syntax tree a command reads: `syntaxTree(state)` and `ensureSyntaxTree(state, upto)` of @codemirror/language,
/// for the commands until the view's language layer owns them.
///
/// What differs: CodeMirror keeps the tree in a state field that parses in slices and may lag behind the document,
/// which is why the web's commands call `ensureSyntaxTree` before they trust it. Here a tree is always whole: it
/// is parsed from the document the first time a command asks and remembered against that document (an [Expando]
/// on the [Doc], so a state that did not change its text answers the same tree), by the parser the state names
/// in [commandParser], or the app's own with no plugin formats when it names none. The parse is not incremental;
/// when the view keeps a tree of its own, [syntaxTree] should read that one instead.
library;

import '../state/state.dart';
import '../state/text.dart';
import '../syntax/language.dart';
import '../syntax/markdown.dart';
import '../syntax/tree.dart';

/// The parser the commands read a state's document with: the first one given, the app's Markdown otherwise.
final Facet<MarkdownParser, MarkdownParser?> commandParser = Facet.define<MarkdownParser, MarkdownParser?>(
  combine: (values) => values.isNotEmpty ? values[0] : null,
);

final MarkdownParser _plain = glyphMarkdown();

final Expando<({MarkdownParser parser, Tree tree})> _parsed = Expando<({MarkdownParser parser, Tree tree})>('commandTree');

/// The state's syntax tree, whole.
Tree syntaxTree(EditorState state) {
  final parser = state.facet(commandParser) ?? _plain;
  final Doc doc = state.doc;
  final known = _parsed[doc];
  if (known != null && identical(known.parser, parser)) return known.tree;
  final tree = parser.parse(doc.toString());
  _parsed[doc] = (parser: parser, tree: tree);
  return tree;
}

/// CodeMirror's `ensureSyntaxTree`: the tree parsed at least as far as `upto`. Always the whole tree here, so never
/// null.
Tree ensureSyntaxTree(EditorState state, [int? upto, int? timeout]) => syntaxTree(state);
