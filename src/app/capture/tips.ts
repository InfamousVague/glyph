import { titleKind } from './noteFind.ts';

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
 * understands and the commands the live reader carries out as they are said
 * (capture/liveRoute.ts), so a tip is always something that works: words for a
 * note you name, moving the recording, a new note. The routing tip names one of
 * your own notes, which teaches the command better than a made-up title. Tables,
 * books and voice memos are not taught: a recording does not make them
 * (docs/DESIGN.md §127). Nor, yet, is "Hey Ghost, add … to Doing" said on a
 * board's own Speak, which the live reader does carry out into that lane, and
 * which is the one command that keeps its keyword.
 *
 * A command needs no keyword (docs/DESIGN.md §136), so every tip says it bare,
 * in a form the bare gate takes (liveCommand.ts `bareCommand`): "Add … to
 * Groceries" when the title says the note is a list, else "Add a note to Work,
 * …", since "a note" said is its own evidence. Each is held to the reader by a
 * test.
 *
 * The asks the AI takes (`ASKS`) are on the card alone, and only when the
 * recording is a note's own Speak: an ask is the named runs, which the reader
 * at Done reads without the keyword when they are the whole phrase
 * (ai/instruction.ts `runOf` with `whole`), said first into a note that exists,
 * not a cue for a pause.
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
  { say: 'Scratch that', does: 'to take back the last thing you said' },
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
  { say: 'Make this a list', does: 'to shape the note into tasks, a list or a table' },
  { say: 'Tidy this up', does: 'to format the note, keeping every word that matters' },
  { say: 'Carry on', does: 'and the AI writes on from the last line in the note’s own voice' },
];

/**
 * The tip that sends words to a note, said in a form that works without the keyword: "Add … to Groceries" routes bare
 * because the title says it is a list; for a note whose title does not, "a note" said is the evidence.
 */
function addTo(title: string): string {
  return titleKind(title) ? `Add … to ${title}` : `Add a note to ${title}, …`;
}

/**
 * The tips, in the order they come round. `noteTitle` is a recent note's
 * title for the routing tip; `continuing` says a note is already being added
 * to, which is when "new note" is worth knowing.
 */
export function tips({ noteTitle, continuing }: { noteTitle?: string | null; continuing: boolean }): Tip[] {
  const route: Tip[] = [];
  if (noteTitle) route.push({ say: addTo(noteTitle), does: 'to put it there, into its list if it has one' });
  if (noteTitle) route.push({ say: `New item for ${noteTitle}`, does: 'and then the item, to add to its list' });
  if (continuing) route.push({ say: 'New note', does: 'to start a fresh one' });
  if (noteTitle) route.push({ say: `Move this to ${noteTitle}`, does: 'to send this recording there' });
  // Routing first and then every few cues, since it is the least discoverable; a routing line the cues leave no slot
  // for comes round after them rather than never.
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
 * round, then the switched-on plugins' own, as the plugin wrote them. The routing tip names the most recent note that
 * is not the one being written to.
 */
export function tipInPause({
  notes,
  own,
  target,
  pluginTips,
  turn,
}: {
  /** The notes a command can name, most recent first. */
  notes: readonly { id: string; title: string; note: { body: string } }[];
  /** The id of the note being written to, which no tip sends words to. */
  own: string;
  /** The note being continued, or null for a new one. */
  target: { body: string } | null;
  /** The switched-on plugins' tips, for the routing tip's note (plugins/registry.ts `tips`). */
  pluginTips: (recent: string | null) => readonly Tip[];
  /** How many tips have been shown this recording. */
  turn: number;
}): Tip | null {
  const recent = notes.find((c) => c.id !== own)?.title ?? null;
  const list = [...tips({ noteTitle: recent, continuing: target !== null }), ...pluginTips(recent)];
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
 * one to name: words for it, which go into it as they are said, and moving the recording there. With nothing to name,
 * the one way to make something new, so a first recording still sees that a recording can go somewhere. The asks are
 * there only when `asking`: the recording is a note's own Speak, not over the lock screen, which is the one case an ask
 * said first is run (CaptureScreen.tsx `finish`); a new recording is given none rather than a line that would end as a
 * note of the command's words.
 */
export function starters({ noteTitle, asking = false }: { noteTitle?: string | null; asking?: boolean }): Starters {
  const send: Tip[] = noteTitle
    ? [
        { say: addTo(noteTitle), does: 'to put it there, into its list if it has one' },
        { say: `Move this to ${noteTitle}`, does: 'to send this recording there' },
      ]
    : [{ say: 'Make a list called … with …', does: 'for a new list: its name, and after “with” its items' }];
  return {
    shape: CUES.slice(0, EACH),
    send: send.slice(0, EACH),
    ask: asking ? ASKS.slice(0, EACH) : [],
  };
}

/** How long a pause has to be before a tip shows. Longer than a breath, shorter than giving up. */
export const TIP_AFTER_MS = 2500;
