import { useMemo } from 'react';
import { Users } from '@glacier/icons';
import { usePresence } from '../core/live/presence.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import type { OrgRow } from '../core/orgs/types.ts';
import type { Note } from '../core/store.ts';
import { orgWorkspaceId, useWorkspaces } from '../core/workspaces.ts';
import look from './HomeLayouts.module.css';
import styles from './HomeOrganizations.module.css';

/**
 * The organizations on the home page (Matt: "add organizations to the home page"): a card for each one joined, in its
 * colour, with how many are in it, how many notes are filed in its workspace, and who is in the app now and what
 * they are editing (core/live/presence.ts). A tap opens its dashboard (notes/OrganizationScreen.tsx). An invitation
 * still waiting is the notice above, not a card. Nothing is drawn for an account in no organization.
 */
export function HomeOrganizations({ notes, onOpen }: { notes: readonly Note[]; onOpen: (orgId: string) => void }) {
  const { list } = useOrgs();
  const joined = list.filter((row) => row.state === 'member');
  if (joined.length === 0) return null;
  return (
    <section className={look.section} aria-labelledby="home-organizations" data-section="organizations">
      <h2 id="home-organizations" className={look.heading}>
        <Users size={15} aria-hidden="true" />
        Organizations
        <span className={look.count}>{joined.length}</span>
      </h2>
      <ul className={styles.orgs} aria-label="Organizations">
        {joined.map((row) => (
          <OrgCard key={row.id} row={row} notes={notes} onOpen={onOpen} />
        ))}
      </ul>
    </section>
  );
}

function OrgCard({ row, notes, onOpen }: { row: OrgRow; notes: readonly Note[]; onOpen: (orgId: string) => void }) {
  const { of: filed } = useWorkspaces();
  const seen = usePresence(row.id);
  const workspace = orgWorkspaceId(row.id);
  const count = useMemo(() => notes.filter((note) => filed[note.id] === workspace && !note.archivedAt).length, [notes, filed, workspace]);
  // One line for who is here: someone editing, by name, before a plain count.
  const handles = [...new Set(seen.map((each) => each.handle))];
  const editing = seen.find((each) => each.at);
  const here = editing ? `${editing.handle} is editing ${editing.at!.title || 'a note'}${handles.length > 1 ? `, ${handles.length - 1} more here` : ''}` : handles.length === 1 ? `${handles[0]} is here now` : handles.length > 1 ? `${handles.length} here now` : null;
  return (
    <li>
      <button type="button" className={styles.org} data-hue={row.hue ?? 'ink'} onClick={() => onOpen(row.id)}>
        <span className={styles.hue} aria-hidden="true" />
        <span className={styles.words}>
          <span className={styles.name}>{row.name}</span>
          <span className={styles.meta}>
            {row.members === 1 ? '1 member' : `${row.members} members`} · {count === 1 ? '1 note' : `${count} notes`}
          </span>
          {here ? (
            <span className={styles.here}>
              <span className={styles.dot} aria-hidden="true" />
              {here}
            </span>
          ) : null}
        </span>
      </button>
    </li>
  );
}
