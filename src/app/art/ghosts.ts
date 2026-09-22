/** The ghost's pictures, one per scene (Ghost.tsx, docs/GHOSTS.md). */
import noNotes from './ghosts/02-no-notes-yet.webp';
import emptyWorkspace from './ghosts/03-nothing-in-this-workspace.webp';
import newNote from './ghosts/04-a-new-note.webp';
import searchNothing from './ghosts/05-search-found-nothing.webp';
import trashEmpty from './ghosts/06-the-trash-empty.webp';
import archiveEmpty from './ghosts/07-the-archive-empty.webp';
import listening from './ghosts/08-listening.webp';
import working from './ghosts/09-the-model-working.webp';
import emptyCanvas from './ghosts/10-an-empty-canvas.webp';
import allTicked from './ghosts/11-every-to-do-ticked.webp';
import signedOut from './ghosts/12-signed-out-not-syncing.webp';
import wentWrong from './ghosts/13-something-went-wrong.webp';
import welcome from './ghosts/14-welcome-first-run.webp';
import update from './ghosts/15-an-update-is-ready.webp';

export type GhostScene =
  | 'no-notes'
  | 'empty-workspace'
  | 'new-note'
  | 'search-nothing'
  | 'trash-empty'
  | 'archive-empty'
  | 'listening'
  | 'working'
  | 'empty-canvas'
  | 'all-ticked'
  | 'signed-out'
  | 'went-wrong'
  | 'welcome'
  | 'update';

/** Each scene's picture: the file names keep the scene's number in docs/GHOSTS.md. */
export const GHOSTS: Record<GhostScene, string> = {
  'no-notes': noNotes,
  'empty-workspace': emptyWorkspace,
  'new-note': newNote,
  'search-nothing': searchNothing,
  'trash-empty': trashEmpty,
  'archive-empty': archiveEmpty,
  listening,
  working,
  'empty-canvas': emptyCanvas,
  'all-ticked': allTicked,
  'signed-out': signedOut,
  'went-wrong': wentWrong,
  welcome,
  update,
};
