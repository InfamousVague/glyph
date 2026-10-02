import { useState, type FormEvent } from 'react';
import { Users } from '@glacier/icons';
import { Input } from '@glacier/react';
import { useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { createOrg, useOrgs } from '../core/orgs/orgs.ts';
import type { OrgRow } from '../core/orgs/types.ts';
import { InviteActions } from './InviteActions.tsx';
import type { SettingsTarget } from './SettingsScreen.tsx';
import { GoWord, PaneSection, SettingRow, SettingsCallout, SettingsFootnote } from './kit/settingsKit.tsx';
import { memberWords, roleWords } from './orgWords.ts';
import styles from './OrganizationsPane.module.css';

/**
 * Organizations, a sub-page behind a row on Account (docs/TEAMS.md, D6; Matt: "build the ability to create teams in
 * the app. We should be able to create an organization in order to add users as team members by handle"): the
 * organizations the account is in, each a row that opens the organization's own screen (OrganizationSheet.tsx); the
 * invitations waiting, each with Accept and Decline inline (InviteActions.tsx); and a name to make a new one, which
 * opens as soon as the service answers. The list is the one the sync pass keeps (core/orgs/orgs.ts `useOrgs`), so the
 * page draws at once and is the service's truth by the next pass.
 *
 * Signed out there is nothing to list and nothing to make: the words send the person to Account, as "Local only"
 * sends them to the Privacy card. What the search finds here is OrganizationsPane.findable.ts; the shared words are
 * orgWords.ts.
 */

/** A small round of the organization's hue before its name, the one its workspace's pill wears (ink.css `[data-hue]`). */
export function HueMark({ hue }: { hue: string | null }) {
  return <span className={styles.hue} data-hue={hue ?? 'ink'} aria-hidden="true" />;
}

function NewOrganization({ onMade }: { onMade: (orgId: string) => void }) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const clean = name.trim();

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!clean) return;
    setBusy(true);
    setProblem(null);
    try {
      const org = await createOrg(clean);
      setName('');
      onMade(org.id);
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PaneSection title="New organization" description="A team by name. You own it, and can invite people by their handle; each member gets its workspace.">
      <form className="setk-form" onSubmit={(e) => void submit(e)}>
        <Input aria-label="Organization name" placeholder="Name" autoCapitalize="words" maxLength={60} value={name} onChange={(e) => setName(e.target.value)} />
        {problem ? (
          <p className="setk-form__problem" role="alert">
            {problem}
          </p>
        ) : null}
        <button type="submit" className="app-word setk-form__submit" disabled={busy || !clean}>
          {busy ? 'One moment…' : 'Create'}
        </button>
      </form>
    </PaneSection>
  );
}

interface OrganizationsPaneProps {
  /** Lands on a page of Settings: Account, for the signed-out words. */
  onOpen?: (target: SettingsTarget) => void;
  /** Opens an organization's own screen (settings/OrganizationSheet.tsx), from its row or once it is made. */
  onOrganization?: (orgId: string) => void;
}

export function OrganizationsPane({ onOpen, onOrganization }: OrganizationsPaneProps) {
  const account = useAccount();
  const { list } = useOrgs();
  if (!account.session) {
    return (
      <SettingsCallout>
        <span>
          Organizations come with an account. Sign in under <GoWord onPress={onOpen ? () => onOpen({ id: 'account' }) : undefined}>Account</GoWord> to make or join one.
        </span>
      </SettingsCallout>
    );
  }
  const joined = list.filter((row) => row.state === 'member');
  const invited = list.filter((row) => row.state === 'invited');
  const open = (row: OrgRow) => onOrganization?.(row.id);
  return (
    <>
      {invited.length ? (
        <PaneSection title="Invitations">
          {invited.map((row) => (
            <SettingRow
              key={row.id}
              icon={<HueMark hue={row.hue} />}
              label={row.name}
              hint={row.invitedBy ? `Invited by ${row.invitedBy} · ${memberWords(row.members)}` : memberWords(row.members)}
              layout="stacked"
              control={<InviteActions orgId={row.id} onAnswered={(accepted) => accepted && open(row)} />}
            />
          ))}
        </PaneSection>
      ) : null}
      <PaneSection title="Your organizations">
        {joined.length ? (
          joined.map((row) => <SettingRow key={row.id} icon={<HueMark hue={row.hue} />} label={row.name} hint={`${roleWords(row.role)} · ${memberWords(row.members)}`} onPress={() => open(row)} />)
        ) : (
          <SettingRow icon={<Users size={20} />} label="None yet" hint="Make one below, or accept an invitation when one arrives." />
        )}
      </PaneSection>
      <NewOrganization onMade={(id) => onOrganization?.(id)} />
      <SettingsFootnote>An organization’s name and its members’ handles are kept on the service in the clear, so an invitation can reach them. Notes stay encrypted on your own devices.</SettingsFootnote>
    </>
  );
}
