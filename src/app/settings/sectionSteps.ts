/**
 * Where Settings goes, as pure answers (settings/SettingsScreen.tsx draws them): which sections are rows on the list,
 * which cards they cluster into, where back steps from a page, what a left swipe re-enters, and the word the head
 * says for the way back.
 *
 * Two depths since the sections were streamlined (docs/DESIGN.md §138; Matt: "also see if you can clean up /
 * streamline settings a bit"). A pane is a row on the list. A sub-page (`listed: false`, with a `parent`) is not: it
 * is opened from a row on its parent's page, Notion from its Plugins card and the cheat sheet from About's Help, and
 * it is still searched. Back steps a sub-page to its parent, a pane to the list, and the list closes Settings.
 */

/** What these answers read of a section: SettingsScreen's `SettingsSection` is one. */
export interface SectionPlace {
  id: string;
  label: string;
  group: number;
  /** False keeps it off the list: a sub-page, opened from its parent's page or from the search. */
  listed?: boolean;
  /** The section a sub-page steps back to, and the row that is current in the split view while it shows. */
  parent?: string;
}

/** The sections that are rows on the list, in their order. */
export function listedOf<S extends SectionPlace>(sections: readonly S[]): S[] {
  return sections.filter((section) => section.listed !== false);
}

/** The listed sections clustered into cards: consecutive rows of one group share a card. */
export function clustersOf<S extends SectionPlace>(sections: readonly S[]): S[][] {
  return listedOf(sections).reduce<S[][]>((groups, section) => {
    const last = groups[groups.length - 1];
    if (last && last[0]!.group === section.group) last.push(section);
    else groups.push([section]);
    return groups;
  }, []);
}

/** A sub-page's parent, when it has one that is among the sections. */
function parentOf<S extends SectionPlace>(sections: readonly S[], section: S | undefined): S | undefined {
  return section?.parent ? sections.find((s) => s.id === section.parent) : undefined;
}

/**
 * Where back goes from `activeId`: the id of the page to show, null for the list, or 'close' to leave Settings. A
 * sub-page steps to its parent; a pane, or a sub-page whose parent is not there, to the list; the list closes.
 */
export function stepBack<S extends SectionPlace>(sections: readonly S[], activeId: string | null): string | null | 'close' {
  if (activeId === null) return 'close';
  const active = sections.find((s) => s.id === activeId);
  return parentOf(sections, active)?.id ?? null;
}

/**
 * What a left swipe re-enters: the page back just left, when it is still a section and the swipe is made from where
 * back landed (its parent, or the list for a pane). Anything else stays put.
 */
export function stepForward<S extends SectionPlace>(sections: readonly S[], activeId: string | null, left: string | null): string | null {
  if (!left) return null;
  const leftSection = sections.find((s) => s.id === left);
  if (!leftSection) return null;
  const from = parentOf(sections, leftSection)?.id ?? null;
  return from === activeId ? left : null;
}

/** The word in the head over a page, for where back goes: the parent's name over a sub-page, else "Settings". */
export function backWord<S extends SectionPlace>(sections: readonly S[], active: S | null): string {
  return parentOf(sections, active ?? undefined)?.label ?? 'Settings';
}

/** The row that is current in the split view's column while `shown` is on the right: its parent's for a sub-page. */
export function currentRow<S extends SectionPlace>(sections: readonly S[], shown: S | null): string | null {
  if (!shown) return null;
  return parentOf(sections, shown)?.id ?? shown.id;
}
