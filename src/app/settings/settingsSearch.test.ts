import { describe, expect, it } from 'vitest';
import { findSetting, searchSettings, type SearchableSection } from './settingsSearch.ts';

// The shape of Settings since docs/DESIGN.md §138, cut down: Appearance holds what were Type's and Animations' rows.
const sections: SearchableSection[] = [
  {
    id: 'theme',
    label: 'Appearance',
    summary: 'Dark · Maple Mono',
    words: 'theme look feel',
    settings: [{ name: 'Type', words: 'text font' }, { name: 'Note font', words: 'font typeface' }, { name: 'Code', words: 'syntax' }, { name: 'Smoke at the edges' }, { name: 'Ghostly typing' }],
  },
  { id: 'recording', label: 'Recording', settings: [{ name: "Use Ghost.md's guess" }] },
  { id: 'examples', label: 'Examples', settings: [{ name: 'Add the “How Ghost.md works” canvas' }] },
  { id: 'developer', label: 'Developer', settings: [{ name: 'Smoke bench' }] },
];

const found = (query: string) => searchSettings(sections, query).map((hit) => (hit.setting ? `${hit.section.id}/${hit.setting}` : hit.section.id));

describe('searchSettings', () => {
  it('finds nothing for an empty field', () => {
    expect(found('')).toEqual([]);
    expect(found('   ')).toEqual([]);
  });

  it('finds a section by its name, its state line or its own words', () => {
    expect(found('appear')).toEqual(['theme']);
    expect(found('dark')).toEqual(['theme']);
    expect(found('feel')).toEqual(['theme']);
  });

  it('finds a setting inside a section, each on its own page', () => {
    expect(found('smoke')).toEqual(['theme/Smoke at the edges', 'developer/Smoke bench']);
    expect(found('syntax')).toEqual(['theme/Code']);
    expect(found('FONT')).toEqual(['theme/Type', 'theme/Note font']);
  });

  it('needs every word, in any order, each at the start of a word', () => {
    expect(found('edges smo')).toEqual(['theme/Smoke at the edges']);
    expect(found('moke')).toEqual([]);
    expect(found('smoke bench edges')).toEqual([]);
  });

  it("doesn't list the settings of a section its name already found", () => {
    expect(found('examples')).toEqual(['examples']);
  });

  it('reads curly quotes and apostrophes as straight ones', () => {
    expect(found('"how ghost')).toEqual(['examples/Add the “How Ghost.md works” canvas']);
    expect(found("ghost.md's")).toEqual(["recording/Use Ghost.md's guess"]);
  });
});

describe('findSetting', () => {
  it('finds the row, card or hero naming a setting on a page, and nothing that only mentions it', () => {
    const page = document.createElement('div');
    page.innerHTML = `
      <section class="setk"><div class="setk__title">Code</div>
        <div class="setk-row"><span class="setk-row__label">On the light page</span><span class="setk-row__hint">Code colours</span></div>
      </section>
      <div class="setk-row"><span class="setk-row__label">Add the “How Ghost.md works” canvas</span></div>`;
    expect(findSetting(page, 'Code')?.className).toBe('setk__title');
    expect(findSetting(page, 'add the "how ghost.md works" canvas')?.textContent).toBe('Add the “How Ghost.md works” canvas');
    expect(findSetting(page, 'Code colours')).toBeNull();
  });
});
