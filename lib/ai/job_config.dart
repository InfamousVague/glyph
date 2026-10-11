/// What the phone's own write-up of a meeting reads when the app is not there to ask (ai/backend.dart
/// `keepJobConfig`, src-tauri/src/jobs.rs `JobConfig`; docs/DESIGN.md §127 section 4): the model as the page would
/// choose it, the prompts as the page has them, and the two preferences it obeys. Nothing off the phone. A port of
/// `src/app/ai/jobConfig.ts`.
///
/// Sent at launch, when one of the three preferences it is made from changes (the model chosen, Write up,
/// Summaries), and when a model arrives or goes: the model named is what the page would pick from what is on the
/// phone, and a download changes that without any preference changing. A config that still named the model the
/// phone lacked would send a meeting asked again after the download straight back to "Needs a model" (Rust also
/// picks from what is there by the same rule, `llm::model::model_for`, as a second guard). Only on Android, where
/// the write-up runs, and only to a binary that has it; the model list is not read for a preference that has nothing
/// to do with it.
///
/// What differs:
/// - `isTauri()` is the engine being there ([aiBackend]); `isAndroid` (`core/platform.ts`) is this build's platform,
///   which a test says with Flutter's `debugDefaultTargetPlatformOverride`.
/// - `Pick<Preferences, 'formatModel' | 'writeUp' | 'summaries'>` is the whole [Preferences], of which those three
///   are read.
/// - `onPreferences` is listening to the app's [preferences]; `console.warn` is [debugPrint].
/// - `JSON.stringify(config)` is `jsonEncode` of [JobConfig.toJson], whose keys are in the page's order, so what is
///   compared with the last one sent is the page's text, byte for byte (test/ai/fixtures/job_config_web.json).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../capture/meeting.dart' show meetingGeneration;
import '../core/preferences.dart';
import '../format/prompt.dart' show notesContext, pieceContext, recordingNotesPrompt, recordingSummaryPrompt, temperature;
import 'available.dart' show modelFor, presentIds;
import 'backend.dart' show JobConfig, JobPrompts, ModelInfo, aiBackend, hasNativeGeneration, keepJobConfig, listModels, onModelsChanged;
import 'summary_text.dart' show onePassChars, pieceChars;

/// The config for `models` on this phone and `prefs` as they stand.
JobConfig jobConfigFor(List<ModelInfo> models, Preferences prefs) {
  return JobConfig(
    model: modelFor(presentIds(models), prefs.formatModel) ?? prefs.formatModel,
    prompts: const JobPrompts(summary: recordingSummaryPrompt, notes: recordingNotesPrompt, piece: pieceContext, parts: notesContext),
    onePassChars: onePassChars,
    pieceChars: pieceChars,
    temperature: temperature,
    writeUp: prefs.writeUp,
    summaries: prefs.summaries,
  );
}

/// The preferences the config is made from, as one value: a change of any other leaves it alone.
String jobConfigKey(Preferences prefs) {
  return jsonEncode([prefs.formatModel, prefs.writeUp, prefs.summaries]);
}

/// Whether this device writes meetings up itself: Android, on a binary with the write-up.
Future<bool> _writesUp() async {
  return aiBackend.available && !kIsWeb && defaultTargetPlatform == TargetPlatform.android && await hasNativeGeneration(meetingGeneration);
}

String _lastSent = '';

/// The config sent to the phone, unless it is what was sent last. Completes once it is kept.
Future<void> sendJobConfig() async {
  if (!(await _writesUp())) return;
  List<ModelInfo> models;
  try {
    models = await listModels();
  } catch (_) {
    models = const [];
  }
  final config = jobConfigFor(models, preferences.value);
  final text = jsonEncode(config.toJson());
  if (text == _lastSent) return;
  await keepJobConfig(config);
  _lastSent = text;
}

/// For tests: forget what was sent, so the next send is made.
void forgetSentJobConfig() {
  _lastSent = '';
}

/// Keeps the config current for the life of the app (shell/useHousekeeping.ts); answers the way to stop.
VoidCallback keepJobConfigCurrent() {
  void send() => unawaited(sendJobConfig().then((_) {}, onError: (Object failure) => debugPrint('[glyph] the write-up’s configuration was not kept: $failure')));
  var key = jobConfigKey(preferences.value);
  send();
  void changed() {
    final next = jobConfigKey(preferences.value);
    if (next == key) return;
    key = next;
    send();
  }

  preferences.addListener(changed);
  final unModels = onModelsChanged(send);
  return () {
    preferences.removeListener(changed);
    unModels();
  };
}
