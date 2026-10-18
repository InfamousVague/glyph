/// The calendars, read and kept for the life of the app (docs/CALENDAR.md): every iCal address the account has
/// fetched when the app opens and every 30 minutes while it is open, Google's ticked calendars every 15, and the
/// to-dos with a due date put on Google's when that is switched on. What was read is kept on this device
/// (store.dart) and handed to whatever shows it: a query's `from: events` and a calendar of to-dos
/// (lib/editor/queries), and the home page's Today (lib/home/home_events.dart).
///
/// The schedule is the account's sync engine's shape (lib/sync/engine.dart): [CalendarService.start] once from the
/// app's root, a pass straight away and on a beat while the app is open, one when it comes back to the front
/// ([CalendarService.resumed]), and one soon after the calendars change in Settings or on another device. Nothing is
/// fetched with Local only on, and nothing at all for an account with no calendars.
///
/// The app's calendars are the Calendar plugin's (lib/plugins/calendar, off until switched on): the root hands
/// [CalendarService.start] the plugin's switch. While it is off nothing is read, no to-do goes to Google's, and
/// [CalendarService.events] holds none, so no query and no Today shows one; what was read stays kept, and is shown
/// again the moment it is switched on, with a read soon after. A service started with no switch is always on.
///
/// Google's sign-in is collected by polling `claim` every 3 seconds for up to 10 minutes after Connect, and again
/// when the app comes back to the front, as docs/CALENDAR.md has it. Connect is offered only where glyph-api's
/// `start` does not answer 503 ([CalendarService.checkOffered]), in a build that has a service at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/api.dart' show FetchRequest, Fetcher, ioFetcher;
import '../core/open_link.dart' show openLink;
import '../core/preferences.dart';
import '../core/query/records.dart' show QueryEvent, QueryNote, libraryOf;
import '../core/stored.dart';
import '../root/account_wiring.dart' show accountBase, ghostApiDefine;
import 'event.dart';
import 'google.dart';
import 'ics.dart';
import 'setup.dart';
import 'store.dart';

/// How often each kind of calendar is read while the app is open.
const Duration icalEvery = Duration(minutes: 30);
const Duration googleEvery = Duration(minutes: 15);

/// How soon after the notes change the to-dos are put on Google (Matt, 2026-10-17: "show up on my personal calendar
/// in real time and are removed when removed"): a few seconds, so a run of typing is one pass, and only when what
/// goes on the calendar is not what was put there last.
const Duration todosSoon = Duration(seconds: 4);

/// How a Google sign-in is waited for: a claim every 3 seconds, for 10 minutes. glyph-api lets a phone 30 calls a
/// minute across its Google routes, and every 2 seconds was all 30 of them before the sign-in's own (Matt, 2026-10-17:
/// the page said Connected and the phone said Connect again, a claim having been refused as rate limited).
const Duration claimEvery = Duration(seconds: 3);
const Duration claimFor = Duration(minutes: 10);

/// The source key of Google's status line, beside each calendar's own.
const String googleSource = 'google';

/// Where glyph-api's Google routes are for this build: its service's base and `/google`; null in a build with none.
String? defaultGoogleBase() {
  final base = accountBase(ghostApiDefine);
  return base == null ? null : '$base/google';
}

/// The app's name to a calendar server.
const String _userAgent = 'GhostMd/0.1.0 (https://ghostmarkdown.com)';

class CalendarService extends ChangeNotifier {
  CalendarService({Fetcher? fetch, PreferencesStore? prefs, Stored Function()? kept, String? Function()? googleBase, int Function()? clock, Future<void> Function(String url)? open, this.todosWait = todosSoon})
      : _fetch = fetch,
        _prefs = prefs,
        _kept = CalendarKept(kept),
        _googleBase = googleBase ?? defaultGoogleBase,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _open = open ?? openLink;

  Fetcher? _fetch;
  final PreferencesStore? _prefs;
  final CalendarKept _kept;
  final String? Function() _googleBase;
  final int Function() _clock;

  /// How long after the notes change the to-dos go to Google: [todosSoon], shorter in a test.
  final Duration todosWait;
  final Future<void> Function(String url) _open;

  Fetcher get _fetcher => _fetch ??= ioFetcher();
  PreferencesStore get prefs => _prefs ?? preferences;

