import { EyeOff } from '@glacier/icons';
import type { GlyphPlugin } from '../types.ts';
import { manifest } from './manifest.ts';

/**
 * The Spoilers plugin, standard in Glyph, and the smallest plugin there is:
 * one inline formatting and nothing else. Words between two pairs of pipes,
 * `||like this||`, go to smoke in every note (editor/wispFormat.ts): bent,
 * blurred and half-there until the caret is put in them. Matt: "add support
 * for additional formatting characters through plugins and add spoiler as
 * one which gives text an extreme wisp effect when it's between two pipes".
 *
 * Switched off, the pipes are plain text again and nothing is hidden. The
 * press-and-hold menu's Style page offers it beside the app's own marks
 * (editor/ContextMenu.tsx).
 */
export const spoilerPlugin: GlyphPlugin = {
  manifest,
  icon: EyeOff,
  formats: [{ name: 'Spoiler', delimiter: '||', look: { kind: 'wisp' }, cue: 'spoiler', about: 'The words go to smoke until you put the caret in them.' }],
};
