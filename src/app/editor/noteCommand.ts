import type { EditorView } from '@codemirror/view';
import type { ToastOptions } from '@glacier/react';
import { listBody } from '../ai/instruction.ts';
import { recordChange, recordRun, recordUndone } from '../ai/log.ts';
import type { Plan } from '../capture/command.ts';
import { placeWords } from '../capture/listAppend.ts';
import type { Candidate } from '../capture/route.ts';
import type { Offer } from '../capture/take.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import { applyCommandMutation, newNoteId, noteTitle, undoCommandMutation, type Note } from '../core/store.ts';
import { addAiChanges, aiEdit, type AiChange } from './aiChanges.ts';
import { commonEnds, wisp } from './wispArrivals.ts';

/**
 * A command typed into the note's AI bar, once it is confirmed: words into a note, or a new list made.
 *
 * The bar reads what is typed through the one reader the recorder uses (ai/instruction.ts), and a command naming a note
 * is offered on the confirm card first (ai/ConfirmCard.tsx), as a spoken one is. Confirmed, it is done the way the
 * recorder does it (capture/CaptureScreen.tsx) - with one difference: words for the note that is open go into it
 * through its editor, as a tracked change the AI made (editor/aiChanges.ts), because a write to the store under an
 * open note would be flushed away by the next keystroke (editor/useNoteSaving.ts). Another note is written by the
 * guarded write, which refuses when it changed since the card was drawn, with an Undo; a new list is a new note, with
 * an Undo. Each is recorded in the AI's log (ai/log.ts), so the note it changed says the AI did, with the words asked.
 */

/** A command on a note by name, read from the bar and waiting to be confirmed (ai/instruction.ts). */
export type CommandPlan = Extract<Plan<Candidate & { note: Note }>, { kind: 'place' | 'create-list' }>;

/** The command, the card it is offered on, and the words it was read from. */
export interface CommandOffer {
  plan: CommandPlan;
  offer: Offer<Note>;
  words: string;
}

/** Where the command is confirmed: the open note and its editor, whether its words arrive from smoke, and the toasts. */
export interface CommandContext {
  note: Note;
  view: EditorView;
  wisp: boolean;
  toast: (options: ToastOptions) => void;
}

/** A command's record in the log, so the note it changed says the AI did, with the words asked. Answers its id. */
function stamp(noteId: string, words: string): string {
  const id = `cmd-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
  recordRun({ id, noteId, kind: 'ask', instruction: words, model: 'rules', at: Date.now(), ms: 0, outputTokens: 0, outcome: 'done', message: null, truncated: false });
  return id;
}

/** " and 2 more", after the first item added, when there were more. */
const more = (added: string[]) => (added.length > 1 ? ` and ${added.length - 1} more` : '');

/** Does the confirmed command, and says what it did. */
export async function confirmCommand({ plan, words }: CommandOffer, { note, view, wisp: wisping, toast }: CommandContext): Promise<void> {
  if (plan.kind === 'create-list') {
    const made = await applyCommandMutation({ mutationId: newNoteId(), noteId: newNoteId(), kind: 'create', beforeRevision: null, beforeBody: null, afterBody: listBody(plan.title, plan.items ?? []), source: 'editor' }).catch(() => null);
    if (made?.status !== 'applied') {
      toast({ message: 'That list could not be made.' });
      return;
    }
    const { mutationId } = made;
    fireNativeHaptic('success');
    toast({ message: `Made ${noteTitle(made.note.body)}.`, duration: 6000, action: { label: 'Undo', onPress: () => void undoCommandMutation(mutationId) } });
    return;
  }
  const { kind: _kind, note: named, text, ...placement } = plan;
  const target = named.note;
  if (target.id === note.id) {
    const before = view.state.doc.toString();
    const placed = placeWords(before, text, placement);
    if (!placed.added.length) return;
    const { prefix, suffix } = commonEnds(before, placed.body);
    const insert = placed.body.slice(prefix, placed.body.length - suffix);
    const id = stamp(note.id, words);
    const change: AiChange = { id: `c-${id}`, runId: id, from: prefix, to: prefix + insert.replace(/\n$/, '').length, removed: before.slice(prefix, before.length - suffix), block: true };
    view.dispatch({
      changes: { from: prefix, to: before.length - suffix, insert },
      effects: addAiChanges.of([change]),
      annotations: [aiEdit.of('land'), ...(wisping ? [wisp.of({ kind: 'heard' })] : [])],
      userEvent: 'ai.land',
    });
    recordChange(note.id, id, before, view.state.doc.toString());
    fireNativeHaptic('success');
    toast({ message: `Added “${withoutLead(placed.added[0] ?? '')}”${more(placed.added)}.` });
    return;
  }
  const placed = placeWords(target.body, text, placement);
  if (!placed.added.length) return;
  const mutationId = newNoteId();
  const result = await applyCommandMutation({ mutationId, noteId: target.id, kind: 'append', beforeRevision: target.revision ?? 1, beforeBody: target.body, afterBody: placed.body, source: target.source }).catch(() => null);
  if (result?.status !== 'applied') {
    toast({ message: `${named.title} changed after the preview, so nothing was added.` });
    fireNativeHaptic('warning');
    return;
  }
  const id = stamp(target.id, words);
  recordChange(target.id, id, target.body, result.note.body);
  fireNativeHaptic('success');
  toast({
    message: `Added “${withoutLead(placed.added[0] ?? '')}”${more(placed.added)} to ${named.title}.`,
    duration: 6000,
    action: {
      label: 'Undo',
      onPress: () =>
        void undoCommandMutation(mutationId).then((undone) => {
          if (undone.status === 'undone') recordUndone(target.id, id);
        }),
    },
  });
}
