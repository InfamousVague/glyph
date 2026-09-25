import { useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react';
import { onPreferences, preferences, setPreferences } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { addOpen, afterClose, closeOpen, moveOpen, openOnly, swapOpen } from '../notes/openTabs.ts';
import { afterMove, displayOrder, pruneGroups, sameGroups, type TabGroups } from '../notes/tabGroups.ts';

/**
 * The notes a person has open, as tabs (notes/openTabs.ts), and the groups over them (notes/tabGroups.ts): the React
 * half of both, held once for the whole app.
 *
 * Every way into a note ends in the Shell showing it, so the row is kept here rather than at each of them: a note
 * shown is a note open. The row survives a reload, and arrives on another device (Matt: "Persist tabs across devices
 * and reloads"): the ids are a synced preference (core/preferences.ts `openNotes`, core/sync/prefs.ts). Only the row
 * is kept, never which tab was in front - the app opens on the home page as it always has, so tabs whose notes have
 * not synced yet simply are not drawn rather than opening a note this device cannot show.
 *
 * Tab groups are Chrome-style, named and coloured runs of tabs (Matt chose "Chrome-style groups"), and a synced
 * preference like the row, so a group made on the Mac is there on the phone; read again when another device changes
 * them. A group's tabs are drawn together, so the tabs are handed on in that order.
 *
 * Two things here have bitten, and each says so where it is done: which tab a note opened from inside a book takes
 * (`replaceNext`), and what a closed tab's group is measured against (the prune).
 */

export interface OpenTabs {
  /** The row as kept, in the order opened: ids whose notes have not loaded, or have gone, included. */
  open: readonly string[];
  /** The open notes that exist, in the order drawn: each group's tabs together. */
  tabs: Note[];
  /** `tabs`' ids: the order a drag or a key moves a tab within. */
  drawnIds: readonly string[];
  groups: TabGroups;
  setGroups: Dispatch<SetStateAction<TabGroups>>;
  /**
   * Closes `id`'s tab. Answers where to go when it was the tab being read - the tab after it, else the one before,
   * or null for the home page - and undefined when it was not, and nothing needs to move.
   */
  close: (id: string) => string | null | undefined;
  /** Takes `id` out of the row without asking where to go: its note is being deleted or archived, and the Shell goes home. */
  drop: (id: string) => void;
  /**
   * `id` moved to sit at `to` among the tabs as drawn. A drag has already said which group it is in (`grouped`); a
   * move by the keys asks where it landed - into a group, or out of one.
   */
  move: (id: string, to: number, grouped?: boolean) => void;
  /**
   * The next note shown takes `id`'s tab rather than one of its own; null, it takes one of its own. Read once, by the
   * note being shown, and every other way of opening a note says null first.
   */
  replaceNext: (id: string | null) => void;
}

/**
 * `shown` is the note on screen, or null; `notes` the library as loaded, and `live` the ids among them the person can
 * still see (not deleted, not in the trash), which are the only tabs drawn.
 */
export function useOpenTabs(shown: string | null, notes: readonly Note[], live: ReadonlySet<string>): OpenTabs {
  /*
   * A note opened from inside a book - the index, the chapter bar, the aside, the read-through - takes the current
   * tab's place rather than a tab of its own (notes/openTabs.ts `swapOpen`; Matt: "the book should open in one tab
   * instead of each page opening in a new tab"). The tab to give up is noted here and read once by the effect that
   * turns a shown note into a tab.
   */
  const swap = useRef<string | null>(null);
  const [open, setOpen] = useState<string[]>(() => preferences().openNotes);
  useEffect(() => {
    if (open.join('\u0000') !== preferences().openNotes.join('\u0000')) setPreferences({ openNotes: open });
  }, [open]);
  useEffect(() => {
    if (!shown) return;
    const from = swap.current;
    swap.current = null;
    setOpen((was) => (from ? swapOpen(was, from, shown) : addOpen(was, shown)));
  }, [shown]);
  // A note deleted, or put in the trash, here or on another device leaves no tab behind.
  const openIds = useMemo(() => openOnly(open, live), [open, live]);

  const [groups, setGroups] = useState<TabGroups>(() => preferences().tabGroups);
  useEffect(
    () =>
      onPreferences(() => {
        const theirs = preferences().tabGroups;
        setGroups((ours) => (sameGroups(ours, theirs) ? ours : theirs));
      }),
    [],
  );
  useEffect(() => {
    if (!sameGroups(groups, preferences().tabGroups)) setPreferences({ tabGroups: groups });
  }, [groups]);
  /*
   * A closed tab leaves its group, and a group left with nothing in it goes. Measured against `open` - the tabs as
   * stored - not the tabs whose notes have loaded: on the first render no note has loaded yet, so that list is empty,
   * and pruning against it emptied every group and saved the empty result, which lost the groups on every start.
   */
  useEffect(() => {
    setGroups((was) => {
      const next = pruneGroups(was, open);
      return sameGroups(next, was) ? was : next;
    });
  }, [open]);
  const drawnIds = useMemo(() => displayOrder(openIds, groups), [openIds, groups]);
  const tabs = useMemo(() => drawnIds.map((id) => notes.find((n) => n.id === id)!), [drawnIds, notes]);

  return {
    open,
    tabs,
    drawnIds,
    groups,
    setGroups,
    close: (id) => {
      const next = id === shown ? afterClose(openIds, id) : undefined;
      setOpen((was) => closeOpen(was, id));
      return next;
    },
    drop: (id) => setOpen((was) => closeOpen(was, id)),
    move: (id, to, grouped) => {
      const next = moveOpen(open, drawnIds, id, to);
      setOpen(next);
      if (!grouped) setGroups((was) => afterMove(was, next.filter((each) => drawnIds.includes(each)), id));
    },
    replaceNext: (id) => {
      swap.current = id;
    },
  };
}
