/**
 * Settings' search (Matt: "Add a search bar to the top of the settings sidebar and implement search functionality"):
 * what a few typed words find among the sections, and among the settings inside them.
 *
 * Every word typed has to be found, in any order, each at the start of a word of what it is matched against, so "dark"
 * finds "On the dark page" and "sm ed" finds "Smoke at the edges", but "ark" finds nothing. A section is found by its
 * name, its state line and its own extra words; a setting by its name and its own extra words, and it is shown with its
 * section's name under it, so "smoke" says which of two pages each smoke is on.
 */

/** A setting inside a section, as its page names it: the name has to be the row's or the card's words on that page, so opening it can find it there. */
export interface SettingsFindable {
  name: string;
  /** Other words someone might look for it by: "font" for Family. */
  words?: string;
}

export interface SearchableSection {
  id: string;
  label: string;
  summary?: string;
  words?: string;
  settings?: SettingsFindable[];
}

export interface SettingsHit<S extends SearchableSection> {
  section: S;
  /** The setting found inside it, or none when the section itself was. */
  setting: string | null;
}

/** Lower case, with curly quotes and apostrophes made straight, so what is typed matches what is drawn. */
export function fold(text: string): string {
  return text
    .toLowerCase()
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"');
}

/** The words of a text, split wherever a letter or a digit isn't: "Ghost.md's guess" is ghost, md, s, guess. */
function wordsOf(text: string): string[] {
  return fold(text)
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);
}

/** Whether every typed word starts one of the words of the texts. */
function matches(typed: string[], texts: (string | undefined)[]): boolean {
  const words = texts.flatMap((text) => (text ? wordsOf(text) : []));
  return typed.every((want) => words.some((word) => word.startsWith(want)));
}

/**
 * What the words find, in the list's order: each section found by itself, then each setting found inside it. A section
 * found by its name is not repeated for every setting of its that also matches the words; its settings are shown only
 * when the section's name alone wouldn't have found it.
 */
export function searchSettings<S extends SearchableSection>(sections: S[], query: string): SettingsHit<S>[] {
  const typed = wordsOf(query);
  if (!typed.length) return [];
  const hits: SettingsHit<S>[] = [];
  for (const section of sections) {
    const byName = matches(typed, [section.label]);
    if (byName || matches(typed, [section.label, section.summary, section.words])) hits.push({ section, setting: null });
    if (byName) continue;
    for (const setting of section.settings ?? []) {
      if (matches(typed, [setting.name, setting.words])) hits.push({ section, setting: setting.name });
    }
  }
  return hits;
}

/**
 * The element on a section's page that names a setting: a row's label, a card's title, or the page's hero line. Read
 * from the page as drawn, so a setting that isn't on it just now (signed out, say) opens the page and nothing more.
 */
export function findSetting(page: ParentNode, name: string): HTMLElement | null {
  const want = fold(name).trim();
  const candidates = page.querySelectorAll<HTMLElement>('.setk-row__label, .setk__title, .setk-hero__title');
  for (const candidate of candidates) {
    if (fold(candidate.textContent ?? '').trim() === want) return candidate;
  }
  return null;
}
