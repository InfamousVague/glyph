/// What the app does on the phone outside its own window (docs/FEATURES_2_1.md): reminders for to-dos and tickets,
/// the home screen's widgets and the icon's recent notes, and the Done either hands back. Made by the root on Android
/// over the real library (lib/root/ghost_root.dart), and on no other platform: an iPhone, a Mac and a test have no
/// phone half for any of it, and nothing is offered there.
///
/// - **A pass** a moment after the notes, the Trash or the reminder settings last changed (a sync's notes included):
///   the reminders' plan (lib/reminders/reminder_scheduler.dart) and the home screen's data
///   (lib/home_screen/home_screen_data.dart), each handed over only when it is another than the last. The first pass
///   is at once, as the app opens, and hands everything over: an app stopped by force has lost its alarms.
/// - **Done** from a notification or the Today widget, while the app runs: written into a note that is open on screen
///   through its editor, saved like typing, so the note's own next save never meets it as somebody else's words; into
///   any other note through the library (lib/reminders/done_writer.dart).
/// - **A note opened** is first among the icon's recent notes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../core/library.dart';
import '../core/note.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../editor/editor.dart';
import '../home_screen/home_host.dart';
import '../home_screen/home_screen_data.dart';
import '../reminders/background_tick.dart' as background show ghostBackground;
import '../reminders/done_writer.dart';
import '../reminders/reminder_host.dart';
import '../reminders/reminder_scheduler.dart';
import '../reminders/reminder_settings.dart';
import '../reminders/tick_item.dart';
import '../shell/screen.dart';

class PhoneExtras {
  PhoneExtras({
    required this.library,
    required this.trash,
    required this.reminders,
    required this.home,
    ReminderSettingsStore? settings,
    Stored? kept,
    this.openView,
    DateTime Function()? clock,
    Duration settle = const Duration(milliseconds: 1500),
    Timer Function(Duration wait, void Function() then)? timer,
  })  : settings = settings ?? reminderSettings,
        _clock = clock ?? DateTime.now {
    _scheduler = ReminderScheduler(host: reminders, settings: this.settings, clock: _clock);
    _home = HomeScreenData(host: home, kept: kept, clock: _clock);
    _settle = Settle(settle, _pass, timer: timer);
  }

  final NoteLibrary library;
  final Trash trash;
  final ReminderHost reminders;
  final HomeScreenHost home;
  final ReminderSettingsStore settings;

  /// The editor of the note [noteId] where it is open on screen; null where it is not.
  final EditorViewLike? Function(String noteId)? openView;

  final DateTime Function() _clock;
  late final ReminderScheduler _scheduler;
  late final HomeScreenData _home;
  late final Settle _settle;
  bool _started = false;
  AppLifecycleListener? _life;

  /// The reminders' scheduler, for a test.
  @visibleForTesting
  ReminderScheduler get scheduler => _scheduler;

  bool _skip(Note note) => trash.isTrashed(note.id);

  Future<void> _pass() async {
    final notes = library.value;
    await _scheduler.pass(notes, skip: _skip);
    await _home.pass(notes, library.noteOf, skip: _skip);
  }

  void _changed() => _settle.poke();

  /// From the notes' first read on: listening, and the first pass at once.
  void start() {
    if (_started) return;
    _started = true;
    // Kept in the build: the entry point the phone runs with the app closed lives in a library nothing else imports.
    assert(identical(background.ghostBackground, background.ghostBackground));
    library.addListener(_changed);
    trash.addListener(_changed);
    settings.addListener(_changed);
    reminders.onTick = done;
    phoneReminders.value = reminders;
    _life = AppLifecycleListener(onResume: resumed);
    unawaited(_settle.now());
  }

  /// The screen changed: a note opened is first among the recent ones.
  void screen(Screen now) {
    if (now is ScreenNote) unawaited(_home.opened(now.note.id, library.noteOf, skip: _skip));
  }

  /// The app came back to the front: everything handed over again at the next pass, in case the phone was restarted
  /// or the app's alarms were cleared under it.
  void resumed() {
    _scheduler.forget();
    _home.forget();
    _settle.poke();
  }

  /// Done for the item said as [words] on [line] of [noteId] (0 for a ticket), from outside the app's window.
  Future<bool> done(String noteId, int line, String words) async {
    final view = openView?.call(noteId);
    if (view != null && !view.state.readOnly) {
      final doc = view.state.doc.toString();
      final next = doneIn(doc, line: line, words: words);
      if (next == null || next == doc) return false;
      // Only what differs, as one edit: the caret and everything around the box stay where they are.
      var head = 0;
      while (head < next.length && head < doc.length && next.codeUnitAt(head) == doc.codeUnitAt(head)) {
        head += 1;
      }
      var tail = 0;
      while (tail < next.length - head && tail < doc.length - head && next.codeUnitAt(next.length - 1 - tail) == doc.codeUnitAt(doc.length - 1 - tail)) {
        tail += 1;
      }
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: head, to: doc.length - tail, insert: next.substring(head, next.length - tail)), userEvent: 'input.toggle'));
      return true;
    }
    try {
      final written = await writeDone(library, noteId, line, words);
      if (written) await library.refresh();
      return written;
    } catch (failure) {
      debugPrint('[ghost] a Done from outside the app was not written: $failure');
      await library.refresh().catchError((Object _) {});
      return false;
    }
  }

  void dispose() {
    _settle.dispose();
    if (!_started) return;
    _started = false;
    _life?.dispose();
    _life = null;
    library.removeListener(_changed);
    trash.removeListener(_changed);
    settings.removeListener(_changed);
    reminders.onTick = null;
    if (identical(phoneReminders.value, reminders)) phoneReminders.value = null;
  }
}