  /// Every event read, every calendar's together, in [inDayOrder]; none while the plugin is off ([active]). Told to
  /// its listeners when a read, or the switch, changes them.
  late final ValueNotifier<List<CalendarEvent>> events = ValueNotifier(_merged());

  /// The Calendar plugin's switch, as [start] was handed it: on where it was handed none.
  bool Function() _on = _always;
  static bool _always() => true;
  Listenable? _switched;

  /// Whether the calendars are read and shown: the plugin is on.
  bool get active => _on();

  List<QueryEvent>? _queryEvents;

  /// The events as a query reads them, made once for each change.
  List<QueryEvent> queryEvents() => _queryEvents ??= [for (final event in events.value) event.query];

  /// Every event on [day] (`YYYY-MM-DD`), in [inDayOrder].
  List<CalendarEvent> on(String day) => eventsOn(events.value, day);

  /// The calendars the account has.
  CalendarSetup get setup => calendarSetupOf(prefs.value);

  void _setSetup(CalendarSetup next) => prefs.update((now) => withCalendarSetup(now, next));

  /// How the last read of a source went: `ical:<id>`, `google:<id>`, or [googleSource] for Google's as a whole.
  SourceStatus? statusOf(String source) => _kept.statuses()[source];

  /// The account's Google calendars, as last listed.
  List<GoogleCalendarInfo> get googleCalendars => _kept.calendars;

  /// Whether Connect Google Calendar is offered: null until asked ([checkOffered]).
  bool? get offered => _offered;
  bool? _offered;

  /// Whether a Google sign-in is waiting to be collected.
  bool get connecting => _kept.flight != null && _claiming != null;

  /// Why the last Google sign-in did not finish, in words.
  String? get problem => _problem;
  String? _problem;

  /// Whether a read is running now.
  bool get busy => _icalPass != null || _googlePass != null;

  bool get _localOnly => prefs.value.localOnly;

  // ---- what was read ---------------------------------------------------------------------------------------------

  /// Every source the setup reads now: an address's, unless Google reads the same calendar, and each ticked Google
  /// calendar's.
  Set<String> _sources(CalendarSetup setup) {
    final google = setup.google;
    return {
      for (final address in setup.addresses)
        if (!_readByGoogle(address, setup)) 'ical:${address.id}',
      if (google != null)
        for (final id in google.ticked) 'google:$id',
    };
  }

  /// Whether [address] is the secret address of a calendar that is ticked under Google, which reads it instead.
  bool _readByGoogle(CalendarAddress address, CalendarSetup setup) {
    final google = setup.google;
    final id = googleCalendarOfAddress(address.url);
    return google != null && id != null && google.ticked.contains(id);
  }

  List<CalendarEvent> _merged() {
    if (!active) return const [];
    final live = _sources(setup);
    return inDayOrder([
      for (final MapEntry(:key, :value) in _kept.events().entries)
        if (live.contains(key)) ...value,
    ]);
  }

  void _changed() {
    final next = _merged();
    if (!listEquals(next, events.value)) {
      _queryEvents = null;
      events.value = next;
    }
    notifyListeners();
  }

  // ---- the schedule ----------------------------------------------------------------------------------------------

  List<QueryNote> Function()? _notes;
  Listenable? _notesChanged;
  Timer? _todosSoon;
  Timer? _icalBeat;
  Timer? _googleBeat;
  Timer? _soon;
  bool _started = false;
  String _seen = '';

  /// Whether [start] has been asked: the app reads calendars for its life.
  bool get started => _started;

  /// Starts reading for the life of the app: a read now, then on the beats, and when the calendars change. [notes]
  /// is the library a pass of to-dos reads, and [notesChanged] says when it changes (here or synced from another
  /// device): the to-dos are put on Google soon after ([todosSoon]). [on] is the Calendar plugin's switch, and
  /// [switched] says when it moves. Once.
  void start({List<QueryNote> Function()? notes, Listenable? notesChanged, bool Function()? on, Listenable? switched}) {
    _notes = notes ?? _notes;
    if (_started) return;
    _started = true;
    _notesChanged = notesChanged?..addListener(_onNotes);
    _on = on ?? _always;
    _wasOn = active;
    _switched = switched?..addListener(_onSwitch);
    _seen = jsonOfSetup(setup);
    _wasLocal = _localOnly;
    prefs.addListener(_onPrefs);
    _icalBeat = Timer.periodic(icalEvery, (_) => unawaited(syncIcal(force: true)));
    _googleBeat = Timer.periodic(googleEvery, (_) => unawaited(syncGoogle()));
    // After the first frame: nothing it does can throw into the launch.
    _soon = Timer(Duration.zero, () {
      _soon = null;
      unawaited(syncIcal(force: true));
      unawaited(syncGoogle());
      if (_kept.flight != null) _watchClaim();
    });
  }

