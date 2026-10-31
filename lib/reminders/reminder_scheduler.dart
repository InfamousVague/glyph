/// Reminders kept in step with the notes: a pass reads the library as it is (only the notes that changed are read
/// again: reminder_plan.dart [ReminderPlanner]), and hands the phone the plan only when it is another than the last
/// one handed over. Passes are asked for by whoever hears the library change (lib/root/phone_extras.dart), a moment
/// after the last change, never per keystroke: a note being typed in is saved every few hundred milliseconds, and
/// the pass waits for the saving to stop.
///
/// Notes that arrive by a sync are the library's changes like any other, and so are reminded here too.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../mentions/mention_reminders.dart' show mentionWho;
import 'reminder_host.dart';
import 'reminder_plan.dart';
import 'reminder_settings.dart';

/// Reminders made of something other than the notes' items, added to every plan: the morning's ticket digest on the
/// phone that sends it (lib/book/ticket_digest.dart). Set by whoever makes them; a pass reads it each time.
final ValueNotifier<List<Reminder> Function()?> extraReminders = ValueNotifier<List<Reminder> Function()?>(null);

class ReminderScheduler {
  ReminderScheduler({required this.host, required this.settings, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ReminderHost host;
  final ValueListenable<ReminderSettings> settings;
  final DateTime Function() _clock;
  final ReminderPlanner _planner = ReminderPlanner();

  /// The plan last handed over, as it was handed; null before the first, and after one the phone did not take.
  String? _sent;

  /// The plan the last pass made.
  List<Reminder> plan = const [];

  /// How many notes the last pass read again.
  int get lastRead => _planner.lastRead;

  /// One pass over [notes], [skip] leaving out what the Trash holds. True where the phone was handed a new plan.
  Future<bool> pass(List<Note> notes, {bool Function(Note note)? skip}) async {
    final made = [..._planner.plan(notes, settings: settings.value, now: _clock(), skip: skip, who: mentionWho.value), ...?extraReminders.value?.call()];
    plan = made;
    final json = planJson(made);
    if (json == _sent) return false;
    _sent = json;
    final taken = await host.set(json);
    if (!taken && _sent == json) _sent = null;
    return taken;
  }

  /// The next pass hands the plan over whatever it is: after the phone was restarted under the app, say.
  void forget() => _sent = null;
}

/// A pass asked for, run once things are still: [wait] after the last ask, and one at a time. [timer] is a test's.
class Settle {
  Settle(this.wait, this.run, {Timer Function(Duration wait, void Function() then)? timer}) : _timer = timer ?? Timer.new;

  final Duration wait;
  final Future<void> Function() run;
  final Timer Function(Duration wait, void Function() then) _timer;
  Timer? _waiting;
  bool _running = false;
  bool _again = false;
  bool _gone = false;

  /// Asks for a pass: [wait] from now, or after the one running ends.
  void poke() {
    if (_gone) return;
    _waiting?.cancel();
    _waiting = _timer(wait, _go);
  }

  /// A pass at once.
  Future<void> now() async {
    _waiting?.cancel();
    _waiting = null;
    await _go();
  }

  Future<void> _go() async {
    if (_gone) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      await run();
    } catch (failure) {
      debugPrint('[ghost] a reminders pass failed: $failure');
    } finally {
      _running = false;
    }
    if (_again && !_gone) {
      _again = false;
      poke();
    }
  }

  void dispose() {
    _gone = true;
    _waiting?.cancel();
  }
}
