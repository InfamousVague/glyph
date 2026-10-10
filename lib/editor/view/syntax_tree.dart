/// The note's parse, kept on the state: `syntaxTree(state)` and the language extension, the two things the web's
/// extension files take from `@codemirror/language`.
///
/// What differs from CodeMirror's `Language`/`LanguageState`: the parse is whole and done when the state is made,
/// where CodeMirror parses the viewport first and the rest in idle slices. The parser reads a string, so a change
/// costs the document's text once, made from the text before it and the change ([_textAfter]: one copy of the
/// note's letters), and a reparse of the blocks the change touched (`MarkdownParser.reparse` reuses every other
/// block of the old tree). There is no
/// language data, no indentation service and no folding: nothing in ../glyph asks for them.
///
/// It lives beside the view because the view's base extensions are the first to need it; it reads nothing of the
/// view, and belongs with the state and the parser (see the note to piece A in docs/STAGE4.md).
library;

import '../state/state.dart';
import '../state/text.dart';
import '../syntax/markdown.dart' show MarkdownParser, parser;
import '../syntax/tree.dart' as lezer;

/// The parse a state holds: the tree, the text it was made from, and the parser that made it.
class SyntaxState {
  const SyntaxState(this.parser, this.text, this.tree);

  final MarkdownParser parser;

  /// The document as one string: what the regex half of the extensions reads, and what the next reparse starts
  /// from.
  final String text;
  final lezer.Tree tree;
}

/// The parser a state's note is read with. The first one given wins.
final Facet<MarkdownParser, MarkdownParser?> syntaxParser = Facet.define<MarkdownParser, MarkdownParser?>(
  combine: (values) => values.isEmpty ? null : values.first,
);

SyntaxState _parse(MarkdownParser parser, String text) => SyntaxState(parser, text, parser.parse(text));

final StateField<SyntaxState?> _syntaxField = StateField.define<SyntaxState?>(
  create: (state) {
    final parser = state.facet(syntaxParser);
    return parser == null ? null : _parse(parser, state.doc.toString());
  },
  update: (value, tr) {
    final parser = tr.state.facet(syntaxParser);
    if (parser == null) return null;
    if (value == null || !identical(value.parser, parser)) return _parse(parser, tr.newDoc.toString());
    if (!tr.docChanged) return value;
    final changes = <lezer.ChangedRange>[];
    tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.add(lezer.ChangedRange(fromA, toA, fromB, toB)));
    final text = _textAfter(value.text, tr);
    return SyntaxState(parser, text, parser.reparse(value.tree, text, changes));
  },
);

/// The document after `tr` as one string, made from the string before it and the changes: one copy of the note's
/// letters, where walking the new document's tree for them wrote each line and each break apart (a quarter of a
/// millisecond for 380 kB on a Mac, for every letter typed). The document keeps it as its own, so whoever asks
/// the document for its string next (the save, the +) is handed this one.
String _textAfter(String before, Transaction tr) {
  final doc = tr.newDoc;
  if (before.length != tr.changes.length) return doc.toString();
  String text;
  var count = 0;
  var from = 0, to = 0;
  Doc? put;
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    count += 1;
    from = fromA;
    to = toA;
    put = inserted;
  });
  if (count == 1) {
    // A letter typed, a word deleted: the one change, set into the string it was made against.
    text = before.replaceRange(from, to, put!.toString());
  } else {
    final parts = <String>[];
    var at = 0;
    tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
      if (fromA > at) parts.add(before.substring(at, fromA));
      if (inserted.length > 0) parts.add(inserted.toString());
      at = toA;
    });
    if (at < before.length) parts.add(before.substring(at));
    text = parts.join();
  }
  doc.adoptString(text);
  return text;
}

final lezer.Tree _noTree = parser.parse('');

/// `syntaxTree(state)` (@codemirror/language): the note's parse, or an empty tree for a state with no language.
lezer.Tree syntaxTree(EditorState state) => state.fieldOrNull(_syntaxField)?.tree ?? _noTree;

/// The note's parse, or null for a state with no language: for whoever keeps a tree of its own otherwise
/// (lib/editor/commands/syntax_tree.dart parses a state whole each time its document is new; with this it can
/// read the tree the state already keeps, reparsed only where a change touched).
lezer.Tree? syntaxTreeOrNull(EditorState state) => state.fieldOrNull(_syntaxField)?.tree;

/// The whole document as a string, when the state already holds it for its parse; null for a state with no
/// language.
String? syntaxText(EditorState state) => state.fieldOrNull(_syntaxField)?.text;

/// The language extension: the state parses its note with [language] and keeps the tree. What the web's
/// `glyphMarkdown(formats)` answers, less its key bindings and paste handling, which are the input layer's:
/// `markdownSyntax(glyphMarkdown(formats))`.
Extension markdownSyntax(MarkdownParser language) => Extension.list(<Extension>[syntaxParser.of(language), _syntaxField]);
