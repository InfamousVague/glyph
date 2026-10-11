import type { ReactNode } from 'react';
import { Crown, Pencil, Trash2, UserCheck, UserMinus, UserPlus, UserX } from '@glacier/icons';
import type { Kind } from '../core/notifications/kinds.ts';

/**
 * An organization's own news, as its dashboard (OrganizationScreen.tsx) and its audit log (OrganizationLog.tsx) both
 * draw it from the feed (core/notifications/kinds.ts).
 */

/** The kinds that are the organization's news: an invitation is the invitee's, and is answered on its own row. */
export const NEWS: ReadonlySet<Kind> = new Set<Kind>(['invite-accepted', 'invite-declined', 'member-joined', 'member-left', 'member-removed', 'role-changed', 'org-renamed']);

/** Each kind of news's mark at the start of its row, from the kit, as the notifications drawer draws it. */
export const MARKS: Partial<Record<Kind, ReactNode>> = {
  'invite-accepted': <UserCheck size={17} strokeWidth={2} aria-hidden="true" />,
  'invite-declined': <UserX size={17} strokeWidth={2} aria-hidden="true" />,
  'member-joined': <UserPlus size={17} strokeWidth={2} aria-hidden="true" />,
  'member-left': <UserMinus size={17} strokeWidth={2} aria-hidden="true" />,
  'member-removed': <UserMinus size={17} strokeWidth={2} aria-hidden="true" />,
  'role-changed': <Crown size={17} strokeWidth={2} aria-hidden="true" />,
  'org-renamed': <Pencil size={17} strokeWidth={2} aria-hidden="true" />,
  'org-deleted': <Trash2 size={17} strokeWidth={2} aria-hidden="true" />,
};
