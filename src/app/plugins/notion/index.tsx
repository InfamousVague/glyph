import { SquareKanban } from '@glacier/icons';
import { fireNativeHaptic } from '../../core/haptics.ts';
import { unsentItems } from '../../core/itemLinks.ts';
import { isTauri } from '../../core/tauri.ts';
import { itemSender } from '../sendItems.ts';
import type { GlyphPlugin, NoteEditing } from '../types.ts';
import { BoardPicker } from './BoardPicker.tsx';
import { notionDetails } from './details.ts';
import { boardFor, boardLinks, createTask, notionAvailable, notionReadyNow, type Board } from './client.ts';
import { manifest } from './manifest.ts';
import { NotionMark } from './marks.tsx';
import { NotionPane } from './NotionPane.tsx';
import { notionItems, sendCommand, taskNoteCommand } from './voice.ts';

/**
 * The Notion plugin, standard in Glyph: a note linked to a board sends its list
 * items there as tasks, and each item's words become a link to its task.
 *
 * - On a note's cog: "Notion board" under Linked to (BoardPicker), and "Send
 *   list to Notion" once one is linked.
 * - In the note: swipe a list item left to send it.
 * - While recording: the commands in voice.ts.
 * - In Settings: signing in, and the boards Notion shared (NotionPane).
 */

/** What has just been sent from a note, so the same words are never made into two tasks (plugins/sendItems.ts). */
const sender = itemSender('notion');

/** For the tests, and for a note that is closed: nothing here outlives the app. */
export const forgetSent = sender.forget;

/**
 * Sends list items to Notion from the note on screen: each becomes a task on `board`, and its words a link to it
 * (plugins/sendItems.ts has the rules), then says how many went, or that one was made and its line has gone.
 */
async function sendItems(board: Board, items: readonly { text: string; line?: number }[], editing: NoteEditing): Promise<void> {
  const done = await sender.send(items, editing, async (text) => (await createTask(board, text)).url);
  if (!done) return;
  const { sent, marked } = done;
  if (sent || marked) {
    fireNativeHaptic('success');
    const made = sent || marked;
    editing.say(`${made === 1 ? 'Sent 1 task' : `Sent ${made} tasks`} to ${board.title}.`);
  }
  // A task was made and its words could not be found to mark: said plainly, because a silent nothing is what makes
  // a person press again.
  if (sent > marked) editing.say(`Made the task in ${board.title}, but the line has changed, so it isn’t marked.`);
}

export const notionPlugin: GlyphPlugin = {
  manifest,
  icon: SquareKanban,
  settings: { Pane: NotionPane, summary: () => 'Boards for your lists', hue: 'graphite' },
  noteLinks: [
    {
      id: 'notion-board',
      label: 'Notion board',
      icon: NotionMark,
      hint(noteId) {
        const board = boardFor(noteId);
        return board ? `Tasks go to ${board.title}.` : 'Choose where this note’s list items go as tasks.';
      },
      async unavailable() {
        if (!isTauri()) return 'Works in the Ghost.md app on your phone.';
        return (await notionAvailable()) ? null : 'Needs the newest Ghost.md. Update it in Settings.';
      },
      Picker: BoardPicker,
      linked: (noteId) => boardFor(noteId)?.title ?? null,
    },
  ],
  noteActions: [
    {
      id: 'notion-send-list',
      label: 'Send list to Notion',
      icon: NotionMark,
      visible: (noteId) => notionReadyNow() && boardFor(noteId) !== null,
      hint(_noteId, body) {
        const unsent = unsentItems(body).length;
        return unsent
          ? `${unsent} ${unsent === 1 ? 'item isn’t' : 'items aren’t'} there yet. Each becomes a task and a link.`
          : 'Every item is already in Notion.';
      },
      enabled: (_noteId, body) => unsentItems(body).length > 0,
      async run(editing) {
        const board = boardFor(editing.noteId);
        if (board) await sendItems(board, unsentItems(editing.body()), editing);
      },
    },
  ],
  itemAction: {
    id: 'notion-send-item',
    label: 'Notion',
    busyLabel: 'Sending…',
    available: (noteId) => notionReadyNow() && boardFor(noteId) !== null,
    async run(text, editing) {
      const board = boardFor(editing.noteId);
      if (board) await sendItems(board, [{ text }], editing);
    },
  },
  // The quiet "Notion" after each item not sent yet, once a board is linked.
  suggest(noteId, body) {
    const board = boardFor(noteId);
    if (!notionReadyNow() || !board) return [];
    return unsentItems(body).map((item) => ({
      line: item.line,
      label: 'Notion',
      busyLabel: 'Sending',
      run: (editing: NoteEditing) => sendItems(board, [{ text: item.text, line: item.line }], editing),
    }));
  },
  marks: notionDetails,
  voice: [sendCommand, taskNoteCommand],
  itemTargets: [notionItems],
  tips: () => (Object.keys(boardLinks()).length ? [{ say: 'Send that to Notion', does: 'to make what you just said a task' }] : []),
};
