import type { MarkAction, MarkDetails, MarkDetailsProvider } from '../../core/markDetails.ts';
import { detailsCache } from '../detailsCache.ts';
import { asIssue, canWriteIssues, isIssueUrl, issueAt, issueBrief, issueFields, issueState, readIssue, setIssueOpen, type Issue } from './issues.ts';
import { host } from './manifest.ts';

/**
 * A linked item's issue, read back from GitHub: whether it is open, who has
 * it, what it is labelled, for the pill on the item and the card a tap opens
 * (core/markDetails.ts).
 *
 * The stage is the plain thing GitHub says: open is to do, closed is done.
 * That is what makes the tick work both ways (editor/doneSync.ts): the
 * actions here are called `done` and `reopen`, so ticking the box in the note
 * closes the issue, and an issue closed on GitHub ticks the box the next time
 * the note is read.
 *
 * Reads are paced two at a time, an answer is fresh for 45 seconds so
 * scrolling a list doesn't re-read it, and the last answers are kept
 * (`glyph-github-issues`, at most 300) so a note opened offline still shows
 * the state its issues last had, with when it was read on the card: the
 * plugins' shared cache (plugins/detailsCache.ts), keyed by `issueKey`.
 */

/** The key an issue is kept under: its repo and number. */
export function issueKey(url: string): string | null {
  const at = issueAt(url);
  return at ? `${at.owner}/${at.repo}#${at.number}` : null;
}

/** What the card and the pill show for an issue. */
export function detailsOf(issue: Issue, readAt = Date.now()): MarkDetails {
  const closed = issue.state === 'closed';
  return {
    url: issue.url,
    title: issue.title,
    status: { label: issueState(issue), stage: closed ? 'done' : 'todo' },
    brief: issueBrief(issue),
    fields: issueFields(issue),
    editedAt: issue.updatedAt,
    readAt,
  };
}

const issues = detailsCache({ host, storageKey: 'glyph-github-issues', read: async (_key, url) => detailsOf(await readIssue(url)) });

/** Puts an issue into what is known without reading it: what `createIssue` just made. */
export function rememberIssue(issue: Issue): void {
  issues.keep(`${issue.owner}/${issue.repo}#${issue.number}`, detailsOf(issue));
}

export const githubDetails: MarkDetailsProvider = {
  peek(url) {
    const key = issueKey(url);
    return key ? issues.peek(key) : null;
  },
  want(url, fresh = false) {
    const key = issueKey(url);
    if (key) issues.want(key, url, fresh);
  },
  open: (url) => host.openUrl(url),
  // A GitHub issue pasted into a sentence reads the same as one Glyph sent.
  reads: isIssueUrl,
  actions(url) {
    const key = issueKey(url);
    const details = key ? issues.details(key) : undefined;
    if (!key || !details || !canWriteIssues()) return [];
    const closed = details.status?.stage === 'done';
    const action: MarkAction = {
      id: closed ? 'reopen' : 'done',
      label: closed ? 'Open again' : 'Close issue',
      icon: closed ? 'reopen' : 'done',
      busyLabel: closed ? 'Opening…' : 'Closing…',
      async run() {
        const issue = await setIssueOpen(url, closed);
        issues.keep(key, detailsOf(issue));
        return closed ? `#${issue.number} is open again.` : `#${issue.number} is closed.`;
      },
    };
    return [action];
  },
};

/** Turns GitHub's answer into what a card shows, without a request: for the tests. */
export const detailsFromRaw = (raw: Parameters<typeof asIssue>[0], owner: string, repo: string): MarkDetails => detailsOf(asIssue(raw, owner, repo));
