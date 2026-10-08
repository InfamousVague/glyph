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
  void openPlace(LinkedPlace place) => did.add(switch (place) { NotificationsPlace() => 'notifications', OrganizationPlace(:final orgId) => 'org $orgId' });
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
      for (final link in ['ghostmd://join/$code', noteLink, 'ghostmd://org/o1', 'ghostmd://notifications', share, 'ghostmd://something-else']) {
        openAppLink(link, door);
      }
      await pumpEventQueue();
      expect(door.did, ['join $code', 'note m1', 'org o1', 'notifications', 'fork $share']);
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
