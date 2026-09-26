import { runOf } from '../ai/instruction.ts';
import type { RunKind } from '../ai/kinds.ts';
import { isBookBody } from '../book/book.ts';
import { capitalise } from '../core/text.ts';
import { onlyFiller, PAYLOAD_LEAD } from './command.ts';
import { commandWords, hearKeyword, isOpener, misheardShape, namedAs, onlyFillerPhrase, onlyLead, payloadOf, readNameFirst, readRoute, silenceLine, withoutFinalStop, type Reading } from './liveCommand.ts';
import { runsOf, semanticListKind } from './listAppend.ts';
import { renderNote, type Segment } from './markdown.ts';
import { FIND, findNote, nameWords, titleKind, type Found } from './noteFind.ts';
import { placeTake, placingFor, type Placing } from './place.ts';
import { TAKE_TIMING } from './take.ts';
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
 *   carries on where it was. "Move this to …" is the one command that moves the take.
 * - "Remind me to…", "add a to-do: …": a to-do in the note being written to (`self`). "New note": a fresh one.
 *
 * Nothing it does is stored: the recorder draws the words where they will go, and Done writes each note once, fresh,
 * through `apply_command` (CaptureScreen.tsx `finish`). So a wrong switch is seen, and put right with Not this note
 * (`decline`), Discard or Undo; nothing has to be taken back from the store. It never deletes or replaces text, and never
 * runs a table, a board, a book, a plugin or an AI run; a run or an ask said mid-take is queued for after Done.
 *
 * With "Commands start with hey Ghost" on (the default), only a phrase that opens with the keyword, or a known mishearing
 * of it followed by a command, is read. With it off, a few plain shapes can route at the very start of a recording.
 * An unsure name, or one that matches nothing but comes near a title, gets a card; no card blocks anything, since each
 * takes Keep here after a while, and at once when the recording ends (`close`).
 *
 * A state machine with its own clock handed in, and no screen: the recorder applies its steps. Pure, so every rule is
 * a test.
 */

/** The live reader's timings, in ms. */
export const LIVE_TIMING = {
  /** A command held for its name: this long after its last phrase, and it gives up. */
  holdMs: TAKE_TIMING.commandQuietMs,
  /** The most phrases a held command waits for its name. */
  holdPhrases: 3,
  /** A name that may still be growing: the next phrase, said this soon after it on the recording, is read with it. */
  growMs: 2500,
  /** A one-shot with nothing said for it: its phrases until a pause this long. */
  itemsQuietMs: TAKE_TIMING.itemsQuietMs,
  /** And at most this many of them. */
  itemsPhrases: 3,
  /** A card up this long takes its default, Keep here. */
  cardMs: 8000,
  /** A resolved name must score this well to route with no keyword said, or after a mishearing of it. */
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
  keywordOn: boolean;
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
}

interface Opened<N extends LiveNote> {
  id: number;
  note: N;
  title: string;
  count: number;
  lastAt: number;
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
  return segments.filter((segment) => !gone.some((g) => g.startMs === segment.startMs && g.endMs === segment.endMs && g.text === segment.text));
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
  private kept = false;
  private engagedYet = false;
  private closed = false;
  private held: Held | null = null;
  private pending: Pending<N> | null = null;
  private opened: Opened<N> | null = null;
  private growing: Growing<N> | null = null;
  /** The note the take was routed to, sticky: `awaiting` while nothing has been said for it yet. */
  private routed: { id: string; title: string; awaiting: boolean; name: string } | null = null;
  private declined = new Set<string>();
  /** Keyworded phrases at the take's start, left as words for the reader at Done (`late`). */
  private doneReader: { segments: Segment[]; words: string }[] = [];
  private nextId = 1;

  /** The reader has done something: routed, inserted, placed, raised a card, kept a payload, queued an ask. */
  get engaged(): boolean {
    return this.engagedYet;
  }

