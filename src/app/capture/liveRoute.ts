import { runOf } from '../ai/instruction.ts';
import type { RunKind } from '../ai/kinds.ts';
import { isBookBody } from '../book/book.ts';
import { capitalise } from '../core/text.ts';
import { findKeyword, onlyFiller, PAYLOAD_LEAD } from './command.ts';
import { bareCommand, bareShape, commandWords, hearKeyword, isOpener, misheardShape, namedAs, onlyFillerPhrase, onlyLead, payloadOf, readNameFirst, readRoute, silenceLine, withoutFinalStop, type Reading } from './liveCommand.ts';
import { runsOf, semanticListKind } from './listAppend.ts';
import { renderNote, splitSentences, type Segment } from './markdown.ts';
import { FIND, findNote, headingIn, nameWords, titleKind, type Found } from './noteFind.ts';
import { placeTake, placingFor, type Placing } from './place.ts';
import { commandAfterOpener, contentWords, corrects, cuePrefixOf, opensSend, quoted, readSend, readTakeBack, swapWord, type TakeBack } from './takeBack.ts';
import type { RouteView } from './takeHost.ts';
import type { Span } from './takeTypes.ts';

/**
 * The live reader: a committed phrase read as it is said, for one family of command, "words for a note you name".
 *
 * Matt: "It should first step try to find a note that the person is talking about … then when it's found that note,
 * it should look through the note and see what different things I could be talking about adding to … then it should
 * modify that note, open the note, and start live writing to that note instead of doing the second pass over at the
 * end." Since PR #1 a phrase only showed on the page and the one command in a recording was read at Done, from the
 * whole transcript; this reads again at each commit, for these commands only:
 *
 * - "Hey Ghost, add a note to House TODOs. Call an electrician." At the start of a fresh recording the recorder
 *   switches to that note, for good (`route`): its page shows the note, and what is said is written into its list.
 * - Mid-take, or on a note's own Speak, "add call Sam to House TODOs" puts those words there (`insert`) and the take
 *   carries on where it was. "Move this to …" is the one command that moves the take. "Add call the plumber to House
 *   TODOs", with no keyword at all, does the same (`bare`).
 * - "Remind me to…", "add a to-do: …": a to-do in the note being written to (`self`). "New note": a fresh one.
 * - "Scratch that", "actually, …", "no wait, four" and "scratch that, add it to X instead" take back the last thing
 *   said in this take: gone, replaced, one word changed, or sent to a note named (`takeBack`, docs/DESIGN.md §130).
 *   "Hey Ghost, actually, add a note to X" is that command, said as people say it.
 *
 * Nothing it does is stored: the recorder draws the words where they will go, and Done writes each note once, fresh,
 * through `apply_command` (CaptureScreen.tsx `finish`). So a wrong switch is seen, and put right with Not this note
 * (`decline`), Discard or Undo; nothing has to be taken back from the store. It never deletes or replaces text it did
 * not write in this take. A take-back takes back the last thing this take said, shows what went with Undo, never
 * engages the reader, and stores nothing, since nothing is stored before Done; it never runs a table, a board, a book,
 * a plugin or an AI run; a run or an ask said mid-take is queued for after Done.
 *
 * A phrase is read whether or not it opens with the keyword (docs/DESIGN.md §136). Without it, only a command plainly
 * about a note it names clearly, with its words in the same breath, is one, through one gate (liveCommand.ts
 * `bareCommand`, asked by `clear`); anything short of that is words, untouched. The keyword adds what a bare phrase
 * never gets: a card for an unsure or missing name, a hold for an opener waiting for its name, an ask or a run, the
 * name-first shapes ("For Groceries, …"), a heading or lane of the note being written to, a command said in pieces,
 * and the take-back waiver of §130. An unsure name, or one that matches nothing but comes near a title, gets a card
 * after the keyword; no card blocks anything, since each takes Keep here after a while, and at once when the recording
 * ends (`close`).
 *
 * A state machine with its own clock handed in, and no screen: the recorder applies its steps. Pure, so every rule is
 * a test.
 */

/** The live reader's timings, in ms. */
export const LIVE_TIMING = {
  /** A command held for its name: this long after its last phrase, and it gives up. */
  holdMs: 4500,
  /** The most phrases a held command waits for its name. */
  holdPhrases: 3,
  /** A name that may still be growing: the next phrase, said this soon after it on the recording, is read with it. */
  growMs: 2500,
  /** A one-shot with nothing said for it: its phrases until a pause this long. */
  itemsQuietMs: 2500,
  /** And at most this many of them. */
  itemsPhrases: 3,
  /** A card up this long takes its default, Keep here. */
  cardMs: 8000,
  /**
   * A take-back's Undo: this long on the reader's clock, then it settles and its stretches are marked for the better
   * words. Longer than the chip's four seconds (chip.ts), so a button drawn is a button that works.
   */
  takeBackMs: 5000,
  /** A resolved name must score this well to route with no keyword said, or after a mishearing of it: the alias of FIND.clear. */
  bareScore: FIND.clear,
  /**
   * A name that ran to the end of what was said, and is longer than this many words, is more than a title: Keep here
   * gives back all of it ("add a note to moon base pack sunscreen and the tent").
   */
  nameWords: 4,
} as const;

export interface LiveNote {
  id: string;
  body: string;
}

/** A note a command can name, as the recorder's candidates carry it (capture/candidates.ts). */
export interface LiveCandidate<N extends LiveNote> {
  id: string;
  title: string;
  note: N;
}

export interface LiveContext<N extends LiveNote> {
  notes: readonly LiveCandidate<N>[];
  /** The note being written to now, or null for the take's own new note. */
  aim: N | null;
  /** The take is a note's own Speak, and `aim` is that note. */
  own: boolean;
  /** Over the lock screen: no card, no title said, and no shared note is written to. */
  locked: boolean;
  /** Whether a note is shared, or is a chapter of a shared book (share/share.ts). */
  published?: (id: string) => boolean;
}

/** A card: which note, when the name was unsure or matched none. */
export interface LiveCard<N extends LiveNote> {
  id: number;
  form: 'unsure' | 'missing' | 'declined';
  /** "Add to which note?", "No note called “the moon base”", "Not added to House TODOs". */
  heading: string;
  /** The notes to choose between. */
  candidates: LiveCandidate<N>[];
  /** The title "New note “…”" would make. */
  newTitle: string;
  /** What would land, for the card to show. */
  payload: string;
}

export type CardChoice = { kind: 'note'; id: string } | { kind: 'new' } | { kind: 'keep' };

/** What the recorder does with a phrase, in order. */
export type LiveStep<N extends LiveNote> =
  /** Words of the take, drawn and saved with it. `payload` marks what a command sent. */
  | { kind: 'words'; segment: Segment; payload?: boolean }
  /** Words of the take given back out of it, to go elsewhere (a card answered for a one-shot). */
  | { kind: 'unword'; segments: Segment[] }
  /** A stretch that was a command, for the better words to leave out. */
  | { kind: 'command'; span: Span }
  /** A phrase that was words and then the keyword: the better words keep what came before it. */
  | { kind: 'keyword'; span: Span }
  /** The take goes to `note` from here, words so far and all: sticky, until "move this", "new note" or Not this note. */
  | { kind: 'route'; note: N; title: string; placing: Placing; move: boolean; spot: string | null }
  /** The take goes to a note that does not exist yet, made at Done with this title ("New note “House chores”"). */
  | { kind: 'route-new'; title: string; task: boolean }
  /** The take's own note again (Not this note). */
  | { kind: 'home' }
  /** How the words go into the note being written to changed: a heading said for it, or a to-do. */
  | { kind: 'placing'; placing: Placing }
  /** A one-shot opened for `note`: `segments` go there, not into the take. More may follow (`insert-words`). */
  | { kind: 'insert'; id: number; note: N; title: string; placing: Placing; segments: Segment[] }
  | { kind: 'insert-words'; id: number; segments: Segment[] }
  /** Words given to a one-shot, taken out of it again (a take-back or its Undo); a one-shot with nothing left is not written. */
  | { kind: 'insert-unword'; id: number; segments: Segment[] }
  /** A one-shot closed: the take carries on where it was. */
  | { kind: 'insert-end'; id: number }
  /** A one-shot taken out again (its Not this note): its words back into the take, at their time. */
  | { kind: 'insert-drop'; id: number }
  /** "New note": the words so far stay with the note they were said for, and a fresh note starts. */
  | { kind: 'new-note' }
  | { kind: 'card'; card: LiveCard<N> | null }
  /** A run or an ask, for the note that opens after Done. */
  | { kind: 'ask'; run: RunKind | null; instruction: string }
  /** What the chip at the foot says. */
  | { kind: 'chip'; view: RouteView }
  | { kind: 'haptic'; haptic: 'light' | 'selection' | 'success' | 'warning' }
  /** A line for the review's check of commands, and the take's log. */
  | { kind: 'log'; line: string };

interface Held {
  segments: Segment[];
  /** The keyword was said in the first of them, or they are only its lead ("Hey."), or only filler ("Okay."). */
  why: 'keyword' | 'lead' | 'filler' | 'unsure';
  lastAt: number;
  /** The name heard so far, for the chip: "Looking for “house”". */
  name?: string;
}

interface Pending<N extends LiveNote> {
  card: LiveCard<N>;
  since: number;
  /** The command phrase the card holds. */
  command: Segment;
  payload: string;
  reading: Reading;
  /** The take was at its start: a choice is sticky. */
  atStart: boolean;
  /** Phrases said since, which went to the page as words. */
  after: Segment[];
  /** A card after Not this note: the note declined, and the name it was declined for. */
  declined?: { id: string; name: string };
  /**
   * A take-back's send that was not sure of its note: the words are on the page while it asks (`after` holds them),
   * and Keep here puts them back where they were, a one-shot's into it (`from`), and says so.
   */
  stays?: { text: string; after: Segment[]; from: Placed['where'] };
}

interface Opened<N extends LiveNote> {
  id: number;
  note: N;
  title: string;
  count: number;
  lastAt: number;
  /** The command's words as heard, the stop off, for the chip that cancels it. */
  words: string;
}

/** Words the reader put somewhere in this take: on the page (the take) or into a one-shot. */
interface Placed {
  where: { kind: 'take' } | { kind: 'insert'; id: number };
  segment: Segment;
  /** The source phrase: where it went and its stretch, so an enumeration's items are one thing. */
  from: string;
}

