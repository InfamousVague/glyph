import { describe, expect, it } from 'vitest';
import { movedBody } from './move.ts';

describe('a card dragged into another lane', () => {
  const TICKET = '---\ntype: ticket\nid: GHO-1\nstatus: In progress\npriority: high\n---\n# Fix the login loop\n';

  it('sets a ticket’s front-matter status to the lane it lands in', () => {
    expect(movedBody(TICKET, 0, '', 'ticket', 'status', 'In review')).toContain('status: In review');
    expect(movedBody(TICKET, 0, '', 'ticket', 'status', 'In review')).not.toContain('In progress');
  });

  it('clears the field when dropped in the "No …" lane', () => {
    const cleared = movedBody(TICKET, 0, '', 'ticket', 'status', null)!;
    expect(cleared).not.toContain('status:');
    expect(cleared).toContain('priority: high');
  });

  it('leaves the body alone when the lane is the one it is already in', () => {
    expect(movedBody(TICKET, 0, '', 'ticket', 'status', 'In progress')).toBe(TICKET);
  });

  it('writes a to-do’s inline field on its own line, found by its words', () => {
    const body = '# Board\n\n- [ ] Milk [stage:: Todo]\n- [ ] Eggs [stage:: Todo]\n';
    const source = '- [ ] Eggs [stage:: Todo]';
    const next = movedBody(body, 3, source, 'task', 'stage', 'Doing')!;
    expect(next).toContain('- [ ] Eggs [stage:: Doing]');
    // The other line is untouched.
    expect(next).toContain('- [ ] Milk [stage:: Todo]');
  });

  it('leaves a to-do alone when its line is gone', () => {
    expect(movedBody('# Board\n\n- [ ] Milk\n', 2, '- [ ] Bread', 'task', 'stage', 'Doing')).toBeNull();
  });
});
