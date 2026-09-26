import { applyCommandMutation, createNote, deleteNote, getNote, newNoteId, updateNote as updateStoredNote, type Note } from '../core/store.ts';
import { END, placeTake, type Placing } from './place.ts';
import type { Candidate } from './route.ts';

/**
 * The note a recording is written into, and every write the recorder makes to any note while it runs.
 *
 * The note is chosen at mount - a new id, or the note whose Speak was pressed - because the phone can kill the app
 * mid-sentence, and the sound is kept under that id from the first second. What is written follows three rules, each
 * learned from a bug:
 *
 * - Every write goes through one chain (`queue`), in turn. Two close together used to read the same body and the
 *   second lost the first.
 * - A continued note's own text is read from the store once, when first needed, into a promise (`baseBody`), so two
 *   drafts racing both compose onto the text from BEFORE either of them wrote, and the take's words are always
 *   `placeTake(base, words, placing)` (place.ts): never the stored note, which may already hold a draft of them.
 * - A command that changes the note being recorded onto changes that base, and the words are composed onto the end of
 *   it again (`updateNote`). Applied to the stored note, which already held the words a draft had saved, they were
 *   composed on a second time at the next save (docs/DESIGN.md, the doubled words).
 *
 * Discard undoes what drafts wrote (`undoDraft`): a continued note gets its text back, a new note goes. Aiming the
 * take at another note (`aim`) starts it afresh there: that note's base is read again when first needed, and no draft
 * of it is written yet, so the first note's text is never composed under the words in the second. The screen
 * (CaptureScreen.tsx) owns what is said and shown; this owns the ids, the base and the chain, and tells the screen
 * through its host when the note being recorded onto changed, so the page can show the change land.
 *
 * Where the words go in the note is its `placing` (place.ts): the end, for a new note and for a note's own Speak as it
 * always was, or the lists of a note whose title says it holds them. A note the live reader switched the take to
 * (liveRoute.ts) is written once, at Done, by `writeInto`: read fresh, the words placed into it, and stored through
 * `apply_command`, which checks the body and the revision, so nothing typed or synced meanwhile is overwritten.
 */

/** A note a command can name, with the note itself, kept current by every write here. */
export type NamedNote = Candidate & { note: Note };

export interface TakeWriterHost {
  /** The take's markdown as it is saved: titled for a new note, not for words on the end of one. */
  markdown(titled: boolean): string;
  /** Whether the take holds anything a draft would write: a phrase or a voice memo. */
  hasWords(): boolean;
  /** The notes a command can name; each written note's copy there is replaced by what was stored. */
  candidates(): readonly NamedNote[];
  /** The note being recorded onto changed, or became another, or none: for the page to show it. */
  targetChanged(note: Note | null): void;
}

export class TakeWriter {
  /** The note being written: a new id, or the note this capture continues. */
  noteId = newNoteId();
  /** The note this capture is being added to, if it continues one. */
  target: Note | null = null;
  /**
   * The continued note's text before this capture, read from the store once, when first needed - after the editor
   * that may have been open has flushed its last keystrokes. A promise, so two drafts racing both get the text from
   * BEFORE either of them wrote.
   */
  private base: Promise<string> | null = null;
  /** A draft has been written since the take last began, which Discard (`undoDraft`) takes back. */
  private drafted = false;
  /** The stored row of a new capture's draft, once one is made: later drafts are revision-checked edits of it. */
  private draft: Note | null = null;
  /** Every write to a note, in turn: a command's change, the draft, the take carrying on elsewhere. */
  private chain: Promise<unknown> = Promise.resolve();
  /** Where the words go in the note being written: the end, or its lists (place.ts). */
  placing: Placing = END;
  /** The note was switched to by a command, not opened from its own Speak: it is written by `writeInto` at Done. */
  routed = false;
  /** A switched-to note read fresh, for its tape and phrases, which the candidate it was found as lacks. */
  private refreshing: Promise<unknown> = Promise.resolve();

  constructor(private readonly host: TakeWriterHost) {}

