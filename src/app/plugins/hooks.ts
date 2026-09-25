import { useEffect, useState, useSyncExternalStore } from 'react';
import { onPluginStorage } from './host.ts';
import { plugins, type NoteLinked } from './registry.ts';
import type { GlyphPlugin } from './types.ts';

/**
 * The registry (registry.ts) as React reads it: which plugins there are and which are on, and what a note is linked
 * to. Apart from the registry so that it stays plain code - the recorder, the formatter and a reset ask it outside any
 * component - and so what re-renders a screen is said in one place.
 */

/** The plugins and which are on, kept current. */
export function usePlugins(): { all: readonly GlyphPlugin[]; enabled: readonly GlyphPlugin[]; setEnabled: (id: string, on: boolean) => void } {
  const enabled = useSyncExternalStore(plugins.subscribe, plugins.enabled, plugins.enabled);
  return { all: plugins.all(), enabled, setEnabled: plugins.setEnabled };
}

/**
 * What a note is linked to, kept current: read again when a plugin writes its
 * storage (a board chosen, a repo unlinked) or is switched on or off.
 */
export function useNoteLinks(noteId: string): NoteLinked[] {
  const [links, setLinks] = useState<NoteLinked[]>(() => plugins.linksOf(noteId));
  useEffect(() => {
    const read = () => setLinks(plugins.linksOf(noteId));
    read();
    const offStorage = onPluginStorage(read);
    const offSwitch = plugins.subscribe(read);
    return () => {
      offStorage();
      offSwitch();
    };
  }, [noteId]);
  return links;
}
