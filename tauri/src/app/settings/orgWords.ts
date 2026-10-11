import type { Role } from '../core/orgs/types.ts';

/**
 * The words the organization pages share (settings/OrganizationsPane.tsx, settings/OrganizationSheet.tsx, the home
 * page's card): a role as a row reads it, and a count of members. A `.ts` beside the pages, as the findables are, so
 * the pages export only components.
 */

/** A role, as a row reads it under an organization's name. */
export function roleWords(role: Role): string {
  return role === 'owner' ? 'Owner' : role === 'admin' ? 'Admin' : 'Member';
}

/** How many have joined, as a row reads it. */
export function memberWords(count: number): string {
  return count === 1 ? '1 member' : `${count} members`;
}
