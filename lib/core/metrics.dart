/// Anonymous usage stats (Matt, 2026-11-04: "setup full posthog metrics across every plugin and every function in the
/// app cleanly"; docs/ANALYTICS.md). The app's one front door to them: [track], with a [MetricEvent] from the
/// allow-list below and props of the shapes that event declares, and nothing else.
///
/// WHAT IS SENT. An event's name, a few props that are each a bool, a number, or a word from a fixed vocabulary (a
/// plugin's id, a screen's name, a bucket like `5-30s`), the super properties of [MetricsContext] (version, platform,
/// form factor, Simple or Advanced, the language, which plugins are on), and a random install ID made on this device
/// the first time it sends. Never a note's title or words, a file or folder name, a query, a prompt, a URL, an email, a
/// handle, an organization's name, an error's message, or another service's ids. A prop that is not in its event's
/// schema, or whose value is not of its shape, is dropped before it is queued ([Metrics.track]), and a debug build is
/// told so by an assert; test/core/metrics_test.dart walks every event and runs a fake session through a guard.
///
/// WHO SEES IT. PostHog (the project's region is US, us.i.posthog.com), as events with no person profile
/// (`$process_person_profile: false` on every one) and no GeoIP (`$geoip_disable`), and the project discards the
/// client's IP. No session replay, no surveys, no autocapture: this client is ours, a few hundred lines over the
/// capture API, rather than posthog_flutter, whose native SDKs bring replay, autocapture and person profiles that
/// would each have to be held off, and none of which reach a web build. The install ID is never tied to the account,
/// never sent to glyph-api and never synced: it lives in this device's own storage beside the haptics switch.
///
/// THE SWITCH. Settings › Privacy › Anonymous usage stats, on by default ([usageStatsPref], this device's own). Off,
/// the queue is dropped, the ID deleted and nothing more is queued ([Metrics.reset]); on again, a fresh ID is made.
/// Local only sends nothing, and drops what it would have sent. A build with no project key (every debug build, and
/// a release built without ~/.config/mattssoftware/posthog.env) sends nothing at all.
///
/// HOW IT GOES. Queued in memory, sent as one batch (`POST <host>/batch/`) every [Metrics.sendEvery], at
/// [Metrics.batchSize] events, and as the app goes behind another ([Metrics.flush]); a batch that does not go stays
/// at the head of the queue for the next try, and the queue is kept on the device as the app is hidden so a killed app
/// still sends it next time. Each event has its own `uuid`, so a batch sent twice is counted once. Nothing waits for
/// it: [track] only appends.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../account/api.dart' show FetchRequest, Fetcher;
import 'preferences.dart' show DeviceFlag, DeviceWord;

// --- the vocabularies ----------------------------------------------------------------------------------------------

/// How long something took, as a bucket: never the milliseconds, which are a fingerprint of their own.
const List<String> durationBuckets = ['<1s', '1-5s', '5-30s', '30s-2m', '2-10m', '10-60m', '>1h'];

/// How many, as a bucket.
const List<String> countBuckets = ['0', '1', '2-5', '6-20', '21-100', '101-500', '>500'];

/// How long a cold start took to the first screen.
const List<String> startBuckets = ['<1s', '1-2s', '2-4s', '4-8s', '>8s'];

/// [durationBuckets]'s word for [took].
String durationBucket(Duration took) {
  final s = took.inMilliseconds / 1000;
  if (s < 1) return '<1s';
  if (s < 5) return '1-5s';
  if (s < 30) return '5-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  if (s < 3600) return '10-60m';
  return '>1h';
}

/// [countBuckets]'s word for [n].
String countBucket(int n) {
  if (n <= 0) return '0';
  if (n == 1) return '1';
  if (n <= 5) return '2-5';
  if (n <= 20) return '6-20';
  if (n <= 100) return '21-100';
  if (n <= 500) return '101-500';
  return '>500';
}

/// [startBuckets]'s word for [took].
String startBucket(Duration took) {
  final s = took.inMilliseconds / 1000;
  if (s < 1) return '<1s';
  if (s < 2) return '1-2s';
  if (s < 4) return '2-4s';
  if (s < 8) return '4-8s';
  return '>8s';
}

