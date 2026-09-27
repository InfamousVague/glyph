import { describe, expect, it } from 'vitest';
import { quietHost } from '../../test/takeHost.ts';
import type { TakeNote } from './takeTypes.ts';
import { Take } from './take.ts';

/** The take (capture/take.ts): carrying on in another note. */

describe('carrying on in another note', () => {
  it('starts the take afresh, and marks what it had said as commands for the better words to leave out', () => {
    let changes = 0;
    const take = new Take<TakeNote>(quietHost<TakeNote>({ changed: () => void (changes += 1) }));
    take.listen({ text: 'For the soup.', startMs: 0, endMs: 900 });
    take.listen({ text: 'Leeks and stock.', startMs: 1200, endMs: 2400 });
    const before = changes;
    take.fork();
    expect(take.segments).toEqual([]);
    expect(take.hasContent).toBe(false);
    expect(take.commandSpans).toEqual([
      { startMs: 0, endMs: 900 },
      { startMs: 1200, endMs: 2400 },
    ]);
    // The page is told, so the words said for the last note leave this one.
    expect(changes).toBe(before + 1);
    take.listen({ text: 'Call Sam.', startMs: 3000, endMs: 3900 });
    expect(take.markdown({ titled: true })).toBe('# Call Sam');
  });
});
