import { CircleQuestionMark, Eraser, Highlighter, Megaphone, MessageSquareDashed, Plus } from '@glacier/icons';
import type { ComponentType } from 'react';
import type { GlyphPlugin, InlineFormat, PluginManifest } from '../types.ts';

/**
 * Six marks of Glyph's own, each a plugin of one inline formatting and
 * nothing else, so any of them can be switched off in Settings > Plugins
 * without touching the rest. Matt, of the six proposed: "i like all of
 * these, add them each". The Spoiler (plugins/spoiler/) is the seventh and
 * came first; these follow its shape through `markPlugin` so a mark is a
 * dozen lines: its id, its words, its delimiter, its look, and the word that
 * says it while recording.
 *
 * The looks are CSS on the words (editor/formatLooks.ts), in ink and paper
 * only: a wash for the highlighter, a quieter face for an aside, a dotted
 * line under a doubt, a solid bar over a redaction (cleared while the caret
 * is in it, so it can still be edited), spaced small caps for a shout, and
 * a line under an addition, the pair of `~~struck~~`.
 */

interface Mark {
  id: string;
  name: string;
  description: string;
  icon: ComponentType<{ size?: number }>;
  format: InlineFormat;
}

function markPlugin({ id, name, description, icon, format }: Mark): GlyphPlugin {
  const manifest: PluginManifest = { id, name, description, version: '1.0.0', author: 'Glyph', standard: true, permissions: [], storage: [] };
  return { manifest, icon, formats: [format] };
}

export const highlightPlugin = markPlugin({
  id: 'highlight',
  name: 'Highlighter',
  description: 'A wash of ink behind words between pairs of equals signs, ==like this==. Say “highlight … end highlight”.',
  icon: Highlighter,
  format: {
    name: 'Highlight',
    delimiter: '==',
    look: { kind: 'style', css: 'background: var(--app-wash); border-radius: 0.2em; box-shadow: 0 0 0 0.12em var(--app-wash);' },
    cue: 'highlight',
    about: 'A wash of ink behind the words, for the line you will want again.',
  },
});

export const asidePlugin = markPlugin({
  id: 'aside',
  name: 'Asides',
  description: 'A quiet note to yourself between pairs of percent signs, %%like this%%: smaller, muted, leaning. Say “aside … end aside”.',
  icon: MessageSquareDashed,
  format: {
    name: 'Aside',
    delimiter: '%%',
    look: { kind: 'style', css: 'font-size: 0.88em; font-style: italic; color: var(--glacier-text-muted);' },
    cue: 'aside',
    about: 'A note to yourself inside the note: smaller, quieter, leaning.',
  },
});

export const unsurePlugin = markPlugin({
  id: 'unsure',
  name: 'Unsure',
  description: 'A dotted line under words between pairs of question marks, ??like this??, for a thing to check later. Say “unsure … end unsure”.',
  icon: CircleQuestionMark,
  format: {
    name: 'Unsure',
    delimiter: '??',
    look: { kind: 'style', css: 'text-decoration: underline dotted; text-decoration-color: var(--glacier-text-subtle); text-underline-offset: 0.22em; text-decoration-thickness: 0.09em;' },
    cue: 'unsure',
    about: 'A dotted line under a fact to check later.',
  },
});

export const redactPlugin = markPlugin({
  id: 'redact',
  name: 'Redact',
  description: 'A solid bar of ink over words between pairs of at signs, @@like this@@, lifted while the caret is in them. Say “redact … end redact”.',
  icon: Eraser,
  format: {
    name: 'Redact',
    delimiter: '@@',
    look: { kind: 'style', css: 'background: var(--glacier-text); color: var(--glacier-text); border-radius: 0.1em; box-shadow: 0 0 0 0.08em var(--glacier-text);', clearAtCaret: true },
    cue: 'redact',
    about: 'A solid bar of ink over the words, lifted while you edit them.',
  },
});

export const shoutPlugin = markPlugin({
  id: 'shout',
  name: 'Shout',
  description: 'Spaced small capitals for words between pairs of carets, ^^like this^^: emphasis that is not bold. Say “shout … end shout”.',
  icon: Megaphone,
  format: {
    name: 'Shout',
    delimiter: '^^',
    look: { kind: 'style', css: 'font-variant-caps: all-small-caps; letter-spacing: 0.09em; font-weight: var(--glacier-font-weight-semibold);' },
    cue: 'shout',
    about: 'Spaced small capitals: emphasis that is not bold.',
  },
});

export const addedPlugin = markPlugin({
  id: 'added',
  name: 'Added',
  description: 'A line under words between pairs of plus signs, ++like this++, the pair of ~~struck~~ for what changed. Say “added … end added”.',
  icon: Plus,
  format: {
    name: 'Added',
    delimiter: '++',
    look: { kind: 'style', css: 'text-decoration: underline; text-underline-offset: 0.18em; text-decoration-thickness: 0.11em;' },
    cue: 'added',
    about: 'A line under what was added, the pair of struck-through for what went.',
  },
});

/** The six, in the order the guide and the Style page show them. */
export const MARK_PLUGINS: readonly GlyphPlugin[] = [highlightPlugin, asidePlugin, unsurePlugin, redactPlugin, shoutPlugin, addedPlugin];
