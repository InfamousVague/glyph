/// Moving the caret by what is on screen: the commands commands.dart leaves to the view. CodeMirror's
/// `moveVertically` and `moveToLineBoundary` (@codemirror/view, cursor.ts) and the commands over them
/// (@codemirror/commands: `cursorLineUp`, `selectLineDown`, `cursorPageDown`, `cursorLineBoundaryForward`...).
///
/// A caret going up or down keeps a goal: the place across the line it set out from, carried on the selection
/// range (`goalColumn`), so a short line on the way does not pull it left for good. The goal is pixels from the
/// line's own left edge, which every line of the editor shares.
///
/// What differs from CodeMirror:
/// - CodeMirror asks the page what is at a point one line's height away, and tries again further off until the
///   position moves. Here a line knows its own visual lines, so the next one is asked for by name: the same answer
///   without the search.
/// - A line that is not laid out (off screen, past the scroll view's cache) is answered by column, as commands.dart
///   answers without a view. A caret is on screen when it is being moved, so this is the far end of a page move.
/// - A page is the scroll view's height, less what covers its foot ([EditorMotion.pageHeight]); the page scrolls the
///   note (Editor.tsx's `grow`), so there is no keeping the caret's place on screen: the selection is scrolled into
///   view, as CodeMirror does when the editor does not scroll itself.
/// - `addCursorAbove` and `addCursorBelow` are not here: the app has one caret.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../commands/commands.dart' as commands;
import '../state/change.dart';
import '../state/char.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../view/editor_view.dart';
import '../view/line.dart';
import '../view/sliver.dart';

/// What the motion needs of whoever hosts the view, said once.
class EditorMotion {
  /// How much of the scroll view's foot is covered (the keyboard, a bar): a page is that much shorter.
  static final Expando<double Function()> covered = Expando<double Function()>('covered');

  /// The height a page move goes: the room the note is read in, less five pixels (CodeMirror's `pageInfo`).
  static double pageHeight(EditorView view) {
    final scroller = view.scroller;
    final line = view.heights.lineHeight;
    if (scroller is! RenderSliverEditor || !scroller.attached) return line * 20;
    final room = scroller.constraints.viewportMainAxisExtent - (covered[view]?.call() ?? 0);
    return math.max(line, room - 5);
  }
}

int _visualIndex(RenderEditorLine line, Rect at) {
  final lines = line.visualLines;
  var best = 0;
  var distance = double.infinity;
  for (var i = 0; i < lines.length; i++) {
    final away = ((lines[i].contentTop + lines[i].contentBottom) / 2 - at.center.dy).abs();
    if (away < distance) {
      distance = away;
      best = i;
    }
  }
  return best;
}

double _middle(VisualLine line) => (line.contentTop + line.contentBottom) / 2;

int _side(SelectionRange range, bool forward) => range.assoc != 0 ? range.assoc : ((range.empty ? forward : range.head == range.from) ? 1 : -1);

/// The entry (its first line's number) a caret leaves `entry` for, or null at the note's edge.
int? _nextEntry(EditorView view, int entry, bool forward) {
  final doc = view.state.doc, blocks = view.blocks;
  if (forward) {
    final next = blocks.lastLineOf(entry) + 1;
    return next > doc.lines ? null : next;
  }
  return entry <= 1 ? null : blocks.entryOf(entry - 1);
}

