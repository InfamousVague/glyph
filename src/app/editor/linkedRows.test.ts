import { describe, expect, it } from 'vitest';
import { provideMarkDetails } from '../core/markDetails.ts';
import { linkedOn, unlinked } from './linkedRows.ts';

provideMarkDetails('notion', () => ({
  peek: () => null,
  want: () => undefined,
  open: async () => undefined,
  reads: (url) => url.includes('notion.so/'),
}));

const TASK = 'https://www.notion.so/Buy-milk-3db522a4563081298304c129ce6004e4';

describe('what a line is linked to', () => {
  it('finds an item’s mark, with the item’s words', () => {
    expect(linkedOn(`- [ ] Buy milk [notion](${TASK})`, 40)).toEqual({ from: 40, name: 'notion', url: TASK, words: 'Buy milk', kind: 'mark', item: true });
  });

  it('finds a link written the old way, and one in a sentence', () => {
    expect(linkedOn(`- [ ] [Buy milk](${TASK}) on the way home`)).toMatchObject({ kind: 'link', item: true, words: 'Buy milk on the way home' });
    expect(linkedOn(`Remember [the task](${TASK}) tomorrow.`)).toMatchObject({ kind: 'link', item: false, words: 'the task' });
  });

  it('leaves lines with no link, or a link no plugin reads', () => {
    expect(linkedOn('- [ ] Buy milk')).toBeNull();
    expect(linkedOn('- [ ] Read [the docs](https://example.com/docs)')).toBeNull();
  });

  it('unlinks, keeping the words', () => {
    expect(unlinked(`- [ ] Buy milk [notion](${TASK})`, { kind: 'mark', url: TASK })).toBe('- [ ] Buy milk');
    expect(unlinked(`- [ ] [Buy milk](${TASK}) on the way home`, { kind: 'link', url: TASK })).toBe('- [ ] Buy milk on the way home');
  });
});
