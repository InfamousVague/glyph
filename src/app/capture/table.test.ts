import { describe, expect, it } from 'vitest';
import { appendBlock, cellsOf, fitRow, saysDone, tableMarkdown } from './table.ts';

describe('a table said out loud', () => {
  it('hears column labels and rows the way lists are said', () => {
    expect(cellsOf('Bug, owner and status.')).toEqual(['Bug', 'Owner', 'Status']);
    expect(cellsOf('seek bar drift, Matt, open')).toEqual(['Seek bar drift', 'Matt', 'Open']);
    expect(cellsOf('name and email')).toEqual(['Name', 'Email']);
    expect(cellsOf('Column one, bug, column two, owner.')).toEqual(['Bug', 'Owner']);
    expect(cellsOf('')).toEqual([]);
  });

  it('fits a row to the columns without inventing one', () => {
    expect(fitRow(['Login broken'], 3)).toEqual(['Login broken', '', '']);
    expect(fitRow(['A', 'B', 'C', 'D'], 3)).toEqual(['A', 'B', 'C, D']);
  });

  it('hears when the rows are done, and not in a row that mentions it', () => {
    expect(saysDone('Done.')).toBe(true);
    expect(saysDone("Okay, that's it")).toBe(true);
    expect(saysDone('No more rows.')).toBe(true);
    expect(saysDone('Done list, Sam, closed')).toBe(false);
  });

  it('writes GFM, with pipes in a cell kept as text', () => {
    expect(tableMarkdown(['Bug', 'Owner'], [['Seek bar | drift', 'Matt'], ['Login']])).toBe(
      '| Bug | Owner |\n| --- | --- |\n| Seek bar \\| drift | Matt |\n| Login |  |',
    );
    expect(appendBlock('# Bugbash\n\nFriday.\n', '| A |\n| --- |')).toBe('# Bugbash\n\nFriday.\n\n| A |\n| --- |\n');
  });
});
