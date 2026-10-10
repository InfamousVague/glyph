/// A linked to-do and its task agree on whether it's done, both ways. Ports `src/app/editor/doneSync.ts`.
///
/// Matt, first: "Notion items that are done should automatically update the checked status of the checkbox for the
/// item they're listed in." Then: "notion tasks don't update in sync with linked list item in glyph". A linked item
/// ends with a mark (lib/core/item_links.dart), and the plugin behind the mark reads the task back for the pill
/// (lib/plugins/mark_details.dart). So:
///
/// - **The task changes, the box follows.** A task that reads as done ticks its `- [ ]`; one reopened unticks its
///   `- [x]`. An edit to the note, saved like typing, not part of the undo history (undoing a keystroke should not
///   untick a task Notion says is finished). Once per change of the task: a box set by hand stays as it was set
///   until the task itself changes again, so the note never fights the person holding it.
/// - **The box changes, the task follows.** Ticking or unticking a linked to-do in the note runs the plugin's own
///   Mark done or Reopen, the drawer's actions (mark_menu.dart). A task that can't be written, or a write that
///   fails, leaves the box as the person set it, and the next change of the task is the one that moves it.
///
/// An item linked the old way, its words the link, is the same (`linkedOn`, media/linked_rows.dart). Nothing is
/// read here but what a push needs; the pills' own reads (mark_reads.dart) are what arrive, for the marks in view
/// while the note is open.
///
/// What differs: `setTimeout(…, 0)` is a timer of no length; a failed write is told to `debugPrint` where the page
/// warned on the console.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/item_syntax.dart' show taskBox;
import '../../plugins/mark_details.dart';
import '../commands/task_toggle.dart' show settleFences;
import '../editor.dart';
import '../media/linked_rows.dart' show linkedOn;
import '../view/line_facts.dart' show webLinkFacts;

/// A box to set (`BoxChange`).
class BoxChange {
  const BoxChange({required this.from, required this.to, required this.url, required this.insert, required this.stamp});

  /// The space inside the box.
  final int from;
  final int to;
  final String url;

  /// What goes in it: "x" for done, " " for not.
  final String insert;

  /// When the task last changed as the service says it, or when it was read: the change this answers.
  final int stamp;
}

/// The boxes to set now: to-dos whose mark's task reads the other way, not already set for that change of the
/// task, and not one the person is sending to the service (`skip`).
List<BoxChange> boxesDue(Doc doc, Map<String, int> acted, [Set<String> skip = const <String>{}]) {
  final changes = <BoxChange>[];
  // A linked to-do has a link to a web address on its line: only the lines the tree keeps as having one are read
  // (lib/editor/view/line_facts.dart), where every line of the note was put to the to-do's pattern after each letter.
  for (final line in webLinkFacts.of(doc)) {
    final box = taskBox(line.text);
    if (box == null) continue;
    final mark = linkedOn(line.text);
    if (mark == null || !mark.item || skip.contains(mark.url)) continue;
    final entry = peekMarkDetails(mark.name, mark.url);
    if (entry is! MarkReady) continue;
    final details = entry.details;
    final status = details.status;
    if (details.gone || status == null) continue;
    final done = status.stage == Stage.done;
    if (done == box.done) continue;
    final stamp = details.editedAt ?? details.readAt;
    if (acted[mark.url] == stamp) continue;
    final at = line.from + box.at + 1;
    changes.add(BoxChange(from: at, to: at + 1, url: mark.url, insert: done ? 'x' : ' ', stamp: stamp));
  }
  return changes;
}

/// A box on a linked to-do the person ticked or unticked in this change: the task, and which way (`Flip`).
class Flip {
  const Flip({required this.name, required this.url, required this.done});

  final String name;
  final String url;
  final bool done;

  @override
  bool operator ==(Object other) => other is Flip && other.name == name && other.url == url && other.done == done;

  @override
  int get hashCode => Object.hash(name, url, done);

  @override
  String toString() => 'Flip($name, $url, done: $done)';
}

/// The linked to-dos whose box `tr` turned, compared line by line with what they were.
List<Flip> flipsIn(Transaction tr) {
  if (!tr.docChanged) return const <Flip>[];
  final flips = <String, Flip>{};
  final back = tr.changes.invertedDesc;
  final before = tr.startState.doc, after = tr.state.doc;
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) {
    for (var pos = fromB; pos <= toB;) {
      final line = after.lineAt(pos);
      final now = taskBox(line.text);
      final mark = now != null ? linkedOn(line.text) : null;
      if (now != null && mark != null && mark.item) {
        final mapped = back.mapPos(line.from, -1);
        final was = before.lineAt(mapped < before.length ? mapped : before.length);
        final then = taskBox(was.text);
        final wasMark = then != null ? linkedOn(was.text) : null;
        if (then != null && wasMark?.url == mark.url && then.done != now.done) flips[mark.url] = Flip(name: mark.name, url: mark.url, done: now.done);
      }
      pos = line.to + 1;
    }
  });
  return flips.values.toList();
}