/// CodeMirror's `view.moveVertically(range, forward, distance)`: the caret one visual line up or down from
/// `start`'s head, at its goal; or `distance` pixels away. The same position when there is nowhere to go.
SelectionRange moveVertically(EditorView view, SelectionRange start, bool forward, [double? distance]) {
  final state = view.state, doc = state.doc, blocks = view.blocks;
  final head = start.head;
  final entry = blocks.entryOf(doc.lineAt(head).number);
  final replaced = blocks.at(entry)?.replace;

  // On something drawn in place of its lines: its far edge first, then the line past it.
  if (replaced != null) {
    if (forward && head < replaced.to) return EditorSelection.cursor(replaced.to, -1, null, start.goalColumn);
    if (!forward && head > replaced.from) return EditorSelection.cursor(replaced.from, 1, null, start.goalColumn);
    final next = _nextEntry(view, entry, forward);
    return next == null ? EditorSelection.cursor(head, start.assoc, null, start.goalColumn) : _intoEntry(view, next, forward, (start.goalColumn ?? 0).toDouble(), start, null);
  }

  final line = view.lineAt(head);
  final rect = line?.coordsAtPos(head - line.from, _side(start, forward));
  if (line == null || rect == null) return commands.moveVerticallyByColumn(state, start, forward);
  final goal = (start.goalColumn ?? rect.left.round()).toDouble();

  if (distance != null) return _byDistance(view, line, rect, goal, start, forward, distance);

  final index = _visualIndex(line, rect);
  final to = index + (forward ? 1 : -1);
  if (to >= 0 && to < line.visualLines.length) {
    final hit = line.hitAt(Offset(goal, _middle(line.visualLines[to])));
    if (hit != null) return EditorSelection.cursor(line.from + hit.pos, hit.assoc, null, goal.round());
  }
  final next = _nextEntry(view, entry, forward);
  if (next == null) return EditorSelection.cursor(head, start.assoc, null, goal.round());
  return _intoEntry(view, next, forward, goal, start, line);
}

/// The caret entering `entry` from above (`forward`) or below, at `goal`.
SelectionRange _intoEntry(EditorView view, int entry, bool forward, double goal, SelectionRange start, RenderEditorLine? from) {
  final state = view.state, doc = state.doc;
  final replaced = view.blocks.at(entry)?.replace;
  if (replaced != null) return EditorSelection.cursor(forward ? replaced.from : replaced.to, forward ? 1 : -1, null, goal.round());
  final first = doc.line(entry);
  final last = doc.line(math.min(doc.lines, view.blocks.lastLineOf(entry)));
  final target = view.lineAt(forward ? first.from : last.to);
  if (target != null && target.visualLines.isNotEmpty) {
    final hit = target.hitAt(Offset(goal, _middle(forward ? target.visualLines.first : target.visualLines.last)));
    if (hit != null) return EditorSelection.cursor(target.from + hit.pos, hit.assoc, null, goal.round());
  }
  // Not laid out: by column.
  final here = doc.lineAt(start.head);
  final column = countColumn(here.text, state.tabSize, start.head - here.from);
  final into = forward ? first : last;
  return EditorSelection.cursor(into.from + findColumn(into.text, column, state.tabSize), 0, null, goal.round());
}

SelectionRange _byDistance(EditorView view, RenderEditorLine line, Rect rect, double goal, SelectionRange start, bool forward, double distance) {
  final state = view.state, doc = state.doc;
  final look = view.look;
  final global = line.localToGlobal(Offset(goal, rect.center.dy)) + Offset(0, forward ? distance : -distance);
  // Where that is down the note, by the heights: the line there, if it is laid out, answers for itself.
  final top = (look?.env.contentTop ?? 0) + view.heights.offsetOf(view.blocks.entryOf(doc.lineAt(line.from).number));
  final y = top + rect.center.dy + (forward ? distance : -distance);
  if (y <= 0) return EditorSelection.cursor(0, 1, null, goal.round());
  if (y >= (look?.env.contentTop ?? 0) + view.heights.total) return EditorSelection.cursor(doc.length, -1, null, goal.round());
  final entry = view.blocks.entryOf(view.heights.lineAt(math.max(0, y - (look?.env.contentTop ?? 0))));
  final first = doc.line(entry);
  final target = view.lineAt(first.from);
  if (target != null) {
    final hit = target.hitAt(target.globalToLocal(global));
    if (hit != null) return EditorSelection.cursor(target.from + hit.pos, hit.assoc, null, goal.round());
  }
  if (view.blocks.at(entry)?.replace != null) return EditorSelection.cursor(first.from, 1, null, goal.round());
  final here = doc.lineAt(start.head);
  final column = countColumn(here.text, state.tabSize, start.head - here.from);
  return EditorSelection.cursor(first.from + findColumn(first.text, column, state.tabSize), 0, null, goal.round());
}

