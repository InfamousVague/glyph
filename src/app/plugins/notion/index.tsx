import { SquareKanban } from '@glacier/icons';
import { fireNativeHaptic } from '../../core/haptics.ts';
import { itemAt, linkedLine, unsentItems } from '../../core/itemLinks.ts';
import { isTauri } from '../../core/tauri.ts';
import type { GlyphPlugin, NoteEditing } from '../types.ts';
import { BoardPicker } from './BoardPicker.tsx';
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

/**
 * Sends list items to Notion from the note on screen: each becomes a task on
 * `board`, and its words a link to it, edited into the note so it is one undo
 * per item and saves like typing. Items are found again by their words after
 * each send, since the note can change while Notion answers.
 */
async function sendItems(board: Board, items: readonly { text: string }[], editing: NoteEditing): Promise<void> {
  let sent = 0;
  for (const item of items) {
    try {
      const task = await createTask(board, item.text);
      if (editing.replaceLine((text, line) => itemAt(text, line)?.text === item.text, (text) => linkedLine(text, task.url))) sent += 1;
    } catch (failure) {
      editing.say(failure instanceof Error ? failure.message : String(failure));
      return;
    }
  }
  if (sent) {
    fireNativeHaptic('success');
    editing.say(`${sent === 1 ? 'Sent 1 task' : `Sent ${sent} tasks`} to ${board.title}.`);
  }
}

export const notionPlugin: GlyphPlugin = {
  manifest,
  icon: SquareKanban,
  settings: { Pane: NotionPane, summary: () => 'Boards for your lists' },
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
        if (!isTauri()) return 'Works in the Glyph app on your phone.';
        return (await notionAvailable()) ? null : 'Needs the newest Glyph. Update it in Settings.';
      },
      Picker: BoardPicker,
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
        return unsent ? `${unsent} ${unsent === 1 ? 'item isn’t' : 'items aren’t'} there yet. Each becomes a task and a link.` : 'Every item is already in Notion.';
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
  voice: [sendCommand, taskNoteCommand],
  itemTargets: [notionItems],
  tips: () => (Object.keys(boardLinks()).length ? [{ say: 'Send that to Notion', does: 'to make what you just said a task' }] : []),
};
