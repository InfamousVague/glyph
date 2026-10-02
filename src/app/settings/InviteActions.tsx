import { useEffect, useRef, useState } from 'react';
import { accountState } from '../core/account/account.ts';
import { answerInvite, feedState } from '../core/notifications/feed.ts';
import { syncNotificationsNow, syncStatusNow } from '../core/sync/engine.ts';
import styles from './InviteActions.module.css';

/**
 * Accept and Decline, inline, for an invitation to an organization (docs/TEAMS.md; Matt: "adding a team member should
 * show them an invite ... put the invites in there with an inline accept and deny"). One pair of words, drawn wherever
 * an invitation is: the row on the Notifications page (notes/NotificationsScreen.tsx), the card on the home page
 * (notes/Notices.tsx) and the row on Settings › Account › Organizations (OrganizationsPane.tsx), so the three cannot
 * drift apart.
 *
 * The answer is the feed's `answerInvite`: applied here at once - the invitation's rows say accepted or declined, the
 * organization's row and workspace follow - and replayed by a pass of the notifications and the organizations right
 * after (`syncNotificationsNow`), which also takes the list again so the new workspace is there. The pass never throws;
 * a refusal it met is in the sync status's words, and the answer it could not deliver is still queued, so the words
 * are shown under the buttons only while the queue still holds this organization's answer. "You were not invited."
 * is not shown: the feed reads it as answered from another device, and the fed row says which way.
 */

interface InviteActionsProps {
  orgId: string;
  /** After the pass that carried the answer, however it went: the page may want to move on (open the organization, say). */
  onAnswered?: (accepted: boolean) => void;
}

export function InviteActions({ orgId, onAnswered }: InviteActionsProps) {
  const [pending, setPending] = useState<boolean>(false);
  const [problem, setProblem] = useState<string | null>(null);
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  const answer = async (accept: boolean) => {
    setPending(true);
    setProblem(null);
    answerInvite(orgId, accept);
    await syncNotificationsNow();
    if (!alive.current) return;
    // Still queued after the pass: the service refused it, or could not be reached; its words say which.
    const session = accountState().session;
    const left = session ? feedState(session.accountId).marks.some((mark) => 'org' in mark && mark.org === orgId) : false;
    setPending(false);
    if (left) {
      setProblem(syncStatusNow().message ?? 'Not sent yet. It goes with the next sync.');
      return;
    }
    onAnswered?.(accept);
  };

  return (
    <span className={styles.actions} data-pending={pending || undefined}>
      <span className={styles.words}>
        <button type="button" className={`app-word ${styles.accept}`} disabled={pending} onClick={() => void answer(true)}>
          Accept
        </button>
        <button type="button" className={`app-word ${styles.decline}`} disabled={pending} onClick={() => void answer(false)}>
          Decline
        </button>
      </span>
      {problem ? (
        <span className={styles.problem} role="alert">
          {problem}
        </span>
      ) : null}
    </span>
  );
}
