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
/// text is no record, which the page checked as it read. And the record's facts are written into the note's own
/// front matter as the summary lands ([withSummaryFacts]; docs/MARKDOWN_FIRST.md §5, gap 13; Matt, 2026-10-31):
/// the model, when, how long the tape was, and a hash of the section rather than its text, since the text is in the
/// note. A library restored from its files alone would otherwise read every summary as the person's own and never
/// say "from before the last take". The device's record is read first, the note's facts where it has none
/// ([readSummaryIn]), for a release; the record is still kept.
library;

import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterValue;
import '../core/item_syntax.dart' show jsTrim;
import '../core/properties.dart' show withFrontMatterValue, yamlValue;
import '../core/stored.dart';
import '../core/summary_text.dart' show summarySection;
import 'support/note_sheet.dart';

const String _key = 'glyph-summaries';

/// The front matter keys the summary's facts are written under, flat, since the library's reader (frontmatter.rs
/// `get`) reads no nested map: `summary-model: qwen3.5-2b`, `summary-at: 2026-10-31T14:02:11.000Z`,
/// `summary-for-ms: 3723000`, `summary-sha: <sha256 of the section>`.
const String summaryModelKey = 'summary-model';
const String summaryAtKey = 'summary-at';
const String summaryForMsKey = 'summary-for-ms';
const String summaryShaKey = 'summary-sha';

/// The hash a section is named by in the note: its SHA-256, in hex.
String summarySha(String text) => sha256.convert(utf8.encode(text)).toString();

/// The body with [kept]'s facts written in its front matter (the keys above), the section itself already in it.
String withSummaryFacts(String body, KeptSummary kept) {
  var out = withFrontMatterValue(body, summaryModelKey, kept.model.isEmpty ? null : yamlValue(kept.model));
  out = withFrontMatterValue(out, summaryAtKey, DateTime.fromMillisecondsSinceEpoch(kept.at, isUtc: true).toIso8601String());
  out = withFrontMatterValue(out, summaryForMsKey, kept.forMs > 0 ? '${kept.forMs}' : null);
  return withFrontMatterValue(out, summaryShaKey, summarySha(kept.text));
}

/// The body with the facts taken off: a summary the app no longer owns.
String withoutSummaryFacts(String body) => [summaryModelKey, summaryAtKey, summaryForMsKey, summaryShaKey].fold(body, (out, key) => withFrontMatterValue(out, key, null));

/// The section in [body] that hashes to [sha]: the one found by its shape, or that section less its last lines, one
/// at a time, since the person may have written a list of their own straight under what the app wrote. Null where
/// none does.
String? _sectionNamed(String body, String sha) {
  final section = summarySection(body);
  if (section == null) return null;
  final lines = section.text.split('\n');
  for (var n = lines.length; n > 0; n -= 1) {
    final text = lines.sublist(0, n).join('\n');
    if (summarySha(text) == sha) return text;
  }
  return null;
}

/// What the note's own front matter says the app wrote as its summary ([withSummaryFacts]), with the section's text
/// where the note still holds a section that hashes as it was written. Null where the note says nothing, or holds
/// no such section any more (the person's edit, or the section gone).
KeptSummary? summaryFactsOf(String body) {
  final sha = jsTrim(frontMatterValue(body, summaryShaKey) ?? '');
  if (sha.isEmpty) return null;
  final text = _sectionNamed(body, sha);
  if (text == null) return null;
  final at = DateTime.tryParse(jsTrim(frontMatterValue(body, summaryAtKey) ?? ''));
  return KeptSummary(
    text: text,
    model: jsTrim(frontMatterValue(body, summaryModelKey) ?? ''),
    at: at?.millisecondsSinceEpoch ?? 0,
    forMs: int.tryParse(jsTrim(frontMatterValue(body, summaryForMsKey) ?? '')) ?? 0,
  );
}

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

// ---- read both: the device's record, then the note's own facts --------------------------------------------------

/// What was written for note [id]: this device's record, else what the note's own front matter says ([summaryFactsOf]
/// of [body]).
KeptSummary? readSummaryIn(String id, String body) => readSummary(id) ?? summaryFactsOf(body);

/// [keptText], the note's own facts read where the device has no record.
String? keptTextIn(String id, String body) => readSummaryIn(id, body)?.text;

/// [summaryUnchanged], the note's own facts read where the device has no record.
bool summaryUnchangedIn(String id, String body, String text) => readSummaryIn(id, body)?.text == text;

/// [summaryBehind], the note's own facts read where the device has no record.
bool summaryBehindIn(String id, String body, int recordingMs) {
  final kept = readSummaryIn(id, body);
  return kept != null && recordingMs > kept.forMs;
}
