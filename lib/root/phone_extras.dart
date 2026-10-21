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
/// - **The home screen's widgets** (docs/WIDGETS_ANDROID.md) are handed the to-dos, the notes, the recordings and the
///   calendars' events by the same pass, which a change to the events asks for too.
/// - **Places**, while the Place reminders plugin is on (lib/plugins/places): the same pass works out the open to-dos
///   with a `📍` and hands the phone the whole set for its geofences (lib/reminders/place_scheduler.dart), and the
///   plugin switched off clears them; as the app opens and comes back to the front, whether the location they need
///   is allowed, for the chips' quiet warning ([placeWarning]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../calendar/event.dart' show CalendarEvent;
import '../core/library.dart';
import '../core/note.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../editor/editor.dart';
import '../home_screen/home_host.dart';
import '../home_screen/home_screen_data.dart';
import '../reminders/background_tick.dart' as background show ghostBackground;
import '../reminders/done_writer.dart';
import '../reminders/place_access.dart' show placeAccessWarns;
import '../reminders/place_host.dart';
import '../reminders/place_scheduler.dart';
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
    this.places,
    bool Function()? placesOn,
    this.placesSwitch,
    ReminderSettingsStore? settings,
    Stored? kept,
    this.openView,
    this.events,
    bool Function()? calendarOn,
    String Function()? scheme,
    this.lookChanged,
    DateTime Function()? clock,
    Duration settle = const Duration(milliseconds: 1500),
    Timer Function(Duration wait, void Function() then)? timer,
  })  : settings = settings ?? reminderSettings,
        placesOn = placesOn ?? _off,
        calendarOn = calendarOn ?? _off,
        scheme = scheme ?? _dark,
        _clock = clock ?? DateTime.now {
    _scheduler = ReminderScheduler(host: reminders, settings: this.settings, clock: _clock);
    final watched = places;
    _places = watched == null ? null : PlaceScheduler(host: watched, on: this.placesOn, reminders: this.settings);
    _home = HomeScreenData(host: home, kept: kept, clock: _clock);
    _settle = Settle(settle, _pass, timer: timer);
  }

  final NoteLibrary library;
  final Trash trash;
  final ReminderHost reminders;
  final HomeScreenHost home;
  final ReminderSettingsStore settings;

  /// The phone's geofences, where it has them; null and nothing is watched.
  final PlaceHost? places;

  /// Whether the Place reminders plugin is switched on; off where nothing says.
  final bool Function() placesOn;

  /// What tells when [placesOn] may have changed: the plugins' registry.
  final Listenable? placesSwitch;

  static bool _off() => false;

  /// The calendars' events for the home screen's Calendar widget (lib/calendar `calendar.events`, empty while the
  /// plugin is off), and whether the Calendar plugin is on; none and off where nothing says.
  final ValueListenable<List<CalendarEvent>>? events;
  final bool Function() calendarOn;

  /// The side of the app's theme (`themeScheme`: dark, light or system), the widgets' look, and what tells when it
  /// may have changed (the preferences); the app's own Dark where nothing says.
  final String Function() scheme;
  final Listenable? lookChanged;
  static String _dark() => 'dark';

  /// The editor of the note [noteId] where it is open on screen; null where it is not.
  final EditorViewLike? Function(String noteId)? openView;

  final DateTime Function() _clock;
  late final ReminderScheduler _scheduler;
  late final PlaceScheduler? _places;
  late final HomeScreenData _home;
  late final Settle _settle;
  bool _started = false;
  AppLifecycleListener? _life;

  /// The reminders' scheduler, for a test.
  @visibleForTesting
  ReminderScheduler get scheduler => _scheduler;

  /// The places' scheduler, for a test.
  @visibleForTesting
  PlaceScheduler? get placeScheduler => _places;

  bool _skip(Note note) => trash.isTrashed(note.id);

  Future<void> _pass() async {
    final notes = library.value;
    await _scheduler.pass(notes, skip: _skip);
    await _places?.pass(notes, skip: _skip);
    await _home.pass(notes, library.noteOf, skip: _skip, calendarOn: calendarOn(), events: events?.value ?? const [], scheme: scheme());
  }

  void _changed() => _settle.poke();

  /// The switches changed: the set again, and whether its chips warn.
  void _placesChanged() {
    if (places != null) placeRemindersOn.value = placesOn();
    _settle.poke();
    unawaited(readPlaceAccess());
  }

  /// Whether the location place reminders need is allowed, read again: the chips warn where it is not and places
  /// are watched.
  Future<void> readPlaceAccess() async {
    final host = places, scheduler = _places;
    if (host == null || scheduler == null) return;
    final access = scheduler.watching ? await host.access() : null;
    if (_started) placeWarning.value = scheduler.watching && placeAccessWarns(access);
  }

  /// From the notes' first read on: listening, and the first pass at once.
  void start() {
    if (_started) return;
    _started = true;
    // Kept in the build: the entry point the phone runs with the app closed lives in a library nothing else imports.
    assert(identical(background.ghostBackground, background.ghostBackground));
    library.addListener(_changed);
    trash.addListener(_changed);
    settings.addListener(_placesChanged);
    // The calendars read again, or the Calendar plugin switched (which empties or fills the events): the Calendar
    // widget drawn again at the next pass.
    events?.addListener(_changed);
    lookChanged?.addListener(_changed);
    reminders.onTick = done;
    phoneReminders.value = reminders;
    if (places != null) {
      placesSwitch?.addListener(_placesChanged);
      phonePlaces.value = places;
      placeRemindersOn.value = placesOn();
      unawaited(readPlaceAccess());
    }
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
    _places?.forget();
    _home.forget();
    _settle.poke();
    // Allowed or taken back in the phone's settings meanwhile.
    unawaited(readPlaceAccess());
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
    settings.removeListener(_placesChanged);
    events?.removeListener(_changed);
    lookChanged?.removeListener(_changed);
    reminders.onTick = null;
    if (identical(phoneReminders.value, reminders)) phoneReminders.value = null;
    if (places != null) {
      placesSwitch?.removeListener(_placesChanged);
      if (identical(phonePlaces.value, places)) {
        phonePlaces.value = null;
        placeRemindersOn.value = false;
        placeWarning.value = false;
      }
    }
  }
}
