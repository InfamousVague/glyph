import type { Role } from '../orgs/types.ts';

/**
 * What a notification can be, and the one place its words live (docs/TEAMS.md, "Kinds").
 *
 * Matt: "implement a full notification system and put the invites in there with an inline accept and deny also wire
 * up existing features to notifications where it makes sense so that we see things like claude creating a new note
 * or making edits". Two shapes in one feed: the kinds the service makes about an organization (an invitation, who
 * joined, who left, a rename) carry their few words in the clear, since another account caused them; the kinds this
 * account makes for itself (Claude's writes through the MCP, a meeting written up, a note kept twice by a sync) are
 * sealed under the account key, the way a note is, with the kind inside the seal so that nothing outside it can
 * relabel one. Voice commands and the blanks the phone fills are the person's own act and already toasted, so they
 * are not recorded.
 *
 * The categories are what Settings › Notifications switches: an invitation is not switchable, since the person who
 * sent it is waiting for an answer.
 */

/** Made by the service, about an organization; the words it needs ride in `body`, in the clear. */
export const SERVER_KINDS = ['invite', 'invite-accepted', 'invite-declined', 'member-joined', 'member-left', 'member-removed', 'role-changed', 'org-renamed', 'org-deleted'] as const;
/** Made by this account for itself, sealed; the MCP server posts the first five, the app the last two. */
export const SELF_KINDS = ['note-created', 'note-edited', 'note-appended', 'journal-entry', 'rule-added', 'summary-written', 'sync-conflict'] as const;
export const KINDS = [...SERVER_KINDS, ...SELF_KINDS] as const;

export type ServerKind = (typeof SERVER_KINDS)[number];
export type SelfKind = (typeof SELF_KINDS)[number];
export type Kind = (typeof KINDS)[number];

export function isKind(value: unknown): value is Kind {
  return typeof value === 'string' && (KINDS as readonly string[]).includes(value);
}

export function isSelfKind(value: unknown): value is SelfKind {
  return typeof value === 'string' && (SELF_KINDS as readonly string[]).includes(value);
}

/** The four switches, in the order the pane draws them. `invites` is a category with no switch. */
export const CATEGORIES = ['team', 'claude', 'summaries', 'conflicts'] as const;
export type Category = (typeof CATEGORIES)[number] | 'invites';

const CATEGORY_OF: Record<Kind, Category> = {
  invite: 'invites',
  'invite-accepted': 'team',
  'invite-declined': 'team',
  'member-joined': 'team',
  'member-left': 'team',
  'member-removed': 'team',
  'role-changed': 'team',
  'org-renamed': 'team',
  'org-deleted': 'team',
  'note-created': 'claude',
  'note-edited': 'claude',
  'note-appended': 'claude',
  'journal-entry': 'claude',
  'rule-added': 'claude',
  'summary-written': 'summaries',
  'sync-conflict': 'conflicts',
};

export function categoryOf(kind: Kind): Category {
  return CATEGORY_OF[kind];
}

// --- what a sealed kind carries ------------------------------------------------------------

/** The note a self kind is about, and who wrote it ('Claude' when the MCP had no other name). */
interface AboutNote {
  noteId: string;
  title: string;
  by: string;
}

/**
 * The sealed payload of a self notification, by kind: `{ kind, ...details }` under the account key with
 * `notification:<id>` as its context (core/sync/crypto.ts). The kind inside is the one trusted; the row's plaintext
 * `kind` is for the service's pruning and this device's unread count, which never opens a seal.
 */
export type Details =
  | ({ kind: 'note-created' } & AboutNote)
  | ({
      kind: 'note-edited';
      /** A line diff: how many lines came and went, the first changed line (at most 120 characters) and its anchor. */
      added: number;
      removed: number;
      first: string;
      /** Where the first change is, as `Screen.note.at` takes it (shell/screen.ts): the line's anchor. */
      at: string;
    } & AboutNote)
  | ({ kind: 'note-appended'; lines: number; first: string } & AboutNote)
  | ({ kind: 'journal-entry'; journal: string; first: string } & AboutNote)
  | ({ kind: 'rule-added'; first: string } & AboutNote)
  | { kind: 'summary-written'; noteId: string; title: string }
  | { kind: 'sync-conflict'; noteId: string; title: string };

/** The details of one kind, without the kind: what `record(kind, details)` takes. */
export type DetailsOf<K extends SelfKind> = Omit<Extract<Details, { kind: K }>, 'kind'>;

/** Whether an opened payload has the shape of a self kind: a kind this build knows, about a note with a title. */
export function isDetails(value: unknown): value is Details {
  if (!value || typeof value !== 'object') return false;
  const { kind, noteId, title } = value as { kind?: unknown; noteId?: unknown; title?: unknown };
  return isSelfKind(kind) && typeof noteId === 'string' && typeof title === 'string';
}

