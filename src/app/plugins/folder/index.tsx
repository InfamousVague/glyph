import { Folder } from '@glacier/icons';
import type { GlyphPlugin } from '../types.ts';
import { FolderPane } from './FolderPane.tsx';
import { manifest } from './manifest.ts';

/**
 * The Library folder plugin: the notes in a folder the person chooses (docs/DESIGN.md §185, docs/LIBRARY.md "Choosing
 * the folder"). Matt: "include #6 as a plugin". Built in and off until switched on, since most people never move their
 * notes; what it is here is its page (FolderPane.tsx), and the move itself is the app's (src-tauri/src/
 * library_commands.rs). Switching it off hides the page and leaves the notes wherever they are.
 */
export const libraryFolderPlugin: GlyphPlugin = {
  manifest,
  icon: Folder,
  settings: {
    Pane: FolderPane,
    summary: () => 'Where your notes are kept',
    // What Settings' search finds on the page (docs/DESIGN.md §138): its cards, by their titles.
    settings: [
      { name: 'Where your notes are', words: 'library folder choose move obsidian vault icloud dropbox syncthing backup drive' },
      { name: 'Good to know', words: 'sync google drive index pictures recordings' },
    ],
  },
};
