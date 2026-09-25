import { kindWords, type RunKind } from '../../ai/kinds.ts';
import { BOARD_TITLE } from '../../core/boardNote.ts';
import { SAMPLE_TITLE } from '../../core/sampleNote.ts';
import { lowerFirst } from '../../core/text.ts';
import { HOW_TITLE } from '../../canvas/howCanvas.ts';
import { CANVAS_TITLE } from '../../canvas/sampleCanvas.ts';
import { MODES } from '../../format/modes.ts';

/**
 * The words of Ghost.md: The Guide's own chapters (guide/theGuide/book.ts): a note each, in the app's voice, about
 * one part of the app. The book's other chapters are notes the app already makes - the sample note, the example board
 * and the two example canvases - so what those teach is said once, there.
 *
 * Every line here is meant to be true of the app as it is, and the parts that could drift are held to it:
 *
 * - The spoken examples are data (`COMMANDS`, `ASKS`, `FREE_ASK`, `CUES`), and theGuide.test.ts runs each through
 *   the recorder's own readers. Only two commands act from a recording today, words added to a note by its name and
 *   a new list by name (capture/finalInstruction.ts `permitted`), so those are the only two taught. Voice memos are
 *   not taught either: the recorder reads a finished recording whole, and the "voice memo … end memo" cue is only
 *   read phrase by phrase (capture/take.ts `phrase`), which the recorder no longer calls, so the words are kept.
 * - The AI's rows and runs are described in their own words (ai/kinds.ts), so a hint changed there changes here.
 * - A `[[link]]` names another chapter, and the test holds every one to a chapter the book has, so the guide never
 *   draws a dashed link that makes an empty note when tapped.
 *
 * A chapter's first line is its heading, which is its title: the book finds a chapter by its title.
 */

export interface GuideChapter {
  title: string;
  body: string;
}

/** The commands a recording can give, said first, after "Hey Ghost" (capture/finalInstruction.ts). */
export const COMMANDS = [
  { say: 'Hey Ghost, add bread to Groceries', does: 'puts “bread” in your Groceries note, in its list if it has one.', note: 'Groceries', kind: 'place' },
  {
    say: 'Hey Ghost, make a list called Comic books with Spider-Man, Batman and Superman',
    does: 'makes a new note that is that list. Leave off the “with …” for an empty one.',
    note: 'Comic books',
    kind: 'create-list',
  },
] as const;

/** The AI's runs said in words, into a note's own microphone (ai/instruction.ts `runOf`), in the order taught. */
export const ASKS: readonly { say: string; run: RunKind }[] = [
  { say: 'Hey Ghost, fix the spelling', run: 'fix' },
  { say: 'Hey Ghost, make this a list', run: 'shape' },
  { say: 'Hey Ghost, tidy this up', run: 'format' },
  { say: 'Hey Ghost, summarise this', run: 'summarize' },
  { say: 'Hey Ghost, carry on', run: 'continue' },
];

/**
 * A free ask: anything else after "Hey Ghost", said into a note, is an instruction for the AI. Not one that starts
 * like a command ("add…", "make…"), which the command reader and its model would read first and could refuse as a
 * note it cannot find (capture/command.ts `finalCommandWords`).
 */
export const FREE_ASK = 'Hey Ghost, give each day a heading';

/** The cues the recording chapter names, each one the recorder's own (capture/tips.ts). */
export const CUES = ['Title', 'Heading', 'Bullet point', 'Check box', 'Bold … end bold', 'New paragraph'] as const;

const quoted = (words: string) => `“${words}”`;

export const NOTES_TITLE = 'How your notes are kept';
export const RECORD_TITLE = 'How to record a note';
export const COMMAND_TITLE = 'How to give a command';
export const AI_TITLE = 'How to ask the AI';
export const BOARDS_TITLE = 'How boards work';
export const BOOKS_TITLE = 'How books work';
export const CANVASES_TITLE = 'How canvases work';
export const SHARING_TITLE = 'How sharing and sync work';
export const PLUGINS_TITLE = 'How plugins work';

