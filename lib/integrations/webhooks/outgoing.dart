/// Outgoing webhooks, sent by this device (docs/INTEGRATIONS.md, §1): a note this device changed, in a hook's scope,
/// is POSTed to the hook's URL as payload.dart writes it, signed where the hook has a secret.
///
/// - **Only the device that made the change sends it**, never the server (it cannot read notes) and never a device
///   the change arrived on: what is heard is [CoreLibrary.savedHere], which a note written by sync never passes.
/// - **At most once per note per [quietFor]**: each save of a note puts its send back, so a run of typing is one call,
///   with the words before the run and after it; a note saved without a break is sent [mostFor] after its first save
///   all the same.
/// - **Failures are tried again three times** ([retryWaits]), then said in the pane ([WebhookSender.statusOf]),
///   which keeps how each hook last went on this device.
/// - **Nothing is sent with Local only on, nor while the plugin is off** (plugin.dart), asked when a note is saved,
///   when its send is due, and before each try.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, Fetcher, ioFetcher;
import '../../core/book.dart' show bookIndex, placeOf;
import '../../core/core_library.dart' show SavedHere;
import '../../core/note.dart';
import '../../core/preferences.dart';
import '../../core/stored.dart';
import '../../core/tags.dart' show tagsIn;
import '../../plugins/registry.dart' show plugins;
import '../../sync/kept_secrets.dart';
import 'payload.dart';
import 'setup.dart';

/// How long a note must go unsaved before its change is sent.
const Duration quietFor = Duration(seconds: 10);

/// The longest a note saved over and over waits for its send.
const Duration mostFor = Duration(minutes: 1);

/// How long each of the three tries after a failure waits.
const List<Duration> retryWaits = [Duration(seconds: 2), Duration(seconds: 10), Duration(seconds: 30)];

const String _statusKey = 'glyph-webhooks-status';
const String _userAgent = 'GhostMd/0.1.0 (https://ghostmarkdown.com)';

/// How a hook's last send went: when, which event, and what went wrong, in words, where something did.
@immutable
class HookStatus {
  const HookStatus({required this.at, this.event, this.problem});

  /// Milliseconds since the epoch.
  final int at;
  final String? event;
  final String? problem;

  Map<String, Object?> toJson() => {'at': at, if (event != null) 'event': event, if (problem != null) 'problem': problem};

  static HookStatus? fromJson(Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    final event = raw['event'], problem = raw['problem'];
    return HookStatus(at: (raw['at'] as num).toInt(), event: event is String ? event : null, problem: problem is String ? problem : null);
  }
}

/// One note's run of saves, waiting to be sent.
class _Run {
  _Run(this.before);

  /// The words before the run; null for a note made in it.
  final String? before;
  late Note after;
  Timer? quiet;
  Timer? most;

  void cancel() {
    quiet?.cancel();
    most?.cancel();
  }
}

/// The outgoing hooks' sender, for the life of the app (see the header).
class WebhookSender extends ChangeNotifier {
  /// [on] says whether the plugin is on (plugin.dart): the registry's switch unless a test says.
  /// [secrets] holds the hooks' secrets (lib/sync/kept_secrets.dart; setup.dart says why): the app's own unless a test
  /// gives its own.
  WebhookSender({Fetcher? fetch, PreferencesStore? prefs, Stored Function()? kept, KeptSecrets? secrets, int Function()? clock, Future<void> Function(Duration wait)? wait, bool Function()? on})
      : _fetch = fetch,
        _on = on ?? (() => plugins.isEnabled(webhooksId)),
        _prefs = prefs,
        _kept = kept ?? (() => stored),
        _secrets = secrets ?? integrationSecrets,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _wait = wait ?? ((time) => Future<void>.delayed(time));

  Fetcher? _fetch;
  final PreferencesStore? _prefs;
  final Stored Function() _kept;
  final KeptSecrets _secrets;
  final int Function() _clock;
  final Future<void> Function(Duration wait) _wait;
  final bool Function() _on;

  Fetcher get _fetcher => _fetch ??= ioFetcher();
  PreferencesStore get prefs => _prefs ?? preferences;

  /// The hooks the account has, their secrets from the secure store: before [ready] has read those, a hook reads as
  /// unsigned, which is why a send waits on it.
  WebhookSetup get setup => webhookSetupOf(prefs.value, secret: _secrets.peek);

  void _setSetup(WebhookSetup next) => prefs.update((now) => withWebhookSetup(now, next));

  Future<void>? _readying;

  /// The secrets read from the secure store, and any an older build left in the settings blob moved there and taken
  /// out of the blob (setup.dart, "the secret is not in it"). Every send waits on it; asked again after the settings
  /// change, for a hook added on another device, or a blob an older device wrote.
  Future<void> ready() => _readying ??= _ready().whenComplete(() => _readying = null);