/// The screens by name (lib/shell/screen.dart `Screen.name`).
const Set<String> screenNames = {'list', 'notes', 'note', 'capture', 'meeting', 'academy', 'organization', 'collection', 'market', 'tickets'};

/// The walkthrough's pages (lib/guide/pages.dart `GuidePage`).
const Set<String> onboardingSteps = {'welcome', 'speak', 'meetings', 'ai', 'sync', 'market', 'mode', 'model', 'start'};

/// The kinds of AI that can answer (lib/assistant): a provider's kind, never its model's name or a prompt.
const Set<String> aiProviders = {'local', 'claude', 'openai', 'gemini', 'custom', 'aster', 'lovart', 'elevenlabs', 'none'};

/// What a job is (lib/core/background_jobs.dart `JobKind`).
const Set<String> jobKinds = {'sync', 'ai', 'images', 'audio', 'meetings', 'downloads'};

/// A failed job's one fix (`JobFixKind`).
const Set<String> jobFixes = {'topUp', 'signIn', 'retry', 'open', 'none'};

/// Where an uncaught error came from (lib/diag/error_log.dart).
const Set<String> errorSources = {'framework', 'platform'};

/// The platforms, and the form factors.
const Set<String> platforms = {'android', 'ios', 'macos', 'windows', 'linux', 'web', 'fuchsia'};
const Set<String> formFactors = {'phone', 'fold', 'tablet', 'desktop'};

/// The settings [MetricEvent.settingChanged] may name, and the words each may say. Only choices from a fixed list or
/// a switch: never a name, a time typed in, a list of the person's own. The words come from lib/core/preferences.dart,
/// copied here so the metrics read without the preferences' type, and held the same by test/core/metrics_test.dart.
const Map<String, Set<String>?> settingWords = {
  'theme': {'system', 'light', 'dark', 'dawn', 'boreal', 'ember', 'sakura', 'meadow', 'tide', 'dusk'},
  'homeLayout': {'spotlight', 'cards', 'timeline', 'list'},
  'experience': {'simple', 'advanced'},
  'topBar': {'classic', 'ledger', 'masthead', 'islands'},
  'density': {'extra-compact', 'compact', 'comfortable', 'spacious', 'more-space'},
  'textSize': {'large', 'larger', 'largest'},
  'typeface': {'maple', 'fira', 'jetbrains', 'inter', 'noto', 'plex', 'atkinson', 'lora'},
  'noteFace': {'maple', 'fira', 'jetbrains', 'inter', 'noto', 'plex', 'atkinson', 'lora'},
  'iconPack': {'lucide', 'phosphor', 'tabler', 'material', 'remix'},
  'iconStyle': {'outline', 'solid', 'filled'},
  'accent': {'ink', 'graphite', 'red', 'amber', 'green', 'teal', 'purple'},
  'rounding': {'square', 'soft', 'round', 'rounder'},
  'motionSpeed': {'relaxed', 'normal', 'brisk'},
  'summaries': {'meetings', 'long', 'off'},
  'writeUp': {'charging', 'now'},
  'code': {'pastel', 'ink', 'github', 'solarized', 'one-dark', 'dracula', 'nord'},
  'sounds': {'all', 'notifications', 'off'},
  'noteView': {'mixed', 'formatted'},
  // Switches: null words, the value is the bool.
  'localOnly': null,
  'linkPreviews': null,
  'improve': null,
  'quietStop': null,
  'syncMeetingRecordings': null,
  'meetingSound': null,
  'effects': null,
  'calm': null,
  'menuBarAlways': null,
  'focusMode': null,
  'canvasSnap': null,
  'openStreetMap': null,
  'tagNewNotes': null,
  'lookUpBlanks': null,
  'autoFill': null,
  'usageStats': null,
};

// --- the props' shapes ---------------------------------------------------------------------------------------------

/// What a prop may hold.
@immutable
sealed class MetricProp {
  const MetricProp();

  /// Whether [value] is of this shape.
  bool allows(Object value);
}

/// `true` or `false`.
class FlagProp extends MetricProp {
  const FlagProp();
  @override
  bool allows(Object value) => value is bool;
}

/// A finite number, not a string.
class NumberProp extends MetricProp {
  const NumberProp();
  @override
  bool allows(Object value) => value is num && value.isFinite;
}

