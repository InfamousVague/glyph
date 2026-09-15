import { afterEach, describe, expect, it } from 'vitest';
import { renderNote, setSpokenFormats, type Segment } from '../capture/markdown.ts';
import { toSegments } from '../guide/phrases.ts';
import { CHAPTERS, lessonsFor, nextLesson, type Practice } from './lessons.ts';

const MARKS = [
  { name: 'Highlight', delimiter: '==', cue: 'highlight' },
  { name: 'Spoiler', delimiter: '||', cue: 'spoiler' },
  { name: 'Quiet', delimiter: '%%' },
];

/** A pause lesson's phrases a few seconds apart, the rest a breath apart, the way the recorder commits them. */
function segmentsOf(lesson: Pick<Practice, 'say' | 'pause'>): Segment[] {
  if (!lesson.pause) return toSegments(lesson.say);
  return lesson.say.map((text, i) => ({ text, startMs: i * 4000, endMs: i * 4000 + 1000 }));
}

/** What Glyph writes for a lesson's words, the way the tutorial renders what it hears. */
function said(lesson: Pick<Practice, 'say' | 'pause'>) {
  return { markdown: renderNote(segmentsOf(lesson), '', { titled: false }).markdown, heard: lesson.say.join(' ') };
}

const practices = (formats = MARKS) => lessonsFor(formats).filter((lesson): lesson is Practice => lesson.kind === 'practice');

describe('the voice tutorial', () => {
  afterEach(() => setSpokenFormats([]));

  it('passes every lesson on its own example, through the recorder’s real rules', () => {
    setSpokenFormats(MARKS.flatMap((format) => (format.cue ? [{ word: format.cue, delimiter: format.delimiter }] : [])));
    for (const lesson of practices()) {
      const { markdown, heard } = said(lesson);
      expect(lesson.passes(markdown, heard), `${lesson.id}: ${JSON.stringify(markdown)}`).toBe(true);
    }
  });

  it('does not pass a lesson on plain talk that never said its cue', () => {
    const { markdown, heard } = said({ say: ['We should go to the coast this weekend.'] });
    const passed = practices()
      .filter((lesson) => lesson.passes(markdown, heard))
      .map((lesson) => lesson.id);
    expect(passed).toEqual(['talk']);
  });

  it('does not pass the pause lesson on a spoken new paragraph', () => {
    const pause = practices().find((lesson) => lesson.id === 'pause')!;
    const { markdown, heard } = said({ say: ['The kitchen needs work.', 'New paragraph.', 'The garden is fine.'] });
    expect(pause.passes(markdown, heard)).toBe(false);
  });

  it('teaches the plugins’ spoken marks only when one is on', () => {
    expect(lessonsFor([]).some((lesson) => lesson.id === 'marks')).toBe(false);
    expect(lessonsFor([{ name: 'Quiet', delimiter: '%%' }]).some((lesson) => lesson.id === 'marks')).toBe(false);
    expect(lessonsFor(MARKS).find((lesson) => lesson.id === 'marks')?.teach).toContain('“highlight” or “spoiler”');
  });

  it('keeps ids unique and chapters in order', () => {
    const lessons = lessonsFor(MARKS);
    expect(new Set(lessons.map((lesson) => lesson.id)).size).toBe(lessons.length);
    const order = lessons.map((lesson) => CHAPTERS.indexOf(lesson.chapter));
    expect(order).toEqual([...order].sort((a, b) => a - b));
    expect(new Set(order).size).toBe(CHAPTERS.length);
  });

  it('goes on from the first lesson not yet done', () => {
    const lessons = lessonsFor();
    expect(nextLesson(lessons, new Set())?.id).toBe('talk');
    expect(nextLesson(lessons, new Set(['talk', 'title']))?.id).toBe('section');
    expect(nextLesson(lessons, new Set(lessons.map((l) => l.id)))).toBeNull();
  });
});
