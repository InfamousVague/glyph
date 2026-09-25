import { isBookBody } from '../book/book.ts';
import { lanesOf } from '../core/boards.ts';
import { lowerFirst } from '../core/text.ts';

/**
 * What the recorder suggests saying: the spoken cues that shape a note, the
 * routing commands, and the asks the AI takes.
 *
 * Two shapes. Before the first word, a card of them (`starters`, drawn by
 * SayCard.tsx; Matt: "when I open the AI page, I should see a list of
 * suggested prompts / commands"): a couple of each kind, so the whole of what
 * can be said is on the page while the microphone waits. Then, in a pause
 * (`tips`), one line at a time, never the same one twice in a row, gone when
 * talking resumes. The list follows the cues `markdown.ts` actually
 * understands and the commands `capture/command.ts` reads, so a tip is always
 * something that works. The routing tip names one of your own notes, which
 * teaches the command better than a made-up title.
 *
 * The asks the AI takes (`ASKS`) are on the card alone, and only when the
 * recording is a note's own Speak: an ask is read from the whole take
 * (ai/instruction.ts `bareWords` wants the keyword to open it), so it is
 * something to say first, into a note that exists, not a cue for a pause.
 */

export interface Tip {
  /** The words to say, shown in quotes. */
  say: string;
  /** What saying them does, read after the words: Say “Check box” to make a to-do. */
  does: string;
}

const CUES: readonly Tip[] = [
  { say: 'Bullet point', does: 'to start a list' },
  { say: 'The next item is …', does: 'to add to a list' },
  { say: 'Heading', does: 'and then its words to start a section' },
  { say: 'Check box', does: 'to make a to-do' },
  { say: 'New paragraph', does: 'to break the text' },
  { say: 'Title', does: 'first to name the note' },
  { say: 'Bold … end bold', does: 'around words to make them stand out' },
  { say: 'Quote', does: 'for something someone said' },
  { say: 'Number one', does: 'to start a numbered list' },
  { say: 'Divider', does: 'to draw a line' },
  { say: 'Subheading', does: 'for a section inside a section' },
  { say: 'Option', does: 'for each choice, and “picked option” for the one you chose' },
  { say: 'Info box', does: 'to set a line apart in a box' },
  { say: 'Hidden line', does: 'to keep a line in smoke until it is tapped' },
  { say: 'Calculate', does: 'and then a sum, to see its answer' },
  { say: 'Hashtag', does: 'and a word to tag a line' },
  { say: 'Counter zero of eight', does: 'after an item to count it off' },
  { say: 'Voice memo … end memo', does: 'to keep the sound instead of the words' },
  { say: 'Italic … end italic', does: 'around words to lean them' },
  { say: 'Strike … end strike', does: 'to cross words out' },
  { say: 'Code … end code', does: 'around a command' },
  { say: 'Done task', does: 'for a to-do that is already done' },
  { say: 'Link … to … end link', does: 'with words and an address, “attack dot fm”' },
  { say: 'Note link … end link', does: 'around a note’s name to link to it' },
  { say: 'Footnote … end footnote', does: 'for small print under the note' },
  { say: 'Bookmark this', does: 'at the end of a line to open the note there' },
  { say: 'Define … as …', does: 'to write a term and its meaning' },
  { say: 'Emoji', does: 'and its name, like “emoji party popper”' },
  { say: 'New line', does: 'between two pauses to break a line' },
  { say: 'Code block … end code block', does: 'for lines of code, one a sentence' },
  { say: 'Maths … end maths', does: 'around a formula, “x squared plus y”' },
  { say: 'Superscript … end superscript', does: 'to raise words, and “subscript” to lower them' },
  { say: 'Anchor … end anchor', does: 'to name an item, and “item link … end link” to point at it' },
];

/**
 * The asks the AI takes, said first into a note's own Speak (ai/instruction.ts `runOf`; CaptureScreen.tsx `finish`):
 * the words are read as an instruction rather than written into the note, the take is let go, and the run lands in
 * the note as it opens, every change marked until kept or reverted. Each is held to the reader's rules by a test.
 */
export const ASKS: readonly Tip[] = [
  { say: 'Fix the spelling', does: 'and the note is checked as it opens, every change marked' },
  { say: 'Summarize this', does: 'for the point of the note in far fewer words' },
  { say: 'Make this a list', does: 'to shape what was said into tasks, a list or a table' },
  { say: 'Tidy this up', does: 'to format the note, keeping every word that matters' },
  { say: 'Carry on', does: 'and the AI writes on from the last line in the note’s own voice' },
];

/**
 * The tips, in the order they come round. `noteTitle` is a recent note's
 * title for the routing tip; `continuing` says a note is already being added
 * to, which is when "new note" is worth knowing; `book` is one of the library's
 * books, for the chapter tip.
 */
