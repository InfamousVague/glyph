/// What happened to each finished recording, step by step, kept on the phone. A port of
/// `src/app/capture/voiceLog.ts` (the Tauri app's voice work that followed 1.6).
///
/// The transcript Whisper wrote, which step decided (the rules, the model's sort, its plan), the model's raw
/// answers, what the checks dropped, and what the person chose on the card. Settings › Recording › Voice log shows
/// it and copies it, so a recording that went wrong can be read back exactly instead of remembered.
///
/// Local only, under `glyph-voice-log` in the device's memory (core/stored.dart, so a reset clears it with every
/// other `glyph-` key), the last [_keep] recordings. Nothing is sent anywhere.
///
/// What differs: the page's `useVoiceLog` hook is [useVoiceLog], a [ValueListenable] of the log. A step's time is
/// read from [DateTime.now] unless a clock is given, so a test can hold it still. [voiceLogText] writes a time as
/// `YYYY-MM-DD HH:MM:SS` in the phone's zone, where the page used the locale's `toLocaleString()`.
library;

import 'package:flutter/foundation.dart';

import '../ai/support/watched.dart';
import '../core/stored.dart';

/// One recording in the log (`VoiceLogEntry`).
class VoiceLogEntry {
  VoiceLogEntry({required this.at, required this.transcript, List<String>? steps, this.outcome = 'deciding'}) : steps = steps ?? [];

  /// A kept entry, or null for something that is not one (another build's, a half-written store's).
  static VoiceLogEntry? fromJson(Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    final steps = raw['steps'];
    return VoiceLogEntry(
      at: (raw['at'] as num).toInt(),
      transcript: raw['transcript'] is String ? raw['transcript'] as String : '',
      steps: steps is List ? [for (final line in steps) if (line is String) line] : [],
      outcome: raw['outcome'] is String ? raw['outcome'] as String : '',
    );
  }

  /// When Done was pressed; also the entry's id.
  final int at;
  final String transcript;
  final List<String> steps;

  /// The decision, then what the person did with it.
  String outcome;

  Map<String, Object?> toJson() => {'at': at, 'transcript': transcript, 'steps': steps, 'outcome': outcome};

  VoiceLogEntry withOutcome(String next) => VoiceLogEntry(at: at, transcript: transcript, steps: steps, outcome: next);
}

const String _key = 'glyph-voice-log';
const int _keep = 40;

final ValueNotifier<int> _written = ValueNotifier<int>(0);

List<VoiceLogEntry>? _cache;
Stored? _cacheOf;

List<VoiceLogEntry> _read() {
  // The memory the cache was read from: a test that puts another in its place (core/stored.dart `useStored`) starts
  // from what that one holds.
  if (_cache != null && identical(_cacheOf, stored)) return _cache!;
  _cacheOf = stored;
  _cache = stored.read<List<VoiceLogEntry>>(_key, <VoiceLogEntry>[], (raw) {
    if (raw is! List) return null;
    return [for (final one in raw) ?VoiceLogEntry.fromJson(one)];
  });
  return _cache!;
}

void _write(List<VoiceLogEntry> entries) {
  _cacheOf = stored;
  _cache = entries.take(_keep).toList();
  // No storage: the log lasts as long as the app does (core/stored.dart: a refused write is silence).
  stored.write(_key, [for (final entry in _cache!) entry.toJson()]);
  _written.value += 1;
}

/// The step writer of one recording's entry (`VoiceTrace`).
abstract class VoiceTrace {
  /// The entry's id: when Done was pressed.
  int get at;

  /// One line of what happened.
  void step(String line);

  /// The decision; written to the log.
  void decide(String outcome);
}

class _Trace implements VoiceTrace {
  _Trace(this.at, this._entry, this._clock) : _began = _clock();

  @override
  final int at;
  final VoiceLogEntry _entry;
  final int Function() _clock;
  final int _began;

  void _save() => _write([_entry, ..._read().where((other) => other.at != _entry.at)]);

  @override
  void step(String line) {
    final seconds = ((_clock() - _began) / 1000).toStringAsFixed(1);
    _entry.steps.add('+${seconds}s ${line.length > 1500 ? line.substring(0, 1500) : line}');
  }

  @override
  void decide(String outcome) {
    _entry.outcome = outcome;
    _save();
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;

/// A new entry for the recording just finished (`traceRecording`). Written at once: a recording whose model step
/// never comes back stays in the log as "deciding" instead of leaving no trace.
VoiceTrace traceRecording(String transcript, {int? now, int Function()? clock}) {
  final entry = VoiceLogEntry(at: now ?? _now(), transcript: transcript.length > 4000 ? transcript.substring(0, 4000) : transcript);
  final trace = _Trace(entry.at, entry, clock ?? _now);
  trace._save();
  return trace;
}

/// What the person did with the card: confirmed, cancelled, kept as a note (`settleRecording`).
void settleRecording(int at, String what) {
  final entries = _read();
  if (!entries.any((other) => other.at == at)) return;
  _write([for (final other in entries) other.at == at ? other.withOutcome('${other.outcome} → $what') : other]);
}

/// The log, newest first (`voiceLog`).
List<VoiceLogEntry> voiceLog() => _read();

/// Forgets every recording in the log (`clearVoiceLog`).
void clearVoiceLog() => _write(const []);

String _two(int n) => n.toString().padLeft(2, '0');

String _timeOf(int at) {
  final time = DateTime.fromMillisecondsSinceEpoch(at);
  return '${time.year}-${_two(time.month)}-${_two(time.day)} ${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
}

/// The log as text to paste into a bug report or a chat (`voiceLogText`).
String voiceLogText([List<VoiceLogEntry>? entries]) => [
      for (final entry in entries ?? _read())
        ['## ${_timeOf(entry.at)}', 'Said: ${entry.transcript}', ...entry.steps.map((line) => '- $line'), 'Result: ${entry.outcome}'].join('\n'),
    ].join('\n\n');

/// The log as a screen sees it, following every write (`useVoiceLog`).
ValueListenable<List<VoiceLogEntry>> useVoiceLog() => Watched<List<VoiceLogEntry>>(voiceLog, (listener) {
      _written.addListener(listener);
      return () => _written.removeListener(listener);
    });
