/// One question asked, start to end (docs/ASK_THE_ORG.md; Matt, 2026-11-02: "'Ask the org' with receipts: questions
/// answered only from your notes, every claim linked to the note and line it came from; when notes disagree, it shows
/// both instead of guessing"): the scope's notes searched on the device, the passages found sent to [AskModel], its
/// JSON read and every quote checked. With nothing found the model is not asked at all.
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import 'ask_answer.dart';
import 'ask_model.dart';
import 'ask_prompt.dart';
import 'ask_retrieve.dart';
import 'ask_scope.dart';

/// A question and what came of it.
@immutable
class AskResult {
  const AskResult({required this.question, required this.scope, required this.answer, required this.retrieval, this.by});

  final String question;
  final AskScope scope;
  final AskAnswer answer;
  final AskRetrieval retrieval;

  /// Who answered; null where nobody was asked (nothing found).
  final String? by;
}

/// What the model said could not be read as an answer.
class AskUnreadable implements Exception {
  const AskUnreadable(this.by);

  final String by;

  @override
  String toString() => '$by’s answer could not be read. Try asking again.';
}

/// A question in flight: its result, and the way to stop it.
typedef AskRun = ({Future<AskResult> done, void Function() cancel});

/// Asks [question] of [notes], already the [scope]'s ([notesInScope]); [general] lets the model fill a gap from
/// general knowledge, each such sentence marked.
AskRun ask(String question, {required AskScope scope, required List<Note> notes, required AskModel model, bool general = false, required int now}) {
  final retrieval = retrieve(question, notes, budget: model.budget, now: now);
  if (retrieval.isEmpty && !general) {
    return (done: Future.value(AskResult(question: question, scope: scope, answer: const AskAnswer.nothingFound(), retrieval: retrieval)), cancel: () {});
  }
  final call = model.complete(system: askSystem(whose: scope.whose, general: general), prompt: askPrompt(question, retrieval.passages));
  Future<AskResult> read() async {
    final said = await call.done;
    final raw = parseAskJson(said);
    if (raw == null) throw AskUnreadable(model.name);
    final answer = validateAsk(raw, retrieval.passages, general: general);
    return AskResult(question: question, scope: scope, answer: answer, retrieval: retrieval, by: model.name);
  }

  return (done: read(), cancel: call.cancel);
}
