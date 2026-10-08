/// A prompt that once asked a small language model on the phone to read what was said after "Glyph" when the rules
/// in capture/command.dart could not, and the reader of its answers. A port of `src/app/capture/understand.ts`.
///
/// Matt: "it feels like the model for doing the agentic tasks should be different than the language parsing model,
/// we might need two different AI passes, I can't even pass the tutorial". Speech is still read two ways, and they
/// stay separate: Whisper writes the words and the rules find the marks in them (fast, the same every time, nothing
/// guessed), and only a command, which is an action on another note, gets a model. That model is asked once now, at
/// Done, through `ai_infer_command` (final_instruction.dart and instruction_intent.dart `inferInstruction`), never
/// while the microphone is live: the pass that asked it mid-take has gone (docs/DESIGN.md §127).
///
/// [commandPrompt] and [readCommandAnswer] are the pass before that one, which put this prompt to the model itself.
/// Nothing on the page asks with them any more. On the web they stay because `src-tauri/src/llm/tests.rs` reads the
/// prompt out of the web's file by name and measures the phone's models on the Mac against the same words
/// (`understands_spoken_commands`), and the reader's test holds it to the answers the prompt asks for; here they are
/// kept so the two stay one text.
///
/// What differs: `COMMAND_PROMPT` is [commandPrompt]. The model's answer is read with `dart:convert`, whose
/// `jsonDecode` takes the same JSON as `JSON.parse`.
library;

import 'dart:convert' show jsonDecode;
import 'dart:math' as math;

import 'command.dart' show Plan, PlanMove, PlanNew, PlanPlace, PlanTable, PlacementHow;
import 'route.dart' show Candidate, matchNote;

/// The prompt (`COMMAND_PROMPT`), word for word the web's.
const String commandPrompt = r''' literal for that - and measures the phone's models on the Mac against the
 * same words (`understands_spoken_commands`), and understand.test.ts holds the reader to the answers it asks for.
 */

export const COMMAND_PROMPT = String.raw`You read one spoken command for Ghost.md, a notes app, and answer with JSON. The person may have said "hey Ghost" (or "Glyph") first; the words here are the command. It was written down by speech recognition, so words can be misheard and a note's name can come out spelled or split differently.

Answer with exactly one JSON object on one line, and nothing else. It is one of:
{"action":"add","note":"<a title from the list>","text":"<what to add>","item":false,"task":false}
{"action":"switch","note":"<a title from the list>"}
{"action":"new"}
{"action":"table","note":"<a title from the list, or empty for the note being recorded>","columns":["<label>"]}
{"action":"none"}

- add: put words into a note. "text" is only the thing to add, in their words, without the command or the note's name. "item" is true when they ask for a list item, bullet, point or entry; "task" is true when they ask for a task, to-do or check box.
- switch: carry on recording in that note ("switch to", "go to", "move this to").
- new: start a new note.
- table: add a table. "columns" are the column labels if they said them, otherwise [].
- none: it is not one of these, or you are not sure which note they mean.

"note" is copied exactly from the list of notes. Choose the note whose title is what they said, allowing for misheard words. If no title fits, answer {"action":"none"}. Never invent a note, and never add words they did not say.

Examples, with the notes Groceries, Work and Weekend trip:
Command: Put call Sam on the work list.
{"action":"add","note":"Work","text":"call Sam","item":true,"task":false}
Command: For the weekend trip, book the ferry.
{"action":"add","note":"Weekend trip","text":"book the ferry","item":false,"task":false}
Command: New to-do for work, send the invoice.
{"action":"add","note":"Work","text":"send the invoice","item":true,"task":true}
Command: Switch to groceries.
{"action":"switch","note":"Groceries"}
Command: New note.
{"action":"new"}
Command: Add a table with columns name and date.
{"action":"table","note":"","columns":["name","date"]}
Command: Add eggs to the camping list.
{"action":"none"}''';

/// The question for one command: the person's note titles, then what was said.
String commandMessage(String words, List<String> titles) {
  final list = titles.isNotEmpty ? titles.map((title) => '- $title').join('\n') : '(none)';
  return 'Notes:\n$list\n\nCommand: ${words.trim()}';
}

final RegExp _think = RegExp(r'<think>[\s\S]*?</think>');
final RegExp _fence = RegExp(r'```(?:json)?');

/// The first JSON object in the model's answer, if it wrote one.
Map<String, Object?>? _objectIn(String output) {
  final cleaned = output.replaceAll(_think, '').replaceAll(_fence, '');
  final start = cleaned.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var quoted = false;
  for (var i = start; i < cleaned.length; i += 1) {
    final ch = cleaned[i];
    if (quoted) {
      if (ch == r'\') {
        i += 1;
      } else if (ch == '"') {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        try {
          final Object? value = jsonDecode(cleaned.substring(start, i + 1));
          return value is Map<String, Object?> ? value : null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingMarks = RegExp(r'[\s.,;:!?]+$');

String _text(Object? value) => value is String ? value.replaceAll(_spaces, ' ').trim() : '';

/// The model's answer as a plan the recorder already knows how to confirm, or null: not JSON, not a command, or a
/// note that is not one of [notes]. The note is found again by title, so an answer that copied it slightly wrong
/// still lands on the right note and one that made a note up lands on none.
Plan<N>? readCommandAnswer<N extends Candidate>(String output, List<N> notes) {
  final answer = _objectIn(output);
  if (answer == null) return null;
  final action = _text(answer['action']).toLowerCase();
  N? find(Object? value) {
    final name = _text(value);
    if (name.isEmpty) return null;
    for (final note in notes) {
      if (note.title.trim().toLowerCase() == name.toLowerCase()) return note;
    }
    return matchNote<N>(name, notes)?.note;
  }

  if (action == 'new') return PlanNew<N>();
  if (action == 'switch') {
    final note = find(answer['note']);
    return note != null ? PlanMove<N>(note: note) : null;
  }
  if (action == 'add') {
    final note = find(answer['note']);
    final words = _text(answer['text']).replaceFirst(_trailingMarks, '');
    if (note == null || words.isEmpty) return null;
    final task = answer['task'] == true;
    return PlanPlace<N>(
      note: note,
      text: words,
      how: task || answer['item'] == true ? PlacementHow.item : PlacementHow.leave,
      task: task,
      many: false,
    );
  }
  if (action == 'table') {
    final named = _text(answer['note']);
    final note = named.isNotEmpty ? find(named) : null;
    if (named.isNotEmpty && note == null) return null;
    final labels = answer['columns'];
    final columns = labels is List ? labels.map(_text).where((label) => label.isNotEmpty).toList() : <String>[];
    return PlanTable<N>(note: note, columns: columns.sublist(0, math.min(8, columns.length)));
  }
  return null;
}