  /// The app came back to the front: a sign-in in flight is collected, and what is due is read.
  void resumed() {
    if (!_started) return;
    if (_kept.flight != null) unawaited(collectGoogle());
    unawaited(syncIcal());
    final google = statusOf(googleSource);
    if (google == null || _clock() - google.at >= const Duration(minutes: 5).inMilliseconds) unawaited(syncGoogle());
  }

  /// Stops what [start] started, and a sign-in being waited for.
  void stop() {
    _stopClaim();
    if (!_started) return;
    _started = false;
    prefs.removeListener(_onPrefs);
    _switched?.removeListener(_onSwitch);
    _switched = null;
    _notesChanged?.removeListener(_onNotes);
    _notesChanged = null;
    _todosSoon?.cancel();
    _todosSoon = null;
    _icalBeat?.cancel();
    _googleBeat?.cancel();
    _soon?.cancel();
    _claiming?.cancel();
    _icalBeat = _googleBeat = _soon = _claiming = null;
  }

  @override
  void dispose() {
    stop();
    events.dispose();
    super.dispose();
  }

  static String jsonOfSetup(CalendarSetup setup) => jsonEncode(setup.toJson());

  /// The plugin switched: its events shown or put away at once, and read soon where it came on.
  bool _wasOn = true;
  void _onSwitch() {
    final now = active;
    if (now == _wasOn) return;
    _wasOn = now;
    _changed();
    if (!now) return;
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 300), () {
      _soon = null;
      unawaited(syncIcal(force: true));
      unawaited(syncGoogle());
    });
  }

  /// The settings changed: when the calendars are among what changed (here or on another device), what is new is
  /// read soon and what is gone is forgotten. Local only turned off is a read too.
  bool _wasLocal = false;
  void _onPrefs() {
    final now = jsonOfSetup(setup);
    final local = _localOnly;
    final unlocked = _wasLocal && !local;
    _wasLocal = local;
    if (now == _seen && !unlocked) return;
    _seen = now;
    _forgetGone();
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 300), () {
      _soon = null;
      unawaited(syncIcal(force: unlocked));
      unawaited(syncGoogle());
    });
  }

  /// Forgets what this device read of calendars the account no longer has.
  void _forgetGone() {
    final live = _sources(setup);
    final google = setup.google;
    _kept.drop([
      for (final source in {..._kept.events().keys, ..._kept.statuses().keys})
        if (!live.contains(source) && !(source == googleSource && google != null)) source,
    ]);
    if (google == null) {
      _kept.tokens = null;
      _kept.calendars = const [];
    }
    _changed();
  }

  // ---- iCal ------------------------------------------------------------------------------------------------------

  Future<void>? _icalPass;

  /// Reads every address that is due (each not read in [icalEvery], or all of them where [force] says), one after
  /// another. A pass already running is the one answered.
  Future<void> syncIcal({bool force = false}) => _icalPass ??= _ical(force).whenComplete(() {
        _icalPass = null;
        notifyListeners();
      });

  Future<void> _ical(bool force) async {
    if (_localOnly || !active) return;
    final current = setup;
    for (final address in current.addresses) {
      if (_readByGoogle(address, current)) continue;
      final source = 'ical:${address.id}';
      final last = statusOf(source);
      if (!force && last != null && _clock() - last.at < icalEvery.inMilliseconds) continue;
      await readAddress(address);
    }
  }

  /// Reads one address now and keeps what it gave; answers why it did not work, or null.
  Future<String?> readAddress(CalendarAddress address) async {
    final source = 'ical:${address.id}';
    String? problem;
    try {
      final response = await _fetcher(FetchRequest(method: 'GET', url: Uri.parse(address.url), headers: const {'Accept': 'text/calendar', 'User-Agent': _userAgent}));
      if (!response.ok) {
        problem = response.status == 404 || response.status == 410 ? 'The calendar isn’t at that address any more.' : 'The calendar answered ${response.status}.';
      } else {
        final window = calendarWindow(DateTime.fromMillisecondsSinceEpoch(_clock()));
        final text = response.text;
        if (!text.contains('BEGIN:VCALENDAR')) {
          problem = 'That address gives something that isn’t a calendar.';
        } else {
          final read = parseIcs(text, from: window.from, to: window.to);
          final name = read.name ?? address.label;
          _kept.setEvents(source, [
            for (final event in read.events)
              CalendarEvent(id: event.uid, source: source, calendar: name, title: event.title, start: event.start, end: event.end, allDay: event.allDay, location: event.location),
          ]);
          // The calendar's own name, once it says one: kept with the address, so every device shows it.
          if (read.name != null && read.name != address.name) {
            final now = setup;
            _setSetup(now.copyWith(addresses: [for (final each in now.addresses) each.id == address.id ? each.named(read.name) : each]));
            _seen = jsonOfSetup(setup);
          }
        }
      }
    } catch (_) {
      // Never the address: it is a secret.
      problem = 'The calendar couldn’t be reached. Check the connection.';
    }
    _kept.setStatus(source, SourceStatus(at: _clock(), problem: problem));
    _changed();
    return problem;
  }

  /// Adds the address [typed], and reads it. Answers why it was not added, or null.
  Future<String?> addAddress(String typed) async {
    final read = calendarAddress(typed);
    final url = read.url;
    if (url == null) return read.problem;
    final now = setup;
    final id = addressId(url);
    if (now.addresses.any((each) => each.id == id)) return 'That calendar is here already.';
    final address = CalendarAddress(id: id, url: url);
    _setSetup(now.copyWith(addresses: [...now.addresses, address]));
    _seen = jsonOfSetup(setup);
    _changed();
    if (_localOnly) return null;
    await readAddress(address);
    return null;
  }

  /// Takes the address off, and forgets what it gave.
  void removeAddress(String id) {
    final now = setup;
    _setSetup(now.copyWith(addresses: [for (final each in now.addresses) if (each.id != id) each]));
    _seen = jsonOfSetup(setup);
    _forgetGone();
  }

  // ---- Google ----------------------------------------------------------------------------------------------------

  GoogleCalendarApi? get _api {
    final base = _googleBase();
    return base == null ? null : GoogleCalendarApi(base: base, fetch: _fetcher, clock: _clock);
  }

  /// Whether Connect Google Calendar is offered: there is a service, and its `start` does not answer 503.
  Future<bool> checkOffered() async {
    final api = _api;
    final yes = api != null && !_localOnly && await api.offered();
    if (_offered != yes) {
      _offered = yes;
      notifyListeners();
    }
    return yes;
  }

  /// Starts Google's sign-in: the browser opens at the consent page, and the sign-in is waited for.
  Future<void> connectGoogle() async {
    final api = _api;
    if (api == null) return;
    _problem = null;
    final state = googleToken(), verifier = googleToken();
    _kept.flight = (state: state, verifier: verifier, at: _clock());
    _watchClaim();
    notifyListeners();
    await _open(api.startUrl(state, googleChallenge(verifier)).toString());
  }

  Timer? _claiming;
  bool _collecting = false;

  void _watchClaim() {
    _claiming?.cancel();
    _claiming = Timer.periodic(claimEvery, (_) => unawaited(collectGoogle()));
  }

  void _stopClaim() {
    _claiming?.cancel();
    _claiming = null;
  }

  /// Collects a sign-in in flight; once it is in, the calendars are listed, the primary ticked, and read.
  Future<void> collectGoogle() async {
    final flight = _kept.flight;
    final api = _api;
    if (flight == null || api == null || _collecting) return;
    if (_clock() - flight.at > claimFor.inMilliseconds) {
      _kept.flight = null;
      _stopClaim();
      _problem = 'The sign-in ran out of time. Connect Google Calendar again.';
      notifyListeners();
      return;
    }
    _collecting = true;
    try {
      final claim = await api.claim(flight.state, flight.verifier);
      if (claim is GooglePending) return;
      final tokens = (claim as GoogleSignedIn).tokens;
      _kept.flight = null;
      _stopClaim();
      final refresh = tokens.refreshToken ?? setup.google?.refreshToken;
      if (refresh == null) {
        _problem = 'Google didn’t give Ghost.md a way to stay signed in. Connect again.';
        return;
      }
      _kept.tokens = tokens;
      final session = GoogleSession(api: api, refreshToken: refresh, tokens: tokens, onTokens: (next) => _kept.tokens = next);
      var calendars = const <GoogleCalendarInfo>[];
      try {
        calendars = await session.calendars();
        _kept.calendars = calendars;
      } catch (_) {
        // Listed on the next pass.
      }
      final was = setup.google;
      final primary = calendars.where((each) => each.primary).firstOrNull;
      _setSetup(setup.copyWith(
        google: () => GoogleSetup(
          refreshToken: refresh,
          ticked: was?.ticked.isNotEmpty == true ? was!.ticked : [?primary?.id],
          todos: was?.todos ?? false,
          todoCalendar: was?.todoCalendar,
        ),
      ));
      _seen = jsonOfSetup(setup);
      _problem = null;
      _changed();
      unawaited(syncGoogle());
    } on GoogleFailure catch (failure) {
      // Turned away for now (rate limited, the service restarting or unreachable): asked again on the next beat,
      // the sign-in still in flight. Only a sign-in refused, expired or not this phone's ends it.
      if (failure.status == 0 || failure.status == 429 || failure.status >= 500) return;
      _kept.flight = null;
      _stopClaim();
      _problem = failure.message;
    } finally {
      _collecting = false;
      notifyListeners();
    }
  }

  /// Forgets Google: the sign-in, the calendars, and what they gave. The to-dos already on its calendar stay there.
  void disconnectGoogle() {
    _kept.flight = null;
    _stopClaim();
    _setSetup(setup.copyWith(google: () => null));
    _seen = jsonOfSetup(setup);
    _forgetGone();
  }

  /// Google's side changed here: what is no longer ticked is forgotten now, and what is, read soon.
  void _setGoogle(GoogleSetup Function(GoogleSetup google) change) {
    final google = setup.google;
    if (google == null) return;
    _setSetup(setup.copyWith(google: () => change(google)));
    _seen = jsonOfSetup(setup);
    _forgetGone();
    if (_started) unawaited(syncGoogle());
  }

  /// Ticks a calendar, or takes its tick off: its events are read, or forgotten.
  void tick(String calendarId, bool on) => _setGoogle((google) => google.copyWith(ticked: [for (final id in google.ticked) if (id != calendarId) id, if (on) calendarId]));

  /// To-dos on the calendar, on or off.
  void setTodos(bool on) => _setGoogle((google) => google.copyWith(todos: on));

  /// The calendar the to-dos go on.
  void setTodoCalendar(String calendarId) => _setGoogle((google) => google.copyWith(todoCalendar: () => calendarId));

  /// The calendar the to-dos go on: the one chosen, else the primary.
  String? todoCalendarOf(GoogleSetup google) => google.todoCalendar ?? googleCalendars.where((each) => each.primary).firstOrNull?.id ?? (googleCalendars.isEmpty ? null : 'primary');

  Future<void>? _googlePass;

  /// What was last put on Google of the to-dos: the calendar and each event's id, day and words. Null until a pass
  /// has, so the first after the app opens always does.
  String? _exported;

  static String _fingerprint(String calendarId, List<TodoEvent> todos) =>
      [calendarId, ...([for (final todo in todos) '${todo.id}|${todo.day}|${todo.time}|${todo.title}']..sort())].join('\n');

  /// The notes changed: the to-dos put on Google soon, where they go there at all.
  void _onNotes() {
    final google = setup.google;
    if (!_started || google == null || !google.todos || _localOnly || !active) return;
    _todosSoon?.cancel();
    _todosSoon = Timer(todosWait, () {
      _todosSoon = null;
      unawaited(exportTodosNow());
    });
  }

  Future<void>? _todoPass;
  bool _todosAgain = false;

  /// Puts the to-dos on Google now, alone, without reading any calendar: an added or moved to-do's event made or
  /// moved, a ticked or removed one's deleted. Nothing is asked of Google when they are what was put there last. A
  /// change while a pass runs is put there once it ends.
  Future<void> exportTodosNow() {
    if (_todoPass != null) {
      _todosAgain = true;
      return _todoPass!;
    }
    return _todoPass = _exportTodos().whenComplete(() {
      _todoPass = null;
      if (_todosAgain) {
        _todosAgain = false;
        unawaited(exportTodosNow());
      }
    });
  }

  Future<void> _exportTodos() async {
    final google = setup.google;
    final api = _api;
    final notes = _notes;
    if (google == null || api == null || notes == null || !google.todos || _localOnly || !active) return;
    final target = todoCalendarOf(google);
    if (target == null) return;
    // A whole pass running puts them there itself.
    if (_googlePass case final running?) await running;
    final wanted = todoEvents(libraryOf(notes()));
    final print = _fingerprint(target, wanted);
    if (print == _exported) return;
    try {
      await exportTodos(_session(google, api), target, wanted);
      _exported = print;
    } on GoogleFailure catch (failure) {
      _kept.setStatus(googleSource, SourceStatus(at: _clock(), problem: failure.message));
      _changed();
    } catch (_) {
      _kept.setStatus(googleSource, SourceStatus(at: _clock(), problem: 'Your to-dos couldn’t be put on Google Calendar.'));
      _changed();
    }
  }

  /// Lists the calendars, reads the ticked ones, and puts the to-dos on theirs when that is on. A pass already
  /// running is the one answered.
  Future<void> syncGoogle() => _googlePass ??= _google().whenComplete(() {
        _googlePass = null;
        notifyListeners();
      });

  /// The account's Google, its access kept on this device between passes.
  GoogleSession _session(GoogleSetup google, GoogleCalendarApi api) =>
      GoogleSession(api: api, refreshToken: google.refreshToken, tokens: _kept.tokens, onTokens: (next) => _kept.tokens = next);

  Future<void> _google() async {
    final google = setup.google;
    final api = _api;
    if (google == null || api == null || _localOnly || !active) return;
    String? problem;
    try {
      final session = _session(google, api);
      final calendars = await session.calendars();
      _kept.calendars = calendars;
      final window = calendarWindow(DateTime.fromMillisecondsSinceEpoch(_clock()));
      for (final calendar in calendars) {
        if (!google.ticked.contains(calendar.id)) continue;
        final source = 'google:${calendar.id}';
        try {
          _kept.setEvents(source, await session.events(calendar, from: window.from, to: window.to));
          _kept.setStatus(source, SourceStatus(at: _clock()));
        } on GoogleFailure catch (failure) {
          if (failure.status == 401) rethrow;
          _kept.setStatus(source, SourceStatus(at: _clock(), problem: failure.message));
        }
        _changed();
      }
      final notes = _notes;
      final target = todoCalendarOf(google);
      if (google.todos && notes != null && target != null) {
        final wanted = todoEvents(libraryOf(notes()));
        await exportTodos(session, target, wanted);
        _exported = _fingerprint(target, wanted);
      }
    } on GoogleFailure catch (failure) {
      problem = failure.message;
    } catch (_) {
      problem = 'Google Calendar couldn’t be read.';
    }
    _kept.setStatus(googleSource, SourceStatus(at: _clock(), problem: problem));
    _changed();
  }

  /// Every calendar read again now: Settings' Sync now, a pull on the home page.
  Future<void> syncNow() => Future.wait([syncIcal(force: true), syncGoogle()]);

  /// When anything was last read, and the problem of the last that went wrong, for Settings' line.
  ({int? at, String? problem}) get lastRead {
    int? at;
    String? problem;
    final live = {..._sources(setup), if (setup.google != null) googleSource};
    for (final MapEntry(:key, :value) in _kept.statuses().entries) {
      if (!live.contains(key)) continue;
      if (at == null || value.at > at) at = value.at;
      problem ??= value.problem;
    }
    return (at: at, problem: problem);
  }
}

/// The app's calendars, started by its root (lib/root/ghost_root.dart).
CalendarService calendar = CalendarService();
