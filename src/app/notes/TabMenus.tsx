import { Menu, MenuItem, MenuSeparator, MenuSub } from '@glacier/react';
import { capitalise } from '../core/text.ts';
import { WORKSPACE_HUES } from '../core/workspaces.ts';
import { joinGroup, leaveGroup, membersOf, recolourGroup, ungroup, type TabGroup, type TabGroups } from './tabGroups.ts';
import styles from './NoteTabs.module.css';

/**
 * The two menus of the tab row (notes/NoteTabs.tsx): a tab's, and a group chip's. A mouse opens either with a
 * right-click; a finger opens a tab's by holding it and letting go where it was (notes/useTabDrag.ts), and a chip's by
 * a long press, since a chip is never dragged. Each hangs from an anchor in its tab or chip and says what it is for,
 * so a screen reader hears "Groceries tab" rather than a bare list of verbs.
 *
 * Drawn from the row's own stylesheet: the anchor and the hue dots are the row's, and a menu of its own would be one
 * more place for them to drift.
 */

/** What a tab's menu does: rename a canvas or a book, group it, take it out of its group, close it. */
export function TabMenu({
  noteId,
  title,
  groups,
  onDismiss,
  onRename,
  onNewGroup,
  onGroups,
  onCloseTab,
}: {
  noteId: string;
  title: string;
  groups: TabGroups;
  onDismiss: () => void;
  /** Only a canvas or a book is renamed from its tab: a note is named by its first line, written in the note itself. */
  onRename?: () => void;
  onNewGroup: () => void;
  onGroups: (next: TabGroups) => void;
  onCloseTab: () => void;
}) {
  const groupId = groups.of[noteId];
  const others = groups.list.filter((g) => g.id !== groupId);
  return (
    <Menu open onOpenChange={(open) => !open && onDismiss()} trigger={<span className={styles.menuAnchor} />} placement="bottom-start" aria-label={`${title} tab`}>
      {onRename ? <MenuItem onSelect={onRename}>Rename</MenuItem> : null}
      <MenuItem onSelect={onNewGroup}>Add to a new group</MenuItem>
      {others.length ? (
        <MenuSub label="Add to group">
          {others.map((g) => (
            <MenuItem key={g.id} onSelect={() => onGroups(joinGroup(groups, noteId, g.id))} icon={<span className={styles.hueDot} data-hue={g.hue} aria-hidden="true" />}>
              {g.name}
            </MenuItem>
          ))}
        </MenuSub>
      ) : null}
      {groupId ? <MenuItem onSelect={() => onGroups(leaveGroup(groups, noteId))}>Remove from group</MenuItem> : null}
      <MenuSeparator />
      <MenuItem onSelect={onCloseTab}>Close tab</MenuItem>
    </Menu>
  );
}

/** What a group's menu does: rename it, colour it, ungroup its tabs, or close them all. */
export function GroupMenu({
  group,
  groups,
  tabIds,
  onDismiss,
  onRename,
  onGroups,
  onCloseTabs,
}: {
  group: TabGroup;
  groups: TabGroups;
  /** The tabs in the row, in the order drawn: the group's own are closed in that order. */
  tabIds: readonly string[];
  onDismiss: () => void;
  onRename: () => void;
  onGroups: (next: TabGroups) => void;
  onCloseTabs?: (ids: string[]) => void;
}) {
  return (
    <Menu open onOpenChange={(open) => !open && onDismiss()} trigger={<span className={styles.menuAnchor} />} placement="bottom-start" aria-label={`${group.name} group`}>
      <MenuItem onSelect={onRename}>Rename</MenuItem>
      <MenuSub label="Colour">
        {WORKSPACE_HUES.map((hue) => (
          <MenuItem key={hue} onSelect={() => onGroups(recolourGroup(groups, group.id, hue))} icon={<span className={styles.hueDot} data-hue={hue} aria-hidden="true" />}>
            {capitalise(hue)}
          </MenuItem>
        ))}
      </MenuSub>
      <MenuSeparator />
      <MenuItem onSelect={() => onGroups(ungroup(groups, group.id))}>Ungroup</MenuItem>
      <MenuItem danger onSelect={() => onCloseTabs?.(membersOf(groups, group.id, tabIds))}>
        Close group
      </MenuItem>
    </Menu>
  );
}