  Future<void> _ready() async {
    final raw = prefs.value.more[webhooksKey];
    await _secrets.load([for (final id in WebhookSetup.hookIdsIn(raw)) webhookSecretName(id)]);
    if (!WebhookSetup.storedInTheClear(raw)) return;
    for (final hook in WebhookSetup.fromJson(raw).outgoing) {
      final secret = hook.secret;
      if (secret != null && _secrets.peek(webhookSecretName(hook.id)) == null) await _secrets.write(webhookSecretName(hook.id), secret);
    }
    if (identical(prefs.value.more[webhooksKey], raw)) _setSetup(setup);
  }

  void _onPrefs() {
    final raw = prefs.value.more[webhooksKey];
    if (WebhookSetup.storedInTheClear(raw) || WebhookSetup.hookIdsIn(raw).any((id) => !_secrets.loaded(webhookSecretName(id)))) unawaited(ready());
  }

  /// Nothing is sent with Local only on, nor while the plugin is off.
  bool get _localOnly => prefs.value.localOnly || !_on();

  // ---- the hooks -------------------------------------------------------------------------------------------------

  /// Adds a hook for [typed]; answers why it was not added, or null.
  String? add(String typed, {required Set<WebhookEvent> events, WebhookScope scope = const WebhookScope.all(), String? secret, String? id}) {
    final read = webhookUrl(typed);
    final url = read.url;
    if (url == null) return read.problem;
    if (events.isEmpty) return 'Choose at least one thing to be told of.';
    if (scope.kind != ScopeKind.all && (scope.value == null || scope.value!.isEmpty)) return 'Choose which notes.';
    final now = setup;
    final made = id ?? 'out-${_clock().toRadixString(36)}-${now.outgoing.length}';
    final kept = secret?.trim();
    final signed = kept == null || kept.isEmpty ? null : kept;
    // The secret into the secure store, never the blob (setup.dart says why): held in memory at once, so the hook
    // reads signed from the next line on.
    if (signed != null) unawaited(_secrets.write(webhookSecretName(made), signed));
    _setSetup(now.copyWith(outgoing: [...now.outgoing, OutgoingHook(id: made, url: url, events: events, scope: scope, secret: signed)]));
    notifyListeners();
    return null;
  }

  /// Takes a hook off, its secret and what this device kept of how it went with it.
  void remove(String id) {
    final now = setup;
    _setSetup(now.copyWith(outgoing: [for (final hook in now.outgoing) if (hook.id != id) hook]));
    unawaited(_secrets.write(webhookSecretName(id), null));
    final all = statuses()..remove(id);
    _writeStatuses(all);
    notifyListeners();
  }

