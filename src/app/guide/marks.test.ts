import { describe, expect, it } from 'vitest';
import { markGroups } from './marks.ts';
import { GUIDE_MARKS_PAGE, GUIDE_PAGES } from './pages.ts';
import { BUILT_IN } from '../plugins/registry.ts';

const rows = () => markGroups().flatMap((group) => group.rows);

describe('the guide’s table of marks', () => {
  it('has a page of its own in the walkthrough', () => {
    expect(GUIDE_PAGES).toContain('marks');
    expect(GUIDE_MARKS_PAGE).toBeGreaterThan(0);
  });

  it('shows every mark the app writes, each with its own example', () => {
    const symbols = rows().map((row) => row.symbol);
    for (const mark of ['**', '_', '~~', '`', '#', '##', '-', '1.', '- [ ]', '>', '---', '| |', '![ ]( )', '```', '[ ]( )']) {
      expect(symbols, mark).toContain(mark);
    }
    for (const row of rows()) {
      expect(row.typed, row.name).toBeTruthy();
      expect(row.name, row.typed).toBeTruthy();
    }
    expect(new Set(rows().map((row) => row.name)).size).toBe(rows().length);
  });

  it('shows each mark a switched-on plugin adds, with the words it would say', () => {
    const formats = BUILT_IN.flatMap((plugin) => plugin.formats ?? []);
    const own = markGroups().find((group) => group.title === 'Glyph’s own');
    expect(own?.rows).toHaveLength(formats.length);
    for (const format of formats) {
      const row = own?.rows.find((r) => r.name === format.name);
      expect(row, format.name).toBeTruthy();
      expect(row?.symbol).toBe(format.delimiter);
      // The example is the mark around its words, so a person can copy it as it stands.
      expect(row?.typed.startsWith(format.delimiter) && row?.typed.endsWith(format.delimiter)).toBe(true);
      if (format.cue) expect(row?.say).toContain(format.cue);
    }
  });

  it('draws a plugin’s look from the CSS the plugin declares', () => {
    const own = markGroups().find((group) => group.title === 'Glyph’s own');
    const highlight = own?.rows.find((row) => row.name === 'Highlight');
    expect(highlight?.looks).toBe('style');
    expect(highlight?.css).toContain('background');
    expect(own?.rows.find((row) => row.name === 'Spoiler')?.looks).toBe('wisp');
  });
});
