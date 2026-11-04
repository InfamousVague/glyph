/// The anonymous usage stats put on the app (lib/core/metrics.dart, docs/ANALYTICS.md): the real client made once
/// the root is up, its super properties, `app_opened` with how long the cold start took, a send as the app goes
/// behind another, each plugin that is on counted once a day, and every switch or choice of the settings that is
/// one of a fixed list. Everything else is told from its own choke point: the registry, the activity, the note
/// store, the shell's screens, the error log.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../account/api.dart' show Fetcher, ioFetcher;
import '../core/metrics.dart';
import '../core/preferences.dart';
import '../core/updates.dart' show ghostBuild;
import '../plugins/registry.dart';
import '../settings/panes/about_pane.dart' show ghostVersion;

/// When `main` began, for the cold start's bucket.
final Stopwatch launchClock = Stopwatch();

/// Starts the clock: the first thing `main` does.
void markLaunchBegan() {
  if (!launchClock.isRunning) launchClock.start();
}

/// The platform's word.
String platformWord() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

/// The form factor from the platform and the window: a computer is a desktop; a phone's window narrower than 600 is a
/// phone; wider and nearly square on Android is a Fold's inner screen; anything else a tablet.
String formFactor({required String platform, required double width, required double height}) {
  if (platform == 'macos' || platform == 'windows' || platform == 'linux' || platform == 'web') return 'desktop';
  final short = width < height ? width : height;
  final long = width < height ? height : width;
  if (short < 600) return 'phone';
  if (platform == 'android' && short > 0 && long / short < 1.35) return 'fold';
  return 'tablet';
}

/// The super properties now: never anything of the person's.
Map<String, Object> metricsContext({Registry? registry, Preferences? prefs}) {
  final platform = platformWord();
  var width = 0.0, height = 0.0;
  final views = PlatformDispatcher.instance.views;
  if (views.isNotEmpty) {
    final view = views.first;
    final ratio = view.devicePixelRatio == 0 ? 1 : view.devicePixelRatio;
    width = view.physicalSize.width / ratio;
    height = view.physicalSize.height / ratio;
  }
  final on = [for (final p in (registry ?? plugins).enabled()) p.manifest.id]..sort();
  return {
    'app_version': ghostVersion,
    if (ghostBuild.isNotEmpty) 'app_build': ghostBuild,
    'platform': platform,
    'form_factor': formFactor(platform: platform, width: width, height: height),
    'simple': (prefs ?? preferences.value).simple,
    'lang': PlatformDispatcher.instance.locale.languageCode.toLowerCase(),
    'plugins_on': ',${on.join(',')},',
    'plugin_count': on.length,
  };
}

/// What [startMetrics] put on, for [stopMetrics].
class MetricsWired {
  MetricsWired._(this._life, this._prefs, this._was);
  final AppLifecycleListener? _life;
  final PreferencesStore _prefs;
  Preferences _was;
  bool _usage = usageStatsPref.value;
  final Map<String, String> _activeOn = {};

  void _prefsMoved() {
    final now = _prefs.value;
    final before = _was.toJson(), after = now.toJson();
    _was = now;
    for (final MapEntry(key: setting, value: words) in settingWords.entries) {
      if (!after.containsKey(setting) && !before.containsKey(setting)) continue;
      // A switch that is off by default is left out of the stored shape while off ('calm', 'menuBarAlways').
      final value = after[setting] ?? (words == null ? false : null);
      if (value == (before[setting] ?? (words == null ? false : null))) continue;
      if (words == null && value is bool) {
        track(MetricEvent.settingChanged, {'setting': setting, 'on': value});
      } else if (words != null && value is String && words.contains(value)) {
        track(MetricEvent.settingChanged, {'setting': setting, 'value': value});
      }
    }
  }

  void _usageMoved() {
    final on = usageStatsPref.value;
    if (on == _usage) return;
    _usage = on;
    // Turned on again: the one event that says so, under the fresh ID. Off, nothing is sent at all.
    if (on) track(MetricEvent.settingChanged, {'setting': 'usageStats', 'on': true});
  }

  /// Each plugin that is on, once a calendar day: "how many installs use Notion".
  void countActive([DateTime? at]) {
    final day = (at ?? DateTime.now()).toUtc().toIso8601String().substring(0, 10);
    for (final plugin in plugins.enabled()) {
      final id = plugin.manifest.id;
      if (_activeOn[id] == day) continue;
      _activeOn[id] = day;
      track(MetricEvent.pluginActive, {'plugin': id});
    }
  }
}

MetricsWired? _wired;

/// The version the last launch ran, for `update_installed`: this device's own, never sent but as that event.
final DeviceWord lastVersionRun = DeviceWord('glyph-metrics-version', fallback: '');

/// Makes the app's client and puts it on: once, from the root's `initState`. [fetch] is the network (the app's own
/// `ioFetcher`); [key] the project key a release is built with, none in any other build, which then sends nothing.
MetricsWired startMetrics({String key = posthogKeyDefine, String host = posthogHostDefine, Fetcher? fetch, PreferencesStore? prefs, bool lifecycle = true}) {
  final store = prefs ?? preferences;
  final wired = _wired;
  if (wired != null) return wired;
  Metrics.pluginIds = {for (final p in plugins.all()) p.manifest.id};
  useMetrics(Metrics(
    key: key,
    host: host,
    keep: const DeviceMetricsKeep(),
    send: key.isEmpty ? null : fetcherSend(fetch ?? ioFetcher()),
    localOnly: () => store.value.localOnly,
    context: () => metricsContext(prefs: store.value),
  ));
  final life = lifecycle
      ? AppLifecycleListener(
          onHide: () => unawaited(metrics.hidden()),
          onResume: () {
            track(MetricEvent.appOpened, {'cold': false});
            _wired?.countActive();
          },
        )
      : null;
  final made = _wired = MetricsWired._(life, store, store.value);
  store.addListener(made._prefsMoved);
  usageStatsPref.addListener(made._usageMoved);
  final took = launchClock.isRunning ? launchClock.elapsed : null;
  track(MetricEvent.appOpened, {'cold': true, if (took != null) 'start': startBucket(took)});
  // An update installed: this launch's version is not the one the last launch ran (kept on this device alone).
  final last = lastVersionRun.value;
  if (last.isNotEmpty && last != ghostVersion) track(MetricEvent.updateInstalled);
  if (last != ghostVersion) lastVersionRun.set(ghostVersion);
  made.countActive();
  return made;
}

/// Takes it off again: for a test.
@visibleForTesting
void stopMetrics() {
  final wired = _wired;
  if (wired == null) return;
  wired._life?.dispose();
  wired._prefs.removeListener(wired._prefsMoved);
  usageStatsPref.removeListener(wired._usageMoved);
  _wired = null;
  useMetrics(Metrics.off());
}
