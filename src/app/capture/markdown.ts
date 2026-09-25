import { capitalise } from '../core/text.ts';
import { isTitleShaped, localBlocks, NUMBER_CUE, ORDINAL_START, renderBlocks, STANDALONE_CUE, TITLE_CUE, type Block } from './spoken/blocks.ts';
import { codeBlocksIn, withCodeBlocksWhole } from './spoken/codeBlocks.ts';
import { finishLines, liftFootnotes, spokenExtras } from './spoken/extras.ts';
import { spokenInlineMarkup } from './spoken/inline.ts';
import { announcesList, inlineNumbering, itemOf, itemShaped, leadsList, opensItem } from './spoken/lists.ts';
import { BREAK_MARK } from './spoken/standIns.ts';
import { stripEnd } from './spoken/words.ts';

/**
 * Speech, turned into a note.
 *
 * Local rules, run on every committed Whisper segment with no network and no
 * delay: they catch the spoken cues the guide teaches ("new paragraph",
 * "bullet point", "heading", "check box", "bold … end bold"), the obvious
 * to-dos ("I need to..."), a spoken enumeration after a word that introduces
 * one ("I need eggs, milk and bread"), and an ordinal run ("first... second...
 * finally..."). Nothing else decides the shape of a note: it is what was said,
 * laid out by what was said.
 *
 * Deliberately heuristic and deliberately high-precision. A rule that turns a
 * sentence into a list it was not is worse than one that misses a list, because
 * a missed list is still readable prose and a false one mangles it; so the
 * enumeration rule demands a list-introducing word before the items, and short
 * items after it, rather than trusting commas.
 *
 * This module is the driver: phrases into paragraphs by pause and cue, paragraphs into sentences, and each sentence
 * through the rule families in spoken/ - inline marks (inline.ts), the marks said inside a sentence (extras.ts),
 * numbers and sums (numbers.ts), lists (lists.ts), code blocks (codeBlocks.ts), and the block cues and how blocks are
 * written out (blocks.ts). What spans sentences is held here: a cue said alone, an item phrase waiting for its item,
 * a list announced, the title.
 */

export interface Segment {
  text: string;
  startMs: number;
  endMs: number;
}

export interface RenderedNote {
  markdown: string;
  /** Where the in-progress, uncommitted phrase begins, or null when there is none. */
  pendingFrom: number | null;
  /** The committed transcript, paragraphs joined by blank lines. */
  plain: string;
}

/**
 * A pause long enough to be a new thought, as the gap between two committed phrases.
 *
 * Not the pause itself. The streamer (src-tauri/src/whisper/stream.rs) cuts a phrase 300 ms into the quiet after it
 * and drops quiet once two seconds of it have built up, keeping 300 ms: so any pause from about 2.3 s to 4 s arrives
 * as a 1.7 s gap between the phrases, and a shorter one as none at all. At 2 s, as this once was, a paragraph break by
 * pausing could never happen on the phone. 1.5 s is a spoken pause of a little over two seconds.
 *
 * The engine commits a segment on a much shorter pause, which is a breath rather than a paragraph; treating every
 * commit as a paragraph break would turn a note into a column of one-line fragments. A little over two seconds is long
 * enough that a speaker thinking mid-sentence does not trigger it. capture/voiceSuite.ts `scriptHeard` times the
 * suite's phrases by the same arithmetic, and voiceMemo.ts closes a memo on the same gap.
 */
export const PARAGRAPH_GAP_MS = 1500;

const PARAGRAPH_CUE = /\b(?:new|next) paragraph\b[.,!?]?/gi;

// ---- paragraphs and sentences ----------------------------------------------

