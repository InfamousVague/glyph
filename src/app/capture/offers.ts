import { chaptersOf, withChapter } from '../book/book.ts';
import { lowerFirst } from '../core/text.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import { sameTitle } from '../editor/wikiLinks.ts';
import type { VoiceCommand } from '../plugins/types.ts';
import type { Placement, Plan } from './command.ts';
import { placeWords } from './listAppend.ts';
import type { Span, TakeCandidate, TakeNote } from './takeTypes.ts';

/**
 * "Shall I?": what a command understood will do, before it does anything.
 *
 * Every command asks first (capture/take.ts). A plan - what the rules or the model read in the words - becomes an
 * offer here: the note it names, the lines as they would land, and what the yes will do, which is what the confirm
 * card draws (ai/ConfirmCard.tsx) and what the take carries out on a yes. Some plans are refused on the way, with the
 * reason said instead: a lane with nothing to add, a chapter a book already has, a book asked to be its own chapter.
 * `describeOffer` puts an offer and what came of it in one sentence, for the review's check of what commands did.
 *
 * Pure, so every plan's offer is a test.
 */

/** A command understood and waiting for yes or no: what it will do, shown on the card. */
export type Offer<N extends TakeNote> =
  | { kind: 'place'; note: N; title: string; text: string; placement: Placement; added: string[]; into: 'list' | 'paragraph'; span: Span }
  | { kind: 'change'; note: N; title: string; heading: string; action: string; lines: string[]; change: (body: string) => string | null; span: Span }
  | { kind: 'move'; note: N; title: string; span: Span }
  | { kind: 'new'; title?: string; lines?: readonly string[]; span: Span }
  | { kind: 'board'; title: string; span: Span }
  | { kind: 'book'; title: string; pages: string[]; span: Span }
  | { kind: 'table'; note: N | null; title: string; columns: string[]; rows: string[][]; markdown: string; span: Span }
  | { kind: 'plugin'; voice: VoiceCommand; parsed: unknown; title: string; action: string; span: Span };

/** What a plan comes to: an offer to ask about, or a reason to say instead. */
export type Offered<N extends TakeNote> = { offer: Offer<N> } | { refused: string };

/** What an offer needs to know about the take it is made in, asked only by the plans that need it. */
export interface OfferContext {
  /** The note being recorded onto, by the title the command list knows it by; null for a new note, which has none yet. */
  ownTitle(): string | null;
  /** The id of the note being recorded onto, or null for a new one. */
  targetId(): string | null;
}

/**
 * The offer `plan` makes, a reason it cannot be made, or null when there is nothing to offer: a plan still waiting
 * (a note named with nothing said for it, a table to be asked for), a name that matched no note, or words that would
 * add nothing to the note they name.
 */
export function offerFor<N extends TakeNote>(plan: Plan<TakeCandidate<N>>, span: Span, context: OfferContext): Offered<N> | null {
  switch (plan.kind) {
    case 'no-note':
    case 'await':
    case 'table':
      return null;
    case 'place': {
      const note = plan.note.note;
      const preview = placeWords(note.body, plan.text, plan);
      if (!preview.added.length) return null;
      return { offer: { kind: 'place', note, title: plan.note.title, text: plan.text, placement: plan, added: preview.added, into: preview.into, span } };
    }
    case 'lane':
    case 'card': {
      const note = plan.note.note;
      const change = plan.change;
      if (change(note.body) === null) {
        return { refused: plan.kind === 'card' ? `No item like “${plan.words}” in ${plan.note.title}.` : `Nothing to add to ${plan.lane}.` };
      }
      return {
        offer: {
          kind: 'change',
          note,
          title: plan.note.title,
          heading: plan.kind === 'card' ? `Move to ${plan.lane}` : `Add to ${plan.lane}`,
          action: plan.kind === 'card' ? 'Move' : 'Add',
          lines: [plan.words],
          change,
          span,
        },
      };
    }
    case 'chapter': {
      // A chapter for a book (docs/BOOKS.md): the title said, or this note's. The change is the index with one more line.
      const note = plan.note.note;
      const title = plan.title ?? context.ownTitle();
      if (title === null) return { refused: 'This note has no name yet, so it can’t be a chapter.' };
      if (sameTitle(title, plan.note.title) || (plan.title === null && context.targetId() === note.id)) {
        return { refused: `${plan.note.title} can’t be a chapter of itself.` };
      }
      if (chaptersOf(note.body).some((chapter) => sameTitle(chapter.title, title))) return { refused: `${title} is already in ${plan.note.title}.` };
      const change = (body: string) => {
        const next = withChapter(body, title);
        return next === body ? null : next;
      };
      return { offer: { kind: 'change', note, title: plan.note.title, heading: 'New chapter', action: 'Add', lines: [title], change, span } };
    }
    case 'book':
      return { offer: { kind: 'book', title: plan.title, pages: plan.pages, span } };
    case 'move':
      return { offer: { kind: 'move', note: plan.note.note, title: plan.note.title, span } };
    case 'board':
      return { offer: { kind: 'board', title: 'this note', span } };
    case 'create-list':
      return { offer: { kind: 'new', title: plan.title, ...(plan.items?.length ? { lines: plan.items } : {}), span } };
    case 'new':
      return { offer: { kind: 'new', span } };
  }
}

/** What a command offered, in words, and what came of it: for the review's check of commands. */
export function describeOffer<N extends TakeNote>(offer: Offer<N>, outcome: 'done' | 'declined' | 'dropped'): string {
  const what =
    offer.kind === 'place'
      ? `add “${offer.added.map(withoutLead).join('”, “')}” to ${offer.title}${offer.into === 'list' ? '’s list' : ' as a paragraph'}`
      : offer.kind === 'change'
        ? `${lowerFirst(offer.heading)}: “${offer.lines.join('”, “')}” in ${offer.title}`
        : offer.kind === 'move'
          ? `move this recording to ${offer.title}`
          : offer.kind === 'new'
            ? offer.title ? `create ${offer.title}` : 'start a new note'
            : offer.kind === 'board'
              ? 'make this note a board'
              : offer.kind === 'table'
                ? `add a table (${offer.columns.join(', ')}; ${offer.rows.length} rows) to ${offer.title}`
                : offer.kind === 'book'
                  ? `make a book called ${offer.title}${offer.pages.length ? ` with ${offer.pages.join(', ')}` : ''}`
                  : lowerFirst(offer.title);
  if (outcome === 'done') return `Did: ${what}`;
  return outcome === 'declined' ? `Offered to ${what}; the person said no` : `Offered to ${what}; nobody answered, so it was not done`;
}
