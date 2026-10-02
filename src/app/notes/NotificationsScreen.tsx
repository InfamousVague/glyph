import { useEffect, useReducer, useRef, type CSSProperties, type ReactNode } from 'react';
import { ArrowLeft, AudioLines, BookOpen, CheckCheck, Crown, FilePlus, ListPlus, Mail, PenLine, Pencil, ScrollText, Trash2, TriangleAlert, UserCheck, UserMinus, UserPlus, UserX } from '@glacier/icons';
import { useAccount } from '../core/account/account.ts';
import { useBack } from '../core/back.ts';
import { isWanted, markAllRead, markRead, onNotifications, openDetails, unreadCount, useNotifications } from '../core/notifications/feed.ts';
import { detailOf, sentenceOf, type Kind, type Notification } from '../core/notifications/kinds.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import { usePreferences } from '../core/preferences.ts';
import { syncNotificationsNow } from '../core/sync/engine.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { InviteActions } from '../settings/InviteActions.tsx';
import { GoWord } from '../settings/kit/settingsKit.tsx';
import { PullToRefresh } from './PullToRefresh.tsx';
import { when } from './when.ts';
import styles from './NotificationsScreen.module.css';

/**
 * The notifications, as a page (docs/TEAMS.md; Matt: "implement a full notification system and put the invites in
 * there with an inline accept and deny also wire up existing features to notifications where it makes sense so that
 * we see things like claude creating a new note or making edits"): a row for each, newest first, from the bell in the
 * top bar (NoteTabs.tsx). Built as All notes is (AllNotesScreen.tsx): the glass bar with the way home and the count
 * of unread, the scroller under it with its smoke, and the ghost when there is nothing.
 *
 * A row is its kind's mark, its sentence (core/notifications/kinds.ts `sentenceOf`, the one place the words live),
 * the first line Claude changed under it where there is one, and when. An invitation carries Accept and Decline
 * inline (settings/InviteActions.tsx). A row about a note opens the note - an edit at its first changed line - and
 * a row about an organization opens the organization, each read as it is tapped. What Settings › Notifications
 * switched off, and a muted organization's news, is not drawn (`isWanted`); an invitation always is. A sealed row is
 * opened as it is drawn (`openDetails`) and redrawn with its words a moment later, never waited for.
 *
 * Opening the page takes the feed again, as a pull from the top does: both run a pass of the notifications and the
 * organizations (core/sync/engine.ts `syncNotificationsNow`). Signed out, or with Local only on, nothing arrives,
 * and the page says so with a word that goes to Account, as the plugins' page does.
 */

interface NotificationsScreenProps {
  /** Home. */
  onBack: () => void;
  /** A note a row is about, opened: `at` is the line an edit landed on, as the note screen takes it (shell/screen.ts). */
  onOpenNote: (id: string, at?: string) => void;
  /** An organization a row is about, opened (settings/OrganizationSheet.tsx). */
  onOpenOrganization: (orgId: string) => void;
  /** Settings at Account, from the signed-out words. */
  onAccount: () => void;
}

/** Each kind's mark at the start of its row, from the kit. */
const MARKS: Record<Kind, ReactNode> = {
  invite: <Mail size={18} strokeWidth={2} aria-hidden="true" />,
  'invite-accepted': <UserCheck size={18} strokeWidth={2} aria-hidden="true" />,
  'invite-declined': <UserX size={18} strokeWidth={2} aria-hidden="true" />,
  'member-joined': <UserPlus size={18} strokeWidth={2} aria-hidden="true" />,
  'member-left': <UserMinus size={18} strokeWidth={2} aria-hidden="true" />,
  'member-removed': <UserMinus size={18} strokeWidth={2} aria-hidden="true" />,
  'role-changed': <Crown size={18} strokeWidth={2} aria-hidden="true" />,
  'org-renamed': <Pencil size={18} strokeWidth={2} aria-hidden="true" />,
  'org-deleted': <Trash2 size={18} strokeWidth={2} aria-hidden="true" />,
  'note-created': <FilePlus size={18} strokeWidth={2} aria-hidden="true" />,
  'note-edited': <PenLine size={18} strokeWidth={2} aria-hidden="true" />,
  'note-appended': <ListPlus size={18} strokeWidth={2} aria-hidden="true" />,
  'journal-entry': <BookOpen size={18} strokeWidth={2} aria-hidden="true" />,
  'rule-added': <ScrollText size={18} strokeWidth={2} aria-hidden="true" />,
  'summary-written': <AudioLines size={18} strokeWidth={2} aria-hidden="true" />,
  'sync-conflict': <TriangleAlert size={18} strokeWidth={2} aria-hidden="true" />,
};

