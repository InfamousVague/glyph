import { describe, expect, it } from 'vitest';
import { applyLinks, itemAt, itemWords, linkedLine, markOf, registerMarkName, unmarked, unsentItems } from './itemLinks.ts';

describe('list items for Notion', () => {
  const body = [
    '# AttackFM',
    '',
    '- [ ] Fix the login bug',
    '- [x] Ship 0.6.9',
    '- [ ] Pins in the list [notion](https://www.notion.so/attackfm/Pins-1a2b3c)',
    '- [ ] [Old style link](https://www.notion.so/attackfm/Old-4d5e6f)',
    '- Radio idea',
    '1. First step',
    'Not an item.',
    '- ![](image/a.jpg)',
  ].join('\n');

  it('finds the items that are not sent yet, skipping done and linked ones of either form', () => {
    expect(unsentItems(body)).toEqual([
      { line: 3, text: 'Fix the login bug' },
      { line: 7, text: 'Radio idea' },
      { line: 8, text: 'First step' },
    ]);
  });

  it('marks an item at its end and keeps its marker and its words', () => {
    expect(linkedLine('- [ ] Fix the login bug', 'https://www.notion.so/x-1')).toBe('- [ ] Fix the login bug [notion](https://www.notion.so/x-1)');
    expect(linkedLine('  2) Brackets [out]', 'https://n.so/y')).toBe('  2) Brackets [out] [notion](https://n.so/y)');
    registerMarkName('github');
    expect(linkedLine('- Call Sam', 'https://github.com/i/1', 'github')).toBe('- Call Sam [github](https://github.com/i/1)');
    // Marking a marked item replaces the mark rather than stacking two.
    expect(linkedLine('- [ ] Buy milk [notion](https://n.so/a)', 'https://n.so/b')).toBe('- [ ] Buy milk [notion](https://n.so/b)');
  });

  it('reads a mark back, and the words without it', () => {
    expect(markOf('Buy milk [notion](https://n.so/a)')).toEqual({ name: 'notion', url: 'https://n.so/a' });
    expect(markOf('Buy milk')).toBeNull();
    expect(markOf('[Buy milk](https://n.so/a)')).toBeNull();
    // A one-word link at the end is only a mark when the word is a plugin's name.
    expect(markOf('read the [docs](https://n.so/d)')).toBeNull();
    expect(unmarked('read the [docs](https://n.so/d)')).toBe('read the [docs](https://n.so/d)');
    expect(unmarked('Buy milk [notion](https://n.so/a)  ')).toBe('Buy milk');
    expect(itemWords('- [ ] Buy milk [notion](https://n.so/a)')).toBe('Buy milk');
    expect(itemWords('Just words')).toBeNull();
  });

  it('answers for one line', () => {
    expect(itemAt('- [ ] Call Sam', 4)).toEqual({ line: 4, text: 'Call Sam' });
    expect(itemAt('Just words', 4)).toBeNull();
    expect(itemAt('- [ ] Call Sam [notion](https://n.so/a)', 4)).toBeNull();
  });

  it('is what the voice path writes too, line by line', () => {
    // plugins/notion/voice.ts: body.replace(line, linkedLine(line, url)).
    const noteBody = '# Trip\n\n- [ ] Book the cabin\n- [ ] Pack snacks\n';
    const line = '- [ ] Book the cabin';
    expect(noteBody.replace(line, linkedLine(line, 'https://n.so/a'))).toBe('# Trip\n\n- [ ] Book the cabin [notion](https://n.so/a)\n- [ ] Pack snacks\n');
  });
});

describe('links for things sent while talking', () => {
  it('marks the words where the cues put them', () => {
    const markdown = '# Trip\n\n- [ ] Book the cabin\n- Pack snacks\n\nWe leave Friday.';
    expect(applyLinks(markdown, [{ text: 'Book the cabin.', url: 'https://n.so/a' }])).toBe(
      '# Trip\n\n- [ ] Book the cabin [notion](https://n.so/a)\n- Pack snacks\n\nWe leave Friday.',
    );
    expect(applyLinks(markdown, [{ text: 'leave Friday', url: 'https://n.so/b' }])).toContain('We leave Friday [notion](https://n.so/b).');
  });

  it('does nothing when the words are not there or already linked', () => {
    expect(applyLinks('- x [notion](https://n.so/a)', [{ text: 'x', url: 'https://n.so/a' }])).toBe('- x [notion](https://n.so/a)');
    expect(applyLinks('- [x](https://n.so/a)', [{ text: 'x', url: 'https://n.so/a' }])).toBe('- [x](https://n.so/a)');
    expect(applyLinks('Hello', [{ text: 'bye', url: 'https://n.so/c' }])).toBe('Hello');
  });
});
