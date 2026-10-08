/// Asking the plugins what the note's linked things are doing, and telling the note when they answer. Ports
/// `src/app/editor/markReads.ts`.
///
/// A mark (lib/core/item_links.dart) or a link a plugin reads is drawn from what that plugin knows
/// (lib/plugins/mark_details.dart): the pill at the end of an item (media/links.dart), the row of pills under it
/// (media/linked_rows.dart), and the box that follows its task (done_sync.dart). This is what keeps that knowledge
/// fresh: the details of every linked thing in view, and of every open card on a board in view, are asked for on
/// opening, on coming back to the front, once a minute while the note is open, and whenever the note changes or
/// scrolls. The plugin decides whether a read is due.
///
/// Answers arrive outside any update, so each is passed on as its own transaction, [detailsArrived], at most once a
/// frame; everything that draws from the details redraws on it.
///
/// What differs:
/// - `document.visibilityState` and `visibilitychange` are the app's lifecycle: anything but resumed is hidden (a
///   binding that has never been told is in front, as a test's is).
/// - "Once a frame" is the scheduler's next frame, which this asks for.
/// - The minute's timer runs only while something in view has a reader: with no plugin reading any mark in view
///   there is nobody to ask, and a note of plain words keeps no clock (a clock left running is also what a widget
///   test refuses to end with). A reader appearing later (its plugin switched on) is heard through
///   `onMarkDetails`, and the marks are asked for then.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../../core/boards.dart' show boardsIn, itemsIn;
import '../../core/item_links.dart';
import '../../plugins/mark_details.dart';
import '../editor.dart';
import '../view/lines.dart';

/// Details arrived from a plugin: redraw the pills and rows.
final StateEffectType<Null> detailsArrived = StateEffect.define<Null>();

/// A markdown link to a web address, its words then its address: what a plugin might read, in a line that is not
/// an item's mark. The rows under such lines (media/linked_rows.dart) find them the same way (`LINK`).
final RegExp linkPattern = RegExp(r'\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)');

/// Every linked thing in view, marks and links a plugin reads, for reading their details again.
List<ItemMark> marksInView(EditorViewLike view) {
  final marks = <ItemMark>[];
  forEachVisibleLine(view, (line) {
    final mark = itemWords(line.text) != null ? markOf(line.text) : null;
    if (mark != null) {
      marks.add(mark);
    } else if (line.text.contains('](')) {
      for (final match in linkPattern.allMatches(line.text)) {
        final url = match.group(2) ?? '';
        final name = markNameFor(url);
        if (name != null) marks.add(ItemMark(name: name, url: url));
      }
    }
  });
  return <ItemMark>[...marks, ..._marksOnBoards(view)];
}

/// The marks of the open to-dos on every board on screen.
///
/// A board is drawn as one block in place of its fence (lib/editor/boards), so its lines are not among
/// `visibleRanges`, and its cards are items written further down the note, usually well out of view. Read only by
/// their own lines, a board being looked at never learned its tasks were done, so it never moved them (Matt: "a lot
/// of the notion tickets aren't moved to done").
///
/// Only the cards not ticked yet: what a board shows of a task is whether it is done, and those are the cards that
/// can move. The rest are read as ever when their own lines are in view.
List<ItemMark> _marksOnBoards(EditorViewLike view) {
  final doc = view.state.doc;
  final viewport = view.viewport;
  final text = doc.toString();
  final shown = boardsIn(text).where((board) => doc.line(board.from).from <= viewport.to && doc.line(board.to).to >= viewport.from).toList();
  if (shown.isEmpty) return const <ItemMark>[];
  final open = <String, int>{
    for (final item in itemsIn(text))
      if (item.done == false) item.id: item.line,
  };
  final marks = <ItemMark>[];
  for (final board in shown) {
    for (final column in board.columns) {
      for (final id in column.cards) {
        final number = open[id];
        final line = number == null ? null : doc.line(number).text;
        final mark = line != null && itemWords(line) != null ? markOf(line) : null;
        if (mark != null) marks.add(mark);
      }
    }
  }
  return marks;
}

/// How often an open note reads its tasks again, while it is on screen (`REREAD_MS`).
const Duration rereadEvery = Duration(seconds: 60);

class _MarkReads extends PluginValue with WidgetsBindingObserver {
  _MarkReads(this.view, this.still) {
    _off = onMarkDetails(_arrived);
    if (still) return;
    WidgetsBinding.instance.addObserver(this);
    _want();
  }

  final EditorViewLike view;
  final bool still;
  late final void Function() _off;
  Timer? _timer;
  bool _queued = false;
  bool _gone = false;

  static bool get _hidden {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _want();
  }

  /// Asks for the details of the marks in view: read again if old.
  void _want() {
    if (_gone || _hidden) return;
    var read = false;
    for (final mark in marksInView(view)) {
      read = read || hasMarkDetails(mark.name);
      wantMarkDetails(mark.name, mark.url);
    }
    // The clock runs while there is somebody to ask.
    if (read) {
      _timer ??= Timer.periodic(rereadEvery, (_) => _want());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _arrived() {
    // A reader that was not there when the note opened: its marks are asked for now.
    if (!still && !_gone && _timer == null && marksInView(view).any((mark) => hasMarkDetails(mark.name))) _want();
    _redraw();
  }

  /// Answers arrive outside an update; the redraw is its own transaction, once per frame.
  void _redraw() {
    if (_queued || _gone) return;
    _queued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _queued = false;
      if (!_gone) view.dispatch(TransactionSpec(effects: detailsArrived.of(null)));
    });
  }

  @override
  void update(ViewUpdate update) {
    // While an IME composes, nothing is asked: the composition's end is a change of its own (glyph_lines.dart).
    if (still || update.view.composing) return;
    // A mark just made or scrolled to is read; one already read recently is not.
    if (update.docChanged || update.viewportChanged) _want();
  }

  @override
  void destroy() {
    _gone = true;
    _off();
    _timer?.cancel();
    if (!still) WidgetsBinding.instance.removeObserver(this);
  }
}

final ViewPlugin<_MarkReads> _reading = ViewPlugin.define<_MarkReads>((view) => _MarkReads(view, false));
final ViewPlugin<_MarkReads> _stillReading = ViewPlugin.define<_MarkReads>((view) => _MarkReads(view, true));

/// The reads, and the redraw their answers bring. `still`: nothing is ever asked for, and the note is drawn from
/// what is already known (a note drawn small on a card), though an answer that arrives is still drawn.
Extension markReads({required bool still}) => still ? _stillReading : _reading;
