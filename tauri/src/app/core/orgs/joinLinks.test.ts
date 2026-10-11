import { beforeEach, describe, expect, it } from 'vitest';
import { appJoinLink, dropHeldJoin, heldJoin, holdJoin, inviteUrl, linkName, linkTermsWords, readJoinLink } from './joinLinks.ts';
import type { InviteLink } from './types.ts';

/**
 * Invite links on this side (docs/TEAMS.md): the link as it is sent, the shapes it arrives in, the words a link's row
 * says, and the code held on this device while no one is signed in.
 */

const CODE = 'AbCdEfGhIjKlMnOpQrSt_-';

beforeEach(() => localStorage.clear());

describe('an invite link', () => {
  it('is the reader page with the code in its hash, and reads back from every shape it arrives in', () => {
    expect(inviteUrl(CODE)).toBe(`https://ghostmarkdown.com/read.html#join=${CODE}`);
    expect(appJoinLink(CODE)).toBe(`ghostmd://join/${CODE}`);
    for (const shape of [inviteUrl(CODE), `  ${inviteUrl(CODE)}  `, `https://attack.fm/glyph/#join=${CODE}`, `#join=${CODE}`, appJoinLink(CODE), `${appJoinLink(CODE)}/`, CODE]) {
      expect(readJoinLink(shape), shape).toBe(CODE);
    }
  });

  it('is nothing when it is a share link, a note link, or a code that could not be one', () => {
    for (const other of ['https://ghostmarkdown.com/read.html#abc.def', 'ghostmd://note/abc', 'ghostmd://join/short', '#join=has space here', 'join=' + CODE, '', 'x'.repeat(65)]) {
      expect(readJoinLink(other), other).toBeNull();
    }
  });

  it('is named on its row by the end of its code', () => {
    expect(linkName(CODE)).toBe('Link ending rSt_-');
  });
});

describe('a link’s row', () => {
  const link = (over: Partial<InviteLink>): InviteLink => ({ id: 'l', code: CODE, createdAt: 0, expiresAt: null, maxUses: null, uses: 0, by: 'matt', ...over });
  const HOUR = 3600_000;

  it('says how long it lasts and how many have used it', () => {
    expect(linkTermsWords(link({}), 0)).toBe('Lasts until turned off · none joined yet');
    expect(linkTermsWords(link({ uses: 3 }), 0)).toBe('Lasts until turned off · 3 joined');
    expect(linkTermsWords(link({ expiresAt: 5 * HOUR, maxUses: 5, uses: 2 }), 0)).toBe('Stops in 5 hours · 2 of 5 used');
    expect(linkTermsWords(link({ expiresAt: 7 * 24 * HOUR }), 0)).toBe('Stops in 7 days · none joined yet');
    expect(linkTermsWords(link({ expiresAt: 10 * 60_000 }), 0)).toBe('Stops in 1 hour · none joined yet');
  });
});

describe('a code held while signed out', () => {
  it('is kept until it is let go, and for a week at most', () => {
    expect(heldJoin()).toBeNull();
    holdJoin(CODE, 1000);
    expect(heldJoin(2000)).toBe(CODE);
    expect(heldJoin(1000 + 7 * 24 * 3600_000)).toBeNull();
    dropHeldJoin();
    expect(heldJoin(2000)).toBeNull();
  });
});
