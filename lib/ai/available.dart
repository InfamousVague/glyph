/// Whether the AI can run here, and if not, why, in one sentence a person can act on. A port of
/// `src/app/ai/available.ts`.
///
/// Matt: where there is no engine (a browser, iOS, a phone with no model), the bar and Ask show, greyed, with the
/// reason and a way to fix it where there is one. So every surface that offers the AI asks this one question and
/// draws the same answer, rather than each finding its own words for "not here". The rules, in the order they bite:
///
/// - No engine (a browser tab): the AI runs on the phone.
/// - iOS: every model command refuses there (ai_commands.rs `NOT_ON_IOS`).
/// - A binary older than `ai_generate` (native generation 10).
/// - The catalogue not read yet: waiting, not refused.
/// - No model on the phone: get one, unless Local only forbids the download.
///
/// Which model runs is decided here too: the one chosen in Settings when it is on the phone, else the biggest that
/// is no bigger than it, else the smallest there is. One model, one pass (Matt), so there is always exactly one
/// answer. A model this binary cannot run is passed over while another is on the phone (support/runnable.dart).
///
/// What differs: [Availability] is a sealed pair, [Available] and [Unavailable], with the web's fields readable on
/// either. The hook `useAvailability` is an [AvailabilityController], which reads the phone as it is made (a hook's
/// mount), follows the preferences, and whose [AvailabilityController.refresh] is the app coming back to the front.
/// `isTauri()` is the engine being there ([aiBackend]); `isIOS` is this build's platform unless the controller is
/// told otherwise.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/preferences.dart';
import 'backend.dart';
import 'support/runnable.dart';

/// The binary generation that has `ai_generate` (`AI_GENERATION`).
const int aiGeneration = 10;

/// Whether the AI can run, and with which model or why not (`Availability`).
@immutable
sealed class Availability {
  const Availability();

  /// Whether it can run: an [Available] then, an [Unavailable] otherwise.
  bool get ok;

  /// The model that runs; null when none can.
  String? get model => null;

  /// The model chosen in Settings; null when none can run.
  String? get chosen => null;

  /// Why not; null when it can.
  String? get reason => null;

  /// A model worth getting, when getting one is the fix.
  String? get get => null;

  /// The answer is not in yet (the catalogue is being read): grey, but not for long.
  bool get waiting => false;
}

/// It can (`{ ok: true, model, chosen }`).
final class Available extends Availability {
  const Available({required this.model, required this.chosen});

  @override
  bool get ok => true;

  @override
  final String model;

  @override
  final String chosen;

  @override
  bool operator ==(Object other) => other is Available && other.model == model && other.chosen == chosen;

  @override
  int get hashCode => Object.hash(model, chosen);

  @override
  String toString() => 'Available(model: $model, chosen: $chosen)';
}

/// It cannot (`{ ok: false, reason, get, waiting }`).
final class Unavailable extends Availability {
  const Unavailable({required this.reason, required this.get, required this.waiting});

  @override
  bool get ok => false;

  @override
  final String reason;

  @override
  final String? get;

  @override
  final bool waiting;

  @override
  bool operator ==(Object other) => other is Unavailable && other.reason == reason && other.get == get && other.waiting == waiting;

  @override
  int get hashCode => Object.hash(reason, get, waiting);

  @override
  String toString() => 'Unavailable(reason: $reason, get: $get, waiting: $waiting)';
}

/// JavaScript's `Number.MAX_SAFE_INTEGER`.
const int _last = 9007199254740991;

/// Bytes of a model, for choosing among what is on the phone; an unknown id sorts last.
int _sizeOf(String id) => modelSpec(id)?.bytes ?? _last;

/// [ids] by [compare], equals left in the order they came: JavaScript's sort, which Dart's does not promise to be.
List<String> _sorted(Iterable<String> ids, int Function(String a, String b) compare) {
  final out = <String>[];
  for (final id in ids) {
    var at = out.length;
    while (at > 0 && compare(out[at - 1], id) > 0) {
      at -= 1;
    }
    out.insert(at, id);
  }
  return out;
}