const notes = `# ${NOTES_TITLE}

Every note is a plain Markdown file, named after its first line. Nothing is locked inside the app: the words are the file, and any app that reads Markdown reads them.

## Home

Ghost.md opens on the home page. Anything waiting on you comes first, then:

- **Pinned**: the notes you pinned.
- **Library**: your books, a card each.
- **Recent**: the notes you were in last.
- **To do**: every to-do not yet ticked, from all of your notes. Tick one there without opening its note.

**All notes**, at the foot of the page, shows every note as a grid of cards, newest first or A to Z, with a search through their words.

## Starting a note

At the bottom right of the home page are the **+**, the **microphone**, Settings and Search. The + makes a Note, a Canvas or a Book, or keeps a copy of a note someone shared with you. The microphone records one: see [[${RECORD_TITLE}]].

A new note has no file until it has words, so a note opened and left empty leaves nothing behind.

## Finding one

Search, at the bottom right of the home page, opens the palette: your notes by name, and everything Ghost.md can do. On a computer, ⌘K opens it too.

The sidebar lists your notes by workspace, with the Trash at its foot. Its toggle lists them by name alone, a line each, and its folder button shows them where the device keeps files: the Files app on a phone, Finder on a Mac.

## Keeping them in order

The three dots at the top of a note open its More sheet:

- **Pin to the top** keeps it first on the home page.
- **Archive** puts it away without deleting it.
- **Workspace** files it in one. The workspace pills on the home page choose which one you are looking at.
- **Move to Trash**, at the foot. A note in the Trash can be put back, or deleted for good.
`;

const record = `# ${RECORD_TITLE}

Say it, and Ghost.md writes it down as Markdown. In the app, the words are heard on the device itself, and nothing you say is sent anywhere to be turned into text. In a browser, the browser's own speech recognition does it.

## Starting

- The **microphone** at the bottom right of the home page starts a new note.
- The **microphone** at the top of a note talks into that note. A note that already has a recording has **Add** on its cassette instead.
- On Android, the **side key** starts one from anywhere, the lock screen too, once Ghost.md is your digital assistant. Settings, About, How to talk to Ghost.md shows the way on your phone.

Before the first word, a card lists things to say. In a pause, a line suggests one more.

## Talking

Talk the way you would to a person. Ghost.md listens for a cue at the start of a sentence, and lays out what follows it:

${CUES.map((cue) => `- ${quoted(cue)}`).join('\n')}

A pause of a couple of seconds starts a new paragraph by itself, and a cue said on its own waits for the next thing you say. Every mark has its words: the Formatting cheat sheet gives each one, and [[${SAMPLE_TITLE}]] shows them at work.

## Stopping

Tap **Done**, or hold the side key again. **Discard** throws the recording away. To stop by itself once you go quiet, turn on Stop when I go quiet in Settings, under Recording.

A note you said keeps its recording on a cassette at the top of the note: play it back, **Add** more to it, or remove the sound and keep the words.

With Review after recording on, as it is to begin with, a slower model listens again when you stop, and the note opens with what it would change marked, for you to keep or put back. Better words, beside it, has a larger model go over the recording afterwards and fix the words it misheard.

A recording can also be a command: see [[${COMMAND_TITLE}]].
`;

const command = `# ${COMMAND_TITLE}

A recording can be a command rather than the note's words. Start it with “Hey Ghost”, and what follows is read as one; “Glyph” still works too. A recording that starts with a command's own words, such as “Add … to …” or “Make a list called …”, is read as one even without “Hey Ghost”.

## The commands

${COMMANDS.map((c) => `- **${quoted(c.say)}** ${c.does}`).join('\n')}

Say the note's name the way you would say it: capitals and punctuation don't matter. A command is the whole recording, so say it and then stop.

Nothing is written until you have seen it. A card names the note and shows exactly what will change, and waits for you to tap **Add**, or **Create** for a new list. **Cancel** leaves everything as it was. When the name matches no note, or more than one, no card comes up, and nothing is added to any note.

## Asking the AI

Said into a note's own microphone, “Hey Ghost” and what you want is an ask about that note: ${quoted(ASKS[0]!.say)}, or ${quoted(FREE_ASK)}. The note opens with the AI at work on it. [[${AI_TITLE}]] has the rest.
`;