/// One of a fixed set of words.
class WordProp extends MetricProp {
  const WordProp(this.words);
  final Set<String> words;
  @override
  bool allows(Object value) => value is String && words.contains(value);
}

/// A short code written in the app's own source: a job's kind (`lovart-banners`), a settings pane's id, a plugin's
/// action. Lowercase letters, digits, `-` and `_`, at most 32: it cannot hold a sentence, a capital or a space.
class CodeProp extends MetricProp {
  const CodeProp();
  static final RegExp shape = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');
  @override
  bool allows(Object value) => value is String && shape.hasMatch(value);
}

/// A choice's id from a list in the app (a Lovart style, an image model's tool id): letters, digits, `.`, `-`, `_`, at
/// most 48, no space.
class ChoiceProp extends MetricProp {
  const ChoiceProp();
  static final RegExp shape = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,47}$');
  @override
  bool allows(Object value) => value is String && shape.hasMatch(value);
}

/// A plugin's id, as the registry names it ([Metrics.pluginIds]), or the code shape before there is a registry.
class PluginProp extends MetricProp {
  const PluginProp();
  @override
  bool allows(Object value) => value is String && CodeProp.shape.hasMatch(value) && (Metrics.pluginIds.isEmpty || Metrics.pluginIds.contains(value));
}

/// A Dart type's name (`SocketException`, `_TypeError`), never its message.
class TypeNameProp extends MetricProp {
  const TypeNameProp();
  static final RegExp shape = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]{0,47}$');
  @override
  bool allows(Object value) => value is String && shape.hasMatch(value);
}

const _flag = FlagProp();
const _number = NumberProp();
const _code = CodeProp();
const _choice = ChoiceProp();
const _plugin = PluginProp();
const _durations = WordProp({...durationBuckets});
const _counts = WordProp({...countBuckets});

// --- the allow-list ------------------------------------------------------------------------------------------------

/// Every event the app may send, and the props each may carry. Adding one is adding it here, with docs/ANALYTICS.md.
enum MetricEvent {
  // Lifecycle: the DAU signal.
  appOpened('app_opened', {'cold': _flag, 'start': WordProp({...startBuckets})}),

  // Screens, by name only.
  screenViewed('screen_viewed', {'screen': WordProp(screenNames)}),
  settingsOpened('settings_opened', {'pane': _code}),
  changelogViewed('changelog_viewed', {}),

  // Notes, never their ids.
  noteCreated('note_created', {'source': WordProp({'editor', 'capture'})}),
  noteOpened('note_opened', {}),
  noteEdited('note_edited', {}),
  noteTrashed('note_trashed', {}),
  noteRestored('note_restored', {}),
  noteDeleted('note_deleted', {}),
  folderCreated('folder_created', {}),
  folderDeleted('folder_deleted', {}),
  workspaceCreated('workspace_created', {}),
  workspaceDeleted('workspace_deleted', {}),
  searchUsed('search_used', {'results': _counts}),

  // Plugins.
  pluginEnabled('plugin_enabled', {'plugin': _plugin}),
  pluginDisabled('plugin_disabled', {'plugin': _plugin}),
  pluginActive('plugin_active', {'plugin': _plugin}),
  pluginSetupStarted('plugin_setup_started', {'plugin': _plugin}),
  pluginSetupFinished('plugin_setup_finished', {'plugin': _plugin}),
  pluginDisconnected('plugin_disconnected', {'plugin': _plugin}),
  pluginAction('plugin_action', {'plugin': _plugin, 'action': _code, 'choice': _choice, 'count': _counts, 'ok': _flag}),

  // Background jobs, every one through lib/core/background_jobs.dart.
  jobStarted('job_started', {'job': _code, 'kind': WordProp(jobKinds), 'plugin': _plugin, 'person': _flag}),
  jobFinished('job_finished', {'job': _code, 'kind': WordProp(jobKinds), 'plugin': _plugin, 'took': _durations}),
  jobFailed('job_failed', {'job': _code, 'kind': WordProp(jobKinds), 'plugin': _plugin, 'took': _durations, 'fix': WordProp(jobFixes)}),
  jobStopped('job_stopped', {'job': _code, 'kind': WordProp(jobKinds), 'plugin': _plugin, 'took': _durations}),

