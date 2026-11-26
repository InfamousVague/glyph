/// Snoozing a conversation (GMFB-36, from the Uplink gap review: snoozed messages were in Uplink's backlog, #53): it
/// leaves Messages until the time chosen, then comes back at the top with a notification, and stays at the top until
/// it is opened.
///
/// Kept with the app's choices (AppState), by the conversation's key (`text:<thread>`, or `space:<room>` for a
/// space's chat in Messages), and looked at by this app while it runs: a snooze whose time came while Ghost was closed
/// ends as soon as it opens again. Where the device has no notification for it (a computer), the app says it itself
/// while it is open ([Snoozed.back]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_state.dart';

/// The conversations snoozed and those just back from a snooze; whoever listens is told as either changes.
class Snoozed extends ChangeNotifier {
  Snoozed._();
  static final Snoozed instance = Snoozed._();

  /// The name it is kept under with the app's choices.
  static const storeKey = 'snoozed';

  /// What time it is: a test puts its own clock here.
  static DateTime Function() now = DateTime.now;

  /// Says a snooze is over ([key], what it was called): a notification on the phone. A test puts its own here.
  static void Function(String key, String title) woke = (_, _) {};

  /// Whether this device puts up a notification as a snooze ends; where it doesn't, [back] says it.
  static bool notifies = false;

  /// Says a snooze is over inside the app, where the device puts up no notification of it: [title] is what the
  /// conversation was called. Messages sets it while it is on the screen (lib/ui/conversations.dart) and says so in
  /// a toast; null while there is nowhere to say it.
  static void Function(String title)? back;

  AppState? _app;
  Timer? _timer;

  /// Each snoozed conversation's key: until when (ms), and what it was called when snoozed.
  Map<String, ({int until, String title})> _until = {};

  /// Those back from a snooze and not yet opened: at the top of Messages.
  Set<String> _woken = {};

  /// Reads what was kept, ends the snoozes whose time has come, and looks again every half minute.
  void start(AppState app) {
    _app = app;
    _read(app.choice(storeKey, '{}'));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => wakeDue());
    wakeDue();
  }

  /// For a test: as it was before [start].
  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    _app = null;
    _until = {};
    _woken = {};
  }

  /// What was kept: `{"u": {key: {"at": ms, "t": title}}, "w": [keys back and not yet opened]}`.
  void _read(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final u = j['u'], w = j['w'];
      _until = {
        if (u is Map)
          for (final e in u.entries)
            if (e.key is String && e.value is Map && (e.value as Map)['at'] is int) e.key as String: (until: (e.value as Map)['at'] as int, title: '${(e.value as Map)['t'] ?? ''}'),
      };
      _woken = {if (w is List) for (final k in w) if (k is String) k};
    } catch (_) {}
  }

  /// Keeps both, and tells whoever listens.
  void _save() {
    _app?.set(storeKey, jsonEncode({
      'u': {for (final e in _until.entries) e.key: {'at': e.value.until, 't': e.value.title}},
      'w': [..._woken],
    }));
    notifyListeners();
  }

  /// The key of a conversation of texts or with a friend, by its thread.
  static String text(int thread) => 'text:$thread';

  /// The key of a space's chat in Messages, by its room.
  static String space(String room) => 'space:$room';

  /// Whether [key] is out of Messages now.
  bool hides(String key) => _until.containsKey(key);

  /// Whether [key] is back from a snooze and not yet opened.
  bool woken(String key) => _woken.contains(key);

  /// When [key]'s snooze ends, where it is snoozed.
  DateTime? until(String key) => _until[key] == null ? null : DateTime.fromMillisecondsSinceEpoch(_until[key]!.until);

  /// How many are snoozed now.
  int get count => _until.length;

  /// Puts [key] away until [when].
  void snooze(String key, DateTime when, {String title = ''}) {
    _until[key] = (until: when.millisecondsSinceEpoch, title: title);
    _woken.remove(key);
    _save();
  }

  /// Brings [key] back now, without a notification.
  void unsnooze(String key) {
    if (_until.remove(key) == null) return;
    _save();
  }

  /// [key] was opened: it goes back to its place by date.
  void opened(String key) {
    if (!_woken.remove(key)) return;
    _save();
  }

  /// Ends every snooze whose time has come, each with its notification.
  void wakeDue() {
    final at = now().millisecondsSinceEpoch;
    final due = [for (final e in _until.entries) if (e.value.until <= at) e];
    if (due.isEmpty) return;
    for (final e in due) {
      _until.remove(e.key);
      _woken.add(e.key);
      woke(e.key, e.value.title);
    }
    _save();
  }

  /// The times offered, from [from]: in an hour, in three hours, this evening at six (while it is before five), tomorrow
  /// at nine, and next Monday at nine.
  static List<({String label, DateTime at})> choices(DateTime from) {
    final day = DateTime(from.year, from.month, from.day);
    final tomorrow = day.add(const Duration(days: 1));
    final monday = day.add(Duration(days: 8 - from.weekday));
    return [
      (label: 'For an hour', at: from.add(const Duration(hours: 1))),
      (label: 'For 3 hours', at: from.add(const Duration(hours: 3))),
      if (from.hour < 17) (label: 'Until this evening (6 PM)', at: day.add(const Duration(hours: 18))),
      (label: 'Until tomorrow (9 AM)', at: tomorrow.add(const Duration(hours: 9))),
      (label: 'Until next week (Monday, 9 AM)', at: monday.add(const Duration(hours: 9))),
    ];
  }
}
