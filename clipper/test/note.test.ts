import { describe, expect, it } from 'vitest';
import { frontMatterEnd, frontMatterValue } from '../../tauri/src/app/core/frontMatter.ts';
import { imageNames } from '../../tauri/src/app/core/imageRefs.ts';
import { noteTitle } from '../../tauri/src/app/core/noteTitle.ts';
import { libraryOf } from '../../tauri/src/app/core/query/records.ts';
import { cleanTitle, contentOf, frontMatter, localDate, noteBody, parseTags } from '../src/core/note.ts';

/**
 * A clip as the note it becomes, read back by the app's own readers (tauri/src/app/core): its front matter is front
 * matter, its title is the note's title, its tags are the query engine's tags, its pictures are the sync's pictures.
 */

const AT = new Date(2026, 9, 16, 17, 42);

describe('the note', () => {
  const body = noteBody({
    title: 'The Quiet Garden',
    url: 'https://field.example/2026/10/the-quiet-garden?ref=feed#beds',
    clipped: AT,
    tags: ['reading', 'garden'],
    comment: 'For the spring planting.',
    content: 'Most of the work happens underground.\n\n![Beds](image/clip-1.jpg)\n',
  });

  it('is front matter, the title as its first heading, the comment, a rule and the words', () => {
    expect(body).toBe(
      [
        '---',
        'source: https://field.example/2026/10/the-quiet-garden?ref=feed#beds',
        'clipped: 2026-10-16',
        'tags: [reading, garden]',
        '---',
        '# The Quiet Garden',
        '',
        'For the spring planting.',
        '',
        '---',
        '',
        'Most of the work happens underground.',
        '',
        '![Beds](image/clip-1.jpg)',
        '',
      ].join('\n'),
    );
  });

  it('reads back as the app reads a note: its front matter, its title, its keys and its pictures', () => {
    const lines = body.split('\n');
    expect(frontMatterEnd(lines)).toBe(5);
    expect(noteTitle(body)).toBe('The Quiet Garden');
    expect(frontMatterValue(body, 'source')).toBe('https://field.example/2026/10/the-quiet-garden?ref=feed#beds');
    expect(frontMatterValue(body, 'clipped')).toBe('2026-10-16');
    expect(imageNames(body)).toEqual(['clip-1.jpg']);
  });

  it('has tags a query finds', () => {
    const { records } = libraryOf([{ id: 'n1', body, createdAt: AT.getTime(), updatedAt: AT.getTime() }]);
    const note = records.find((r) => r.done === null)!;
    expect(note.tags).toEqual(expect.arrayContaining(['reading', 'garden']));
    expect(note.props.source).toBe('https://field.example/2026/10/the-quiet-garden?ref=feed#beds');
  });

  it('has no tags line, comment or rule when there are none', () => {
    const plain = noteBody({ title: 'A page', url: 'https://x.example/', clipped: AT, tags: [], comment: '  ', content: 'Words.' });
    expect(plain).toBe('---\nsource: https://x.example/\nclipped: 2026-10-16\n---\n# A page\n\nWords.\n');
  });

  it('quotes an address that would not read back as itself', () => {
    expect(frontMatter({ url: 'https://x.example/a b', clipped: AT, tags: [] })).toContain('source: "https://x.example/a b"');
    expect(frontMatterValue(noteBody({ title: 'T', url: 'https://x.example/it\'s', clipped: AT, tags: [], comment: '', content: '' }), 'source')).toBe("https://x.example/it's");
  });
});

describe('the pieces', () => {
  it('reads tags as the app writes them: commas or spaces, no #, a letter first, each once', () => {
    expect(parseTags('#reading, garden  later, Reading, 2026, work/clients, bad:tag')).toEqual(['reading', 'garden', 'later', 'work/clients', 'badtag']);
    expect(parseTags('')).toEqual([]);
  });

  it('cleans a title onto one line, short, never empty', () => {
    expect(cleanTitle('  The\n Quiet\tGarden ', 'https://x.example/')).toBe('The Quiet Garden');
    expect(cleanTitle('# Not a heading of a heading', 'https://x.example/')).toBe('Not a heading of a heading');
    expect(cleanTitle('', 'https://www.field.example/a')).toBe('www.field.example');
    expect(cleanTitle('x'.repeat(400), 'https://x.example/').length).toBe(160);
  });

  it('writes the date on this computer’s calendar', () => {
    expect(localDate(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });

  it('makes a bookmark of the link, the description and the preview picture', () => {
    const words = contentOf({ mode: 'bookmark', url: 'https://www.field.example/2026/garden', title: 'The Quiet Garden', markdown: '', description: 'How a garden\nkeeps its soil.', pictures: [{ url: 'https://x/p.png', alt: 'The Quiet Garden' }] });
    expect(words).toBe('[field.example/2026/garden](https://www.field.example/2026/garden)\n\nHow a garden keeps its soil.\n\n![The Quiet Garden](ghost-clip:picture/0)\n');
  });

  it('makes a screenshot of its one picture', () => {
    expect(contentOf({ mode: 'screenshot', url: 'https://x.example/', title: 'X', markdown: '', pictures: [{ url: 'data:image/png;base64,AA', alt: 'Screenshot of X' }] })).toBe('![Screenshot of X](ghost-clip:picture/0)\n');
  });
});