  // Voice.
  recordingStarted('recording_started', {'mode': WordProp({'note', 'meeting'})}),
  recordingFinished('recording_finished', {'mode': WordProp({'note', 'meeting'}), 'took': _durations}),

  // AI.
  aiUsed('ai_used', {'feature': _code, 'provider': WordProp(aiProviders)}),

  // Account, organizations, sharing: never who.
  signedUp('signed_up', {}),
  signedIn('signed_in', {}),
  signedOut('signed_out', {}),
  orgCreated('org_created', {}),
  inviteSent('invite_sent', {'way': WordProp({'email', 'link', 'handle'})}),
  orgJoined('org_joined', {}),
  noteShared('note_shared', {}),

  // Sync.
  syncFailed('sync_failed', {'reason': _code}),

  // Updates.
  updateInstalled('update_installed', {}),

  // Settings: the setting's name, and its new value where it is a switch or a word from its list.
  settingChanged('setting_changed', {'setting': WordProp({...settingWordsKeys}), 'value': _choice, 'on': _flag}),

  // The walkthrough.
  onboardingStarted('onboarding_started', {}),
  onboardingStep('onboarding_step', {'step': WordProp(onboardingSteps)}),
  onboardingFinished('onboarding_finished', {'step': WordProp(onboardingSteps)}),

  // Errors nobody caught, by type only.
  errorCaught('error_caught', {'type': TypeNameProp(), 'source': WordProp(errorSources)});

  const MetricEvent(this.wire, this.props);

  /// The name PostHog sees.
  final String wire;

  /// The props it may carry, by name, and their shapes. Every prop is optional.
  final Map<String, MetricProp> props;
}

/// [settingWords]'s keys, as a const set the enum can hold.
const Set<String> settingWordsKeys = {
  'theme', 'homeLayout', 'experience', 'topBar', 'density', 'textSize', 'typeface', 'noteFace', 'iconPack', 'iconStyle', 'accent', 'rounding', 'motionSpeed', //
  'summaries', 'writeUp', 'code', 'sounds', 'noteView', 'localOnly', 'linkPreviews', 'improve', 'quietStop', 'syncMeetingRecordings', 'meetingSound', //
  'effects', 'calm', 'menuBarAlways', 'focusMode', 'canvasSnap', 'openStreetMap', 'tagNewNotes', 'lookUpBlanks', 'autoFill', 'usageStats',
};

/// The super properties' shapes: what [MetricsContext] answers is checked against these, as an event's props are.
const Map<String, MetricProp> superProps = {
  'app_version': ChoiceProp(),
  'app_build': ChoiceProp(),
  'platform': WordProp(platforms),
  'form_factor': WordProp(formFactors),
  'simple': FlagProp(),
  'lang': _lang,
  'plugins_on': _pluginList,
  'plugin_count': _number,
};

const _lang = _LangProp();
const _pluginList = _PluginListProp();

/// A language's two or three letters (`en`, `de`), never a region.
class _LangProp extends MetricProp {
  const _LangProp();
  static final RegExp shape = RegExp(r'^[a-z]{2,3}$');
  @override
  bool allows(Object value) => value is String && shape.hasMatch(value);
}

/// The plugins on, as `,a,b,c,` (sorted, so a filter "contains ,notion," finds one).
class _PluginListProp extends MetricProp {
  const _PluginListProp();
  @override
  bool allows(Object value) {
    if (value is! String || value.length > 2000) return false;
    if (value == ',') return true;
    if (!value.startsWith(',') || !value.endsWith(',')) return false;
    return value.substring(1, value.length - 1).split(',').every((id) => const PluginProp().allows(id));
  }
}

// --- where it is kept, and how it goes -------------------------------------------------------------------------------

/// What the metrics keep on this device: the switch, the install ID and the unsent queue.
abstract interface class MetricsKeep {
  bool get on;
  set on(bool value);

  /// The install ID, or '' for none.
  String get installId;
  set installId(String value);

  /// The queue as JSON, or '' for none.
  String get queue;
  set queue(String value);

  /// Told when [on] moves.
  ValueListenable<bool> get switched;
}

