/// What the Style page of the press-and-hold menu writes: a port of `src/app/editor/format.ts`.
///
/// The delimiters are the kit's, exactly: `**`, `_`, backtick, `~~`, and the block prefixes from `@glacier/logic`'s
/// `rich-text.ts`, plus a to-do's `- [ ] `. That is not politeness, it is correctness - the bar writes characters
/// and the highlighter reads them, and if the two ever disagree the app types a mark that does not render.
/// Underscore for italic (not `*`) also keeps `*` free to mean bold's half, which is what a person typing expects.
/// A plugin's formatting is wrapped the same way, with its own delimiter, through [toggleWrap].
///
/// Every edit goes through `state.changeByRange`, so a multi-cursor selection behaves and the caret lands somewhere
/// sensible afterwards: with a selection, around the wrapped text; with none, BETWEEN the delimiters, so pressing
/// Bold and typing produces bold text instead of leaving the caret stranded past the markers.
///
/// Transactions are annotated `input.format` so `feel.dart` can tell a deliberate bar press (which already got its
/// own tap tick from the button) from a mark the person typed by hand (which is the thing worth announcing).
///
/// What differs: the web's functions take the view and dispatch; these take the state and answer the
/// [Transaction] to dispatch, or null where the web dispatches nothing ([toggleBlock] with nothing to change,
/// [moveLines] at either end). `view.hasFocus`, which decides whether [insertBlock] scrolls the caret into view,
/// is a parameter. `TABLE_SEED` is [tableSeed].
library;

import '../../core/item_syntax.dart';
import '../state/change.dart';
import '../state/history.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';
import 'inserts.dart';

/// The inline marks the bar writes (`Mark`).
enum Mark { bold, italic, code, strike }

/// The block forms the bar writes (`Block`).
enum Block { heading, quote, bullet, number, task }

const Map<Mark, String> _markDelimiters = <Mark, String>{Mark.bold: '**', Mark.italic: '_', Mark.code: '`', Mark.strike: '~~'};

const Map<Block, String> _blockPrefixes = <Block, String>{
  Block.heading: '# ',
  Block.quote: '> ',
  Block.bullet: '- ',
  Block.number: '1. ',
  Block.task: '- [ ] ',
};

/// A prefix matcher per block form, loose enough to spot what is already there.
final Map<Block, RegExp> _blockPatterns = <Block, RegExp>{
  Block.heading: RegExp(r'^#{1,6}\s+'),
  Block.quote: RegExp(r'^>\s+'),
  // The list forms in core/item_syntax.dart's spelling. A to-do here is a bullet's: the bar's forms are one each,
  // and a numbered to-do is shown, and toggled, as the numbered line it also is.
  Block.bullet: RegExp('^$bulletPattern\\s+'),
  Block.number: RegExp('^$numberPattern\\s+'),
  Block.task: RegExp('^$bulletPattern\\s+$boxPattern\\s+'),
};

/// The order forms are recognised in: a to-do before the list it also is.
const List<Block> _blockOrder = <Block>[Block.heading, Block.quote, Block.task, Block.bullet, Block.number];

final Annotation<String> _format = Transaction.userEvent.of('input.format');

int _max(int a, int b) => a > b ? a : b;
int _min(int a, int b) => a < b ? a : b;

/// Wrap or unwrap the selection.
///
/// Toggling recognises two shapes, because a selection lands either way: the delimiters sitting just OUTSIDE it
/// (the word was selected and is being un-bolded) or INSIDE it (the whole `**word**` was selected). Both unwrap.
Transaction toggleMark(EditorState state, Mark mark) => toggleWrap(state, _markDelimiters[mark]!);