/** The kinds about an organization, whose row opens it; an invitation is answered on its own row instead. */
const ORG_KINDS: ReadonlySet<Kind> = new Set<Kind>(['invite-accepted', 'invite-declined', 'member-joined', 'member-left', 'member-removed', 'role-changed', 'org-renamed']);

export function NotificationsScreen({ onBack, onOpenNote, onOpenOrganization, onAccount }: NotificationsScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  useWispEdge(scroller, 'notifications', topBar);
  useBack(true, onBack);
  const account = useAccount();
  const prefs = usePreferences();
  const { list: orgs } = useOrgs();
  const all = useNotifications();
  // A sealed row opening is told through the feed's listeners, not through the list, which is the same rows still:
  // the page redraws on every word from the feed, so a row drawn by its kind gets its words a moment later.
  const [, redraw] = useReducer((n: number) => n + 1, 0);
  useEffect(() => onNotifications(redraw), []);
  const shown = all.filter((n) => isWanted(n, prefs.notifications));
  const unread = unreadCount(prefs.notifications, all);
  const signedIn = Boolean(account.session);
  const held = !signedIn || prefs.localOnly;

  // Opened: the feed taken again now, so what arrived while the app was away is here before the page is read.
  useEffect(() => {
    if (!held) void syncNotificationsNow();
  }, [held]);

  const open = (n: Notification) => {
    if (n.readAt === null) markRead(n.id);
    const details = openDetails(n);
    if (details) {
      onOpenNote(details.noteId, details.kind === 'note-edited' ? details.at : undefined);
      return;
    }
    // An organization the person is still in; a row about one they left or that is gone only reads.
    if (ORG_KINDS.has(n.kind) && n.org && orgs.some((row) => row.id === n.org!.id && row.state === 'member')) onOpenOrganization(n.org.id);
  };

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <button type="button" className={styles.back} onClick={onBack} aria-label="Back to home">
          <ArrowLeft size={20} aria-hidden="true" />
        </button>
        <h1 className={styles.title}>
          Notifications
          {unread ? <span className={styles.count}>{unread}</span> : null}
        </h1>
        {unread ? (
          <button type="button" className={`app-word ${styles.readAll}`} onClick={markAllRead}>
            <CheckCheck size={16} strokeWidth={2.2} aria-hidden="true" />
            Mark all read
          </button>
        ) : null}
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          {held ? (
            <p className={styles.held}>
              {signedIn ? (
                <>
                  <GoWord onPress={onAccount}>Local only</GoWord> is on, so nothing arrives until it is off.
                </>
              ) : (
                <>
                  Notifications come with an account: an invitation to a team, what Claude wrote, a meeting written up. Sign in under <GoWord onPress={onAccount}>Account</GoWord>.
                </>
              )}
            </p>
          ) : shown.length === 0 ? (
            <div className={styles.empty}>
              <Ghost scene="all-ticked" size="lead" className={styles.emptyArt} />
              <p className={styles.emptyLead}>Nothing yet.</p>
              <p className={styles.emptyHint}>Invitations, what Claude wrote and your meetings written up arrive here.</p>
            </div>
          ) : (
            <ol className={styles.rows} aria-label="Notifications">
              {shown.map((n, i) => (
                <Row key={n.id} n={n} index={i} onOpen={() => open(n)} />
              ))}
            </ol>
          )}
        </div>
      </div>
      {held ? null : <PullToRefresh scroller={scroller} onRefresh={syncNotificationsNow} />}
    </div>
  );
}

/** One notification: its mark, its sentence and the line under it, when, and Accept and Decline for an invitation. */
function Row({ n, index, onOpen }: { n: Notification; index: number; onOpen: () => void }) {
  const opened = openDetails(n);
  const sentence = sentenceOf(n, opened);
  const detail = detailOf(opened);
  const pending = n.kind === 'invite' && n.state === 'pending';
  const answered = n.kind === 'invite' && !pending ? (n.state === 'accepted' ? 'Accepted' : 'Declined') : null;
  return (
    <li className={styles.row} style={{ '--i': Math.min(index, 12) } as CSSProperties} data-unread={n.readAt === null || undefined} data-kind={n.kind}>
      <button type="button" className={styles.body} onClick={onOpen}>
        <span className={styles.mark}>{MARKS[n.kind]}</span>
        <span className={styles.words}>
          <span className={styles.sentence}>{sentence}</span>
          {detail ? <span className={styles.detail}>{detail}</span> : null}
          {answered ? <span className={styles.detail}>{answered}</span> : null}
        </span>
        <span className={styles.when}>{when(n.at)}</span>
      </button>
      {pending && n.org ? (
        <div className={styles.actions}>
          <InviteActions orgId={n.org.id} />
        </div>
      ) : null}
    </li>
  );
}
