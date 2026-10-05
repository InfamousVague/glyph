import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type FormEvent, type RefObject } from 'react';
import { Activity, ArrowLeft, FilePlus, History, Settings, UserPlus, Users } from '@glacier/icons';
import { Input } from '@glacier/react';
import { useAccount } from '../core/account/account.ts';
import { useBack } from '../core/back.ts';
import { failureText } from '../core/failure.ts';
import { useNotifications } from '../core/notifications/feed.ts';
import { sentenceOf, type Notification } from '../core/notifications/kinds.ts';
import { fetchOrg, inviteByHandle, setOrgColour, useOrgs } from '../core/orgs/orgs.ts';
import type { Member, Org, OrgRow } from '../core/orgs/types.ts';
import { usePreferences } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { syncNotificationsNow } from '../core/sync/engine.ts';
import { orgWorkspaceId, useWorkspaces, type WorkspaceHue } from '../core/workspaces.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { InviteActions } from '../settings/InviteActions.tsx';
import { InviteLinks } from '../settings/InviteLinks.tsx';
import { GoWord } from '../settings/kit/settingsKit.tsx';
import { memberWords, roleWords } from '../settings/orgWords.ts';
import { NoteCard } from './NoteCard.tsx';
import { WorkspaceSwatch } from './WorkspaceSwatch.tsx';
import { MARKS, NEWS } from './orgNews.tsx';
import { PullToRefresh } from './PullToRefresh.tsx';
import { when } from './when.ts';
import styles from './OrganizationScreen.module.css';

/**
 * An organization's dashboard (docs/TEAMS.md; Matt: "Design and deploy a dashboard for organizations when clicking an
 * organization in the header don't take me to the settings, instead, take me to this dashboard page and have a
 * organization settings icon on that"). The page an organization opens on, from the top bar's picker, a notification
 * about it, an invitation accepted or one just made: what the team is and what it has been doing, with its settings
 * (settings/OrganizationSheet.tsx) behind the cog at the bar's end rather than in front of everything.
 *
 * Built as All notes is (AllNotesScreen.tsx): the glass bar with the way home, the organization's name with its
 * colour, and the cog; under it the scroller with its smoke. On it, in order:
 *
 * - **The other organizations**, as a row of pills to move between them, when there is more than one.
 * - **The hero**: the colour, the name, how many and what you are, and what its workspace is and is not yet (D1:
 *   notes filed there are the team’s, docs/SHARED.md), with New note (made filed in its workspace) and Invite (for an owner or
 *   an admin, which brings the invite field into view).
 * - **Notes**: the newest of the notes filed in its workspace, as cards, and the way to all of them.
 * - **Members**: who is in it and who is invited, with their roles, and for an owner or an admin the invite field and
 *   the invite links (settings/InviteLinks.tsx).
 * - **Activity**: the organization's own news from the feed (who joined, left or was removed, a rename, a new role,
 *   an invitation answered), newest first, and the way to its audit log (OrganizationLog.tsx): every change to every
 *   note filed here with the team's news between them, which the clock beside the cog opens too.
 *
 * On a wide window the members stand beside the notes and the activity, as To do stands beside the home page's
 * groups. Invited and not yet a member, the page is the invitation with Accept and Decline; gone from the list, it
 * says so. Signed out or with Local only on, nothing can arrive, and the page says why with a word to Account.
 *
 * The members are read when the page opens, when the organization's news arrives, and when a pull from the top takes
 * the feed again, so someone who accepts while the page is open is a member a moment later.
 */

interface OrganizationScreenProps {
  orgId: string;
  /** The notes this device holds (not the trash), of which those filed in the organization's workspace are shown. */
  notes: readonly Note[];
  /** Home. */
  onBack: () => void;
  onOpenNote: (id: string) => void;
  /** A new note, filed in the organization's workspace, opened ready to type. */
  onNewNote: () => void;
  /** Every note filed in the organization's workspace: the home page with that workspace chosen. */
  onAllNotes: () => void;
  /** The organization's settings (settings/OrganizationSheet.tsx), from the cog. */
  onSettings: () => void;
  /** Another organization's dashboard, from the row of pills. */
  onOpenOrganization: (orgId: string) => void;
  /** The organization's audit log (OrganizationLog.tsx), from the clock in the bar and the Activity heading. */
  onLog: () => void;
  /** Settings at Account, from the signed-out words. */
  onAccount: () => void;
}

