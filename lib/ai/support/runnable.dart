/// The models this build of the app cannot run (GLY-2, GLY-5; docs/DESIGN.md §163). A port of
/// `src/app/core/runnable.ts`.
///
/// Matt saw "The summary didn't come" every time and an "FFI error" on every fill: the chosen model was Gemma 4 E4B,
/// whose chat template the engine's llama.cpp has no name for. The engine now renders such a template itself, but
/// that is in the binary, and a binary is a new install: until it is on the phone, the app has to cope with the one
/// it has. So a model that fails that way is remembered as one this binary cannot run, by the binary's version, and
/// the model that runs is chosen from the others (ai/available.dart `modelFor`). A new binary is asked again, since
/// it may carry the fix. With no other model on the phone the failing one is still the one tried, and its failure is
/// said in a sentence a person can act on (ai/backend.dart `generate`).
///
/// What differs: nothing but where it lives (lib/ai/support, until lib/core takes it) and that the binary's version
/// is asked of the app's [aiBackend]. [forgetBinaryVersion] is for tests, which the page got by loading the module
/// afresh.
library;

import '../../core/stored.dart';
import '../backend.dart' show binaryVersion;

const String _key = 'glyph-models-cannot-run';

/// The binary's version, once it has answered; null until then, and every record is believed meanwhile.
String? _version;
bool _asked = false;

/// The binary's version as far as it is known yet, asked the first time a record needs it and not before.
String? _knownVersion() {
  if (!_asked) {
    _asked = true;
    binaryVersion().then((answered) => _version = answered);
  }
  return _version;
}

/// Forgets the version this module was told, as a new launch does.
void forgetBinaryVersion() {
  _version = null;
  _asked = false;
}

Map<String, String> _records() => stored.read<Map<String, String>>(_key, const {}, (raw) {
      if (raw is! Map) return null;
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
      };
    });

final RegExp _template = RegExp('cannot apply the chat template', caseSensitive: false);

/// Whether a failure is a model's chat template the engine could not apply (`isTemplateFailure`).
bool isTemplateFailure(String message) => _template.hasMatch(message);

/// Whether this binary has been found unable to run [model] (`cannotRun`).
bool cannotRun(String model) {
  final said = _records()[model];
  if (said == null) return false;
  final known = _knownVersion();
  return known == null || said == known;
}

/// [model] remembered as one this binary cannot run (`markCannotRun`).
Future<void> markCannotRun(String model) async {
  final answered = await binaryVersion();
  stored.write(_key, {..._records(), model: answered});
}

/// The models that can run, of those on the phone; all of them where none can, so the failure is still said
/// (`runnable`).
List<String> runnable(Iterable<String> present) {
  final all = present.toList();
  final can = all.where((id) => !cannotRun(id)).toList();
  return can.isNotEmpty ? can : all;
}