  /** The continued note's text before this capture, once a draft or a command has read it; null until then. */
  get baseBody(): Promise<string> | null {
    return this.base;
  }

  /** Whether a draft has been written since the take last began (on this note), which Discard takes back. */
  get savedDraft(): boolean {
    return this.drafted;
  }

  /**
   * The take is written into `note` from here, or into a new note with a fresh id when it is null. It begins afresh
   * there: the base is `note`'s, read when first needed, and nothing written to the note before is this take's draft
   * to take back.
   */
  aim(note: Note | null, placing: Placing = END, { routed = false }: { routed?: boolean } = {}): void {
    this.target = note;
    this.draft = null;
    this.base = null;
    this.drafted = false;
    this.placing = placing;
    this.routed = routed && note !== null;
    this.noteId = note?.id ?? newNoteId();
    this.host.targetChanged(note);
  }

  /**
   * The note aimed at, read again from the store in the background: a candidate carries no tape or phrases, which the
   * sound kept at Done lines up with. It replaces `target` only while the take is still aimed there. Synchronous to
   * call, so a phrase committed straight after a switch lands in the new note; Done waits for it (`refreshed`).
   */
  refresh(id: string): void {
    this.refreshing = this.refreshing.then(async () => {
      const full = await getNote(id).catch(() => null);
      if (full && this.target?.id === id) {
        this.target = full;
        this.host.targetChanged(full);
      }
    });
  }

  /** Every `refresh` asked for so far, done. */
  refreshed(): Promise<unknown> {
    return this.refreshing;
  }

  /**
   * What the drafts wrote stays where it is: Discard no longer takes it back, and the base is read afresh when next
   * needed. The take carrying on elsewhere ("New note"), at once, before the note it goes on to is known.
   */
  keepDraft(): void {
    this.drafted = false;
    this.base = null;
  }

  /** How the words go into the note being written changed: a heading said for them, or a to-do. */
  setPlacing(placing: Placing): void {
    this.placing = placing;
  }

  /** A command changed the note being recorded onto, outside `updateNote`: its new body is the base the words go under. */
  rebase(note: Note): void {
    if (this.target?.id !== note.id) return;
    this.target = note;
    this.base = Promise.resolve(note.body);
    this.host.targetChanged(note);
  }

  /** Every write asked for so far, done: what Done waits on before it writes the note itself. */
  settled(): Promise<unknown> {
    return this.chain;
  }

  /** A write to a note, after every write before it, whether that one worked or not. */
  queue<T>(run: () => Promise<T>): Promise<T> {
    const done = this.chain.then(run, run);
    this.chain = done.catch(() => undefined);
    return done;
  }

  /** The body to store: this capture's markdown in the continued note's text, where its placing says, if there is one. */
  async compose(markdown: string): Promise<string> {
    const continued = this.target;
    if (!continued) return markdown;
    this.base ??= getNote(continued.id)
      .catch(() => null)
      .then((stored) => stored?.body ?? continued.body);
    return placeTake(await this.base, markdown, this.placing).body;
  }

  /**
   * The take's words into `note`, an existing note, once: read fresh, placed where `placing` says, and stored through
   * `apply_command` (a compare-and-swap on the body and the revision). A conflict - the note changed between the read
   * and the write - reads and places once more; a second, or a note deleted meanwhile, makes the words a note of their
   * own (`fallback`, titled), so they are never lost and never overwrite anyone's edit.
   */
  writeInto(
    note: { id: string },
    markdown: string,
    placing: Placing,
    fallback: () => string,
  ): Promise<{ saved: Note; before: string | null; blocks: string[]; spot: string | null; mutationId: string | null; own: boolean }> {
    return this.queue(async () => {
      for (let attempt = 0; attempt < 2; attempt += 1) {
        const fresh = await getNote(note.id).catch(() => null);
        if (!fresh) break;
        const placed = placeTake(fresh.body, markdown, placing);
        if (placed.body === fresh.body) return { saved: fresh, before: fresh.body, blocks: [], spot: placed.spot, mutationId: null, own: false };
        const mutationId = newNoteId();
        const result = await applyCommandMutation({
          mutationId,
          noteId: fresh.id,
          kind: 'append',
          beforeRevision: fresh.revision ?? 1,
          beforeBody: fresh.body,
          afterBody: placed.body,
          source: fresh.source,
        }).catch(() => null);
        if (result?.status === 'applied') {
          this.remember(result.note);
          if (this.target?.id === result.note.id) this.target = result.note;
          return { saved: result.note, before: fresh.body, blocks: placed.blocks, spot: placed.spot, mutationId, own: false };
        }
      }
      const made = await createNote(newNoteId(), fallback(), 'capture');
      return { saved: made, before: null, blocks: [], spot: null, mutationId: null, own: true };
    });
  }

