import { createNote, deleteNote, getNote, newNoteId, updateNote as updateStoredNote, type Note } from '../core/store.ts';
import { appendBody } from './appendBody.ts';
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
 *   `appendBody(base, words)`: never the stored note, which may already hold a draft of them.
 * - A command that changes the note being recorded onto changes that base, and the words are composed onto the end of
 *   it again (`updateNote`). Applied to the stored note, which already held the words a draft had saved, they were
 *   composed on a second time at the next save (docs/DESIGN.md, the doubled words).
 *
 * Discard undoes what drafts wrote (`undoDraft`): a continued note gets its text back, a new note goes. Aiming the
 * take at another note (`aim`) starts it afresh there: that note's base is read again when first needed, and no draft
 * of it is written yet, so the first note's text is never composed under the words in the second. The screen
 * (CaptureScreen.tsx) owns what is said and shown; this owns the ids, the base and the chain, and tells the screen
 * through its host when the note being recorded onto changed, so the page can show the change land.
 */

/** A note a command can name, with the note itself, kept current by every write here. */
export type NamedNote = Candidate & { note: Note };

export interface TakeWriterHost {
  /** The take's markdown as it is saved: titled for a new note, not for words on the end of one. */
  markdown(titled: boolean): string;
  /** Whether the take holds anything a draft would write: a phrase, a table or a voice memo. */
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
  aim(note: Note | null): void {
    this.target = note;
    this.draft = null;
    this.base = null;
    this.drafted = false;
    this.noteId = note?.id ?? newNoteId();
    this.host.targetChanged(note);
  }

  /**
   * What the drafts wrote stays where it is: Discard no longer takes it back, and the base is read afresh when next
   * needed. The take carrying on elsewhere ("New note"), at once, before the note it goes on to is known.
   */
  keepDraft(): void {
    this.drafted = false;
    this.base = null;
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

  /** The body to store: this capture's markdown, below the continued note's text if there is one. */
  async compose(markdown: string): Promise<string> {
    const continued = this.target;
    if (!continued) return markdown;
    this.base ??= getNote(continued.id)
      .catch(() => null)
      .then((stored) => stored?.body ?? continued.body);
    return appendBody(await this.base, markdown);
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
        const saved = await updateStoredNote(id, appendBody(next, this.host.markdown(false)), fresh.revision ?? 1);
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
