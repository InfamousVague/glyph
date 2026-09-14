import { useSyncExternalStore } from 'react';
import { notionPlugin } from './notion/index.tsx';
import { projectsPlugin } from './projects/index.tsx';
import { PluginPermissionError } from './host.ts';
import type { GlyphPlugin, ItemAction, ItemTarget, NoteAction, NoteLink, Permission, Tip, VoiceCommand } from './types.ts';

/**
 * The plugins in this build, which are switched on, and everything they offer.
 *
 * The app asks here and never names a plugin: the note's cog asks for
 * `noteLinks()`, the recorder for `voiceCommands()`, the formatter for
 * `contextFor(noteId)`, Settings for `usePlugins()`. A switched-off plugin
 * offers nothing anywhere, at once; its data stays where it was, so switching
 * it on again brings it back as it was.
 *
 * Switches are `glyph-plugins` in localStorage (id to on/off), and a plugin
 * with no switch yet is on if it is standard.
 */

const SWITCHES_KEY = 'glyph-plugins';

export interface Registry {
  all(): readonly GlyphPlugin[];
  enabled(): readonly GlyphPlugin[];
  isEnabled(id: string): boolean;
  setEnabled(id: string, on: boolean): void;
  subscribe(listener: () => void): () => void;
  noteLinks(): NoteLink[];
  noteActions(): NoteAction[];
  itemAction(noteId: string): ItemAction | null;
  voiceCommands(): VoiceCommand[];
  itemTargets(): ItemTarget[];
  tips(recentTitle: string | null): Tip[];
  contextFor(noteId: string): string | null;
  contextVersion(noteId: string): number;
  /** Every key any plugin owns, switched on or not, for a reset. */
  storageKeys(): string[];
}

interface SwitchStore {
  read(): Record<string, boolean>;
  write(switches: Record<string, boolean>): void;
}

const localSwitches: SwitchStore = {
  read() {
    try {
      const parsed: unknown = JSON.parse(localStorage.getItem(SWITCHES_KEY) ?? '{}');
      return parsed && typeof parsed === 'object' ? (parsed as Record<string, boolean>) : {};
    } catch {
      return {};
    }
  },
  write(switches) {
    try {
      localStorage.setItem(SWITCHES_KEY, JSON.stringify(switches));
    } catch {
      // Without storage a switch lasts as long as the page.
    }
  },
};

/**
 * The extension points a plugin uses must match what its manifest asks for:
 * commands heard while recording need `voice`, and anything that changes a
 * note (an action, the swipe, items sent on from a voice command) needs
 * `notes`. Checked when the registry is made, so a plugin that overreaches
 * never loads.
 */
function checkExtensions(plugin: GlyphPlugin): void {
  const has = (kind: Permission) => plugin.manifest.permissions.some((p) => p.kind === kind);
  if ((plugin.voice?.length || plugin.itemTargets?.length) && !has('voice')) throw new PluginPermissionError(plugin.manifest, 'the “voice” permission its commands need');
  if ((plugin.noteActions?.length || plugin.itemAction || plugin.itemTargets?.length) && !has('notes')) {
    throw new PluginPermissionError(plugin.manifest, 'the “notes” permission its note actions need');
  }
}

export function createRegistry(plugins: readonly GlyphPlugin[], store: SwitchStore = localSwitches): Registry {
  const ids = new Set<string>();
  for (const plugin of plugins) {
    if (ids.has(plugin.manifest.id)) throw new Error(`Two plugins are called “${plugin.manifest.id}”.`);
    ids.add(plugin.manifest.id);
    checkExtensions(plugin);
  }
  const listeners = new Set<() => void>();
  let switches = store.read();
  // A stable array between changes, so useSyncExternalStore sees no change when there is none.
  let enabledCache: readonly GlyphPlugin[] | null = null;

  const isEnabled = (id: string) => {
    const plugin = plugins.find((p) => p.manifest.id === id);
    if (!plugin) return false;
    return switches[id] ?? plugin.manifest.standard;
  };
  const enabled = () => (enabledCache ??= plugins.filter((p) => isEnabled(p.manifest.id)));

  return {
    all: () => plugins,
    enabled,
    isEnabled,
    setEnabled(id, on) {
      if (!ids.has(id) || isEnabled(id) === on) return;
      switches = { ...switches, [id]: on };
      store.write(switches);
      enabledCache = null;
      listeners.forEach((listener) => listener());
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    noteLinks: () => enabled().flatMap((p) => p.noteLinks ?? []),
    noteActions: () => enabled().flatMap((p) => p.noteActions ?? []),
    itemAction: (noteId) => enabled().map((p) => p.itemAction).find((action) => action?.available(noteId)) ?? null,
    voiceCommands: () => enabled().flatMap((p) => p.voice ?? []),
    itemTargets: () => enabled().flatMap((p) => p.itemTargets ?? []),
    tips: (recentTitle) => enabled().flatMap((p) => p.tips?.(recentTitle) ?? []),
    contextFor(noteId) {
      const parts = enabled()
        .map((p) => p.formatContext?.for(noteId) ?? null)
        .filter((part): part is string => Boolean(part?.trim()));
      return parts.length ? parts.join('\n\n') : null;
    },
    contextVersion(noteId) {
      // One context gives its own version, so a note formatted before plugins
      // existed (with its project's version) is not formatted again for it.
      const versions = enabled()
        .map((p) => p.formatContext?.version(noteId) ?? 0)
        .filter((version) => version !== 0);
      if (versions.length <= 1) return versions[0] ?? 0;
      return versions.reduce((sum, version) => (sum * 31 + version) % 2 ** 52, 7);
    },
    storageKeys: () => [SWITCHES_KEY, ...plugins.flatMap((p) => p.manifest.storage)],
  };
}

/** The plugins that ship with Glyph. */
export const BUILT_IN: readonly GlyphPlugin[] = [notionPlugin, projectsPlugin];

export const plugins = createRegistry(BUILT_IN);

/** The plugins and which are on, kept current. */
export function usePlugins(): { all: readonly GlyphPlugin[]; enabled: readonly GlyphPlugin[]; setEnabled: (id: string, on: boolean) => void } {
  const enabled = useSyncExternalStore(plugins.subscribe, plugins.enabled, plugins.enabled);
  return { all: plugins.all(), enabled, setEnabled: plugins.setEnabled };
}

/** The formatter's context for a note, from every plugin that gives one (format/pipeline.ts). */
export const pluginContextFor = (noteId: string) => plugins.contextFor(noteId);
export const pluginContextVersion = (noteId: string) => plugins.contextVersion(noteId);

