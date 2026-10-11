import type { SettingsFindable } from '../settings/settingsSearch.ts';
import type { GlyphPlugin } from './types.ts';

/**
 * What Settings' search finds on Plugins (plugins/PluginsPane.tsx): every plugin, on or off, by its name and what it
 * does, since a card is the way to switch on one that is off. A plugin's own page is a sub-page behind its card
 * (docs/DESIGN.md §138) with its own list on its `settings` (plugins/types.ts).
 */
export function findable(all: readonly GlyphPlugin[]): SettingsFindable[] {
  return all.map((plugin) => ({ name: plugin.manifest.name, words: plugin.manifest.description }));
}