/** Committed segments, grouped into paragraphs by pause length and spoken cue. */
export function toParagraphs(segments: readonly Segment[]): string[] {
  const paragraphs: string[] = [];
  let current = '';
  let lastEnd: number | null = null;

  const flush = () => {
    const text = current.trim();
    if (text) paragraphs.push(capitalise(text));
    current = '';
  };

  for (const segment of segments) {
    const text = segment.text.trim();
    if (!text) continue;
    if (lastEnd !== null && segment.startMs - lastEnd > PARAGRAPH_GAP_MS) flush();
    lastEnd = segment.endMs;

    text.split(PARAGRAPH_CUE).forEach((piece, index) => {
      if (index > 0) flush();
      const part = piece.replace(/^(?:[\s.,;:?]|!(?!\[))+/, '').trim();
      // A phrase after a finished sentence starts one, whatever case Whisper gave it.
      const said = current && /[.!?]$/.test(current) ? capitalise(part) : part;
      if (part) current = current ? `${current} ${said}` : said;
    });
  }
  flush();
  return paragraphs;
}

interface Sentence {
  text: string;
}

/**
 * Where one sentence ends and the next begins: a stop, then a capital. A sentence can start with inline markup
 * ("**Friday** is the deadline"), so asterisks and underscores may come before the capital, and a said line break
 * (spoken/standIns.ts) ends a sentence as a stop does.
 */
const SENTENCE_BOUNDARY = new RegExp(String.raw`(?<=[.!?*_${BREAK_MARK}])\s+(?=["'([*_]*[A-Z0-9])`, 'g');

/**
 * The sentences of a paragraph.
 *
 * Whisper punctuates and capitalises, so a terminal mark followed by a capital
 * is a reliable boundary for speech in a way it is not for typed prose (which
 * has "e.g. Smith" and version numbers).
 */
function sentencesOf(paragraph: string): Sentence[] {
  const out: Sentence[] = [];
  let start = 0;
  for (const match of paragraph.matchAll(SENTENCE_BOUNDARY)) {
    const end = match.index ?? 0;
    const text = paragraph.slice(start, end).trim();
    if (text) out.push({ text });
    start = end + match[0].length;
  }
  const tail = paragraph.slice(start).trim();
  if (tail) out.push({ text: tail });
  return out;
}

// ---- the whole note -------------------------------------------------------------

export interface RenderOptions {
  /**
   * Whether the note may take a `# title`. False for a recording added to the end of a note that has one (a note's
   * own Speak, CaptureScreen.tsx): its opening sentence stays a sentence, and a spoken "Title: …" becomes a
   * `## heading` there rather than a second title mid-note.
   */
  titled?: boolean;
}

/**
 * Committed segments and an optional in-progress phrase, rendered to markdown.
 *
 * Pure, and cheap enough to run on every event: a note is a few hundred words
 * and the engine emits about one event a second.
 */
export function renderNote(
  segments: readonly Segment[],
  partial = '',
  { titled = true }: RenderOptions = {},
): RenderedNote {
  const paragraphs = withCodeBlocksWhole(toParagraphs(segments));
  const plain = paragraphs.join('\n\n');

  const blocks: Block[] = [];
  let title: string | null = null;
  /** A cue said as its own sentence, waiting for the sentence it introduces. */
  let pendingCue: string | null = null;
  /** The title is decided by the first sentence with content, not by a cue before it. */
  let seenContent = false;
  /** A list is open: announced, or begun by an item. Its kind, for the items that follow. */
  let openList: 'number' | 'bullet' | null = null;
  /**
   * Whether short plain sentences join the open list: only when it was
   * announced ("here's my shopping list") or talked into being ("the next item
   * is …"). After a cue ("bullet point, eggs") a short "Thanks." is a reply,
   * not an item.
   */
  let takesShortItems = false;
  /** An item phrase that stopped short ("The next item is."), waiting for its item. */
  let pendingItem: string | null = null;
  /** The phrase waiting was a numbered cue ("number three, the next item is"): the item is numbered. */
  let pendingNumbered = false;
  /** The open list was led by "Pack these.": its items hang under that line, as a list said with a colon does. */
  let ledList = false;
  const paragraphStarts = new Set<number>();
  /** What the spoken footnotes say, in order: written under the note. */
  const footnotes: string[] = [];

  /**
   * The kind an item said as a phrase, or a short item under an announced list, takes: numbered if the list it
   * follows is, bullets otherwise.
   */
  const listKind = (): 'number' | 'bullet' => {
    const last = blocks[blocks.length - 1];
    if (last?.kind === 'number') return 'number';
    if (last?.kind === 'bullet' || last?.kind === 'item') return 'bullet';
    return openList ?? 'bullet';
  };

  paragraphs.forEach((paragraph) => {
    paragraphStarts.add(blocks.length);
    for (const piece of codeBlocksIn(paragraph)) {
      if (piece.kind === 'fence') {
        blocks.push(piece);
        pendingCue = null;
        seenContent = true;
        openList = null;
        takesShortItems = false;
        continue;
      }
      const said = liftFootnotes(piece.text, footnotes);
      const sentences = sentencesOf(spokenExtras(spokenInlineMarkup(inlineNumbering(said))));

      const firstOrdinal = sentences.findIndex((s) => ORDINAL_START.test(s.text));

      sentences.forEach((spoken, sentenceIndex) => {
        const cueOnly = STANDALONE_CUE.exec(spoken.text);
        if (cueOnly?.[1]) {
          pendingCue = cueOnly[1];
          return;
        }
        const sentence: Sentence = pendingCue ? { ...spoken, text: `${pendingCue}: ${spoken.text}` } : spoken;
        pendingCue = null;

        // The item after "the next item is", said as its own phrase. A second
        // item phrase instead means the first was just words.
        if (pendingItem !== null) {
          const held = pendingItem;
          const numbered = pendingNumbered;
          pendingItem = null;
          pendingNumbered = false;
          if (!opensItem(sentence.text) && !itemOf(sentence.text)) {
            const kind = numbered ? 'number' : listKind();
            blocks.push({ kind, text: capitalise(stripEnd(sentence.text)) });
            openList = kind;
            takesShortItems = true;
            return;
          }
          blocks.push({ kind: 'para', text: held });
        }
        if (opensItem(sentence.text)) {
          pendingItem = sentence.text;
          seenContent = true;
          return;
        }
        // "Number three, the next item is", with the item after a breath: the
        // number waits for it too, so the list's count carries on.
        const numberedOpener = NUMBER_CUE.exec(sentence.text);
        if (numberedOpener?.[2] && opensItem(numberedOpener[2])) {
          pendingItem = sentence.text;
          pendingNumbered = true;
          seenContent = true;
          return;
        }

        // The very first sentence can be a spoken title, or a short opening that
        // reads as one.
        if (!seenContent) {
          seenContent = true;
          const cue = TITLE_CUE.exec(sentence.text);
          if (cue?.[1]) {
            const words = capitalise(stripEnd(cue[1]));
            if (titled) title = words;
            else blocks.push({ kind: 'heading', text: words });
            return;
          }
          if (titled && isTitleShaped(sentence.text) && !itemOf(sentence.text)) {
            title = stripEnd(sentence.text);
            openList = announcesList(sentence.text);
            takesShortItems = openList !== null;
            return;
          }
        }

        // A list item said as a phrase ("the next item is …"), or a short item
        // under a list someone announced. It takes the list's kind.
        const item = itemOf(sentence.text);
        if (item) {
          const kind = listKind();
          blocks.push({ kind, text: item });
          openList = kind;
          takesShortItems = true;
          return;
        }

        const ordinalRun = firstOrdinal >= 0 && sentenceIndex >= firstOrdinal;
        const made = localBlocks(sentence.text, ordinalRun);
        // A short plain sentence under an open list is its next item. Only
        // plain: a cue ("number two, …", "then …" in an ordinal run) has
        // already said what the sentence is.
        if (openList && takesShortItems && made.length === 1 && made[0]?.kind === 'para' && itemShaped(sentence.text)) {
          const kind = listKind();
          // "The stove and the lantern." is two things; "bread and butter" is one.
          const parts = stripEnd(sentence.text).split(/\s+and\s+(?=(?:the|a|an|some|two|three)\s)/i);
          for (const part of parts) blocks.push({ kind: ledList && kind === 'bullet' ? 'item' : kind, text: capitalise(part.trim()) });
          openList = kind;
          return;
        }
        const led = made.length === 1 && made[0]?.kind === 'para' && leadsList(sentence.text) && announcesList(sentence.text) !== null;
        // "Pack these." is the line a list hangs from: "Pack these:", like a list said with its colon.
        blocks.push(...(led ? [{ kind: 'intro' as const, text: `${stripEnd(sentence.text)}:` }] : made));
        ledList = led;
        const last = made[made.length - 1];
        const announced = announcesList(sentence.text);
        if (announced) {
          openList = announced;
          takesShortItems = true;
        } else if (last?.kind === 'number' || last?.kind === 'bullet') {
          openList = last.kind;
        } else {
          openList = null;
          takesShortItems = false;
        }
      });
    }
  });

  // A "the next item is" that nothing followed: it was words.
  if (pendingItem !== null) blocks.push({ kind: 'para', text: pendingItem });

  const notes = footnotes.map((note, index) => `[^${index + 1}]: ${note}`).join('\n');
  const laidOut = renderBlocks(blocks, paragraphStarts);
  const body = finishLines(notes ? `${laidOut}${laidOut ? '\n\n' : ''}${notes}` : laidOut);
  let markdown = title ? `# ${title}${body ? `\n\n${body}` : ''}` : body;

  let pendingFrom: number | null = null;
  const tail = partial.trim();
  if (tail) {
    const last = blocks[blocks.length - 1];
    const separator = !markdown ? '' : last?.kind === 'para' ? ' ' : '\n\n';
    pendingFrom = markdown.length + separator.length;
    markdown = `${markdown}${separator}${tail}`;
  }

  return { markdown, pendingFrom, plain };
}
