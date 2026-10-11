import { accountState } from '../account/account.ts';
import { stampNow, type Stamp } from './format.ts';

/**
 * Who a comment is by: the account's handle, or `me` on a device with no account, as a version's author is
 * (core/versions/record.ts). Tracked per person (docs/SHARED.md, S8: "make sure replies and comments are tracked per
 * user in the organization"): every line of the fence names its author, so a member's comments can be counted and an
 * organization's log can say who commented.
 */
export function commentHandle(): string {
  return accountState().session?.handle ?? 'me';
}

/** This person, now: what a new comment, a reply or a resolution is stamped with. */
export function stampHere(now: Date = new Date()): Stamp {
  return { by: commentHandle(), at: stampNow(now) };
}
