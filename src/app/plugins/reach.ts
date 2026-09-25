import type { Permission, PluginManifest } from './types.ts';

/**
 * What a plugin may reach, as Settings says it (PluginsPane.tsx), and the one question about it the registry asks:
 * whether it reaches past the phone, which Local only holds off.
 */

/** Each permission, in the words Settings uses for it (PluginsPane.tsx). */
export const PERMISSION_WORDS: Record<Permission, string> = {
  notes: 'Your notes',
  network: 'The internet',
  ai: 'The model on your phone',
  voice: 'Voice commands',
  native: 'Built-in app commands',
};

/** Whether a plugin reaches outside the phone, and so is held off while Local only is on (plugins/registry.ts). */
export function usesNetwork(manifest: PluginManifest): boolean {
  return manifest.permissions.some((p) => p.kind === 'network');
}

/** What a plugin may reach, in one line: "Your notes · The internet (api.notion.com) · Voice commands". */
export function reachLine(manifest: PluginManifest): string {
  return manifest.permissions
    .map((p) => (p.kind === 'network' && manifest.hosts?.length ? `${PERMISSION_WORDS.network} (${manifest.hosts.join(', ')})` : PERMISSION_WORDS[p.kind]))
    .join(' · ');
}
