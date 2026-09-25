import { useEffect, useState, type ReactNode } from 'react';
import type { TabGroup } from './tabGroups.ts';
import styles from './NoteTabs.module.css';

/**
 * A group's chip, before its first tab in the row (notes/NoteTabs.tsx): its name in its colour, as Chrome draws one. A
 * tap folds the group to the chip and opens it again; a right-click or a long press opens its menu (rename, colour,
 * ungroup, close; notes/TabMenus.tsx). Folded, it stands for every tab it holds. It is not a tab - no `data-tab` - so
 * the drag and the hold pass it by (notes/useTabDrag.ts), though a folded one is counted as its tabs.
 */
export function GroupChip({
  group,
  count,
  renaming,
  onToggle,
  onMenu,
  onRename,
  menu,
}: {
  group: TabGroup;
  count: number;
  /** Its name is open as a field: a group just made, or Rename chosen from its menu. */
  renaming: boolean;
  onToggle: () => void;
  onMenu: () => void;
  /** The name it is left with, however the field closes: Enter and a blur keep the words, Escape the name it had. */
  onRename: (name: string) => void;
  /** Its menu, while it is open. */
  menu: ReactNode;
}) {
  const [draft, setDraft] = useState(group.name);
  useEffect(() => {
    if (renaming) setDraft(group.name);
  }, [renaming, group.name]);
  return (
    <span className={styles.group} data-hue={group.hue} data-group-chip={group.id} data-collapsed={group.collapsed || undefined} data-count={count}>
      {renaming ? (
        <input
          className={styles.groupName}
          value={draft}
          aria-label="Group name"
          autoFocus
          onFocus={(event) => event.currentTarget.select()}
          onChange={(event) => setDraft(event.currentTarget.value)}
          onBlur={() => onRename(draft)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') onRename(draft);
            else if (event.key === 'Escape') onRename(group.name);
          }}
        />
      ) : (
        <button
          type="button"
          className={styles.groupChip}
          aria-expanded={!group.collapsed}
          aria-label={`${group.name}, ${count} ${count === 1 ? 'tab' : 'tabs'}${group.collapsed ? ', folded' : ''}`}
          onClick={onToggle}
          onContextMenu={(event) => {
            event.preventDefault();
            onMenu();
          }}
        >
          {group.name}
          {/* Open or folded alike, so folding a group leaves its chip the size it was (Matt: "changing tab groups to
              closed slightly changes the size of the tab group labels") - the count only arriving on folding made
              the chip grow by it and pushed every tab after it along. */}
          <span className={styles.groupCount}>{count}</span>
        </button>
      )}
      {menu}
    </span>
  );
}