/// Settings › Privacy's switch, this device's own and never synced: on by default.
final DeviceFlag usageStatsPref = DeviceFlag('glyph-usage-stats', fallback: () => true);
final DeviceWord _installIdWord = DeviceWord('glyph-metrics-id', fallback: '');
final DeviceWord _queueWord = DeviceWord('glyph-metrics-queue', fallback: '');

/// The device's own storage, beside the haptics switch (lib/core/preferences.dart [DeviceFlag]).
class DeviceMetricsKeep implements MetricsKeep {
  const DeviceMetricsKeep();
  @override
  bool get on => usageStatsPref.value;
  @override
  set on(bool value) => usageStatsPref.set(value);
  @override
  String get installId => _installIdWord.value;
  @override
  set installId(String value) => _installIdWord.set(value);
  @override
  String get queue => _queueWord.value;
  @override
  set queue(String value) => _queueWord.set(value);
  @override
  ValueListenable<bool> get switched => usageStatsPref;
}

/// A test's.
class MemoryMetricsKeep implements MetricsKeep {
  MemoryMetricsKeep({bool on = true, this.installId = '', this.queue = ''}) : _on = ValueNotifier(on);
  final ValueNotifier<bool> _on;
  @override
  bool get on => _on.value;
  @override
  set on(bool value) => _on.value = value;
  @override
  String installId;
  @override
  String queue;
  @override
  ValueListenable<bool> get switched => _on;
}

/// Sends one batch's body to [url]; answers whether it was taken. Never throws.
typedef MetricsSend = Future<bool> Function(Uri url, Uint8List body);

/// A [MetricsSend] over the app's own [Fetcher] (lib/account/api.dart `ioFetcher`).
MetricsSend fetcherSend(Fetcher fetch) => (url, body) async {
      try {
        final answer = await fetch(FetchRequest(method: 'POST', url: url, headers: const {'Content-Type': 'application/json'}, body: body, timeout: const Duration(seconds: 20)));
        return answer.status >= 200 && answer.status < 300;
      } catch (_) {
        return false;
      }
    };

/// The super properties, asked as each event is queued.
typedef MetricsContext = Map<String, Object> Function();

/// The project key and host a release is built with (tool/posthog-defines.sh): none, and nothing is ever sent.
const String posthogKeyDefine = String.fromEnvironment('POSTHOG_KEY');
const String posthogHostDefine = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://us.i.posthog.com');

// --- the client ------------------------------------------------------------------------------------------------------

/// One event, as queued.
typedef QueuedMetric = Map<String, Object?>;

class Metrics {
  Metrics({
    this.key = '',
    String host = posthogHostDefine,
    MetricsKeep? keep,
    MetricsSend? send,
    bool Function()? localOnly,
    MetricsContext? context,
    DateTime Function()? clock,
    Random? random,
    this.sendEvery = const Duration(seconds: 30),
    this.batchSize = 20,
    this.most = 500,
    this.perSession = 200,
    bool early = false,
  })  : _early = early ? [] : null,
        host = host.endsWith('/') ? host.substring(0, host.length - 1) : host,
        keep = keep ?? MemoryMetricsKeep(),
        _send = send,
        _localOnly = localOnly ?? _never,
        _context = context,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure() {
    this.keep.switched.addListener(_switched);
    _restore();
  }

  /// A client that sends nothing: no key. The app's until the root starts the real one ([useMetrics]), and what is
  /// tracked before then (the walkthrough opening as the root is made, say) is held, at most [_mostEarly], and handed
  /// to that one, which keeps it only if it sends at all.
  factory Metrics.off() => Metrics(early: true);

  static bool _never() => false;

  /// The ids of the plugins in this build, for [PluginProp]: set by the root once the registry is up.
  static Set<String> pluginIds = const {};

  /// PostHog's project key (`phc_…`, public; it ships in the app). Empty: nothing is queued or sent.
  final String key;
  final String host;
  final MetricsKeep keep;
  final MetricsSend? _send;
  final bool Function() _localOnly;
  MetricsContext? _context;
  final DateTime Function() _clock;
  final Random _random;

  /// How often a non-empty queue is sent; at [batchSize] it is sent at once.
  final Duration sendEvery;
  final int batchSize;

  /// The queue's cap: past it the oldest go.
  final int most;

