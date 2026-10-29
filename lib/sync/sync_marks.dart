/// Each note's sync, marked by its title (docs/ACTIVITY.md, In place; Matt, 2026-10-29: "per-note sync marks (blue
/// arrow → tick) in lists and the note's header"): a small blue arrow while it waits to go (changed here and not yet
/// sent, or a team's note not yet sent), a tick for a moment as it goes, then nothing; red where it could not be sent,
/// with the reason.
///
/// Read cheaply, from what the sync already keeps, so a row asks as it is drawn and no list of notes is walked:
/// - **The account's notes**: the fingerprint each was last sent or taken at ([SyncState.notes], told by the engine as
///   it reads and saves it, lib/sync/engine.dart) against the note's own ([mark], made once per note as the row has
///   it). A note with no fingerprint and no words is not a note yet, and waits for nothing.
/// - **A team's notes** (docs/SHARED.md): their words travel in the team's document, so the channel says, as it sees to
///   each one (lib/team/sync.dart `_push`), the note as it was when it went: one changed here since waits. One the
///   channel has not seen to since the app started is not marked.
/// - **Sent** and **not sent** come from the sends themselves (lib/sync/notes.dart `_send`, `_sendCounted`; the
///   channel's `_push`): a tick for [NoteSyncMarks.tickFor] after the last, and red, with the first reason, until the
///   note goes.
///
/// Nothing is marked signed out, with "Nothing leaves the phone" on, or for a note live with another device (its words
/// go a keystroke at a time). The marks are nothing the sync needs: the engine and the channel tell them, and
/// lib/activity/sync_mark.dart draws them.
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import 'notes.dart' show FileKind, SyncState, isBlankNote, mark;

/// A note's sync as its title wears it.
enum NoteSyncLook {
  /// Synced, or not synced at all: nothing.
  none,

  /// Changed here, not yet sent: a blue arrow.
  waiting,

  /// Just sent: a tick, for a moment.
  sent,

  /// Could not be sent: red, with the reason.
  failed,
}

/// What a note's mark is, and why it failed.
@immutable
class NoteSyncMark {
  const NoteSyncMark(this.look, {this.reason, this.left});

  static const NoteSyncMark none = NoteSyncMark(NoteSyncLook.none);

  final NoteSyncLook look;
  final String? reason;

  /// How long a tick has left, where it is one.
  final Duration? left;

  @override
  bool operator ==(Object other) => other is NoteSyncMark && other.look == look && other.reason == reason;

  @override
  int get hashCode => Object.hash(look, reason);

  @override
  String toString() => 'NoteSyncMark(${look.name}${reason == null ? '' : ', $reason'})';
}

/// The marks of every note, told by the sync (see the header).
class NoteSyncMarks extends ChangeNotifier {
  NoteSyncMarks({this.tickFor = const Duration(milliseconds: 1600), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// How long a tick stays once a note has gone.
  final Duration tickFor;
  final DateTime Function() _clock;

  /// Whether this device syncs now: signed in, and not keeping everything here. Told by the engine; nothing is marked
  /// until it is.
  bool Function() syncing = () => false;

  /// Whether a note is a team's: filed in an organization's workspace, or a folder under it.
  bool Function(String id) teamNote = (_) => false;

  /// Whether a note is live with another device right now.
  bool Function(String id) live = (_) => false;

  SyncState? _account;
  final Map<String, int> _teamWent = {};
  final Map<String, DateTime> _sentAt = {};
  final Map<String, String> _failed = {};
  final Expando<String> _marks = Expando<String>('note sync mark');

  /// The account's sync as this device keeps it: read at the start of a pass and saved as it goes. Null forgets it.
  void account(SyncState? state) {
    _account = state;
    notifyListeners();
  }

  /// [id] went (an account's note, or a team's row or its words): a tick, and no red.
  void sent(String id) {
    _sentAt[id] = _clock();
    _failed.remove(id);
    notifyListeners();
  }

  /// A team's note seen to by its channel as it was at [updatedAt]: one changed after waits. [went], it was sent.
  void teamSeen(String id, int updatedAt, {bool went = false}) {
    _teamWent[id] = updatedAt;
    if (went) {
      sent(id);
    } else if (_failed.remove(id) != null) {
      notifyListeners();
    }
  }

  /// [id] could not be sent: red until it goes, with [reason].
  void failed(String id, String reason) {
    _failed[id] = reason;
    _sentAt.remove(id);
    notifyListeners();
  }

  final Map<String, int> _going = {};

  static String _file(FileKind kind, String name) => '${kind.name}/$name';

  /// A file going to the service now (lib/sync/notes.dart `sendFile`): a picture by its name, a recording by its
  /// note's id. Answers what to call once it has gone, sent or not.
  VoidCallback sending(FileKind kind, String name) {
    final key = _file(kind, name);
    _going[key] = (_going[key] ?? 0) + 1;
    notifyListeners();
    var told = false;
    return () {
      if (told) return;
      told = true;
      final left = (_going[key] ?? 1) - 1;
      left <= 0 ? _going.remove(key) : _going[key] = left;
      notifyListeners();
    };
  }

  /// Whether the file is going now: where it is drawn, a thin bar in its colour (the picture in the note, the note's
  /// tape).
  bool isSending(FileKind kind, String name) => _going.containsKey(_file(kind, name));

  /// The marks asked again: a tick's moment is up (lib/activity/sync_mark.dart).
  void refresh() => notifyListeners();

  /// Everything forgotten: a sign-out, and a test's fresh start.
  void forget() {
    _account = null;
    _teamWent.clear();
    _sentAt.clear();
    _failed.clear();
    notifyListeners();
  }

  String _markOf(Note note) => _marks[note] ??= mark(note);

  /// Whether [note] waits to go.
  bool waiting(Note note) {
    if (teamNote(note.id)) {
      final went = _teamWent[note.id];
      return went != null && note.updatedAt > went;
    }
    final state = _account;
    if (state == null) return false;
    final known = state.notes[note.id];
    if (known == null) return !isBlankNote(note);
    return known.mark != _markOf(note);
  }

  /// [note]'s mark now.
  NoteSyncMark of(Note note) {
    if (!syncing() || live(note.id)) return NoteSyncMark.none;
    final reason = _failed[note.id];
    final waits = waiting(note);
    if (reason != null && (waits || teamNote(note.id))) return NoteSyncMark(NoteSyncLook.failed, reason: reason);
    if (waits) return const NoteSyncMark(NoteSyncLook.waiting);
    final at = _sentAt[note.id];
    if (at != null) {
      final left = tickFor - _clock().difference(at);
      if (left > Duration.zero) return NoteSyncMark(NoteSyncLook.sent, left: left);
      _sentAt.remove(note.id);
    }
    return NoteSyncMark.none;
  }
}

/// The app's marks. A test puts its own in place ([useNoteSyncMarks]) and back.
NoteSyncMarks noteSyncMarks = NoteSyncMarks();

/// Makes [next] the app's marks.
void useNoteSyncMarks(NoteSyncMarks next) => noteSyncMarks = next;
