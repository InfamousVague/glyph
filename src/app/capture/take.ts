import { renderNote, type Segment } from './markdown.ts';
import type { FinalPlan } from './command.ts';
import { describeOffer, offerFor, type Offer } from './offers.ts';
import type { Span, TakeCandidate, TakeNote } from './takeTypes.ts';
import type { TakeHost } from './takeHost.ts';

// The confirm card (ai/ConfirmCard.tsx) reads offers from here, where the recorder's take makes them.
export type { Offer } from './offers.ts';

/**
 * One recording's words, and the card a command read at Done puts up, as state with no screen and no clock of its own.
 *
 * The recorder (CaptureScreen) keeps the take's words here: each phrase the live reader (liveRoute.ts) says is words
 * arrives by `listen`, which only shows it, and the stretches that were commands are marked for the better words to
 * leave out (`commandSpans`, `keywordSpans`). A command the live reader did not carry out is read once, from the whole
 * transcript, at Done (ai/instruction.ts): words for a note by name, or a new list by name. It is offered here with
 * `offerFinal`, and with the microphone stopped its card waits for a tap - Add or Create (`confirm`), or Cancel
 * (`cancel`). "New note" carries the take on in a fresh note (`fork`).
 */

export class Take<N extends TakeNote> {
  /** The words of the note, as committed phrases (commands taken out). */
  segments: Segment[] = [];
  /** Recording spans that were commands, for the better-words pass to leave out. */
  commandSpans: Span[] = [];
  /** Phrases that were words and then "Glyph": the better words keep only what came before it. */
  keywordSpans: Span[] = [];
  /** Notes other than this one that commands changed. */
  touched = new Set<string>();

  private pending: Offer<N> | null = null;
  constructor(private readonly host: TakeHost<N>) {}

  // ---- the card after Done -------------------------------------------------------------------

  private setPending(offer: Offer<N> | null): void {
    this.pending = offer;
    this.host.offer(offer);
  }

  /** Offer a plan only after the complete capture has been classified. */
  offerFinal(plan: FinalPlan<TakeCandidate<N>>): void {
    this.segments = [];
    this.host.changed();
    const made = offerFor<N>(plan);
    if (!made) return;
    this.setPending(made);
    this.host.route(null);
    this.host.haptic('selection');
  }

  /** Add or Create, tapped: the command does what it showed. A new list is made by the recorder once this is done. */
  confirm(): void {
    const held = this.pending;
    if (!held) return;
    this.setPending(null);
    this.host.log(describeOffer(held, 'done'));
    if (held.kind === 'place') {
      this.touched.add(held.note.id);
      this.host.addItems(held.note, held.text, held.placement);
    } else {
      this.host.route({ phase: 'moved', title: held.title });
    }
  }

  /** Cancel, tapped: nothing happens, and the review's check of commands is told the person said no. */
  cancel(): void {
    if (!this.pending) return;
    this.host.log(describeOffer(this.pending, 'declined'));
    this.setPending(null);
  }

  // ---- carrying on in another note ---------------------------------------------------------------

  /**
   * The take carries on in another note: what it has is that note's, and stays there. The stretches of the tape it
   * came from are marked as commands, so the better words never write them into the next note.
   */
  fork(): void {
    for (const segment of this.segments) this.commandSpans.push({ startMs: segment.startMs, endMs: segment.endMs });
    this.segments = [];
    this.host.changed();
  }

  // ---- a phrase --------------------------------------------------------------------------------------

  /**
   * Listen only.  CaptureScreen uses this for every live Whisper commit: it
   * renders the accumulating transcript but cannot route, infer, write, or
   * derive a note from an incomplete utterance.
   */
  listen(segment: Segment): void {
    const text = segment.text.replace(/^[\s.,;:!?…]+/, '');
    if (!text) return;
    this.segments = [...this.segments, { ...segment, text }];
    this.host.changed();
  }

  /**
   * Whether there is anything to save: words that lay out as something. Read from the laid-out note, as the recorder's
   * Done reads it, so a cue said alone - held for a sentence that never comes - is nothing to save.
   */
  get hasContent(): boolean {
    return renderNote(this.segments).markdown.trim() !== '';
  }

  /** The take's markdown: its words as the cues lay them out. */
  markdown(options: TakeMarkdownOptions): string {
    return takeMarkdown(this, options).markdown;
  }
}

export interface TakeMarkdownOptions {
  /** Whether the words may take a `# title`: not when they go on the end of a note that has one. */
  titled: boolean;
  /** The phrase still being guessed, set after the words and marked as pending. */
  partial?: string;
}

/**
 * A take's markdown, from what it holds: its words as the cues lay them out, and the phrase still being guessed after
 * them. What the page shows as it is spoken and what is saved at Done are this, so they cannot disagree. `pendingFrom`
 * is where the guessed phrase starts, for drawing it lighter.
 */
export function takeMarkdown(take: { readonly segments: readonly Segment[] }, { titled, partial = '' }: TakeMarkdownOptions): { markdown: string; pendingFrom: number | null } {
  const { markdown, pendingFrom } = renderNote(take.segments, partial, { titled });
  return { markdown, pendingFrom };
}