  /// How many of one event (of one plugin's action, of one job) a run may queue: a loop never floods.
  final int perSession;

  final List<QueuedMetric> _queue = [];

  /// What [Metrics.off] holds for the real client.
  final List<(MetricEvent, Map<String, Object>)>? _early;
  static const int _mostEarly = 50;
  /// How many of each event (and plugin, action or job, where it has one) this run queued.
  final Map<String, int> _counted = {};
  Timer? _timer;
  bool _sending = false;

  /// What was queued and not yet sent: for a test, and Settings' word on it.
  List<QueuedMetric> get queued => List.unmodifiable(_queue);

  /// Whether events are queued at all now.
  bool get sending => key.isNotEmpty && _send != null && keep.on && !_localOnly();

  /// The super properties from now on.
  set context(MetricsContext? context) => _context = context;

  /// Queues [event] with [props], each checked against its schema; a prop that is not is left out (and a debug build
  /// asserts). Does nothing while [sending] is false. Never waits, never throws.
  void track(MetricEvent event, [Map<String, Object> props = const {}]) {
    try {
      final early = _early;
      if (early != null) {
        if (early.length < _mostEarly) early.add((event, Map.of(props)));
        return;
      }
      if (!sending) {
        if (_localOnly() && _queue.isNotEmpty) _drop();
        return;
      }
      final seat = '${event.wire}|${props['plugin'] ?? ''}|${props['action'] ?? ''}|${props['job'] ?? ''}';
      final n = (_counted[seat] ?? 0) + 1;
      if (n > perSession) return;
      _counted[seat] = n;
      final checked = checkProps(event, props);
      final id = _installId();
      final context = <String, Object>{};
      final asked = _context?.call() ?? const <String, Object>{};
      for (final MapEntry(:key, :value) in asked.entries) {
        final shape = superProps[key];
        if (shape != null && shape.allows(value)) context[key] = value;
      }
      _queue.add({
        'event': event.wire,
        'uuid': _uuid(),
        'timestamp': _clock().toUtc().toIso8601String(),
        'properties': {
          ...context,
          ...checked,
          'distinct_id': id,
          r'$process_person_profile': false,
          r'$geoip_disable': true,
          r'$ip': null,
          r'$lib': 'ghost-md',
        },
      });
      while (_queue.length > most) {
        _queue.removeAt(0);
      }
      if (_queue.length >= batchSize) {
        unawaited(flush());
      } else {
        _timer ??= Timer(sendEvery, () {
          _timer = null;
          unawaited(flush());
        });
      }
    } catch (failure) {
      // The stats are never the app's trouble.
      assert(() {
        debugPrint('[metrics] ${event.wire} was not queued: $failure');
        return true;
      }());
    }
  }

  /// [props] as [event] allows them: the ones of its schema and shape. Public for the tests.
  static Map<String, Object> checkProps(MetricEvent event, Map<String, Object> props) {
    final kept = <String, Object>{};
    for (final MapEntry(:key, :value) in props.entries) {
      final shape = event.props[key];
      if (shape != null && shape.allows(value)) {
        kept[key] = value;
      } else {
        assert(false, '[metrics] ${event.wire} has no prop “$key” of that shape: it was left out');
      }
    }
    return kept;
  }

