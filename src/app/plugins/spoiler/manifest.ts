import type { PluginManifest } from '../types.ts';

export const manifest: PluginManifest = {
  id: 'spoiler',
  name: 'Spoilers',
  description: 'Hides a secret in smoke. Words between two pairs of pipes, ||like this||, are bent and blurred until you put the caret in them.',
  version: '1.0.0',
  author: 'Glyph',
  standard: true,
  permissions: [],
  storage: [],
};
