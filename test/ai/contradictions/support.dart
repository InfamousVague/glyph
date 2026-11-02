/// What the contradiction finder's tests share: notes, and an AI that answers from a script (never a real one).
library;

import 'dart:async';

import 'package:ghost_md/ai/contradictions/ai.dart';
import 'package:ghost_md/core/note.dart';

/// A note as the library holds one, edited at [day] (days after 2026-11-01).
Note note(String id, String body, {int day = 0, String? path, int revision = 1}) => Note(
      id: id,
      body: body,
      createdAt: DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
      updatedAt: DateTime.utc(2026, 11, 1).add(Duration(days: day)).millisecondsSinceEpoch,
      source: NoteSource.editor,
      path: path ?? 'Inbox/$id.md',
      revision: revision,
    );

/// The plan with its release day, and the standup a week later that moved it.
final Note plan = note('plan', '# Release plan\n\nRelease is Thursday Nov 12.\n- Owner: @sam\n#release', day: 0);
final Note standup = note('standup', '# Standup\n\n- Release moved to Monday Nov 16 #release\n- @sam is out Friday', day: 7);

/// An AI whose answers are [answers], one a request, the prompts it was asked kept in [asked].
class ScriptedAi implements ContradictionAi {
  ScriptedAi(this.answers, {this.onDevice = false, this.name = 'Scripted', this.reply});

  /// Answers by the prompt, in place of [answers].
  final String Function(String prompt)? reply;

  final List<String> answers;
  final List<String> asked = [];
  @override
  final bool onDevice;
  @override
  final String name;

  /// Held until completed, where a test stops a run in flight.
  Completer<String>? hold;
  bool cancelled = false;

  @override
  Duration get perRequest => const Duration(seconds: 30);

  @override
  ContradictionAsk ask({required String system, required String prompt}) {
    asked.add(prompt);
    final held = hold;
    if (held != null) {
      return ContradictionAsk(held.future, () {
        cancelled = true;
        if (!held.isCompleted) held.completeError(StateError('cancelled'));
      });
    }
    final answer = reply?.call(prompt) ?? (answers.isEmpty ? '{"findings": []}' : answers.removeAt(0));
    return ContradictionAsk(Future.value(answer), () => cancelled = true);
  }
}

/// The answer that finds the release day moved in pair [pair].
String releaseMoved({int pair = 1, double confidence = 0.93, String older = 'Release is Thursday', String newer = 'Release moved to Monday'}) =>
    '{"findings": [{"pair": $pair, "older": "A", "older_quote": "$older", "newer": "B", "newer_quote": "$newer", "what": "The release day moved from Thursday to Monday.", "confidence": $confidence}]}';
