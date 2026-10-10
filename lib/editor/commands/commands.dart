/// The editing commands: CodeMirror's `@codemirror/commands` 6.11.0 (comment.ts and commands.ts; history.ts is
/// `state/history.dart`), every command its `defaultKeymap` binds that a state can answer, under CodeMirror's own
/// names and in its order, so this file reads beside `@codemirror/commands/dist/index.js`. With them the parts of
/// @codemirror/view 6.43 (`moveByChar`, `byGroup`, `moveToLineBoundary`, `skipAtomicRanges`) and of
/// @codemirror/language 6.12 (`indentUnit`, `getIndentUnit`, `indentString`, `IndentContext`, `getIndentation`,
/// `matchBrackets`) the commands stand on, and lang-markdown's language data ([markdownLanguageData]).
///
/// A command is a [StateCommand]: a function of `{state, dispatch}` that sends one [Transaction] and says whether it
/// did anything. Held to CodeMirror's own answers by `test/editor/commands/commands_test.dart`, over the fixture
/// `tool/command_fixtures.mjs` records from the real library under jsdom.
///
/// What differs:
/// - Text runs left to right, always (the app has no right-to-left handling): a line is one bidi span, so
///   `cursorCharLeft` is [cursorCharBackward], `cursorGroupRight` is [cursorGroupForward], and so on. Both names
///   are here. A caret moved by character still carries bidi level 0, as CodeMirror's does.
/// - The commands that take an `EditorView` in CodeMirror take a state here. What the view answered there:
///   - atomic ranges (`EditorView.atomicRanges`) come from the [atomicRangesFor] facet, empty until the view
///     provides them;
///   - `view.lineBlockAt` is the document's line, and `view.moveToLineBoundary` its ends: lines are taken as
///     UNWRAPPED. On a wrapped line the web's Home/End stop at the wrap point, which only a layout knows; the view
///     has to bind its own motion there (see "left to the view");
///   - [deleteLine] asks where the caret goes one line down. That is pixels on the web (`view.moveVertically`);
///     here it is the [verticalMotion] facet, which answers by column ([moveVerticallyByColumn]) until the view
///     provides the real thing;
///   - `EditorView.announce` ("Selection deleted") is the [announce] effect.
/// - Indentation is what the web app's configuration computes, not a general engine: its only language is
///   Markdown, whose `indentNodeProp` answers null for the Document, no node of @lezer/markdown has `closedBy`
///   or `openedBy`, and no `indentService` is configured. So [getIndentation] is always null (a new line takes
///   the indentation of the line it came from, [indentSelection] changes nothing), `isBetweenBrackets` is only its
///   text test (`()`, `[]`, `{}`), and [matchBrackets] is `matchPlainBrackets`.
/// - The syntax tree is `syntax_tree.dart`'s: Markdown alone. The web hands HTML blocks and tags to @lezer/html,
///   so inside them its `cursorSyntaxLeft/Right`, `selectParentSyntax`, bracket matching, and word motion (HTML's
///   `wordChars` are `-_`) answer by HTML's nodes; here they answer by Markdown's. The fixture leaves those cases
///   out and counts them.
/// - `moveLineUp`/`moveLineDown` keep CodeMirror's main index even when a block that could not move dropped its
///   ranges; where that index would point past the ranges left (a selection CodeMirror then breaks on), it is the
///   last range here.
/// - Language data is typed: `commentTokens` is a [CommentTokens].
///
/// Left to the view (bound in the keymaps below with a null `run` and the command's name in `viewCommand`):
/// - `cursorLineUp`, `cursorLineDown`, `selectLineUp`, `selectLineDown`: need `moveVertically(range, forward)`,
///   the position one visual line away at the caret's goal column (pixels), and `moveToLineBoundary` when that
///   does not move.
/// - `cursorPageUp`, `cursorPageDown`, `selectPageUp`, `selectPageDown`: need `moveVertically(range, forward,
///   distance)` with the page's height, and the scroll position to keep the caret's place on screen.
/// - `addCursorAbove`, `addCursorBelow`: `moveVertically` again.
/// - `cursorLineBoundaryForward/Backward` and `deleteLineBoundaryForward/Backward` on a WRAPPED line: need
///   `coordsAtPos` and `posAtCoords`. They are here for the unwrapped line, which is also what CodeMirror falls back
///   to.
/// - `toggleTabFocusMode`: the view's focus handling.
/// Not ported: `cursorSubwordForward/Backward` and their select twins (not in any keymap; they use
/// `Intl.Segmenter`), `temporarilySetTabFocusMode`.
library;

import '../state/change.dart';
import '../state/char.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../syntax/tree.dart';
import 'syntax_tree.dart';

// ---------------------------------------------------------------------------------------------------------------
// What the view and the language supply
// ---------------------------------------------------------------------------------------------------------------

/// What [atomicRangesFor] takes: the ranges a caret may not stand inside (a hidden marker, a widget), for a state.
typedef AtomicRangesFor = List<({int from, int to})> Function(EditorState state);

/// CodeMirror's `EditorView.atomicRanges`, for the commands: motion by character and by group steps over these
/// ranges, and a deletion that would end inside one takes it whole. Empty by default; the view provides its own.
/// Each provider's ranges must be sorted by `from`, as a range set is.
final Facet<AtomicRangesFor, List<AtomicRangesFor>> atomicRangesFor = Facet.define<AtomicRangesFor, List<AtomicRangesFor>>();

/// What [verticalMotion] takes: CodeMirror's `view.moveVertically(range, forward)`.
typedef VerticalMotion = SelectionRange Function(EditorState state, SelectionRange range, bool forward);

/// Where a caret goes one line up or down, for [deleteLine]. The first provider answers;
/// [moveVerticallyByColumn] when there is none. The view provides the real one, by pixels (and, on a wrapped line,
/// by the distance `deleteLine` gives `moveVertically` in CodeMirror, so the caret leaves the whole line).
final Facet<VerticalMotion, VerticalMotion> verticalMotion = Facet.define<VerticalMotion, VerticalMotion>(
  combine: (values) => values.isNotEmpty ? values[0] : moveVerticallyByColumn,
);

/// A vertical move without a layout: the same column (tabs counted, a cluster one column) on the next or the
/// previous line, and no move on the last or the first.
SelectionRange moveVerticallyByColumn(EditorState state, SelectionRange range, bool forward) {
  final line = state.doc.lineAt(range.head);
  if (line.number == (forward ? state.doc.lines : 1)) return EditorSelection.cursor(range.head);
  final next = state.doc.line(line.number + (forward ? 1 : -1));
  final col = countColumn(line.text, state.tabSize, range.head - line.from);
  return EditorSelection.cursor(next.from + findColumn(next.text, col, state.tabSize));
}

/// CodeMirror's `EditorView.announce`: words for a screen reader. [deleteCharBackward] and the other deletions send
/// "Selection deleted" (through [EditorState.phrase]) when they delete a selection.
final StateEffectType<String> announce = StateEffect.define<String>();

/// CodeMirror's `CommentTokens`: how a language writes a comment, read from the `commentTokens` language data.
class CommentTokens {
  /// Either part may be missing.
  const CommentTokens({this.line, this.block});

  /// What starts a comment that runs to the end of its line.
  final String? line;

  /// What opens and closes a block comment.
  final BlockCommentTokens? block;
}

/// The `block` part of [CommentTokens].
class BlockCommentTokens {
  /// The two marks.
  const BlockCommentTokens({required this.open, required this.close});

  /// What opens the comment.
  final String open;

  /// What closes it.
  final String close;
}

/// What lang-markdown's language answers for language data (its `commonmarkLanguage` data facet, which
/// `markdownLanguage` and the app's language share): `commentTokens`, a block comment `<!--` `-->`, and nothing
/// else (no `closeBrackets`, no `wordChars`), the same at every position. A state made with this extension answers
/// [EditorState.languageDataAt] as the web's does outside nested HTML.
final Extension markdownLanguageData = EditorState.languageData.of(_markdownData);

const List<Map<String, Object?>> _markdownDataValue = <Map<String, Object?>>[
  <String, Object?>{'commentTokens': CommentTokens(block: BlockCommentTokens(open: '<!--', close: '-->'))},
];

List<Map<String, Object?>> _markdownData(EditorState state, int pos, int side) => _markdownDataValue;

// ---------------------------------------------------------------------------------------------------------------
// @codemirror/language: indentation
// ---------------------------------------------------------------------------------------------------------------

final RegExp _notSpace = RegExp(r'\S');

/// CodeMirror's `indentUnit`: what one level of indentation is, a string of one whitespace character repeated. Two
/// spaces when nothing says.
final Facet<String, String> indentUnit = Facet.define<String, String>(
  combine: (values) {
    if (values.isEmpty) return '  ';
    final unit = values[0];
    if (unit.isEmpty || _notSpace.hasMatch(unit) || unit.split('').any((e) => e != unit[0])) {
      throw ArgumentError('Invalid indent unit: "${values[0]}"');
    }
    return unit;
  },
);

/// CodeMirror's `getIndentUnit`: the column width of an indent unit ([indentUnit], and the tab size when it is
/// tabs).
int getIndentUnit(EditorState state) {
  final unit = state.facet(indentUnit);
  return unit.codeUnitAt(0) == 9 ? state.tabSize * unit.length : unit.length;
}

/// CodeMirror's `indentString`: the whitespace that covers columns 0 to `cols`, in tabs as far as they go when the
/// indent unit is tabs.
String indentString(EditorState state, int cols) {
  final result = StringBuffer();
  final ts = state.tabSize;
  var ch = state.facet(indentUnit)[0];
  if (ch == '\t') {
    while (cols >= ts) {
      result.write('\t');
      cols -= ts;
    }
    ch = ' ';
  }
  for (var i = 0; i < cols; i++) {
    result.write(ch);
  }
  return result.toString();
}

