import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Copy, Link2, Share2, X } from '@glacier/icons';
import { SegmentedControl } from '@glacier/react';
import { notYet } from '../core/account/api.ts';
import { failureText } from '../core/failure.ts';
import { inviteUrl, LIFETIMES, linkName, linkTermsWords, USES } from '../core/orgs/joinLinks.ts';
import { dropInviteLink, listInviteLinks, makeInviteLink } from '../core/orgs/orgs.ts';
import type { InviteLink } from '../core/orgs/types.ts';
import styles from './InviteLinks.module.css';

/**
 * Invite by link, for the owner and admins (docs/TEAMS.md; core/orgs/joinLinks.ts): the organization's working links,
 * each to copy, send or turn off, and a new one made for a day, a week, thirty days or for good, for one person, a
 * few, or anyone who has it. Matt: "add the ability to invite people to a team by link". Shown on the organization's
 * Members page (settings/OrganizationSheet.tsx) and under its dashboard's invite field (notes/OrganizationScreen.tsx).
 *
 * A link made is copied at once, as a share link is (share/ShareRows.tsx), since sending it is why it was made. The
 * service's refusals are said under the rows in its own words.
 */
export function InviteLinks({ orgId, inset = false, around, now = Date.now }: {
  orgId: string;
  /**
   * The heading the panel sits under, drawn by the page around it. Given here rather than by the page, so that where
   * the service has no invite links the heading goes with the rest: drawn outside, it stood over nothing (Matt:
   * "Invite by link has no buttons or anything").
   */
  around?: (panel: ReactNode) => ReactNode;
  /** Inside a settings card (settings/kit), which pads its forms rather than its contents: padded as they are. */
  inset?: boolean;
  now?: () => number;
}) {
  const [links, setLinks] = useState<InviteLink[] | null>(null);
  // A service from before invite links (core/account/api.ts `notYet`): the page ships after the service, but a page
  // that reaches one first draws nothing here rather than a refusal.
  const [missing, setMissing] = useState(false);
  const [making, setMaking] = useState(false);
  const [lasts, setLasts] = useState('week');
  const [uses, setUses] = useState('any');
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<{ words: string; problem: boolean } | null>(null);

  const read = useCallback(async () => {
    try {
      setLinks(await listInviteLinks(orgId));
    } catch (failure) {
      if (notYet(failure)) {
        setMissing(true);
        return;
      }
      setLinks([]);
      setSaid({ words: failureText(failure), problem: true });
    }
  }, [orgId]);
  useEffect(() => {
    void read();
  }, [read]);

  const copy = async (code: string, words = 'The link is copied.') => {
    try {
      await navigator.clipboard.writeText(inviteUrl(code));
      setSaid({ words, problem: false });
    } catch {
      // A device that will not copy (a webview without the permission): the link itself, to select and copy by hand.
      setSaid({ words: `This device wouldn’t copy it. The link: ${inviteUrl(code)}`, problem: false });
    }
  };
  const canSend = typeof navigator !== 'undefined' && typeof navigator.share === 'function';
  const send = (code: string) => void navigator.share({ title: 'Join my team on Ghost.md', url: inviteUrl(code) }).catch(() => undefined);

  const make = async () => {
    setBusy(true);
    setSaid(null);
    try {
      const link = await makeInviteLink(orgId, {
        expiresIn: LIFETIMES.find((choice) => choice.value === lasts)?.seconds ?? null,
        maxUses: USES.find((choice) => choice.value === uses)?.uses ?? null,
      });
      setLinks((was) => [link, ...(was ?? [])]);
      setMaking(false);
      await copy(link.code, 'The link is made and copied. Anyone signed in who has it can join.');
    } catch (failure) {
      setSaid({ words: failureText(failure), problem: true });
    } finally {
      setBusy(false);
    }
  };

  const turnOff = async (link: InviteLink) => {
    setSaid(null);
    try {
      await dropInviteLink(orgId, link.id);
      setLinks((was) => (was ?? []).filter((l) => l.id !== link.id));
      setSaid({ words: 'The link is turned off. No one else can join by it.', problem: false });
    } catch (failure) {
      setSaid({ words: failureText(failure), problem: true });
    }
  };

  if (missing) return null;
  const panel = (
    <div className={styles.links} data-inset={inset || undefined}>
      {links === null ? (
        <p className={styles.quiet}>Reading the links…</p>
      ) : links.length ? (
        <ul className={styles.list} aria-label="Invite links">
          {links.map((link) => (
            <li key={link.id} className={styles.link}>
              <Link2 size={16} className={styles.mark} aria-hidden="true" />
              <span className={styles.words}>
                <span className={styles.url}>{linkName(link.code)}</span>
                <span className={styles.terms}>{linkTermsWords(link, now())}</span>
              </span>
              <button type="button" className={styles.icon} aria-label="Copy the link" title="Copy the link" onClick={() => void copy(link.code)}>
                <Copy size={16} aria-hidden="true" />
              </button>
              {canSend ? (
                <button type="button" className={styles.icon} aria-label="Send the link" title="Send the link" onClick={() => send(link.code)}>
                  <Share2 size={16} aria-hidden="true" />
                </button>
              ) : null}
              <button type="button" className={styles.icon} aria-label="Turn the link off" title="Turn the link off" onClick={() => void turnOff(link)}>
                <X size={16} aria-hidden="true" />
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className={styles.quiet}>No links yet. Make one to send to people who should join.</p>
      )}

      {making ? (
        <div className={styles.making}>
          <span className={styles.choice}>
            <span className={styles.choiceLabel}>Lasts</span>
            <SegmentedControl aria-label="How long the link lasts" fullWidth size="sm" options={LIFETIMES.map(({ value, label }) => ({ value, label }))} value={lasts} onValueChange={setLasts} />
          </span>
          <span className={styles.choice}>
            <span className={styles.choiceLabel}>Who</span>
            <SegmentedControl aria-label="How many can join by it" fullWidth size="sm" options={USES.map(({ value, label }) => ({ value, label }))} value={uses} onValueChange={setUses} />
          </span>
          <span className={styles.buttons}>
            <button type="button" className={styles.primary} disabled={busy} onClick={() => void make()}>
              {busy ? 'One moment…' : 'Make the link'}
            </button>
            <button type="button" className={styles.action} disabled={busy} onClick={() => setMaking(false)}>
              Cancel
            </button>
          </span>
        </div>
      ) : (
        <span className={styles.buttons}>
          <button
            type="button"
            className={styles.action}
            onClick={() => {
              setSaid(null);
              setMaking(true);
            }}
          >
            <Link2 size={14} aria-hidden="true" />
            New link
          </button>
        </span>
      )}

      {said ? (
        <p className={styles.said} role={said.problem ? 'alert' : 'status'}>
          {said.words}
        </p>
      ) : null}
    </div>
  );
  return around ? around(panel) : panel;
}
