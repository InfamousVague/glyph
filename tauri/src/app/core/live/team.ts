import * as Y from 'yjs';
import { accountState } from '../account/account.ts';
import { orgKeyOf } from '../orgs/orgKeys.ts';
import type { TeamDoc } from '../team/doc.ts';
import { holdRoom, releaseRoom } from './hub.ts';
import { meIn, PRESENCE_ROOM } from './presence.ts';
import { TeamRoom, type LiveDoc } from './teamRoom.ts';

/**
 * A team's rooms as the app opens them (docs/LIVE.md, "The team's rooms"): on the hub's one connection, as this
 * account, with the organization key this device holds. The room itself is teamRoom.ts, which the MCP connector
 * shares; it is said again here, so the screens and their tests import it from where they always have.
 */
export { lacks, TeamRoom, type LiveDoc, type Me, type RoomDeps } from './teamRoom.ts';

/**
 * A team note's room, for its editor: the document's changes and the carets of the members who have it open. Null
 * when this device cannot seal a word in it - signed out, or without the organization key yet.
 */
export function openTeamRoom(orgId: string, noteId: string, doc: LiveDoc): TeamRoom | null {
  const key = orgKeyOf(orgId);
  if (!key || !accountState().session) return null;
  return new TeamRoom(orgId, noteId, meIn(orgId), { key, doc, hold: holdRoom, release: releaseRoom });
}

/** The organization's own room: who is in the app and where (presence.ts holds one per organization). */
export function openPresenceRoom(orgId: string): TeamRoom | null {
  const key = orgKeyOf(orgId);
  if (!key || !accountState().session) return null;
  return new TeamRoom(orgId, PRESENCE_ROOM, meIn(orgId), { key, hold: holdRoom, release: releaseRoom });
}

/**
 * A caret from a member's presence (presence.ts `Caret`) as indexes in this device's copy of the document, or null
 * when it cannot be placed: the words it sat in are gone, or it was never in this document.
 */
export function caretIndexes(doc: Pick<TeamDoc, 'doc' | 'text'>, caret: { anchor: unknown; head: unknown }): { anchor: number; head: number } | null {
  const index = (at: unknown): number | null => {
    try {
      const absolute = Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(at), doc.doc);
      return absolute && absolute.type === doc.text ? absolute.index : null;
    } catch {
      return null;
    }
  };
  const anchor = index(caret.anchor);
  if (anchor === null) return null;
  return { anchor, head: index(caret.head) ?? anchor };
}
