import { Plus } from '../art/Icons.tsx';
import { chooseWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { scrollSideways } from '../core/scrollSideways.ts';
import { OrgMark } from './OrgMark.tsx';
import styles from './WorkspaceBar.module.css';

/**
 * The workspaces, in a row under the list's title, once there is one: "All",
 * then each by name, then + for another. A tap chooses one and the list shows
 * its notes; a tap on the one already chosen opens it to rename or remove
 * (WorkspaceSheet.tsx), where its colour is chosen too - or, for an
 * organization's workspace, which wears a small mark before its name, opens
 * the organization's own screen (docs/TEAMS.md). Nothing at all while there
 * are no workspaces, so a list that never uses them looks as it always did.
 */
export function WorkspaceBar({ onManage, onOrganization }: { onManage: (which: Workspace | 'new') => void; onOrganization?: (orgId: string) => void }) {
  const { list, current } = useWorkspaces();
  if (!list.length) return null;
  return (
    <div className={styles.spaces} role="group" aria-label="Workspaces" onWheel={scrollSideways}>
      <button type="button" className={styles.space} aria-pressed={current === null} onClick={() => chooseWorkspace(null)}>
        All
      </button>
      {list.map((workspace) => (
        <button
          key={workspace.id}
          type="button"
          className={styles.space}
          // Its hue, if it has one: the pill is drawn in it (ink.css `[data-hue]`, notes/WorkspaceBar.module.css).
          data-hue={workspace.hue ?? 'ink'}
          data-org={workspace.org}
          aria-pressed={current?.id === workspace.id}
          onClick={() => (current?.id === workspace.id ? (workspace.org && onOrganization ? onOrganization(workspace.org) : onManage(workspace)) : chooseWorkspace(workspace.id))}
        >
          {workspace.org ? <OrgMark /> : null}
          {workspace.name}
        </button>
      ))}
      <button type="button" className={`${styles.space} ${styles.spaceAdd}`} onClick={() => onManage('new')} aria-label="New workspace">
        <Plus />
      </button>
    </div>
  );
}