const ai = `# ${AI_TITLE}

The AI rewrites a note for you on the device itself. Nothing you write is sent anywhere for it.

## From the note

The three dots at the top of a note open its More sheet, and the AI rows there:

${MODES.map((mode) => `- **${mode.label}**: ${lowerFirst(mode.hint)}`).join('\n')}

## By voice

Tap the microphone at the top of the note, or **Add** on its cassette, and start with “Hey Ghost”:

${ASKS.map((ask) => `- ${quoted(ask.say)}: ${lowerFirst(kindWords(ask.run).hint)}`).join('\n')}
- “Hey Ghost” and anything else, such as ${quoted(FREE_ASK)}: ${lowerFirst(kindWords('ask').hint)}

The recording of the ask is let go, and the note opens with the AI at work on it.

## Watching it work

A line under the note's header says what the AI is doing, with **Stop**. Its lines land in the note as they are written: the words it added tinted, the words that went struck through where they were. **Keep** or **Revert** each change, or **Keep all**. **Undo**, on that line, puts the whole note back. A tap on the line shows how the run went, and the note's log of runs.

A summary lands above the note, carrying on lands under it, and the rest rewrite the words where they are. You can type while it runs: what you type is yours, and the AI writes around it.

A note the AI changed is signed by it too: “Ghost” is among the note's authors.

## The model

The AI runs in the app on an Android phone or a Mac, with a model on the device. It is not in a browser, and not on an iPhone yet. Choose a model in Settings, under Formatting: bigger is more careful, and slower. **Get** downloads one there. **Local only**, on the same page, stops every download and every plugin that uses the network.
`;

const boards = `# ${BOARDS_TITLE}

A board is a note's list laid out as columns, in plain Markdown. Nothing is kept beside the note, and any other app reads the board as a block of text and a list.

## Try it

\`\`\`board
To try: drag-card, tick-card
Done: open-board
\`\`\`

- [ ] Hold a card, then drag it into Done ^drag-card
- [ ] Tick a card, and watch it go to Done ^tick-card
- [x] Open a board ^open-board

## The two pieces

An item has a name: a caret and a word or two at the end of its line, like \`^drag-card\` above. The name is drawn small and faint.

A block of code marked board lays the named items out, a line for each column: its name, a colon, and the names of the items in it.

## The rules

- **A card is its item.** Tick the card and the item is ticked; tap its words and you are on the item's line.
- **A column called Done means done.** Ticking a card moves it there, and dragging a card into Done ticks it.
- **An item with no box is a card with no box**: a question to ask, or something to keep an eye on.
- **Not every item has to be on the board.** An item no column names is an ordinary line.
- A note can hold more than one board, and an item can sit on two.

## Making one

- **From a note that is a list**: the three dots at the top of the note, then **Make a board**. Every item gets a name, and To do, Doing and Done go in under the title.
- **From one list in a note**: press and hold an item and choose **Board from list**.
- **One more card**: the **+** on a column writes a new to-do into the note and puts its card at the top of that column. Press and hold an item and choose **Add to board** to put that one item on.

## Changing it

- Press and hold a card, then drag it: into another column, or up and down its own. The chevrons on a card move it a step at a time.
- Tap the block itself to edit the columns as words: rename one, add one, or put them in another order.
- Drag the line under a board to set how tall it is.

The example board, [[${BOARD_TITLE}]], is the next chapter.
`;

const books = `# ${BOOKS_TITLE}

A book is notes in an order, with an index. You are reading one: this guide is a book, and each chapter is a note of its own.

## The index

A book is a note whose front matter says \`book: true\`, and its index is a list of links to its chapters, each name in double square brackets, in order. A chapter indented under another is part of it, and numbered under it. Words that are not chapters stay above or below the index as the book's own.

A chapter is any note, found by its name. A name with no note yet is a chapter still to be written: open it, and the note is made.

## Making one

The **+** offers a Book beside a Note and a Canvas. Name it and pick its pages from your notes, in the order you want them. **Make the book**, and it opens at its index. Books are on the home page, under Library.

## In the index

- Tap a chapter to open it. A chapter not written yet is drawn waiting.
- Move a chapter up or down a place, or take it out of the book. The note it names is never touched.
- **Add a chapter** names a new one and opens it. **Add a note you have** puts notes you already have in.
- **Read straight through** shows every chapter one after another, with a rail down the side to jump between them.

## In a chapter

A chapter wears its book: under the header, the book's name, its place, and the chapters either side. At its foot, **Previous** and **Next** go on through the book. A tap on the book's name goes back to the index.

A book opens where you left it: at its index, in a chapter, or part way through reading it straight through.

A canvas can be a chapter too. [[${HOW_TITLE}]], the first chapter of this book, is one.

## Sharing it

A book shares as one link, holding its index and every chapter that has a note: see [[${SHARING_TITLE}]].
`;

