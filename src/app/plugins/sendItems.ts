import { failureText } from '../core/failure.ts';
import { itemAt, linkedLine } from '../core/itemLinks.ts';
import type { NoteEditing } from './types.ts';

/**
 * Sending a note's list items somewhere, as the Notion and GitHub plugins do: each item becomes a thing there (a task,
 * an issue), and its words become a link to it, edited into the note so it is one undo per item and saves like
 * typing. What is made, and what is said about it afterwards, is each plugin's; the rules of the sending are here,
 * because GitHub's copy of them had fallen behind Notion's and could make two issues for one item.
 *
 * - **The same words are never made twice** (Matt: "i click it once and it says sending then nothing happens then i
 *   click it again and it fully processes creating the ticket": the task was made both times). What has just been
 *   sent from a note is remembered by the note and the words, for as long as a second press is a second press rather
 *   than a person meaning it, and sending them again marks the line with what already exists.
 * - **A made thing always gets its link.** The note can change while the service answers, so the item is found
 *   again by its words after each send and, failing that, by the line it was on if that is still an item. So the
 *   item is never left looking unsent, which is what makes a person press again.
 * - **A failure stops the run** and is said, in the service's words, before anything else is.
 */

/** How long a send is remembered: a second press within it marks the line rather than making another. */
const SENT_FOR_MS = 5 * 60 * 1000;

export interface Sent {
  /** How many were made this time. */
  sent: number;
  /** How many lines were marked, whether with something made now or something made a moment ago. */
  marked: number;
}

export interface ItemSender {
  /**
   * Sends `items` from the note on screen: `make` makes each and answers its address. Answers what was sent and
   * marked, or null when a `make` failed, which has been said on the note already.
   */
  send(items: readonly { text: string; line?: number }[], editing: NoteEditing, make: (text: string) => Promise<string>): Promise<Sent | null>;
  /** For the tests, and for a note that is closed: nothing sent outlives the app. */
  forget(): void;
}

/** A sender whose links are marked `[mark](url)` (the plugin's id, core/itemLinks.ts), with its own memory of what it sent. */
export function itemSender(mark: string): ItemSender {
  const justSent = new Map<string, { url: string; at: number }>();
  const keyOf = (noteId: string, text: string) => `${noteId}\u0000${text.trim().toLowerCase()}`;
  const alreadySent = (noteId: string, text: string, now = Date.now()): string | null => {
    const known = justSent.get(keyOf(noteId, text));
    if (!known) return null;
    if (now - known.at > SENT_FOR_MS) {
      justSent.delete(keyOf(noteId, text));
      return null;
    }
    return known.url;
  };
  /** The item's line, marked with its link: by its words, or failing that the line it was on if that is still an item. */
  const markItem = (editing: NoteEditing, item: { text: string; line?: number }, url: string): boolean => {
    const link = (text: string) => linkedLine(text, url, mark);
    if (editing.replaceLine((text, line) => itemAt(text, line)?.text === item.text, link)) return true;
    const was = item.line;
    return was !== undefined && editing.replaceLine((text, line) => line === was && itemAt(text, line) !== null, link);
  };
  return {
    async send(items, editing, make) {
      let sent = 0;
      let marked = 0;
      for (const item of items) {
        // Sent a moment ago: mark the line with what already exists rather than making a second one.
        const had = alreadySent(editing.noteId, item.text);
        if (had) {
          if (markItem(editing, item, had)) marked += 1;
          continue;
        }
        try {
          const url = await make(item.text);
          justSent.set(keyOf(editing.noteId, item.text), { url, at: Date.now() });
          sent += 1;
          if (markItem(editing, item, url)) marked += 1;
        } catch (failure) {
          editing.say(failureText(failure));
          return null;
        }
      }
      return { sent, marked };
    },
    forget() {
      justSent.clear();
    },
  };
}