/// The model that runs, given what is on the phone: the chosen one, else the biggest no bigger than it, else the
/// smallest there is; null with none (`modelFor`).
String? modelFor(Iterable<String> present, String chosen) {
  // A model this binary has been found unable to run is passed over while another is there (support/runnable.dart).
  final here = runnable(<String>{...present});
  if (here.isEmpty) return null;
  if (here.contains(chosen)) return chosen;
  final ceiling = _sizeOf(chosen);
  final under = _sorted(here.where((id) => _sizeOf(id) <= ceiling), (a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
  if (under.isNotEmpty) return under.first;
  return _sorted(here, (a, b) => _sizeOf(a).compareTo(_sizeOf(b))).first;
}

/// The ids of the models the catalogue says are on the phone (`presentIds`).
List<String> presentIds(Iterable<ModelInfo> models) => [
      for (final m in models)
        if (m.present) m.id,
    ];

/// The smallest model on the phone, for a line that wants speed over care (the gist); null with none
/// (`smallestOf`).
String? smallestOf(Iterable<String> present) {
  final sorted = _sorted(<String>{...present}, (a, b) => _sizeOf(a).compareTo(_sizeOf(b)));
  return sorted.isEmpty ? null : sorted.first;
}

/// Where the app is running, as the rules ask it (`Where`).
@immutable
class Where {
  const Where({required this.tauri, required this.ios, required this.localOnly, required this.generation});

  /// Whether there is an engine at all: the web's `isTauri()`.
  final bool tauri;
  final bool ios;
  final bool localOnly;

  /// The binary's generation, or null until it has answered.
  final int? generation;

  Where copyWith({bool? tauri, bool? ios, bool? localOnly, int? generation}) =>
      Where(tauri: tauri ?? this.tauri, ios: ios ?? this.ios, localOnly: localOnly ?? this.localOnly, generation: generation ?? this.generation);
}

/// The rules, pure, so each is a test (`availability`).
Availability availability(List<ModelInfo> models, String chosen, Where where) {
  if (!where.tauri) return const Unavailable(reason: 'The AI runs on the phone. Install Ghost.md on Android to use it.', get: null, waiting: false);
  if (where.ios) return const Unavailable(reason: 'The AI is not on iOS yet.', get: null, waiting: false);
  final generation = where.generation;
  if (generation != null && generation < aiGeneration) {
    return const Unavailable(reason: 'The AI needs the newest Ghost.md. Install it from attack.fm/glyph.', get: null, waiting: false);
  }
  if (models.isEmpty) return const Unavailable(reason: 'Looking for the model.', get: null, waiting: true);
  final model = modelFor(presentIds(models), chosen);
  if (model != null) return Available(model: model, chosen: chosen);
  if (where.localOnly) {
    return const Unavailable(reason: 'No model is on the phone, and Local only is on, so none can be downloaded. Turn it off in Settings to get one.', get: null, waiting: false);
  }
  return Unavailable(reason: 'The AI needs a model on the phone. It runs here, and nothing leaves the phone.', get: chosen, waiting: false);
}

/// [availability] under a name the controller's own getter does not hide.
const Availability Function(List<ModelInfo> models, String chosen, Where where) _rules = availability;

/// The answer as a screen sees it, following the catalogue, the download, and the settings (`useAvailability`,
/// whose answer was `AvailabilityState`).
///
/// Made, it reads the phone and asks the binary its generation, as the hook did when its screen mounted; [dispose]
/// is the screen going. [ios] is whether this is an iPhone, this build's own platform when not said. [models] is the
/// catalogue's controller, one of its own when not given, which it then disposes with itself.
class AvailabilityController extends ChangeNotifier {
  AvailabilityController({bool? ios, ModelsController? models})
      : _ios = ios ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
        _models = models ?? ModelsController(),
        _ownsModels = models == null {
    _models.addListener(_changed);
    preferences.addListener(_changed);
    unawaited(_models.refresh());
    unawaited(nativeGeneration().then((value) {
      if (_disposed) return;
      _known = value;
      notifyListeners();
    }));
  }

  final bool _ios;
  final ModelsController _models;
  final bool _ownsModels;
  int? _known;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Where the app is running now.
  Where get where => Where(tauri: aiBackend.available, ios: _ios, localOnly: preferences.value.localOnly, generation: _known);

  /// Whether the AI can run, and with which model or why not.
  Availability get availability => _rules(_models.models, preferences.value.formatModel, where);

  /// What is on the phone, for a screen that names it.
  List<ModelInfo> get models => _models.models;

  /// The download in flight, if one is.
  Download? get download => _models.download;

  /// Why the last download failed, in the engine's words.
  String? get problem => _models.problem;

  /// Gets a model, in the open, with the bytes arriving in [download].
  Future<void> fetch(String id) => _models.fetch(id);

  /// Reads the phone again: the app came back to the front.
  Future<void> refresh() => _models.refresh();

  @override
  void dispose() {
    _disposed = true;
    _models.removeListener(_changed);
    preferences.removeListener(_changed);
    if (_ownsModels) _models.dispose();
    super.dispose();
  }
}

/// The model that would run now, from the catalogue as last read; for callers with no controller (`modelNow`).
String? modelNow(Iterable<ModelInfo> models) => modelFor(presentIds(models), preferences.value.formatModel);
