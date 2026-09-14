import { createHost } from '../host.ts';
import type { PluginManifest } from '../types.ts';

export const manifest: PluginManifest = {
  id: 'projects',
  name: 'Projects',
  description: 'Links a note to a GitHub repo, read on the phone into a short briefing so names and terms come out right when the note is formatted.',
  version: '1.0.0',
  author: 'Glyph',
  standard: true,
  permissions: [
    { kind: 'network', why: 'Reads the repo’s README, docs and file list from GitHub. Nothing of your notes goes there.' },
    { kind: 'ai', why: 'The model on your phone writes the briefing from what it read.' },
  ],
  hosts: ['api.github.com'],
  storage: ['glyph-github-projects', 'glyph-project-links', 'glyph-github-token'],
};

export const host = createHost(manifest);
