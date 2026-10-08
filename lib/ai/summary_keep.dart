/// What the app wrote as a note's summary, kept per note on the device (docs/DESIGN.md §127 section 2): the exact
/// section text, the model, when, and how long the tape was. A port of `src/app/ai/summaryKeep.ts`.
///
/// A summary is remade only on purpose, and this is how a remake knows whether the section in the note is still the
/// app's: if it reads exactly as kept it is replaced whole, and if it differs the person edited it and the strip
/// asks first. The kept text also closes the section for every reader (ai/summary_text.dart `summarySection`), so a
/// list of the person's straight under it is never read as the section's. The tape's length says whether the
/// summary is from before the last take: an Add makes the tape longer and the summary older. A note deleted for
/// good takes its record with it. A reset clears the key with every other `glyph-` one.
///
/// What differs: a record is a [KeptSummary] with the web's JSON as its [KeptSummary.toJson]; one whose text is not
/// text is no record, which the page checked as it read.
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';
import 'support/note_sheet.dart';

const String _key = 'glyph-summaries';

/// One note's summary as the app wrote it (`KeptSummary`).
@immutable
class KeptSummary {
  const KeptSummary({required this.text, required this.model, required this.at, required this.forMs});

  /// A record as it was kept, or null for something that is not one.
  static KeptSummary? fromJson(Object? raw) {
    if (raw is! Map || raw['text'] is! String) return null;
    return KeptSummary(
      text: raw['text'] as String,
      model: raw['model'] is String ? raw['model'] as String : '',
      at: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
      forMs: raw['forMs'] is num ? (raw['forMs'] as num).toInt() : 0,
    );
  }

  /// The section exactly as written, `## Summary` through its last item.
  final String text;
  final String model;

  /// When it was written, in ms since the epoch.
  final int at;

  /// The tape's length when it was written: a longer tape now means a take the summary never heard.
  final int forMs;

  Map<String, Object?> toJson() => {'text': text, 'model': model, 'at': at, 'forMs': forMs};

  @override
  bool operator ==(Object other) => other is KeptSummary && other.text == text && other.model == model && other.at == at && other.forMs == forMs;

  @override
  int get hashCode => Object.hash(text, model, at, forMs);

  @override
  String toString() => 'KeptSummary(${toJson()})';
}

final NoteSheet<KeptSummary> _sheet = NoteSheet<KeptSummary>(
  () => stored.readShared<Sheet<KeptSummary>>(_key, const {}, (raw) => sheetOf<KeptSummary>(raw, KeptSummary.fromJson)),
  (value) => stored.write(_key, value),
);

/// What was written for note [id], or null (`readSummary`).
KeptSummary? readSummary(String id) => _sheet.read()[id];

/// The section text as written, for the readers that close the section by it (ai/summary_text.dart
/// `summarySection`); null with none (`keptText`).
String? keptText(String id) => readSummary(id)?.text;

/// Keeps what was written for note [id] (`keepSummary`).
void keepSummary(String id, KeptSummary kept) => _sheet.update(id, (_) => kept);

/// A note is gone: so is what was written for it (`forgetSummary`).
void forgetSummary(String id) => _sheet.forget(id);

/// Whether the section [text] in a note is the one the app wrote, word for word (`summaryUnchanged`).
bool summaryUnchanged(String id, String text) => readSummary(id)?.text == text;

/// Whether the tape has grown since the summary was written: "Summary is from before the last take."
/// (`summaryBehind`).
bool summaryBehind(String id, int recordingMs) {
  final kept = readSummary(id);
  return kept != null && recordingMs > kept.forMs;
}
