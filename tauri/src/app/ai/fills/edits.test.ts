import { describe, expect, it } from 'vitest';
import { blanksIn, fillsIn } from '../../core/blanks.ts';
import { allChanges, applyChanges, landingChanges, signatureChange, type Landing } from './edits.ts';
import { shapeOf } from './shape.ts';

const META = { model: 'Qwen3.5 4B', date: '2026-09-28', source: { kind: 'memory' as const } };

/** The note after the last blank of `text` is answered with `words`. */
function landed(text: string, words: string[], source: Landing['source'] = META.source): string {
  const blank = blanksIn(text).at(-1)!;
  const answer: Landing = { from: blank.from, to: blank.to, question: blank.question, info: shapeOf(blank, text), words, ...META, source };
  return applyChanges(text, landingChanges(text, answer));
}

describe('where an answer goes', () => {
  it('replaces a blank in a sentence with the mark and its source', () => {
    expect(landed('# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}', ['midweek'])).toBe(
      '# Tokyo trip\n\nFlights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)',
    );
    expect(landed('# Weather\n\nLisbon tomorrow: {?weather}', ['Rain showers, 19 to 25 °C'], { kind: 'web', name: 'Open-Meteo' })).toContain('??Rain showers, 19 to 25 °C??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)');
  });

  it('lands items one a line with the list’s own lead, each with its place', () => {
    expect(landed('## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}', ['Rail pass', 'Walking shoes', 'Cash in yen'])).toBe(
      [
        '## Japan packing',
        '- Passport',
        '- Plug adapter',
        '- ??Rail pass??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 1 of 3)',
        '- ??Walking shoes??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 2 of 3)',
        '- ??Cash in yen??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 3 of 3)',
      ].join('\n'),
    );
    expect(landed('# Trip\n\n1. Passport\n2. {?more}', ['Rail pass', 'Cash'])).toContain('2. ??Rail pass??(Qwen3.5 4B from memory, 2026-09-28. Asked: more. 1 of 2)\n3. ??Cash??');
    expect(landed('# Tap\n- [x] Found it\n- [ ] {?the next step}', ['Fit the washer'])).toBe('# Tap\n- [x] Found it\n- [ ] ??Fit the washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)');
  });

  it('never writes a mark into a title', () => {
    const words = ' Book the cabin for the second week of October. Ferry once Sam confirms dates with her brother. Deposit $200 by Friday.';
    expect(landed(`# {?}\n\n${words}`, ['Cabin booking'])).toBe(`# Cabin booking\n\n${words}`);
    expect(landed('# Trip to {?capital of Japan}\n\nFlights booked.', ['Tokyo'])).toBe('# Trip to Tokyo\n\nFlights booked.');
    expect(landed('# {?who wrote Dune}', ['Frank Herbert'])).toBe('# who wrote Dune\n??Frank Herbert??(Qwen3.5 4B from memory, 2026-09-28. Asked: who wrote Dune)');
    expect(landed('{?how long to boil an egg}', ['About 6 minutes for soft, 10 for hard'])).toBe(
      'how long to boil an egg\n\n??About 6 minutes for soft, 10 for hard??(Qwen3.5 4B from memory, 2026-09-28. Asked: how long to boil an egg)',
    );
  });

  it('lands in a table cell, and several answers in one set of changes', () => {
    const table = '# Reading\n\n| Book | Author | Year |\n| --- | --- | --- |\n| The Remains of the Day | {?} | {?} |';
    const [a, b] = blanksIn(table);
    const answers: Landing[] = [
      { from: a!.from, to: a!.to, question: '', info: shapeOf(a!, table), words: ['Kazuo Ishiguro'], ...META },
      { from: b!.from, to: b!.to, question: '', info: shapeOf(b!, table), words: ['1989'], ...META },
    ];
    expect(applyChanges(table, allChanges(table, answers)).split('\n').at(-1)).toBe(
      '| The Remains of the Day | ??Kazuo Ishiguro??(Qwen3.5 4B from memory, 2026-09-28) | ??1989??(Qwen3.5 4B from memory, 2026-09-28) |',
    );
  });

  it('replaces an answer asked again with the new one', () => {
    const note = '# Football\n\nThe 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
    const fill = fillsIn(note)[0]!;
    const pseudo = `${note.slice(0, fill.from)}{?}${note.slice(fill.to)}`;
    const info = shapeOf(blanksIn(pseudo)[0]!, pseudo);
    const next = applyChanges(note, landingChanges(note, { from: fill.from, to: fill.to, question: '', info, words: ['Argentina'], ...META }));
    expect(next).toBe('# Football\n\nThe 2022 World Cup was won by ??Argentina??(Qwen3.5 4B from memory, 2026-09-28)');
  });

  it('signs the note at its top, apart from the answers', () => {
    const note = '# Trip\n\nWords {?}';
    const sign = signatureChange(note)!;
    expect(applyChanges(note, [sign])).toMatch(/^---\nauthors: Ghost\n---\n# Trip/);
    expect(sign.to).toBeLessThanOrEqual(note.indexOf('{?'));
    expect(signatureChange(applyChanges(note, [sign]))).toBeNull();
  });
});
