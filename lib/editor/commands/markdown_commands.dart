/// Enter and Backspace in a list or a quote: `insertNewlineContinueMarkup` and `deleteMarkupBackward` of
/// @codemirror/lang-markdown 6.5.2 (dist/index.js), ported line for line, with `markdownKeymap`, which binds them.
/// "Enter continues a list, Backspace removes a marker whole. The most useful phone behaviour in the package"
/// (src/app/editor/language.ts).
///
/// Held to the real library: tool/markdown_command_fixtures.mjs runs both commands under Node with the app's
/// language over every caret of a set of documents, and test/editor/commands/markdown_commands_test.dart asserts
/// the same answers here.
///
/// What differs:
/// - `markdownLanguage.isActiveAt(state, pos, side)`: on the web an HTML block, an inline HTML tag and a comment
///   block are parsed by the HTML language, mounted over the Markdown node (@lezer/markdown `parseCode`), so
///   Markdown is "not active" inside them and the commands step aside. The Dart parser mounts nothing
///   (lib/editor/syntax/language.dart), so [markdownActiveAt] answers the same question from the Markdown tree:
///   inactive where the position is inside what the HTML parser would have been given, the node's own text between
///   its children, by the same rule of sides. A fenced block parsed by its own language needs no such care: both
///   commands already stand down anywhere inside a `FencedCode`.
/// - `indentUnit` is never set by the app, so `normalizeIndent`, which only rewrites an indent when the unit is a
///   tab, is the identity; it is kept as a function with that said.
/// - the tree is whole (syntax_tree.dart).
/// - a [StateCommand] takes a [StateCommandTarget]; the two are also given as pure functions that answer the
///   [Transaction] or null ([continueMarkup], [deleteMarkup]) for a caller with no target.
library;

import '../state/change.dart';
import '../state/char.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../syntax/tree.dart';
import 'syntax_tree.dart';

class _Context {
  _Context(this.node, this.from, this.to, this.spaceBefore, this.spaceAfter, this.type, this.item);

  final SyntaxNode node;
  final int from;
  final int to;
  final String spaceBefore;
  final String spaceAfter;
  final String type;
  final SyntaxNode? item;

  String blank(int? maxWidth, [bool trailing = true]) {
    var result = spaceBefore + (node.name == 'Blockquote' ? '>' : '');
    if (maxWidth != null) {
      while (result.length < maxWidth) {
        result += ' ';
      }
      return result;
    } else {
      for (var i = to - from - result.length - spaceAfter.length; i > 0; i--) {
        result += ' ';
      }
      return result + (trailing ? spaceAfter : '');
    }
  }

  String marker(Doc doc, int add) {
    final number = node.name == 'OrderedList' ? '${int.parse(_itemNumber(item!, doc)!.group(2)!) + add}' : '';
    return spaceBefore + number + type + spaceAfter;
  }
}

final RegExp _quoteLead = RegExp(r'^ *>( ?)');
final RegExp _orderedLead = RegExp(r'^( *)\d+([.)])( *)');
final RegExp _bulletLead = RegExp(r'^( *)([-+*])( {1,4}\[[ xX]\])?( +)');
final RegExp _ticked = RegExp(r'[xX]');

List<_Context> _getContext(SyntaxNode node, Doc doc) {
  final nodes = <SyntaxNode>[], context = <_Context>[];
  for (SyntaxNode? cur = node; cur != null; cur = cur.parent) {
    if (cur.name == 'FencedCode') return context;
    if (cur.name == 'ListItem' || cur.name == 'Blockquote') nodes.add(cur);
  }
  for (var i = nodes.length - 1; i >= 0; i--) {
    final node = nodes[i];
    RegExpMatch? match;
    final line = doc.lineAt(node.from), startPos = node.from - line.from;
    final rest = line.text.substring(startPos);
    if (node.name == 'Blockquote' && (match = _quoteLead.firstMatch(rest)) != null) {
      context.add(_Context(node, startPos, startPos + match!.group(0)!.length, '', match.group(1)!, '>', null));
    } else if (node.name == 'ListItem' && node.parent!.name == 'OrderedList' && (match = _orderedLead.firstMatch(rest)) != null) {
      var after = match!.group(3)!, len = match.group(0)!.length;
      if (after.length >= 4) {
        after = after.substring(0, after.length - 4);
        len -= 4;
      }
      context.add(_Context(node.parent!, startPos, startPos + len, match.group(1)!, after, match.group(2)!, node));
    } else if (node.name == 'ListItem' && node.parent!.name == 'BulletList' && (match = _bulletLead.firstMatch(rest)) != null) {
      var after = match!.group(4)!, len = match.group(0)!.length;
      if (after.length > 4) {
        after = after.substring(0, after.length - 4);
        len -= 4;
      }
      var type = match.group(2)!;
      final box = match.group(3);
      if (box != null && box.isNotEmpty) type += box.replaceFirst(_ticked, ' ');
      context.add(_Context(node.parent!, startPos, startPos + len, match.group(1)!, after, type, node));
    }
  }
  return context;
}

