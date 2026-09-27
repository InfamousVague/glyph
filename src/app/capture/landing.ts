/**
 * What a recording left in a note that already existed, handed to the note as it opens after Done: which note, the
 * pieces of text put in (for its Undo to find and take out), and the other notes it wrote to or made.
 *
 * The Undo is an edit in the editor (editor/NoteScreen.tsx): the note's own saving writes it like typing, and the
 * editor's own undo can bring it back. The recording's sound and phrases stay as they are, as they would if the words
 * were deleted by hand, so the next recording still lines up with its sound. Pure, so each rule is a test.
 */
export interface CaptureLanding {
  /** The note that opens. */
  noteId: string;
  title: string;
  /** The pieces of text put in it, each exactly as written. */
  blocks: string[];
  /** Writes to other notes (a one-shot "add … to X"), by their `apply_command` mutation ids, for Undo to reverse. */
  others: string[];
  /** Those other notes' titles, for the toast to name. */
  into?: string[];
  /** Notes the recording made, to be filed in the workspace the list is showing. */
  made: string[];
  /** Where the recording starts on the note's tape, for Undo to drop its better words (capture/refine.ts). */
  fromMs?: number;
  /** What the recording took back at Done, unseen (liveRoute.ts `tookBackAtDone`): for the toast to name, since its Undo could not be tapped. */
  tookBack?: string[];
}

/**
 * What the note's toast says: the note the words went into, and the others; or, for a note of the take's own, the
 * others. And what a take-back settled at Done took out, so nothing goes unsaid.
 */
export function landingLine({ title, blocks, others, into = [], tookBack = [] }: CaptureLanding): string {
  const names = [...new Set(into)];
  const added = !blocks.length && names.length ? `Added to ${names.length > 2 ? `${names.slice(0, 2).join(', ')} and ${names.length - 2} more` : names.join(' and ')}` : !others.length ? `Added to ${title}` : `Added to ${title} and ${others.length === 1 ? (names[0] ?? 'one other note') : `${others.length} other notes`}`;
  if (!tookBack.length) return added;
  return `${added}. Took back “${tookBack[0]}”${tookBack.length > 1 ? ` and ${tookBack.length - 1} more` : ''}`;
}

/**
 * The edits that take `blocks` out of `doc`: each found exactly, once, nearest the line it went in at, with the line
 * break that joined it to the text above. A block that is no longer there as written - edited, or gone - is left alone
 * and counted in `missing`.
 */
export function takeOut(doc: string, blocks: readonly string[]): { changes: { from: number; to: number }[]; missing: number } {
  const changes: { from: number; to: number }[] = [];
  let missing = 0;
  for (const block of blocks) {
    if (!block) continue;
    const found: number[] = [];
    for (let at = doc.indexOf(block); at >= 0; at = doc.indexOf(block, at + 1)) {
      // A whole line or lines: starting at a line's start and ending at one's end.
      const starts = at === 0 || doc[at - 1] === '\n';
      const ends = at + block.length === doc.length || doc[at + block.length] === '\n';
      if (starts && ends) found.push(at);
    }
    if (found.length !== 1) {
      missing += 1;
      continue;
    }
    const at = found[0]!;
    // With the break before it, or, for a block that opens the note, the one after it; a paragraph's blank line too.
    let from = at;
    let to = at + block.length;
    if (at > 0) {
      from = at - 1;
      if (block.includes('\n') || !/^\s*(?:[-*+]|\d+[.)])\s/.test(block)) {
        while (from > 0 && doc[from - 1] === '\n') from -= 1;
      }
    } else if (doc[to] === '\n') {
      to += 1;
    }
    if (changes.some((change) => from < change.to && to > change.from)) {
      missing += 1;
      continue;
    }
    changes.push({ from, to });
  }
  return { changes: changes.sort((a, b) => a.from - b.from), missing };
}
