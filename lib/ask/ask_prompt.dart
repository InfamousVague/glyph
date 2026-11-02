/// What the model is told for a question (docs/ASK_THE_ORG.md, "The prompt"; Matt, 2026-11-02: "questions answered
/// only from your notes, every claim linked to the note and line it came from; when notes disagree, it shows both
/// instead of guessing"): the rules, then the passages found, each with its note, its date and its numbered lines.
library;

import 'ask_retrieve.dart';

/// The rules, with or without general knowledge allowed.
String askSystem({required String whose, bool general = false}) => '''
You answer a question using ONLY the passages from $whose given below. They are the only source of truth.

Rules:
- Every sentence of your answer must cite the passage lines it rests on. A citation is {"noteId", "fromLine", "toLine", "quote"}, where "quote" is copied word for word from those lines (a short phrase is enough) and the lines are the numbers shown before each line.
- Never cite a note or a line that is not in the passages.
- If the passages do not answer the question, set "notFound" to true and give no sentences. Do not guess.
- If passages disagree with each other (different dates, numbers, owners, decisions), do not pick one: put each side in "conflicts", each with its own citation.
${general ? '- You may add a sentence from general knowledge only where the passages leave a gap; mark it "general": true and give it no citations. Never present general knowledge as coming from the notes.' : '- Do not use general knowledge or anything outside the passages.'}
- Be brief: at most six sentences.

Reply with JSON only, no other words, in this shape:
{"notFound": false, "sentences": [{"text": "...", "citations": [{"noteId": "...", "fromLine": 1, "toLine": 1, "quote": "..."}]}], "conflicts": [{"about": "...", "sides": [{"text": "...", "citation": {"noteId": "...", "fromLine": 1, "toLine": 1, "quote": "..."}}]}]}''';

String _day(int ms) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}

String _attr(String value) => value.replaceAll('"', '\'').replaceAll('\n', ' ');

/// The question and the passages, as the model is sent them.
String askPrompt(String question, List<AskPassage> passages) {
  final out = StringBuffer();
  for (final p in passages) {
    out.writeln('<passage note="${_attr(p.note.id)}" title="${_attr(p.title)}" written="${_day(p.note.createdAt)}" lines="${p.fromLine}-${p.toLine}">');
    for (var at = 0; at < p.lines.length; at += 1) {
      out.writeln('${p.fromLine + at}: ${p.lines[at]}');
    }
    out.writeln('</passage>');
  }
  out
    ..writeln()
    ..writeln('Question: ${question.trim()}');
  return out.toString();
}
