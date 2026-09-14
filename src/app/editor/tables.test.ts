import { describe, expect, it } from 'vitest';
import { parseTable } from './tables.ts';

describe('reading a GFM table to draw it', () => {
  it('reads the header, the alignment and the rows, escaped pipes kept as text', () => {
    expect(parseTable('| Bug | Owner | Status |\n| --- | :---: | ---: |\n| Seek bar \\| drift | Matt | Open |\n| Login |')).toEqual({
      header: ['Bug', 'Owner', 'Status'],
      align: [null, 'center', 'right'],
      rows: [
        ['Seek bar | drift', 'Matt', 'Open'],
        ['Login', '', ''],
      ],
    });
  });

  it('is not a table without its divider line', () => {
    expect(parseTable('| a | b |\n| c | d |')).toBeNull();
  });
});