  /** Stores `body` as note `id`: a birth, or a revision-checked edit of a note this capture knows; never an upsert of a missing id. */
  async persist(id: string, body: string, source: Note['source'] = 'capture'): Promise<Note> {
    const known = this.target?.id === id ? this.target : this.draft?.id === id ? this.draft : null;
    const saved = known ? await updateStoredNote(id, body, known.revision ?? 1) : await createNote(id, body, source);
    if (this.target?.id === id) {
      this.target = saved;
      this.host.targetChanged(saved);
    } else if (this.noteId === id) {
      this.draft = saved;
    }
    this.remember(saved);
    return saved;
  }

  /** The words so far, written to the note they were said for now rather than waiting for Done. */
  async flushDraft(): Promise<void> {
    if (!this.host.hasWords()) return;
    await this.queue(async () => {
      this.drafted = true;
      const body = await this.compose(this.host.markdown(!this.target));
      await this.persist(this.noteId, body, 'capture');
    });
  }

  /** Undoes whatever drafts wrote: the continued note gets its text back, a new note goes. */
  async undoDraft(): Promise<void> {
    if (!this.drafted) return;
    this.drafted = false;
    await this.chain.catch(() => undefined);
    const continued = this.target;
    if (continued) await this.persist(continued.id, (await this.base) ?? continued.body, continued.source);
    else await deleteNote(this.noteId);
  }

  /**
   * A note's body rewritten by `change`, in turn with every other write: the new body, or null when there is no such
   * note or the change changed nothing.
   *
   * The note being recorded onto is the special case: the change goes into the note as it was before this take's
   * words, and the words are composed onto the end of that again. Applied to the stored note, which already holds the
   * words a draft saved, they were composed on a second time at the next save.
   */
  updateNote(id: string, change: (body: string) => string | null): Promise<string | null> {
    return this.queue(async () => {
      const fresh = await getNote(id);
      if (!fresh) return null;
      const continued = this.target;
      if (continued?.id === id) {
        // No draft composed yet means the store holds the note as it was; otherwise the base is what drafts build on.
        const base = await (this.base ??= Promise.resolve(fresh.body));
        const next = change(base);
        if (next === null || next === base) return null;
        this.base = Promise.resolve(next);
        const updated = { ...fresh, body: next };
        this.target = updated;
        // The page shows the change land, in its place above the words being said.
        this.host.targetChanged(updated);
        const known = this.named(id);
        if (known) known.note = updated;
        const saved = await updateStoredNote(id, placeTake(next, this.host.markdown(false), this.placing).body, fresh.revision ?? 1);
        this.target = saved;
        if (known) known.note = saved;
        return next;
      }
      const body = change(fresh.body);
      if (body === null || body === fresh.body) return null;
      const saved = await updateStoredNote(id, body, fresh.revision ?? 1);
      this.remember(saved);
      return body;
    });
  }

  /** The command list's copy of note `id`, if it has one. */
  private named(id: string): NamedNote | undefined {
    return this.host.candidates().find((candidate) => candidate.id === id);
  }

  /** `saved` in place of the command list's copy of it, so the next command reads what is stored. */
  remember(saved: Note): void {
    const known = this.named(saved.id);
    if (known) known.note = saved;
  }
}
