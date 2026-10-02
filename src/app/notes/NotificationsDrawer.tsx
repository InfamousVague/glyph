import { useEffect, useReducer, type CSSProperties, type ReactNode } from 'react';
import { AudioLines, BookOpen, CheckCheck, Crown, FilePlus, ListPlus, Mail, PenLine, Pencil, ScrollText, Trash2, TriangleAlert, UserCheck, UserMinus, UserPlus, UserX, X } from '@glacier/icons';
import { useAccount } from '../core/account/account.ts';
import { isWanted, markAllRead, markRead, onNotifications, openDetails, unreadCount, useNotifications } from '../core/notifications/feed.ts';
import { detailOf, sentenceOf, type Kind, type Notification } from '../core/notifications/kinds.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import { usePreferences } from '../core/preferences.ts';
import { syncNotificationsNow } from '../core/sync/engine.ts';
import { Ghost } from '../art/Ghost.tsx';
import { InviteActions } from '../settings/InviteActions.tsx';
import { GoWord } from '../settings/kit/settingsKit.tsx';
import { FloatingCard } from './FloatingCard.tsx';
import { when } from './when.ts';
import styles from './NotificationsDrawer.module.css';

/**
 * The notifications, in a drawer hung from the bell (docs/TEAMS.md; Matt: "implement a full notification system and put
 * the invites in there with an inline accept and deny also wire up existing features to notifications where it makes
 * sense so that we see things like claude creating a new note or making edits"). It was a page in the pane, as All notes
 * is; Matt: "revamp the notifications make it all in a drawer instead of full screen, also the items in the list are
 * clipped right now. and don't render 100% width". So it is the floating card the notes drawer and the aside are
 * (notes/FloatingCard.tsx), at the right under the bell (notes/NoteTabs.tsx), a little wider than theirs and never the
 * window's width: the page stays live beside it, and a tap outside it, Escape, the back gesture or the bell again
 * closes it.
 *
 * Its head is the name with the count of unread, Mark all read, and a close; under it the rows scroll inside the card.
 * A row is its kind's mark, its sentence (core/notifications/kinds.ts `sentenceOf`, the one place the words live) wrapped
 * whole, the first line Claude changed under it on up to two lines, and when. An invitation carries Accept and Decline
 * inline (settings/InviteActions.tsx). A row about a note opens the note - an edit at its first changed line - and a
 * row about an organization opens the organization, each read as it is tapped and the drawer closed behind it. What
 * Settings › Notifications switched off, and a muted organization's news, is not drawn (`isWanted`); an invitation
 * always is. A sealed row is opened as it is drawn (`openDetails`) and redrawn with its words a moment later.
 *
 * Opening the drawer takes the feed again (core/sync/engine.ts `syncNotificationsNow`). Signed out, or with Local only
 * on, nothing arrives, and the drawer says so with a word that goes to Account.
 */

interface NotificationsDrawerProps {
  onClose: () => void;
  /** A note a row is about, opened: `at` is the line an edit landed on, as the note screen takes it (shell/screen.ts). */
  onOpenNote: (id: string, at?: string) => void;
  /** An organization a row is about, opened (notes/OrganizationScreen.tsx). */
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

export function NotificationsDrawer({ onClose, onOpenNote, onOpenOrganization, onAccount }: NotificationsDrawerProps) {
  const account = useAccount();
  const prefs = usePreferences();
  const { list: orgs } = useOrgs();
  const all = useNotifications();
  // A sealed row opening is told through the feed's listeners, not through the list, which is the same rows still:
  // the drawer redraws on every word from the feed, so a row drawn by its kind gets its words a moment later.
  const [, redraw] = useReducer((n: number) => n + 1, 0);
  useEffect(() => onNotifications(redraw), []);
  const shown = all.filter((n) => isWanted(n, prefs.notifications));
  const unread = unreadCount(prefs.notifications, all);
  const signedIn = Boolean(account.session);
  const held = !signedIn || prefs.localOnly;

  // Opened: the feed taken again now, so what arrived while the app was away is here before the drawer is read.
  useEffect(() => {
    if (!held) void syncNotificationsNow();
  }, [held]);

  const open = (n: Notification) => {
    if (n.readAt === null) markRead(n.id);
    const details = openDetails(n);
    if (details) {
      onClose();
      onOpenNote(details.noteId, details.kind === 'note-edited' ? details.at : undefined);
      return;
    }
    // An organization the person is still in; a row about one they left or that is gone only reads.
    if (ORG_KINDS.has(n.kind) && n.org && orgs.some((row) => row.id === n.org!.id && row.state === 'member')) {
      onClose();
      onOpenOrganization(n.org.id);
    }
  };

  return (
    <FloatingCard side="end" wide label="Notifications" toggle="[data-notifications-toggle]" onClose={onClose}>
      <div className={styles.panel}>
        <header className={styles.head}>
          <h2 className={styles.title}>
            Notifications
            {unread ? <span className={styles.count}>{unread}</span> : null}
          </h2>
          {unread ? (
            <button type="button" className={`app-word ${styles.readAll}`} onClick={markAllRead}>
              <CheckCheck size={15} strokeWidth={2.2} aria-hidden="true" />
              Mark all read
            </button>
          ) : null}
          <button type="button" className={styles.close} onClick={onClose} aria-label="Close notifications" title="Close">
            <X size={16} strokeWidth={2.2} aria-hidden="true" />
          </button>
        </header>
        <div className={styles.scroll}>
          {held ? (
            <p className={styles.held}>
              {signedIn ? (
                <>
                  <GoWord
                    onPress={() => {
                      onClose();
                      onAccount();
                    }}
                  >
                    Local only
                  </GoWord>{' '}
                  is on, so nothing arrives until it is off.
                </>
              ) : (
                <>
                  Notifications come with an account: an invitation to a team, what Claude wrote, a meeting written up. Sign in under{' '}
                  <GoWord
                    onPress={() => {
                      onClose();
                      onAccount();
                    }}
                  >
                    Account
                  </GoWord>
                  .
                </>
              )}
            </p>
          ) : shown.length === 0 ? (
            <div className={styles.empty}>
              <Ghost scene="all-ticked" size="small" className={styles.emptyArt} />
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
    </FloatingCard>
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
