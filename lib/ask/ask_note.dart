/// Save as note (docs/ASK_THE_ORG.md, "The sheet"; Matt, 2026-11-02, "'Ask the org' with receipts"): the question and
/// its answer as a Markdown note, each sentence's receipts as `[^1]` numbers and the receipts themselves as
/// `[[Note title]]` links with their lines and quotes, so the file says where every claim came from without the app.
library;

import 'ask.dart';
import 'ask_answer.dart';

String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The note's title: "Ask: When do we launch?".
String askNoteTitle(String question) {
  final words = _oneLine(question).replaceAll(RegExp(r'[\[\]#|]'), '');
  return 'Ask: ${words.length > 90 ? '${words.substring(0, 89)}…' : words}';
}

String _link(String title) => '[[${title.replaceAll(RegExp(r'[\[\]|#]'), '')}]]';

/// The note's Markdown (see the library's doc).
String askNoteBody(AskResult result) {
  final answer = result.answer;
  String refs(List<AskCitation> cited) => cited.map((c) => '[^${answer.numberOf(c)}]').join();
  final out = StringBuffer()
    ..writeln('# ${askNoteTitle(result.question)}')
    ..writeln()
    ..writeln('> ${_oneLine(result.question)}')
    ..writeln()
    ..writeln('Asked of ${result.scope.whose}${result.by == null ? '' : ', answered by ${result.by}'}.')
    ..writeln();
  final fromNotes = [for (final s in answer.sentences) if (!s.general) s];
  if (answer.notFound && answer.conflicts.isEmpty) {
    out
      ..writeln('Not in your notes: nothing in ${result.scope.whose} answers this.')
      ..writeln();
  } else if (fromNotes.isNotEmpty) {
    out
      ..writeln('## Answer')
      ..writeln();
    for (final s in fromNotes) {
      out.writeln('- ${_oneLine(s.text)} ${refs(s.citations)}');
    }
    out.writeln();
  }
  final general = [for (final s in answer.sentences) if (s.general) s];
  if (general.isNotEmpty) {
    out
      ..writeln('## General knowledge, not from your notes')
      ..writeln();
    for (final s in general) {
      out.writeln('- ${_oneLine(s.text)}');
    }
    out.writeln();
  }
  if (answer.conflicts.isNotEmpty) {
    out
      ..writeln('## Your notes disagree')
      ..writeln();
    for (final conflict in answer.conflicts) {
      final sides = conflict.sides.map((side) => '${_link(side.citation.title)} says ${_oneLine(side.text)} [^${answer.numberOf(side.citation)}]').join('; ');
      out.writeln('- ${conflict.about.isEmpty ? '' : '${_oneLine(conflict.about)}: '}$sides');
    }
    out.writeln();
  }
  final receipts = answer.receipts;
  if (receipts.isNotEmpty) {
    out
      ..writeln('## Receipts')
      ..writeln();
    for (final c in receipts) {
      out.writeln('[^${answer.numberOf(c)}]: ${_link(c.title)}, ${c.lines}: “${_oneLine(c.quote)}”');
    }
  }
  return '${out.toString().trimRight()}\n';
}