final RegExp _itemNumberPattern = RegExp(r'^(\s*)(\d+)(?=[.)])');

RegExpMatch? _itemNumber(SyntaxNode item, Doc doc) =>
    _itemNumberPattern.firstMatch(doc.sliceString(item.from, item.from + 10 > doc.length ? doc.length : item.from + 10));

void _renumberList(SyntaxNode after, Doc doc, List<ChangeSpec> changes, [int offset = 0]) {
  for (var prev = -1, node = after;;) {
    if (node.name == 'ListItem') {
      final m = _itemNumber(node, doc)!;
      final number = int.parse(m.group(2)!);
      if (prev >= 0) {
        if (number != prev + 1) return;
        changes.add(ChangeSpec(from: node.from + m.group(1)!.length, to: node.from + m.group(0)!.length, insert: '${prev + 2 + offset}'));
      }
      prev = number;
    }
    final next = node.nextSibling;
    if (next == null) break;
    node = next;
  }
}

/// lang-markdown's `normalizeIndent` rewrites leading blank space as tabs when the editor's `indentUnit` is a tab.
/// The app never sets `indentUnit` (two spaces, CodeMirror's default), so the content comes back as it is.
String _normalizeIndent(String content, EditorState state) => content;

/// The node kinds @lezer/markdown hands to the HTML parser (`parseCode`).
const Set<String> _htmlMounted = <String>{'HTMLBlock', 'HTMLTag', 'CommentBlock'};

/// `markdownLanguage.isActiveAt(state, pos, side)`: whether Markdown, and not a language nested in it, is the
/// language at `pos`. See the header for what stands in for the nested HTML tree.
bool markdownActiveAt(EditorState state, int pos, [int side = -1]) {
  for (SyntaxNode? node = syntaxTree(state).topNode; node != null; node = node.enter(pos, side)) {
    if (!_htmlMounted.contains(node.name)) continue;
    // `leftOverSpace`: the node's text that no child covers, which is what the HTML parser reads.
    var at = node.from;
    for (var child = node.firstChild; ; child = child.nextSibling) {
      final next = child != null ? child.from : node.to;
      if (next > at && (side > 0 ? at <= pos : at < pos) && (side < 0 ? next >= pos : next > pos)) return false;
      if (child == null) break;
      at = child.to;
    }
  }
  return true;
}

final RegExp _nonSpace = RegExp(r'\S');
final RegExp _space = RegExp(r'\s');
final RegExp _onlySpaceOrQuote = RegExp(r'^[\s>]*$');
final RegExp _notSpaceOrQuote = RegExp(r'[^\s>]');
final RegExp _quotedEnd = RegExp(r'>\s*$');
final RegExp _leadChars = RegExp(r'^[\s\d.)\-+*>]*');

/// lang-markdown's `insertNewlineContinueMarkupCommand(config)`: [insertNewlineContinueMarkup] with its one option.
/// `nonTightLists: false` makes Enter on an empty item always leave the list, never open a gap in a tight one.
StateCommand insertNewlineContinueMarkupCommand({bool? nonTightLists}) => (StateCommandTarget target) {
  final tr = continueMarkup(target.state, nonTightLists: nonTightLists);
  if (tr == null) return false;
  target.dispatch(tr);
  return true;
};