/** The last take-back, undoable until it settles. */
interface TookBack {
  id: number;
  /** The opener and its rest as said, keyword and head off: what Undo writes as words, on the phrase's stretch. */
  phrase: Segment;
  /** "Hey Ghost" was said before the opener: Undo marks the stretch `keyword`, as `read` marks one, so the better words leave it out. */
  keyed: boolean;
  /** The head came before the keyword: the phrase is marked `keyword` at settle, else `command`. */
  headBeforeKeyword: boolean;
  /** What came off the page or out of a one-shot, in order: one source phrase's group. */
  removed: Placed[];
  /** What went, as it would move on a send: the last sentence alone when the phrase held several. */
  taken: Segment[];
  /** What it put in their place: a phrase cut short of its last sentence, a replacement, a changed sentence, re-placed items. */
  placed: Placed[];
  outcome: 'gone' | 'sent' | 'placed' | 'changed' | 'replaced';
  /** A bare drop, nothing said after the opener, or only a send's opener: a send in the next breath is its second half. */
  dropOnly: boolean;
  /** A send's opener Whisper cut from its name ("Scratch that, add it to" | "Groceries instead."): never written, the name read with it. */
  fragment: string | null;
  /** A send: the one-shot it made. */
  sent: { id: number; title: string } | null;
  /** A phrase the reader at Done was to read, taken out of `doneReader`: back there on Undo. */
  doneReader: { segments: Segment[]; words: string } | null;
  /** What went, as the chip said it, for the landing when Done settles it unseen. */
  quote: string;
  /** A send said in a breath of its own: its phrase, marked with the take-back's when it settles. */
  sends?: Segment[];
  since: number;
}

interface Growing<N extends LiveNote> {
  reading: Reading;
  score: number;
  command: Segment;
  /** The command's words as heard, the stop gone, to be read again with the next phrase. */
  words: string;
  /** Where the name went: the route, or the one-shot. */
  into: { kind: 'route' } | { kind: 'insert'; id: number };
  note: N;
}

/** What `command` answers when it holds the phrase for its name, or leaves it to the reader at Done. */
const HELD = Symbol('held');
const DONE_READER = Symbol('done-reader');

/** A stretch of a segment. */
const spanOf = (segment: Segment): Span => ({ startMs: segment.startMs, endMs: segment.endMs });

/** Whether two phrases are the one phrase: the same stretch and the same words (`withoutWords` knows them so). */
const same = (a: Segment, b: Segment): boolean => a.startMs === b.startMs && a.endMs === b.endMs && a.text === b.text;

/** The source phrase a placed segment came from: where it went, and the stretch it was said over. */
const fromOf = (where: Placed['where'], segment: Segment): string => `${where.kind === 'insert' ? `insert ${where.id}` : 'take'}|${segment.startMs}-${segment.endMs}`;

/** What a chip can hold of a sentence. */
const cut = (text: string): string => (text.length > 40 ? `${text.slice(0, 40)}…` : text);

/** A phrase's stretch, marked as a command's for the better words. */
const spanStep = <N extends LiveNote>(segment: Segment): LiveStep<N> => ({ kind: 'command', span: spanOf(segment) });

/** A held command's words as heard, joined, the keyword and the lead-ins gone, the stop off: '' for the keyword alone. */
function heldWords(held: Held): string {
  const joined = held.segments.map((s, i) => (i < held.segments.length - 1 ? withoutFinalStop(s.text) : s.text)).join(' ');
  return withoutFinalStop(commandWordsOf(joined));
}

/**
 * A take's words in the order they were said. A card's words land when it settles, after what was said while it was
 * up, so they can arrive out of order; the sort is stable, so the pieces of one phrase keep theirs. The same array
 * when nothing moved.
 */
export function inOrder(segments: readonly Segment[]): Segment[] {
  const ordered = segments.every((segment, i) => i === 0 || segments[i - 1]!.startMs <= segment.startMs);
  return ordered ? (segments as Segment[]) : [...segments].sort((a, b) => a.startMs - b.startMs);
}

/** A take's words without `gone` (an `unword` step), each known by its stretch and its words. */
export function withoutWords(segments: readonly Segment[], gone: readonly Segment[]): Segment[] {
  return segments.filter((segment) => !gone.some((g) => same(g, segment)));
}

/** Words as a sentence: first letter up, a stop at the end. */
function sentence(text: string): string {
  const said = capitalise(text.trim());
  return !said || /[.!?…:]$/.test(said) ? said : `${said}.`;
}

/**
 * A payload as the take's words: one sentence; or, said as a short enumeration ("milk, eggs and bread") or as an
 * item of a list, the cue-marked items the renderer lays out as a list ("Check box: call Sam.", capture/markdown.ts),
 * each on the command phrase's stretch of the recording.
 */
export function payloadWords(whole: Segment, payload: string, { item = false, task = false }: { item?: boolean; task?: boolean } = {}): Segment[] {
  const words = payloadOf(payload).trim();
  const said = words.replace(/[\s.!?…]+$/, '');
  if (!said) return [];
  const pieces = /,/.test(said) ? said.split(/\s*(?:,|\band\b)\s*/i).map((piece) => piece.trim()).filter(Boolean) : [];
  const listed = pieces.length >= 2 && pieces.every((piece) => piece.split(/\s+/).length <= 4) ? pieces : null;
  // As it was said: a phrase Whisper cut before its stop runs on into the next ("…fix the light" | "sockets.").
  if (!listed && !item) return [{ ...whole, text: capitalise(words) }];
  const cue = task ? 'Check box' : 'Bullet point';
  return (listed ?? [said]).map((piece) => ({ ...whole, text: `${cue}: ${piece}.` }));
}

/** What a command said of the words it sent, for where they go (place.ts `placingFor`): a to-do, or a paragraph. */
function saidOf(reading: Reading): { task: boolean; paragraph: boolean } {
  return { task: reading.placing === 'task', paragraph: reading.placing === 'paragraph' };
}

/** The first two lines of what would land, lead-ins gone, for a card to show. */
function shown(payload: string): string {
  return payloadOf(payload).split(/(?<=[.!?])\s+/).slice(0, 2).join(' ');
}

/** "the moon base" as the title a new note for it would take: "Moon base". */
function titleFor(name: string): string {
  return capitalise(
    name
      .trim()
      .replace(/^(?:(?:the|my|our|a)\s+)+/i, '')
      .replace(/[.!?]+$/, ''),
  );
}

/**
 * What stays here when a name finds no note: the payload; or, when the name ran to the end of what was said and is
 * longer than a title, everything said after the verb, since the grammar cannot tell where such a name ends ("add a
 * note to moon base pack sunscreen and the tent" keeps "Moon base pack sunscreen and the tent.").
 */
function keptWords(reading: Reading, payload: string): string {
  if (reading.stopped || reading.nameFirst || reading.split || !reading.tail) return payload;
  // Ended as a sentence, as the phrase it was the end of was.
  return reading.name.split(/\s+/).length > LIVE_TIMING.nameWords ? sentence(payloadOf(reading.tail)) : payload;
}

export class LiveRoute<N extends LiveNote> {
  private engagedYet = false;
  private closed = false;
  private held: Held | null = null;
  private pending: Pending<N> | null = null;
  private opened: Opened<N> | null = null;
  private growing: Growing<N> | null = null;
  /** The note the take was routed to, sticky: `awaiting` while nothing has been said for it yet; `words` for the chip that cancels it. */
  private routed: { id: string; title: string; awaiting: boolean; name: string; words: string } | null = null;
  private declined = new Set<string>();
  /** Keyworded phrases at the take's start, left as words for the reader at Done (`late`). */
  private doneReader: { segments: Segment[]; words: string }[] = [];
  private nextId = 1;
  /** Every phrase the reader put somewhere in this take, in the order they were said (by start, then as emitted), as the page shows them. */
  private said: Placed[] = [];
  /** The last take-back, until it settles. */
  private undoable: TookBack | null = null;
  /** A take-back ran, spans pushed or to come: the take's words are not the transcript's (`changedWords`). */
  private tookBackYet = false;
  /** Take-backs settled by `close`, quoted, for the landing to name. */
  private closedWith: string[] = [];
  /** "New note" was said or tapped: the take is past its start, whatever the page holds now. */
  private sealedYet = false;

  /** The reader has done something: routed, inserted, placed, raised a card, kept a payload, queued an ask. */
  get engaged(): boolean {
    return this.engagedYet;
  }

  /**
   * The take's words are not the transcript's: a command was carried out, or something was taken back. The recorder
   * reads the take's phrases, not the transcript, at Done, and hands them to the better words.
   */
  get changedWords(): boolean {
    return this.engagedYet || this.tookBackYet;
  }

  /** What Done settled unseen, for the note's toast: each take-back still open when the recording ended, quoted. */
  get tookBackAtDone(): readonly string[] {
    return this.closedWith;
  }

  /** Words of the take are on the page: something that lays out as anything. */
  private get kept(): boolean {
    return this.said.some((placed) => placed.where.kind === 'take' && renderable(placed.segment.text));
  }

  /** The take is at its start: nothing on the page, nothing done, and no note sealed by "New note". A route said here is sticky. */
  private get atStart(): boolean {
    return !this.kept && !this.engagedYet && !this.sealedYet;
  }

  /** A bare drop is waiting for a send in the next breath ("Scratch that." | "Add it to Groceries."): the partial starting one belongs in the chip. */
  get sendOpen(): boolean {
    return this.undoable?.dropOnly === true;
  }

  /** A command is being held, a one-shot is open, a card is up, or a take-back can still be undone: the recording stays open. */
  get holding(): boolean {
    return this.held !== null || this.opened !== null || this.pending !== null || this.undoable !== null;
  }

  /** A note was routed to and nothing has been said for it yet: the phrase still being heard belongs in the chip. */
  get awaitingPayload(): boolean {
    return this.routed?.awaiting === true;
  }

  /**
   * A command is being said, waiting for its name, or a one-shot is taking its words: the phrase still being heard is
   * the command's, for the chip, not the page's. A card up is not: what is said meanwhile goes to the page.
   */
  get hearingCommand(): boolean {
    return this.held !== null || this.opened !== null || this.routed?.awaiting === true;
  }

  /** The card up now, if one is. */
  get card(): LiveCard<N> | null {
    return this.pending?.card ?? null;
  }

  // ---- a phrase ---------------------------------------------------------------------------------

  /** A committed phrase: what the recorder does with it. */
  phrase(said: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    return this.late(this.heard(said, ctx, now), ctx);
  }

