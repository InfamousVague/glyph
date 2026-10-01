import { describe, expect, it } from 'vitest';
import { NOTES, TODAY } from './library.fixture.ts';
import { readQuery } from './read.ts';
import { libraryOf } from './records.ts';
import { runQuery } from './run.ts';
import { QUERY_TEMPLATES } from './templates.ts';

/* The databases the + offers ready-made (core/query/templates.ts): each reads, runs, and is shown as its row says. */

describe('the ready-made databases', () => {
  it('each reads without a problem, and is shown the way its row says', () => {
    for (const template of QUERY_TEMPLATES) {
      const reading = readQuery(template.lines);
      expect(reading.problem, template.id).toBeNull();
      const result = runQuery(reading.query!, libraryOf(NOTES), TODAY);
      expect(result.show, template.id).toBe(template.show);
    }
  });

  it('finds something in an ordinary library', () => {
    const found = (id: string) => {
      const template = QUERY_TEMPLATES.find((each) => each.id === id)!;
      return runQuery(readQuery(template.lines).query!, libraryOf(NOTES), TODAY).matched;
    };
    expect(found('week')).toBeGreaterThan(0);
    expect(found('late')).toBeGreaterThan(0);
    expect(found('people')).toBeGreaterThan(0);
    expect(found('board')).toBe(3);
    expect(found('tickets')).toBe(2);
    expect(found('count')).toBe(5);
  });

  it('has an id each, and leaves only Write your own to be written over', () => {
    expect(new Set(QUERY_TEMPLATES.map((template) => template.id)).size).toBe(QUERY_TEMPLATES.length);
    expect(QUERY_TEMPLATES.filter((template) => template.select).map((template) => template.id)).toEqual(['own']);
    const own = QUERY_TEMPLATES.find((template) => template.id === 'own')!;
    expect(own.lines).toContain(own.select!);
  });
});
