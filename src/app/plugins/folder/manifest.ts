import { createHost } from '../host.ts';
import type { PluginManifest } from '../types.ts';

/** The binary with `library_root`, the folder panel and picker, the move and the way back (src-tauri/src/ota.rs). */
export const FOLDER_GENERATION = 25;

/**
 * The Library folder plugin's manifest. Not standard: a person who never wants the notes anywhere but Ghost.md's own
 * folder never sees it, and switching it off changes nothing about where they are, only hides the page.
 *
 * Its id has a hyphen on purpose: every plugin's id is also a name its item marks may carry (core/itemLinks.ts), and
 * `[folder](…)` at the end of a list item is a link a person could well write.
 */
export const manifest: PluginManifest = {
  id: 'library-folder',
  name: 'Library folder',
  description: 'Keeps your notes in a folder of yours: an Obsidian vault, a folder in iCloud Drive or Dropbox, one Syncthing keeps, a backup drive. They are Markdown files already, so other apps read them as they are.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: false,
  permissions: [
    { kind: 'notes', why: 'Moves your notes into the folder you choose, and back, and reads the Markdown files already in it as notes.' },
    { kind: 'native', why: 'Opens the system’s own folder panel or picker, which is the only way a folder is ever chosen, and moves the library in the app itself.' },
  ],
  native: { generation: FOLDER_GENERATION, commands: ['library_root', 'library_choose_folder', 'library_inspect', 'library_move', 'library_use_app_folder'] },
  storage: [],
};

export const host = createHost(manifest);