  /**
   * A phrase read. `took` is set when the phrase is the take-back half of one cut in two by `takeBack`: whether the
   * keyword came before it, and whether the head did.
   */
  private heard(said: Segment, ctx: LiveContext<N>, now: number, took?: { keyed: boolean; headBeforeKeyword: boolean }): LiveStep<N>[] {
    const text = said.text.replace(/^[\s.,;:!?…]+/, '');
    if (!text) return [];
    const segment = { ...said, text };
    if (this.closed) return [this.words(segment)];
    const steps: LiveStep<N>[] = [];

    // A card up: this phrase may be its answer. Not this note's card goes at the next phrase.
    if (this.pending) {
      const answer = this.spokenAnswer(text);
      if (answer) return [{ kind: 'command', span: spanOf(segment) }, ...this.settle(answer, ctx)];
      if (this.pending.declined) steps.push(...this.settle({ kind: 'keep' }, ctx));
    }

    // A name that may still be growing: this phrase, read with it.
    const growing = this.growing;
    this.growing = null;
    // The last thing said, taken back: before a name could grow into "scratch that", and before a held command, an
    // open one-shot or a note waiting for its words could take it as theirs.
    const taken = this.takeBack(segment, ctx, now, took);
    if (taken) return [...steps, ...taken];
    // Measured on the recording, from the end of the command to the start of this phrase: a long phrase is committed
    // well after it began.
    if (growing && segment.startMs - growing.command.endMs <= LIVE_TIMING.growMs) {
      const grown = this.grow(growing, segment, ctx, now);
      if (grown) return [...steps, ...grown];
    }

    const keyed = hearKeyword(text, (words) => this.readsAsRoute(words, ctx)) !== null;
    // A command held for its name: read again, joined. Unless the keyword is said again: then the held command got no
    // name, and this phrase is a command of its own ("Hey Ghost, add to signing." | "Hey Ghost, add milk to groceries.").
    if (this.held) {
      if (!keyed || this.held.why === 'lead' || this.held.why === 'filler') return [...steps, ...this.readHeld(segment, ctx, now)];
      steps.push(...this.letGoHeld(ctx, now));
    }

    // A one-shot with nothing said for it yet: its phrases, until a pause. Each is marked, so the better words leave
    // it out of the take's own note (refineText.ts).
    const opened = this.opened;
    if (opened && !keyed) {
      opened.count += 1;
      opened.lastAt = now;
      const theirs = opened.count === 1 ? payloadWords(segment, text) : [segment];
      steps.push({ kind: 'command', span: spanOf(segment) }, ...theirs.map((piece) => this.place({ kind: 'insert', id: opened.id }, piece)));
      if (opened.count >= LIVE_TIMING.itemsPhrases) steps.push(...this.closeInsert());
      return steps;
    }
    if (opened) steps.push(...this.closeInsert());
    // A note routed to, and nothing said for it yet: this is what it is for.
    if (this.routed?.awaiting && !keyed) {
      this.routed.awaiting = false;
      return [...steps, ...this.payload(segment, text), { kind: 'chip', view: null }];
    }
    const pending = this.pending;
    const read = this.read(segment, ctx, now);
    // What is said with a card up goes to the page as words, and is what a one-shot chosen on the card takes.
    const word = read.length === 1 && read[0]!.kind === 'words' && read[0]!.segment === segment;
    if (pending && this.pending === pending && word) pending.after.push(segment);
    return [...steps, ...read];
  }

