/**
 * An organization as the service describes it (docs/TEAMS.md; server/src/orgs.rs): a name, a hue, and rows of
 * people by handle, each with a role and whether they have joined yet. Plaintext on the service, as handles already
 * are - Matt: "create an organization in order to add users as team members by handle" - so another account's
 * invitation can reach this one; the notes stay sealed per account.
 *
 * A leaf: the shapes, and the one rule about an organization's workspace id, shared by core/workspaces.ts,
 * core/noteFolders.ts and the Organization screen without any of them importing the calls.
 */

export type Role = 'owner' | 'admin' | 'member';

/** Whether a row has joined, or is still looking at the invitation. */
export type MemberState = 'member' | 'invited';

/** One of the organizations the account is in, or invited to: what `GET orgs` lists. */
/**
 * What the organization key needs, as the list says it (docs/SHARED.md, S2): the generation in force (0 while none
 * has been made), whether this account holds a wrap at it, and how many members with a public key lack one.
 */
export interface KeyNeeds {
  generation: number;
  mine: boolean;
  missing: number;
}

export interface OrgRow {
  id: string;
  name: string;
  /** A workspace hue (core/workspaces.ts `WORKSPACE_HUES`), or null for the app's own ink. */
  hue: string | null;
  /** This account's role in it. */
  role: Role;
  /** Whether this account has joined, or is invited. */
  state: MemberState;
  /** How many have joined. */
  members: number;
  /** The handle that invited this account, for an invited row; null when that account is gone. */
  invitedBy?: string | null;
  createdAt: number;
  /** This account's colour in it (docs/SHARED.md, S7): the organization's override, else the account's own, else null. */
  colour?: string | null;
  /** Absent on a row kept by a build before keys: read as none made and nobody missing. */
  keys?: KeyNeeds;
}

export interface Member {
  handle: string;
  role: Role;
  state: MemberState;
  /** When they joined, or were invited, in ms. */
  since: number;
  invitedBy?: string | null;
  /** Their colour in this organization, or null for none (S7). */
  colour?: string | null;
  /** Their encryption public key, to wrap the organization key to (S3); null until a device of theirs made one. */
  pub?: string | null;
}

/** An organization in full: what `GET orgs/{id}` answers a member. */
export interface Org extends Omit<OrgRow, 'members'> {
  members: Member[];
}

/**
 * An invite link, as the owner and admins see it (server/src/store/org_links.rs): a code anyone signed in who holds it
 * may join with, until it expires, is used up or is turned off.
 */
export interface InviteLink {
  id: string;
  code: string;
  createdAt: number;
  /** When it stops working, in ms; null for when it is turned off. */
  expiresAt: number | null;
  /** How many may join by it; null for no limit. */
  maxUses: number | null;
  uses: number;
  /** The handle of who made it; null once their account is gone. */
  by: string | null;
}

/** What a working code says before it is followed: enough to ask "Join it?", and nothing about who is in it. */
export interface JoinPreview {
  org: { id: string; name: string; hue: string | null; members: number };
  by: string | null;
  /** Whether the caller is in it already. */
  member: boolean;
}

/** What this device keeps of the account's organizations: the list as the service last gave it. */
export interface OrgState {
  list: OrgRow[];
  /** When the list was last taken from the service, in ms; null for never. */
  at: number | null;
  /** The account's own colour (S7), as the list last said it; null, or absent from an older build's state, for none. */
  colour?: string | null;
}

/**
 * An organization's workspace has the deterministic id `org-<orgId>` (docs/TEAMS.md, D5): every device of every
 * member makes the same one, so a filing keyed by it survives whichever device's settings win a sync, and the id
 * says what the workspace is to a build that would strip any other field.
 */
const ORG_WORKSPACE = 'org-';

export function orgWorkspaceId(orgId: string): string {
  return `${ORG_WORKSPACE}${orgId}`;
}

/** The organization a workspace stands for, by its id; null for a personal workspace. */
export function orgIdOf(workspaceId: string): string | null {
  return workspaceId.startsWith(ORG_WORKSPACE) && workspaceId.length > ORG_WORKSPACE.length ? workspaceId.slice(ORG_WORKSPACE.length) : null;
}

/** Whether a workspace is an organization's: the id's prefix, which is the truth. */
export function isOrgWorkspace(workspace: { id: string }): boolean {
  return orgIdOf(workspace.id) !== null;
}
