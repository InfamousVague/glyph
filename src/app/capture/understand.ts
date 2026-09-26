import { matchNote, type Candidate } from './route.ts';
import type { Plan } from './command.ts';

/**
 * A prompt that once asked a small language model on the phone to read what was said after "Glyph" when the rules in
 * capture/command.ts could not, and the reader of its answers.
 *
 * Matt: "it feels like the model for doing the agentic tasks should be different than the language parsing model, we
 * might need two different AI passes, I can't even pass the tutorial". Speech is still read two ways, and they stay
 * separate: Whisper writes the words and the rules find the marks in them (fast, the same every time, nothing
 * guessed), and only a command, which is an action on another note, gets a model. That model is asked once now, at
 * Done, through `ai_infer_command` (capture/finalInstruction.ts and instructionIntent.ts `inferInstruction`), never
 * while the microphone is live: the pass that asked it mid-take has gone (docs/DESIGN.md §127).
 *
 * `COMMAND_PROMPT` and `readCommandAnswer` are the pass before that one, which put this prompt to the model itself.
 * Nothing on the page asks with them any more. They stay because `src-tauri/src/llm/tests.rs` reads the prompt out of
 * this file by name - it is a `String.raw` literal for that - and measures the phone's models on the Mac against the
 * same words (`understands_spoken_commands`), and understand.test.ts holds the reader to the answers it asks for.
 */

export const COMMAND_PROMPT = String.raw`You read one spoken command for Ghost.md, a notes app, and answer with JSON. The person said "hey Ghost" (or "Glyph") and then the command. It was written down by speech recognition, so words can be misheard and a note's name can come out spelled or split differently.

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
{"action":"none"}`;

/** The question for one command: the person's note titles, then what was said. */
export function commandMessage(words: string, titles: readonly string[]): string {
  const list = titles.length ? titles.map((title) => `- ${title}`).join('\n') : '(none)';
  return `Notes:\n${list}\n\nCommand: ${words.trim()}`;
}

interface Answer {
  action?: unknown;
  note?: unknown;
  text?: unknown;
  item?: unknown;
  task?: unknown;
  columns?: unknown;
}

/** The first JSON object in the model's answer, if it wrote one. */
function objectIn(output: string): Answer | null {
  const cleaned = output.replace(/<think>[\s\S]*?<\/think>/g, '').replace(/```(?:json)?/g, '');
  const start = cleaned.indexOf('{');
  if (start < 0) return null;
  let depth = 0;
  let quoted = false;
  for (let i = start; i < cleaned.length; i += 1) {
    const ch = cleaned[i];
    if (quoted) {
      if (ch === '\\') i += 1;
      else if (ch === '"') quoted = false;
    } else if (ch === '"') quoted = true;
    else if (ch === '{') depth += 1;
    else if (ch === '}' && (depth -= 1) === 0) {
      try {
        const value = JSON.parse(cleaned.slice(start, i + 1)) as unknown;
        return value && typeof value === 'object' && !Array.isArray(value) ? (value as Answer) : null;
      } catch {
        return null;
      }
    }
  }
  return null;
}

const text = (value: unknown) => (typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '');

/**
 * The model's answer as a plan the recorder already knows how to confirm, or null: not JSON, not a command, or a note
 * that is not one of `notes`. The note is found again by title, so an answer that copied it slightly wrong still
 * lands on the right note and one that made a note up lands on none.
 */
export function readCommandAnswer<N extends Candidate>(output: string, notes: readonly N[]): Plan<N> | null {
  const answer = objectIn(output);
  if (!answer) return null;
  const action = text(answer.action).toLowerCase();
  const find = (value: unknown): N | null => {
    const name = text(value);
    if (!name) return null;
    return notes.find((note) => note.title.trim().toLowerCase() === name.toLowerCase()) ?? matchNote(name, notes)?.note ?? null;
  };
  if (action === 'new') return { kind: 'new' };
  if (action === 'switch') {
    const note = find(answer.note);
    return note ? { kind: 'move', note } : null;
  }
  if (action === 'add') {
    const note = find(answer.note);
    const words = text(answer.text).replace(/[\s.,;:!?]+$/, '');
    if (!note || !words) return null;
    const task = answer.task === true;
    return { kind: 'place', note, text: words, how: task || answer.item === true ? 'item' : 'leave', task, many: false, target: null };
  }
  if (action === 'table') {
    const named = text(answer.note);
    const note = named ? find(named) : null;
    if (named && !note) return null;
    const columns = Array.isArray(answer.columns) ? answer.columns.map(text).filter(Boolean).slice(0, 8) : [];
    return { kind: 'table', note, columns };
  }
  return null;
}
