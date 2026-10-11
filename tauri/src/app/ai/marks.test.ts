import { beforeEach, describe, expect, it } from 'vitest';
import { forgetMarks, hasMarks, loadMarks, saveMarks } from './marks.ts';

beforeEach(() => localStorage.clear());

describe('the marks kept with a note', () => {
  const change = { id: 'c', runId: 'r', from: 0, to: 3, removed: '', block: true };

  it('come back for the same body and not for another', () => {
    saveMarks('n', 'abc\n', [change]);
    expect(hasMarks('n')).toBe(true);
    expect(loadMarks('n', 'abc\n')).toEqual([change]);
    expect(loadMarks('n', 'abd\n')).toBeNull();
    expect(loadMarks('other', 'abc\n')).toBeNull();
  });

  it('go when there are none left, and with the note', () => {
    saveMarks('n', 'abc\n', [change]);
    saveMarks('n', 'abc\n', []);
    expect(hasMarks('n')).toBe(false);
    saveMarks('n', 'abc\n', [change]);
    forgetMarks('n');
    expect(hasMarks('n')).toBe(false);
  });
});
