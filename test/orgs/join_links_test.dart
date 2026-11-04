// Invite links on this side (lib/orgs/join_links.dart; docs/TEAMS.md). A port of
// `src/app/core/orgs/joinLinks.test.ts`: the link as it is sent, the shapes it arrives in, the words a link's row
// says, and the code held on this device while no one is signed in.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/orgs/join_links.dart';
import 'package:ghost_md/orgs/types.dart';

const code = 'AbCdEfGhIjKlMnOpQrSt_-';

void main() {
  group('an invite link', () {
    test('is the reader page with the code in its hash, and reads back from every shape it arrives in', () {
      expect(inviteUrl(code), 'https://ghostmarkdown.com/read.html#join=$code');
      expect(appJoinLink(code), 'ghostmd://join/$code');
      for (final shape in [inviteUrl(code), '  ${inviteUrl(code)}  ', 'https://attack.fm/glyph/#join=$code', '#join=$code', appJoinLink(code), '${appJoinLink(code)}/', code]) {
        expect(readJoinLink(shape), code, reason: shape);
      }
    });

    test('reads from the join page an emailed invitation links to (Matt, 2026-11-03), and nothing that only looks like it', () {
      expect(joinPageUrl(code), 'https://ghostmarkdown.com/join#$code');
      for (final shape in [joinPageUrl(code), 'https://ghostmarkdown.com/join/#$code', 'https://www.ghostmarkdown.com/join#$code', 'https://ghostmarkdown.com/join#join=$code', ' ${joinPageUrl(code)}\n']) {
        expect(readJoinLink(shape), code, reason: shape);
        expect(isJoinPageLink(shape), isTrue, reason: shape);
      }
      for (final other in ['https://evil.example/join#$code', 'http://ghostmarkdown.com/join#$code', 'https://ghostmarkdown.com.evil.example/join#$code', 'https://ghostmarkdown.com/joined#$code']) {
        expect(isJoinPageLink(other), isFalse, reason: other);
      }
      expect(readJoinLink('https://ghostmarkdown.com/join#short'), isNull);
    });

    test('is nothing when it is a share link, a note link, or a code that could not be one', () {
      for (final other in ['https://ghostmarkdown.com/read.html#abc.def', 'ghostmd://note/abc', 'ghostmd://join/short', '#join=has space here', 'join=$code', '', 'x' * 65]) {
        expect(readJoinLink(other), isNull, reason: other);
      }
    });

    test('is named on its row by the end of its code', () {
      expect(linkName(code), 'Link ending rSt_-');
    });
  });

  group('a link’s row', () {
    InviteLink link({int? expiresAt, int? maxUses, int uses = 0}) => InviteLink(id: 'l', code: code, expiresAt: expiresAt, maxUses: maxUses, uses: uses, by: 'matt');
    const hour = 3600000;

    test('says how long it lasts and how many have used it', () {
      expect(linkTermsWords(link(), 0), 'Lasts until turned off · none joined yet');
      expect(linkTermsWords(link(uses: 3), 0), 'Lasts until turned off · 3 joined');
      expect(linkTermsWords(link(expiresAt: 5 * hour, maxUses: 5, uses: 2), 0), 'Stops in 5 hours · 2 of 5 used');
      expect(linkTermsWords(link(expiresAt: 7 * 24 * hour), 0), 'Stops in 7 days · none joined yet');
      expect(linkTermsWords(link(expiresAt: 10 * 60000), 0), 'Stops in 1 hour · none joined yet');
    });

    test('offers the lifetimes and the uses the service takes', () {
      expect(lifetimes.map((each) => each.seconds), [86400, 7 * 86400, 30 * 86400, null]);
      expect(uses.map((each) => each.uses), [1, 5, 25, null]);
    });
  });

  group('an invitation by email (Matt, 2026-11-03)', () {
    const minute = 60000, hour = 3600000;

    test('says when it was sent and when it stops', () {
      EmailInvite invite({int sentAt = 0, int? expiresAt}) => EmailInvite(id: 'e', email: 'kim@example.com', sentAt: sentAt, expiresAt: expiresAt);
      expect(emailTermsWords(invite(expiresAt: 14 * 24 * hour), 0), 'Sent just now · Stops in 14 days');
      expect(emailTermsWords(invite(expiresAt: 14 * 24 * hour), 5 * minute), 'Sent 5 minutes ago · Stops in 14 days');
      expect(emailTermsWords(invite(expiresAt: 14 * 24 * hour), 3 * hour), 'Sent 3 hours ago · Stops in 14 days');
      expect(emailTermsWords(invite(expiresAt: 14 * 24 * hour), 3 * 24 * hour), 'Sent 3 days ago · Stops in 11 days');
      expect(emailTermsWords(invite(), minute), 'Sent 1 minute ago');
    });

    test('takes an address people type, and nothing that is not one', () {
      for (final ok in ['kim@example.com', ' Kim.Lee+team@mail.example.co.uk ']) {
        expect(looksLikeEmail(ok), isTrue, reason: ok);
      }
      for (final no in ['', 'kim', 'kim@', '@example.com', 'kim@example', 'kim smith@example.com', 'kim@@example.com', 'kim@example.c0m']) {
        expect(looksLikeEmail(no), isFalse, reason: no);
      }
    });
  });

  group('a code held while signed out', () {
    test('is kept until it is let go, and for a week at most', () {
      final kept = MemoryStored();
      expect(heldJoin(kept: kept), isNull);
      holdJoin(code, now: 1000, kept: kept);
      expect(heldJoin(now: 2000, kept: kept), code);
      expect(heldJoin(now: 1000 + 7 * 24 * 3600000, kept: kept), isNull);
      dropHeldJoin(kept: kept);
      expect(heldJoin(now: 2000, kept: kept), isNull);
    });

    test('is not kept when it could not be a code', () {
      final kept = MemoryStored({heldJoinKey: '{"code":"short","at":1000}'});
      expect(heldJoin(now: 2000, kept: kept), isNull);
    });
  });
}
