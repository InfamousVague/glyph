import { noteTitle } from '../core/noteTitle.ts';
import { appendBody } from './appendBody.ts';
import { listTitle } from './instructionMutation.ts';
import { inOrder, LiveRoute, withoutWords, type CardChoice, type LiveCard, type LiveStep } from './liveRoute.ts';
import { renderNote, type Segment } from './markdown.ts';
import { END, placeTake, placingFor, type Placing } from './place.ts';
import type { RouteView } from './takeHost.ts';
import type { Span } from './takeTypes.ts';

/**
 * A recording's notes as the live reader (liveRoute.ts) leaves them, over notes held in memory: the recorder's
 * bookkeeping without its screen, its microphone or its store. The voice suite (voiceSuite.ts) plays each script
 * through it, and the live reader's tests read what a recording would write from it; the recorder
 * (CaptureScreen.tsx) applies the same steps to its take and its writer, and writes the same bodies at Done, since both
 * compose with `placeTake`.
 */

export interface MemoryNote {
  id: string;
  body: string;
}

interface Written {
  /** The note the words are for; null for a note of their own, made at Done. */
  note: MemoryNote | null;
  /** A note of their own by name ("New note “House chores”"). */
  title: string | null;
  placing: Placing;
  segments: Segment[];
}

export interface LiveTakeOptions {
  keywordOn?: boolean;
  /** The note whose own Speak this is. */
  own?: MemoryNote | null;
  locked?: boolean;
  published?: (id: string) => boolean;
}

export class LiveTake {
  readonly live = new LiveRoute<MemoryNote>();
  /** The take's words, for the note it is aimed at now. */
  segments: Segment[] = [];
  aim: MemoryNote | null;
  /** A note of the take's own, to be made at Done with this title. */
  pendingTitle: string | null = null;
  placing: Placing;
  /** What was said before "New note", for the note it was said for. */
  parts: Written[] = [];
  inserts = new Map<number, Written>();
  card: LiveCard<MemoryNote> | null = null;
  chips: RouteView[] = [];
  asks: { run: string | null; instruction: string }[] = [];
  log: string[] = [];
  commandSpans: Span[] = [];
  keywordSpans: Span[] = [];
  /** The one-shots closed (`insert-end`), in order: the recorder shows each one's lines then. */
  ended: number[] = [];
  routed = false;

  constructor(
    private notes: MemoryNote[],
    private readonly options: LiveTakeOptions = {},
  ) {
    this.aim = options.own ?? null;
    this.placing = options.own ? placingFor(options.own.body, { own: true }) : END;
  }

  private ctx() {
    return {
      notes: this.notes.map((note) => ({ id: note.id, title: noteTitle(note.body), note })).filter((c) => c.title),
      aim: this.aim,
      own: Boolean(this.options.own),
      keywordOn: this.options.keywordOn ?? true,
      locked: this.options.locked ?? false,
      published: this.options.published,
    };
  }

  phrase(segment: Segment, now: number): void {
    this.apply(this.live.phrase(segment, this.ctx(), now));
  }

  tick(now: number): void {
    this.apply(this.live.tick(now, this.ctx()));
  }

  answer(choice: CardChoice): void {
    if (this.card) this.apply(this.live.answer(this.card.id, choice, this.ctx()));
  }

  decline(now: number): void {
    this.apply(this.live.decline(this.ctx(), now));
  }

  close(now: number): void {
    this.apply(this.live.close(this.ctx(), now));
  }

  /** A take-back's Undo, tapped. */
  undo(id: number): void {
    this.apply(this.live.undoTakeBack(id));
  }

  /** "New note", tapped: as the recorder's `startNewNote` does it, the reader told first. */
  forked(): void {
    this.apply(this.live.forked());
    this.apply([{ kind: 'new-note' }]);
  }