/// CodeMirror's `view.moveToLineBoundary(range, forward, includeWrap)`: the end or the start of the visual line the
/// head is on (of the whole line without `includeWrap`).
SelectionRange moveToLineBoundary(EditorView view, SelectionRange start, bool forward, {bool includeWrap = true}) {
  final state = view.state;
  final docLine = state.doc.lineAt(start.head);
  final whole = EditorSelection.cursor(forward ? docLine.to : docLine.from, forward ? -1 : 1);
  if (!includeWrap) return whole;
  final line = view.lineAt(start.head);
  final rect = line?.coordsAtPos(start.head - line.from, start.assoc != 0 ? start.assoc : -1);
  if (line == null || rect == null || line.visualLines.length < 2) return whole;
  final index = _visualIndex(line, rect);
  // The first visual line starts where the line does, and the last ends where it does, whatever is hidden there.
  if (!forward && index == 0) return EditorSelection.cursor(line.from, 1);
  if (forward && index == line.visualLines.length - 1) return EditorSelection.cursor(line.to, -1);
  final hit = line.hitAt(Offset(forward ? line.size.width + 100000 : -100000, _middle(line.visualLines[index])));
  if (hit == null) return whole;
  return EditorSelection.cursor(line.from + hit.pos, forward ? -1 : 1);
}

final RegExp _leadingSpace = RegExp(r'^\s*');

/// commands.ts `moveByLineBoundary`: the visual line's end, then the line's; going back, the first thing on the
/// line that is not a space before its very start.
SelectionRange _byLineBoundary(EditorView view, SelectionRange start, bool forward) {
  final line = view.state.doc.lineAt(start.head);
  var moved = moveToLineBoundary(view, start, forward);
  if (moved.head == start.head && moved.head != (forward ? line.to : line.from)) moved = moveToLineBoundary(view, start, forward, includeWrap: false);
  if (!forward && moved.head == line.from && line.length > 0) {
    final space = _leadingSpace.firstMatch(line.text.substring(0, math.min(100, line.length)))![0]!.length;
    if (space > 0 && start.head != line.from + space) moved = EditorSelection.cursor(line.from + space);
  }
  return moved;
}

Transaction _setSel(EditorState state, EditorSelection selection) => state.update(TransactionSpec(selection: selection, scrollIntoView: true, userEvent: 'select'));

bool _moveSel(EditorView view, SelectionRange Function(SelectionRange range) how) {
  final state = view.state;
  final selection = EditorSelection.create(<SelectionRange>[for (final r in state.selection.ranges) how(r)], state.selection.mainIndex);
  if (selection.eq(state.selection, true)) return false;
  view.dispatch(_setSel(state, selection));
  return true;
}

bool _extendSel(EditorView view, SelectionRange Function(SelectionRange range) how) {
  final state = view.state;
  final selection = EditorSelection.create(<SelectionRange>[
    for (final range in state.selection.ranges)
      () {
        final head = how(range);
        return EditorSelection.range(range.anchor, head.head, head.goalColumn, null, head.assoc);
      }(),
  ], state.selection.mainIndex);
  if (selection.eq(state.selection)) return false;
  view.dispatch(_setSel(state, selection));
  return true;
}

SelectionRange _rangeEnd(SelectionRange range, bool forward) => EditorSelection.cursor(forward ? range.to : range.from);

/// `cursorLineUp` and `cursorLineDown`: one visual line; at the note's first or last, to that line's edge.
bool cursorByLine(EditorView view, bool forward) => _moveSel(view, (range) {
  if (!range.empty) return _rangeEnd(range, forward);
  final moved = moveVertically(view, range, forward);
  return moved.head != range.head ? moved : moveToLineBoundary(view, range, forward);
});

/// `selectLineUp` and `selectLineDown`.
bool selectByLine(EditorView view, bool forward) => _extendSel(view, (range) => moveVertically(view, range, forward));

/// `cursorPageUp` and `cursorPageDown`.
bool cursorByPage(EditorView view, bool forward) {
  final height = EditorMotion.pageHeight(view);
  return _moveSel(view, (range) => range.empty ? moveVertically(view, range, forward, height) : _rangeEnd(range, forward));
}

/// `selectPageUp` and `selectPageDown`.
bool selectByPage(EditorView view, bool forward) {
  final height = EditorMotion.pageHeight(view);
  return _extendSel(view, (range) => moveVertically(view, range, forward, height));
}

/// `cursorLineBoundaryForward` and `Backward` on what is drawn: Home and End on a wrapped line.
bool cursorLineBoundary(EditorView view, bool forward) => _moveSel(view, (range) => _byLineBoundary(view, range, forward));

/// `selectLineBoundaryForward` and `Backward`.
bool selectLineBoundary(EditorView view, bool forward) => _extendSel(view, (range) => _byLineBoundary(view, range, forward));

