/// Who writes an index, what it is asked and how its answers are checked (docs/AI_INDEXES.md §4). Matt, 2026-11-02:
/// "the AI keeps an index note (what's here, the key decisions, who owns what)".
///
/// **Whatever is connected**, in the assistant's order ([pickIndexAi]): Local only on, the device's own model and
/// nothing else; else the assistant's provider (Claude, or OpenAI, Gemini, Aster, a custom endpoint), read whole with
/// `aiText`; else the device's model; else nobody, with a sentence that says what to do.
///
/// **Answers are checked, never trusted** ([readNoteFacts]): each note is asked about by the number it was sent
/// under, and an answer about a number not sent, with no one-liner, or with a date that is not one is dropped. The
/// words go through `plainLine`, so an answer cannot write a link or a marker.
library;

import 'dart:convert';

import '../../assistant/provider.dart' show AiStreamer, aiText;
import '../../claude/claude_settings.dart' show ClaudeSettings;
import '../../claude/claude_spend.dart' show ClaudeSpend, meterClaude;
import '../../claude/messages_api.dart' show ClaudeApi;
import '../../assistant/assistant.dart' show AssistantChoice, claudeAssistantId;
import '../backend.dart' show RunOptions, generate;
import 'index_section.dart' show plainLine;

/// One model an index is written by.
abstract interface class IndexAi {
  /// What the section's marker and the card say: "Claude", "On this device".
  String get name;

  /// Whether it is the device's own model (slower, and with less room a request).
  bool get onDevice;

  /// One answer, whole. Throws where the model did not answer.
  Future<String> ask({required String system, required String prompt, required int maxTokens});

  /// Stops what is being asked, if anything.
  void cancel();
}

/// How much goes in one request, and how much of one note.
int batchCharsOf(IndexAi ai) => ai.onDevice ? 12000 : 60000;
int noteCharsOf(IndexAi ai) => ai.onDevice ? 2500 : 6000;

/// A cloud provider through its streamer: Claude's client, or another's (lib/assistant/provider.dart).
class CloudIndexAi implements IndexAi {
  CloudIndexAi({required this.name, required this.streamer, required this.model, this.spend});

  @override
  final String name;
  final AiStreamer streamer;
  final String model;

  /// The provider's spending meter, counted as each answer ends and refused once its month's limit is reached.
  final ClaudeSpend? spend;

  final Set<void Function()> _cancels = {};

  @override
  bool get onDevice => false;

  @override
  Future<String> ask({required String system, required String prompt, required int maxTokens}) async {
    final meter = spend;
    if (meter != null && meter.reached) throw StateError('$name’s spending limit for the month is reached.');
    final body = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };
    var call = streamer.stream(body);
    if (meter != null) call = meterClaude(call, model: model, spend: meter);
    _cancels.add(call.cancel);
    try {
      return await aiText(call, who: name);
    } finally {
      _cancels.remove(call.cancel);
    }
  }

  @override
  void cancel() {
    for (final stop in [..._cancels]) {
      stop();
    }
  }
}

/// The device's own model (lib/ai/backend.dart [generate]).
class DeviceIndexAi implements IndexAi {
  DeviceIndexAi(this.model);

  final String model;
  void Function()? _cancel;

  @override
  String get name => 'On this device';

  @override
  bool get onDevice => true;

  @override
  Future<String> ask({required String system, required String prompt, required int maxTokens}) async {
    final run = generate(RunOptions(model: model, system: system, prompt: prompt, maxTokens: maxTokens, temperature: 0.2, onProgress: (_) {}));
    _cancel = run.cancel;
    try {
      return (await run.done).text;
    } finally {
      _cancel = null;
    }
  }

  @override
  void cancel() => _cancel?.call();
}

/// Who writes an index now, or why nobody can.
class IndexAiPick {
  const IndexAiPick(this.ai, [this.why]);

  final IndexAi? ai;
  final String? why;
}

/// The rule (see the header): [localOnly] keeps it to [device]; else [cloud], else [device]; else nobody.
IndexAiPick pickIndexAi({required bool localOnly, required IndexAi? Function() cloud, required IndexAi? Function() device}) {
  if (localOnly) {
    final here = device();
    return here != null ? IndexAiPick(here) : const IndexAiPick(null, 'Local only is on, and this device has no model. Get one in Settings › AI.');
  }
  final away = cloud();
  if (away != null) return IndexAiPick(away);
  final here = device();
  if (here != null) return IndexAiPick(here);
  return const IndexAiPick(null, 'Connect an AI in Settings › AI, or get a model for this device.');
}