  apply(steps: readonly LiveStep<MemoryNote>[]): void {
    for (const step of steps) {
      switch (step.kind) {
        case 'words':
          this.segments = inOrder([...this.segments, step.segment]);
          break;
        case 'unword':
          this.segments = withoutWords(this.segments, step.segments);
          break;
        case 'command':
          this.commandSpans.push(step.span);
          break;
        case 'keyword':
          this.keywordSpans.push(step.span);
          break;
        case 'route':
          this.aim = step.note;
          this.pendingTitle = null;
          this.placing = step.placing;
          this.routed = true;
          break;
        case 'route-new':
          this.aim = null;
          this.pendingTitle = step.title;
          this.placing = placingFor(listTitle(step.title), { said: { task: step.task } });
          this.routed = true;
          break;
        case 'home':
          this.aim = this.options.own ?? null;
          this.pendingTitle = null;
          this.placing = this.options.own ? placingFor(this.options.own.body, { own: true }) : END;
          this.routed = false;
          break;
        case 'placing':
          this.placing = step.placing;
          break;
        case 'insert':
          this.inserts.set(step.id, { note: step.note, title: null, placing: step.placing, segments: [...step.segments] });
          break;
        case 'insert-words': {
          const insert = this.inserts.get(step.id);
          if (insert) insert.segments.push(...step.segments);
          break;
        }
        case 'insert-unword': {
          const insert = this.inserts.get(step.id);
          if (insert) insert.segments = withoutWords(insert.segments, step.segments);
          break;
        }
        case 'insert-end':
          this.ended.push(step.id);
          break;
        case 'insert-drop': {
          const insert = this.inserts.get(step.id);
          this.inserts.delete(step.id);
          if (insert) this.segments = inOrder([...this.segments, ...insert.segments]);
          break;
        }
        case 'new-note':
          this.parts.push({ note: this.aim, title: this.pendingTitle, placing: this.placing, segments: this.segments });
          this.segments = [];
          this.aim = null;
          this.pendingTitle = null;
          this.placing = END;
          this.routed = false;
          break;
        case 'card':
          this.card = step.card;
          break;
        case 'ask':
          this.asks.push({ run: step.run, instruction: step.instruction });
          break;
        case 'chip':
          if (step.view) this.chips.push(step.view);
          break;
        case 'log':
          this.log.push(step.line);
          break;
        default:
          break;
      }
    }
  }

  /** The words for one note, as Done writes them. */
  private written(into: Written, bodies: Map<string, string>): { id: string | null; body: string } {
    const titled = into.note === null && into.title === null;
    const markdown = renderNote(into.segments, '', { titled }).markdown;
    if (into.note) {
      const base = bodies.get(into.note.id) ?? into.note.body;
      return { id: into.note.id, body: placeTake(base, markdown, into.placing).body };
    }
    if (into.title) return { id: null, body: placeTake(listTitle(into.title), markdown, into.placing).body };
    return { id: null, body: markdown };
  }

  /**
   * What the recording leaves: every existing note's body by id, and the notes it made, in order (the take's own
   * first when it has words). Written as Done writes: the parts, then the one-shots, then the take's own aim.
   */
  result(): { bodies: Map<string, string>; made: string[] } {
    const bodies = new Map(this.notes.map((note) => [note.id, note.body]));
    const made: string[] = [];
    const write = (into: Written) => {
      if (!renderNote(into.segments).markdown.trim() && into.note) return;
      const { id, body } = this.written(into, bodies);
      if (id) bodies.set(id, body);
      else if (body.trim()) made.push(body);
    };
    for (const part of this.parts) write(part);
    for (const insert of this.inserts.values()) write(insert);
    write({ note: this.aim, title: this.pendingTitle, placing: this.placing, segments: this.segments });
    return { bodies, made };
  }

  /** The body of note `id` after the recording. */
  body(id: string): string | undefined {
    return this.result().bodies.get(id);
  }

  /** The page as it reads now: the note aimed at with the words where they go. */
  page(): string {
    const markdown = renderNote(this.segments, '', { titled: this.aim === null && this.pendingTitle === null }).markdown;
    if (this.aim) return placeTake(this.aim.body, markdown, this.placing).body;
    if (this.pendingTitle) return placeTake(listTitle(this.pendingTitle), markdown, this.placing).body;
    return appendBody('', markdown);
  }
}