  Map<String, HookStatus> statuses() {
    final raw = _kept().read<Object?>(_statusKey, null);
    if (raw is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && HookStatus.fromJson(value) != null) key: HookStatus.fromJson(value)!,
    };
  }

  void _writeStatuses(Map<String, HookStatus> all) => _kept().write(_statusKey, all.isEmpty ? null : {for (final MapEntry(:key, :value) in all.entries) key: value.toJson()});

  /// How [hookId]'s last send went; null before its first.
  HookStatus? statusOf(String hookId) => statuses()[hookId];

  void _setStatus(String hookId, HookStatus status) {
    _writeStatuses(statuses()..[hookId] = status);
    notifyListeners();
  }

  // ---- what is heard ---------------------------------------------------------------------------------------------

  List<Note> Function() _notes = () => const [];
  StreamSubscription<SavedHere>? _heard;
  final Map<String, _Run> _runs = {};

  /// Notes made with no words yet, whose making is still to be told once they have some.
  final Set<String> _unsaid = {};

  /// Whether [start] has been asked.
  bool get started => _heard != null;

  /// Hears [saves] for the life of the app; [notes] is the library, for which notebook a note is a page of.
  void start({required Stream<SavedHere> saves, List<Note> Function()? notes}) {
    if (notes != null) _notes = notes;
    if (_heard != null) return;
    _heard = saves.listen((saved) => heard(saved.before, saved.after));
    prefs.addListener(_onPrefs);
    unawaited(ready());
  }

  void stop() {
    if (_heard != null) prefs.removeListener(_onPrefs);
    unawaited(_heard?.cancel());
    _heard = null;
    for (final run in _runs.values) {
      run.cancel();
    }
    _runs.clear();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// A note this device changed: [before] as it was (null for one made now), [after] as it is. Its send waits for
  /// the run of saves to end.
  void heard(Note? before, Note after) {
    if (_localOnly || setup.outgoing.isEmpty) return;
    final run = _runs.putIfAbsent(after.id, () => _Run(before == null || _unsaid.contains(after.id) ? null : before.body));
    run.after = after;
    run.quiet?.cancel();
    run.quiet = Timer(quietFor, () => unawaited(_due(after.id)));
    run.most ??= Timer(mostFor, () => unawaited(_due(after.id)));
  }

  /// Every send still waiting, sent now: for a test, and for the app going behind another.
  Future<void> flush() => Future.wait([for (final id in [..._runs.keys]) _due(id)]);

  Future<void> _due(String id) async {
    final run = _runs.remove(id);
    if (run == null) return;
    run.cancel();
    if (_localOnly) return;
    final note = run.after;
    if (prefs.value.trash.containsKey(note.id)) return;
    // A note made blank says nothing yet: its making is told with its first words.
    if (note.body.trim().isEmpty) {
      if (run.before == null) _unsaid.add(note.id);
      return;
    }
    _unsaid.remove(note.id);
    final change = changeOf(run.before, note.body);
    await Future.wait([
      for (final hook in setup.outgoing)
        if (inScope(hook.scope, note))
          if (eventFor(hook.events, change) case final event?) _send(hook, event, note, change.changed),
    ]);
  }

  /// Whether [note] is among [scope]'s.
  bool inScope(WebhookScope scope, Note note) {
    final value = scope.value;
    switch (scope.kind) {
      case ScopeKind.all:
        return true;
      case ScopeKind.workspace:
        return prefs.value.workspaces.notes[note.id] == value;
      case ScopeKind.notebook:
        return note.id == value || placeOf(bookIndex(_notes()), note)?.book.id == value;
      case ScopeKind.tag:
        return tagsIn(note.body).any((tag) => tag.name == value);
    }
  }

  String? _workspaceOf(String noteId) {
    final spaces = prefs.value.workspaces;
    final id = spaces.notes[noteId];
    return id == null ? null : spaces.list.where((each) => each.id == id).firstOrNull?.name;
  }

  Future<void> _send(OutgoingHook hook, WebhookEvent event, Note note, List<String> changed) async {
    final body = payloadOf(event: event, at: DateTime.fromMillisecondsSinceEpoch(_clock()), id: note.id, body: note.body, workspace: _workspaceOf(note.id), changed: changed);
    String? problem;
    for (var attempt = 0; attempt <= retryWaits.length; attempt += 1) {
      if (attempt > 0) await _wait(retryWaits[attempt - 1]);
      // Local only turned on, or the hook taken off, while it waited: not sent.
      if (_localOnly || !setup.outgoing.any((each) => each.id == hook.id)) return;
      problem = await post(hook, event, body);
      if (problem == null) break;
    }
    _setStatus(hook.id, HookStatus(at: _clock(), event: event.wire, problem: problem));
  }

  /// One POST of [body] to [hook]; answers what went wrong, or null.
  Future<String?> post(OutgoingHook hook, WebhookEvent event, String body) async {
    // The secret as the store holds it now: [hook] may have been read before the store was.
    await ready();
    final bytes = utf8.encode(body);
    final headers = {'Content-Type': 'application/json', 'User-Agent': _userAgent, 'X-Ghost-Event': event.wire};
    final secret = _secrets.peek(webhookSecretName(hook.id)) ?? hook.secret;
    if (secret != null) headers[signatureHeader] = signatureOf(secret, bytes);
    try {
      final response = await _fetcher(FetchRequest(method: 'POST', url: Uri.parse(hook.url), headers: headers, body: bytes, timeout: const Duration(seconds: 15)));
      return response.ok ? null : 'The URL answered ${response.status}.';
    } catch (_) {
      return 'The URL couldn’t be reached.';
    }
  }

  /// A made-up note's change sent to [hookId] now, once: Send a test. Answers what went wrong, or null.
  Future<String?> sendTest(String hookId) async {
    final hook = setup.outgoing.where((each) => each.id == hookId).firstOrNull;
    if (hook == null) return 'That webhook is gone.';
    if (_localOnly) return 'Nothing is sent while Local only is on.';
    final event = hook.events.contains(WebhookEvent.edited) || hook.events.isEmpty ? WebhookEvent.edited : hook.events.first;
    const words = '# A test from Ghost.md\n\n- [x] Send a test';
    final body = payloadOf(event: event, at: DateTime.fromMillisecondsSinceEpoch(_clock()), id: 'test', body: words, changed: const ['- [x] Send a test']);
    final problem = await post(hook, event, body);
    _setStatus(hook.id, HookStatus(at: _clock(), event: event.wire, problem: problem));
    return problem;
  }
}

/// The app's outgoing webhooks, started by its root (lib/root/ghost_root.dart).
WebhookSender webhooks = WebhookSender();