/// The assistant's provider as an [IndexAi] (lib/assistant/assistant.dart `chatBy`): Claude where it answers, else the
/// other provider; null for nobody.
IndexAi? cloudIndexAi(AssistantChoice choice, ClaudeSettings claude) {
  final by = choice.chatBy;
  if (by == null) return null;
  if (by == claudeAssistantId) {
    final key = claude.key;
    if (key == null || key.trim().isEmpty) return null;
    return CloudIndexAi(name: 'Claude', streamer: ClaudeApi(key: key), model: claude.model, spend: claude.spend);
  }
  final route = choice.chatRoute;
  if (route == null) return null;
  return CloudIndexAi(name: route.name, streamer: route.api(), model: route.model, spend: route.spend);
}

// ---- the asks ------------------------------------------------------------------------------------------------------

/// What a batch of notes is asked under.
const String noteFactsSystem = '''You keep the index page of a folder of notes, for a new teammate who has not read them.
For each note you are given, answer:
- "about": one plain sentence, at most 20 words, saying what the note is for or what it settles. No links, no markdown.
- "theme": a short name (1 to 3 words) for the group it belongs in. Reuse one of the existing themes where it fits.
- "decisions": the decisions the note records, if any (at most 3), each {"date": "YYYY-MM-DD", "what": "what was decided, at most 15 words"}. Use the date the note gives for the decision, else the note's date. A plan or an idea is not a decision.
Answer with a JSON array and nothing else, one object per note: [{"n": 1, "about": "...", "theme": "...", "decisions": []}]''';

/// What the overview is asked under.
const String overviewSystem = '''You keep the index page of a folder of notes. Write two or three plain sentences saying what the folder is for and what is in it, for a new teammate. No links, no lists, no headings, no markdown.''';

/// One note as a batch sends it.
class IndexSource {
  const IndexSource({required this.title, required this.day, required this.text});

  final String title;

  /// Its date, `YYYY-MM-DD`.
  final String day;
  final String text;
}

/// A batch's words: the themes so far, then each note under its number, cut at [noteChars].
String noteFactsPrompt(List<IndexSource> notes, {required List<String> themes, required int noteChars}) {
  final out = StringBuffer();
  out.writeln(themes.isEmpty ? 'Existing themes: none yet.' : 'Existing themes: ${themes.join(', ')}.');
  out.writeln();
  for (var i = 0; i < notes.length; i += 1) {
    final note = notes[i];
    final text = note.text.length > noteChars ? '${note.text.substring(0, noteChars)}\n[…cut]' : note.text;
    out
      ..writeln('### Note ${i + 1}: ${note.title} (${note.day})')
      ..writeln(text.trim())
      ..writeln();
  }
  return out.toString();
}

/// The overview's words: the folder's name and each theme's one-liners.
String overviewPrompt(String folder, Map<String, List<String>> themes) {
  final out = StringBuffer('Folder: $folder\n\n');
  for (final MapEntry(key: theme, value: abouts) in themes.entries) {
    out.writeln('$theme:');
    for (final about in abouts.take(12)) {
      out.writeln('- $about');
    }
  }
  return out.toString();
}

/// What the AI said about one note of a batch.
class IndexFacts {
  const IndexFacts({required this.n, required this.about, required this.theme, this.decisions = const []});

  /// The number the note was sent under, from 1.
  final int n;
  final String about, theme;

  /// Each decision's day and words.
  final List<(String, String)> decisions;
}

final RegExp _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The answer to a batch of [count] notes, checked item by item (see the header). An answer that is not a JSON array
/// at all reads as none.
List<IndexFacts> readNoteFacts(String answer, int count) {
  final start = answer.indexOf('['), end = answer.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  Object? parsed;
  try {
    parsed = jsonDecode(answer.substring(start, end + 1));
  } catch (_) {
    return const [];
  }
  if (parsed is! List) return const [];
  final seen = <int>{};
  final facts = <IndexFacts>[];
  for (final item in parsed) {
    if (item is! Map) continue;
    final n = item['n'];
    final number = n is int ? n : (n is String ? int.tryParse(n) : null);
    if (number == null || number < 1 || number > count || !seen.add(number)) continue;
    final about = item['about'] is String ? plainLine(item['about'] as String, most: 160) : '';
    if (about.isEmpty) continue;
    var theme = item['theme'] is String ? plainLine((item['theme'] as String).replaceAll('#', ''), most: 40) : '';
    if (theme.isEmpty) theme = 'Other';
    final decisions = <(String, String)>[];
    final said = item['decisions'];
    if (said is List) {
      for (final d in said.take(3)) {
        if (d is! Map || d['date'] is! String || d['what'] is! String) continue;
        final date = (d['date'] as String).trim();
        final what = plainLine(d['what'] as String, most: 120);
        if (!_day.hasMatch(date) || DateTime.tryParse(date) == null || what.isEmpty) continue;
        decisions.add((date, what));
      }
    }
    facts.add(IndexFacts(n: number, about: about, theme: theme, decisions: decisions));
  }
  return facts;
}

/// The overview from its answer: one paragraph, plain.
String readOverview(String answer) => plainLine(answer.replaceAll(RegExp(r'^#+\s*', multiLine: true), '').replaceAll(RegExp(r'[*_`]'), ''), most: 600);