/// CodeMirror's `IndentContext`: a state with a line break imagined into it, for working out an indentation as if
/// the break were already there.
class IndentContext {
  /// `simulateBreak` is where the imagined break is; `simulateDoubleBreak` imagines two (a caret between
  /// brackets); `overrideIndentation` answers a line's indentation by its start, or -1 to read the text.
  IndentContext(this.state, {this.simulateBreak, this.simulateDoubleBreak = false, this.overrideIndentation})
    : unit = getIndentUnit(state);

  /// The editor state.
  final EditorState state;

  /// The position of the imagined line break, if there is one.
  final int? simulateBreak;

  /// Whether two breaks are imagined at [simulateBreak].
  final bool simulateDoubleBreak;

  /// Indentations that are not the text's (lines [indentSelection] has already redone).
  final int Function(int start)? overrideIndentation;

  /// The indent unit, in columns.
  final int unit;

  /// The line at `pos` with the imagined break taken into account: before it for a negative `bias` when the break
  /// is at `pos`, after it otherwise.
  ({String text, int from}) lineAt(int pos, [int bias = 1]) {
    final line = state.doc.lineAt(pos);
    final simulateBreak = this.simulateBreak;
    if (simulateBreak != null && simulateBreak >= line.from && simulateBreak <= line.to) {
      if (simulateDoubleBreak && simulateBreak == pos) {
        return (text: '', from: pos);
      } else if (bias < 0 ? simulateBreak < pos : simulateBreak <= pos) {
        return (text: line.text.substring(simulateBreak - line.from), from: simulateBreak);
      } else {
        return (text: line.text.substring(0, simulateBreak - line.from), from: line.from);
      }
    }
    return (text: line.text, from: line.from);
  }

  /// The text directly after `pos`: the rest of the line, or 100 characters of it.
  String textAfterPos(int pos, [int bias = 1]) {
    if (simulateDoubleBreak && pos == simulateBreak) return '';
    final (:text, :from) = lineAt(pos, bias);
    return _slice(text, pos - from, text.length < pos + 100 - from ? text.length : pos + 100 - from);
  }

  /// The column of `pos`.
  int column(int pos, [int bias = 1]) {
    final (:text, :from) = lineAt(pos, bias);
    var result = countColumn(text, pos - from);
    final override = overrideIndentation != null ? overrideIndentation!(from) : -1;
    if (override > -1) result += override - countColumn(text, _indentEnd(text));
    return result;
  }

  /// The column of offset `pos` in `line`, tabs counted.
  int countColumn(String line, [int? pos]) => _countColumn(line, state.tabSize, pos ?? line.length);

  /// The indentation, in columns, of the line at `pos`.
  int lineIndent(int pos, [int bias = 1]) {
    final (:text, :from) = lineAt(pos, bias);
    final override = overrideIndentation;
    if (override != null) {
      final overriden = override(from);
      if (overriden > -1) return overriden;
    }
    return countColumn(text, _indentEnd(text));
  }

  /// The imagined break, if any. (As CodeMirror's `simulateBreak || null`: a break at 0 reads as none.)
  int? get simulatedBreak => simulateBreak == null || simulateBreak == 0 ? null : simulateBreak;
}

int _countColumn(String string, int tabSize, int to) => countColumn(string, tabSize, to);

// `text.search(/\S|$/)`
int _indentEnd(String text) {
  final at = text.indexOf(_nonSpace);
  return at < 0 ? text.length : at;
}

/// CodeMirror's `getIndentation`: the indentation, in columns, a line starting at `pos` should have, or null when
/// nothing can say. With the web app's configuration nothing ever can (see "What differs" at the head of this
/// file): no indent service, and Markdown's tree answers null. The commands then keep the indentation they find.
int? getIndentation(IndentContext context, int pos) => null;

// ---------------------------------------------------------------------------------------------------------------
// @codemirror/language: matching brackets
// ---------------------------------------------------------------------------------------------------------------

/// CodeMirror's `MatchResult`: the bracket at a position and the one that goes with it.
typedef MatchResult = ({({int from, int to}) start, ({int from, int to})? end, bool matched});

const int _defaultScanDist = 10000;
const String _defaultBrackets = '()[]{}';

/// CodeMirror's `matchBrackets`: the match of the bracket at `pos`, looking in direction `dir` (1: a bracket that
/// opens after `pos`; -1: one that closes before it). Null when there is no bracket there. Markdown's tree marks
/// no brackets, so this is `matchPlainBrackets`: characters of `brackets` (pairs, opener first) counted through
/// the text, only those in nodes of the type the first one is in.
MatchResult? matchBrackets(
  EditorState state,
  int pos,
  int dir, {
  int maxScanDistance = _defaultScanDist,
  String brackets = _defaultBrackets,
}) {
  final tree = syntaxTree(state), node = tree.resolveInner(pos, dir);
  return _matchPlainBrackets(state, pos, dir, tree, node.type, maxScanDistance, brackets);
}

MatchResult? _matchPlainBrackets(EditorState state, int pos, int dir, Tree tree, NodeType tokenType, int maxScanDistance, String brackets) {
  if (dir < 0 ? pos == 0 : pos == state.doc.length) return null;
  final startCh = dir < 0 ? state.sliceDoc(pos - 1, pos) : state.sliceDoc(pos, pos + 1);
  final bracket = brackets.indexOf(startCh);
  if (bracket < 0 || (bracket % 2 == 0) != (dir > 0)) return null;

  final startToken = (from: dir < 0 ? pos - 1 : pos, to: dir > 0 ? pos + 1 : pos);
  final iter = state.doc.iterRange(pos, dir > 0 ? state.doc.length : 0);
  var depth = 0;
  for (var distance = 0; !iter.next().done && distance <= maxScanDistance;) {
    final text = iter.value;
    if (dir < 0) distance += text.length;
    final basePos = pos + distance * dir;
    for (var pos = dir > 0 ? 0 : text.length - 1, end = dir > 0 ? text.length : -1; pos != end; pos += dir) {
      final found = brackets.indexOf(text[pos]);
      if (found < 0 || !identical(tree.resolveInner(basePos + pos, 1).type, tokenType)) continue;
      if ((found % 2 == 0) == (dir > 0)) {
        depth++;
      } else if (depth == 1) {
        // Closing
        return (start: startToken, end: (from: basePos + pos, to: basePos + pos + 1), matched: (found >> 1) == (bracket >> 1));
      } else {
        depth--;
      }
    }
    if (dir > 0) distance += text.length;
  }
  return iter.done ? (start: startToken, end: null, matched: false) : null;
}

// ---------------------------------------------------------------------------------------------------------------
// JavaScript's strings, where the source leans on them
// ---------------------------------------------------------------------------------------------------------------

final RegExp _nonSpace = RegExp(r'\S');
final RegExp _space = RegExp(r'\s');
final RegExp _leadingSpace = RegExp(r'^\s*');
final RegExp _trailingSpace = RegExp(r'\s*$');

// `String.prototype.slice`: a negative index counts from the end, anything past an end is the end.
String _slice(String s, int start, [int? end]) {
  final length = s.length;
  var from = start < 0 ? length + start : start, to = end == null ? length : (end < 0 ? length + end : end);
  if (from < 0) from = 0;
  if (to > length) to = length;
  return from >= to ? '' : s.substring(from, to);
}

// `s.charAt(i)`, and `s[i]` where a missing one is compared to a string: empty outside the string.
String _charAt(String s, int index) => index < 0 || index >= s.length ? '' : s[index];

// `/^\s*/.exec(s)[0]`
String _indentOf(String s) => _leadingSpace.firstMatch(s)![0]!;