  /** A command is being held, a one-shot is open, or a card is up: the recording stays open. */
  get holding(): boolean {
    return this.held !== null || this.opened !== null || this.pending !== null;
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

  private heard(said: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
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
    // Measured on the recording, from the end of the command to the start of this phrase: a long phrase is committed
    // well after it began.
    if (growing && segment.startMs - growing.command.endMs <= LIVE_TIMING.growMs) {
      const grown = this.grow(growing, segment, ctx, now);
      if (grown) return [...steps, ...grown];
    }

    const keyed = ctx.keywordOn && hearKeyword(text, (words) => this.readsAsRoute(words, ctx)) !== null;
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
      steps.push({ kind: 'command', span: spanOf(segment) }, { kind: 'insert-words', id: opened.id, segments: opened.count === 1 ? payloadWords(segment, text) : [segment] });
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

  /** The clock: holds give up, cards take their default, a one-shot closes after a pause. */
  tick(now: number, ctx: LiveContext<N>): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    if (this.held && now - this.held.lastAt > LIVE_TIMING.holdMs) steps.push(...this.letGoHeld(ctx, now));
    if (this.pending && now - this.pending.since > LIVE_TIMING.cardMs) steps.push(...this.settle({ kind: 'keep' }, ctx));
    if (this.opened && now - this.opened.lastAt > LIVE_TIMING.itemsQuietMs) steps.push(...this.closeInsert());
    return this.late(steps, ctx);
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
    const steps: LiveStep<N>[] = [{ kind: 'home' }, { kind: 'log', line: `Not added to ${routed.title}: the take went back to its own note` }];
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
    return [{ kind: 'insert-drop', id }];
  }

  /** Done, Discard, the side key, the screen off, back: every hold and card settled, before anything is composed. */
  close(ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const steps: LiveStep<N>[] = [];
    if (this.held) steps.push(...this.letGoHeld(ctx, now));
    if (this.pending) steps.push(...this.settle({ kind: 'keep' }, ctx));
    if (this.opened) steps.push(...this.closeInsert());
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

  // ---- reading ----------------------------------------------------------------------------------

  private words(segment: Segment, payload = false): LiveStep<N> {
    if (renderable(segment.text)) this.kept = true;
    return payload ? { kind: 'words', segment, payload } : { kind: 'words', segment };
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
   * Whether `words` after a mishearing of the keyword are a command for a note named clearly (liveCommand.ts
   * `misheardShape`): a note it can write to, never the one being written to.
   */
  private readsAsRoute(words: string, ctx: LiveContext<N>): boolean {
    return misheardShape(commandWords(words), (reading) => {
      const found = this.find(reading, ctx);
      return found.status === 'resolved' && found.score >= LIVE_TIMING.bareScore && this.refusal(found.note, ctx) === null;
    });
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
      out.push({ kind: 'unword', segments }, ...segments.map((segment): LiveStep<N> => ({ kind: 'command', span: spanOf(segment) })));
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
    const atStart = !this.kept && !this.engagedYet;
    const heard = ctx.keywordOn ? hearKeyword(text, (words) => this.readsAsRoute(words, ctx)) : null;
    if (!heard) {
      // "Okay." or "Hey." before the command, or Whisper's "Thank you." on a silence: held for the next phrase.
      if (atStart && ((ctx.keywordOn && onlyLead(text)) || onlyFillerPhrase(text) || silenceLine(text))) {
        this.held = { segments: [segment], why: onlyLead(text) ? 'lead' : 'filler', lastAt: now };
        return [];
      }
      if (!ctx.keywordOn && atStart) return this.bare(segment, ctx, now);
      return [this.words(segment)];
    }
    const before = heard.before.trim();
    const words = before && !onlyFiller(before);
    // "The heating is fixed now, hey Ghost, add…": the words before it are the take's, a phrase of their own.
    const kept: LiveStep<N>[] = words ? [this.words({ ...segment, text: /[.!?…]$/.test(before) ? before : `${before}.` })] : [];
    const mark: LiveStep<N> = words ? { kind: 'keyword', span: spanOf(segment) } : { kind: 'command', span: spanOf(segment) };
    const said = commandWords(heard.after);
    const outcome = this.command(said, segment, ctx, now, { keyed: true, atStart: atStart && !words });
    if (outcome === DONE_READER) return this.leftForDone([segment], said);
    if (outcome === HELD) return [...kept, ...this.heldChip()];
    return [...kept, mark, ...outcome];
  }

  /** The chip while a command is held: "Looking for “house”" once a name is heard, and until then the keyword's. */
  private heldChip(): LiveStep<N>[] {
    const name = this.held?.name;
    const view: RouteView = name ? { phase: 'hearing', name, guess: null, lead: 'Add to' } : { phase: 'command', words: '' };
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
    const heard = ctx.keywordOn ? hearKeyword(joined, (words) => this.readsAsRoute(words, ctx)) : null;
    if (held.why === 'lead' || held.why === 'filler') {
      // "Hey." | "Ghost, add…", "Okay." | "Hey Ghost, add…": one command, or the held phrase given back.
      if (heard && onlyFiller(heard.before)) {
        const said = commandWords(heard.after);
        const outcome = this.command(said, whole, ctx, now, { keyed: true, atStart: true });
        if (outcome === DONE_READER) return this.leftForDone(segments, said);
        if (outcome === HELD) return this.heldChip();
        return [...spans, ...outcome];
      }
      // No command came of it: the held phrase is words after all.
      return [this.words(held.segments[0]!), ...this.read(segment, ctx, now)];
    }
    const words = commandWords(heard ? heard.after : joined);
    if (isOpener(words) && held.why === 'keyword') {
      this.held = { segments, why: held.why, lastAt: now };
      if (segments.length < LIVE_TIMING.holdPhrases) return [{ kind: 'chip', view: { phase: 'command', words } }];
      // This many phrases and still no name: it gives up, as it does after a quiet.
      return this.letGoHeld(ctx, now);
    }
    const outcome = this.command(words, whole, ctx, now, { keyed: true, atStart: !this.kept && !this.engagedYet, fromHold: true });
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
      const outcome = this.command(commandWords(heard?.after ?? first.text), first, ctx, now, { keyed: true, atStart: !this.kept && !this.engagedYet, fromHold: true });
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
  private command(words: string, whole: Segment, ctx: LiveContext<N>, now: number, { keyed, atStart, fromHold = false }: { keyed: boolean; atStart: boolean; fromHold?: boolean }): LiveStep<N>[] | typeof HELD | typeof DONE_READER {
    if (!words || isOpener(words)) {
      this.held = { segments: [whole], why: 'keyword', lastAt: now };
      return HELD;
    }
    // A command said while a note switched to waits for its words: they are not what comes next.
    if (this.routed) this.routed.awaiting = false;
    const readings = [...readRoute(words), ...(keyed ? readNameFirst(words) : [])];
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
    return this.act(reading, found, whole, ctx, now, { keyed, atStart });
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

  /** What a chosen reading does, by how sure the name is. */
  private act(reading: Reading, found: Found<LiveCandidate<N>>, whole: Segment, ctx: LiveContext<N>, now: number, { keyed, atStart }: { keyed: boolean; atStart: boolean }): LiveStep<N>[] {
    const payload = payloadOf(reading.payload);
    if (found.status === 'current') return this.here(reading, payload, whole, ctx, found.heading);
    if (found.status === 'resolved') return this.resolved(reading, found.note, found.score, payload, whole, ctx, now, { atStart });
    if (found.status === 'unsure') {
      if (!keyed || ctx.locked) return this.keep(keptWords(reading, payload), whole, ctx.locked ? 'Not sure which note, so the words stay here.' : null);
      // A card never offers a note the words can't go into: "hello trade the book" between two books is no choice.
      const choices = found.candidates.filter((candidate) => this.refusal(candidate, ctx) === null);
      if (!choices.length) return this.keep(payload, whole, this.refusal(found.candidates[0]!, ctx), reading.trailing);
      return this.raise({ form: 'unsure', heading: 'Add to which note?', candidates: choices.slice(0, 3), reading, payload, whole, atStart, now }, ctx);
    }
    const near = found.near.filter((candidate) => this.refusal(candidate, ctx) === null);
    if (keyed && !ctx.locked && (near.length || reading.noun)) {
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
    const sticky = reading.move || (atStart && !ctx.own && this.routed === null);
    if (sticky) {
      this.routed = { id: note.id, title, awaiting: !payload && !reading.move, name: reading.name };
      steps.push({ kind: 'route', note, title, placing, move: reading.move, spot }, { kind: 'haptic', haptic: 'success' });
      steps.push({ kind: 'log', line: `${reading.move ? 'Moved this recording to' : 'Writing to'} ${candidate.title}` });
      steps.push(...this.payload(whole, payload, { task: reading.placing === 'task' }));
      steps.push({ kind: 'chip', view: payload || reading.move ? { phase: 'moved', title, spot } : { phase: 'waiting', title, many: false, leave: true } });
      if (!reading.stopped && score < 1 && !reading.move) this.growing = { reading, score, command: whole, words: withoutFinalStop(commandWordsOf(whole.text)), into: { kind: 'route' }, note };
    } else {
      const id = this.nextId++;
      steps.push({ kind: 'insert', id, note, title, placing, segments: payloadWords(whole, payload, { task: reading.placing === 'task' }) }, { kind: 'haptic', haptic: 'success' });
      steps.push({ kind: 'log', line: `Added to ${candidate.title}${spot ? `, ${spot}` : ''}` });
      if (payload) {
        steps.push({ kind: 'insert-end', id });
        if (!reading.stopped && score < 1) this.growing = { reading, score, command: whole, words: withoutFinalStop(commandWordsOf(whole.text)), into: { kind: 'insert', id }, note };
      } else {
        this.opened = { id, note, title, count: 0, lastAt: now };
        steps.push({ kind: 'chip', view: { phase: 'waiting', title, many: false, leave: true } });
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
    return [{ kind: 'new-note' }, { kind: 'chip', view: { phase: 'moved', title: 'New note' } }, { kind: 'haptic', haptic: 'selection' }, { kind: 'log', line: 'Started a new note' }];
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
    { form, heading, candidates, reading, payload, whole, atStart, now }: { form: LiveCard<N>['form']; heading: string; candidates: LiveCandidate<N>[]; reading: Reading; payload: string; whole: Segment; atStart: boolean; now: number },
    ctx: LiveContext<N>,
  ): LiveStep<N>[] {
    const before = this.pending ? this.settle({ kind: 'keep' }, ctx) : [];
    this.engage();
    const card: LiveCard<N> = { id: this.nextId++, form, heading, candidates, newTitle: titleFor(reading.name), payload: shown(payload) };
    this.pending = { card, since: now, command: whole, payload, reading, atStart, after: [] };
    return [...before, { kind: 'card', card }, { kind: 'haptic', haptic: 'selection' }];
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
      return [...steps, ...this.keep(keptWords(pending.reading, pending.payload), pending.command, null, pending.reading.trailing)];
    }
    if (choice.kind === 'new') {
      const title = pending.card.newTitle;
      if (pending.atStart || pending.declined) {
        this.routed = null;
        steps.push({ kind: 'route-new', title, task: pending.reading.placing === 'task' || titleKind(title) === 'task' }, { kind: 'chip', view: { phase: 'moved', title } });
        steps.push(...this.payload(pending.command, pending.payload, { task: pending.reading.placing === 'task' }));
        return steps;
      }
      // Not at the start: a new note for the payload alone, made at Done.
      return [...steps, ...this.keep(pending.payload, pending.command, `The words stay here: a new note for them is made from the start of a recording.`)];
    }
    const candidate = [...pending.card.candidates, ...ctx.notes].find((c) => c.id === choice.id);
    if (!candidate) return steps;
    const refused = this.refusal(candidate, ctx);
    if (refused) return [...steps, ...(pending.declined ? [{ kind: 'chip', view: { phase: 'said', text: refused } } as const] : this.keep(pending.payload, pending.command, refused, pending.reading.trailing))];
    if (pending.atStart || pending.declined) {
      const placing = placingFor(candidate.note.body, { said: saidOf(pending.reading), heading: pending.reading.heading, move: pending.declined !== undefined });
      const spot = spotOf(candidate.note.body, placing);
      this.routed = { id: candidate.id, title: candidate.title, awaiting: false, name: pending.reading.name };
      steps.push({ kind: 'route', note: candidate.note, title: candidate.title, placing, move: pending.declined !== undefined, spot }, { kind: 'chip', view: { phase: 'moved', title: candidate.title, spot } });
      if (pending.payload) steps.push(...this.payload(pending.command, pending.payload, { task: pending.reading.placing === 'task' }));
      else if (!pending.after.length && !pending.declined) this.routed.awaiting = true;
      return steps;
    }
    const placing = placingFor(candidate.note.body, { said: saidOf(pending.reading), heading: pending.reading.heading });
    const id = this.nextId++;
    const segments = pending.payload ? payloadWords(pending.command, pending.payload, { task: pending.reading.placing === 'task' }) : pending.after;
    // The words said since, sent there instead: out of the take, and out of its better words.
    if (!pending.payload && pending.after.length) steps.push({ kind: 'unword', segments: pending.after }, ...pending.after.map((segment): LiveStep<N> => ({ kind: 'command', span: spanOf(segment) })));
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
        this.routed = { id: note.id, title, awaiting: !payload, name: best.reading.name };
        steps.push({ kind: 'route', note: note.note, title, placing, move: false, spot });
      } else {
        steps.push({ kind: 'insert-drop', id: growing.into.id });
        const id = this.nextId++;
        steps.push({ kind: 'insert', id, note: note.note, title, placing, segments: [] });
        this.opened = { id, note: note.note, title, count: 0, lastAt: now };
      }
    }
    if (payload) {
      if (growing.into.kind === 'route' || best.found.note.id !== growing.note.id) {
        if (this.routed) this.routed.awaiting = false;
        if (growing.into.kind === 'route') steps.push(...this.payload(segment, payload));
        else if (this.opened) steps.push({ kind: 'insert-words', id: this.opened.id, segments: payloadWords(segment, payload) }, ...this.closeInsert());
      } else {
        steps.push({ kind: 'insert-words', id: growing.into.id, segments: payloadWords(segment, payload) });
      }
    }
    steps.push({ kind: 'chip', view: payload ? { phase: 'moved', title, spot } : { phase: 'waiting', title, many: false, leave: true } });
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

  /** With the keyword off, at the very start: only the plainest shapes, a clear name, and a note that holds lists. */
  private bare(segment: Segment, ctx: LiveContext<N>, now: number): LiveStep<N>[] {
    const words = commandWords(segment.text);
    const readings = readRoute(words).filter((r) => !r.self && !r.newNote && !r.verb && (r.shape === 1 || r.shape === 2 || (r.shape === 3 && r.stopped) || nameWords(r.name).generic.length + nameWords(r.name).specific.length > 0));
    const chosen = this.choose(readings, ctx);
    if (!chosen || chosen.found.status !== 'resolved' || chosen.found.score < LIVE_TIMING.bareScore) return [this.words(segment)];
    const note = chosen.found.note;
    const reading = endedAs(chosen.reading, segment.text);
    // A kind word in its title ("House TODOs", "Task Management"), or a list in it.
    const kinds = nameWords(note.title);
    const evidence = kinds.specific.length + kinds.generic.length > 0 || runsOf(note.note.body.split('\n')).length > 0;
    if (!evidence) return [this.words(segment)];
    return [{ kind: 'command', span: spanOf(segment) }, ...this.resolved(reading, note, chosen.found.score, payloadOf(reading.payload), segment, ctx, now, { atStart: true })];
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
