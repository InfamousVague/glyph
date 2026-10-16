/// The home screen kept in step with the notes: each pass works out what the Today and Pinned widgets draw and what
/// the icon's recent notes are (home_data.dart), and hands over only what changed (home_host.dart). Asked for with
/// the reminders' pass (lib/root/phone_extras.dart), after the notes have been still a moment.
library;

import 'dart:async';

import '../core/note.dart';
import '../core/stored.dart';
import 'home_data.dart';
import 'home_host.dart';

/// Where the notes opened last are kept on this device, newest first.
const String recentNotesKey = 'glyph-recent-notes';

class HomeScreenData {
  HomeScreenData({required this.host, Stored? kept, DateTime Function()? clock})
      : _kept = kept ?? stored,
        _clock = clock ?? DateTime.now;

  final HomeScreenHost host;
  final Stored _kept;
  final DateTime Function() _clock;
  final Map<HomeKind, String> _sent = {};

  /// The notes opened last, newest first.
  List<String> get recent => _kept.read<List<String>>(recentNotesKey, const [], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : null);

  Future<void> _put(HomeKind kind, String json) async {
    if (_sent[kind] == json) return;
    _sent[kind] = json;
    final taken = await host.put(kind, json);
    if (!taken && _sent[kind] == json) _sent.remove(kind);
  }

  /// One pass over [notes]: the Today widget's to-dos, the pinned notes, and the recent notes' titles.
  Future<void> pass(List<Note> notes, Note? Function(String id) noteOf, {bool Function(Note note)? skip}) async {
    await _put(HomeKind.today, todayJson(todayItems(notes, now: _clock(), skip: skip)));
    await _put(HomeKind.pinned, namedJson(pinnedNotes(notes, skip: skip)));
    await _put(HomeKind.recent, namedJson(namedNotes(recent, noteOf, skip: skip)));
  }

  /// A note opened: first among the recent ones, and the icon's shortcuts told.
  Future<void> opened(String id, Note? Function(String id) noteOf, {bool Function(Note note)? skip}) async {
    final before = recent;
    final now = openedLast(before, id);
    if (now.length == before.length && now.indexed.every((each) => before[each.$1] == each.$2)) return;
    _kept.write(recentNotesKey, now);
    await _put(HomeKind.recent, namedJson(namedNotes(now, noteOf, skip: skip)));
  }

  /// The next pass hands everything over whatever it is.
  void forget() => _sent.clear();
}
