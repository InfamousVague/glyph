import { describe, expect, it } from 'vitest';
import { tickedBody } from './tick.ts';

/* A to-do ticked from a query in another note (core/query/tick.ts). */

describe('a to-do ticked from a query', () => {
  it('turns the box on the line the query read', () => {
    expect(tickedBody('# Shop\n\n- [ ] Milk\n- [ ] Eggs', 2, '- [ ] Milk', true)).toBe('# Shop\n\n- [x] Milk\n- [ ] Eggs');
    expect(tickedBody('- [x] Milk 📅 2026-10-04', 0, '- [x] Milk 📅 2026-10-04', false)).toBe('- [ ] Milk 📅 2026-10-04');
  });

  it('finds the line by its words where the note has moved under it', () => {
    expect(tickedBody('# Shop\n\nA new line.\n\n- [ ] Milk', 2, '- [ ] Milk', true)).toBe('# Shop\n\nA new line.\n\n- [x] Milk');
  });

  it('leaves alone a line that is gone, or no longer a to-do', () => {
    expect(tickedBody('# Shop\n\n- [ ] Bread', 2, '- [ ] Milk', true)).toBeNull();
    expect(tickedBody('- Milk', 0, '- Milk', true)).toBeNull();
  });

  it('changes nothing where the box is already as asked', () => {
    const body = '- [x] Milk';
    expect(tickedBody(body, 0, body, true)).toBe(body);
  });

  it('moves the card on a board in that note into Done, in the same write', () => {
    const body = '- [ ] Ship it ^ship\n- [ ] Test it ^test\n\n```board\nTo do: ship, test\nDone:\n```';
    expect(tickedBody(body, 0, '- [ ] Ship it ^ship', true)).toBe('- [x] Ship it ^ship\n- [ ] Test it ^test\n\n```board\nTo do: test\nDone: ship\n```');
  });
});
