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
/// A state can be ASLEEP ([syntaxAsleep]): the editor a note keeps behind its canvas or its notebook's index is
/// never drawn, and what it holds there is the canvas's JSON, which read as Markdown is one paragraph thousands of
/// lines long (30 ms for a canvas of 200 cards on a Mac, at its opening and again each time the canvas's words
/// are handed to it). Asleep, the field parses nothing and [syntaxTree] answers the empty tree, as for a state
/// with no language, which is all the extensions that draw ask of it; whoever acts on the note's words through
/// a sleeping state (a command, the AI's fills) asks [syntaxTreeWhole], which reads the note then, once for the
/// words as they are. The parse is made the moment the state is woken.
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
  const SyntaxState(this.parser, this.text, this.tree) : asleep = false;

  /// What a sleeping state holds: its parser, and nothing read.
  SyntaxState.asleep(this.parser)
      : text = '',
        tree = _noTree,
        asleep = true;

  final MarkdownParser parser;

  /// Whether nothing was read: [text] and [tree] are then empty, whatever the note holds.
  final bool asleep;

  /// The document as one string: what the regex half of the extensions reads, and what the next reparse starts
  /// from.
  final String text;
  final lezer.Tree tree;
}

/// The parser a state's note is read with. The first one given wins.
final Facet<MarkdownParser, MarkdownParser?> syntaxParser = Facet.define<MarkdownParser, MarkdownParser?>(
  combine: (values) => values.isEmpty ? null : values.first,
);

/// Whether the state's note is left unread: given true by whoever keeps an editor out of sight (lib/note's host,
/// for the editor behind a canvas or an index), and taken back, through a compartment, as the editor is shown.
/// Any true wins.
final Facet<bool, bool> syntaxAsleep = Facet.define<bool, bool>(combine: (values) => values.contains(true));

/// What the parsing has cost, for the tests that hold it to a count. Debug builds only: every count is made inside
/// an `assert`.
abstract final class SyntaxWork {
  /// Notes read whole.
  static int whole = 0;

  /// Notes read again where a change touched them.
  static int again = 0;

  static void reset() {
    whole = 0;
    again = 0;
  }
}

SyntaxState _parse(MarkdownParser parser, Doc doc) {
  // Read already for these words while the state slept ([syntaxTreeWhole]): that reading is the parse.
  final known = _whole[doc];
  final text = doc.toString();
  if (known != null && identical(known.parser, parser)) return SyntaxState(parser, text, known.tree);
  assert(() {
    SyntaxWork.whole += 1;
    return true;
  }());
  return SyntaxState(parser, text, parser.parse(text));
}

final StateField<SyntaxState?> _syntaxField = StateField.define<SyntaxState?>(
  create: (state) {
    final parser = state.facet(syntaxParser);
    if (parser == null) return null;
    return state.facet(syntaxAsleep) ? SyntaxState.asleep(parser) : _parse(parser, state.doc);
  },
  update: (value, tr) {
    final parser = tr.state.facet(syntaxParser);
    if (parser == null) return null;
    if (tr.state.facet(syntaxAsleep)) return value != null && value.asleep && identical(value.parser, parser) ? value : SyntaxState.asleep(parser);
    if (value == null || value.asleep || !identical(value.parser, parser)) return _parse(parser, tr.newDoc);
    if (!tr.docChanged) return value;
    final changes = <lezer.ChangedRange>[];
    tr.changes.iterChangedRanges((fromA, toA, fromB, toB) => changes.add(lezer.ChangedRange(fromA, toA, fromB, toB)));
    final text = _textAfter(value.text, tr);
    assert(() {
      SyntaxWork.again += 1;
      return true;
    }());
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

/// `syntaxTree(state)` (@codemirror/language): the note's parse, or an empty tree for a state with no language
/// and for one that is asleep.
lezer.Tree syntaxTree(EditorState state) => state.fieldOrNull(_syntaxField)?.tree ?? _noTree;

/// The note's parse, or null for a state with no language or asleep: for whoever keeps a tree of its own
/// otherwise.
lezer.Tree? syntaxTreeOrNull(EditorState state) {
  final held = state.fieldOrNull(_syntaxField);
  return held == null || held.asleep ? null : held.tree;
}

/// The note's parse, whole, whether the state is asleep or not; null for a state with no language. For whoever
/// acts on what the note says and not on what is drawn of it: the commands (lib/editor/commands/syntax_tree.dart
/// reads the tree the state keeps, reparsed only where a change touched, through this), the blanks the AI fills.
/// A sleeping state's note is read here, the first time it is asked for the words as they are, and that reading
/// is the state's own once it wakes with the same words.
lezer.Tree? syntaxTreeWhole(EditorState state) {
  final held = state.fieldOrNull(_syntaxField);
  if (held == null) return null;
  if (!held.asleep) return held.tree;
  final doc = state.doc;
  final known = _whole[doc];
  if (known != null && identical(known.parser, held.parser)) return known.tree;
  assert(() {
    SyntaxWork.whole += 1;
    return true;
  }());
  final tree = held.parser.parse(doc.toString());
  _whole[doc] = (parser: held.parser, tree: tree);
  return tree;
}

final Expando<({MarkdownParser parser, lezer.Tree tree})> _whole = Expando<({MarkdownParser parser, lezer.Tree tree})>('syntaxTreeWhole');

/// The whole document as a string, when the state already holds it for its parse; null for a state with no
/// language or asleep.
String? syntaxText(EditorState state) {
  final held = state.fieldOrNull(_syntaxField);
  return held == null || held.asleep ? null : held.text;
}

/// The language extension: the state parses its note with [language] and keeps the tree. What the web's
/// `glyphMarkdown(formats)` answers, less its key bindings and paste handling, which are the input layer's:
/// `markdownSyntax(glyphMarkdown(formats))`.
Extension markdownSyntax(MarkdownParser language) => Extension.list(<Extension>[syntaxParser.of(language), _syntaxField]);
