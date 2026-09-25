import { capitalise } from '../../core/text.ts';
import { itemOf, enumeration } from './lists.ts';
import { SMALL_NUMBER, spokenSum } from './numbers.ts';
import { ANCHOR_MARK, BREAK_MARK } from './standIns.ts';
import { stripEnd, words } from './words.ts';

/**
 * The cues that make a sentence a block of its own - "heading", "bullet point", "check box", "quote", "divider",
 * "callout", "option", "calculate", "define … as …", "I need to …" - and how the blocks are written out, with the
 * blank lines between them that markdown reads as where one list ends and the next thing begins.
 *
 * One sentence at a time (`localBlocks`), then the whole note's blocks together (`renderBlocks`), which is where
 * consecutive items of one kind become one list. capture/markdown.ts `renderNote` decides which sentences get here and
 * holds what spans sentences: a cue said alone, an item phrase waiting for its item, a list announced. Pure.
 */

const HEADING_CUE = /^(?:new\s+section|section|heading)[:,.]?\s+(.+)$/i;
const SUBHEADING_CUE = /^(?:sub[\s-]?heading|sub[\s-]?section|smaller\s+heading)[:,.]?\s+(.+)$/i;
const BULLET_CUE = /^(?:bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet))[:,.]?\s+(.+)$/i;
export const TITLE_CUE = /^(?:title|note\s+title|call\s+(?:this|it)(?:\s+no(?:te|de))?)[:,.]?\s+(.+)$/i;
const IMPORTANT_CUE = /^(important|key\s+point|note)[:,]\s*(.+)$/i;
const TASK = /^(?:(?:i|we)\s+(?:really\s+)?(?:need|have|got)\s+to|remember\s+to|don'?t\s+forget\s+to|do\s+not\s+forget\s+to|remind\s+me\s+to|to[\s-]?do[:,]?|task[:,])\s+(.+)$/i;
const ORDINAL = /^(first(?:ly)?|second(?:ly)?|third(?:ly)?|fourth(?:ly)?|fifth(?:ly)?|next|then|after\s+that|finally|lastly)[,:]?\s+(.+)$/i;
/** "First", which makes the "then" and "next" after it in the paragraph list items rather than joins. */
export const ORDINAL_START = /^first(?:ly)?\b/i;

/*
 * Cues added for the "how to talk to Glyph" guide. Each one that could be
 * ordinary speech demands the comma or colon Whisper writes after a spoken
 * pause, because that pause is the only thing separating a command from a
 * sentence: "Number one, book flights" is a list item, "number one priority is
 * sleep" is prose, and only the comma tells them apart.
 */
const QUOTE_CUE = /^quote[:,]\s*(.+)$/i;
export const NUMBER_CUE = new RegExp(String.raw`^number\s+(${SMALL_NUMBER})[:,]\s*(.+)$`, 'i');
const CHECKBOX_CUE = /^(?:check(?:ed)?\s?box[:,.]?|checklist(?:\s+item)?[:,]|check\s+item[:,])\s*(.+)$/i;
const DIVIDER_CUE = /^(?:divider|horizontal\s+(?:line|rule)|separator)[.!]?$/i;
/** "Callout: the gate sticks", "warning callout: mind the step": a GitHub callout (`> [!NOTE]`), a note unless said otherwise. */
const CALLOUT_CUE = /^(?:(note|tip|important|warning|caution)\s+)?(?:callout[:,.]?|call[\s-]out[:,.]|info\s?box[:,.]?)\s*(.+)$/i;
/** "Hidden line: it was the butler": a line kept in smoke until it is tapped (`>|`). */
const HIDDEN_CUE = /^(?:hidden|secret|spoiler)\s+line[:,.]\s*(.+)$/i;
/** "Option: tent", "picked option: hotel": choices, one of them picked (`- ( )`, `- (x)`). */
const CHOICE_CUE = /^(?:(pick(?:ed)?|pict|chosen|selected)[\s-]*)?(?:option|choice|auction)[:,.]\s*(.+)$/i;
/** "Calculate: four hundred fifty plus one hundred twenty": a sum, worked out on the page (`= 450 + 120`). */
const SUM_CUE = /^(?:calculate|sum|add\s+up)[:,.]\s*(.+)$/i;
/**
 * "Done task: call Sam": a to-do already done (`- [x]`). A bare "done" is a reply, not a cue, and "checked box" is how
 * Whisper hears "check box" often enough that it stays an open one.
 */
const DONE_CUE = /^(?:ticked\s+(?:box|off|item)|done\s+(?:item|task|to[\s-]?do)|finished\s+(?:item|task|to[\s-]?do))[:,.]?\s+(.+)$/i;
/** "Define deposit as what you pay up front": a term and its meaning (`Deposit` / `: What you pay up front`). */
const DEFINE_CUE = /^(?:define|definition(?:\s+of)?)[:,]?\s+(?!(?:your|my|our|his|her|their|them|it|this|that|what|how|a|an)\b)(.+?)[,]?\s+(?:as|means|is)[:,]?\s+(.+)$/i;

/**
 * A cue said on its own, as its own sentence.
 *
 * The way people actually dictate a command is word, pause, content - and
 * Whisper writes the pause as a full stop, so "Heading. Groceries." arrives as
 * two sentences and the cue regexes above, which expect the content in the same
 * sentence, never saw it: the note got the literal word "Heading." Now a
 * sentence that is nothing but a cue is held and applied to the next sentence,
 * across a paragraph break if the pause was long.
 *
 * It doubles as the guard against prompt leakage. Whisper is prompted with the
 * cue vocabulary so it spells cue words consistently, and a model prompted with
 * words can echo them on a quiet window. An echoed "Bullet point." with nothing
 * after it is held forever and never rendered, instead of appearing in the note.
 */
export const STANDALONE_CUE = new RegExp(
  String.raw`^(title|note\s+title|call\s+(?:this|it)(?:\s+no(?:te|de))?|heading|section|new\s+section|sub[\s-]?heading|sub[\s-]?section|call[\s-]?out|info\s?box|hidden\s+line|option|choice|(?:pick(?:ed)?|pict|chosen|selected)[\s-]*option|calculate|checked\s?box|ticked\s+box|done\s+(?:item|task|to[\s-]?do)|bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet)|quote|check\s?box|checklist(?:\s+item)?|check\s+item|to[\s-]?do|task|important|key\s+point|number\s+${SMALL_NUMBER})[.,:!]?$`,
  'i',
);

export type Block =
  | { kind: 'para'; text: string }
  | { kind: 'heading'; text: string }
  | { kind: 'bullet'; text: string }
  /** One entry of a spoken enumeration: a bullet that belongs to its intro, not to its neighbours. */
  | { kind: 'item'; text: string }
  | { kind: 'number'; text: string }
  | { kind: 'task'; text: string }
  | { kind: 'intro'; text: string }
  | { kind: 'quote'; text: string }
  | { kind: 'rule'; text: string }
  | { kind: 'subheading'; text: string }
  /** A line that stands out ("Important: …"): its own paragraph, never run into the next. */
  | { kind: 'standout'; text: string }
  | { kind: 'callout'; text: string; type: string }
  | { kind: 'hidden'; text: string }
  | { kind: 'choice'; text: string; picked: boolean }
  | { kind: 'sum'; text: string }
  | { kind: 'done'; text: string }
  | { kind: 'definition'; text: string; term: string }
  | { kind: 'fence'; text: string; lang: string };

/**
 * Which run a block belongs to, for deciding where blank lines go.
 *
 * An enumeration is its own family, separate from spoken bullets and to-dos,
 * because it is a CLOSED list: "for the drive we want snacks, water and a
 * charger" is complete when the sentence ends. Sharing a family let the next
 * sentence's to-do ("ask Sam about the dog") render as a fifth item of the
 * snacks list, which is a claim about the note Matt never made. Spoken bullets
 * and to-dos, by contrast, are open lists that grow a sentence at a time, so
 * consecutive ones do merge.
 */
const family = (block: Block): string => {
  switch (block.kind) {
    case 'item':
    case 'intro':
      return 'items';
    case 'bullet':
    case 'task':
    case 'done':
      return 'bullets';
    case 'number':
      return 'numbers';
    case 'quote':
      return 'quotes';
    case 'choice':
      return 'choices';
    case 'hidden':
      return 'hidden';
    default:
      return block.kind;
  }
};

/**
 * Blocks for one sentence under the local rules.
 *
 * `ordinalRun` is decided per paragraph by the caller, because "then" and
 * "next" only start list items once a "first" has made the run a list; on
 * their own they are just how people join clauses.
 */
export function localBlocks(text: string, ordinalRun: boolean): Block[] {
  const heading = HEADING_CUE.exec(text);
  if (heading?.[1]) return [{ kind: 'heading', text: capitalise(stripEnd(heading[1])) }];

  const subheading = SUBHEADING_CUE.exec(text);
  if (subheading?.[1]) return [{ kind: 'subheading', text: capitalise(stripEnd(subheading[1])) }];

  const callout = CALLOUT_CUE.exec(text);
  if (callout?.[2]) return [{ kind: 'callout', type: (callout[1] ?? 'note').toLowerCase(), text: capitalise(callout[2].trim()) }];

  const hidden = HIDDEN_CUE.exec(text);
  if (hidden?.[1]) return [{ kind: 'hidden', text: capitalise(hidden[1].trim()) }];

  const choice = CHOICE_CUE.exec(text);
  if (choice?.[2]) return [{ kind: 'choice', picked: Boolean(choice[1]), text: capitalise(stripEnd(choice[2])) }];

  const sum = SUM_CUE.exec(text);
  const worked = sum?.[1] ? spokenSum(sum[1]) : null;
  if (worked) return [{ kind: 'sum', text: `= ${worked}` }];

  const done = DONE_CUE.exec(text);
  if (done?.[1]) return [{ kind: 'done', text: itemOf(done[1]) ?? capitalise(stripEnd(done[1])) }];

  const defined = DEFINE_CUE.exec(text);
  if (defined?.[1] && defined[2] && words(defined[1]) <= 3) return [{ kind: 'definition', term: capitalise(stripEnd(defined[1])), text: capitalise(defined[2].trim()) }];

  const bullet = BULLET_CUE.exec(text);
  if (bullet?.[1]) return [{ kind: 'bullet', text: itemOf(bullet[1]) ?? capitalise(stripEnd(bullet[1])) }];

  const important = IMPORTANT_CUE.exec(text);
  if (important?.[1] && important[2]) {
    return [{ kind: 'standout', text: `**${capitalise(important[1])}:** ${capitalise(important[2])}` }];
  }

  if (DIVIDER_CUE.test(text)) return [{ kind: 'rule', text: '---' }];

  const quote = QUOTE_CUE.exec(text);
  if (quote?.[1]) return [{ kind: 'quote', text: capitalise(quote[1].trim()) }];

  const numbered = NUMBER_CUE.exec(text);
  if (numbered?.[2]) return [{ kind: 'number', text: itemOf(numbered[2]) ?? capitalise(stripEnd(numbered[2])) }];

  const checkbox = CHECKBOX_CUE.exec(text);
  if (checkbox?.[1]) return [{ kind: 'task', text: itemOf(checkbox[1]) ?? capitalise(stripEnd(checkbox[1])) }];

  const task = TASK.exec(text);
  if (task?.[1]) return [{ kind: 'task', text: capitalise(stripEnd(task[1])) }];

  if (ordinalRun) {
    const ordinal = ORDINAL.exec(text);
    if (ordinal?.[2]) return [{ kind: 'number', text: capitalise(stripEnd(ordinal[2])) }];
  }

  const list = enumeration(text);
  if (list) {
    return [
      { kind: 'intro', text: `${list.intro}:` },
      ...list.items.map((item): Block => ({ kind: 'item', text: item })),
    ];
  }

  return [{ kind: 'para', text }];
}

/**
 * `paragraphStarts` holds the index of the first block each spoken paragraph
 * produced. Sentences of one paragraph arrive as separate prose blocks and are
 * joined back into one line; two prose blocks either side of a paragraph break
 * (a spoken "new paragraph", or a long pause) must not be.
 */
export function renderBlocks(blocks: readonly Block[], paragraphStarts: ReadonlySet<number> = new Set()): string {
  const out: string[] = [];
  let previous: Block | null = null;
  let number = 0;

  for (const [index, block] of blocks.entries()) {
    if (block.kind !== 'number') number = 0;
    const joined = previous?.kind === 'para' && block.kind === 'para' && !paragraphStarts.has(index);
    // An intro always opens a new run. Written straight under a list line,
    // markdown reads "For food we want:" as a lazy continuation of the item
    // above it rather than as the start of a new list - it rendered inside a
    // to-do before this rule existed.
    const sameRun =
      previous !== null &&
      family(previous) === family(block) &&
      block.kind !== 'para' &&
      block.kind !== 'intro' &&
      block.kind !== 'standout' &&
      block.kind !== 'callout' &&
      block.kind !== 'sum' &&
      block.kind !== 'fence' &&
      block.kind !== 'heading' &&
      block.kind !== 'subheading';

    if (joined) {
      out[out.length - 1] = `${out[out.length - 1]} ${block.text}`;
    } else {
      if (previous !== null && !sameRun) out.push('');
      switch (block.kind) {
        case 'heading':
          out.push(`## ${block.text}`);
          break;
        case 'bullet':
        case 'item':
          out.push(`- ${block.text}`);
          break;
        case 'task':
          out.push(`- [ ] ${block.text}`);
          break;
        case 'done':
          out.push(`- [x] ${block.text}`);
          break;
        case 'definition':
          out.push(block.term, `: ${block.text}`);
          break;
        case 'fence':
          out.push(`\`\`\`${block.lang}`, block.text, '```');
          break;
        case 'number':
          number += 1;
          out.push(`${number}. ${block.text}`);
          break;
        case 'quote':
          out.push(`> ${block.text}`);
          break;
        case 'subheading':
          out.push(`### ${block.text}`);
          break;
        case 'callout':
          out.push(`> [!${block.type.toUpperCase()}]`, `> ${block.text}`);
          break;
        case 'hidden':
          out.push(`>| ${block.text}`);
          break;
        case 'choice':
          out.push(`- (${block.picked ? 'x' : ' '}) ${block.text}`);
          break;
        case 'rule':
          // Always behind a blank line (a different family from anything
          // before it): `---` straight under a line of text is a setext
          // underline, which would turn that text into a heading.
          out.push('---');
          break;
        default:
          out.push(block.text);
      }
    }
    previous = block;
  }
  return out.join('\n');
}

/**
 * Marked words, a clip or a picture: something said to be kept as it is, not a name for the note. The stand-ins count
 * too (spoken/standIns.ts): a line's name, the bookmark or a break said in the first sentence make it a line, not a
 * title.
 */
const KEPT_AS_SAID = new RegExp(String.raw`\*\*|~~|==|%%|\?\?|\^\^|\+\+|\|\||` + '`' + String.raw`|!\[|\[\[|\[\^|\]\(|<https?:|[\^~$${ANCHOR_MARK}-${BREAK_MARK}]|:[a-z_+-]+:|(?:^|\s)_\S`);

/**
 * Whether an opening sentence reads as a title: short, not a question, and not
 * something the local rules would rather make a list item or a to-do. "Grocery
 * run." is a title; "I need to call the bank." is a task that happens to be
 * first.
 */
export function isTitleShaped(text: string): boolean {
  if (/\?$/.test(text.trim())) return false;
  if (KEPT_AS_SAID.test(text)) return false;
  if (words(text) > 6) return false;
  if (
    TASK.test(text) ||
    BULLET_CUE.test(text) ||
    HEADING_CUE.test(text) ||
    QUOTE_CUE.test(text) ||
    NUMBER_CUE.test(text) ||
    CHECKBOX_CUE.test(text) ||
    DIVIDER_CUE.test(text) ||
    IMPORTANT_CUE.test(text) ||
    SUBHEADING_CUE.test(text) ||
    CALLOUT_CUE.test(text) ||
    HIDDEN_CUE.test(text) ||
    CHOICE_CUE.test(text) ||
    SUM_CUE.test(text) ||
    DONE_CUE.test(text) ||
    DEFINE_CUE.test(text) ||
    enumeration(text)
  ) {
    return false;
  }
  return true;
}