// --- the row as it is kept ---------------------------------------------------------------

/** One notification as the service feeds it and this device keeps it (docs/TEAMS.md, "Shapes"). */
export interface Notification {
  id: string;
  /** The account's revision at which the row was last written; 0 for a self row this device has not sent yet. */
  rev: number;
  kind: Kind;
  /** When it happened, in ms. */
  at: number;
  readAt: number | null;
  hidden: boolean;
  /** The handle of who caused it; null when that account is gone ("someone"); absent for a self kind. */
  from?: string | null;
  /** The organization a server kind is about: its live name while the reader is a member, else the name in `body`. */
  org?: { id: string; name: string };
  /** A server kind's few words, in the clear. */
  body?: Record<string, unknown>;
  /** A self kind's payload, sealed: `Details`. */
  blob?: string;
  /** An invitation's answer, if any; `pending` until one is given. */
  state?: 'pending' | 'accepted' | 'declined';
}

// --- the words ------------------------------------------------------------------------

/** "sam", or "Someone" for an account that is gone. */
function who(from: string | null | undefined): string {
  return from ? from : 'Someone';
}

/** The organization's name: live while the reader is a member, else as the row remembers it. */
function orgName(n: Notification): string {
  const named = n.body?.name;
  return n.org?.name ?? (typeof named === 'string' ? named : 'an organization');
}

function text(value: unknown, fallback: string): string {
  return typeof value === 'string' && value ? value : fallback;
}

function roleWords(role: unknown): string {
  const r = role as Role;
  if (r === 'owner') return 'the owner';
  if (r === 'admin') return 'an admin';
  return 'a member';
}

function lines(count: number): string {
  return count === 1 ? '1 line' : `${count} lines`;
}

/**
 * The sentence a row reads as. `opened` is a self row's payload once this device has opened it, or null while it is
 * sealed, or could not be opened: then the row is drawn by its kind alone ("Claude edited a note"), and never stalls
 * on the seal (core/notifications/feed.ts `openDetails`).
 */
export function sentenceOf(n: Notification, opened: Details | null = null): string {
  const kind = opened?.kind ?? n.kind;
  switch (kind) {
    case 'invite':
      return `${who(n.from)} invited you to ${orgName(n)}`;
    case 'invite-accepted':
      return `${who(n.from)} accepted your invitation to ${orgName(n)}`;
    case 'invite-declined':
      return `${who(n.from)} declined your invitation to ${orgName(n)}`;
    case 'member-joined':
      return `${who(n.from)} joined ${orgName(n)}`;
    case 'member-left':
      return `${who(n.from)} left ${orgName(n)}`;
    case 'member-removed': {
      // The removed person is told the name (they are no longer a member, so the live name is not theirs to read);
      // the others are told who went.
      const handle = n.body?.handle;
      return typeof handle === 'string' ? `${who(n.from)} removed ${handle} from ${orgName(n)}` : `${who(n.from)} removed you from ${orgName(n)}`;
    }
    case 'role-changed':
      return `${who(n.from)} made you ${roleWords(n.body?.role)} of ${orgName(n)}`;
    case 'org-renamed':
      return `${who(n.from)} renamed ${text(n.body?.was, 'an organization')} to ${orgName(n)}`;
    case 'org-deleted':
      return `${who(n.from)} deleted ${orgName(n)}`;
    case 'note-created':
      return opened?.kind === 'note-created' ? `${opened.by} created ${opened.title}` : 'Claude created a note';
    case 'note-edited':
      return opened?.kind === 'note-edited' ? `${opened.by} edited ${opened.title} · ${lines(opened.added + opened.removed)} changed` : 'Claude edited a note';
    case 'note-appended':
      return opened?.kind === 'note-appended' ? `${opened.by} added ${lines(opened.lines)} to ${opened.title}` : 'Claude added to a note';
    case 'journal-entry':
      return opened?.kind === 'journal-entry' ? `${opened.by} wrote an entry in ${opened.title}` : 'Claude wrote a journal entry';
    case 'rule-added':
      return opened?.kind === 'rule-added' ? `${opened.by} added a rule to ${opened.title}` : 'Claude added a rule';
    case 'summary-written':
      return opened?.kind === 'summary-written' ? `A meeting was written up: ${opened.title}` : 'A meeting was written up';
    case 'sync-conflict':
      return opened?.kind === 'sync-conflict' ? `${opened.title} was kept twice: both devices had changed it` : 'A note was kept twice';
  }
}

/** The line under the sentence, when a self kind carries one: the first line Claude changed, added or wrote. */
export function detailOf(opened: Details | null): string | null {
  if (!opened) return null;
  if (opened.kind === 'note-edited' || opened.kind === 'note-appended' || opened.kind === 'journal-entry' || opened.kind === 'rule-added') return opened.first || null;
  return null;
}
