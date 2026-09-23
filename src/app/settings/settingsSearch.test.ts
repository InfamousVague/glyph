import { describe, expect, it } from 'vitest';
import { findSetting, searchSettings, type SearchableSection } from './settingsSearch.ts';

const sections: SearchableSection[] = [
  { id: 'type', label: 'Type', summary: 'Larger · Inter', words: 'text font', settings: [{ name: 'Text size' }, { name: 'Family', words: 'font typeface' }] },
  { id: 'theme', label: 'Appearance', summary: 'Dark', settings: [{ name: 'Code', words: 'syntax' }] },
  { id: 'animations', label: 'Animations', settings: [{ name: 'Smoke at the edges' }, { name: 'Ghostly typing' }] },
  { id: 'developer', label: 'Developer', settings: [{ name: 'Smoke bench' }] },
  { id: 'recording', label: 'Recording', settings: [{ name: 'Commands start with “hey Ghost”' }, { name: "Use Ghost.md's guess" }] },
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
    expect(found('FONT')).toEqual(['type', 'type/Family']);
  });

  it('finds a setting inside a section, each on its own page', () => {
    expect(found('smoke')).toEqual(['animations/Smoke at the edges', 'developer/Smoke bench']);
    expect(found('syntax')).toEqual(['theme/Code']);
  });

  it('needs every word, in any order, each at the start of a word', () => {
    expect(found('edges smo')).toEqual(['animations/Smoke at the edges']);
    expect(found('moke')).toEqual([]);
    expect(found('smoke bench edges')).toEqual([]);
  });

  it("doesn't list the settings of a section its name already found", () => {
    expect(found('anim')).toEqual(['animations']);
  });

  it('reads curly quotes and apostrophes as straight ones', () => {
    expect(found('"hey')).toEqual(['recording/Commands start with “hey Ghost”']);
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
      <div class="setk-row"><span class="setk-row__label">Commands start with “hey Ghost”</span></div>`;
    expect(findSetting(page, 'Code')?.className).toBe('setk__title');
    expect(findSetting(page, 'commands start with "hey ghost"')?.textContent).toBe('Commands start with “hey Ghost”');
    expect(findSetting(page, 'Code colours')).toBeNull();
  });
});
