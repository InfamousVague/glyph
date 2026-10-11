import { describe, expect, it } from 'vitest';
import { chapterOf } from './chapterNumber.ts';

describe('a chapter number in a title', () => {
  it('reads the standard at the end: Ch. or Chapter, an Arabic or Roman number, after a mark or in brackets', () => {
    expect(chapterOf('The risks, and a glossary · Ch. 8')).toEqual({ number: 8, name: 'The risks, and a glossary' });
    expect(chapterOf('The risks (Chapter 8)')).toEqual({ number: 8, name: 'The risks' });
    expect(chapterOf('The risks — chapter VIII')).toEqual({ number: 8, name: 'The risks' });
    expect(chapterOf('The risks, Ch 12')).toEqual({ number: 12, name: 'The risks' });
    expect(chapterOf('The risks [ch. iv]')).toEqual({ number: 4, name: 'The risks' });
  });

  it('reads a number written in front, the way many chapters already are', () => {
    expect(chapterOf('08 · The risks, and a glossary')).toEqual({ number: 8, name: 'The risks, and a glossary' });
    expect(chapterOf('Chapter 3: Getting there')).toEqual({ number: 3, name: 'Getting there' });
    expect(chapterOf('Ch. XII · The end')).toEqual({ number: 12, name: 'The end' });
  });

  it('leaves titles alone that only end in a number or a word like one', () => {
    expect(chapterOf('Top 10')).toBeNull();
    expect(chapterOf('Batch 5')).toBeNull();
    expect(chapterOf('Chapter mix: songs')).toBeNull();
    expect(chapterOf('Packing (shared 2)')).toBeNull();
    expect(chapterOf('2026 plans')).toBeNull();
    expect(chapterOf('Task Management')).toBeNull();
  });

  it('reads § as the word for a chapter, and numbers to three places, but not four', () => {
    expect(chapterOf('Notes § 4')).toEqual({ number: 4, name: 'Notes' });
    expect(chapterOf('§ 3 · Rules')).toEqual({ number: 3, name: 'Rules' });
    expect(chapterOf('The end · Ch. 120')).toEqual({ number: 120, name: 'The end' });
    expect(chapterOf('The end · Chapter C')).toEqual({ number: 100, name: 'The end' });
    expect(chapterOf('The end · Ch. 1200')).toBeNull();
  });
});