  /** The clock: holds give up, cards take their default, a one-shot closes after a pause, a take-back settles. */
  tick(now: number, ctx: LiveContext<N>): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    if (this.held && now - this.held.lastAt > LIVE_TIMING.holdMs) steps.push(...this.letGoHeld(ctx, now));
    if (this.pending && now - this.pending.since > LIVE_TIMING.cardMs) steps.push(...this.settle({ kind: 'keep' }, ctx));
    if (this.opened && now - this.opened.lastAt > LIVE_TIMING.itemsQuietMs) steps.push(...this.closeInsert());
    if (this.undoable && now - this.undoable.since > LIVE_TIMING.takeBackMs) steps.push(...this.settleTakeBack());
    return this.late(steps, ctx);
  }

  /** A take-back's Undo, tapped: what went comes back, and what was said is written as words. */
  undoTakeBack(id: number): LiveStep<N>[] {
    const took = this.undoable;
    // Settled already (Done settles it too): the chip is drawn a moment after the reader's clock starts, so a tap is never silent.
    if (!took || took.id !== id) return [{ kind: 'chip', view: { phase: 'said', text: 'Too late to put that back.' } }];
    this.undoable = null;
    // What it put in their place, out (a send's one-shot emptied with it, so Done skips it); what went, back where it
    // was (the recorder re-listens and re-sorts, and a card up takes it as said since); then the take-back itself, and
    // a send said after it, as the words they would have been: the opener and its rest, keyword off and the head's own
    // steps standing. A correction goes back beside the item it corrected, in its one-shot; anything else to the page.
    // A keyword's stretch is marked as `read` marks one, so the better words leave "hey Ghost" out.
    const steps = this.putBack(took);
    const beside = (took.outcome === 'replaced' || took.outcome === 'changed') && took.removed[0] ? took.removed[0].where : { kind: 'take' as const };
    steps.push(this.place(beside, took.phrase));
    if (took.keyed) steps.push({ kind: 'keyword', span: spanOf(took.phrase) });
    for (const send of took.sends ?? []) {
      const heard = findKeyword(send.text);
      steps.push(this.place({ kind: 'take' }, { ...send, text: sentence(heard ? heard.after : send.text) }));
      if (heard) steps.push({ kind: 'keyword', span: spanOf(send) });
    }
    steps.push({ kind: 'chip', view: { phase: 'done', text: 'Put back' } }, { kind: 'haptic', haptic: 'light' }, { kind: 'log', line: `Put back “${took.quote}”` });
    return steps;
  }

  /**
   * "New note", tapped: the words so far are sealed with the note they were said for, out of a take-back's reach, an
   * open take-back settles, and the take is past its start, as after the spoken cue.
   */
  forked(): LiveStep<N>[] {
    if (this.closed) return [];
    const steps = this.settleTakeBack();
    this.said = [];
    this.sealedYet = true;
    return steps;
  }

  /** A card's button: a note, a new note, or Keep here. */
  answer(cardId: number, choice: CardChoice, ctx: LiveContext<N>): LiveStep<N>[] {
    if (this.closed || this.pending?.card.id !== cardId) return [];
    return this.settle(choice, ctx);
  }

  /**
   * Not this note: the take goes home, and that name is not sent to that note again in this take. A card offers the
   * find's other candidates and a new note, for 8 s or until the next phrase.
   */
  decline(ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const routed = this.routed;
    if (!routed || this.closed) return [];
    this.routed = null;
    this.growing = null;
    this.declined.add(`${routed.id}|${routed.name.toLowerCase()}`);
    const steps: LiveStep<N>[] = [...this.settleTakeBack(), { kind: 'home' }, { kind: 'log', line: `Not added to ${routed.title}: the take went back to its own note` }];
    if (ctx.locked) return [...steps, { kind: 'chip', view: { phase: 'said', text: `Not added to ${routed.title}.` } }];
    const found = findNote(routed.name, ctx.notes.filter((c) => c.id !== routed.id));
    const others = (found.status === 'resolved' ? [found.note] : found.status === 'unsure' ? found.candidates : found.status === 'missing' ? found.near : []).filter((c) => this.refusal(c, ctx) === null);
    const card: LiveCard<N> = { id: this.nextId++, form: 'declined', heading: `Not added to ${routed.title}`, candidates: others.slice(0, 2), newTitle: titleFor(routed.name), payload: '' };
    // Nothing is held for this card to give back: what was said since the command is the take's already.
    const command = { text: '', startMs: 0, endMs: 0 };
    this.pending = { card, since: now, command, payload: '', reading: namedAs(routed.name), atStart: false, after: [], declined: { id: routed.id, name: routed.name } };
    return [...steps, { kind: 'card', card }];
  }

  /** A one-shot's own Not this note: its words back into the take. Nothing once the recording has ended: Done is writing it. */
  dropInsert(id: number): LiveStep<N>[] {
    if (this.closed) return [];
    if (this.opened?.id === id) this.opened = null;
    this.rehome(id);
    return [{ kind: 'insert-drop', id }];
  }

  /** A one-shot's words back in the take (`insert-drop`): the record says so too, their order as it was. */
  private rehome(id: number): void {
    const home = (placed: Placed): Placed => (placed.where.kind === 'insert' && placed.where.id === id ? { ...placed, where: { kind: 'take' }, from: fromOf({ kind: 'take' }, placed.segment) } : placed);
    this.said = this.said.map(home);
    if (this.undoable) {
      this.undoable.removed = this.undoable.removed.map(home);
      this.undoable.placed = this.undoable.placed.map(home);
    }
  }

  /** Done, Discard, the side key, the screen off, back: every hold, card and take-back settled, before anything is composed. */
  close(ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    if (this.held) steps.push(...this.letGoHeld(ctx, now));
    if (this.pending) steps.push(...this.settle({ kind: 'keep' }, ctx));
    if (this.opened) steps.push(...this.closeInsert());
    steps.push(...this.settleTakeBack(true));
    this.growing = null;
    this.closed = true;
    return this.late(steps, ctx);
  }

  /** The recording's last words, which only the stop's transcript had: read like any phrase, then closed again. */
  final(said: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    this.closed = false;
    const steps = this.phrase(said, ctx, now);
    return [...steps, ...this.close(ctx, now)];
  }

  // ---- taking it back ---------------------------------------------------------------------------

  /** A command with nothing said for it yet: what a safe take-back cancels, and what a risky one is the words of. */
  private commandWaiting(): boolean {
    const held = this.held !== null && (this.held.why === 'unsure' || (this.held.why === 'keyword' && heldWords(this.held) !== ''));
    return held || (this.opened !== null && this.opened.count === 0) || this.routed?.awaiting === true || (this.pending !== null && !this.pending.after.length);
  }

  /**
   * A hold that is only filler, a lead or the keyword alone, dropped before a take-back goes ahead: filler either
   * way, its stretch marked. `keyed` when it was the keyword, which made the take-back its command.
   */
  private dropHold(): { steps: LiveStep<N>[]; keyed: boolean } {
    const held = this.held;
    const keyed = held !== null && held.why === 'keyword' && heldWords(held) === '';
    if (!held || (!keyed && held.why !== 'lead' && held.why !== 'filler')) return { steps: [], keyed: false };
    this.held = null;
    return { steps: held.segments.map((s) => spanStep<N>(s)), keyed };
  }

  /**
   * The last thing said, taken back, when `segment` says so (takeBack.ts): gone, replaced by the rest of the phrase,
   * one word changed, or sent to a note named; a command with nothing said for it yet, cancelled. Null when the phrase
   * is not one, or its opener is how people talk and no correction follows, so the phrase carries on as words. A phrase
   * with words before the opener is read as two: the head first, a phrase of its own (it may itself be what is taken
   * back), then the take-back, with `took` saying what the head took with it. Nothing here engages the reader.
   */
  private takeBack(segment: Segment, ctx: LiveContext<N>, now: number, took?: { keyed: boolean; headBeforeKeyword: boolean }): LiveStep<N>[] | null {
    // A send said in a breath of its own, after a bare drop still open: "Scratch that." | "Add it to Groceries."; or
    // the name Whisper cut from its send: "Scratch that, add it to" | "Groceries instead."
    const open = this.undoable;
    if (open?.dropOnly && !open.sent) {
      const name = readSend(segment.text) ?? (open.fragment !== null ? readSend(`${open.fragment} ${segment.text}`) : null);
      const sent = name === null ? null : this.sendAfter(open, name, segment, ctx, now);
      if (sent) return sent;
    }
    const read = readTakeBack(segment.text);
    if (!read) return null;
    const held = this.held;
    const keyedByHold = held !== null && held.why === 'keyword' && heldWords(held) === '';
    // "Hey Ghost, actually, add a note to House TODOs": the command, said as people say it, and read as that command
    // by `command`, the words before the keyword the take's own as ever.
    if (read.risky && (read.keyed || keyedByHold) && !read.send && commandAfterOpener(read.said) !== read.said) return null;
    // "Actually, add call the plumber to House TODOs" with no keyword: the command, when its words pass the bare gate.
    // A phrase with words before it ("Buy milk. Actually, add …") is read as two first, and its rest meets this alone.
    if (read.risky && !read.head && !read.keyed && !keyedByHold && !read.send && this.bareReading(commandAfterOpener(commandWords(read.said)), ctx) !== null) return null;
    if (read.head) {
      const head = this.heard({ ...segment, text: sentence(read.head) }, ctx, now);
      const rest = this.heard({ ...segment, text: read.said }, ctx, now, { keyed: read.keyed, headBeforeKeyword: read.headBeforeKeyword });
      return [...head, ...rest];
    }
    const keyed = read.keyed || took?.keyed === true || keyedByHold;
    const headBeforeKeyword = took?.headBeforeKeyword ?? false;
    // A risky opener at a command with nothing said for it is the command's words: "add a note to House TODOs." |
    // "Actually, …"; and with a send's card up, words said since it.
    const waiting = this.commandWaiting();
    if (read.risky && (waiting || this.pending?.stays)) return null;

    // The last thing said, with the rest of its source phrase: an enumeration's items go as one. Several plain phrases
    // on one stretch (a phrase read as its head and its rest) are each their own, so the last is the unit. Of a phrase
    // that holds several sentences, the last, the others kept.
    const last = this.said.at(-1) ?? null;
    let group = last ? this.said.filter((placed) => placed.from === last.from) : [];
    if (group.length > 1 && group.every((placed) => placed.where.kind === 'take' && !cuePrefixOf(placed.segment.text))) group = [last!];
    const sentences = group.length === 1 ? splitSentences(last!.segment.text) : [];
    const unitRaw = sentences.length >= 2 ? sentences.at(-1)! : group.length === 1 ? last!.segment.text : null;
    const kept: Segment | null = sentences.length >= 2 ? { ...last!.segment, text: sentences.slice(0, -1).join(' ') } : null;
    const unitText = unitRaw !== null ? quoted(unitRaw) : group.map((placed) => quoted(placed.segment.text)).join(', ');
    const taken: Segment[] = kept ? [{ ...last!.segment, text: unitRaw! }] : group.map((placed) => placed.segment);
    const swap = read.rest && unitRaw !== null ? swapWord(unitRaw, read.rest) : null;
    // How people talk counts only before a correction of what went: the sentence again with a change, one word of a
    // kind, a send, or, after the keyword, a sentence of its own. With nothing said before, it is words, keyword and
    // all, read as any phrase is.
    if (last && !waiting && read.risky && !read.send && !swap && !corrects(unitText, read.rest) && !(keyed && contentWords(read.rest).length >= 2)) return null;
    if (!last && read.risky) return null;

    const steps: LiveStep<N>[] = this.dropHold().steps;
    if (waiting || this.pending?.stays) return [...steps, ...this.cancel(read, segment, ctx, now)];
    if (!last) {
      this.tookBackYet = true;
      steps.push(spanStep(segment), { kind: 'chip', view: { phase: 'said', text: 'Nothing to take back.' } }, { kind: 'haptic', haptic: 'warning' }, { kind: 'log', line: 'Nothing to take back' });
      if (read.rest && !read.send) steps.push(...this.heard({ ...segment, text: sentence(read.rest) }, ctx, now));
      return steps;
    }

    // Decided before anything moves, so a send that finds no note moves nothing.
    const found = read.send ? findNote(read.send, ctx.notes, { aim: ctx.aim }) : null;
    const refused = found ? this.sendRefused(found, read.send!, ctx) : null;
    if (refused) {
      this.tookBackYet = true;
      return [...steps, spanStep(segment), { kind: 'chip', view: { phase: 'said', text: refused } }, { kind: 'haptic', haptic: 'warning' }, { kind: 'log', line: refused }];
    }
    const where = last.where;
    const segments = group.map((placed) => placed.segment);

    // A send that is not sure of its note asks, the words on the page: a note chosen takes them, as a card mid-take
    // takes what was said since it (`settle`); Keep here puts them back where they were. The phrase's own stretch is
    // marked now, since the card is the moment: there is no Undo.
    if (found && (found.status === 'unsure' || found.status === 'missing')) {
      steps.push(...this.settleTakeBack());
      // The sentence alone on the page, split from the rest of its phrase, or brought home from its one-shot, so it can go by itself.
      if (kept || where.kind !== 'take') {
        steps.push(where.kind === 'take' ? this.unword(segments) : this.unwordInsert(where.id, segments));
        if (kept) steps.push(this.place(where, kept));
        for (const piece of taken) steps.push(this.place({ kind: 'take' }, piece));
      }
      return [...steps, ...this.askSend(found, read.send!, taken, unitText, where, segment, ctx, now)];
    }

    // Take it back: off the page or out of its one-shot, the rest of a phrase of several sentences kept.
    steps.push(...this.settleTakeBack());
    steps.push(where.kind === 'take' ? this.unword(segments) : this.unwordInsert(where.id, segments));
    const doneAt = this.doneReader.findIndex((entry) => entry.segments.some((s) => group.some((placed) => same(placed.segment, s))));
    const doneReader = doneAt >= 0 ? this.doneReader.splice(doneAt, 1)[0]! : null;
    // The corrected item said next still goes to the named note, and is read as the first said for it.
    if (this.opened && where.kind === 'insert' && where.id === this.opened.id) {
      this.opened.lastAt = now;
      this.opened.count = Math.max(0, this.opened.count - 1);
    }
    const before = new Set(this.said);
    if (kept) steps.push(this.place(where, kept));

    const undo = this.nextId++;
    let outcome: TookBack['outcome'] = 'gone';
    let sent: TookBack['sent'] = null;
    let view: RouteView = { phase: 'tookBack', said: cut(unitText), outcome: 'gone', undo };
    let line = `Took back “${unitText}”`;
    let fragment: string | null = null;
    if (found?.status === 'current' || found?.status === 'resolved') {
      const went = this.sendTaken(found, taken, unitText, ctx, undo);
      steps.push(...went.steps);
      ({ outcome, sent, view, line } = went);
    } else if (swap) {
      steps.push(this.place(where, { ...taken[0]!, text: swap.text }));
      outcome = 'changed';
      view = { phase: 'tookBack', said: cut(swap.from), outcome: { changed: swap.to }, undo };
      line = `Changed “${swap.from}” to “${swap.to}” in “${unitText}”`;
    } else if (read.rest && read.risky) {
      // The sentence again, in the unit's place, the cue it was written with inherited so the list shape holds.
      const prefix = cuePrefixOf(unitRaw ?? group[0]!.segment.text);
      const pieces = prefix ? payloadWords(segment, read.rest, { item: true, task: /check/i.test(prefix) }) : [{ ...segment, text: sentence(read.rest) }];
      for (const piece of pieces) steps.push(this.place(where, piece));
      const said = pieces.map((piece) => quoted(piece.text)).join(', ');
      outcome = 'replaced';
      view = { phase: 'tookBack', said: cut(unitText), outcome: { replaced: cut(said) }, undo };
      line = `Replaced “${unitText}” with “${said}”`;
    } else if (read.rest && opensSend(read.rest) && isOpener(commandWords(read.rest))) {
      // "Scratch that, add it to" | "Groceries instead.": Whisper cut the name from its send. The opener waits for it, never written.
      fragment = read.rest;
    }

    this.tookBackYet = true;
    const placed = this.said.filter((entry) => !before.has(entry));
    const mine: TookBack = {
      id: undo,
      phrase: { ...segment, text: sentence(read.said) },
      keyed,
      headBeforeKeyword,
      removed: group,
      taken,
      placed,
      outcome,
      sent,
      dropOnly: outcome === 'gone' && (!read.rest || fragment !== null),
      fragment,
      doneReader,
      quote: unitText,
      since: now,
    };
    this.undoable = mine;
    if (this.pending) for (const entry of placed) if (entry.where.kind === 'take') this.pending.after.push(entry.segment);
    steps.push({ kind: 'chip', view }, { kind: 'haptic', haptic: 'selection' }, { kind: 'log', line });
    // A safe opener's rest is a phrase of its own: words, a cue, a command, or another take-back.
    if (read.rest && !read.risky && !read.send && !swap && fragment === null) {
      steps.push(...this.heard({ ...segment, text: sentence(read.rest) }, ctx, now));
      if (this.undoable === mine) mine.placed = this.said.filter((entry) => !before.has(entry));
    }
    return steps;
  }

  /**
   * Why a send's note cannot take the words, or null: a book, a shared note over the lock screen, a name not sure of
   * over the lock screen or between notes that are all refused, or a name that finds nothing and comes near nothing.
   */
  private sendRefused(found: Found<LiveCandidate<N>>, name: string, ctx: LiveContext<N>): string | null {
    if (found.status === 'resolved') return this.refusal(found.note, ctx);
    if (found.status === 'unsure') {
      const choices = found.candidates.filter((candidate) => this.refusal(candidate, ctx) === null);
      if (!choices.length) return this.refusal(found.candidates[0]!, ctx) ?? 'Not sure which note, so the words stay here.';
      return ctx.locked ? 'Not sure which note, so the words stay here.' : null;
    }
    if (found.status === 'missing') {
      if (ctx.locked) return 'No note by that name, so the words stay here.';
      return found.near.some((candidate) => this.refusal(candidate, ctx) === null) ? null : `No note called “${name}”, so the words stay here.`;
    }
    return null;
  }

  /**
   * A send that is not sure of its note: the same card a command's name gets, holding the words as said since it,
   * which are on the page (`taken`); a note chosen takes them, and Keep here puts them back where they were (`from`).
   */
  private askSend(found: Found<LiveCandidate<N>> & { status: 'unsure' | 'missing' }, name: string, taken: Segment[], unitText: string, from: Placed['where'], segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    this.tookBackYet = true;
    const form = found.status;
    const heading = form === 'unsure' ? 'Add to which note?' : `No note called “${name}”`;
    const candidates = (form === 'unsure' ? found.candidates : found.near).filter((candidate) => this.refusal(candidate, ctx) === null).slice(0, form === 'unsure' ? 3 : 2);
    return [
      spanStep(segment),
      ...this.raise({ form, heading, candidates, reading: namedAs(name), payload: unitText, whole: segment, atStart: false, now, stays: { text: unitText, after: taken, from } }, ctx),
      { kind: 'log', line: `Took back “${unitText}”, asking which note` },
    ];
  }

  /**
   * The words taken back, sent: into the note found, as a one-shot that shows its lines once the Undo goes; or, for
   * the note being written to, as an item of its list, under a heading named for it. What the chip and the log say.
   */
  private sendTaken(found: Found<LiveCandidate<N>> & { status: 'current' | 'resolved' }, taken: Segment[], unitText: string, ctx: LiveContext<N>, undo: number): { steps: LiveStep<N>[]; outcome: TookBack['outcome']; sent: TookBack['sent']; view: RouteView; line: string } {
    const steps: LiveStep<N>[] = [];
    if (found.status === 'current') {
      const aim = ctx.aim;
      let spot: string | null = null;
      if (aim && found.heading) {
        const placing = placingFor(aim.body, { said: { task: false }, heading: found.heading, lane: found.heading });
        steps.push({ kind: 'placing', placing });
        spot = spotOf(aim.body, placing);
      }
      for (const piece of taken) steps.push(...payloadWords(piece, quoted(piece.text), { item: true }).map((item) => this.place({ kind: 'take' }, item, true)));
      return { steps, outcome: 'placed', sent: null, view: { phase: 'tookBack', said: cut(unitText), outcome: { placed: spot ?? 'in a list' }, undo }, line: `Put “${unitText}” ${spot ?? 'in its list'}` };
    }
    const note = found.note.note;
    const title = ctx.locked ? 'the note you named' : found.note.title;
    const id = this.nextId++;
    for (const piece of taken) this.record({ kind: 'insert', id }, piece);
    steps.push({ kind: 'insert', id, note, title, placing: placingFor(note.body, { said: { task: false, paragraph: false } }), segments: taken }, { kind: 'haptic', haptic: 'success' });
    return { steps, outcome: 'sent', sent: { id, title }, view: { phase: 'tookBack', said: cut(unitText), outcome: { sent: title }, undo }, line: `Took back “${unitText}” and sent it to ${title}` };
  }

  /**
   * "Add it to Groceries" said in the breath after a bare "Scratch that": the drop's second half. The words go to
   * the note found, or into this note's list; a name that is not sure asks on the card, the words on the page; a note
   * the reader cannot write to, or a name said with the keyword that finds nothing, puts them back and says why. Null
   * when a name said without the keyword finds nothing, so the phrase is words ("Put it in the oven").
   */
  private sendAfter(open: TookBack, name: string, segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] | null {
    const found = findNote(name, ctx.notes, { aim: ctx.aim });
    const refused = this.sendRefused(found, name, ctx);
    if (refused && found.status === 'missing' && findKeyword(segment.text) === null) return null;
    const steps: LiveStep<N>[] = this.dropHold().steps;
    if (refused) {
      // The words back where they were, the drop's own stretches marked and the words' not: with the live phrases
      // handed on, they survive the better words.
      this.undoable = null;
      steps.push(...this.putBack(open), { kind: open.headBeforeKeyword ? 'keyword' : 'command', span: spanOf(open.phrase) }, spanStep(segment));
      steps.push({ kind: 'chip', view: { phase: 'said', text: refused } }, { kind: 'haptic', haptic: 'warning' }, { kind: 'log', line: refused });
      return steps;
    }
    if (found.status === 'unsure' || found.status === 'missing') {
      // The card a send in one breath raises, the words on the page while it asks; the drop settles now, since the card is the moment.
      steps.push(...this.settleTakeBack());
      for (const piece of open.taken) steps.push(this.place({ kind: 'take' }, piece));
      return [...steps, ...this.askSend(found, name, open.taken, open.quote, open.removed[0]?.where ?? { kind: 'take' }, segment, ctx, now)];
    }
    const before = new Set(this.said);
    const went = this.sendTaken(found, open.taken, open.quote, ctx, open.id);
    steps.push(...went.steps, { kind: 'chip', view: went.view }, { kind: 'log', line: went.line });
    open.outcome = went.outcome;
    open.sent = went.sent;
    open.placed.push(...this.said.filter((entry) => !before.has(entry)));
    open.dropOnly = false;
    // The send's own phrase never lands: its stretch is the take-back's too, marked with it when it settles.
    open.sends = [...(open.sends ?? []), segment];
    open.since = now;
    return steps;
  }

  /** What a take-back put in their place, out, and what went, back where it was: Undo's and a refused send's. */
  private putBack(took: TookBack): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    for (const placed of [...took.placed].reverse()) steps.push(placed.where.kind === 'take' ? this.unword([placed.segment]) : this.unwordInsert(placed.where.id, [placed.segment]));
    for (const placed of took.removed) {
      steps.push(this.place(placed.where, placed.segment));
      if (this.pending && placed.where.kind === 'take') this.pending.after.push(placed.segment);
    }
    if (took.doneReader) this.doneReader.push(took.doneReader);
    return steps;
  }

  /**
   * A safe take-back at a command with nothing said for it yet cancels the command, and nothing else is taken back:
   * a held opener, an empty one-shot, a note routed to and waiting, or a card with nothing said since. No Undo (say
   * the command again). With nothing on the page afterwards the take is at its start again, so the corrected command
   * is sticky.
   */
  private cancel(read: TakeBack, segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    let what = '';
    const held = this.held;
    if (held) {
      this.held = null;
      what = heldWords(held);
      steps.push(...held.segments.map((s) => spanStep<N>(s)));
    } else if (this.opened && this.opened.count === 0) {
      what = this.opened.words;
      steps.push(...this.closeInsert());
    } else if (this.routed?.awaiting) {
      what = this.routed.words;
      this.routed = null;
      steps.push(...this.settleTakeBack(), { kind: 'home' });
    } else if (this.pending) {
      const pending = this.pending;
      this.tookBackYet = true;
      // A take-back's own send, still asking: the words go back, and the card goes.
      if (pending.stays) return [...steps, spanStep(segment), ...this.settle({ kind: 'keep' }, ctx)];
      what = withoutFinalStop(commandWordsOf(pending.command.text));
      this.pending = null;
      steps.push({ kind: 'card', card: null });
    }
    this.tookBackYet = true;
    if (!this.said.length) this.engagedYet = false;
    steps.push(spanStep(segment), { kind: 'chip', view: { phase: 'tookBack', said: cut(what), outcome: 'gone' } }, { kind: 'haptic', haptic: 'selection' }, { kind: 'log', line: `Took back the command “${what}”` });
    if (read.rest && !read.send) steps.push(...this.heard({ ...segment, text: sentence(read.rest) }, ctx, now));
    return steps;
  }

  /**
   * A take-back settled: its stretches marked for the better words, which are pushed only now because `commandSpans`
   * cannot be undone; a send's one-shot shown with its Not this note, which is the way back after the window. At
   * `closing` (Done) the quote is kept for the note's toast, since its Undo could not be tapped.
   */
  private settleTakeBack(closing = false): LiveStep<N>[] {
    const took = this.undoable;
    if (!took) return [];
    this.undoable = null;
    const marks = new Map<string, LiveStep<N>>();
    const mark = (segment: Segment, kind: 'command' | 'keyword' = 'command') => {
      const key = `${segment.startMs}-${segment.endMs}`;
      if (!marks.has(key)) marks.set(key, { kind, span: spanOf(segment) });
    };
    // The phrase first: on the stretch it shares with its head, its own mark is the one that stands.
    mark(took.phrase, took.headBeforeKeyword ? 'keyword' : 'command');
    for (const placed of took.removed) mark(placed.segment);
    for (const send of took.sends ?? []) mark(send);
    const steps: LiveStep<N>[] = [...marks.values()].sort((a, b) => (a.kind === 'command' || a.kind === 'keyword' ? a.span.startMs : 0) - (b.kind === 'command' || b.kind === 'keyword' ? b.span.startMs : 0));
    if (took.sent && !closing) steps.push({ kind: 'insert-end', id: took.sent.id });
    if (closing) this.closedWith.push(took.quote);
    return steps;
  }

  // ---- reading ----------------------------------------------------------------------------------

  private words(segment: Segment, payload = false): LiveStep<N> {
    return this.place({ kind: 'take' }, segment, payload);
  }

  /**
   * A phrase put somewhere, on the record: at its place by time, after those said at the same time, so a phrase's
   * pieces keep their order. Anything placed after a bare drop is what "it" now means, so a send in the next breath
   * follows the drop only.
   */
  private record(where: Placed['where'], segment: Segment): void {
    if (this.undoable?.dropOnly) this.undoable.dropOnly = false;
    let at = this.said.length;
    while (at > 0 && this.said[at - 1]!.segment.startMs > segment.startMs) at -= 1;
    this.said.splice(at, 0, { where, segment, from: fromOf(where, segment) });
  }

  /** The one way words go on the page or into a one-shot: recorded, and the step that puts them there. */
  private place(where: Placed['where'], segment: Segment, payload = false): LiveStep<N> {
    this.record(where, segment);
    if (where.kind === 'insert') return { kind: 'insert-words', id: where.id, segments: [segment] };
    return payload ? { kind: 'words', segment, payload } : { kind: 'words', segment };
  }

  /** Phrases off the record: taken out of the take, or of a one-shot, or a card's said-since. */
  private forget(segments: readonly Segment[]): void {
    this.said = this.said.filter((placed) => !segments.some((gone) => same(gone, placed.segment)));
    if (this.pending) this.pending.after = this.pending.after.filter((after) => !segments.some((gone) => same(gone, after)));
  }

  /** The one way words leave the take (`unword`), or a one-shot (`insert-unword`): off the record, and the step. */
  private unword(segments: readonly Segment[]): LiveStep<N> {
    this.forget(segments);
    return { kind: 'unword', segments: [...segments] };
  }

  private unwordInsert(id: number, segments: readonly Segment[]): LiveStep<N> {
    this.forget(segments);
    return { kind: 'insert-unword', id, segments: [...segments] };
  }

  /**
   * A command's payload as the take's words (`payloadWords`). The phrase it was read from is marked, so the better
   * words put these in its place rather than the phrase as heard, "The note is" and all (refineText.ts).
   */
  private payload(whole: Segment, payload: string, options: { item?: boolean; task?: boolean } = {}): LiveStep<N>[] {
    const words = payloadWords(whole, payload, options);
    return words.length ? [{ kind: 'command', span: spanOf(whole) }, ...words.map((segment) => this.words(segment, true))] : [];
  }

  private engage(): void {
    this.engagedYet = true;
  }

  /**
   * Whether `words` after a mishearing of the keyword are a command for a note named clearly: the gate every bare
   * phrase passes (liveCommand.ts `misheardShape`, `clear`), since a mishearing is exactly as trustworthy as no
   * keyword.
   */
  private readsAsRoute(words: string, ctx: LiveContext<N>): boolean {
    return misheardShape(commandWords(words), (reading) => this.clear(reading, this.find(reading, ctx), ctx));
  }

  /**
   * The gate a phrase passes with no trustworthy keyword, with what only the live reader knows: the note found is one
   * it may write to (`refusal`), and whether the take is at the start of a fresh recording, where a route may wait for
   * its words (liveCommand.ts `bareCommand`).
   */
  private clear(reading: Reading, found: Found<LiveCandidate<N>>, ctx: LiveContext<N>): boolean {
    return found.status === 'resolved' && this.refusal(found.note, ctx) === null && bareCommand(reading, { title: found.note.title, body: found.note.note.body }, found.score, { atStart: this.atStart && !ctx.own });
  }

  /**
   * What `bare` carries out, and what a risky opener before it is not a correction of: the readings of `words` that
   * pass the bare gate, the best of them chosen as a keyed command's is (`choose`). Null when none does.
   */
  private bareReading(words: string, ctx: LiveContext<N>): { reading: Reading; note: LiveCandidate<N>; score: number } | null {
    const passing = readRoute(words).filter((reading) => bareShape(reading) && this.clear(reading, this.find(reading, ctx), ctx));
    const chosen = this.choose(passing, ctx);
    if (!chosen || chosen.found.status !== 'resolved') return null;
    return { reading: chosen.reading, note: chosen.found.note, score: chosen.found.score };
  }

  /** Why a note is never written to from here, or null: it is a book, or it is shared and the phone is locked. */
  private refusal(candidate: LiveCandidate<N>, ctx: LiveContext<N>): string | null {
    if (isBookBody(candidate.note.body)) return `“${candidate.title}” is a book, so the words stay here.`;
    if (ctx.locked && ctx.published?.(candidate.note.id)) return 'That note is shared, so the words stay here.';
    return null;
  }

  /**
   * Keyworded phrases at the take's start that were left as words for the reader at Done, once the live reader has
   * done something: the reader at Done no longer runs (CaptureScreen.tsx `finish`), so each is taken out of the words
   * and queued or left out, as one said mid-take is ("Hey Ghost, fix the spelling." | … | "Hey Ghost, add call Sam to
   * House TODOs."). Before the phrase's own steps, so an ask said later is the one kept.
   */
  private late(steps: LiveStep<N>[], ctx: LiveContext<N>): LiveStep<N>[] {
    if (!this.engagedYet || !this.doneReader.length) return steps;
    const out: LiveStep<N>[] = [];
    for (const { segments, words } of this.doneReader.splice(0)) {
      out.push(this.unword(segments), ...segments.map((segment) => spanStep<N>(segment)));
      const done = this.notRoute(words, ctx, { atStart: false });
      if (done !== DONE_READER) out.push(...done);
    }
    return [...out, ...steps];
  }

  /** Phrases the reader at Done is to read: words for now, remembered in case the live reader engages later (`late`). */
  private leftForDone(segments: Segment[], words: string): LiveStep<N>[] {
    this.doneReader.push({ segments, words });
    return segments.map((segment) => this.words(segment));
  }

  private find(reading: Reading, ctx: LiveContext<N>): Found<LiveCandidate<N>> {
    return findNote(reading.name, ctx.notes, { aim: ctx.aim });
  }

  private read(segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const text = segment.text;
    const atStart = this.atStart;
    const heard = hearKeyword(text, (words) => this.readsAsRoute(words, ctx));
    if (!heard) {
      // "Okay." or "Hey." before the command, or Whisper's "Thank you." on a silence: held for the next phrase.
      if (atStart && (onlyLead(text) || onlyFillerPhrase(text) || silenceLine(text))) {
        this.held = { segments: [segment], why: onlyLead(text) ? 'lead' : 'filler', lastAt: now };
        return [];
      }
      return this.bare(segment, ctx, now);
    }
    const before = heard.before.trim();
    const words = before && !onlyFiller(before);
    // "The heating is fixed now, hey Ghost, add…": the words before it are the take's, a phrase of their own.
    const kept: LiveStep<N>[] = words ? [this.words({ ...segment, text: /[.!?…]$/.test(before) ? before : `${before}.` })] : [];
    const mark: LiveStep<N> = words ? { kind: 'keyword', span: spanOf(segment) } : { kind: 'command', span: spanOf(segment) };
    const said = commandWords(heard.after);
    const outcome = this.command(said, segment, ctx, now, { atStart: atStart && !words });
    if (outcome === DONE_READER) return this.leftForDone([segment], said);
    if (outcome === HELD) return [...kept, ...this.heldChip()];
    return [...kept, mark, ...outcome];
  }

  /** The chip while a command is held: "Looking for “house”" once a name is heard, and until then the keyword's. */
  private heldChip(): LiveStep<N>[] {
    const name = this.held?.name;
    const view: RouteView = name ? { phase: 'hearing', name } : { phase: 'command', words: '' };
    return [{ kind: 'chip', view }, { kind: 'haptic', haptic: 'light' }];
  }

  /** A held command read again with the phrase just committed. */
  private readHeld(segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const held = this.held!;
    this.held = null;
    const segments = [...held.segments, segment];
    // Joined, each phrase's own stop gone but the last one's, which ends the command as it ends the phrase.
    const joined = segments.map((s, i) => (i < segments.length - 1 ? withoutFinalStop(s.text) : s.text)).join(' ');
    const whole = { text: joined, startMs: segments[0]!.startMs, endMs: segment.endMs };
    const spans: LiveStep<N>[] = segments.map((s) => ({ kind: 'command', span: spanOf(s) }));
    const heard = hearKeyword(joined, (words) => this.readsAsRoute(words, ctx));
    if (held.why === 'lead' || held.why === 'filler') {
      // "Hey." | "Ghost, add…", "Okay." | "Hey Ghost, add…": one command, or the held phrase given back.
      if (heard && onlyFiller(heard.before)) {
        const said = commandWords(heard.after);
        const outcome = this.command(said, whole, ctx, now, { atStart: true });
        if (outcome === DONE_READER) return this.leftForDone(segments, said);
        if (outcome === HELD) return this.heldChip();
        return [...spans, ...outcome];
      }
      // No keyed command came of it: this phrase is read on its own, and the held one is words after all, unless the
      // phrase was a bare command ("Okay." | "Add a note to House TODOs, call Sam.", "Um." | "New note."), which the
      // filler was said before: then it is marked with the command, as after the keyword, and makes no note of "Okay.".
      // Decided after the read, since `record` places by time; a phrase read as a command starts with its mark.
      const rest = this.read(segment, ctx, now);
      const commanded = rest[0]?.kind === 'command';
      return commanded ? [...held.segments.map((s) => spanStep<N>(s)), ...rest] : [this.words(held.segments[0]!), ...rest];
    }
    const words = commandWords(heard ? heard.after : joined);
    if (isOpener(words) && held.why === 'keyword') {
      this.held = { segments, why: held.why, lastAt: now };
      if (segments.length < LIVE_TIMING.holdPhrases) return [{ kind: 'chip', view: { phase: 'command', words } }];
      // This many phrases and still no name: it gives up, as it does after a quiet.
      return this.letGoHeld(ctx, now);
    }
    const outcome = this.command(words, whole, ctx, now, { atStart: this.atStart, fromHold: true });
    if (outcome === DONE_READER) return this.leftForDone(segments, words);
    if (outcome === HELD) return this.heldChip();
    return [...spans, ...outcome];
  }

  /** A held command that got no name: its words back, or, once the reader has engaged, left out. */
  private letGoHeld(ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const held = this.held;
    this.held = null;
    if (!held) return [];
    if (held.why === 'lead' || held.why === 'filler') return [this.words(held.segments[0]!)];
    if (held.why === 'unsure') {
      // An unsure name that did not grow: its card now.
      const first = held.segments[0]!;
      const heard = hearKeyword(first.text, () => true);
      const outcome = this.command(commandWords(heard?.after ?? first.text), first, ctx, now, { atStart: this.atStart, fromHold: true });
      if (outcome === DONE_READER || outcome === HELD) return [this.words(first)];
      return [{ kind: 'command', span: spanOf(first) }, ...outcome];
    }
    if (this.engagedYet) return [{ kind: 'chip', view: { phase: 'said', text: 'No note was named, so that was left out.' } }];
    const back: LiveStep<N>[] = [];
    for (const [i, segment] of held.segments.entries()) {
      const heard = i === 0 ? hearKeyword(segment.text, () => true) : null;
      const text = heard ? heard.after : segment.text;
      if (text.trim()) back.push(this.words({ ...segment, text: sentence(withoutFinalStop(text)) }));
    }
    return [...back, { kind: 'log', line: 'Heard “hey Ghost” but no note named, so those words stayed in the note' }, { kind: 'chip', view: { phase: 'said', text: 'No note was named, so the words stay here.' } }];
  }

  /**
   * A command's words after the keyword: a route, a to-do for here, a new note; held for its name; or no route at all.
   * `whole` is the stretch of the recording it was said over.
   */
  private command(said: string, whole: Segment, ctx: LiveContext<N>, now: number, { atStart, fromHold = false }: { atStart: boolean; fromHold?: boolean }): LiveStep<N>[] | typeof HELD | typeof DONE_READER {
    // "Actually, add a note to House TODOs": the command, said as people say it (takeBack.ts).
    const words = commandAfterOpener(said);
    if (!words || isOpener(words)) {
      this.held = { segments: [whole], why: 'keyword', lastAt: now };
      return HELD;
    }
    // A command said while a note switched to waits for its words: they are not what comes next.
    if (this.routed) this.routed.awaiting = false;
    const readings = [...readRoute(words), ...readNameFirst(words)];
    const chosen = this.choose(readings, ctx);
    if (!chosen) return this.notRoute(words, ctx, { atStart });
    const { found } = chosen;
    const reading = endedAs(chosen.reading, whole.text);
    if (reading.newNote) return this.newNote(ctx, { atStart });
    if (reading.self) return this.self(reading, whole, ctx);
    // An unsure name at the phrase's end, with nothing after it, may still be growing: one more phrase first.
    if (found.status === 'unsure' && !reading.stopped && !reading.payload && !fromHold) {
      this.held = { segments: [whole], why: 'unsure', lastAt: now, name: reading.name };
      return HELD;
    }
    return this.act(reading, found, whole, ctx, now, { atStart });
  }

  /**
   * The best reading of a command: a clear note beats the note being written to, which beats an unsure name, which beats
   * one that matched nothing; then the better score; then the reading that leaves the payload as it was said.
   */
  private choose(readings: readonly Reading[], ctx: LiveContext<N>): { reading: Reading; found: Found<LiveCandidate<N>> } | null {
    const special = readings.find((r) => r.newNote);
    if (special) return { reading: special, found: { status: 'missing', near: [] } };
    const scored = readings
      .filter((r) => !r.self)
      .map((reading) => ({ reading, found: this.find(reading, ctx) }))
      .filter(({ reading, found }) => {
        if (found.status === 'resolved' && this.declined.has(`${found.note.id}|${reading.name.toLowerCase()}`)) return false;
        // "call the electrician" is a name only when a note is plainly called that: "Call log".
        if (reading.verb) return found.status === 'resolved' && found.score >= 0.9 && nameWords(found.note.title).words[0] === nameWords(reading.name).words[0];
        if (reading.nameFirst) return found.status === 'resolved';
        return true;
      });
    const self = readings.find((r) => r.self);
    const rank = (found: Found<LiveCandidate<N>>) => (found.status === 'resolved' ? 4 : found.status === 'current' ? 3 : found.status === 'unsure' ? 2 : 1);
    const score = (found: Found<LiveCandidate<N>>) => (found.status === 'resolved' || found.status === 'unsure' ? found.score : found.status === 'current' ? 1 : 0);
    const better = (a: (typeof scored)[number], b: (typeof scored)[number]): number => {
      if (rank(a.found) !== rank(b.found)) return rank(b.found) - rank(a.found);
      if (score(a.found) !== score(b.found)) return score(b.found) - score(a.found);
      const lead = (r: Reading) => (PAYLOAD_LEAD.test(r.payload) ? 1 : 0);
      if (lead(a.reading) !== lead(b.reading)) return lead(b.reading) - lead(a.reading);
      if (a.reading.stopped !== b.reading.stopped) return a.reading.stopped ? -1 : 1;
      // The same name read two ways: "add fix the tap under Kitchen in home jobs" is under a heading the note has, and
      // "add clean under the sofa in house to-dos" is one to-do, since House TODOs has no heading "the sofa".
      if (a.reading.name.toLowerCase() === b.reading.name.toLowerCase()) {
        const placed = (x: (typeof scored)[number]) => x.reading.heading !== null && x.found.status === 'resolved' && headingIn(x.found.note.note.body, x.reading.heading);
        if (placed(a) !== placed(b)) return placed(a) ? -1 : 1;
        if ((a.reading.heading !== null) !== (b.reading.heading !== null)) return a.reading.heading !== null ? 1 : -1;
        return 0;
      }
      // One name the start of the other: the longer when what it adds is kind words ("house chores"), else the shorter.
      const [short, long] = a.reading.name.length <= b.reading.name.length ? [a, b] : [b, a];
      if (long.reading.name.toLowerCase().startsWith(short.reading.name.toLowerCase())) {
        const extra = nameWords(long.reading.name.slice(short.reading.name.length));
        const kindOnly = extra.words.length > 0 && extra.distinctive.length === 0;
        return (kindOnly ? long : short) === a ? -1 : 1;
      }
      return a.reading.split === b.reading.split ? 0 : a.reading.split ? 1 : -1;
    };
    const ranked = [...scored].sort(better);
    const bestFound = ranked[0];
    if (self && (!bestFound || bestFound.found.status !== 'resolved' || !bestFound.reading.verb)) return { reading: self, found: { status: 'current', heading: null } };
    if (!bestFound) return null;
    // A name from a split point that matched nothing says nothing, unless every reading matched nothing.
    const real = ranked.find((c) => !(c.found.status === 'missing' && c.reading.split));
    return real ?? bestFound;
  }

  /** What a chosen reading of a keyed command does, by how sure the name is. */
  private act(reading: Reading, found: Found<LiveCandidate<N>>, whole: Segment, ctx: LiveContext<N>, now: number, { atStart }: { atStart: boolean }): LiveStep<N>[] {
    const payload = payloadOf(reading.payload);
    if (found.status === 'current') return this.here(reading, payload, whole, ctx, found.heading);
    if (found.status === 'resolved') return this.resolved(reading, found.note, found.score, payload, whole, ctx, now, { atStart });
    if (found.status === 'unsure') {
      if (ctx.locked) return this.keep(keptWords(reading, payload), whole, 'Not sure which note, so the words stay here.');
      // A card never offers a note the words can't go into: "hello trade the book" between two books is no choice.
      const choices = found.candidates.filter((candidate) => this.refusal(candidate, ctx) === null);
      if (!choices.length) return this.keep(payload, whole, this.refusal(found.candidates[0]!, ctx), reading.trailing);
      return this.raise({ form: 'unsure', heading: 'Add to which note?', candidates: choices.slice(0, 3), reading, payload, whole, atStart, now }, ctx);
    }
    const near = found.near.filter((candidate) => this.refusal(candidate, ctx) === null);
    if (!ctx.locked && (near.length || reading.noun)) {
      return this.raise({ form: 'missing', heading: `No note called “${reading.name}”`, candidates: near.slice(0, 2), reading, payload, whole, atStart, now }, ctx);
    }
    return this.keep(keptWords(reading, payload), whole, ctx.locked ? 'No note by that name, so the words stay here.' : `No note called “${reading.name}”, so the words stay here.`, reading.trailing);
  }

  /** A clear note: the take goes there, or its words do, or, for the note already being written to, only how they go. */
  private resolved(reading: Reading, candidate: LiveCandidate<N>, score: number, payload: string, whole: Segment, ctx: LiveContext<N>, now: number, { atStart }: { atStart: boolean }): LiveStep<N>[] {
    const note = candidate.note;
    const refused = this.refusal(candidate, ctx);
    if (refused) return this.keep(payload, whole, refused, reading.trailing);
    if (ctx.aim?.id === note.id) return this.here(reading, payload, whole, ctx, reading.heading);
    const placing = placingFor(note.body, { said: saidOf(reading), heading: reading.heading, move: reading.move });
    // Where the words go, by what they say when they were said: "under Electrical".
    const spot = payload ? (placeTake(note.body, renderNote(payloadWords(whole, payload), '', { titled: false }).markdown, placing).spot ?? spotOf(note.body, placing)) : spotOf(note.body, placing);
    const title = ctx.locked ? 'the note you named' : candidate.title;
    this.engage();
    const steps: LiveStep<N>[] = [];
    const words = withoutFinalStop(commandWordsOf(whole.text));
    const sticky = reading.move || (atStart && !ctx.own && this.routed === null);
    if (sticky) {
      this.routed = { id: note.id, title, awaiting: !payload && !reading.move, name: reading.name, words };
      steps.push(...this.settleTakeBack(), { kind: 'route', note, title, placing, move: reading.move, spot }, { kind: 'haptic', haptic: 'success' });
      steps.push({ kind: 'log', line: `${reading.move ? 'Moved this recording to' : 'Writing to'} ${candidate.title}` });
      steps.push(...this.payload(whole, payload, { task: reading.placing === 'task' }));
      steps.push({ kind: 'chip', view: payload || reading.move ? { phase: 'moved', title, spot } : { phase: 'waiting', title } });
      if (!reading.stopped && score < 1 && !reading.move) this.growing = { reading, score, command: whole, words, into: { kind: 'route' }, note };
    } else {
      const id = this.nextId++;
      const theirs = payloadWords(whole, payload, { task: reading.placing === 'task' });
      for (const piece of theirs) this.record({ kind: 'insert', id }, piece);
      steps.push({ kind: 'insert', id, note, title, placing, segments: theirs }, { kind: 'haptic', haptic: 'success' });
      steps.push({ kind: 'log', line: `Added to ${candidate.title}${spot ? `, ${spot}` : ''}` });
      if (payload) {
        steps.push({ kind: 'insert-end', id });
        if (!reading.stopped && score < 1) this.growing = { reading, score, command: whole, words, into: { kind: 'insert', id }, note };
      } else {
        this.opened = { id, note, title, count: 0, lastAt: now, words };
        steps.push({ kind: 'chip', view: { phase: 'waiting', title } });
      }
    }
    if (reading.trailing) steps.push(this.words({ ...whole, text: sentence(reading.trailing) }));
    return steps;
  }

  /** The note being written to, named: its words go on as they were, only placed as the command said. */
  private here(reading: Reading, payload: string, whole: Segment, ctx: LiveContext<N>, heading: string | null): LiveStep<N>[] {
    this.engage();
    const steps: LiveStep<N>[] = [];
    const task = reading.placing === 'task';
    if (ctx.aim && (heading || task)) steps.push({ kind: 'placing', placing: placingFor(ctx.aim.body, { said: { task }, heading, lane: heading }) });
    // Said for a list ("add milk to the list", "…to Kitchen"), the words are an item of it.
    steps.push(...this.payload(whole, payload, { item: true, task }));
    if (reading.trailing) steps.push(this.words({ ...whole, text: sentence(reading.trailing) }));
    return steps;
  }

  /** "Remind me to call Sam": a to-do in the note being written to. */
  private self(reading: Reading, whole: Segment, ctx: LiveContext<N>): LiveStep<N>[] {
    this.engage();
    const aimed = ctx.aim ? runsOf(ctx.aim.body.split('\n')) : [];
    const task = reading.placing === 'task' || aimed.some((run) => run.style.task) || (ctx.aim !== null && semanticListKind(ctx.aim.body) === 'task');
    const words = this.payload(whole, reading.payload, { item: true, task });
    return words.length ? [...words, { kind: 'haptic', haptic: 'selection' }] : [];
  }

  /** "New note": at the start of a fresh take it is one already. */
  private newNote(ctx: LiveContext<N>, { atStart }: { atStart: boolean }): LiveStep<N>[] {
    if (atStart && !ctx.own && this.routed === null) return [{ kind: 'chip', view: { phase: 'said', text: 'This is a new note already.' } }];
    this.engage();
    this.routed = null;
    // The words so far are sealed with the note they were said for: out of a take-back's reach.
    const steps = this.settleTakeBack();
    this.said = [];
    this.sealedYet = true;
    return [...steps, { kind: 'new-note' }, { kind: 'chip', view: { phase: 'moved', title: 'New note' } }, { kind: 'haptic', haptic: 'selection' }, { kind: 'log', line: 'Started a new note' }];
  }

  /** The words stay where the take is going: the payload kept, the command left out, and why. */
  private keep(payload: string, whole: Segment, why: string | null, trailing = ''): LiveStep<N>[] {
    this.engage();
    const steps: LiveStep<N>[] = [];
    steps.push(...this.payload(whole, payload));
    if (trailing) steps.push(this.words({ ...whole, text: sentence(trailing) }));
    if (why) steps.push({ kind: 'chip', view: { phase: 'said', text: why } }, { kind: 'haptic', haptic: 'warning' }, { kind: 'log', line: why });
    return steps;
  }

  /**
   * A card, holding the command phrase; later phrases go to the page as words. One up already, for an earlier command,
   * takes its default first, Keep here: a card is never dropped with its words.
   */
  private raise(
    {
      form,
      heading,
      candidates,
      reading,
      payload,
      whole,
      atStart,
      now,
      stays,
    }: { form: LiveCard<N>['form']; heading: string; candidates: LiveCandidate<N>[]; reading: Reading; payload: string; whole: Segment; atStart: boolean; now: number; stays?: NonNullable<Pending<N>['stays']> },
    ctx: LiveContext<N>,
  ): LiveStep<N>[] {
    const before = this.pending ? this.settle({ kind: 'keep' }, ctx) : [];
    this.engage();
    const card: LiveCard<N> = { id: this.nextId++, form, heading, candidates, newTitle: titleFor(reading.name), payload: shown(payload) };
    // A take-back's send holds what it would send as the words said since, on the page: a note chosen takes them,
    // and Keep here puts them back where they were and says so (`stays`).
    this.pending = stays ? { card, since: now, command: whole, payload: '', reading, atStart, after: [...stays.after], stays } : { card, since: now, command: whole, payload, reading, atStart, after: [] };
    return [...before, { kind: 'card', card }, { kind: 'haptic', haptic: 'selection' }];
  }

  /**
   * A take-back's send that got no note from its card: the words back where they were, a one-shot's into it (on the
   * page they never left), and a chip says so, or says `why` the note chosen would not take them.
   */
  private restore(pending: Pending<N>, why: string | null = null): LiveStep<N>[] {
    const stays = pending.stays;
    if (!stays) return [];
    const steps: LiveStep<N>[] = [];
    if (stays.from.kind === 'insert') {
      steps.push(this.unword(stays.after));
      for (const piece of stays.after) steps.push(this.place(stays.from, piece));
    }
    const text = why ?? `“${cut(stays.text)}” stays ${stays.from.kind === 'insert' ? 'where it was' : 'here'}.`;
    return [...steps, { kind: 'chip', view: { phase: 'said', text } }];
  }

  /** A spoken answer to the card up now: one of its titles, "the first one", "keep it here", "new note". */
  private spokenAnswer(text: string): CardChoice | null {
    const card = this.pending?.card;
    if (!card) return null;
    const said = withoutFinalStop(text).toLowerCase().replace(/^(?:um+|uh+|er+|ok(?:ay)?|so)[,\s]+/, '');
    if (/^keep(?:\s+it)?\s+here$/.test(said)) return { kind: 'keep' };
    if (/^(?:a\s+)?new\s+note$/.test(said)) return { kind: 'new' };
    const nth = /^the\s+(first|second|third)(?:\s+one)?$/.exec(said);
    if (nth) {
      const chosen = card.candidates[['first', 'second', 'third'].indexOf(nth[1]!)];
      return chosen ? { kind: 'note', id: chosen.id } : null;
    }
    const found = findNote(said, card.candidates);
    return found.status === 'resolved' && found.score >= 0.85 ? { kind: 'note', id: found.note.id } : null;
  }

  /** A card settled, by a tap, a spoken answer, its clock or the end of the recording. */
  private settle(choice: CardChoice, ctx: LiveContext<N>): LiveStep<N>[] {
    const pending = this.pending;
    this.pending = null;
    if (!pending) return [];
    const steps: LiveStep<N>[] = [{ kind: 'card', card: null }];
    if (choice.kind === 'keep') {
      if (pending.declined) return steps;
      if (pending.stays) return [...steps, ...this.restore(pending)];
      return [...steps, ...this.keep(keptWords(pending.reading, pending.payload), pending.command, null, pending.reading.trailing)];
    }
    if (choice.kind === 'new') {
      const title = pending.card.newTitle;
      if (pending.atStart || pending.declined) {
        this.routed = null;
        steps.push(...this.settleTakeBack(), { kind: 'route-new', title, task: pending.reading.placing === 'task' || titleKind(title) === 'task' }, { kind: 'chip', view: { phase: 'moved', title } });
        steps.push(...this.payload(pending.command, pending.payload, { task: pending.reading.placing === 'task' }));
        return steps;
      }
      if (pending.stays) return [...steps, ...this.restore(pending)];
      // Not at the start: a new note for the payload alone, made at Done.
      return [...steps, ...this.keep(pending.payload, pending.command, `The words stay here: a new note for them is made from the start of a recording.`)];
    }
    const candidate = [...pending.card.candidates, ...ctx.notes].find((c) => c.id === choice.id);
    if (!candidate) return pending.stays ? [...steps, ...this.restore(pending)] : steps;
    const refused = this.refusal(candidate, ctx);
    if (refused) {
      if (pending.declined) return [...steps, { kind: 'chip', view: { phase: 'said', text: refused } }];
      if (pending.stays) return [...steps, ...this.restore(pending, refused)];
      return [...steps, ...this.keep(pending.payload, pending.command, refused, pending.reading.trailing)];
    }
    if (pending.atStart || pending.declined) {
      const placing = placingFor(candidate.note.body, { said: saidOf(pending.reading), heading: pending.reading.heading, move: pending.declined !== undefined });
      const spot = spotOf(candidate.note.body, placing);
      this.routed = { id: candidate.id, title: candidate.title, awaiting: false, name: pending.reading.name, words: withoutFinalStop(commandWordsOf(pending.command.text)) };
      steps.push(...this.settleTakeBack(), { kind: 'route', note: candidate.note, title: candidate.title, placing, move: pending.declined !== undefined, spot }, { kind: 'chip', view: { phase: 'moved', title: candidate.title, spot } });
      if (pending.payload) steps.push(...this.payload(pending.command, pending.payload, { task: pending.reading.placing === 'task' }));
      else if (!pending.after.length && !pending.declined) this.routed.awaiting = true;
      return steps;
    }
    const placing = placingFor(candidate.note.body, { said: saidOf(pending.reading), heading: pending.reading.heading });
    const id = this.nextId++;
    const segments = pending.payload ? payloadWords(pending.command, pending.payload, { task: pending.reading.placing === 'task' }) : pending.after;
    // The words said since, sent there instead: out of the take, and out of its better words.
    if (!pending.payload && pending.after.length) steps.push(this.unword(pending.after), ...pending.after.map((segment) => spanStep<N>(segment)));
    for (const segment of segments) this.record({ kind: 'insert', id }, segment);
    steps.push({ kind: 'insert', id, note: candidate.note, title: candidate.title, placing, segments }, { kind: 'insert-end', id }, { kind: 'haptic', haptic: 'success' });
    return steps;
  }

  /** The name the last command ran to the phrase's end with, read again with this phrase. */
  private grow(growing: Growing<N>, segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] | null {
    const joined = `${growing.words} ${withoutFinalStop(segment.text)}`;
    const readings = readRoute(joined).filter((r) => r.shape === growing.reading.shape && r.name.toLowerCase().startsWith(growing.reading.name.toLowerCase()) && r.name.length > growing.reading.name.length);
    const before = new Set(nameWords(growing.reading.name).words.map((w) => w.slice(0, 5)));
    let best: { reading: Reading; found: Found<LiveCandidate<N>> & { status: 'resolved' } } | null = null;
    for (const reading of readings) {
      const found = this.find(reading, ctx);
      if (found.status !== 'resolved' || found.score <= growing.score || this.refusal(found.note, ctx) !== null) continue;
      const title = nameWords(found.note.title);
      const added = nameWords(reading.name.slice(growing.reading.name.length)).words;
      // Grown only by a title word the name lacked, never by one it had ("house" | "Household bills" is words).
      if (!added.some((w) => title.words.includes(w) && !before.has(w.slice(0, 5)))) continue;
      if (!best || found.score > best.found.score) best = { reading, found };
    }
    if (!best) return null;
    const payload = payloadOf(best.reading.payload);
    const steps: LiveStep<N>[] = [{ kind: 'command', span: spanOf(segment) }];
    const note = best.found.note;
    // Over the lock screen, as for any note named: no title said (`resolved`).
    const title = ctx.locked ? 'the note you named' : note.title;
    const placing = placingFor(note.note.body, { said: saidOf(best.reading) });
    const spot = spotOf(note.note.body, placing);
    if (note.id !== growing.note.id) {
      if (growing.into.kind === 'route') {
        this.routed = { id: note.id, title, awaiting: !payload, name: best.reading.name, words: joined };
        steps.push(...this.settleTakeBack(), { kind: 'route', note: note.note, title, placing, move: false, spot });
      } else {
        this.rehome(growing.into.id);
        steps.push({ kind: 'insert-drop', id: growing.into.id });
        const id = this.nextId++;
        steps.push({ kind: 'insert', id, note: note.note, title, placing, segments: [] });
        this.opened = { id, note: note.note, title, count: 0, lastAt: now, words: joined };
      }
    }
    if (payload) {
      if (growing.into.kind === 'route' || best.found.note.id !== growing.note.id) {
        if (this.routed) this.routed.awaiting = false;
        if (growing.into.kind === 'route') steps.push(...this.payload(segment, payload));
        else if (this.opened) {
          const into = this.opened.id;
          steps.push(...payloadWords(segment, payload).map((piece) => this.place({ kind: 'insert', id: into }, piece)), ...this.closeInsert());
        }
      } else {
        const into = growing.into.id;
        steps.push(...payloadWords(segment, payload).map((piece) => this.place({ kind: 'insert', id: into }, piece)));
      }
    }
    steps.push({ kind: 'chip', view: payload ? { phase: 'moved', title, spot } : { phase: 'waiting', title } });
    return steps;
  }

  private closeInsert(): LiveStep<N>[] {
    const opened = this.opened;
    this.opened = null;
    if (!opened) return [];
    return [{ kind: 'insert-end', id: opened.id }];
  }

  /** A keyworded phrase that is no route: for the reader at Done at the take's start, else queued or left out. */
  private notRoute(words: string, ctx: LiveContext<N>, { atStart }: { atStart: boolean }): LiveStep<N>[] | typeof DONE_READER {
    // "Hey Ghost, fix the spelling", "make a list called packing" first: the recording's one command, read at Done as ever.
    if (atStart) return DONE_READER;
    const run = runOf(words);
    this.engage();
    if (this.routed === null && !ctx.locked) {
      const said = capitalise(withoutFinalStop(words));
      return [
        { kind: 'ask', run, instruction: withoutFinalStop(words) },
        { kind: 'chip', view: { phase: 'said', text: `“${said.length > 40 ? `${said.slice(0, 40)}…` : said}” runs when you're done.` } },
        { kind: 'log', line: `Queued “${said}” for after the recording` },
      ];
    }
    return [{ kind: 'chip', view: { phase: 'said', text: "That can't run in the middle of a recording, so it was left out." } }, { kind: 'log', line: `Left out “${withoutFinalStop(words)}”: it can't run mid-recording` }];
  }

  /**
   * A phrase with no keyword: a command only when it passes the bare gate (`bareReading`), carried out as a keyed
   * clear name is: sticky at the start of a fresh recording, a one-shot mid-take, "move this to X" moving the take.
   * Else words, untouched. No card, no hold, no chip: what the keyword adds is `command`, and a "No note called…"
   * card mid-dictation for a sentence that was never a command is the failure that asked for the keyword in the first
   * place (§38). "New note" alone starts one; "another note" does not, since "Another note:" is how people introduce
   * their next point. "Actually, add …" is the command, as after the keyword.
   */
  private bare(segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const words = commandAfterOpener(commandWords(segment.text));
    if (/^new\s+note$/i.test(withoutFinalStop(words))) return [spanStep(segment), ...this.newNote(ctx, { atStart: this.atStart })];
    const chosen = this.bareReading(words, ctx);
    if (!chosen) return [this.words(segment)];
    const reading = endedAs(chosen.reading, segment.text);
    return [spanStep(segment), ...this.resolved(reading, chosen.note, chosen.score, payloadOf(reading.payload), segment, ctx, now, { atStart: this.atStart })];
  }
}

