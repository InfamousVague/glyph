import { describe, expect, it } from 'vitest';
import { noteSheet, sheetOf, type Sheet } from './noteSheet.ts';

/** A sheet kept in a variable, counting its writes: what a module's read and write through core/stored.ts stand for. */
function kept(start: Sheet<number> = {}) {
  let held: Sheet<number> = start;
  const writes: Sheet<number>[] = [];
  const sheet = noteSheet<number>(
    () => held,
    (value) => {
      held = value;
      writes.push(value);
    },
  );
  return { sheet, writes, held: () => held };
}

describe('a record per note, under one key', () => {
  it('keeps a note’s record worked out from the one before, and leaves the others as they were', () => {
    const { sheet, held } = kept({ a: 1 });
    sheet.update('b', (was) => (was ?? 0) + 5);
    sheet.update('a', (was) => (was ?? 0) + 1);
    expect(held()).toEqual({ a: 2, b: 5 });
  });

  it('writes a copy, never the sheet it read, which other readers may share', () => {
    const start = { a: 1 };
    const { sheet, held } = kept(start);
    sheet.update('a', () => 2);
    expect(start).toEqual({ a: 1 });
    expect(held()).not.toBe(start);
  });

  it('writes nothing when the record comes back as it was, or a missing one stays missing', () => {
    const { sheet, writes } = kept({ a: 1 });
    sheet.update('a', (was) => was);
    sheet.update('gone', () => undefined);
    sheet.forget('gone');
    expect(writes).toEqual([]);
  });

  it('forgets a note, and takes a record away when it is worked out to nothing', () => {
    const { sheet, held } = kept({ a: 1, b: 2 });
    sheet.forget('a');
    sheet.update('b', () => undefined);
    expect(held()).toEqual({});
  });

  it('reads only an object of notes as a sheet', () => {
    expect(sheetOf({ a: 1 })).toEqual({ a: 1 });
    for (const other of [null, [1, 2], 'text', 3, undefined]) expect(sheetOf(other)).toEqual({});
  });
});
