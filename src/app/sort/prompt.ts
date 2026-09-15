/**
 * What the sorting model is told, and shown (sort/useSort.ts). The answer is a small JSON array a 4B model writes
 * reliably, and every item is checked against the notes and the memo before it can move anything (sort/plan.ts).
 */

export const SORT_PROMPT = String.raw`You sort a voice memo into a person's notes, inside Glyph, a notes app. The person spoke the memo in one go. Some of it is meant for notes they already have: "add oat milk to groceries", "put call Sam on the work list", "for the trip note, book the ferry". The rest is a new note of its own.

Think briefly first: for each sentence, does the person name one of their notes, or clearly mean one? Only the notes listed exist.

Then answer with ONLY a JSON array, and nothing else. One object for each thing to put in an existing note:
{"note": "the note's title, exactly as listed", "add": "what to add, without the command words", "as": "item" | "task" | "text", "from": "the memo's words it came from, copied exactly"}
"as": "item" for a list item, "task" for a to-do, "text" for a sentence or paragraph.

Rules: only notes from the list. "from" copied character for character from the memo. Leave everything that isn't for an existing note out of the array; it becomes a new note. If nothing is for an existing note, answer [].`;

export interface SortInput {
  memo: string;
  /** The person's notes: titles, and each one's last lines so a list can be recognised. */
  notes: readonly { title: string; body: string }[];
}

/** The user message: the notes first, the memo last so it is freshest. */
export function sortMessage({ memo, notes }: SortInput): string {
  const listed = notes
    .slice(0, 40)
    .map((note) => {
      const tail = note.body.split('\n').filter((line) => line.trim()).slice(-3).join(' / ');
      return `- ${note.title}${tail ? ` (ends: ${tail.slice(0, 120)})` : ''}`;
    })
    .join('\n');
  return `THE PERSON'S NOTES:\n${listed || '(none)'}\n\nTHE MEMO:\n${memo.trim()}`;
}

/** Room to think and to answer: a short answer, a memo's worth of placements at most. */
export function sortBudget(model: string, chars: number): { think: number; total: number } {
  const think = /9b/.test(model) ? 400 : /2b/.test(model) ? 500 : 600;
  const answer = Math.min(900, 300 + Math.ceil(chars / 10));
  return { think, total: Math.min(4096, think + answer) };
}
