import { findKeyword, planCommand, reply } from '../capture/command.ts';

/**
 * The voice tutorial's lessons (tutorial/TutorialScreen.tsx): what to say, and how to tell it worked.
 *
 * Matt: "I'd like to be able to take a tutorial at any time for the commands you can say in the app, and have it walk
 * the user through each of the things and mark off lesson by lesson what we've learned so far; it should only take
 * a few minutes." And then, on what it was missing: "just learning the voice to markdown commands and tips and
 * tricks". So every cue the recorder knows is a lesson (the same list the guide's marks page shows, guide/phrases.ts),
 * every "Glyph" command is one, and the habits that make them work close it as tips.
 *
 * A practice lesson is one cue: a line on what it does, words to say, and a check run on what Glyph writes from what
 * was really said (capture/markdown.ts `renderNote`, the recorder's own rules), not on the words matching the example.
 * Any sentence with a bullet point in it passes the bullet lesson. A tip is read, not said, and ticked with Got it.
 *
 * Grouped in chapters so a long list still reads as a few short parts. Pure, so every practice lesson's example is a
 * test that its own check passes (lessons.test.ts).
 */

interface LessonBase {
  id: string;
  chapter: Chapter;
  title: string;
  /** One or two lines on what it does. */
  teach: string;
}

export interface Practice extends LessonBase {
  kind: 'practice';
  /** Words to try, one phrase per pause. */
  say: string[];
  /** The phrases are said with a long pause between them, the pause being the lesson. */
  pause?: boolean;
  /** What Glyph would be asking, for a lesson that answers it. */
  asks?: string;
  /** What was heard shows this worked: the markdown Glyph wrote, and the plain words. */
  passes: (markdown: string, heard: string) => boolean;
  /** Said when it passes. */
  praise: string;
}

export interface Tip extends LessonBase {
  kind: 'tip';
}

export type Lesson = Practice | Tip;

export const CHAPTERS = ['The basics', 'Lists', 'Making it stand out', 'Talking to Glyph', 'Tips and tricks'] as const;
export type Chapter = (typeof CHAPTERS)[number];

/** A plugin's formatting that can be said: "highlight … end highlight" wraps the words in `==` (plugins/types.ts). */
export interface SaidFormat {
  name: string;
  delimiter: string;
  cue?: string;
}

/** A pretend note for the command lessons, so a command can be understood without touching a real note. */
export const PRACTICE_NOTE = { id: 'tutorial-practice', title: 'Practice list' };