  /// Sends what is queued, a batch at a time; a batch that does not go stays for the next try. Never throws.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final send = _send;
    if (_sending || send == null || _queue.isEmpty) return;
    if (!sending) {
      _drop();
      return;
    }
    _sending = true;
    try {
      while (_queue.isNotEmpty && sending) {
        final batch = _queue.take(100).toList();
        final body = Uint8List.fromList(utf8.encode(jsonEncode({'api_key': key, 'batch': batch, 'historical_migration': false})));
        final taken = await send(Uri.parse('$host/batch/'), body);
        if (!taken) break;
        // What was queued meanwhile stays behind it.
        _queue.removeRange(0, min(batch.length, _queue.length));
      }
    } finally {
      _sending = false;
    }
    _keepQueue();
  }

  /// As the app goes behind another: what is queued is kept on the device, and a send begun.
  Future<void> hidden() async {
    _keepQueue();
    await flush();
  }

  /// Settings' switch off, or a test: the queue dropped, the ID deleted, the counts forgotten. On again, the next
  /// event makes a new ID.
  void reset() {
    _drop();
    keep.installId = '';
    _counted.clear();
  }

  void _drop() {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    keep.queue = '';
  }

  void _switched() {
    if (!keep.on) reset();
  }

  void _keepQueue() {
    try {
      keep.queue = _queue.isEmpty || !sending ? '' : jsonEncode(_queue.length > most ? _queue.sublist(_queue.length - most) : _queue);
    } catch (_) {}
  }

  /// What a run before this one left unsent.
  void _restore() {
    final text = keep.queue;
    if (text.isEmpty) return;
    try {
      final read = jsonDecode(text);
      if (read is List) {
        for (final each in read) {
          if (each is Map<String, Object?> && each['event'] is String && MetricEvent.values.any((e) => e.wire == each['event'])) _queue.add(each);
        }
      }
    } catch (_) {}
    keep.queue = '';
  }

  String _installId() {
    final had = keep.installId;
    if (had.isNotEmpty) return had;
    final made = _uuid();
    keep.installId = made;
    return made;
  }

  /// A version 4 UUID from [_random].
  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void dispose() {
    keep.switched.removeListener(_switched);
    _timer?.cancel();
    _timer = null;
  }
}

Metrics _metrics = Metrics.off();

/// The app's client: [Metrics.off] until lib/root/metrics_wiring.dart starts the real one.
Metrics get metrics => _metrics;

/// Makes [next] the app's.
void useMetrics(Metrics next) {
  if (identical(next, _metrics)) return;
  final early = _metrics._early;
  _metrics.dispose();
  _metrics = next;
  if (early != null && next._early == null) {
    for (final (event, props) in early) {
      next.track(event, props);
    }
  }
}

/// `metrics.track`: the one call the rest of the app makes.
void track(MetricEvent event, [Map<String, Object> props = const {}]) => _metrics.track(event, props);

// --- the helpers a choke point uses ----------------------------------------------------------------------------------

final Set<int> _editedHere = {};

/// A note edited: once per note per run, and the note's id never leaves this set (a hash of it, in memory).
void trackNoteEdited(String noteId) {
  if (_editedHere.add(noteId.hashCode)) track(MetricEvent.noteEdited);
}

/// A job's code from its id: what comes before its first `:` (`summary:<note>` is `summary`), only where it is a
/// code at all.
String? jobCode(String id) {
  final head = id.split(':').first;
  return CodeProp.shape.hasMatch(head) ? head : null;
}

/// An error's type, without its type arguments (`List<String>` is `List`), only where it is a name at all.
String? errorType(Object error) {
  final name = error.runtimeType.toString().split('<').first;
  return TypeNameProp.shape.hasMatch(name) ? name : null;
}

final Set<String> _errorsHere = {};

/// An uncaught error, counted once per type per run.
void trackError(Object error, String source) {
  final type = errorType(error) ?? 'Unknown';
  if (_errorsHere.length > 50 || !_errorsHere.add('$source/$type')) return;
  track(MetricEvent.errorCaught, {'type': type, 'source': source});
}

/// A plugin's action, the one shape every plugin's own events take: [action] is a code from its source (`banner_made`,
/// `import_started`), [choice] a choice's id from a list in the app, [count] a count to bucket.
void trackPlugin(String plugin, String action, {String? choice, int? count, bool? ok}) => track(MetricEvent.pluginAction, {
      'plugin': plugin,
      'action': action,
      'choice': ?choice,
      if (count != null) 'count': countBucket(count),
      'ok': ?ok,
    });

/// For a test: the run's own counts forgotten.
@visibleForTesting
void debugForgetMetricsRun() {
  _editedHere.clear();
  _errorsHere.clear();
}

Timer? _searchSettles;

/// A search's results counted once its words stop changing (two seconds), as a bucket: never the query.
void trackSearchSoon(int results) {
  // No timer at all where nothing would be sent (a test, a build with no key, the switch off).
  if (!_metrics.sending) return;
  _searchSettles?.cancel();
  _searchSettles = Timer(const Duration(seconds: 2), () {
    _searchSettles = null;
    track(MetricEvent.searchUsed, {'results': countBucket(results)});
  });
}
