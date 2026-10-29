// Links that opened the app (lib/share/app_links.dart). A port of `src/app/share/appLinks.test.ts`, case for case,
// with the native side as a `LinkSource` the test drives; then the sorting the web does in `shell/useAppLinks.ts`,
// and what a share link and an invite do once sorted (`App.tsx` `forkFromLink`, `notes/JoinSheet.tsx`).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/orgs/join_links.dart';
import 'package:ghost_md/share/app_links.dart';
import 'package:ghost_md/share/share.dart';

import 'support.dart';

final share = 'ghostmd://fork#${'a' * 22}.${'b' * 43}';
const noteLink = 'ghostmd://note/m1';
const code = 'AbCdEfGhIjKlMnOpQrSt_-';

/// The native side, as a test drives it.
class Native implements LinkSource {
  final List<List<String>> kept = [];
  String? activity;
  bool failing = false;
  final StreamController<void> heard = StreamController<void>.broadcast(sync: true);

  @override
  Future<List<String>> take() async {
    if (failing) {
      failing = false;
      throw StateError('an older binary');
    }
    return kept.isEmpty ? const [] : kept.removeAt(0);
  }

  @override
  String? takeActivityLink() {
    final link = activity;
    activity = null;
    return link;
  }

  @override
  Stream<void> get arrived => heard.stream;
}

class Door implements AppLinkDoor {
  final List<String> did = [];
  Object? failure;

  @override
  Future<void> fork(String link) async {
    did.add('fork $link');
    if (failure != null) throw failure!;
  }

  @override
  void join(String code) => did.add('join $code');

  @override
  Future<void> openNote(String id) async => did.add('note $id');

  @override
  void openPlace(LinkedPlace place) => did.add(switch (place) { NotificationsPlace() => 'notifications', OrganizationPlace(:final orgId) => 'org $orgId', MarketPlace() => 'market $place' });
}

