import type { SettingsFindable } from './settingsSearch.ts';

/** What Settings' search finds on Export (settings/ExportCard.tsx; docs/DESIGN.md §167, a section since §205). */
export function findable(): SettingsFindable[] {
  return [{ name: 'Export everything', words: 'backup back up usb drive stick zip archive copy save all notes' }];
}