export function tips({
  noteTitle,
  continuing,
  keyword = true,
  lane = null,
  book = null,
}: {
  noteTitle?: string | null;
  continuing: boolean;
  keyword?: boolean;
  lane?: string | null;
  /** A book in the library, for the chapter tip; with none, the tip is how to make one (docs/BOOKS.md). */
  book?: string | null;
}): Tip[] {
  const say = (command: string) => (keyword ? `Hey Ghost, ${lowerFirst(command)}` : command);
  const route: Tip[] = [];
  if (noteTitle) route.push({ say: say(`Add … to ${noteTitle}`), does: 'to put it there, into its list if it has one' });
  if (noteTitle) route.push({ say: say(`New item for ${noteTitle}`), does: 'and then the item, to add to its list' });
  // On a note with a board, its lanes can be named (core/boards.ts).
  if (lane) route.push({ say: say(`Add … to ${lane}`), does: 'to put a card in that lane' });
  if (lane) route.push({ say: say(`Move … to ${lane}`), does: 'to move a card there' });
  if (continuing) route.push({ say: say('New note'), does: 'to start a fresh one' });
  if (noteTitle) route.push({ say: say(`Move this to ${noteTitle}`), does: 'to send this recording there' });
  if (noteTitle) route.push({ say: say(`Add a table to ${noteTitle}`), does: 'and it asks for the columns and rows' });
  if (book) route.push({ say: say(`Add a chapter to ${book}`), does: 'and then its name, to put a page in that book' });
  else route.push({ say: say('Make a book called …'), does: 'to start a book; name notes after “with” to be its pages' });
  // Routing first and then every few cues, since it is the least discoverable; a routing line the cues leave no slot
  // for (a note with a board names its lanes too) comes round after them rather than never.
  const out: Tip[] = [];
  CUES.forEach((cue, i) => {
    if (i % 3 === 0 && route[i / 3]) out.push(route[i / 3]!);
    out.push(cue);
  });
  out.push(...route.slice(Math.ceil(CUES.length / 3)));
  return out;
}

/**
 * The tip for this pause (CaptureScreen.tsx shows it until words come again): the `turn`th of the tips, round and
 * round, then the switched-on plugins' own. The routing tip names the most recent note that is not the one being
 * written to; a continued note with a board names one of its lanes, the second when it has one, since the first is
 * usually the one things start in; the chapter tip names a book in the library. With the keyword on, the plugins' tips
 * are said after it, as every command is.
 */
export function tipInPause({
  notes,
  own,
  target,
  keyword,
  pluginTips,
  turn,
}: {
  /** The notes a command can name, most recent first. */
  notes: readonly { id: string; title: string; note: { body: string } }[];
  /** The id of the note being written to, which no tip sends words to. */
  own: string;
  /** The note being continued, or null for a new one. */
  target: { body: string } | null;
  keyword: boolean;
  /** The switched-on plugins' tips, for the routing tip's note (plugins/registry.ts `tips`). */
  pluginTips: (recent: string | null) => readonly Tip[];
  /** How many tips have been shown this recording. */
  turn: number;
}): Tip | null {
  const recent = notes.find((c) => c.id !== own)?.title ?? null;
  const theirs = pluginTips(recent).map((t) => (keyword ? { ...t, say: `Hey Ghost, ${lowerFirst(t.say)}` } : t));
  const lane = target ? ((lanesOf(target.body)[1] ?? lanesOf(target.body)[0])?.name ?? null) : null;
  const book = notes.find((c) => c.id !== own && isBookBody(c.note.body))?.title ?? null;
  const list = [...tips({ noteTitle: recent, continuing: target !== null, keyword, lane, book }), ...theirs];
  return list[turn % list.length] ?? null;
}

/** What the card before the first word shows, and in what order. */
export interface Starters {
  /** How to shape the note: the first few cues. */
  shape: Tip[];
  /** Where to send it: adding to a note by name, and moving the recording. */
  send: Tip[];
  /** What to ask the AI to do with the note; empty where an ask cannot run. */
  ask: Tip[];
}

/** How many of each the card holds: enough to show the shape of each kind, few enough to fit above the buttons on a phone. */
const EACH = 2;

/**
 * The card's suggestions, a couple of each kind (SayCard.tsx). The sending pair names a note of theirs when there is
 * one to name, and a book's chapter over moving the recording when the library has a book; with nothing to name, the
 * pair makes something new, so a first recording still sees that a recording can go somewhere. The asks are there
 * only when `asking`: the recording is a note's own Speak, not over the lock screen, which is the one case an ask said
 * first is run (CaptureScreen.tsx `finish`); a new recording is given none rather than a line that would end as a
 * note of the command's words.
 */
export function starters({
  noteTitle,
  keyword = true,
  book = null,
  asking = false,
}: {
  noteTitle?: string | null;
  keyword?: boolean;
  book?: string | null;
  asking?: boolean;
}): Starters {
  const say = (command: string) => (keyword ? `Hey Ghost, ${lowerFirst(command)}` : command);
  const chapter: Tip | null = book ? { say: say(`Add a chapter to ${book}`), does: 'and then its name, to put a page in that book' } : null;
  const send: Tip[] = noteTitle
    ? [{ say: say(`Add … to ${noteTitle}`), does: 'to put it there, into its list if it has one' }, chapter ?? { say: say(`Move this to ${noteTitle}`), does: 'to send this recording there' }]
    : [{ say: say('Make a list called …'), does: 'and then its items, for a new note that is a list' }, chapter ?? { say: say('Make a book called …'), does: 'to start a book' }];
  return {
    shape: CUES.slice(0, EACH),
    send: send.slice(0, EACH),
    ask: asking ? ASKS.slice(0, EACH).map((ask) => ({ say: say(ask.say), does: ask.does })) : [],
  };
}

/** How long a pause has to be before a tip shows. Longer than a breath, shorter than giving up. */
export const TIP_AFTER_MS = 2500;
