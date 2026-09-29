import { describe, expect, it } from 'vitest';
import { noteTitle } from '../core/noteTitle.ts';
import { PRESETS } from './journal.ts';
import { entryStarts, pageBody, pageStarts, startLine } from './entryStarts.ts';

describe('what a new page starts with', () => {
  it('offers just the title first, then the journal templates', () => {
    expect(pageStarts().map((each) => each.name)).toEqual(['Just the title', ...PRESETS.map((each) => each.name)]);
    expect(pageStarts()[0]!.text).toBe('');
  });

  it('keeps the page’s title as its heading, so the index still finds it, with the template under it', () => {
    const at = new Date(2026, 8, 29, 14, 5);
    expect(pageBody('Monday', '', 'Field guide', at)).toBe('# Monday\n\n');
    const morning = pageBody('Monday', PRESETS[2]!.text, 'Field guide', at);
    expect(noteTitle(morning)).toBe('Monday');
    expect(morning.startsWith('# Monday\n\n## ')).toBe(true);
    expect(morning).toContain('> What is on your mind this morning?');
    expect(morning.match(/^# /gm)).toHaveLength(1);
    expect(pageBody('Monday', '**{{time}}** from {{journal}}, {{title}}', 'Field guide', at)).toBe('# Monday\n\n**14:05** from Field guide, Monday');
  });
});

describe('what a new entry starts with', () => {
  it('puts the usual template first, then the presets it is not, then an empty page', () => {
    expect(entryStarts(PRESETS[1]!.text).map((each) => each.id)).toEqual(['usual', 'stamped', 'morning', 'todos', 'empty']);
    expect(startLine('', 'Log')).toBe('Nothing, a blank page');
  });
});