/// What [insertNewlineContinueMarkup] would dispatch, or null where it answers false.
Transaction? continueMarkup(EditorState state, {bool? nonTightLists}) {
  final tree = syntaxTree(state), doc = state.doc;
  var dont = false;
  final changes = state.changeByRange((range) {
    if (!range.empty || !markdownActiveAt(state, range.from, -1) && !markdownActiveAt(state, range.from, 1)) {
      dont = true;
      return RangeChange(range: range);
    }
    final pos = range.from, line = doc.lineAt(pos);
    final context = _getContext(tree.resolveInner(pos, -1), doc);
    while (context.isNotEmpty && context.last.from > pos - line.from) {
      context.removeLast();
    }
    if (context.isEmpty) {
      dont = true;
      return RangeChange(range: range);
    }
    final inner = context.last;
    if (inner.to - inner.spaceAfter.length > pos - line.from) {
      dont = true;
      return RangeChange(range: range);
    }
    final emptyLine = pos >= (inner.to - inner.spaceAfter.length) && !_nonSpace.hasMatch(_from(line.text, inner.to));
    // Empty line in list
    if (inner.item != null && emptyLine) {
      if (inner.item!.from < line.from && !_onlySpaceOrQuote.hasMatch(_upTo(line.text, inner.to))) {
        dont = true;
        return RangeChange(range: range);
      }
      final first = inner.node.firstChild!, second = inner.node.getChild('ListItem', 'ListItem');
      // Not second item or blank line before: delete a level of markup
      if (first.to >= pos ||
          second != null && second.to < pos ||
          line.from > 0 && !_notSpaceOrQuote.hasMatch(doc.lineAt(line.from - 1).text) ||
          nonTightLists == false) {
        final next = context.length > 1 ? context[context.length - 2] : null;
        int delTo;
        var insert = '';
        if (next != null && next.item != null) {
          // Re-add marker for the list at the next level
          delTo = line.from + next.from;
          insert = next.marker(doc, 1);
        } else {
          delTo = line.from + (next != null ? next.to : 0);
        }
        final changes = <ChangeSpec>[ChangeSpec(from: delTo, to: pos, insert: insert)];
        if (inner.node.name == 'OrderedList') _renumberList(inner.item!, doc, changes, -2);
        if (next != null && next.node.name == 'OrderedList') _renumberList(next.item!, doc, changes);
        return RangeChange(range: EditorSelection.cursor(delTo + insert.length), changes: changes);
      } else {
        // Move second item down, making tight two-item list non-tight
        final insert = _blankLine(context, state, line);
        return RangeChange(
          range: EditorSelection.cursor(pos + insert.length + 1),
          changes: ChangeSpec(from: line.from, insert: insert + state.lineBreak),
        );
      }
    }
    if (inner.node.name == 'Blockquote' && emptyLine && line.from > 0) {
      final prevLine = doc.lineAt(line.from - 1), quoted = _quotedEnd.firstMatch(prevLine.text);
      // Two aligned empty quoted lines in a row
      if (quoted != null && quoted.start == inner.from) {
        final changes = state.changes(<ChangeSpec>[
          ChangeSpec(from: prevLine.from + quoted.start, to: prevLine.to),
          ChangeSpec(from: line.from + inner.from, to: line.to),
        ]);
        return RangeChange(range: range.map(changes), changes: changes);
      }
    }
    final changes = <ChangeSpec>[];
    if (inner.node.name == 'OrderedList') _renumberList(inner.item!, doc, changes);
    final continued = inner.item != null && inner.item!.from < line.from;
    var insert = '';
    // If not dedented
    if (!continued || _leadChars.firstMatch(line.text)!.group(0)!.length >= inner.to) {
      for (var i = 0, e = context.length - 1; i <= e; i++) {
        insert += i == e && !continued
            ? context[i].marker(doc, 1)
            : context[i].blank(i < e ? countColumn(line.text, 4, context[i + 1].from) - insert.length : null);
      }
    }
    var from = pos;
    while (from > line.from && _space.hasMatch(line.text[from - line.from - 1])) {
      from--;
    }
    insert = _normalizeIndent(insert, state);
    if (_nonTightList(inner.node, state.doc)) insert = _blankLine(context, state, line) + state.lineBreak + insert;
    changes.add(ChangeSpec(from: from, to: pos, insert: state.lineBreak + insert));
    return RangeChange(range: EditorSelection.cursor(from + insert.length + 1), changes: changes);
  });
  if (dont) return null;
  return state.updateAll(<TransactionSpec>[changes, const TransactionSpec(scrollIntoView: true, userEvent: 'input')]);
}

// JavaScript's `slice` forgives an index past the end; `substring` does not.
String _from(String text, int at) => at >= text.length ? '' : text.substring(at < 0 ? 0 : at);
String _upTo(String text, int at) => text.substring(0, at > text.length ? text.length : (at < 0 ? 0 : at));
String _between(String text, int from, int to) {
  final end = to > text.length ? text.length : to, start = from < 0 ? 0 : from;
  return start >= end ? '' : text.substring(start, end);
}

/// This command, when invoked in Markdown context with cursor selection(s), will create a new line with the markup
/// for blockquotes and lists that were active on the old line. If the cursor was directly after the end of the
/// markup for the old line, trailing whitespace and list markers are removed from that line.
///
/// The command does nothing in non-Markdown context, so it should not be used as the only binding for Enter.
final StateCommand insertNewlineContinueMarkup = insertNewlineContinueMarkupCommand();

bool _isMark(SyntaxNode node) => node.name == 'QuoteMark' || node.name == 'ListMark';