/** How many of the workspace's notes the page shows before "All of them". */
const NOTES_SHOWN = 6;
/** How many of the organization's news rows the page shows; the audit log has them all. */
const ACTIVITY_SHOWN = 8;

/** The sentence about the workspace, as the organization's settings say it (docs/TEAMS.md, D1). */
const TEAMS_NOTES = 'Notes filed here are the team’s: everyone in it reads and edits them, and edits made apart merge.';

/** When, mid-sentence: "yesterday" and "just now" lose their capital, a weekday or a month keeps its own. */
function since(ms: number): string {
  const words = when(ms);
  return words === 'Yesterday' || words === 'Just now' ? words.toLowerCase() : words;
}

export function OrganizationScreen({ orgId, notes, onBack, onOpenNote, onNewNote, onAllNotes, onSettings, onOpenOrganization, onLog, onAccount }: OrganizationScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  const inviteField = useRef<HTMLInputElement>(null);
  useWispEdge(scroller, 'organization', topBar);
  useBack(true, onBack);
  const account = useAccount();
  const prefs = usePreferences();
  const { list } = useOrgs();
  const { of: filed } = useWorkspaces();
  const feed = useNotifications();
  const row = list.find((each) => each.id === orgId) ?? null;
  const signedIn = Boolean(account.session);
  const held = !signedIn || prefs.localOnly;
  const member = row?.state === 'member';
  const me = account.session?.handle ?? '';

  // The organization in full - the members - read again whenever something about it may have changed.
  const [org, setOrg] = useState<Org | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const read = useCallback(async () => {
    try {
      setOrg(await fetchOrg(orgId));
      setProblem(null);
    } catch (failure) {
      setProblem(failureText(failure));
    }
  }, [orgId]);
  // Its news as the feed holds it: a new row (someone joined, a role changed) is the members changed too.
  const news = useMemo(() => feed.filter((n) => n.org?.id === orgId && NEWS.has(n.kind)), [feed, orgId]);
  const newest = news[0]?.rev ?? 0;
  useEffect(() => {
    setOrg(null);
    setProblem(null);
  }, [orgId]);
  useEffect(() => {
    if (held || !member) return;
    void read();
  }, [held, member, read, newest, row?.members, row?.colour]);
  // Opened: the feed and the list taken again now, so what changed while the app was away is here before it is read.
  useEffect(() => {
    if (!held) void syncNotificationsNow();
  }, [held, orgId]);

  // The notes filed in its workspace, newest change first.
  const workspaceId = orgWorkspaceId(orgId);
  const filedHere = useMemo(() => notes.filter((note) => filed[note.id] === workspaceId && !note.archivedAt).sort((a, b) => b.updatedAt - a.updatedAt), [notes, filed, workspaceId]);

  const others = list.filter((each) => each.id !== orgId);
  const canInvite = member && (row?.role === 'owner' || row?.role === 'admin');
  const joined = org?.members.filter((m) => m.state === 'member') ?? [];
  const invited = org?.members.filter((m) => m.state === 'invited') ?? [];
  const count = org ? joined.length : (row?.members ?? 0);
  const refresh = async () => {
    await syncNotificationsNow();
    if (member) await read();
  };
  const toInvite = () => {
    inviteField.current?.scrollIntoView({ block: 'center', behavior: 'smooth' });
    inviteField.current?.focus({ preventScroll: true });
  };

  return (
    <div className={styles.screen} data-hue={row?.hue ?? 'ink'}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <button type="button" className={styles.back} onClick={onBack} aria-label="Back to home">
          <ArrowLeft size={20} aria-hidden="true" />
        </button>
        <h1 className={styles.title}>
          <span className={styles.titleHue} data-hue={row?.hue ?? 'ink'} aria-hidden="true" />
          <span className={styles.titleName}>{row?.name ?? 'Organization'}</span>
        </h1>
        {/* The audit log, behind a clock before the cog: every change to the notes filed here, and the team's news. */}
        {row && !held && member ? (
          <button type="button" className={styles.cog} onClick={onLog} aria-label="Audit log" title="Audit log">
            <History size={19} strokeWidth={2.1} aria-hidden="true" />
          </button>
        ) : null}
        {/* The organization's settings, behind a cog at the bar's end (Matt: "have a organization settings icon on that"). */}
        {row && !held ? (
          <button type="button" className={styles.cog} onClick={onSettings} aria-label="Organization settings" title="Organization settings">
            <Settings size={19} strokeWidth={2.1} aria-hidden="true" />
          </button>
        ) : null}
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          {others.length ? <Switcher current={row} others={others} onOpen={onOpenOrganization} /> : null}
          {held ? (
            <p className={styles.held}>
              {signedIn ? (
                <>
                  <GoWord onPress={onAccount}>Local only</GoWord> is on, so nothing about the organization arrives until it is off.
                </>
              ) : (
                <>
                  Organizations come with an account. Sign in under <GoWord onPress={onAccount}>Account</GoWord>.
                </>
              )}
            </p>
          ) : !row ? (
            <div className={styles.gone}>
              <Ghost scene="empty-workspace" size="small" className={styles.goneArt} />
              <p className={styles.goneLead}>This organization is not in your list any more.</p>
              <p className={styles.goneHint}>You left it, it was deleted, or the invitation was withdrawn.</p>
            </div>
          ) : !member ? (
            <Invitation row={row} />
          ) : (
            <>
              <Hero row={row} count={count} canInvite={Boolean(canInvite)} onNewNote={onNewNote} onInvite={toInvite} />
              {problem ? (
                <p className={styles.problem} role="alert">
                  {problem}
                </p>
              ) : null}
              <div className={styles.grid}>
                <section className={styles.section} aria-labelledby="org-notes" data-group="notes">
                  <div className={styles.headRow}>
                    <h2 id="org-notes" className={styles.heading}>
                      <FilePlus size={15} className={styles.mark} aria-hidden="true" />
                      Notes
                      {filedHere.length ? <span className={styles.count}>{filedHere.length}</span> : null}
                    </h2>
                    {filedHere.length > NOTES_SHOWN ? (
                      <button type="button" className={`app-word ${styles.more}`} onClick={onAllNotes}>
                        All {filedHere.length}
                      </button>
                    ) : filedHere.length ? (
                      <button type="button" className={`app-word ${styles.more}`} onClick={onAllNotes}>
                        In its workspace
                      </button>
                    ) : null}
                  </div>
                  {filedHere.length ? (
                    <ol className={styles.cards} aria-label="Notes in this organization">
                      {filedHere.slice(0, NOTES_SHOWN).map((note, i) => (
                        <NoteCard key={note.id} note={note} index={i} onOpen={onOpenNote} dense />
                      ))}
                    </ol>
                  ) : (
                    <p className={styles.none}>Nothing is filed here yet. Start one with New note, or file a note here from its More, under Workspace.</p>
                  )}
                </section>
                <section className={styles.section} aria-labelledby="org-members" data-group="members">
                  <div className={styles.headRow}>
                    <h2 id="org-members" className={styles.heading}>
                      <Users size={15} className={styles.mark} aria-hidden="true" />
                      Members
                      <span className={styles.count}>{count}</span>
                    </h2>
                  </div>
                  <ul className={styles.members} aria-label="Members">
                    {org ? (
                      [...joined, ...invited].map((m, i) => <MemberLine key={m.handle} member={m} me={me} index={i} />)
                    ) : (
                      <li className={styles.reading}>Reading the members…</li>
                    )}
                  </ul>
                  {/* Your colour in this organization (docs/SHARED.md, S7), under the members, where it is worn. */}
                  <YourColour row={row} />
                  {canInvite ? (
                    <Invite
                      field={inviteField}
                      onInvite={async (handle) => {
                        await inviteByHandle(orgId, handle);
                        await read();
                      }}
                    />
                  ) : null}
                  {canInvite ? (
                    <InviteLinks
                      orgId={orgId}
                      around={(panel) => (
                        <div className={styles.byLink}>
                          <h3 className={styles.subheading}>Invite by link</h3>
                          {panel}
                        </div>
                      )}
                    />
                  ) : null}
                </section>
                <section className={styles.section} aria-labelledby="org-activity" data-group="activity">
                  <div className={styles.headRow}>
                    <h2 id="org-activity" className={styles.heading}>
                      <Activity size={15} className={styles.mark} aria-hidden="true" />
                      Activity
                    </h2>
                    <button type="button" className={`app-word ${styles.more}`} onClick={onLog}>
                      Audit log
                    </button>
                  </div>
                  {news.length ? (
                    <ol className={styles.activity} aria-label="Activity">
                      {news.slice(0, ACTIVITY_SHOWN).map((n, i) => (
                        <NewsLine key={n.id} n={n} index={i} />
                      ))}
                    </ol>
                  ) : (
                    <p className={styles.none}>Nothing has happened here yet. Who joins, leaves or changes role shows here.</p>
                  )}
                </section>
              </div>
            </>
          )}
        </div>
      </div>
      {held ? null : <PullToRefresh scroller={scroller} onRefresh={refresh} />}
    </div>
  );
}