const canvases = `# ${CANVASES_TITLE}

A canvas is cards on a page as big as you need, with lines between them. It is written in JSON Canvas, the format Obsidian uses, so a canvas made here opens there, and one made there opens here.

## Making one

The **+** offers a Canvas. It opens empty: double-tap the page for a card of words there, or use the tools at the bottom left.

## Cards

Add a card, among the tools, offers:

- **Words**: Markdown, drawn the way a note draws it. Double-tap the card to write in it.
- **A note**: one of your notes, drawn small. A tap opens it.
- **A link**: a web address, opened with a tap.
- **A picture**, from your phone or computer.
- **A chart**: a diagram, written as Mermaid and drawn on the card.
- **A table**: rows and columns to fill in.

Press and hold a card to lift it, and put it down where you want it. A card open for writing has a corner to resize it by, and a cross to take it off. A group, drawn as a named box, carries the cards wholly inside it when it moves.

## Lines

The line tool joins the next two cards you tap, with an arrow at the end. Tap a line to write words on it, or to take it off.

## Finding your way

Drag with a finger to move about, and pinch to zoom. **Fit** shows the whole canvas, and a tap on a card's title zooms to it. The map in the corner shows where you are: drag on it to move.

## In a note

A canvas can sit in any note, in a frame you can look around in: its name in \`![[ ]]\`, on a line of its own. **Open**, over the frame, opens the canvas itself.

The switch at the top of a canvas shows its JSON, to read or change by hand. A canvas's name is in its More sheet, since it has no first line to be named by.

The example canvas, [[${CANVAS_TITLE}]], is the next chapter.
`;

const sharing = `# ${SHARING_TITLE}

Your notes stay on your device. An account keeps them the same on every device you sign in on, and lets you share a note by its link.

## An account

In Settings, under Account, **Create an account** with a handle and a password. Keep the recovery codes it gives you somewhere safe: with the password lost, a recovery code is the only way back in.

Signed in, your notes, pictures, settings and recordings sync, encrypted on the device first, so only your own devices can read them. The server keeps copies it cannot read. **Sync now** syncs at once.

**Live typing**, under Account, shows what is typed on one device on another as it is typed, while a note is open on both. It is a trial.

## Sharing a note

The three dots at the top of a note, then **Share a read-only link**. Anyone with the link can read the note, and nobody else can, the server included. Your edits reach readers a few seconds after you save. **Stop sharing** makes the link read nothing from then on.

A book shares the same way, as its index and every chapter that has a note. Every link you have shared is in Settings, under Account, Shared links.

## Reading one

A shared link opens a page to read it on. From there, the reader can download it as Markdown, or save a copy into their own Ghost.md; the **+** and From a shared link does the same. The copy is theirs to change, and the shared one stays as it is.
`;

const pluginsChapter = `# ${PLUGINS_TITLE}

A plugin adds something to Ghost.md, and each has a switch in Settings, under Plugins. Switched off, it offers nothing anywhere, and what it kept waits until it is switched on again.

## The ones that come with Ghost.md

- **Marks**: Ghost.md's own marks on top of Markdown: a spoiler in smoke, a highlight, an aside, a doubt, a shout, an addition, and five effects, heat, frost, a wave, a shimmer and a haunting. The Formatting cheat sheet has every one, and [[${SAMPLE_TITLE}]] shows them.
- **Notion**: a note's list items become tasks on your Notion boards. Swipe an item to send it, or send the whole list from the note's More sheet, under Linked to.
- **GitHub**: links a note to a repository. Its list items become issues you can tick off from either side, and the repository is read on the phone into a short briefing, so its names come out right when the note is formatted.
- **Claude**: read, add to and change your notes from Claude, through Ghost.md's MCP server. Its page in Settings says how to connect it.

**Local only**, in Settings under Formatting, switches off every plugin that uses the network.
`;

/** The guide's own chapters, by title, each a note's whole body. */
export const OWN_CHAPTERS: readonly GuideChapter[] = [
  { title: NOTES_TITLE, body: notes },
  { title: RECORD_TITLE, body: record },
  { title: COMMAND_TITLE, body: command },
  { title: AI_TITLE, body: ai },
  { title: BOARDS_TITLE, body: boards },
  { title: BOOKS_TITLE, body: books },
  { title: CANVASES_TITLE, body: canvases },
  { title: SHARING_TITLE, body: sharing },
  { title: PLUGINS_TITLE, body: pluginsChapter },
];
