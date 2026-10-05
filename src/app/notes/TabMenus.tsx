import { MenuItem, MenuSeparator } from '@glacier/react';
import { useRef } from 'react';
import { capitalise } from '../core/text.ts';
import { WORKSPACE_HUES } from '../core/workspaces.ts';
import { PopMenu, PopSub } from '../editor/PopMenu.tsx';
import { joinGroup, leaveGroup, membersOf, recolourGroup, ungroup, type TabGroup, type TabGroups } from './tabGroups.ts';
import styles from './NoteTabs.module.css';
import menu from './NoteMenu.module.css';

/**
 * The two menus of the tab row (notes/NoteTabs.tsx): a tab's, and a group chip's. A mouse opens either with a
 * right-click; a finger opens a tab's by holding it and letting go where it was (notes/useTabDrag.ts), and a chip's by
 * a long press, since a chip is never dragged. Each hangs from an anchor in its tab or chip and says what it is for,
 * so a screen reader hears "Groceries tab" rather than a bare list of verbs.
 *
 * Both are the kit's menu through editor/PopMenu.tsx, hanging down from the bar (Matt: "Allow the header to be
 * overlapped by the popup menus use the glacierUI context menus"), which gives them what the kit's alone did not: the
 * back gesture closes one, where a back swipe used to go to the screen under it; a press anywhere closes one; under a
 * finger the rows are a thumb's height; and none runs taller than the room under the bar. The rows under a name (Add to
 * group, Colour) are listed in place under it, each with its whole name, except for a mouse on a window wide enough
 * for a flyout either side of the menu: the kit's flyout ran off a phone's edge.
 *
 * Drawn from the row's own stylesheet: the anchor and the hue dots are the row's, and a menu of its own would be one
 * more place for them to drift.
 */

/** What a tab's menu does: rename a canvas or a book, group it, take it out of its group, close it, delete its note. */
export function TabMenu({
  noteId,
  title,
  groups,
  onDismiss,
  onRename,
  onNewGroup,
  onGroups,
  onCloseTab,
  onDeleteNote,
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
  /** The tab's note to the Trash, with an Undo; absent, the menu has no Delete. */
  onDeleteNote?: () => void;
}) {
  const anchor = useRef<HTMLSpanElement>(null);
  const groupId = groups.of[noteId];
  const others = groups.list.filter((g) => g.id !== groupId);
  return (
    <>
      <span ref={anchor} className={styles.menuAnchor} />
      <PopMenu anchor={anchor} placement="bottom-start" reach="down" aria-label={`${title} tab`} onDismiss={onDismiss}>
        {onRename ? <MenuItem onSelect={onRename}>Rename</MenuItem> : null}
        <MenuItem onSelect={onNewGroup}>Add to a new group</MenuItem>
        {others.length ? (
          <PopSub label="Add to group" reach="down">
            {others.map((g) => (
              <MenuItem
                key={g.id}
                aria-label={`Add to ${g.name}`}
                onSelect={() => onGroups(joinGroup(groups, noteId, g.id))}
                icon={<span className={styles.hueDot} data-hue={g.hue} aria-hidden="true" />}
              >
                {g.name}
              </MenuItem>
            ))}
          </PopSub>
        ) : null}
        {groupId ? <MenuItem onSelect={() => onGroups(leaveGroup(groups, noteId))}>Remove from group</MenuItem> : null}
        <MenuSeparator />
        <MenuItem onSelect={onCloseTab}>Close tab</MenuItem>
        {onDeleteNote ? (
          <MenuItem danger className={menu.danger} onSelect={onDeleteNote}>
            Delete note
          </MenuItem>
        ) : null}
      </PopMenu>
    </>
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
  const anchor = useRef<HTMLSpanElement>(null);
  return (
    <>
      <span ref={anchor} className={styles.menuAnchor} />
      <PopMenu anchor={anchor} placement="bottom-start" reach="down" aria-label={`${group.name} group`} onDismiss={onDismiss}>
        <MenuItem onSelect={onRename}>Rename</MenuItem>
        <PopSub label="Colour" reach="down">
          {WORKSPACE_HUES.map((hue) => (
            <MenuItem
              key={hue}
              aria-label={`Colour: ${capitalise(hue)}`}
              onSelect={() => onGroups(recolourGroup(groups, group.id, hue))}
              icon={<span className={styles.hueDot} data-hue={hue} aria-hidden="true" />}
            >
              {capitalise(hue)}
            </MenuItem>
          ))}
        </PopSub>
        <MenuSeparator />
        <MenuItem onSelect={() => onGroups(ungroup(groups, group.id))}>Ungroup</MenuItem>
        <MenuItem danger onSelect={() => onCloseTabs?.(membersOf(groups, group.id, tabIds))}>
          Close group
        </MenuItem>
      </PopMenu>
    </>
  );
}
