import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { LESSONS } from '../app/academy/lessons.ts';
import { referencePage, referenceSections } from './reference.ts';

/*
 * ghostmarkdown.com's formatting reference (landing/reference.html), written from the Academy's lessons. With
 * WRITE_REFERENCE=1 this writes the page; without it, it fails while the page is not what the lessons say.
 */

const PAGE = join(__dirname, '..', '..', 'landing', 'reference.html');

describe('the formatting reference', () => {
  it('lists every lesson once: standard Markdown first, then Ghost.md’s own', () => {
    const sections = referenceSections();
    const listed = sections.flatMap((part) => part.lessons.map((lesson) => lesson.id));
    expect(new Set(listed).size).toBe(listed.length);
    expect(listed.length).toBe(LESSONS.length);
    expect(sections[0]?.lessons.every((lesson) => lesson.standard)).toBe(true);
    expect(sections.slice(1).every((part) => part.lessons.every((lesson) => !lesson.standard))).toBe(true);
  });

  it('is the page the site serves', () => {
    const page = referencePage();
    if (process.env.WRITE_REFERENCE) writeFileSync(PAGE, page);
    expect(readFileSync(PAGE, 'utf8'), 'landing/reference.html is behind the lessons: WRITE_REFERENCE=1 npx vitest run src/landing/reference.test.ts').toBe(page);
  });

  it('keeps the characters as they are typed, escaped for the page', () => {
    const page = referencePage();
    // A query's `due <= today+7` and a quote's `>` come through as characters, never as markup.
    expect(page).toContain('due &lt;= today+7');
    expect(page).toContain('&gt; The deposit');
  });
});
