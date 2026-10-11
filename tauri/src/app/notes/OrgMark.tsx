import { UserGroup } from '@glacier/icons';
import styles from './OrgMark.module.css';

/**
 * The small mark an organization's workspace wears before its name (docs/TEAMS.md, D5): on its pill (WorkspaceBar.tsx),
 * its chip and its row in the home filters (home/HomeFilters.tsx), and its folder in the sidebar (NoteTree.tsx). An
 * organization's name can be a personal workspace's too - the dedupe is among personal ones only - so two pills called
 * Ghost are told apart by this, and by `data-org` on each for anything that asks. The kit's group of three (Matt chose UserGroup, 2026-10-02), at the text's size.
 */
export function OrgMark({ className }: { className?: string }) {
  return <UserGroup size="1em" strokeWidth={2.2} className={`${styles.mark}${className ? ` ${className}` : ''}`} aria-label="Organization" role="img" />;
}
