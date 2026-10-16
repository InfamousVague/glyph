/**
 * The names the popup shares with the page's side and the saving, in a module that imports nothing, so the popup's
 * script does not carry Readability and Turndown to show five buttons.
 */

export type ClipMode = 'article' | 'selection' | 'page' | 'bookmark' | 'screenshot';

export const MODES: readonly ClipMode[] = ['article', 'selection', 'page', 'bookmark', 'screenshot'];

/** The address a picture is written with until it is stored or linked (core/pictures.ts `placePictures`). */
export const PICTURE_SCHEME = 'ghost-clip:picture/';

/** The most pictures one clip stores; the rest are linked. */
export const MOST_PICTURES = 60;
