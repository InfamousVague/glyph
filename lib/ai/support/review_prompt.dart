/// What the reviewing model is told, and what it is shown. A port of `src/app/review/prompt.ts`.
///
/// The review runs after a recording with reasoning ON, and its thinking is streamed to the screen as it happens:
/// Matt asked to see "the AI reasoning dissecting and parsing the note". So the prompt asks for the checking to be
/// done in the thinking, and for the answer to be nothing but the findings, in a small JSON shape a 4B model writes
/// reliably. Every finding must quote text that is really in a note, or it is thrown away (review_findings.dart), so
/// a model that invents a problem cannot invent a fix.
///
/// What differs: nothing in the words; [reviewPrompt] is the web's `REVIEW_PROMPT` byte for byte, in a raw string.
/// A note a command changed is a `({title, body})` record, and a budget a `({think, total})` one. Kept under
/// lib/ai/support until lib/review has a prompt.dart of its own.
library;

import 'dart:math' as math;

import '../../core/item_syntax.dart' show jsTrim;
import 'review_diff.dart';

/// The system prompt (`REVIEW_PROMPT`).
const String reviewPrompt = r'''You check a voice note that a fast pipeline just wrote, inside Ghost.md, a notes app. A small speech model transcribed what the person said as they said it, simple rules turned spoken cues into markdown (lists, headings, to-dos, tables), and voice commands that start with "Ghost.md" moved words into other notes. You are the careful second look. You are given the note as saved, what the fast speech model heard, what a slower and more accurate speech model heard, where those two disagree, the commands that ran, and the titles of the person's notes.

Think it through first, before you answer, but briefly: a few short lines for each check, no drafts, no second-guessing. Check four things:
1. Words: where the two transcripts disagree, which is right? The slower model is usually right about sounds; the fast one is sometimes right about names the person has used before. Only a real mistake counts, not punctuation or casing.
2. Structure: is each list, heading, to-do and table what the person meant? A to-do that should be a plain sentence, items that should be one list, a heading that is really a sentence.
3. Commands: set the words of each spoken command in what was heard beside what the command did. If the person named one note and the words went to another, that is a mistake: say so, and add the line to the note they named. Also: nothing lost, nothing added twice, no command words left in a note.
4. Names and terms: people, projects and features spelled the way the person's note titles and project notes spell them.

Then answer with ONLY a JSON array of findings, and nothing else. Each finding is an object:
{"check": "words" | "structure" | "commands" | "names", "what": "a short title", "why": "one plain sentence", "note": "the title of the note to change, or omit for this note", "find": "text copied exactly from that note", "replace": "what that text should be"}
To add a line to a note instead of changing text, give "add" (the line) and no "find" or "replace".

Rules: "find" must be copied character for character from the note it names. Keep each change as small as the mistake. Nothing the person did not say. No finding for style. If everything is right, answer [].''';

/// What a review is given (`ReviewInput`).
class ReviewInput {
  const ReviewInput({
    required this.title,
    required this.body,
    required this.heard,
    required this.careful,
    required this.changes,
    required this.commands,
    required this.titles,
    required this.touched,
  });

  final String title;

  /// The note as the recording left it.
  final String body;

  /// What the fast model heard, phrase by phrase, commands included.
  final String heard;

  /// What the careful model heard, or null when it could not listen again.
  final String? careful;
  final List<WordChange> changes;

  /// The commands the recording ran, in words: "Added “Fix the seek bar” to HelloTrade's list".
  final List<String> commands;

  /// The person's note titles, for names and for where commands went.
  final List<String> titles;

  /// Other notes a command changed: their titles and bodies, so a finding can quote them.
  final List<({String title, String body})> touched;
}

String _or(String text, String empty) => text.isEmpty ? empty : text;

/// The user message: every piece labelled, the note last so it is freshest.
String reviewMessage(ReviewInput input) {
  final sections = <String>[];
  sections.add('WHAT THE FAST SPEECH MODEL HEARD:\n${_or(jsTrim(input.heard), '(nothing)')}');
  final careful = input.careful;
  if (careful != null) sections.add('WHAT THE SLOWER, MORE ACCURATE SPEECH MODEL HEARD:\n${_or(jsTrim(careful), '(nothing)')}');
  if (input.changes.isNotEmpty) {
    sections.add(
      'WHERE THEY DISAGREE (fast → slower):\n${input.changes.take(40).map((c) => '- …${c.before} [${_or(c.heard, '∅')} → ${_or(c.careful, '∅')}] ${c.after}…').join('\n')}',
    );
  } else if (careful != null) {
    sections.add('WHERE THEY DISAGREE: nowhere.');
  }
  sections.add('COMMANDS THAT RAN:\n${input.commands.isNotEmpty ? input.commands.map((c) => '- $c').join('\n') : '(none)'}');
  sections.add("THE PERSON'S NOTE TITLES:\n${_or(input.titles.take(60).join(' · '), '(none)')}");
  for (final other in input.touched) {
    sections.add('OTHER NOTE A COMMAND CHANGED, "${other.title}":\n${jsTrim(other.body)}');
  }
  sections.add('THIS NOTE, "${input.title}", AS SAVED:\n${jsTrim(input.body)}');
  return sections.join('\n\n');
}

final RegExp _nine = RegExp('9b');
final RegExp _two = RegExp('2b');

/// How long the model may think, and how much it may write in all. A 4B model left to itself reasons for thousands
/// of tokens on a small note, which is minutes on a phone, so the thought is closed for it at a budget (native
/// `think_budget`) and the answer gets its own room after. Bigger models think more per token, so they get less.
({int think, int total}) reviewBudget(String model, int chars) {
  final think = _nine.hasMatch(model)
      ? 500
      : _two.hasMatch(model)
      ? 600
      : 700;
  final answer = math.min(1200, 500 + (chars / 12).ceil());
  return (think: think, total: math.min(4096, think + answer));
}
