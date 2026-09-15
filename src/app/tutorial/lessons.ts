import { findKeyword, planCommand } from '../capture/command.ts';

/**
 * The voice tutorial's lessons (tutorial/TutorialScreen.tsx): what to say, and how to tell it worked.
 *
 * Matt: "I'd like to be able to take a tutorial at any time for the commands you can say in the app, and have it walk
 * the user through each of the things and mark off lesson by lesson what we've learned so far; it should only take
 * a few minutes." So a lesson is one cue: a line on what it does, words to say, and a check run on what Glyph writes
 * from what was really said (capture/markdown.ts `renderNote`, the recorder's own rules), not on the words matching
 * the example. Any sentence with a bullet point in it passes the bullet lesson.
 *
 * Pure, so every lesson's example is a test that its own check passes (lessons.test.ts).
 */

export interface Lesson {
  id: string;
  title: string;
  /** One line on what it does. */
  teach: string;
  /** Words to try, one phrase per pause. */
  say: string[];
  /** What was heard shows this worked: the markdown Glyph wrote, and the plain words. */
  passes: (markdown: string, heard: string) => boolean;
  /** Said when it passes. */
  praise: string;
}

/** A pretend note for the command lesson, so the command can be understood without touching a real note. */
export const PRACTICE_NOTE = { id: 'tutorial-practice', title: 'Practice list' };

export const LESSONS: readonly Lesson[] = [
  {
    id: 'talk',
    title: 'Just talk',
    teach: 'Glyph writes down what you say. Speak the way you would to a person.',
    say: ['I need to pick up the dry cleaning before six.'],
    passes: (_markdown, heard) => heard.trim().split(/\s+/).length >= 3,
    praise: 'That’s a note.',
  },
  {
    id: 'title',
    title: 'Name the note',
    teach: 'Say “Title” and the name. It becomes the note’s heading.',
    say: ['Title: weekend trip.'],
    // Said into a note that already has words, the title cue writes a heading; either way it's the cue said, and a heading made.
    passes: (markdown, heard) => /^#+ \S/m.test(markdown) && /\b(title|call this note)\b/i.test(heard),
    praise: 'Titled.',
  },
  {
    id: 'bullets',
    title: 'Bullet points',
    teach: 'Say “Bullet point” before each thing, and pause between them.',
    say: ['Bullet point: oat milk.', 'Next point: eggs.'],
    passes: (markdown) => /^- (?!\[)\S/m.test(markdown),
    praise: 'A list.',
  },
  {
    id: 'todo',
    title: 'To-dos',
    teach: 'Say “To-do” or “Check box” to make something you can tick off.',
    say: ['To-do: call the plumber.'],
    passes: (markdown) => /^- \[ \] \S/m.test(markdown),
    praise: 'Something to tick off.',
  },
  {
    id: 'section',
    title: 'Sections',
    teach: 'Say “Heading” at the start of a sentence to begin a new part of the note.',
    say: ['Heading: the budget.'],
    passes: (markdown, heard) => /^##+ \S/m.test(markdown) && /\b(heading|new section|section)\b/i.test(heard),
    praise: 'A new section.',
  },
  {
    id: 'bold',
    title: 'Bold anywhere',
    teach: 'Wrap words in “bold” and “end bold”. “Italic” works the same way.',
    say: ['The deadline is bold Friday at noon end bold.'],
    passes: (markdown) => /\*\*[^*\s][^*]*\*\*|(^|[^\w])_[^_\s][^_]*_/.test(markdown),
    praise: 'It stands out.',
  },
  {
    id: 'paragraph',
    title: 'New paragraph',
    teach: 'Say “New paragraph”, or just stop talking for two seconds, and carry on.',
    say: ['The kitchen needs work.', 'New paragraph.', 'The garden is fine.'],
    passes: (markdown) => /\S\n\n(?!#|- |>)\S/.test(markdown),
    praise: 'Two paragraphs.',
  },
  {
    id: 'command',
    title: 'Send it to a note',
    teach: 'Start with “Glyph”, then say what to add and which note. Glyph always asks before it does it.',
    say: ['Glyph, add eggs to my practice list.'],
    passes: (_markdown, heard) => {
      const found = findKeyword(heard);
      if (!found) return false;
      const plan = planCommand(found.after, { notes: [PRACTICE_NOTE] });
      return plan?.kind === 'place' || plan?.kind === 'await';
    },
    praise: 'Glyph would add it to Practice list, after asking you.',
  },
];

/** The first lesson not yet done, or null when all are. */
export function nextLesson(done: ReadonlySet<string>): Lesson | null {
  return LESSONS.find((lesson) => !done.has(lesson.id)) ?? null;
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
