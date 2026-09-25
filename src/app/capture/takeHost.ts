import type { VoiceCommand } from '../plugins/types.ts';
import type { Placement, Plan } from './command.ts';
import type { Offer } from './offers.ts';
import type { Span, TakeCandidate, TakeNote } from './takeTypes.ts';

/**
 * What a take (capture/take.ts) asks of whoever runs it, and what it tells them.
 *
 * The take is a state machine with no screen: it decides, and its host shows and does. Two hosts run one - the
 * recorder (CaptureScreen.tsx), over the real notes, and the voice test suite (capture/voiceSuite.ts), over an
 * in-memory store - and a test of the take passes one that does nothing until told (src/test/takeHost.ts). The chip,
 * the card and the table being asked for are the host's to draw from what arrives here; the notes are the host's to
 * change when the take says yes.
 */

/** A table being asked for: its note (null for the one being recorded), its labels, its rows so far. */
export interface TableDraft<N extends TakeNote> {
  note: N | null;
  title: string;
  columns: string[];
  rows: string[][];
  lastAt: number;
}

/** What the chip at the foot of the recorder says. */
export type RouteView =
  | { phase: 'hearing'; name: string; guess: string | null; lead: 'Add to' | 'New item for' | 'Move to' | 'Start' | 'Table for' | 'Chapter for' | 'New book' }
  | { phase: 'done'; text: string }
  | { phase: 'command'; words: string; thinking?: boolean }
  | { phase: 'said'; text: string }
  | { phase: 'waiting'; title: string; many: boolean; leave: boolean }
  | { phase: 'added'; title: string; body: string; added: string[] }
  | { phase: 'moved'; title: string }
  | { phase: 'missed'; title: string }
  | { phase: 'plugin'; state: 'working' | 'done' | 'failed'; lead: string | null; title: string }
  | null;

export type Haptic = 'light' | 'selection' | 'success' | 'warning';

/** What the take asks of whoever runs it. */
export interface TakeHost<N extends TakeNote> {
  /** The notes a command can name, most recent first. */
  notes(): readonly TakeCandidate<N>[];
  /** The note this take is written onto, or null for a new one. */
  target(): N | null;
  commandWord(): boolean;
  /** Clear command-shaped full utterances may act without a wake word. */
  instructionCommands(): boolean;
  voiceCommands(): readonly VoiceCommand[];
  /** The words switched-on plugins let an item command end a note's name with ("…in Notion"). */
  itemTargets(): readonly string[];
  /** A plan the rules couldn't read, read by the phone's command model; absent where there is none. */
  understand?(words: string): { done: Promise<Plan<TakeCandidate<N>> | null>; cancel: () => void };

  route(view: RouteView): void;
  offer(offer: Offer<N> | null): void;
  table(draft: TableDraft<N> | null): void;
  /** What of a command is being heard, for the chip; empty when none. */
  itemWords(text: string): void;
  haptic(kind: Haptic): void;
  /** The take's words changed: segments, tables or the board flag. */
  changed(): void;

  /** Yes to a place offer: the words into that note. */
  addItems(note: N, spoken: string, placement: Placement): void;
  /** Yes to a change offer: that note's body rewritten. */
  changeNote(note: N, change: (body: string) => string | null, title: string): void;
  addTable(note: N, title: string, markdown: string): void;
  /** Yes to a move offer: this take's words so far go to `note` and carry on there. */
  moveTo(note: N): void;
  /** A new note from here, the words so far staying where they were said (the take is forked, `fork`); with a `title`, one already named. */
  newNote(title?: string): void;
  /** Yes to a book offer: a book note with that title and those pages, made beside this take, which carries on (docs/BOOKS.md). */
  newBook(title: string, pages: readonly string[]): void;
  /** Yes to a plugin's command: what it keeps in the note, if anything. */
  runPlugin(voice: VoiceCommand, parsed: unknown): string | null;
  describePlugin(voice: VoiceCommand, parsed: unknown): { title: string; action: string };
  /** A voice memo closed: the clip's markdown, for the stretch of this take's tape. */
  clip(span: Span): string;
  /** A line for the review's check of commands. */
  log(line: string): void;
  /** What was last said, for plugin commands ("send that to Notion"). */
  said(text: string): void;
}

/**
 * A host that is always the one `ref` holds now.
 *
 * The recorder makes its take once, but its host is new with every render, because each render's functions see that
 * render's state. So the take is given this instead, which looks each member up on the ref at the moment the take
 * uses it: a method is always the newest render's, and `understand` - there only once the phone's command model has
 * been found - is read afresh each time rather than fixed at the first render's answer. The recorder used to forward
 * every member by hand, one line each, and every member the host gained was a line to remember there as well.
 */
export function hostThrough<N extends TakeNote>(ref: { readonly current: TakeHost<N> }): TakeHost<N> {
  return new Proxy({} as TakeHost<N>, {
    get: (_, member) => ref.current[member as keyof TakeHost<N>],
  });
}
