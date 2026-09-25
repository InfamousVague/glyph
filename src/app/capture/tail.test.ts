import { describe, expect, it } from 'vitest';
import { layout, tailStart } from './tail.ts';

const text = (runs: { text: string }[]) => runs.map((r) => r.text).join('');

describe('the recorder lays out the live note', () => {
  it('reads each kind of line off its mark', () => {
    const lines = layout('# Trip\n\n- [ ] Book the cabin\n- snacks\n1. first\n> quoted\nplain', null);
    expect(lines.map((l) => [l.kind, l.mark])).toEqual([
      ['heading', '#'],
      ['blank', ''],
      ['task', '- [ ]'],
      ['bullet', '-'],
      ['number', '1.'],
      ['quote', '>'],
      ['para', ''],
    ]);
    expect(lines[0]?.level).toBe(1);
    expect(text(lines[2]?.runs ?? [])).toBe('Book the cabin');
  });

  it('reads every marker the note can hold, as core/itemSyntax.ts spells them', () => {
    const lines = layout('* [ ] Starred to-do\n+ Plus bullet\n2) Bracketed\n1234. Long numbered', null);
    expect(lines.map((l) => [l.kind, l.mark])).toEqual([
      ['task', '* [ ]'],
      ['bullet', '+'],
      ['number', '2)'],
      ['number', '1234.'],
    ]);
  });

  it('dims the stars around bold and not the bold words', () => {
    const [line] = layout('We agreed on **four thousand** today', null);
    expect(line?.runs).toEqual([
      { text: 'We agreed on ', kind: 'text' },
      { text: '**', kind: 'mark' },
      { text: 'four thousand', kind: 'text' },
      { text: '**', kind: 'mark' },
      { text: ' today', kind: 'text' },
    ]);
  });

  it('marks everything from the pending offset as a guess', () => {
    const md = '# Trip\n\nBook the cabin and';
    const lines = layout(md, md.indexOf('and'));
    expect(lines[2]?.runs).toEqual([
      { text: 'Book the cabin ', kind: 'text' },
      { text: 'and', kind: 'pending' },
    ]);
    expect(lines[2]?.pending).toBe(false);
    const whole = layout('- [ ] guess', 0);
    expect(whole[0]?.pending).toBe(true);
    expect(whole[0]?.kind).toBe('task');
  });

  it('starts the tail on a whole line', () => {
    const md = 'first line\n- [ ] second line here';
    const start = tailStart(md, 8);
    expect(md.slice(start)).toBe('- [ ] second line here');
    expect(layout(md, null, start)[0]?.kind).toBe('task');
    expect(tailStart('short', 100)).toBe(0);
  });
});