// `state.sliceDoc`, with ends outside the document cut to it, as CodeMirror's `Text.sliceString` cuts them.
String _sliceDoc(EditorState state, int from, int to) {
  final length = state.doc.length;
  final a = from < 0 ? 0 : (from > length ? length : from), b = to > length ? length : to;
  return b <= a ? '' : state.sliceDoc(a, b);
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

// ---------------------------------------------------------------------------------------------------------------
// comment.ts
// ---------------------------------------------------------------------------------------------------------------

/// Comment or uncomment the current selection. Will use line comments if available, otherwise falling back to
/// block comments. (Markdown has only block comments, so this is [toggleBlockCommentByLine] there.)
bool toggleComment(StateCommandTarget target) {
  final state = target.state, line = state.doc.lineAt(state.selection.main.from), config = _getConfig(target.state, line.from);
  return config.line != null
      ? toggleLineComment(target)
      : config.block != null
      ? toggleBlockCommentByLine(target)
      : false;
}

// CommentOption
const int _optToggle = 0, _optComment = 1, _optUncomment = 2;

StateCommand _command(TransactionSpec? Function(int option, EditorState state) f, int option) {
  return (StateCommandTarget target) {
    final state = target.state;
    if (state.readOnly) return false;
    final tr = f(option, state);
    if (tr == null) return false;
    target.dispatch(state.update(tr));
    return true;
  };
}

/// Comment or uncomment the current selection using line comments. The line comment syntax is taken from the
/// `commentTokens` language data.
final StateCommand toggleLineComment = _command(_changeLineComment, _optToggle);

/// Comment the current selection using line comments.
final StateCommand lineComment = _command(_changeLineComment, _optComment);

/// Uncomment the current selection using line comments.
final StateCommand lineUncomment = _command(_changeLineComment, _optUncomment);

/// Comment or uncomment the current selection using block comments. The block comment syntax is taken from the
/// `commentTokens` language data.
final StateCommand toggleBlockComment = _command(_changeBlockComment, _optToggle);

/// Comment the current selection using block comments.
final StateCommand blockComment = _command(_changeBlockComment, _optComment);

/// Uncomment the current selection using block comments.
final StateCommand blockUncomment = _command(_changeBlockComment, _optUncomment);

/// Comment or uncomment the lines around the current selection using block comments.
final StateCommand toggleBlockCommentByLine = _command((o, s) => _changeBlockComment(o, s, _selectedLineRanges(s)), _optToggle);

CommentTokens _getConfig(EditorState state, int pos) {
  final data = state.languageDataAt<Object?>('commentTokens', pos, 1);
  return data.isNotEmpty && data[0] is CommentTokens ? data[0]! as CommentTokens : const CommentTokens();
}

const int _searchMargin = 50;

typedef _CommentEnd = ({int pos, int margin});

/// Determines if the given range is block-commented in the given state.
({_CommentEnd open, _CommentEnd close})? _findBlockComment(EditorState state, BlockCommentTokens tokens, int from, int to) {
  final open = tokens.open, close = tokens.close;
  final textBefore = _sliceDoc(state, from - _searchMargin, from);
  final textAfter = _sliceDoc(state, to, to + _searchMargin);
  final spaceBefore = _trailingSpace.firstMatch(textBefore)![0]!.length, spaceAfter = _leadingSpace.firstMatch(textAfter)![0]!.length;
  final beforeOff = textBefore.length - spaceBefore;
  if (_slice(textBefore, beforeOff - open.length, beforeOff) == open && _slice(textAfter, spaceAfter, spaceAfter + close.length) == close) {
    return (
      open: (pos: from - spaceBefore, margin: spaceBefore != 0 ? 1 : 0),
      close: (pos: to + spaceAfter, margin: spaceAfter != 0 ? 1 : 0),
    );
  }
  String startText, endText;
  if (to - from <= 2 * _searchMargin) {
    startText = endText = _sliceDoc(state, from, to);
  } else {
    startText = _sliceDoc(state, from, from + _searchMargin);
    endText = _sliceDoc(state, to - _searchMargin, to);
  }
  final startSpace = _leadingSpace.firstMatch(startText)![0]!.length, endSpace = _trailingSpace.firstMatch(endText)![0]!.length;
  final endOff = endText.length - endSpace - close.length;
  if (_slice(startText, startSpace, startSpace + open.length) == open && _slice(endText, endOff, endOff + close.length) == close) {
    return (
      open: (pos: from + startSpace + open.length, margin: _space.hasMatch(_charAt(startText, startSpace + open.length)) ? 1 : 0),
      close: (pos: to - endSpace - close.length, margin: _space.hasMatch(_charAt(endText, endOff - 1)) ? 1 : 0),
    );
  }
  return null;
}

typedef _FromTo = ({int from, int to});

List<_FromTo> _selectedLineRanges(EditorState state) {
  final ranges = <_FromTo>[];
  for (final r in state.selection.ranges) {
    final fromLine = state.doc.lineAt(r.from);
    var toLine = r.to <= fromLine.to ? fromLine : state.doc.lineAt(r.to);
    if (toLine.from > fromLine.from && toLine.from == r.to) {
      toLine = r.to == fromLine.to + 1 ? fromLine : state.doc.lineAt(r.to - 1);
    }
    final last = ranges.length - 1;
    if (last >= 0 && ranges[last].to > fromLine.from) {
      ranges[last] = (from: ranges[last].from, to: toLine.to);
    } else {
      ranges.add((from: fromLine.from + _indentOf(fromLine.text).length, to: toLine.to));
    }
  }
  return ranges;
}

// Performs toggle, comment and uncomment of block comments in languages that support them.
TransactionSpec? _changeBlockComment(int option, EditorState state, [List<_FromTo>? ranges]) {
  ranges ??= <_FromTo>[for (final r in state.selection.ranges) (from: r.from, to: r.to)];
  final tokens = <BlockCommentTokens?>[for (final r in ranges) _getConfig(state, r.from).block];
  if (!tokens.every((c) => c != null)) return null;
  final comments = <({_CommentEnd open, _CommentEnd close})?>[
    for (var i = 0; i < ranges.length; i++) _findBlockComment(state, tokens[i]!, ranges[i].from, ranges[i].to),
  ];
  if (option != _optUncomment && !comments.every((c) => c != null)) {
    return TransactionSpec(
      changes: state.changes(<ChangeSpec>[
        for (var i = 0; i < ranges.length; i++)
          if (comments[i] == null) ...<ChangeSpec>[
            ChangeSpec(from: ranges[i].from, insert: '${tokens[i]!.open} '),
            ChangeSpec(from: ranges[i].to, insert: ' ${tokens[i]!.close}'),
          ],
      ]),
    );
  } else if (option != _optComment && comments.any((c) => c != null)) {
    final changes = <ChangeSpec>[];
    for (var i = 0; i < comments.length; i++) {
      final comment = comments[i];
      if (comment != null) {
        final token = tokens[i]!, open = comment.open, close = comment.close;
        changes
          ..add(ChangeSpec(from: open.pos - token.open.length, to: open.pos + open.margin))
          ..add(ChangeSpec(from: close.pos - close.margin, to: close.pos + token.close.length));
      }
    }
    return TransactionSpec(changes: changes);
  }
  return null;
}

class _CommentLine {
  _CommentLine(this.line, this.comment, this.token, this.indent, this.empty);

  final Line line;
  final int comment;
  final String token;
  int indent;
  final bool empty;
  bool single = false;
}

// Performs toggle, comment and uncomment of line comments.
TransactionSpec? _changeLineComment(int option, EditorState state, [List<_FromTo>? ranges]) {
  ranges ??= <_FromTo>[for (final r in state.selection.ranges) (from: r.from, to: r.to)];
  final lines = <_CommentLine>[];
  var prevLine = -1;
  ranges:
  for (final (:from, :to) in ranges) {
    final startI = lines.length;
    var minIndent = 1000000000;
    String? token;
    for (var pos = from; pos <= to;) {
      final line = state.doc.lineAt(pos);
      if (token == null) {
        token = _getConfig(state, line.from).line;
        if (token == null || token.isEmpty) continue ranges;
      }
      if (line.from > prevLine && (from == to || to > line.from)) {
        prevLine = line.from;
        final indent = _indentOf(line.text).length;
        final empty = indent == line.length;
        final comment = _slice(line.text, indent, indent + token.length) == token ? indent : -1;
        if (indent < line.text.length && indent < minIndent) minIndent = indent;
        lines.add(_CommentLine(line, comment, token, indent, empty));
      }
      pos = line.to + 1;
    }
    if (minIndent < 1000000000) {
      for (var i = startI; i < lines.length; i++) {
        if (lines[i].indent < lines[i].line.text.length) lines[i].indent = minIndent;
      }
    }
    if (lines.length == startI + 1) lines[startI].single = true;
  }
  if (option != _optUncomment && lines.any((l) => l.comment < 0 && (!l.empty || l.single))) {
    final changes = <ChangeSpec>[];
    for (final l in lines) {
      if (l.single || !l.empty) changes.add(ChangeSpec(from: l.line.from + l.indent, insert: '${l.token} '));
    }
    final changeSet = state.changes(changes);
    return TransactionSpec(changes: changeSet, selection: state.selection.map(changeSet, 1));
  } else if (option != _optComment && lines.any((l) => l.comment >= 0)) {
    final changes = <ChangeSpec>[];
    for (final l in lines) {
      if (l.comment >= 0) {
        final from = l.line.from + l.comment;
        var to = from + l.token.length;
        if (_charAt(l.line.text, to - l.line.from) == ' ') to++;
        changes.add(ChangeSpec(from: from, to: to));
      }
    }
    return TransactionSpec(changes: changes);
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------
// @codemirror/view: motion (cursor.ts), over the state alone
// ---------------------------------------------------------------------------------------------------------------

// The atomic ranges every provider gives for this state.
List<List<({int from, int to})>> _atoms(EditorState state) {
  final providers = state.facet(atomicRangesFor);
  return providers.isEmpty ? const <List<({int from, int to})>>[] : <List<({int from, int to})>>[for (final f in providers) f(state)];
}

// `skipAtomicRanges`: a position inside an atomic range moves to its edge: the side `bias` says, the nearer one for
// no bias, and the same side again for any range that edge lands in.
int _skipAtomicRanges(List<List<({int from, int to})>> atoms, int pos, int bias) {
  for (;;) {
    var moved = 0;
    for (final set in atoms) {
      // `set.between(pos - 1, pos + 1, ...)`: the bounds are read once, the position moves as it goes.
      final lo = pos - 1, hi = pos + 1;
      for (final (:from, :to) in set) {
        if (from > hi) break;
        if (to < lo) continue;
        if (pos > from && pos < to) {
          final side = moved != 0
              ? moved
              : bias != 0
              ? bias
              : (pos - from < to - pos ? -1 : 1);
          pos = side < 0 ? from : to;
          moved = side;
        }
      }
    }
    if (moved == 0) return pos;
  }
}

// `skipAtoms`
SelectionRange _skipAtoms(EditorState state, SelectionRange oldPos, SelectionRange pos) {
  final atoms = _atoms(state);
  if (atoms.isEmpty) return pos;
  final newPos = _skipAtomicRanges(atoms, pos.from, oldPos.head > pos.from ? -1 : 1);
  return newPos == pos.from ? pos : EditorSelection.cursor(newPos, newPos < pos.from ? 1 : -1);
}

// What `moveVisually` moved over.
String _movedOver = '';

// `moveVisually` for a line that is one left-to-right span: the next cluster, or null at the line's end.
SelectionRange? _moveVisually(Line line, SelectionRange start, bool forward) {
  final startIndex = start.head - line.from;
  // End of span
  if (startIndex == (forward ? line.length : 0)) return null;
  final nextIndex = findClusterBreak(line.text, startIndex, forward);
  _movedOver = line.text.substring(_min(startIndex, nextIndex), _max(startIndex, nextIndex));
  return EditorSelection.cursor(nextIndex + line.from, forward ? -1 : 1, 0);
}

// `moveByChar` (the function, before atomic ranges)
SelectionRange _moveByCharPlain(EditorState state, SelectionRange start, bool forward, [bool Function(String next) Function(String initial)? by]) {
  var line = state.doc.lineAt(start.head);
  bool Function(String next)? check;
  for (var cur = start;;) {
    var next = _moveVisually(line, cur, forward);
    var char = _movedOver;
    if (next == null) {
      if (line.number == (forward ? state.doc.lines : 1)) return cur;
      char = '\n';
      line = state.doc.line(line.number + (forward ? 1 : -1));
      // view.visualLineSide(line, !forward)
      next = forward ? EditorSelection.cursor(line.from, 1) : EditorSelection.cursor(line.to, -1);
    }
    if (check == null) {
      if (by == null) return next;
      check = by(char);
    } else if (!check(char)) {
      return cur;
    }
    cur = next;
  }
}

/// CodeMirror's `view.moveByChar`: the caret one cluster on from `start`, across the line break at a line's end,
/// and where it was when there is nowhere to go. With `by`, further: it is given the first cluster and returns
/// the test every next one must pass to be moved over too. Atomic ranges ([atomicRangesFor]) are stepped over.
SelectionRange moveByChar(EditorState state, SelectionRange start, bool forward, [bool Function(String next) Function(String initial)? by]) =>
    _skipAtoms(state, start, _moveByCharPlain(state, start, forward, by));

// `byGroup`
bool Function(String next) _byGroup(EditorState state, int pos, String start) {
  final categorize = state.charCategorizer(pos);
  var cat = categorize(start);
  return (String next) {
    final nextCat = categorize(next);
    if (cat == CharCategory.space) cat = nextCat;
    return cat == nextCat;
  };
}

/// CodeMirror's `view.moveByGroup`: the caret across the next group of word characters, or of other characters
/// that are not spaces (spaces before the group are crossed with it).
SelectionRange moveByGroup(EditorState state, SelectionRange start, bool forward) =>
    _skipAtoms(state, start, _moveByCharPlain(state, start, forward, (initial) => _byGroup(state, start.head, initial)));

/// CodeMirror's `view.moveToLineBoundary` for a line that does not wrap: the line's end or its start.
SelectionRange moveToLineBoundary(EditorState state, SelectionRange start, bool forward) {
  final line = state.doc.lineAt(start.head);
  return EditorSelection.cursor(forward ? line.to : line.from, forward ? -1 : 1);
}

// ---------------------------------------------------------------------------------------------------------------
// commands.ts: moving the selection
// ---------------------------------------------------------------------------------------------------------------

EditorSelection _updateSel(EditorSelection sel, SelectionRange Function(SelectionRange range) by) =>
    EditorSelection.create(<SelectionRange>[for (final r in sel.ranges) by(r)], sel.mainIndex);

Transaction _setSel(EditorState state, EditorSelection selection) =>
    state.update(TransactionSpec(selection: selection, scrollIntoView: true, userEvent: 'select'));

bool _moveSel(StateCommandTarget target, SelectionRange Function(SelectionRange range) how) {
  final state = target.state;
  final selection = _updateSel(state.selection, how);
  if (selection.eq(state.selection, true)) return false;
  target.dispatch(_setSel(state, selection));
  return true;
}

SelectionRange _rangeEnd(SelectionRange range, bool forward) => EditorSelection.cursor(forward ? range.to : range.from);

bool _cursorByChar(StateCommandTarget target, bool forward) =>
    _moveSel(target, (range) => range.empty ? moveByChar(target.state, range, forward) : _rangeEnd(range, forward));

/// Move the selection one character to the left (which is backward: text is left to right here).
bool cursorCharLeft(StateCommandTarget target) => _cursorByChar(target, false);

/// Move the selection one character to the right.
bool cursorCharRight(StateCommandTarget target) => _cursorByChar(target, true);

/// Move the selection one character forward.
bool cursorCharForward(StateCommandTarget target) => _cursorByChar(target, true);

/// Move the selection one character backward.
bool cursorCharBackward(StateCommandTarget target) => _cursorByChar(target, false);

SelectionRange _byCharLogical(EditorState state, SelectionRange range, bool forward) {
  var pos = range.head;
  final line = state.doc.lineAt(pos);
  if (pos == (forward ? line.to : line.from)) {
    pos = forward ? _min(state.doc.length, line.to + 1) : _max(0, line.from - 1);
  } else {
    pos = line.from + findClusterBreak(line.text, pos - line.from, forward);
  }
  return EditorSelection.cursor(pos, forward ? -1 : 1);
}

bool _moveByCharLogical(StateCommandTarget target, bool forward) =>
    _moveSel(target, (range) => range.empty ? _byCharLogical(target.state, range, forward) : _rangeEnd(range, forward));

/// Move the selection one character forward, in logical (non-text-direction-aware) string index order.
bool cursorCharForwardLogical(StateCommandTarget target) => _moveByCharLogical(target, true);

/// Move the selection one character backward, in logical string index order.
bool cursorCharBackwardLogical(StateCommandTarget target) => _moveByCharLogical(target, false);

bool _cursorByGroup(StateCommandTarget target, bool forward) =>
    _moveSel(target, (range) => range.empty ? moveByGroup(target.state, range, forward) : _rangeEnd(range, forward));

/// Move the selection to the left across one group of word or non-word (but also non-space) characters.
bool cursorGroupLeft(StateCommandTarget target) => _cursorByGroup(target, false);

/// Move the selection one group to the right.
bool cursorGroupRight(StateCommandTarget target) => _cursorByGroup(target, true);

/// Move the selection one group forward.
bool cursorGroupForward(StateCommandTarget target) => _cursorByGroup(target, true);

/// Move the selection one group backward.
bool cursorGroupBackward(StateCommandTarget target) => _cursorByGroup(target, false);

bool Function(String next) _toGroupStart(EditorState state, int pos, String start) {
  final categorize = state.charCategorizer(pos);
  final cat = categorize(start);
  var initial = cat != CharCategory.space;
  return (String next) {
    final nextCat = categorize(next);
    if (nextCat != CharCategory.space) return initial && nextCat == cat;
    initial = false;
    return true;
  };
}

/// Move the cursor one group forward in the default Windows style, where it moves to the start of the next group.
bool cursorGroupForwardWin(StateCommandTarget target) => _moveSel(
  target,
  (range) => range.empty
      ? moveByChar(target.state, range, true, (start) => _toGroupStart(target.state, range.head, start))
      : _rangeEnd(range, true),
);

final RegExp _interesting = RegExp(r'[^\s,.;:]');

bool _interestingNode(EditorState state, SyntaxNode node) {
  // No node of Markdown's has `closedBy` or `openedBy`.
  final len = node.to - node.from;
  return len != 0 && (len > 2 || _interesting.hasMatch(state.sliceDoc(node.from, node.to))) || node.firstChild != null;
}

SelectionRange _moveBySyntax(EditorState state, SelectionRange start, bool forward) {
  var pos = syntaxTree(state).resolveInner(start.head);
  // Scan forward through child nodes to see if there's an interesting node ahead.
  for (var at = start.head;;) {
    final next = forward ? pos.childAfter(at) : pos.childBefore(at);
    if (next == null) break;
    if (_interestingNode(state, next)) {
      pos = next;
    } else {
      at = forward ? next.to : next.from;
    }
  }
  // (A node with a bracket prop would go to its match here.)
  final newPos = forward ? pos.to : pos.from;
  return EditorSelection.cursor(newPos, forward ? -1 : 1);
}

/// Move the cursor over the next syntactic element to the left.
bool cursorSyntaxLeft(StateCommandTarget target) => _moveSel(target, (range) => _moveBySyntax(target.state, range, false));

/// Move the cursor over the next syntactic element to the right.
bool cursorSyntaxRight(StateCommandTarget target) => _moveSel(target, (range) => _moveBySyntax(target.state, range, true));

SelectionRange _moveByLineBoundary(EditorState state, SelectionRange start, bool forward) {
  final line = state.doc.lineAt(start.head);
  var moved = moveToLineBoundary(state, start, forward);
  // (On a wrapped line CodeMirror tries again without the wrap points when this did not move.)
  if (!forward && moved.head == line.from && line.length != 0) {
    final space = _indentOf(state.sliceDoc(line.from, _min(line.from + 100, line.to))).length;
    if (space != 0 && start.head != line.from + space) moved = EditorSelection.cursor(line.from + space);
  }
  return moved;
}

/// Move the selection to the end of the line. (On the web: to the next line wrap point, or the end of the line
/// if there isn't one left on this line. Lines do not wrap here; see the head of this file.)
bool cursorLineBoundaryForward(StateCommandTarget target) => _moveSel(target, (range) => _moveByLineBoundary(target.state, range, true));

/// Move the selection to the start of the line. If the line is indented, and the cursor isn't already at the end
/// of the indentation, this will move to the end of the indentation instead of the start of the line.
bool cursorLineBoundaryBackward(StateCommandTarget target) => _moveSel(target, (range) => _moveByLineBoundary(target.state, range, false));

/// Move the selection one line boundary to the left: [cursorLineBoundaryBackward].
bool cursorLineBoundaryLeft(StateCommandTarget target) => _moveSel(target, (range) => _moveByLineBoundary(target.state, range, false));

/// Move the selection one line boundary to the right: [cursorLineBoundaryForward].
bool cursorLineBoundaryRight(StateCommandTarget target) => _moveSel(target, (range) => _moveByLineBoundary(target.state, range, true));

/// Move the selection to the start of the line.
bool cursorLineStart(StateCommandTarget target) =>
    _moveSel(target, (range) => EditorSelection.cursor(target.state.doc.lineAt(range.head).from, 1));

/// Move the selection to the end of the line.
bool cursorLineEnd(StateCommandTarget target) => _moveSel(target, (range) => EditorSelection.cursor(target.state.doc.lineAt(range.head).to, -1));

bool _toMatchingBracket(StateCommandTarget target, bool extend) {
  final state = target.state;
  var found = false;
  final selection = _updateSel(state.selection, (range) {
    // JavaScript's `a || b || (c && d) || (e && f)`: the first that is a result, matched or not.
    final matching =
        matchBrackets(state, range.head, -1) ??
        matchBrackets(state, range.head, 1) ??
        (range.head > 0 ? matchBrackets(state, range.head - 1, 1) : null) ??
        (range.head < state.doc.length ? matchBrackets(state, range.head + 1, -1) : null);
    if (matching == null || matching.end == null) return range;
    found = true;
    final head = matching.start.from == range.head ? matching.end!.to : matching.end!.from;
    return extend ? EditorSelection.range(range.anchor, head) : EditorSelection.cursor(head);
  });
  if (!found) return false;
  target.dispatch(_setSel(state, selection));
  return true;
}

/// Move the selection to the bracket matching the one it is currently on, if any.
bool cursorMatchingBracket(StateCommandTarget target) => _toMatchingBracket(target, false);

/// Extend the selection to the bracket matching the one the selection head is currently on, if any.
bool selectMatchingBracket(StateCommandTarget target) => _toMatchingBracket(target, true);

bool _extendSel(StateCommandTarget target, bool forward, SelectionRange Function(SelectionRange range) how) {
  final selection = _updateSel(target.state.selection, (range) {
    if (range.undirectional && (range.head >= range.anchor) != forward) range = EditorSelection.range(range.head, range.anchor);
    final head = how(range);
    // `head.bidiLevel || undefined`: level 0 is dropped with no level.
    return EditorSelection.range(range.anchor, head.head, head.goalColumn, head.bidiLevel == 0 ? null : head.bidiLevel, head.assoc);
  });
  if (selection.eq(target.state.selection)) return false;
  target.dispatch(_setSel(target.state, selection));
  return true;
}

bool _selectByChar(StateCommandTarget target, bool forward) => _extendSel(target, forward, (range) => moveByChar(target.state, range, forward));

/// Move the selection head one character to the left, while leaving the anchor in place.
bool selectCharLeft(StateCommandTarget target) => _selectByChar(target, false);

/// Move the selection head one character to the right.
bool selectCharRight(StateCommandTarget target) => _selectByChar(target, true);

/// Move the selection head one character forward.
bool selectCharForward(StateCommandTarget target) => _selectByChar(target, true);

/// Move the selection head one character backward.
bool selectCharBackward(StateCommandTarget target) => _selectByChar(target, false);

/// Move the selection head one character forward by logical (non-direction aware) string index order.
bool selectCharForwardLogical(StateCommandTarget target) => _extendSel(target, true, (range) => _byCharLogical(target.state, range, true));

/// Move the selection head one character backward by logical string index order.
bool selectCharBackwardLogical(StateCommandTarget target) => _extendSel(target, false, (range) => _byCharLogical(target.state, range, false));

bool _selectByGroup(StateCommandTarget target, bool forward) => _extendSel(target, forward, (range) => moveByGroup(target.state, range, forward));

/// Move the selection head one group to the left.
bool selectGroupLeft(StateCommandTarget target) => _selectByGroup(target, false);

/// Move the selection head one group to the right.
bool selectGroupRight(StateCommandTarget target) => _selectByGroup(target, true);

/// Move the selection head one group forward.
bool selectGroupForward(StateCommandTarget target) => _selectByGroup(target, true);

/// Move the selection head one group backward.
bool selectGroupBackward(StateCommandTarget target) => _selectByGroup(target, false);

/// Move the selection head one group forward in the default Windows style, skipping to the start of the next
/// group.
bool selectGroupForwardWin(StateCommandTarget target) => _extendSel(
  target,
  true,
  (range) => moveByChar(target.state, range, true, (start) => _toGroupStart(target.state, range.head, start)),
);

/// Move the selection head over the next syntactic element to the left.
bool selectSyntaxLeft(StateCommandTarget target) => _extendSel(target, false, (range) => _moveBySyntax(target.state, range, false));

/// Move the selection head over the next syntactic element to the right.
bool selectSyntaxRight(StateCommandTarget target) => _extendSel(target, true, (range) => _moveBySyntax(target.state, range, true));

/// Move the selection head to the next line boundary.
bool selectLineBoundaryForward(StateCommandTarget target) => _extendSel(target, true, (range) => _moveByLineBoundary(target.state, range, true));

/// Move the selection head to the previous line boundary.
bool selectLineBoundaryBackward(StateCommandTarget target) =>
    _extendSel(target, false, (range) => _moveByLineBoundary(target.state, range, false));

/// Move the selection head one line boundary to the left.
bool selectLineBoundaryLeft(StateCommandTarget target) => _extendSel(target, false, (range) => _moveByLineBoundary(target.state, range, false));

/// Move the selection head one line boundary to the right.
bool selectLineBoundaryRight(StateCommandTarget target) => _extendSel(target, true, (range) => _moveByLineBoundary(target.state, range, true));

/// Move the selection head to the start of the line.
bool selectLineStart(StateCommandTarget target) =>
    _extendSel(target, false, (range) => EditorSelection.cursor(target.state.doc.lineAt(range.head).from));

/// Move the selection head to the end of the line.
bool selectLineEnd(StateCommandTarget target) => _extendSel(target, true, (range) => EditorSelection.cursor(target.state.doc.lineAt(range.head).to));

/// Move the selection to the start of the document.
bool cursorDocStart(StateCommandTarget target) {
  target.dispatch(_setSel(target.state, EditorSelection.single(0)));
  return true;
}

/// Move the selection to the end of the document.
bool cursorDocEnd(StateCommandTarget target) {
  target.dispatch(_setSel(target.state, EditorSelection.single(target.state.doc.length)));
  return true;
}

/// Move the selection head to the start of the document.
bool selectDocStart(StateCommandTarget target) {
  target.dispatch(_setSel(target.state, EditorSelection.single(target.state.selection.main.anchor, 0)));
  return true;
}

/// Move the selection head to the end of the document.
bool selectDocEnd(StateCommandTarget target) {
  final state = target.state;
  target.dispatch(_setSel(state, EditorSelection.single(state.selection.main.anchor, state.doc.length)));
  return true;
}

/// Select the entire document.
bool selectAll(StateCommandTarget target) {
  final state = target.state;
  target.dispatch(state.update(TransactionSpec(selection: EditorSelection.single(0, state.doc.length), userEvent: 'select')));
  return true;
}

/// Expand the selection to cover entire lines.
bool selectLine(StateCommandTarget target) {
  final state = target.state;
  final ranges = <SelectionRange>[
    for (final block in _selectedLineBlocks(state)) EditorSelection.undirectionalRange(block.from, _min(block.to + 1, state.doc.length)),
  ];
  target.dispatch(state.update(TransactionSpec(selection: EditorSelection.create(ranges), userEvent: 'select')));
  return true;
}

/// Select the next syntactic construct that is larger than the selection.
bool selectParentSyntax(StateCommandTarget target) {
  final state = target.state;
  final selection = _updateSel(state.selection, (range) {
    // `tree.resolveStack(pos, side)`: with no nested trees, the node `resolveInner` finds and its parents.
    final tree = syntaxTree(state);
    var stack = tree.resolveInner(range.from, 1);
    if (range.empty) {
      final stackBefore = tree.resolveInner(range.from, -1);
      if (stackBefore.from >= stack.from && stackBefore.to <= stack.to) stack = stackBefore;
    }
    for (SyntaxNode? cur = stack; cur != null; cur = cur.parent) {
      final node = cur;
      if (((node.from < range.from && node.to >= range.to) || (node.to > range.to && node.from <= range.from)) && cur.parent != null) {
        return EditorSelection.undirectionalRange(node.from, node.to);
      }
    }
    return range;
  });
  if (selection.eq(state.selection)) return false;
  target.dispatch(_setSel(state, selection));
  return true;
}

/// Simplify the current selection. When multiple ranges are selected, reduce it to its main range. Otherwise, if
/// the selection is non-empty, convert it to a cursor selection.
bool simplifySelection(StateCommandTarget target) {
  final state = target.state, cur = state.selection;
  EditorSelection? selection;
  if (cur.ranges.length > 1) {
    selection = EditorSelection.create(<SelectionRange>[cur.main]);
  } else if (!cur.main.empty) {
    selection = EditorSelection.create(<SelectionRange>[EditorSelection.cursor(cur.main.head)]);
  }
  if (selection == null) return false;
  target.dispatch(_setSel(state, selection));
  return true;
}

// ---------------------------------------------------------------------------------------------------------------
// commands.ts: deleting
// ---------------------------------------------------------------------------------------------------------------

bool _deleteBy(StateCommandTarget target, int Function(SelectionRange range) by) {
  if (target.state.readOnly) return false;
  var event = 'delete.selection';
  final state = target.state;
  final changes = state.changeByRange((range) {
    var from = range.from, to = range.to;
    if (from == to) {
      var towards = by(range);
      if (towards < from) {
        event = 'delete.backward';
        towards = _skipAtomic(state, towards, false);
      } else if (towards > from) {
        event = 'delete.forward';
        towards = _skipAtomic(state, towards, true);
      }
      from = _min(from, towards);
      to = _max(to, towards);
    } else {
      from = _skipAtomic(state, from, false);
      to = _skipAtomic(state, to, true);
    }
    return from == to
        ? RangeChange(range: range)
        : RangeChange(changes: ChangeSpec(from: from, to: to), range: EditorSelection.cursor(from, from < range.head ? -1 : 1));
  });
  if ((changes.changes! as ChangeSet).empty) return false;
  target.dispatch(
    state.updateAll(<TransactionSpec>[
      changes,
      TransactionSpec(
        scrollIntoView: true,
        userEvent: event,
        effects: event == 'delete.selection' ? announce.of(state.phrase('Selection deleted')) : null,
      ),
    ]),
  );
  return true;
}

int _skipAtomic(EditorState state, int pos, bool forward) {
  for (final ranges in _atoms(state)) {
    // `ranges.between(pos, pos, ...)`
    final at = pos;
    for (final (:from, :to) in ranges) {
      if (from > at) break;
      if (to < at) continue;
      if (from < pos && to > pos) pos = forward ? to : from;
    }
  }
  return pos;
}

final RegExp _notSpaceOrTab = RegExp(r'[^ \t]');
final RegExp _variationSelector = RegExp(r'[︀-️]');

bool _deleteByChar(StateCommandTarget target, bool forward, bool byIndentUnit) => _deleteBy(target, (range) {
  var pos = range.from;
  final state = target.state, line = state.doc.lineAt(pos);
  String before;
  int targetPos;
  if (byIndentUnit &&
      !forward &&
      pos > line.from &&
      pos < line.from + 200 &&
      !_notSpaceOrTab.hasMatch(before = line.text.substring(0, pos - line.from))) {
    if (before[before.length - 1] == '\t') return pos - 1;
    final col = countColumn(before, state.tabSize);
    final rest = col % getIndentUnit(state), drop = rest != 0 ? rest : getIndentUnit(state);
    for (var i = 0; i < drop && _charAt(before, before.length - 1 - i) == ' '; i++) {
      pos--;
    }
    targetPos = pos;
  } else {
    targetPos = findClusterBreak(line.text, pos - line.from, forward, forward) + line.from;
    if (targetPos == pos && line.number != (forward ? state.doc.lines : 1)) {
      targetPos += forward ? 1 : -1;
    } else if (!forward && _variationSelector.hasMatch(_slice(line.text, targetPos - line.from, pos - line.from))) {
      targetPos = findClusterBreak(line.text, targetPos - line.from, false, false) + line.from;
    }
  }
  return targetPos;
});

/// Delete the selection, or, for cursor selections, the character or indentation unit before the cursor.
bool deleteCharBackward(StateCommandTarget target) => _deleteByChar(target, false, true);

/// Delete the selection or the character before the cursor. Does not implement any extended behavior like
/// deleting whole indentation units in one go.
bool deleteCharBackwardStrict(StateCommandTarget target) => _deleteByChar(target, false, false);

/// Delete the selection or the character after the cursor.
bool deleteCharForward(StateCommandTarget target) => _deleteByChar(target, true, false);

bool _deleteByGroup(StateCommandTarget target, bool forward) => _deleteBy(target, (range) {
  var pos = range.head;
  final state = target.state, line = state.doc.lineAt(pos);
  final categorize = state.charCategorizer(pos);
  for (CharCategory? cat;;) {
    if (pos == (forward ? line.to : line.from)) {
      if (pos == range.head && line.number != (forward ? state.doc.lines : 1)) pos += forward ? 1 : -1;
      break;
    }
    final next = findClusterBreak(line.text, pos - line.from, forward) + line.from;
    final nextChar = line.text.substring(_min(pos, next) - line.from, _max(pos, next) - line.from);
    final nextCat = categorize(nextChar);
    if (cat != null && nextCat != cat) break;
    if (nextChar != ' ' || pos != range.head) cat = nextCat;
    pos = next;
  }
  return pos;
});

/// Delete the selection or backward until the end of the next group, only skipping groups of whitespace when
/// they consist of a single space.
bool deleteGroupBackward(StateCommandTarget target) => _deleteByGroup(target, false);

/// Delete the selection or forward until the end of the next group.
bool deleteGroupForward(StateCommandTarget target) => _deleteByGroup(target, true);

/// Variant of [deleteGroupForward] that uses the Windows convention of also deleting the whitespace after a word.
bool deleteGroupForwardWin(StateCommandTarget target) => _deleteBy(
  target,
  (range) => moveByChar(target.state, range, true, (start) => _toGroupStart(target.state, range.head, start)).head,
);

/// Delete the selection, or, if it is a cursor selection, delete to the end of the line. If the cursor is directly
/// at the end of the line, delete the line break after it.
bool deleteToLineEnd(StateCommandTarget target) => _deleteBy(target, (range) {
  final lineEnd = target.state.doc.lineAt(range.head).to;
  return range.head < lineEnd ? lineEnd : _min(target.state.doc.length, range.head + 1);
});

/// Delete the selection, or, if it is a cursor selection, delete to the start of the line. If the cursor is
/// directly at the start of the line, delete the line break before it.
bool deleteToLineStart(StateCommandTarget target) => _deleteBy(target, (range) {
  final lineStart = target.state.doc.lineAt(range.head).from;
  return range.head > lineStart ? lineStart : _max(0, range.head - 1);
});

/// Delete the selection, or, if it is a cursor selection, delete to the start of the line (on the web: or the
/// next line wrap before the cursor).
bool deleteLineBoundaryBackward(StateCommandTarget target) => _deleteBy(target, (range) {
  final lineStart = moveToLineBoundary(target.state, range, false).head;
  return range.head > lineStart ? lineStart : _max(0, range.head - 1);
});

/// Delete the selection, or, if it is a cursor selection, delete to the end of the line (on the web: or the next
/// line wrap after the cursor).
bool deleteLineBoundaryForward(StateCommandTarget target) => _deleteBy(target, (range) {
  final lineStart = moveToLineBoundary(target.state, range, true).head;
  return range.head < lineStart ? lineStart : _min(target.state.doc.length, range.head + 1);
});

final RegExp _trailingSpaces = RegExp(r'\s+$');

/// Delete all whitespace directly before a line end from the document.
bool deleteTrailingWhitespace(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = <ChangeSpec>[];
  final iter = state.doc.iter();
  for (var pos = 0, prev = '';;) {
    iter.next();
    if (iter.lineBreak || iter.done) {
      final trailing = prev.indexOf(_trailingSpaces);
      if (trailing > -1) changes.add(ChangeSpec(from: pos - (prev.length - trailing), to: pos));
      if (iter.done) break;
      prev = '';
    } else {
      prev = iter.value;
    }
    pos += iter.value.length;
  }
  if (changes.isEmpty) return false;
  target.dispatch(state.update(TransactionSpec(changes: changes, userEvent: 'delete')));
  return true;
}

/// Replace each selection range with a line break, leaving the cursor on the line before the break.
bool splitLine(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = state.changeByRange(
    (range) => RangeChange(
      changes: ChangeSpec(from: range.from, to: range.to, insert: Doc.of(<String>['', ''])),
      range: EditorSelection.cursor(range.from),
    ),
  );
  target.dispatch(state.updateAll(<TransactionSpec>[changes, const TransactionSpec(scrollIntoView: true, userEvent: 'input')]));
  return true;
}

/// Flip the characters before and after the cursor(s).
bool transposeChars(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = state.changeByRange((range) {
    if (!range.empty || range.from == 0 || range.from == state.doc.length) return RangeChange(range: range);
    final pos = range.from, line = state.doc.lineAt(pos);
    final from = pos == line.from ? pos - 1 : findClusterBreak(line.text, pos - line.from, false) + line.from;
    final to = pos == line.to ? pos + 1 : findClusterBreak(line.text, pos - line.from, true) + line.from;
    return RangeChange(
      changes: ChangeSpec(from: from, to: to, insert: state.doc.slice(pos, to).append(state.doc.slice(from, pos))),
      range: EditorSelection.cursor(to),
    );
  });
  if ((changes.changes! as ChangeSet).empty) return false;
  target.dispatch(state.updateAll(<TransactionSpec>[changes, const TransactionSpec(scrollIntoView: true, userEvent: 'move.character')]));
  return true;
}

class _LineBlock {
  _LineBlock(this.from, this.to, this.ranges);

  final int from;
  int to;
  final List<SelectionRange> ranges;
}

List<_LineBlock> _selectedLineBlocks(EditorState state) {
  final blocks = <_LineBlock>[];
  var upto = -1;
  for (final range in state.selection.ranges) {
    final startLine = state.doc.lineAt(range.from);
    var endLine = state.doc.lineAt(range.to);
    if (!range.empty && range.to == endLine.from) endLine = state.doc.lineAt(range.to - 1);
    if (upto >= startLine.number) {
      final prev = blocks[blocks.length - 1];
      prev.to = endLine.to;
      prev.ranges.add(range);
    } else {
      blocks.add(_LineBlock(startLine.from, endLine.to, <SelectionRange>[range]));
    }
    upto = endLine.number + 1;
  }
  return blocks;
}

bool _moveLine(StateCommandTarget target, bool forward) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = <ChangeSpec>[];
  final ranges = <SelectionRange>[];
  for (final block in _selectedLineBlocks(state)) {
    if (forward ? block.to == state.doc.length : block.from == 0) continue;
    final nextLine = state.doc.lineAt(forward ? block.to + 1 : block.from - 1);
    final size = nextLine.length + 1;
    if (forward) {
      changes
        ..add(ChangeSpec(from: block.to, to: nextLine.to))
        ..add(ChangeSpec(from: block.from, insert: nextLine.text + state.lineBreak));
      for (final r in block.ranges) {
        ranges.add(EditorSelection.range(_min(state.doc.length, r.anchor + size), _min(state.doc.length, r.head + size)));
      }
    } else {
      changes
        ..add(ChangeSpec(from: nextLine.from, to: block.from))
        ..add(ChangeSpec(from: block.to, insert: state.lineBreak + nextLine.text));
      for (final r in block.ranges) {
        ranges.add(EditorSelection.range(r.anchor - size, r.head - size));
      }
    }
  }
  if (changes.isEmpty) return false;
  target.dispatch(
    state.update(
      TransactionSpec(
        changes: changes,
        scrollIntoView: true,
        // CodeMirror passes the old main index whatever ranges are left; past them it is the last here.
        selection: EditorSelection.create(ranges, _min(state.selection.mainIndex, ranges.length - 1)),
        userEvent: 'move.line',
      ),
    ),
  );
  return true;
}

/// Move the selected lines up one line.
bool moveLineUp(StateCommandTarget target) => _moveLine(target, false);

/// Move the selected lines down one line.
bool moveLineDown(StateCommandTarget target) => _moveLine(target, true);

bool _copyLine(StateCommandTarget target, bool forward) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = <ChangeSpec>[];
  for (final block in _selectedLineBlocks(state)) {
    if (forward) {
      changes.add(ChangeSpec(from: block.from, insert: state.doc.sliceString(block.from, block.to) + state.lineBreak));
    } else {
      changes.add(ChangeSpec(from: block.to, insert: state.lineBreak + state.doc.sliceString(block.from, block.to)));
    }
  }
  final changeSet = state.changes(changes);
  target.dispatch(
    state.update(
      TransactionSpec(
        changes: changeSet,
        selection: state.selection.map(changeSet, forward ? 1 : -1),
        scrollIntoView: true,
        userEvent: 'input.copyline',
      ),
    ),
  );
  return true;
}

/// Create a copy of the selected lines. Keep the selection in the top copy.
bool copyLineUp(StateCommandTarget target) => _copyLine(target, false);

/// Create a copy of the selected lines. Keep the selection in the bottom copy.
bool copyLineDown(StateCommandTarget target) => _copyLine(target, true);

/// Delete selected lines. Each caret goes where [verticalMotion] puts it one line down, then through the
/// deletion.
bool deleteLine(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  final changes = state.changes(<ChangeSpec>[
    for (final block in _selectedLineBlocks(state))
      if (block.from > 0)
        ChangeSpec(from: block.from - 1, to: block.to)
      else if (block.to < state.doc.length)
        ChangeSpec(from: block.from, to: block.to + 1)
      else
        ChangeSpec(from: block.from, to: block.to),
  ]);
  final move = state.facet(verticalMotion);
  final selection = _updateSel(state.selection, (range) => move(state, range, true)).map(changes);
  target.dispatch(state.update(TransactionSpec(changes: changes, selection: selection, scrollIntoView: true, userEvent: 'delete.line')));
  return true;
}

// ---------------------------------------------------------------------------------------------------------------
// commands.ts: new lines and indentation
// ---------------------------------------------------------------------------------------------------------------

/// Replace the selection with a newline.
bool insertNewline(StateCommandTarget target) {
  final state = target.state;
  target.dispatch(
    state.updateAll(<TransactionSpec>[state.replaceSelection(state.lineBreak), const TransactionSpec(scrollIntoView: true, userEvent: 'input')]),
  );
  return true;
}

/// Replace the selection with a newline and the same amount of indentation as the line above.
bool insertNewlineKeepIndent(StateCommandTarget target) {
  final state = target.state;
  target.dispatch(
    state.updateAll(<TransactionSpec>[
      state.changeByRange((range) {
        final indent = _indentOf(state.doc.lineAt(range.from).text);
        return RangeChange(
          changes: ChangeSpec(from: range.from, to: range.to, insert: state.lineBreak + indent),
          range: EditorSelection.cursor(range.from + indent.length + 1),
        );
      }),
      const TransactionSpec(scrollIntoView: true, userEvent: 'input'),
    ]),
  );
  return true;
}

final RegExp _emptyBrackets = RegExp(r'\(\)|\[\]|\{\}');

// A caret between a bracket and the one that closes it. (CodeMirror also asks the tree for a node with `closedBy`
// before the caret and its closer after; Markdown's tree has none.)
_FromTo? _isBetweenBrackets(EditorState state, int pos) {
  if (_emptyBrackets.hasMatch(_sliceDoc(state, pos - 1, pos + 1))) return (from: pos, to: pos);
  return null;
}

/// Replace the selection with a newline and indent the newly created line(s). If the current line consists only
/// of whitespace, this will also delete that whitespace. When the cursor is between matching brackets, an
/// additional newline will be inserted after the cursor.
final StateCommand insertNewlineAndIndent = _newlineAndIndent(false);

/// Create a blank, indented line below the current line.
final StateCommand insertBlankLine = _newlineAndIndent(true);

StateCommand _newlineAndIndent(bool atEof) {
  return (StateCommandTarget target) {
    final state = target.state;
    if (state.readOnly) return false;
    final changes = state.changeByRange((range) {
      var from = range.from, to = range.to;
      final line = state.doc.lineAt(from);
      final explode = !atEof && from == to ? _isBetweenBrackets(state, from) : null;
      if (atEof) from = to = (to <= line.to ? line : state.doc.lineAt(to)).to;
      final cx = IndentContext(state, simulateBreak: from, simulateDoubleBreak: explode != null);
      final indent = getIndentation(cx, from) ?? countColumn(_indentOf(state.doc.lineAt(from).text), state.tabSize);
      while (to < line.to && _space.hasMatch(line.text[to - line.from])) {
        to++;
      }
      if (explode != null) {
        from = explode.from;
        to = explode.to;
      } else if (from > line.from && from < line.from + 100 && !_nonSpace.hasMatch(_slice(line.text, 0, from))) {
        // (`line.text.slice(0, from)`: CodeMirror reads `from` as an offset into the line here, and so does this.)
        from = line.from;
      }
      final insert = <String>['', indentString(state, indent)];
      if (explode != null) insert.add(indentString(state, cx.lineIndent(line.from, -1)));
      return RangeChange(
        changes: ChangeSpec(from: from, to: to, insert: Doc.of(insert)),
        range: EditorSelection.cursor(from + 1 + insert[1].length),
      );
    });
    target.dispatch(state.updateAll(<TransactionSpec>[changes, const TransactionSpec(scrollIntoView: true, userEvent: 'input')]));
    return true;
  };
}

TransactionSpec _changeBySelectedLine(EditorState state, void Function(Line line, List<ChangeSpec> changes, SelectionRange range) f) {
  var atLine = -1;
  return state.changeByRange((range) {
    final changes = <ChangeSpec>[];
    for (var pos = range.from; pos <= range.to;) {
      final line = state.doc.lineAt(pos);
      if (line.number > atLine && (range.empty || range.to > line.from)) {
        f(line, changes, range);
        atLine = line.number;
      }
      pos = line.to + 1;
    }
    final changeSet = state.changes(changes);
    return RangeChange(
      changes: changes,
      range: EditorSelection.range(changeSet.mapPos(range.anchor, 1), changeSet.mapPos(range.head, 1)),
    );
  });
}

/// Auto-indent the selected lines, by [getIndentation]. With the app's Markdown that never has an answer, so this
/// changes nothing and returns true, as it does on the web.
bool indentSelection(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  final updated = <int, int>{};
  final context = IndentContext(state, overrideIndentation: (start) => updated[start] ?? -1);
  final changes = _changeBySelectedLine(state, (line, changes, range) {
    var indent = getIndentation(context, line.from);
    if (indent == null) return;
    if (!_nonSpace.hasMatch(line.text)) indent = 0;
    final cur = _indentOf(line.text);
    final norm = indentString(state, indent);
    if (cur != norm || range.from < line.from + cur.length) {
      updated[line.from] = indent;
      changes.add(ChangeSpec(from: line.from, to: line.from + cur.length, insert: norm));
    }
  });
  if (!(changes.changes! as ChangeSet).empty) target.dispatch(state.updateAll(<TransactionSpec>[changes, const TransactionSpec(userEvent: 'indent')]));
  return true;
}

/// Add a unit ([indentUnit]) of indentation to all selected lines.
bool indentMore(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  target.dispatch(
    state.updateAll(<TransactionSpec>[
      _changeBySelectedLine(state, (line, changes, range) {
        changes.add(ChangeSpec(from: line.from, insert: state.facet(indentUnit)));
      }),
      const TransactionSpec(userEvent: 'input.indent'),
    ]),
  );
  return true;
}

/// Remove a unit ([indentUnit]) of indentation from all selected lines.
bool indentLess(StateCommandTarget target) {
  final state = target.state;
  if (state.readOnly) return false;
  target.dispatch(
    state.updateAll(<TransactionSpec>[
      _changeBySelectedLine(state, (line, changes, range) {
        final space = _indentOf(line.text);
        if (space.isEmpty) return;
        final col = countColumn(space, state.tabSize);
        var keep = 0;
        final insert = indentString(state, _max(0, col - getIndentUnit(state)));
        while (keep < space.length && keep < insert.length && space.codeUnitAt(keep) == insert.codeUnitAt(keep)) {
          keep++;
        }
        changes.add(ChangeSpec(from: line.from + keep, to: line.from + space.length, insert: insert.substring(keep)));
      }),
      const TransactionSpec(userEvent: 'delete.dedent'),
    ]),
  );
  return true;
}

/// Insert a tab character at the cursor or, if something is selected, use [indentMore] to indent the entire
/// selection.
bool insertTab(StateCommandTarget target) {
  final state = target.state;
  if (state.selection.ranges.any((r) => !r.empty)) return indentMore(target);
  target.dispatch(state.updateAll(<TransactionSpec>[state.replaceSelection('\t'), const TransactionSpec(scrollIntoView: true, userEvent: 'input')]));
  return true;
}

// ---------------------------------------------------------------------------------------------------------------
// Keymaps
// ---------------------------------------------------------------------------------------------------------------

/// CodeMirror's `KeyBinding`, for commands over a state. `key` is the binding everywhere unless a platform's own
/// (`mac`, `win`, `linux`) is given; `Mod-` is Cmd on a Mac and Ctrl elsewhere. `shift` runs when Shift is held
/// with the key.
///
/// A command this file leaves to the view has a null [run] (or [shift]) and its CodeMirror name in [viewCommand]
/// (or [shiftViewCommand]), for the view to fill.
class KeyBinding {
  /// A binding.
  const KeyBinding({this.key, this.mac, this.win, this.linux, this.run, this.shift, this.preventDefault = false, this.viewCommand, this.shiftViewCommand});

  /// The key, as CodeMirror names it (`Mod-ArrowLeft`, `Shift-Alt-ArrowUp`).
  final String? key;

  /// The key on macOS.
  final String? mac;

  /// The key on Windows.
  final String? win;

  /// The key on Linux.
  final String? linux;

  /// The command, or null when it is the view's ([viewCommand]).
  final StateCommand? run;

  /// The command with Shift held, or null when there is none or it is the view's ([shiftViewCommand]).
  final StateCommand? shift;

  /// Whether the key is swallowed even when the command returns false.
  final bool preventDefault;

  /// CodeMirror's name of the command [run] stands for, when the view has to supply it.
  final String? viewCommand;

  /// The same for [shift].
  final String? shiftViewCommand;
}

/// Array of key bindings containing the Emacs-style bindings that are available on macOS by default: Ctrl-b/f
/// (character), Ctrl-p/n (line: the view's), Ctrl-a/e (line start and end), Ctrl-d/h (delete), Ctrl-k (to line
/// end), Ctrl-Alt-h (group backward), Ctrl-o (split line), Ctrl-t (transpose), Ctrl-v (page down: the view's).
final List<KeyBinding> emacsStyleKeymap = List<KeyBinding>.unmodifiable(<KeyBinding>[
  const KeyBinding(key: 'Ctrl-b', run: cursorCharLeft, shift: selectCharLeft, preventDefault: true),
  const KeyBinding(key: 'Ctrl-f', run: cursorCharRight, shift: selectCharRight),
  const KeyBinding(key: 'Ctrl-p', viewCommand: 'cursorLineUp', shiftViewCommand: 'selectLineUp'),
  const KeyBinding(key: 'Ctrl-n', viewCommand: 'cursorLineDown', shiftViewCommand: 'selectLineDown'),
  const KeyBinding(key: 'Ctrl-a', run: cursorLineStart, shift: selectLineStart),
  const KeyBinding(key: 'Ctrl-e', run: cursorLineEnd, shift: selectLineEnd),
  const KeyBinding(key: 'Ctrl-d', run: deleteCharForward),
  const KeyBinding(key: 'Ctrl-h', run: deleteCharBackward),
  const KeyBinding(key: 'Ctrl-k', run: deleteToLineEnd),
  const KeyBinding(key: 'Ctrl-Alt-h', run: deleteGroupBackward),
  const KeyBinding(key: 'Ctrl-o', run: splitLine),
  const KeyBinding(key: 'Ctrl-t', run: transposeChars),
  const KeyBinding(key: 'Ctrl-v', viewCommand: 'cursorPageDown'),
]);

/// An array of key bindings closely sticking to platform-standard or widely used bindings: arrows by character,
/// group, line boundary, line and page; Home and End; document start and end; Enter; select all; Backspace and
/// Delete by character, group and line boundary. It ends with the bindings of [emacsStyleKeymap], their `key`
/// made `mac`.
final List<KeyBinding> standardKeymap = List<KeyBinding>.unmodifiable(<KeyBinding>[
  const KeyBinding(key: 'ArrowLeft', run: cursorCharLeft, shift: selectCharLeft, preventDefault: true),
  const KeyBinding(key: 'Mod-ArrowLeft', mac: 'Alt-ArrowLeft', run: cursorGroupLeft, shift: selectGroupLeft, preventDefault: true),
  const KeyBinding(mac: 'Cmd-ArrowLeft', run: cursorLineBoundaryLeft, shift: selectLineBoundaryLeft, preventDefault: true),
  const KeyBinding(key: 'ArrowRight', run: cursorCharRight, shift: selectCharRight, preventDefault: true),
  const KeyBinding(key: 'Mod-ArrowRight', mac: 'Alt-ArrowRight', run: cursorGroupRight, shift: selectGroupRight, preventDefault: true),
  const KeyBinding(mac: 'Cmd-ArrowRight', run: cursorLineBoundaryRight, shift: selectLineBoundaryRight, preventDefault: true),
  const KeyBinding(key: 'ArrowUp', viewCommand: 'cursorLineUp', shiftViewCommand: 'selectLineUp', preventDefault: true),
  const KeyBinding(mac: 'Cmd-ArrowUp', run: cursorDocStart, shift: selectDocStart),
  const KeyBinding(mac: 'Ctrl-ArrowUp', viewCommand: 'cursorPageUp', shiftViewCommand: 'selectPageUp'),
  const KeyBinding(key: 'ArrowDown', viewCommand: 'cursorLineDown', shiftViewCommand: 'selectLineDown', preventDefault: true),
  const KeyBinding(mac: 'Cmd-ArrowDown', run: cursorDocEnd, shift: selectDocEnd),
  const KeyBinding(mac: 'Ctrl-ArrowDown', viewCommand: 'cursorPageDown', shiftViewCommand: 'selectPageDown'),
  const KeyBinding(key: 'PageUp', viewCommand: 'cursorPageUp', shiftViewCommand: 'selectPageUp'),
  const KeyBinding(key: 'PageDown', viewCommand: 'cursorPageDown', shiftViewCommand: 'selectPageDown'),
  const KeyBinding(key: 'Home', run: cursorLineBoundaryBackward, shift: selectLineBoundaryBackward, preventDefault: true),
  const KeyBinding(key: 'Mod-Home', run: cursorDocStart, shift: selectDocStart),
  const KeyBinding(key: 'End', run: cursorLineBoundaryForward, shift: selectLineBoundaryForward, preventDefault: true),
  const KeyBinding(key: 'Mod-End', run: cursorDocEnd, shift: selectDocEnd),
  KeyBinding(key: 'Enter', run: insertNewlineAndIndent, shift: insertNewlineAndIndent),
  const KeyBinding(key: 'Mod-a', run: selectAll),
  const KeyBinding(key: 'Backspace', run: deleteCharBackward, shift: deleteCharBackward, preventDefault: true),
  const KeyBinding(key: 'Delete', run: deleteCharForward, preventDefault: true),
  const KeyBinding(key: 'Mod-Backspace', mac: 'Alt-Backspace', run: deleteGroupBackward, preventDefault: true),
  const KeyBinding(key: 'Mod-Delete', mac: 'Alt-Delete', run: deleteGroupForward, preventDefault: true),
  const KeyBinding(mac: 'Mod-Backspace', run: deleteLineBoundaryBackward, preventDefault: true),
  const KeyBinding(mac: 'Mod-Delete', run: deleteLineBoundaryForward, preventDefault: true),
  for (final b in emacsStyleKeymap)
    KeyBinding(mac: b.key, run: b.run, shift: b.shift, viewCommand: b.viewCommand, shiftViewCommand: b.shiftViewCommand),
]);

/// The default keymap: syntax motion (Alt-Arrow, Ctrl-Arrow on macOS), move and copy line (Alt-ArrowUp/Down, with
/// Shift), add a cursor above or below (the view's), Escape ([simplifySelection]), Mod-Enter ([insertBlankLine]),
/// Alt-l ([selectLine]), Mod-i ([selectParentSyntax]), Mod-[ and Mod-] (indent), Mod-Alt-\ ([indentSelection]),
/// Shift-Mod-k ([deleteLine]), Shift-Mod-\ ([cursorMatchingBracket]), Mod-/ ([toggleComment]), Alt-A
/// ([toggleBlockComment]), Ctrl-m (tab focus mode: the view's); then everything in [standardKeymap].
final List<KeyBinding> defaultKeymap = List<KeyBinding>.unmodifiable(<KeyBinding>[
  const KeyBinding(key: 'Alt-ArrowLeft', mac: 'Ctrl-ArrowLeft', run: cursorSyntaxLeft, shift: selectSyntaxLeft),
  const KeyBinding(key: 'Alt-ArrowRight', mac: 'Ctrl-ArrowRight', run: cursorSyntaxRight, shift: selectSyntaxRight),
  const KeyBinding(key: 'Alt-ArrowUp', run: moveLineUp),
  const KeyBinding(key: 'Shift-Alt-ArrowUp', run: copyLineUp),
  const KeyBinding(key: 'Alt-ArrowDown', run: moveLineDown),
  const KeyBinding(key: 'Shift-Alt-ArrowDown', run: copyLineDown),
  const KeyBinding(key: 'Mod-Alt-ArrowUp', viewCommand: 'addCursorAbove'),
  const KeyBinding(key: 'Mod-Alt-ArrowDown', viewCommand: 'addCursorBelow'),
  const KeyBinding(key: 'Escape', run: simplifySelection),
  KeyBinding(key: 'Mod-Enter', run: insertBlankLine),
  const KeyBinding(key: 'Alt-l', mac: 'Ctrl-l', run: selectLine),
  const KeyBinding(key: 'Mod-i', run: selectParentSyntax, preventDefault: true),
  const KeyBinding(key: 'Mod-[', run: indentLess),
  const KeyBinding(key: 'Mod-]', run: indentMore),
  const KeyBinding(key: 'Mod-Alt-\\', run: indentSelection),
  const KeyBinding(key: 'Shift-Mod-k', run: deleteLine),
  const KeyBinding(key: 'Shift-Mod-\\', run: cursorMatchingBracket),
  const KeyBinding(key: 'Mod-/', run: toggleComment),
  KeyBinding(key: 'Alt-A', mac: 'Ctrl-A', run: toggleBlockComment),
  const KeyBinding(key: 'Ctrl-m', mac: 'Shift-Alt-m', viewCommand: 'toggleTabFocusMode'),
  ...standardKeymap,
]);

/// A binding that binds Tab to [indentMore] and Shift-Tab to [indentLess].
const KeyBinding indentWithTab = KeyBinding(key: 'Tab', run: indentMore, shift: indentLess);
