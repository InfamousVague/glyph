import { describe, expect, it } from 'vitest';
import { applyLinks, itemAt, linkedLine, unsentItems } from './itemLinks.ts';

describe('list items for Notion', () => {
  const body = [
    '# AttackFM',
    '',
    '- [ ] Fix the login bug',
    '- [x] Ship 0.6.9',
    '- [ ] [Pins in the list](https://www.notion.so/attackfm/Pins-1a2b3c)',
    '- Radio idea',
    '1. First step',
    'Not an item.',
    '- ![](image/a.jpg)',
  ].join('\n');

  it('finds the items that are not sent yet, skipping done and linked ones', () => {
    expect(unsentItems(body)).toEqual([
      { line: 3, text: 'Fix the login bug' },
      { line: 6, text: 'Radio idea' },
      { line: 7, text: 'First step' },
    ]);
  });

  it('turns an item into a link and keeps its marker', () => {
    expect(linkedLine('- [ ] Fix the login bug', 'https://www.notion.so/x-1')).toBe('- [ ] [Fix the login bug](https://www.notion.so/x-1)');
    expect(linkedLine('  2) Brackets [out]', 'https://n.so/y')).toBe('  2) [Brackets out](https://n.so/y)');
  });

  it('answers for one line', () => {
    expect(itemAt('- [ ] Call Sam', 4)).toEqual({ line: 4, text: 'Call Sam' });
    expect(itemAt('Just words', 4)).toBeNull();
  });
});

describe('links for things sent while talking', () => {
  it('links the words where the cues put them', () => {
    const markdown = '# Trip\n\n- [ ] Book the cabin\n- Pack snacks\n\nWe leave Friday.';
    expect(applyLinks(markdown, [{ text: 'Book the cabin.', url: 'https://n.so/a' }])).toBe(
      '# Trip\n\n- [ ] [Book the cabin](https://n.so/a)\n- Pack snacks\n\nWe leave Friday.',
    );
    expect(applyLinks(markdown, [{ text: 'leave Friday', url: 'https://n.so/b' }])).toContain('We [leave Friday](https://n.so/b).');
  });

  it('does nothing when the words are not there or already linked', () => {
    expect(applyLinks('- [x](https://n.so/a)', [{ text: 'x', url: 'https://n.so/a' }])).toBe('- [x](https://n.so/a)');
    expect(applyLinks('Hello', [{ text: 'bye', url: 'https://n.so/c' }])).toBe('Hello');
  });
});
