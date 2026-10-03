import { useCallback, useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { Bell, DoorOpen, FolderOpen, SlidersHorizontal, Trash2, Users } from '@glacier/icons';
import { Input, Switch } from '@glacier/react';
import { useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { deleteOrg, fetchOrg, inviteByHandle, removeMember, setRole, updateOrg, useOrgs } from '../core/orgs/orgs.ts';
import type { Member, Org, OrgRow, Role } from '../core/orgs/types.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { orgWorkspaceId, useWorkspaces, type WorkspaceHue } from '../core/workspaces.ts';
import { WorkspaceSwatch } from '../notes/WorkspaceSwatch.tsx';
import { when } from '../notes/when.ts';
import { InviteActions } from './InviteActions.tsx';
import { InviteLinks } from './InviteLinks.tsx';
import { SettingsScreen, type SettingsSection, type SettingsTarget } from './SettingsScreen.tsx';
import { PaneHero, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsFootnote } from './kit/settingsKit.tsx';
import { memberWords, roleWords } from './orgWords.ts';
import styles from './OrganizationsPane.module.css';

/**
 * An organization's own screen (docs/TEAMS.md, D6; Matt: "There should be a way to view an organization ... when on
 * the organization view make a new settings screen copying the same layout and stuff from the normal settings page
 * but make it tailored towards organization features"): the Settings surface itself (SettingsScreen.tsx), with the
 * organization's name where "Settings" stood, no search over its five sections, and opened landed on Members, so the
 * first thing seen is the team - a hero of the name, its colour, how many and what you are - and not a menu. Back
 * from Members steps to the list of sections, which is the organization's settings; from there back closes.
 *
 * The sections: General (the name and the colour, which owners and admins change; the workspace follows), Members
 * (the list with each one's role, invite by handle or by link, remove, and for the owner a role to set or the organization to
 * hand over), Workspace (the organization's workspace on this device, and the way to the notes filed in it),
 * Notifications (mute this organization's team news) and, last and on its own, Leave or Delete, each tapped twice
 * as a reset is (DeveloperPane.tsx). The service's refusals are shown in its own words under the row that asked.
 *
 * Opened from Settings › Account › Organizations (`from: 'settings'`), its head reads "← Organizations" and closing
 * reopens Settings on that page (App.tsx); from the organization's dashboard's cog (`from: 'dashboard'`), closing
 * finds the dashboard again; from anywhere else - the home filters, a folder's menu, the workspace's sheet - closing
 * goes back to the notes. The personal Settings sheet is never open at the same time.
 *
 * What the organization's workspace is, and is not yet, is said on Members and on Workspace: notes filed there stay
 * the person's own for now (docs/TEAMS.md, D1); sharing them with the team is the next slice.
 */

interface OrganizationSheetProps {
  orgId: string;
  /**
   * Opened from Settings › Account › Organizations: the head says so, and closing goes back there. From the
   * organization's dashboard (notes/OrganizationScreen.tsx), closing finds the dashboard again, so the head's word is
   * the organization's name said as the place it goes, not "Back to your notes".
   */
  from?: 'settings' | 'dashboard';
  onClose: () => void;
  /** The notes filed in the organization's workspace: the home page with that workspace chosen. */
  onNotes: () => void;
  /**
   * Land on Members as it opens (the default), or on the list of sections: from the organization's dashboard
   * (notes/OrganizationScreen.tsx), whose page already shows the team, the cog opens the settings themselves.
   */
  landOnMembers?: boolean;
}

/** How long a leave or a delete stays armed after its first tap, as a reset does. */
const ARMED_MS = 5000;

/** The sentence about the workspace, said on Members and on Workspace (docs/TEAMS.md, D1). */
const YOURS_FOR_NOW = 'Notes filed here stay yours for now; sharing them with the team comes next.';

/** When, mid-sentence: "yesterday" and "just now" lose their capital, a weekday or a month keeps its own. */
function since(ms: number): string {
  const words = when(ms);
  return words === 'Yesterday' || words === 'Just now' ? words.toLowerCase() : words;
}

/** The chip after a handle: the role, and whether they have joined yet. */
function RoleChip({ member }: { member: Member }) {
  return (
    <span className={styles.role} data-role={member.role} data-state={member.state}>
      {member.state === 'invited' ? 'Invited' : roleWords(member.role)}
    </span>
  );
}

/** A round of the organization's colour, as the hero's glyph. */
function HueGlyph({ hue }: { hue: string | null }) {
  return <span className={styles.heroHue} data-hue={hue ?? 'ink'} aria-hidden="true" />;
}

// --- General -----------------------------------------------------------------------------

function General({ org, canEdit, onChange }: { org: Org; canEdit: boolean; onChange: (change: { name?: string; hue?: string | null }) => Promise<void> }) {
  const [name, setName] = useState(org.name);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => setName(org.name), [org.name]);
  const clean = name.trim();
  const change = async (what: { name?: string; hue?: string | null }) => {
    setBusy(true);
    setProblem(null);
    try {
      await onChange(what);
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <PaneSection title="Name" footer={canEdit ? 'Every member sees the new name, and their workspace for it is renamed with it.' : 'Only the owner or an admin can rename it.'}>
        {canEdit ? (
          <form
            className="setk-form"
            onSubmit={(event: FormEvent) => {
              event.preventDefault();
              if (clean && clean !== org.name) void change({ name: clean });
            }}
          >
            <Input aria-label="Organization name" placeholder="Name" autoCapitalize="words" maxLength={60} value={name} onChange={(e) => setName(e.target.value)} />
            {problem ? (
              <p className="setk-form__problem" role="alert">
                {problem}
              </p>
            ) : null}
            <button type="submit" className="app-word setk-form__submit" disabled={busy || !clean || clean === org.name}>
              {busy ? 'One moment…' : 'Rename'}
            </button>
          </form>
        ) : (
          <SettingRow label="Name" value={org.name} />
        )}
      </PaneSection>
      <PaneSection title="Colour" footer="Worn by the organization's workspace on every member's device: its pill, its folder and its tag on a note.">
        {canEdit ? (
          <div className={styles.swatch}>
            <WorkspaceSwatch hue={(org.hue as WorkspaceHue | null) ?? 'ink'} onHue={(hue) => void change({ hue: hue === 'ink' ? null : hue })} />
          </div>
        ) : (
          <SettingRow label="Colour" value={<span className={styles.hue} data-hue={org.hue ?? 'ink'} aria-hidden="true" />} />
        )}
      </PaneSection>
    </>
  );
}

// --- Members -----------------------------------------------------------------------------

/** What the signed-in person may do to a member row, by the roles (docs/TEAMS.md, D10). */
function MemberRow({ member, me, role, onDo }: { member: Member; me: string; role: Role; onDo: (what: 'remove' | 'admin' | 'member' | 'owner', handle: string) => Promise<void> }) {
  const self = member.handle.toLowerCase() === me.toLowerCase();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  // Handing the organization over is tapped twice, as leaving it is: the owner's seat is not a thing to lose to a slip.
  const [handing, setHanding] = useState(false);
  useEffect(() => {
    if (!handing) return undefined;
    const id = window.setTimeout(() => setHanding(false), ARMED_MS);
    return () => window.clearTimeout(id);
  }, [handing]);
  const act = async (what: 'remove' | 'admin' | 'member' | 'owner') => {
    if (what === 'owner' && !handing) {
      setHanding(true);
      fireNativeHaptic('warning');
      return;
    }
    setBusy(true);
    setProblem(null);
    try {
      await onDo(what, member.handle);
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
      setHanding(false);
    }
  };
  const joined = member.state === 'member';
  // The owner sets roles and hands over; an admin removes members and invitees, never the owner or another admin;
  // nobody removes themself here - that is Leave, last on the list, tapped twice.
  const canRole = role === 'owner' && !self && joined;
  const canRemove = !self && member.role !== 'owner' && (role === 'owner' || (role === 'admin' && member.role !== 'admin'));
  const words = [
    ...(canRole ? [member.role === 'admin' ? { what: 'member' as const, word: 'Make member' } : { what: 'admin' as const, word: 'Make admin' }] : []),
    ...(canRole ? [{ what: 'owner' as const, word: handing ? 'Tap again to hand over' : 'Hand over' }] : []),
    ...(canRemove ? [{ what: 'remove' as const, word: joined ? 'Remove' : 'Withdraw' }] : []),
  ];
  const hint = problem ?? (joined ? `${self ? 'You, ' : ''}${member.role === 'owner' ? 'owner since' : 'joined'} ${since(member.since)}` : `Invited${member.invitedBy ? ` by ${member.invitedBy}` : ''} ${since(member.since)}`);
  return (
    <SettingRow
      label={
        <>
          {member.handle}
          <RoleChip member={member} />
        </>
      }
      hint={hint}
      layout={words.length ? 'stacked' : 'trailing'}
      control={
        words.length ? (
          <span className={styles.memberWords}>
            {words.map(({ what, word }) => (
              <RowAction key={what} onPress={() => void act(what)} disabled={busy}>
                {word}
              </RowAction>
            ))}
          </span>
        ) : undefined
      }
    />
  );
}

function Invite({ onInvite }: { onInvite: (handle: string) => Promise<void> }) {
  const [handle, setHandle] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const clean = handle.trim();
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!clean) return;
    setBusy(true);
    setProblem(null);
    setSaid(null);
    try {
      await onInvite(clean);
      setSaid(`${clean} is invited. They see it in their notifications.`);
      setHandle('');
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };
  return (
    <PaneSection title="Invite" description="By handle. They get an invitation in their notifications, with Accept and Decline, and join once they accept.">
      <form className="setk-form" onSubmit={(e) => void submit(e)}>
        <Input aria-label="Handle" placeholder="Handle" autoCapitalize="none" autoCorrect="off" spellCheck={false} value={handle} onChange={(e) => setHandle(e.target.value)} />
        {problem ? (
          <p className="setk-form__problem" role="alert">
            {problem}
          </p>
        ) : said ? (
          <p className="setk-form__problem" role="status">
            {said}
          </p>
        ) : null}
        <button type="submit" className="app-word setk-form__submit" disabled={busy || !clean}>
          {busy ? 'One moment…' : 'Invite'}
        </button>
      </form>
    </PaneSection>
  );
}

function Members({ row, org, me, onInvite, onDo }: { row: OrgRow; org: Org | null; me: string; onInvite: (handle: string) => Promise<void>; onDo: (what: 'remove' | 'admin' | 'member' | 'owner', handle: string) => Promise<void> }) {
  const joined = org?.members.filter((m) => m.state === 'member').length ?? row.members;
  const canInvite = row.state === 'member' && (row.role === 'owner' || row.role === 'admin');
  return (
    <>
      <PaneSection footer={YOURS_FOR_NOW}>
        <PaneHero glyph={<HueGlyph hue={row.hue} />} title={row.name} meta={`${memberWords(joined)} · ${row.state === 'invited' ? 'You are invited' : `You are ${roleWords(row.role).toLowerCase()}`}`} />
      </PaneSection>
      {row.state === 'invited' ? (
        <PaneSection title="Invitation">
          <SettingRow label={row.invitedBy ? `${row.invitedBy} invited you` : 'You are invited'} hint="Accept to join, and its workspace is made on each of your devices." layout="stacked" control={<InviteActions orgId={row.id} />} />
        </PaneSection>
      ) : (
        <PaneSection title="Members">
          {org ? org.members.map((member) => <MemberRow key={member.handle} member={member} me={me} role={row.role} onDo={onDo} />) : <SettingRow label="Reading the members…" />}
        </PaneSection>
      )}
      {canInvite ? <Invite onInvite={onInvite} /> : null}
      {canInvite ? (
        <PaneSection title="Invite by link" description="Anyone signed in who has the link can join as a member, until it stops or you turn it off. Send it however you like.">
          <InviteLinks orgId={row.id} inset />
        </PaneSection>
      ) : null}
    </>
  );
}

// --- Leave or Delete ---------------------------------------------------------------------

/** A row tapped twice, armed for a few seconds in between, as a reset is (DeveloperPane.tsx `ResetRow`). */
function TwiceRow({ icon, label, hint, word, busyWord, onDo }: { icon: ReactNode; label: string; hint: string; word: string; busyWord: string; onDo: () => Promise<void> }) {
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  useEffect(() => {
    if (!armed) return undefined;
    const id = window.setTimeout(() => setArmed(false), ARMED_MS);
    return () => window.clearTimeout(id);
  }, [armed]);
  const press = async () => {
    if (!armed) {
      setArmed(true);
      fireNativeHaptic('warning');
      return;
    }
    setBusy(true);
    setProblem(null);
    try {
      await onDo();
    } catch (failure) {
      setProblem(failureText(failure));
      setBusy(false);
      setArmed(false);
    }
  };
  return (
    <SettingRow
      icon={icon}
      label={label}
      hint={problem ?? hint}
      control={
        <RowAction onPress={() => void press()} disabled={busy}>
          {busy ? busyWord : armed ? 'Tap again' : word}
        </RowAction>
      }
    />
  );
}

// --- the screen ----------------------------------------------------------------------------

export function OrganizationSheet({ orgId, from, onClose, onNotes, landOnMembers = true }: OrganizationSheetProps) {
  const account = useAccount();
  const prefs = usePreferences();
  const { list } = useOrgs();
  const { list: spaces } = useWorkspaces();
  const row = list.find((each) => each.id === orgId) ?? null;
  const [org, setOrg] = useState<Org | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  // Landed on Members, once, as the screen opens (docs/TEAMS.md, D6): the team first, the settings behind it.
  const [goTo, setGoTo] = useState<(SettingsTarget & { nonce: number }) | null>(() => (landOnMembers ? { id: 'members', nonce: Date.now() } : null));

  /** The organization in full, read again after every change here: the members, and the kept row with them. */
  const read = useCallback(async () => {
    try {
      setOrg(await fetchOrg(orgId));
      setProblem(null);
    } catch (failure) {
      // An invitee, or an organization gone meanwhile: the kept row draws what it can, and the words say the rest.
      setProblem(failureText(failure));
    }
  }, [orgId]);
  useEffect(() => {
    if (!account.session || row?.state !== 'member') return;
    void read();
  }, [account.session, read, row?.state]);
  // Another organization: landed on its Members again.
  useEffect(() => setGoTo(landOnMembers ? { id: 'members', nonce: Date.now() } : null), [orgId, landOnMembers]);

  const me = account.session?.handle ?? '';
  const name = row?.name ?? org?.name ?? 'Organization';
  const role: Role = row?.role ?? 'member';
  const canEdit = row?.state === 'member' && (role === 'owner' || role === 'admin');
  const muted = prefs.notifications.mutedOrgs.includes(orgId);
  const workspace = spaces.find((w) => w.id === orgWorkspaceId(orgId)) ?? null;

  const onDo = async (what: 'remove' | 'admin' | 'member' | 'owner', handle: string) => {
    if (what === 'remove') await removeMember(orgId, handle);
    else await setRole(orgId, handle, what);
    await read();
  };
  const leave = async () => {
    await removeMember(orgId, me);
    onClose();
  };
  const destroy = async () => {
    await deleteOrg(orgId);
    onClose();
  };

  const gone = !row;
  const sections: SettingsSection[] = [
    {
      id: 'general',
      label: 'General',
      icon: <SlidersHorizontal size={16} />,
      hue: 'graphite',
      group: 0,
      content: org && row ? (
        <General
          org={org}
          canEdit={canEdit}
          onChange={async (change) => {
            await updateOrg(orgId, change);
            await read();
          }}
        />
      ) : (
        <SettingRow label="Name" value={name} />
      ),
    },
    {
      id: 'members',
      label: 'Members',
      icon: <Users size={16} />,
      hue: 'blue',
      group: 0,
      summary: row ? memberWords(row.members) : undefined,
      content: row ? (
        <>
          {problem ? <SettingsCallout>{problem}</SettingsCallout> : null}
          <Members
            row={row}
            org={org}
            me={me}
            onInvite={async (handle) => {
              await inviteByHandle(orgId, handle);
              await read();
            }}
            onDo={onDo}
          />
        </>
      ) : (
        <SettingsCallout>This organization is not in your list any more.</SettingsCallout>
      ),
    },
    {
      id: 'workspace',
      label: 'Workspace',
      icon: <FolderOpen size={16} />,
      hue: 'green',
      group: 1,
      summary: workspace ? workspace.name : 'Not on this device yet',
      content: (
        <PaneSection title="Its workspace" footer={YOURS_FOR_NOW}>
          <SettingRow icon={<span className={styles.hue} data-hue={row?.hue ?? 'ink'} aria-hidden="true" />} label={workspace?.name ?? name} hint={workspace ? 'Made on every member’s device, named and coloured after the organization.' : 'Made here once you have joined and the next sync lands.'} />
          <SettingRow icon={<FolderOpen size={20} />} label="Notes filed here" hint="The home page, with this workspace chosen." onPress={workspace ? onNotes : undefined} disabledReason={workspace ? undefined : 'Nothing is filed here yet.'} />
        </PaneSection>
      ),
    },
    {
      id: 'notifications',
      label: 'Notifications',
      icon: <Bell size={16} />,
      hue: 'coral',
      group: 1,
      summary: muted ? 'Muted' : 'On',
      content: (
        <PaneSection title="This organization" footer="Muted, its team news is not drawn or counted. Its invitations still are. The choice follows you to your other devices.">
          <SettingRow
            label="Mute this organization"
            hint="Who joined, left or was removed, a rename, a deletion."
            control={
              <Switch
                aria-label="Mute this organization"
                checked={muted}
                onCheckedChange={(on) =>
                  setPreferences({
                    notifications: { ...prefs.notifications, mutedOrgs: on ? [...prefs.notifications.mutedOrgs.filter((id) => id !== orgId), orgId] : prefs.notifications.mutedOrgs.filter((id) => id !== orgId) },
                  })
                }
              />
            }
          />
          <SettingsFootnote>The four switches over what reaches you at all are under Settings › Notifications.</SettingsFootnote>
        </PaneSection>
      ),
    },
    {
      id: 'leave',
      label: role === 'owner' ? 'Delete' : 'Leave',
      icon: role === 'owner' ? <Trash2 size={16} /> : <DoorOpen size={16} />,
      hue: 'red',
      group: 2,
      content:
        role === 'owner' ? (
          <PaneSection title="Delete organization" footer="Every member is told, and their workspace for it goes; the notes filed there stay with each of them, unfiled. Invitations waiting are withdrawn.">
            <TwiceRow icon={<Trash2 size={20} />} label="Delete organization" hint="For good. Tap twice." word="Delete" busyWord="Deleting" onDo={destroy} />
          </PaneSection>
        ) : (
          <PaneSection title="Leave organization" footer="Your workspace for it goes from your devices; the notes filed there stay yours, unfiled. The others are told.">
            <TwiceRow icon={<DoorOpen size={20} />} label="Leave organization" hint="Tap twice." word="Leave" busyWord="Leaving" onDo={leave} />
          </PaneSection>
        ),
    },
  ];

  return (
    <SettingsScreen
      open
      onClose={onClose}
      sections={gone ? sections.filter((s) => s.id === 'members') : sections}
      goTo={goTo}
      title={name}
      search={false}
      closeWord={from === 'settings' ? 'Organizations' : from === 'dashboard' ? name : undefined}
    />
  );
}