/// `deleteLineBoundaryBackward` and `Forward`: to the visual line's edge, or the line break when already there.
bool deleteLineBoundary(EditorView view, bool forward) {
  final state = view.state;
  if (state.readOnly) return false;
  var event = 'delete.selection';
  final spec = state.changeByRange((range) {
    var from = range.from, to = range.to;
    if (range.empty) {
      final edge = moveToLineBoundary(view, range, forward).head;
      final towards = forward ? (range.head < edge ? edge : math.min(state.doc.length, range.head + 1)) : (range.head > edge ? edge : math.max(0, range.head - 1));
      if (towards < from) event = 'delete.backward';
      if (towards > from) event = 'delete.forward';
      from = math.min(from, towards);
      to = math.max(to, towards);
    }
    return from == to ? RangeChange(range: range) : RangeChange(changes: ChangeSpec(from: from, to: to), range: EditorSelection.cursor(from, from < range.head ? -1 : 1));
  });
  if ((spec.changes! as ChangeSet).empty) return false;
  view.dispatch(state.updateAll(<TransactionSpec>[spec, TransactionSpec(scrollIntoView: true, userEvent: event)]));
  return true;
}

/// The commands the keymaps name for the view to supply (`KeyBinding.viewCommand`).
final Map<String, bool Function(EditorView view)> viewCommands = <String, bool Function(EditorView view)>{
  'cursorLineUp': (view) => cursorByLine(view, false),
  'cursorLineDown': (view) => cursorByLine(view, true),
  'selectLineUp': (view) => selectByLine(view, false),
  'selectLineDown': (view) => selectByLine(view, true),
  'cursorPageUp': (view) => cursorByPage(view, false),
  'cursorPageDown': (view) => cursorByPage(view, true),
  'selectPageUp': (view) => selectByPage(view, false),
  'selectPageDown': (view) => selectByPage(view, true),
};

/// The [commands.verticalMotion] a view gives commands.dart: where `deleteLine` leaves the caret, one document
/// line away at the caret's own place across.
SelectionRange verticalMotionOf(EditorView view, EditorState state, SelectionRange range, bool forward) {
  if (!identical(state, view.state)) return commands.moveVerticallyByColumn(state, range, forward);
  final doc = state.doc;
  final here = doc.lineAt(range.head);
  final entry = view.blocks.entryOf(here.number);
  final next = _nextEntry(view, entry, forward);
  if (next == null) return EditorSelection.cursor(range.head);
  final line = view.lineAt(range.head);
  final rect = line?.coordsAtPos(range.head - line.from, _side(range, forward));
  if (rect == null) return commands.moveVerticallyByColumn(state, range, forward);
  return _intoEntry(view, next, forward, (range.goalColumn ?? rect.left.round()).toDouble(), range, line);
}

/// The atomic ranges round the selection, for commands.dart's [commands.atomicRangesFor]: what the view's
/// `atomicRanges` hold on the lines a caret can reach in one move, sorted.
List<({int from, int to})> atomicRangesOf(EditorView view, EditorState state) {
  if (!identical(state, view.state)) return const <({int from, int to})>[];
  final sets = view.atomicRanges;
  if (sets.isEmpty) return const <({int from, int to})>[];
  final doc = state.doc;
  final found = <({int from, int to})>[];
  for (final range in state.selection.ranges) {
    final a = doc.line(math.max(1, doc.lineAt(range.from).number - 1)).from;
    final b = doc.line(math.min(doc.lines, doc.lineAt(range.to).number + 1)).to;
    for (final set in sets) {
      set.between(a, b, (from, to, _) {
        found.add((from: from, to: to));
        return null;
      });
    }
  }
  found.sort((x, y) => x.from != y.from ? x.from - y.from : x.to - y.to);
  return found;
}

/// A position kept out of the inside of an atomic range: its nearer edge (CodeMirror's `skipAtomicRanges` with no
/// bias, what a pointer's selection is put through).
int skipAtoms(EditorView view, int pos) {
  for (;;) {
    var moved = false;
    for (final set in view.atomicRanges) {
      set.between(pos, pos, (from, to, _) {
        if (pos > from && pos < to) {
          pos = pos - from < to - pos ? from : to;
          moved = true;
        }
        return null;
      });
    }
    if (!moved) return pos;
  }
}