bool _nonTightList(SyntaxNode node, Doc doc) {
  if (node.name != 'OrderedList' && node.name != 'BulletList') return false;
  final first = node.firstChild!, second = node.getChild('ListItem', 'ListItem');
  if (second == null) return false;
  final line1 = doc.lineAt(first.to), line2 = doc.lineAt(second.from);
  final empty = _onlySpaceOrQuote.hasMatch(line1.text);
  return line1.number + (empty ? 0 : 1) < line2.number;
}

String _blankLine(List<_Context> context, EditorState state, Line line) {
  var insert = '';
  for (var i = 0, e = context.length - 2; i <= e; i++) {
    insert += context[i].blank(i < e ? countColumn(line.text, 4, context[i + 1].from) - insert.length : null, i < e);
  }
  return _normalizeIndent(insert, state);
}

SyntaxNode _contextNodeForDelete(Tree tree, int pos) {
  var node = tree.resolveInner(pos, -1), scan = pos;
  if (_isMark(node)) {
    scan = node.from;
    node = node.parent!;
  }
  for (SyntaxNode? prev; (prev = node.childBefore(scan)) != null;) {
    if (_isMark(prev!)) {
      scan = prev.from;
    } else if (prev.name == 'OrderedList' || prev.name == 'BulletList') {
      node = prev.lastChild!;
      scan = node.to;
    } else {
      break;
    }
  }
  return node;
}

/// What [deleteMarkupBackward] would dispatch, or null where it answers false.
Transaction? deleteMarkup(EditorState state) {
  final tree = syntaxTree(state);
  var dont = false;
  final changes = state.changeByRange((range) {
    final pos = range.from, doc = state.doc;
    if (range.empty && markdownActiveAt(state, range.from)) {
      final line = doc.lineAt(pos);
      final context = _getContext(_contextNodeForDelete(tree, pos), doc);
      if (context.isNotEmpty) {
        final inner = context.last;
        final spaceEnd = inner.to - inner.spaceAfter.length + (inner.spaceAfter.isNotEmpty ? 1 : 0);
        // Delete extra trailing space after markup
        if (pos - line.from > spaceEnd && !_nonSpace.hasMatch(_between(line.text, spaceEnd, pos - line.from))) {
          return RangeChange(
            range: EditorSelection.cursor(line.from + spaceEnd),
            changes: ChangeSpec(from: line.from + spaceEnd, to: pos),
          );
        }
        if (pos - line.from == spaceEnd &&
            // Only apply this if we're on the line that has the construct's syntax, or there's only indentation in
            // the target range
            ((inner.item != null && line.from <= inner.item!.from) || _onlySpaceOrQuote.hasMatch(_upTo(line.text, inner.to)))) {
          final start = line.from + inner.from;
          // Replace a list item marker with blank space
          if (inner.item != null && inner.node.from < inner.item!.from && _nonSpace.hasMatch(_between(line.text, inner.from, inner.to))) {
            var insert = inner.blank(countColumn(line.text, 4, inner.to) - countColumn(line.text, 4, inner.from));
            if (start == line.from) insert = _normalizeIndent(insert, state);
            return RangeChange(
              range: EditorSelection.cursor(start + insert.length),
              changes: ChangeSpec(from: start, to: line.from + inner.to, insert: insert),
            );
          }
          // Delete one level of indentation
          if (start < pos) return RangeChange(range: EditorSelection.cursor(start), changes: ChangeSpec(from: start, to: pos));
        }
      }
    }
    dont = true;
    return RangeChange(range: range);
  });
  if (dont) return null;
  return state.updateAll(<TransactionSpec>[changes, const TransactionSpec(scrollIntoView: true, userEvent: 'delete')]);
}

/// This command will, when invoked in a Markdown context with the cursor directly after list or blockquote markup,
/// delete one level of markup. When the markup is for a list, it will be replaced by spaces on the first invocation
/// (a further invocation will delete the spaces), to make it easy to continue a list.
///
/// When not after Markdown block markup, this command will return false, so it is intended to be bound alongside
/// other deletion commands, with a higher precedence than the more generic commands.
bool deleteMarkupBackward(StateCommandTarget target) {
  final tr = deleteMarkup(target.state);
  if (tr == null) return false;
  target.dispatch(tr);
  return true;
}

/// lang-markdown's `markdownKeymap`: Enter and Backspace, tried before the default keymap's (`Prec.high` on the
/// web), which take over where these answer false.
final List<({String key, StateCommand run})> markdownKeymap = <({String key, StateCommand run})>[
  (key: 'Enter', run: insertNewlineContinueMarkup),
  (key: 'Backspace', run: deleteMarkupBackward),
];