/** The other organizations, as pills to move between them, each in its colour; an invitation waiting says so. */
function Switcher({ current, others, onOpen }: { current: OrgRow | null; others: readonly OrgRow[]; onOpen: (orgId: string) => void }) {
  return (
    <nav className={styles.switcher} aria-label="Your organizations">
      {current ? (
        <span className={styles.pill} aria-current="page">
          <span className={styles.pillHue} data-hue={current.hue ?? 'ink'} aria-hidden="true" />
          {current.name}
        </span>
      ) : null}
      {others.map((org) => (
        <button key={org.id} type="button" className={styles.pill} onClick={() => onOpen(org.id)} data-invited={org.state === 'invited' || undefined}>
          <span className={styles.pillHue} data-hue={org.hue ?? 'ink'} aria-hidden="true" />
          {org.name}
          {org.state === 'invited' ? <span className={styles.pillNote}>invited</span> : null}
        </button>
      ))}
    </nav>
  );
}

/** The organization at the top of its page: its colour, its name, how many and what you are, and two things to do. */
function Hero({ row, count, canInvite, onNewNote, onInvite }: { row: OrgRow; count: number; canInvite: boolean; onNewNote: () => void; onInvite: () => void }) {
  return (
    <section className={styles.hero} aria-label={row.name}>
      <span className={styles.heroHue} data-hue={row.hue ?? 'ink'} aria-hidden="true" />
      <div className={styles.heroWords}>
        <p className={styles.heroName}>{row.name}</p>
        <p className={styles.heroMeta}>
          {memberWords(count)} · You are {roleWords(row.role).toLowerCase()}
        </p>
        <p className={styles.heroNote}>{TEAMS_NOTES}</p>
      </div>
      <div className={styles.heroActions}>
        <button type="button" className={styles.action} onClick={onNewNote}>
          <FilePlus size={16} strokeWidth={2.1} aria-hidden="true" />
          New note
        </button>
        {canInvite ? (
          <button type="button" className={styles.action} onClick={onInvite}>
            <UserPlus size={16} strokeWidth={2.1} aria-hidden="true" />
            Invite
          </button>
        ) : null}
      </div>
    </section>
  );
}

