import { plugins } from '../plugins/registry.ts';
import { CHAPTERS, lessonsFor, type Chapter, type Lesson } from '../tutorial/lessons.ts';

/**
 * The cheat sheet's spoken half: every rule Glyph knows for turning talk into markdown, in one list to look things up
 * in (Matt: "i want the glossary / lexicon / cheat sheet added for all formatting rules in the help section").
 *
 * The typed half is the table of marks that was already there (guide/marks.ts). This half is the tutorial's own
 * lessons (tutorial/lessons.ts) read as reference rather than as practice: each one already says what the rule is and
 * gives words that work, and the tutorial's spoken formats come from the switched-on plugins, so a mark that is not
 * there is not promised here either. One list, one source: a rule cannot drift between the two.
 */

export interface SaidRule {
  /** What it does: "Name the note". */
  title: string;
  /** The rule itself, in a line. */
  teach: string;
  /** Words that work, where the rule has an example to give. */
  say: string[];
  /** A rule practised by saying something, as against a piece of advice. */
  spoken: boolean;
}

export interface SaidGroup {
  chapter: Chapter;
  rules: SaidRule[];
}

function ruleOf(lesson: Lesson): SaidRule {
  return { title: lesson.title, teach: lesson.teach, say: lesson.kind === 'practice' ? lesson.say : [], spoken: lesson.kind === 'practice' };
}

/** Every spoken rule, in the tutorial's order, grouped by the chapter it belongs to. Empty chapters are left out. */
export function saidGroups(): SaidGroup[] {
  const lessons = lessonsFor(plugins.formats().map((format) => ({ name: format.name, delimiter: format.delimiter, cue: format.cue })));
  return CHAPTERS.map((chapter) => ({ chapter, rules: lessons.filter((lesson) => lesson.chapter === chapter).map(ruleOf) })).filter(
    (group) => group.rules.length > 0,
  );
}