class _DoneSync extends PluginValue {
  _DoneSync(this.view) {
    _off = onMarkDetails(_later);
    _later();
  }

  final EditorViewLike view;

  /// The change of each task a box was last set for, by either side.
  final Map<String, int> _acted = <String, int>{};

  /// Boxes the person set, to send to the service: done or not, and the mark's name.
  final Map<String, Flip> _sending = <String, Flip>{};

  /// Sends under way.
  final Set<String> _inFlight = <String>{};
  late final void Function() _off;
  Timer? _timer;
  bool _gone = false;

  @override
  void update(ViewUpdate update) {
    if (!update.docChanged) return;
    for (final tr in update.transactions) {
      if (tr.isUserEvent('sync')) continue;
      for (final flip in flipsIn(tr)) {
        _sending[flip.url] = flip;
      }
    }
    // A mark pasted or typed in, a box turned, or a composition ending: look again.
    _later();
  }

  @override
  void destroy() {
    _gone = true;
    _off();
    _timer?.cancel();
  }

  /// Answers arrive outside an update, and a change cannot be dispatched from inside one: the sync is its own turn.
  void _later() {
    if (_timer != null || _gone) return;
    _timer = Timer(Duration.zero, () {
      _timer = null;
      _sync();
    });
  }

  /// The task as it reads now: its change stamp and whether it's done, or null while unread.
  ({int stamp, bool? done})? _task(Flip flip) {
    final entry = peekMarkDetails(flip.name, flip.url);
    if (entry is! MarkReady) return null;
    final details = entry.details;
    final status = details.status;
    return (stamp: details.editedAt ?? details.readAt, done: details.gone || status == null ? null : status.stage == Stage.done);
  }

  /// Boxes the person set go to the service, through the plugin's own Mark done or Reopen.
  void _send() {
    for (final flip in _sending.values.toList()) {
      if (_inFlight.contains(flip.url)) continue;
      final task = _task(flip);
      if (task == null) {
        wantMarkDetails(flip.name, flip.url);
        continue;
      }
      final wanted = flip.done ? 'done' : 'reopen';
      final action = task.done == null || task.done == flip.done ? null : markActions(flip.name, flip.url, '').where((a) => a.id == wanted).firstOrNull;
      if (action == null) {
        // Already so, or nothing to write it with: the box stays as set until the task changes.
        _sending.remove(flip.url);
        _acted[flip.url] = task.stamp;
        continue;
      }
      _inFlight.add(flip.url);
      unawaited(
        Future<void>.sync(() async {
          await action.run();
        }).catchError((Object failure) => debugPrint('[glyph] the task did not follow its box: $failure')).whenComplete(() {
          _inFlight.remove(flip.url);
          // Turned again while it was sending: that turn is sent next.
          if (_sending[flip.url]?.done == flip.done) _sending.remove(flip.url);
          final after = _task(flip);
          if (after != null) _acted[flip.url] = after.stamp;
          if (!_gone) _later();
        }),
      );
    }
  }

  void _sync() {
    // While an IME composes, the document is not touched (glyph_lines.dart); the composition's end brings a change.
    if (_gone || view.composing) return;
    _send();
    final changes = boxesDue(view.state.doc, _acted, _sending.keys.toSet());
    if (changes.isEmpty) return;
    for (final change in changes) {
      _acted[change.url] = change.stamp;
    }
    // A task going done in Notion moves its card the way a tap on the box does, in the same change: the lanes of a
    // board say what its ticks say, however the tick arrived (lib/core/boards.dart, lib/editor/boards).
    final ticks = <int, bool>{for (final change in changes) view.state.doc.lineAt(change.from).number: change.insert != ' '};
    view.dispatch(
      TransactionSpec(
        changes: <ChangeSpec>[
          for (final change in changes) ChangeSpec(from: change.from, to: change.to, insert: change.insert),
          ...settleFences(view.state, ticks),
        ],
        annotations: <Annotation<Object?>>[Transaction.addToHistory.of(false), Transaction.userEvent.of('sync.tick')],
      ),
    );
  }
}

final ViewPlugin<_DoneSync> _plugin = ViewPlugin.define<_DoneSync>(_DoneSync.new);

/// A linked to-do's box follows its task, and its task its box.
Extension doneSync() => _plugin;