/** What a "Glyph, …" command in `heard` would do, against the practice note. */
function commandIn(heard: string) {
  const found = findKeyword(heard);
  return found ? planCommand(found.after, { notes: [PRACTICE_NOTE] }) : null;
}

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const BASICS: Lesson[] = [
  {
    kind: 'practice',
    id: 'talk',
    chapter: 'The basics',
    title: 'Just talk',
    teach: 'Glyph writes down what you say. Speak the way you would to a person.',
    say: ['The dry cleaning is ready after six.'],
    passes: (_markdown, heard) => heard.trim().split(/\s+/).length >= 3,
    praise: 'That’s a note.',
  },
  {
    kind: 'practice',
    id: 'title',
    chapter: 'The basics',
    title: 'Name the note',
    teach: 'Say “Title” or “Call this note”, then the name. Said first, it becomes the note’s heading.',
    say: ['Title: weekend trip.'],
    // Said into a note that already has words, the title cue writes a heading; either way it's the cue said, and a heading made.
    passes: (markdown, heard) => /^#+ \S/m.test(markdown) && /\b(title|call this note)\b/i.test(heard),
    praise: 'Titled.',
  },
  {
    kind: 'practice',
    id: 'section',
    chapter: 'The basics',
    title: 'Sections',
    teach: 'Say “Heading” or “New section” at the start of a sentence to begin a new part of the note.',
    say: ['Heading: the budget.'],
    passes: (markdown, heard) => /^##+ \S/m.test(markdown) && /\b(heading|new section|section)\b/i.test(heard),
    praise: 'A new section.',
  },
  {
    kind: 'practice',
    id: 'paragraph',
    chapter: 'The basics',
    title: 'New paragraph',
    teach: 'Say “New paragraph” between two thoughts.',
    say: ['The kitchen needs work.', 'New paragraph.', 'The garden is fine.'],
    passes: (markdown) => /\S\n\n(?!#|- |>)\S/.test(markdown),
    praise: 'Two paragraphs.',
  },
  {
    kind: 'practice',
    id: 'pause',
    chapter: 'The basics',
    title: 'Or just stop talking',
    teach: 'You don’t have to say it. Stop for two seconds and the next thing you say starts a new paragraph.',
    say: ['The kitchen needs work.', 'The garden is fine.'],
    pause: true,
    passes: (markdown, heard) => /\S\n\n(?!#|- |>)\S/.test(markdown) && !/new paragraph/i.test(heard),
    praise: 'The pause did it.',
  },
];

const LISTS: Lesson[] = [
  {
    kind: 'practice',
    id: 'bullets',
    chapter: 'Lists',
    title: 'Bullet points',
    teach: 'Say “Bullet point” before the first thing and “Next point” before each one after, with a pause between.',
    say: ['Bullet point: oat milk.', 'Next point: eggs.'],
    passes: (markdown) => /^- (?!\[)\S/m.test(markdown),
    praise: 'A list.',
  },
  {
    kind: 'practice',
    id: 'breath',
    chapter: 'Lists',
    title: 'A list in one breath',
    teach: 'Name three or more short things after a word like need, buy or bring. No cue at all.',
    say: ['For the drive we need snacks, water, a charger and the good playlist.'],
    passes: (markdown, heard) => /:\n- \S/.test(markdown) && !/\b(bullet|next) point\b/i.test(heard),
    praise: 'A list, from plain talk.',
  },
  {
    kind: 'practice',
    id: 'numbers',
    chapter: 'Lists',
    title: 'Numbers, out loud',
    teach: 'When the order matters, say “Number one”, “Number two” and so on.',
    say: ['Number one: passports.', 'Number two: chargers.'],
    passes: (markdown, heard) => /^\d+\. \S/m.test(markdown) && /\bnumber\s+(one|two|three|four|five|\d)\b/i.test(heard),
    praise: 'Numbered.',
  },
  {
    kind: 'practice',
    id: 'steps',
    chapter: 'Lists',
    title: 'Steps in order',
    teach: 'Start with “First”, then say “Second”, “Then” or “Finally”. The steps are numbered for you.',
    say: ['How to reset the router.', 'First, unplug it.', 'Second, wait thirty seconds.', 'Finally, plug it back in.'],
    passes: (markdown, heard) => /^\d+\. \S/m.test(markdown) && /\bfirst\b/i.test(heard) && !/\bnumber\s+(one|two|\d)\b/i.test(heard),
    praise: 'Step by step.',
  },
  {
    kind: 'practice',
    id: 'todo',
    chapter: 'Lists',
    title: 'To-dos',
    teach: 'Say it like you’d say it to yourself: “Remember to”, “I need to”, or “Check box”. You get something to tick off.',
    say: ['Remember to call the plumber.'],
    passes: (markdown) => /^- \[ \] \S/m.test(markdown),
    praise: 'Something to tick off.',
  },
  {
    kind: 'practice',
    id: 'alone',
    chapter: 'Lists',
    title: 'A cue on its own',
    teach: 'Say the cue, pause, then the thing. The cue waits for whatever you say next.',
    say: ['Bullet point.', 'Oat milk.'],
    passes: (markdown, heard) =>
      /^(- |#+ |> |\d+\. )\S/m.test(markdown) &&
      /\b(bullet point|next point|check ?box|to-?do|heading|new section|quote|number (one|two|three))[.!,]?\s+\S/i.test(heard),
    praise: 'It waited for you.',
  },
];

function emphasis(formats: readonly SaidFormat[]): Lesson[] {
  const said = formats.filter((format): format is SaidFormat & { cue: string } => Boolean(format.cue));
  const lessons: Lesson[] = [
    {
      kind: 'practice',
      id: 'important',
      chapter: 'Making it stand out',
      title: 'Important',
      teach: 'Start a sentence with “Important” or “Key point” and a pause. The word is written in bold.',
      say: ['Important: they need an answer by Monday.'],
      passes: (markdown) => /\*\*(important|key point):?\*\*/i.test(markdown),
      praise: 'Nobody will miss it.',
    },
    {
      kind: 'practice',
      id: 'bold',
      chapter: 'Making it stand out',
      title: 'Bold and italic, anywhere',
      teach: 'Wrap words in “bold” and “end bold”, even mid-sentence. “Italic” and “end italic” work the same way.',
      say: ['The deadline is bold Friday at noon end bold.'],
      passes: (markdown) => /\*\*[^*\s][^*]*\*\*|(^|[^\w])_[^_\s][^_]*_/.test(markdown),
      praise: 'It stands out.',
    },
    {
      kind: 'practice',
      id: 'quote',
      chapter: 'Making it stand out',
      title: 'Quote someone',
      teach: 'Say “Quote” and their words. It keeps what they said apart from what you said.',
      say: ['Quote: the deposit comes back in full.'],
      passes: (markdown) => /^> \S/m.test(markdown),
      praise: 'In their words.',
    },
    {
      kind: 'practice',
      id: 'divider',
      chapter: 'Making it stand out',
      title: 'A dividing line',
      teach: 'Say “Divider” or “Horizontal line” on its own, between two parts of a note.',
      say: ['That covers the morning.', 'Divider.', 'The afternoon is free.'],
      passes: (markdown) => /^---$/m.test(markdown),
      praise: 'A clean break.',
    },
  ];
  if (said.length) {
    const first = said[0]!;
    const names = said.map((format) => `“${format.cue}”`);
    const listed = names.length > 1 ? `${names.slice(0, -1).join(', ')} or ${names[names.length - 1]}` : names[0];
    lessons.push({
      kind: 'practice',
      id: 'marks',
      chapter: 'Making it stand out',
      title: said.length > 1 ? 'Glyph’s own marks' : `${first.name}`,
      teach: `Your plugins add marks you can say the same way as bold: ${listed}, then “end” and the same word.`,
      say: [`The gate code is ${first.cue} four four one two end ${first.cue}.`],
      passes: (markdown) => said.some((format) => new RegExp(`${escape(format.delimiter)}[^\\n]+?${escape(format.delimiter)}`).test(markdown)),
      praise: 'Marked.',
    });
  }
  return lessons;
}

const COMMANDS: Lesson[] = [
  {
    kind: 'practice',
    id: 'command',
    chapter: 'Talking to Glyph',
    title: 'Send it to a note',
    teach: 'Start with “Glyph”, then say what to add and which note. Words before “Glyph” stay where you are.',
    say: ['Glyph, add eggs to my practice list.'],
    passes: (_markdown, heard) => {
      const plan = commandIn(heard);
      return plan?.kind === 'place' || plan?.kind === 'await';
    },
    praise: 'Glyph would add it to Practice list, after asking you.',
  },
  {
    kind: 'practice',
    id: 'answer',
    chapter: 'Talking to Glyph',
    title: 'Yes or no',
    teach: 'Glyph always asks before a command changes anything. Say “yes” to go ahead, or “no” or “scratch that” to drop it. A tap works too.',
    asks: 'Add “eggs” to Practice list?',
    say: ['Yes.'],
    passes: (_markdown, heard) => reply(heard) !== null,
    praise: 'Answered.',
  },
  {
    kind: 'practice',
    id: 'jump',
    chapter: 'Talking to Glyph',
    title: 'Switch notes mid-recording',
    teach: 'Say “Glyph, switch to” a note and you carry on talking there. “Glyph, new note” starts a fresh one.',
    say: ['Glyph, switch to my practice list.'],
    passes: (_markdown, heard) => {
      const plan = commandIn(heard);
      return plan?.kind === 'move' || plan?.kind === 'new';
    },
    praise: 'Glyph would carry on there, after asking you.',
  },
  {
    kind: 'practice',
    id: 'table',
    chapter: 'Talking to Glyph',
    title: 'Build a table',
    teach: 'Say “Glyph, add a table”. It asks for the column labels, then each row, and shows the table before adding it.',
    say: ['Glyph, add a table to my practice list.'],
    passes: (_markdown, heard) => commandIn(heard)?.kind === 'table',
    praise: 'Glyph would start asking for the columns.',
  },
];

const TIPS: Lesson[] = [
  {
    kind: 'tip',
    id: 'tip-breath',
    chapter: 'Tips and tricks',
    title: 'Breathe before a cue',
    teach:
      'Glyph listens for cues at the start of a sentence. Take a short pause before “heading” or “bullet point”. Said mid-sentence, they stay ordinary words.',
  },
  {
    kind: 'tip',
    id: 'tip-words',
    chapter: 'Tips and tricks',
    title: 'Your words stay yours',
    teach: 'Glyph never changes what you said, only how it’s laid out. Talk normally, and lists and to-dos come out of it.',
  },
  {
    kind: 'tip',
    id: 'tip-sidekey',
    chapter: 'Tips and tricks',
    title: 'Record from anywhere',
    teach:
      'Hold the side key to start recording, whatever is on screen. Press it again, or tap Done, to save. With “Stop when I go quiet” on, four quiet seconds save it too.',
  },
  {
    kind: 'tip',
    id: 'tip-wake',
    chapter: 'Tips and tricks',
    title: 'Say “Glyph” with the app open',
    teach:
      'With the list or a note on screen, say “Glyph” and the recorder opens with what you said. It’s on unless you turn it off in Settings, under Recording.',
  },
  {
    kind: 'tip',
    id: 'tip-memo',
    chapter: 'Tips and tricks',
    title: 'Talk now, sort later',
    teach:
      'Turn on Memo mode in Settings, under Recording, and everything goes on one scratch page. When you’re done, Glyph shows where each part should go before anything is filed.',
  },
  {
    kind: 'tip',
    id: 'tip-fix',
    chapter: 'Tips and tricks',
    title: 'Fix it after',
    teach: 'A recording lands at the top of your notes. Open it to change anything: the marks are all there, dimmed, to edit like any other text.',
  },
];

/** Every lesson, in order, with a lesson for the plugins' spoken marks when any are switched on. */
export function lessonsFor(formats: readonly SaidFormat[] = []): Lesson[] {
  return [...BASICS, ...LISTS, ...emphasis(formats), ...COMMANDS, ...TIPS];
}

/** The first lesson not yet done, or null when all are. */
export function nextLesson(lessons: readonly Lesson[], done: ReadonlySet<string>): Lesson | null {
  return lessons.find((lesson) => !done.has(lesson.id)) ?? null;
}

const KEY = 'glyph-tutorial';

export function readProgress(): Set<string> {
  try {
    const raw = localStorage.getItem(KEY);
    const ids = raw ? (JSON.parse(raw) as unknown) : [];
    return new Set(Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string') : []);
  } catch {
    return new Set();
  }
}

export function writeProgress(done: ReadonlySet<string>): void {
  try {
    localStorage.setItem(KEY, JSON.stringify([...done]));
  } catch {
    // Progress still counts for this run.
  }
}