/** Invited and not yet in: the invitation is the page, with Accept and Decline. */
function Invitation({ row }: { row: OrgRow }) {
  return (
    <section className={styles.hero} aria-label={row.name}>
      <span className={styles.heroHue} data-hue={row.hue ?? 'ink'} aria-hidden="true" />
      <div className={styles.heroWords}>
        <p className={styles.heroName}>{row.name}</p>
        <p className={styles.heroMeta}>{row.invitedBy ? `${row.invitedBy} invited you` : 'You are invited'} · {memberWords(row.members)}</p>
        <p className={styles.heroNote}>Accept to join: its workspace is made on each of your devices, and the team’s news reaches you.</p>
      </div>
      <div className={styles.heroActions}>
        <InviteActions orgId={row.id} />
      </div>
    </section>
  );
}

/** One member: an initial in a round, the handle, the role, and since when; invited ones dashed. */
function MemberLine({ member, me, index }: { member: Member; me: string; index: number }) {
  const self = member.handle.toLowerCase() === me.toLowerCase();
  const joined = member.state === 'member';
  const line = joined ? `${self ? 'You, ' : ''}${member.role === 'owner' ? 'owner since' : 'joined'} ${since(member.since)}` : `Invited${member.invitedBy ? ` by ${member.invitedBy}` : ''} ${since(member.since)}`;
  return (
    <li className={styles.member} data-state={member.state} style={{ '--i': Math.min(index, 12) } as CSSProperties}>
      {/* Their initial on their colour (docs/SHARED.md, S7): the one their cursor and comments wear. */}
      <span className={styles.avatar} data-hue={member.colour ?? undefined} aria-hidden="true">
        {member.handle.slice(0, 1).toUpperCase()}
      </span>
      <span className={styles.memberWords}>
        <span className={styles.handle}>
          {member.handle}
          <span className={styles.role} data-role={member.role} data-state={member.state}>
            {joined ? roleWords(member.role) : 'Invited'}
          </span>
        </span>
        <span className={styles.since}>{line}</span>
      </span>
    </li>
  );
}