/// Wrap or unwrap the selection in `delimiter`: a mark's, or a plugin formatting's.
Transaction toggleWrap(EditorState state, String delimiter) {
  final width = delimiter.length;

  return state.updateAll(<TransactionSpec>[
    state.changeByRange((range) {
      final from = range.from, to = range.to;
      final doc = state.doc;
      final outsideBefore = doc.sliceString(_max(0, from - width), from);
      final outsideAfter = doc.sliceString(to, _min(doc.length, to + width));

      if (outsideBefore == delimiter && outsideAfter == delimiter) {
        return RangeChange(
          changes: <ChangeSpec>[ChangeSpec(from: from - width, to: from), ChangeSpec(from: to, to: to + width)],
          range: EditorSelection.range(from - width, to - width),
        );
      }

      final selected = doc.sliceString(from, to);
      if (selected.length >= width * 2 && selected.startsWith(delimiter) && selected.endsWith(delimiter)) {
        return RangeChange(
          changes: <ChangeSpec>[ChangeSpec(from: from, to: from + width), ChangeSpec(from: to - width, to: to)],
          range: EditorSelection.range(from, to - width * 2),
        );
      }

      return RangeChange(
        changes: <ChangeSpec>[ChangeSpec(from: from, insert: delimiter), ChangeSpec(from: to, insert: delimiter)],
        range: range.empty ? EditorSelection.cursor(from + width) : EditorSelection.range(from + width, to + width),
      );
    }),
    TransactionSpec(annotations: _format),
  ]);
}

/// Which lines a range touches, as line numbers.
List<int> _linesOf(EditorState state, int from, int to) {
  final first = state.doc.lineAt(from).number;
  final last = state.doc.lineAt(to).number;
  return <int>[for (var n = first; n <= last; n += 1) n];
}

/// Apply or remove a block form on every line the selection touches.
///
/// Applied when ANY touched line lacks the prefix, removed only when every one of them already has it - so dragging
/// across a half-formatted list completes it rather than clearing the half that was done. Null when there is
/// nothing to change.
Transaction? toggleBlock(EditorState state, Block block) {
  final pattern = _blockPatterns[block]!;
  final prefix = _blockPrefixes[block]!;
  final main = state.selection.main;
  final numbers = _linesOf(state, main.from, main.to);
  final lines = <Line>[for (final n in numbers) state.doc.line(n)];
  final removing = lines.every((line) => pattern.hasMatch(line.text));

  final changes = <ChangeSpec>[];
  for (final line in lines) {
    final match = pattern.firstMatch(line.text);
    if (removing && match != null) {
      changes.add(ChangeSpec(from: line.from, to: line.from + match.group(0)!.length));
    } else if (!removing && match == null) {
      // A numbered list counts up rather than repeating "1."; anything else uses the same prefix on every line.
      final insert = block == Block.number ? '${numbers.indexOf(line.number) + 1}. ' : prefix;
      changes.add(ChangeSpec(from: line.from, insert: insert));
    }
  }
  if (changes.isEmpty) return null;
  return state.update(TransactionSpec(changes: changes, annotations: _format));
}

/// Which of `delimiters` surround the caret right now, for the bar's pressed state.
List<String> activeWraps(EditorState state, List<String> delimiters) {
  final from = state.selection.main.from, to = state.selection.main.to;
  final doc = state.doc;
  return <String>[
    for (final delimiter in delimiters)
      if (doc.sliceString(_max(0, from - delimiter.length), from) == delimiter &&
          doc.sliceString(to, _min(doc.length, to + delimiter.length)) == delimiter)
        delimiter,
  ];
}

/// Which inline marks surround the caret right now, for the bar's pressed state.
List<Mark> activeMarks(EditorState state) {
  final active = activeWraps(state, <String>[for (final mark in Mark.values) _markDelimiters[mark]!]).toSet();
  return <Mark>[
    for (final mark in Mark.values)
      if (active.contains(_markDelimiters[mark])) mark,
  ];
}

/// Which block form the caret's line is in, if any.
Block? activeBlock(EditorState state) {
  final text = state.doc.lineAt(state.selection.main.head).text;
  for (final block in _blockOrder) {
    if (_blockPatterns[block]!.hasMatch(text)) return block;
  }
  return null;
}

/// A link around the selected words, or an empty one, with the caret where the address goes.
Transaction insertLink(EditorState state) {
  final from = state.selection.main.from, to = state.selection.main.to;
  final words = state.doc.sliceString(from, to);
  const lead = 'https://';
  return state.update(
    TransactionSpec(
      changes: ChangeSpec(from: from, to: to, insert: '[$words]($lead)'),
      selection: EditorSelection.single(from + words.length + 3 + lead.length),
      annotations: _format,
    ),
  );
}

