import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { titleKey } from '../core/titleKey.ts';
import { BUILT_INS, fillNoteTemplate, type TemplateId } from './noteTemplates.ts';

/**
 * The six templates a new note can start from (noteTemplates.ts), each filled exactly as it will be written at 14:05 on
 * Monday 28 September 2026 in en-GB, with its caret (`|`); a taken name given " (2)" before anything is measured; and
 * none of the things a card cannot draw still.
 */

const AT = () => new Date(2026, 8, 28, 14, 5);
const template = (id: TemplateId) => BUILT_INS.find((one) => one.id === id)!;
const fill = (id: TemplateId, taken: string[] = []) => inLocale('en-GB', () => fillNoteTemplate(template(id), AT(), new Set(taken.map(titleKey))));
/** The note as it is made, the caret drawn in it as `|`. */
const made = (id: TemplateId, taken: string[] = []) => {
  const { body, caret } = fill(id, taken);
  return `${body.slice(0, caret)}|${body.slice(caret)}`;
};

describe('the six templates', () => {
  it('are in this order, each with its name and its fixed sentence', () => {
    expect(BUILT_INS.map((one) => [one.id, one.name, one.sentence])).toEqual([
      ['day', 'A day', 'Named for today, with a to-do to start.'],
      ['meeting', 'A meeting', 'Named for this minute, with who was there, notes and to-dos.'],
      ['checklist', 'A checklist', 'A name to type, then a to-do.'],
      ['book', 'Notes on a book', 'Its title, who wrote it, notes and quotes.'],
      ['map', 'A map at the top', 'Where you are, drawn large above the words.'],
      ['reading', 'A page to read', 'A large title, a lead line and a column set for reading.'],
    ]);
  });

  it('make each note exactly, with the caret in its first open line', () => {
    expect(made('day')).toBe('# 2026-09-28\n\nMonday 28 September\n\n- [ ] |');
    expect(made('meeting')).toBe('# Meeting 2026-09-28 14.05\n\nWith |\n\n## Notes\n\n- \n\n## To do\n\n- [ ] ');
    expect(made('checklist')).toBe('# |\n\n- [ ] ');
    expect(made('book')).toBe('# |\n\nBy \n\n## Notes\n\n- \n\n## Quotes\n\n> ');
    expect(made('map')).toBe('---\nlook: map\n---\n# |\n\nMonday 28 September, 14:05.\n');
    expect(made('reading')).toBe('---\nlook: reading\n---\n# |\n');
  });

  it('name a note by its heading, or by nothing where the heading is left open', () => {
    expect(fill('day').title).toBe('2026-09-28');
    expect(fill('meeting').title).toBe('Meeting 2026-09-28 14.05');
    expect(fill('checklist').title).toBe('');
    // The record keeps the words after the front matter: the look is not a word.
    expect(fill('reading').words).toBe('# \n');
  });

  it('give a taken name " (2)" before the caret is measured, so it lands where it would have', () => {
    expect(made('meeting', ['Meeting 2026-09-28 14.05'])).toBe('# Meeting 2026-09-28 14.05 (2)\n\nWith |\n\n## Notes\n\n- \n\n## To do\n\n- [ ] ');
    const second = fill('meeting', ['Meeting 2026-09-28 14.05']);
    expect(second.words.startsWith('# Meeting 2026-09-28 14.05 (2)\n')).toBe(true);
    expect(second.renamed).toBe(true);
    expect(made('day', ['2026-09-28', '2026-09-28 (2)'])).toBe('# 2026-09-28 (3)\n\nMonday 28 September\n\n- [ ] |');
    expect(fill('day').renamed).toBe(false);
    // An open heading has no name, and is never taken.
    expect(fill('checklist', ['']).renamed).toBe(false);
  });

  it('hold no spoiler, effect, whole line of emphasis or journal’s name, and no words in a to-do', () => {
    for (const one of BUILT_INS) {
      expect(one.words).not.toMatch(/\|\||==|~~|\{\{journal\}\}/);
      for (const line of one.words.split('\n')) {
        expect(line).not.toMatch(/^\s*[*_][^*_].*[*_]\s*$/);
        expect(line).not.toMatch(/^- \[ \] \S/);
      }
      // Its shape shows in the first five lines a card shows.
      expect(fill(one.id).words.split('\n').slice(0, 5).join('').trim()).not.toBe('');
    }
  });
});
