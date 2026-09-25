import { beforeEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { sweepMemos, wasMemo } from './sweepMemos.ts';
import { isTrashed } from './trash.ts';

describe('sweeping the memos out', () => {
  beforeEach(() => localStorage.clear());

  it('knows a memo by its front matter and nothing else', () => {
    expect(wasMemo('---\nkind: memo\n---\nMilk')).toBe(true);
    expect(wasMemo('---\nid: x\nKind:  Memo\n---\nMilk')).toBe(true);
    expect(wasMemo('# Groceries\n\nkind: memo')).toBe(false);
    expect(wasMemo('---\nkind: memoir\n---\nwords')).toBe(false);
    expect(wasMemo('---\ntitle: Plans\n---\n# Plans')).toBe(false);
  });

  // Until 2026-09-25 a `kind: memo` line was enough before any close came; the block now has to be front matter as
  // the list reads it (core/frontMatter.ts), closed.
  it('knows no memo by a block that never closes', () => {
    expect(wasMemo('---\nkind: memo\nMilk')).toBe(false);
    expect(wasMemo('---\nkind: memo\n')).toBe(false);
  });

  it('puts every memo in the trash, once, and leaves the notes alone', () => {
    const notes = [makeNote('m1', '---\nkind: memo\n---\nMilk'), makeNote('n1', '# A note'), makeNote('m2', '---\nkind: memo\n---\nEggs')];
    expect(sweepMemos(notes)).toBe(2);
    expect(isTrashed('m1')).toBe(true);
    expect(isTrashed('m2')).toBe(true);
    expect(isTrashed('n1')).toBe(false);
    // Done once: a memo-shaped note written later by hand is not swept.
    expect(sweepMemos([...notes, makeNote('m3', '---\nkind: memo\n---\nLater')])).toBe(0);
    expect(isTrashed('m3')).toBe(false);
  });
});
