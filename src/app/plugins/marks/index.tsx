import { CircleQuestionMark, Eraser, EyeOff, Highlighter, Megaphone, MessageSquareDashed, Plus } from '@glacier/icons';
import type { GlyphPlugin, InlineFormat, PluginManifest } from '../types.ts';

/**
 * Marks: the formatting Glyph adds to Markdown, all of it in one plugin
 * (Matt: "move all the additional formatting to one single plugin instead of
 * one of each like shout redact unsure etc"). Seven marks, one switch in
 * Settings > Plugins, and each carries its own icon for the Style page
 * (editor/ContextMenu.tsx) and its own words for the guide's table
 * (guide/marks.ts).
 *
 * A mark is its delimiter and its look (plugins/types.ts `InlineFormat`): the
 * spoiler goes to smoke (editor/wispFormat.ts), the rest are CSS on the words
 * (editor/formatLooks.ts), in ink and paper only. Each is said as well as
 * typed: "highlight … end highlight" while recording (capture/markdown.ts).
 * Switched off, every one of them is plain text again.
 */

export const manifest: PluginManifest = {
  id: 'marks',
  name: 'Marks',
  description: 'Glyph’s own formatting on top of Markdown: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout and an addition. Typed or said.',
  version: '1.0.0',
  author: 'Glyph',
  standard: true,
  permissions: [],
  storage: [],
};

/** The marks, in the order the Style page and the guide show them. */
export const MARKS: readonly InlineFormat[] = [
  {
    name: 'Spoiler',
    delimiter: '||',
    look: { kind: 'wisp' },
    cue: 'spoiler',
    about: 'The words go to smoke until you put the caret in them.',
    icon: EyeOff,
  },
  {
    name: 'Highlight',
    delimiter: '==',
    look: { kind: 'style', css: 'background: var(--app-wash); border-radius: 0.2em; box-shadow: 0 0 0 0.12em var(--app-wash);' },
    cue: 'highlight',
    about: 'A wash of ink behind the words, for the line you will want again.',
    icon: Highlighter,
  },
  {
    name: 'Aside',
    delimiter: '%%',
    look: { kind: 'style', css: 'font-size: 0.88em; font-style: italic; color: var(--glacier-text-muted);' },
    cue: 'aside',
    about: 'A note to yourself inside the note: smaller, quieter, leaning.',
    icon: MessageSquareDashed,
  },
  {
    name: 'Unsure',
    delimiter: '??',
    look: { kind: 'style', css: 'text-decoration: underline dotted; text-decoration-color: var(--glacier-text-subtle); text-underline-offset: 0.22em; text-decoration-thickness: 0.09em;' },
    cue: 'unsure',
    about: 'A dotted line under a fact to check later.',
    icon: CircleQuestionMark,
  },
  {
    name: 'Redact',
    delimiter: '@@',
    look: { kind: 'style', css: 'background: var(--glacier-text); color: var(--glacier-text); border-radius: 0.1em; box-shadow: 0 0 0 0.08em var(--glacier-text);', clearAtCaret: true },
    cue: 'redact',
    about: 'A solid bar of ink over the words, lifted while you edit them.',
    icon: Eraser,
  },
  {
    name: 'Shout',
    delimiter: '^^',
    look: { kind: 'style', css: 'font-variant-caps: all-small-caps; letter-spacing: 0.09em; font-weight: var(--glacier-font-weight-semibold);' },
    cue: 'shout',
    about: 'Spaced small capitals: emphasis that is not bold.',
    icon: Megaphone,
  },
  {
    name: 'Added',
    delimiter: '++',
    look: { kind: 'style', css: 'text-decoration: underline; text-underline-offset: 0.18em; text-decoration-thickness: 0.11em;' },
    cue: 'added',
    about: 'A line under what was added, the pair of struck-through for what went.',
    icon: Plus,
  },
];

export const marksPlugin: GlyphPlugin = {
  manifest,
  icon: Highlighter,
  formats: MARKS,
};