/**
 * A reading with the phrase's own full stop given back to whatever ends it: the grammar reads without it (a phrase-final
 * stop is never a separator), but the words that end the phrase end with it, so a sentence said next starts a new one.
 */
function endedAs(reading: Reading, phrase: string): Reading {
  const end = /([.!?…])["”]?\s*$/.exec(phrase)?.[1] ?? '';
  const open = (text: string) => text !== '' && !/[.!?…]["”]?$/.test(text);
  if (!end) return reading;
  if (reading.trailing) return open(reading.trailing) ? { ...reading, trailing: `${reading.trailing}${end}` } : reading;
  return open(reading.payload) ? { ...reading, payload: `${reading.payload}${end}` } : reading;
}

/** The command's words of a phrase: after the keyword, the lead-ins gone. */
function commandWordsOf(text: string): string {
  const heard = hearKeyword(text, () => true);
  return commandWords(heard ? heard.after : text);
}

/** Whether text lays out as anything: "Bullet point." alone does not, until its item comes. */
function renderable(text: string): boolean {
  return /[\p{L}\p{N}]/u.test(text);
}

/** Where the words will go, in words: "under Electrical", "in its to-do list", or null for the end. */
export function spotOf(body: string, placing: Placing): string | null {
  if (placing.kind === 'end') return null;
  if (placing.kind === 'lane') return `in ${placing.lane}`;
  if (placing.heading) return `under ${placing.heading}`;
  if (placing.fresh) return placing.fresh === 'task' ? 'in a new to-do list' : 'in a new list';
  const runs = runsOf(body.split('\n'));
  if (runs.length === 1) return runs[0]!.style.task ? 'in its to-do list' : 'in its list';
  return placing.task && runs.some((run) => run.style.task) ? 'in its to-do list' : 'in its lists';
}