void main() {
  group('a note link', () {
    test('names the note the notification’s tap opens, and nothing else does', () {
      expect(readNoteLink('ghostmd://note/m1'), 'm1');
      expect(readNoteLink(' ghostmd://note/abc_DEF-123/ '), 'abc_DEF-123');
      expect(readNoteLink('ghostmd://note/'), isNull);
      expect(readNoteLink('ghostmd://note/a b'), isNull);
      expect(readNoteLink('ghostmd://note/../x'), isNull);
      expect(readNoteLink(share), isNull);
      expect(readNoteLink('https://attack.fm/glyph/note/m1'), isNull);
    });
  });

  group('a place link', () {
    test('names the notifications drawer or an organization’s dashboard, and nothing else does', () {
      expect(readPlaceLink('ghostmd://notifications'), const NotificationsPlace());
      expect(readPlaceLink(' ghostmd://notifications/ '), const NotificationsPlace());
      expect(readPlaceLink('ghostmd://org/$code'), const OrganizationPlace(code));
      expect(readPlaceLink('ghostmd://org/'), isNull);
      expect(readPlaceLink('ghostmd://org/a b'), isNull);
      expect(readPlaceLink('ghostmd://org/${'x' * 65}'), isNull);
      expect(readPlaceLink(noteLink), isNull);
    });

    // The website's market page opens each thing by its kind and id (landing/market.html; Matt, 2026-10-26: "add a
    // browsable marketplace listed under the plugins section on the website that deeplinks to the app").
    test('names the Market, a shelf of it, or one plugin, theme or font on it', () {
      expect(readPlaceLink('ghostmd://market'), const MarketPlace());
      expect(readPlaceLink(' ghostmd://market/ '), const MarketPlace());
      expect(readPlaceLink('ghostmd://market/plugin/notion'), const MarketPlace(kind: MarketKind.plugin, id: 'notion'));
      expect(readPlaceLink('ghostmd://market/theme/dusk'), const MarketPlace(kind: MarketKind.theme, id: 'dusk'));
      expect(readPlaceLink('ghostmd://market/font/lora/'), const MarketPlace(kind: MarketKind.font, id: 'lora'));
      expect(readPlaceLink('ghostmd://market/plugin/place-reminders'), const MarketPlace(kind: MarketKind.plugin, id: 'place-reminders'));
      // A kind alone is its shelf, said either way; an id alone is whichever thing has it.
      expect(readPlaceLink('ghostmd://market/themes'), const MarketPlace(kind: MarketKind.theme));
      expect(readPlaceLink('ghostmd://market/plugin'), const MarketPlace(kind: MarketKind.plugin));
      expect(readPlaceLink('ghostmd://market/notion'), const MarketPlace(id: 'notion'));
      expect(readPlaceLink('ghostmd://market/plugin-x'), const MarketPlace(id: 'plugin-x'));
      // A page's query or fragment says nothing, and the case of the link is not the id's.
      expect(readPlaceLink('ghostmd://market/plugin/claude?from=site'), const MarketPlace(kind: MarketKind.plugin, id: 'claude'));
      expect(readPlaceLink('GHOSTMD://Market/Plugin/Claude'), const MarketPlace(kind: MarketKind.plugin, id: 'claude'));
      // Anything else is not the Market's.
      expect(readPlaceLink('ghostmd://market/widget/notion'), isNull);
      expect(readPlaceLink('ghostmd://market/plugin/a b'), isNull);
      expect(readPlaceLink('ghostmd://market/plugin/../x'), isNull);
      expect(readPlaceLink('ghostmd://market/plugin/notion/more'), isNull);
      expect(readPlaceLink('ghostmd://market/plugin/${'x' * 65}'), isNull);
      expect(readPlaceLink('ghostmd://marketplace'), isNull);
      expect(readPlaceLink('https://ghostmarkdown.com/market.html#plugin/notion'), isNull);
    });

    test('a Market link says itself as the link it was', () {
      for (final link in ['ghostmd://market', 'ghostmd://market/theme', 'ghostmd://market/plugin/notion', 'ghostmd://market/lora']) {
        expect(readPlaceLink(link).toString(), link);
      }
    });
  });

  group('links that opened the app', () {
    test('hands every link the native side kept to the opener, which sorts them', () async {
      final native = Native()..kept.add([share, noteLink, 'ghostmd://something-else']);
      final opened = <String>[];
      followAppLinks(opened.add, native);
      await pumpEventQueue();
      expect(opened, [share, noteLink, 'ghostmd://something-else']);
    });

    test('takes the link the activity was opened with as well, once, and the same link from both roads once', () async {
      final native = Native()
        ..activity = noteLink
        ..kept.add([noteLink]);
      final opened = <String>[];
      followAppLinks(opened.add, native);
      await pumpEventQueue();
      expect(opened, [noteLink]);
      // The plugin missed the next one; the activity did not.
      native.activity = 'ghostmd://note/m2';
      native.heard.add(null);
      await pumpEventQueue();
      expect(opened, [noteLink, 'ghostmd://note/m2']);
      // Nothing anywhere: nothing opened.
      native.heard.add(null);
      await pumpEventQueue();
      expect(opened, hasLength(2));
    });

    test('still takes the activity’s link when the native side cannot answer', () async {
      final native = Native()
        ..activity = noteLink
        ..failing = true;
      final opened = <String>[];
      followAppLinks(opened.add, native);
      await pumpEventQueue();
      expect(opened, [noteLink]);
    });

    test('takes again when another arrives while the app runs, and stops listening when asked', () async {
      final native = Native();
      final opened = <String>[];
      final stop = followAppLinks(opened.add, native);
      await pumpEventQueue();
      expect(opened, isEmpty);
      native.kept.add([share]);
      native.heard.add(null);
      await pumpEventQueue();
      expect(opened, [share]);
      stop();
      await pumpEventQueue();
      expect(native.heard.hasListener, isFalse);
      // A take that answers after the stop opens nothing.
      native.kept.add([share]);
      native.heard.add(null);
      await pumpEventQueue();
      expect(opened, hasLength(1));
    });
  });

  group('a link, sorted', () {
    test('is an invite by the app’s own scheme, a note, a place, or a share; and nothing else', () {
      expect(readAppLink('ghostmd://join/$code'), isA<JoinAppLink>().having((l) => l.code, 'code', code));
      expect(readAppLink(noteLink), isA<NoteAppLink>().having((l) => l.noteId, 'noteId', 'm1'));
      expect(readAppLink('ghostmd://notifications'), isA<PlaceAppLink>().having((l) => l.place, 'place', const NotificationsPlace()));
      expect(readAppLink(share), isA<ShareAppLink>().having((l) => (l.id, l.key), 'id and key', ('a' * 22, 'b' * 43)));
      expect(readAppLink('ghostmd://something-else'), isNull);
      // A bad code by the app's scheme is not an invite, and nothing else either.
      expect(readAppLink('ghostmd://join/short'), isNull);
    });

    test('goes to the door that does what it asks', () async {
      final door = Door();
      for (final link in ['ghostmd://join/$code', noteLink, 'ghostmd://org/o1', 'ghostmd://notifications', 'ghostmd://market/font/lora', share, 'ghostmd://something-else']) {
        openAppLink(link, door);
      }
      await pumpEventQueue();
      expect(door.did, ['join $code', 'note m1', 'org o1', 'notifications', 'market ghostmd://market/font/lora', 'fork $share']);
      // A door that fails is its own trouble, and is said.
      final failures = <Object>[];
      door.failure = const ShareError('That link reads nothing: the share was taken down.');
      openAppLink(share, door, onError: failures.add);
      await pumpEventQueue();
      expect(failures.single, isA<ShareError>());
    });
  });

  group('what a link does', () {
    late FakeService service;
    late Shares shares;
    late Pictures pictures;

    setUp(() async {
      service = await FakeService.start(seed: testAccount);
      final prefs = PreferencesStore()..startWithoutStorage();
      pictures = Pictures();
      shares = Shares(account: SignedAccount()..signIn(service), api: apiOf(service), crypto: service.crypto, prefs: prefs, pictures: pictures, listNotes: () async => const []);
    });

    test('a share link saves a copy into this library, pictures and all, and answers the note to open', () async {
      const a = 'aaaa1111-0000-4000-8000-000000000001.jpg';
      final book = note('b', bookNoteBody('Cabin trip', ['Packing']));
      final page = note('p', '# Packing\n\n![The tent](image/$a)');
      pictures.held[a] = jpeg(1);
      final link = await shares.shareNote(book, [book, page]);
      final key = readShareLink(link)!;
      pictures.held.clear();

      final saved = <String>[];
      final forked = await forkFromLink(
        'ghostmd://fork#${key.id}.${key.key}',
        shares: shares,
        notes: () async => [note('mine', '# Packing\n\nMy own.')],
        save: (body) async {
          saved.add(body);
          return note('s${saved.length}', body);
        },
      );
      expect(forked, isA<ForkedCopy>());
      expect(noteTitle((forked as ForkedCopy).note.body), 'Cabin trip');
      expect(saved.map(noteTitle), ['Cabin trip', 'Packing (shared)']);
      expect(pictures.keptNames, [a]);
      expect(pictures.held[a], jpeg(1));
    });

    // Matt, 2026-10-29: a meeting's own share link, posted to Slack once it was written up (lib/plugins/slack/
    // meetings.dart), opened from Slack's reader page with "Open in Ghost.md", saved "Engineering Standup (shared)" beside
    // the meeting, with no summary and no recording.
    group('a share of a note this library has opens that note, and saves no copy', () {
      Future<Note> never(String body) async => throw StateError('a copy was saved: ${noteTitle(body)}');
      final standup = note('m1', '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.\n\n## Transcript\n\n**Sam Lee:** Morning.');

      test('the account’s own share, made on this device or another, is known by its id: nothing is read', () async {
        final link = await shares.shareNote(standup, [standup]);
        final found = readShareLink(link)!;
        expect(shares.noteOfShare(found.id), 'm1');
        service.calls.clear();
        for (final given in ['ghostmd://fork#${found.id}.${found.key}', link]) {
          final forked = await forkFromLink(given, shares: shares, notes: () async => [standup], save: never);
          expect(forked, isA<ForkedOwn>().having((f) => f.noteId, 'note', 'm1'), reason: given);
        }
        expect(service.calls.where((call) => call.contains('shares/')), isEmpty, reason: 'the share is not read: the note is here');
      });

      test('someone else’s share of a note that is here too (a team’s) opens it, by the id the share carries', () async {
        final link = await shares.shareNote(standup, [standup]);
        // A member of the organization: another account, which made no share of its own.
        final member = Shares(account: SignedAccount()..signIn(service), api: apiOf(service), crypto: service.crypto, prefs: PreferencesStore()..startWithoutStorage(), pictures: Pictures(), listNotes: () async => const []);
        expect(member.noteOfShare(readShareLink(link)!.id), isNull);
        final forked = await forkFromLink(link, shares: member, notes: () async => [standup], save: never);
        expect(forked, isA<ForkedOwn>().having((f) => f.noteId, 'note', 'm1'));
      });

      test('a share of a note this library does not have is still saved as a copy, its title taken: "(shared)"', () async {
        final link = await shares.shareNote(standup, [standup]);
        final saved = <String>[];
        // The note gone from here (deleted for good), and another note by that title written since.
        final forked = await forkFromLink(link, shares: shares, notes: () async => [note('other', '# Engineering Standup\n\nMy own.')], save: (body) async {
          saved.add(body);
          return note('copy', body);
        });
        expect(forked, isA<ForkedCopy>());
        expect(saved.map(noteTitle), ['Engineering Standup (shared)']);
      });

      test('a share carries its note’s id, sealed with it: a meeting’s share is sent again once for it, any other is not', () async {
        final shared = sharedOf(standup, [standup], at: 5);
        expect(shared.note, 'm1');
        expect(shared.toJson()['note'], 'm1');
        final crypto = service.crypto;
        final key = newShareKey(crypto);
        final opened = await openShare(crypto, await sealShare(crypto, shared, key), key);
        expect(opened.note, 'm1');
        final older = Shared(kind: shared.kind, title: shared.title, pages: shared.pages, at: shared.at);
        expect(shareDigest(older), shareDigest(shared));
        // A meeting's, posted to the team's Slack channel: sent again, so a member's app opens the meeting from it.
        const turns = {'ms': 4000, 'turns': <Object?>[]};
        expect(shareDigest(older.withMeeting(turns)), isNot(shareDigest(shared.withMeeting(turns))));
        // A book carries the book's.
        final book = note('b', bookNoteBody('Cabin trip', ['Packing']));
        expect(sharedOf(book, [book, note('p', '# Packing')]).note, 'b');
      });
    });

    test('an invite link given where a share was asked for is an invite, and nothing is read', () async {
      service.calls.clear();
      Future<Note> never(String body) async => throw StateError('nothing is saved');
      for (final link in [inviteUrl(code), 'ghostmd://join/$code', code]) {
        final forked = await forkFromLink(link, shares: shares, notes: () async => const [], save: never);
        expect(forked, isA<ForkedInvite>().having((f) => f.code, 'code', code), reason: link);
      }
      expect(service.calls, isEmpty);
      await expectLater(forkFromLink('ghostmd://something-else', shares: shares, notes: () async => const [], save: never), throwsA(isA<ShareError>()));
    });

    test('an invite is held on this device, and asked about once someone is signed in', () {
      final kept = MemoryStored();
      expect(joinToAsk(signedIn: true, kept: kept), isNull);
      // Followed signed out: held, and not asked about yet.
      expect(takeJoin(code, now: 1000, kept: kept), code);
      expect(joinToAsk(signedIn: false, now: 2000, kept: kept), isNull);
      // Signed in: asked about, until it is let go, and never a week later.
      expect(joinToAsk(signedIn: true, now: 2000, kept: kept), code);
      expect(joinToAsk(signedIn: true, now: 1000 + 7 * 24 * 3600000, kept: kept), isNull);
      dropHeldJoin(kept: kept);
      expect(joinToAsk(signedIn: true, now: 2000, kept: kept), isNull);
    });
  });
}