/// A block at the caret's line, with the caret (or a selection) placed in it, as one Undo: inserts.dart's rule for
/// a block. It takes a line with nothing on it but a lead, and otherwise goes after the line; a blank line keeps it
/// apart from words on either side. Without the one after, a table took the next line of words as a row; without
/// the one before, a rule under a paragraph reads as a heading in Obsidian and on GitHub. `userEvent` is the +
/// beside the line's own when it is the one asking. `hasFocus` is the view's: the caret is scrolled into view only
/// while the note has focus.
Transaction insertBlock(EditorState state, String text, BlockSelect select, {String userEvent = 'input.format', bool hasFocus = false}) {
  final plan = blockPlan(state, state.selection.main.head, text, select);
  return state.update(
    TransactionSpec(
      changes: plan.changes,
      selection: plan.editorSelection,
      scrollIntoView: hasFocus,
      annotations: <Annotation<Object?>>[Transaction.userEvent.of(userEvent), isolateHistory.of('full')],
    ),
  );
}

/// The table every insert starts from: two columns, a heading row and a row of cells, "Column" selected to be
/// written over (`TABLE_SEED`).
const ({String text, BlockSelect select}) tableSeed = (
  text: '| Column | Column |\n| --- | --- |\n| Cell | Cell |',
  select: BlockSelect.at(2, 8),
);

/// A small table at the caret's line, its first heading selected to be written over.
Transaction insertTable(EditorState state, {String userEvent = 'input.format', bool hasFocus = false}) =>
    insertBlock(state, tableSeed.text, tableSeed.select, userEvent: userEvent, hasFocus: hasFocus);

/// A rule at the caret's line, the caret after it.
Transaction insertRule(EditorState state, {bool hasFocus = false}) =>
    insertBlock(state, '---', const BlockSelect.at(3), hasFocus: hasFocus);

/// The selection gone, or the line the caret is on when nothing is selected.
Transaction deleteSelection(EditorState state) {
  return state.updateAll(<TransactionSpec>[
    state.changeByRange((range) {
      if (!range.empty) {
        return RangeChange(changes: ChangeSpec(from: range.from, to: range.to), range: EditorSelection.cursor(range.from));
      }
      final line = state.doc.lineAt(range.head);
      final to = _min(state.doc.length, line.to + 1);
      return RangeChange(changes: ChangeSpec(from: line.from, to: to), range: EditorSelection.cursor(line.from));
    }),
    const TransactionSpec(userEvent: 'delete.selection', scrollIntoView: true),
  ]);
}

/// The selection again after itself, or the line again under itself.
Transaction duplicateSelection(EditorState state) {
  final range = state.selection.main;
  if (!range.empty) {
    final text = state.sliceDoc(range.from, range.to);
    return state.update(
      TransactionSpec(
        changes: ChangeSpec(from: range.to, insert: text),
        selection: EditorSelection.create(<SelectionRange>[EditorSelection.range(range.to, range.to + text.length)]),
        userEvent: 'input.duplicate',
        scrollIntoView: true,
      ),
    );
  }
  final line = state.doc.lineAt(range.head);
  return state.update(
    TransactionSpec(
      changes: ChangeSpec(from: line.to, insert: '\n${line.text}'),
      selection: EditorSelection.create(<SelectionRange>[EditorSelection.cursor(range.head + line.length + 1)]),
      userEvent: 'input.duplicate',
      scrollIntoView: true,
    ),
  );
}

/// The lines the selection touches, moved one line up (`by` -1) or down (1). Null at either end, where nothing
/// happens.
Transaction? moveLines(EditorState state, int by) {
  final range = state.selection.main;
  final first = state.doc.lineAt(range.from);
  final last = state.doc.lineAt(range.to);
  final swapWith = by < 0 ? first.number - 1 : last.number + 1;
  if (swapWith < 1 || swapWith > state.doc.lines) return null;
  final other = state.doc.line(swapWith);
  final block = state.sliceDoc(first.from, last.to);
  final moved = by < 0 ? '$block\n${other.text}' : '${other.text}\n$block';
  final from = _min(first.from, other.from);
  final to = _max(last.to, other.to);
  final shift = by < 0 ? -(other.length + 1) : other.length + 1;
  return state.update(
    TransactionSpec(
      changes: ChangeSpec(from: from, to: to, insert: moved),
      selection: EditorSelection.create(<SelectionRange>[EditorSelection.range(range.from + shift, range.to + shift)]),
      userEvent: 'move.line',
      scrollIntoView: true,
    ),
  );
}
