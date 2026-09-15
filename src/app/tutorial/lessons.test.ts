import { describe, expect, it } from 'vitest';
import { renderNote } from '../capture/markdown.ts';
import { toSegments } from '../guide/phrases.ts';
import { LESSONS, nextLesson } from './lessons.ts';

/** What Glyph writes for a lesson's words, the way the tutorial renders what it hears. */
function said(say: readonly string[]) {
  const segments = toSegments(say);
  return { markdown: renderNote(segments, '', { titled: false }).markdown, heard: say.join(' ') };
}

describe('the voice tutorial', () => {
  it('passes every lesson on its own example, through the recorder’s real rules', () => {
    for (const lesson of LESSONS) {
      const { markdown, heard } = said(lesson.say);
      expect(lesson.passes(markdown, heard), `${lesson.id}: ${JSON.stringify(markdown)}`).toBe(true);
    }
  });

  it('does not pass a lesson on plain talk that never said its cue', () => {
    const { markdown, heard } = said(['We should go to the coast this weekend.']);
    const passed = LESSONS.filter((lesson) => lesson.passes(markdown, heard)).map((lesson) => lesson.id);
    expect(passed).toEqual(['talk']);
  });

  it('goes on from the first lesson not yet done', () => {
    expect(nextLesson(new Set())?.id).toBe('talk');
    expect(nextLesson(new Set(['talk', 'title']))?.id).toBe('bullets');
    expect(nextLesson(new Set(LESSONS.map((l) => l.id)))).toBeNull();
  });
});