/** One piece of the organization's news, as the notifications drawer words it. */
function NewsLine({ n, index }: { n: Notification; index: number }) {
  return (
    <li className={styles.news} data-unread={n.readAt === null || undefined} style={{ '--i': Math.min(index, 12) } as CSSProperties}>
      <span className={styles.newsMark}>{MARKS[n.kind] ?? null}</span>
      <span className={styles.newsWords}>{sentenceOf(n, null)}</span>
      <span className={styles.when}>{when(n.at)}</span>
    </li>
  );
}

/**
 * Your colour here (docs/SHARED.md, S7): the account's own unless one is picked here, worn in this organization
 * alone - by your cursor and selections in a team note, your comments and your row above. Matt: "add the ability
 * for users to pick and change their color".
 */
function YourColour({ row }: { row: OrgRow }) {
  const { colour: accountColour } = useOrgs();
  const [problem, setProblem] = useState<string | null>(null);
  const worn = (row.colour as WorkspaceHue | null) ?? 'ink';
  const overridden = (row.colour ?? null) !== (accountColour ?? null);
  const choose = async (hue: WorkspaceHue | null) => {
    setProblem(null);
    try {
      await setOrgColour(row.id, hue);
    } catch (failure) {
      setProblem(failureText(failure));
    }
  };
  return (
    <div className={styles.yourColour}>
      <span className={styles.yourColourWords}>
        <span className={styles.subheading}>Your colour</span>
        <span className={styles.since}>{overridden ? 'In this organization alone.' : 'Your account’s, from Settings.'}</span>
      </span>
      <WorkspaceSwatch hue={worn} onHue={(hue) => void choose(hue === 'ink' ? null : hue)} />
      {overridden ? (
        <button type="button" className={`app-word ${styles.more}`} onClick={() => void choose(null)}>
          Use your account’s colour
        </button>
      ) : null}
      {problem ? (
        <p className={styles.inviteSaid} role="alert">
          {problem}
        </p>
      ) : null}
    </div>
  );
}

/** The invite field, for an owner or an admin: a handle in, the service's answer under it in its own words. */
function Invite({ field, onInvite }: { field: RefObject<HTMLInputElement | null>; onInvite: (handle: string) => Promise<void> }) {
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
    <form className={styles.invite} onSubmit={(e) => void submit(e)}>
      <Input ref={field} aria-label="Invite by handle" placeholder="Invite by handle" autoCapitalize="none" autoCorrect="off" spellCheck={false} value={handle} onChange={(e) => setHandle(e.target.value)} />
      <button type="submit" className={styles.action} disabled={busy || !clean}>
        {busy ? 'One moment…' : 'Invite'}
      </button>
      {problem ? (
        <p className={styles.inviteSaid} role="alert">
          {problem}
        </p>
      ) : said ? (
        <p className={styles.inviteSaid} role="status">
          {said}
        </p>
      ) : null}
    </form>
  );
}
