// A share follows its pictures as well as its pages, and where a note was written stays out of it (lib/share/share.dart
// `Shares`). A port of `src/app/share/refresh.test.ts`, case for case, with the account's shares going through the
// service in memory where the web's test stands in for the call: a picture that reaches the sharing device after the
// share went, by sync, changes no page, so the share has to remember which it lacked and go again when one arrives -
// and only then. The last group is this port's own: the three seconds after a save, stopping, and reading by a link.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/share/share.dart';

import 'support.dart';

const picture = 'aaaa1111-0000-4000-8000-000000000001.jpg';

/// This device: its notes, its pictures, its settings, and its shares on the service.
class Here {
  Here(this.service, {bool signedIn = true}) {
    prefs.startWithoutStorage();
    account = SignedAccount();
    if (signedIn) account.signIn(service);
    shares = Shares(account: account, api: apiOf(service), crypto: service.crypto, prefs: prefs, pictures: pictures, listNotes: () async => notes);
  }
  final FakeService service;
  final PreferencesStore prefs = PreferencesStore();
  final Pictures pictures = Pictures();
  final List<Note> notes = [];
  late final SignedAccount account;
  late final Shares shares;

  /// Every share written to the service, in order.
  List<String> get puts => [for (final call in service.calls) if (call.startsWith('PUT shares/')) call];

  String keyOf(String noteId) => readShareLink(shares.linkFor(noteId)!)!.key;

  /// What the service holds for a note's share, opened as a reader would.
  Future<Shared> held(String noteId) => openShare(service.crypto, service.shares[prefs.value.shares[noteId]!.id]!.blob, keyOf(noteId));
}

void main() {
  late FakeService service;
  late Here here;

  setUp(() async {
    service = await FakeService.start(seed: testAccount);
    here = Here(service);
  });

  group('a share and the pictures it lacked', () {
    test('is sent again when a picture it lacked arrives, and not before or after', () async {
      final one = note('n1', '# Orders\n\n![The ticket](image/$picture)');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      expect(here.puts, hasLength(1));
      expect((await here.held('n1')).pictures, isNull);

      // Nothing changed and the picture is still not here: nothing goes.
      expect(await here.shares.refreshShares(), 0);

      // It arrives by sync: the share goes again, carrying it.
      here.pictures.held[picture] = Uint8List.fromList([0xff, 0xd8, 1, 2]);
      expect(await here.shares.refreshShares(), 1);
      expect((await here.held('n1')).pictures?[picture], [0xff, 0xd8, 1, 2]);

      // Sent with it: nothing more to send.
      expect(await here.shares.refreshShares(), 0);
      expect(here.puts, hasLength(2));
    });

    test('sends once more a share recorded before shares remembered what they lacked', () async {
      final one = note('n2', '# Words\n\nNo pictures.');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      // As 1.6.0-13 left it: the older digest, and no list.
      final kept = here.prefs.value.shares['n2']!;
      here.prefs.update((now) => now.copyWith(shares: {'n2': ShareEntry(id: kept.id, key: kept.key, sent: 'older')}));
      expect(await here.shares.refreshShares(), 1);
      expect(await here.shares.refreshShares(), 0);
    });
  });

  group('a share of a note that says where it was written', () {
    const tag = '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n';
    Future<String> sentBody(String noteId) async => (await here.held(noteId)).pages[0].body;

    test('sends the words without the tag, and the tag only once the note says to carry it', () async {
      final one = note('n1', '$tag# Walk\n\nThe river.');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      // What the server holds, opened as a reader would: no location, no place.
      expect(await sentBody('n1'), '# Walk\n\nThe river.');
      // Nothing changed: the tag's absence is what was sent, so nothing goes again.
      expect(await here.shares.refreshShares(), 0);
      // Ticked: sent again at once, carrying both keys.
      await here.shares.shareWithPlace('n1', on: true);
      expect(here.puts, hasLength(2));
      expect(await sentBody('n1'), '$tag# Walk\n\nThe river.');
      expect(here.prefs.value.shares['n1']?.place, isTrue);
      // Unticked: sent again without them.
      await here.shares.shareWithPlace('n1', on: false);
      expect(here.puts, hasLength(3));
      expect(await sentBody('n1'), '# Walk\n\nThe river.');
      expect(here.prefs.value.shares['n1']?.toJson().containsKey('place'), isFalse);
    });

    test('carries the tag and never a place added later, when only the tag was ticked', () async {
      final one = note('n3', '$tag# Walk\n\nThe river.');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      await here.shares.shareWithPlace('n3', on: true);
      // A place added with the + beside the line after the tick was given: the re-seal carries the tag, not the
      // place.
      here.notes[0] = one.copyWith(body: '$tag# Walk\n\nThe river.\n\n[Cais](geo:38.7057,-9.1446)\n\nThe bridge.');
      expect(await here.shares.refreshShares(), 1);
      final body = await sentBody('n3');
      expect(body, contains('location: 51.5074,-0.1278'));
      expect(body, isNot(contains('geo:')));
      expect(body, contains('The bridge.'));
    });

    test('carries the places once they are ticked, as a switch of their own that the settings keep', () async {
      final one = note('n4', '# Lisbon\n\n[Cais](geo:38.7057,-9.1446)');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      expect(await sentBody('n4'), '# Lisbon');
      expect(here.shares.sharingPlaces('n4'), isFalse);
      await here.shares.shareWithPlaces('n4', on: true);
      expect(await sentBody('n4'), '# Lisbon\n\n[Cais](geo:38.7057,-9.1446)');
      expect((here.prefs.value.shares['n4']?.places, here.prefs.value.shares['n4']?.place), (true, false));
      // Kept through the settings being read again, as another device reads them.
      here.prefs.value = Preferences.fromJson(here.prefs.value.toJson());
      expect(here.shares.sharingPlaces('n4'), isTrue);
      await here.shares.shareWithPlaces('n4', on: false);
      expect(await sentBody('n4'), '# Lisbon');
      expect(here.prefs.value.shares['n4']?.toJson().containsKey('places'), isFalse);
    });

    test('follows a tag added after the share went, without publishing it', () async {
      final one = note('n2', '# Walk\n\nThe river.');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      // "Add my location" on a note shared last week, or a tag arriving by sync: the words did not change for the
      // reader.
      here.notes[0] = one.copyWith(body: '$tag# Walk\n\nThe river.');
      expect(await here.shares.refreshShares(), 0);
      // A change to the words goes, still without the tag.
      here.notes[0] = one.copyWith(body: '$tag# Walk\n\nThe river, and the bridge.');
      expect(await here.shares.refreshShares(), 1);
      expect(await sentBody('n2'), '# Walk\n\nThe river, and the bridge.');
    });
  });

  group('the account’s shares', () {
    test('are listed with their links, read back by anyone holding one, and stopped', () async {
      final one = note('n1', '# Packing\n\n- [ ] Tent');
      here.notes.add(one);
      final link = await here.shares.shareNote(one, here.notes);
      final found = readShareLink(link)!;
      expect(here.shares.sharedLinks(), [(noteId: 'n1', link: link, id: found.id)]);
      expect(here.shares.linkFor('n1'), link);
      expect((await here.shares.sharesOnServer()).map((each) => each.id), [found.id]);
      // The service holds ciphertext, and says nothing of the note.
      expect(service.shares[found.id]!.blob, isNot(contains('Tent')));
      // A reader has no account: the link alone reads it.
      final reader = Here(service, signedIn: false);
      final read = await reader.shares.readShared(link);
      expect((read.kind, read.title, read.pages.single.body), ('note', 'Packing', '# Packing\n\n- [ ] Tent'));
      await expectLater(reader.shares.readShared('https://example.com/nothing'), throwsA(isA<ShareError>()));
      // Shared again, it is the same share and the same link.
      expect(await here.shares.shareNote(one.copyWith(body: '# Packing\n\n- [x] Tent'), here.notes), link);
      expect(service.shares, hasLength(1));
      await here.shares.stopSharing('n1');
      expect(service.shares, isEmpty);
      expect(here.shares.linkFor('n1'), isNull);
      expect(here.prefs.value.shares, isEmpty);
      await expectLater(reader.shares.readShared(link), throwsA(anything));
    });

    test('need an account to be made, and say so', () async {
      final signedOut = Here(service, signedIn: false);
      final one = note('n1', '# Words');
      await expectLater(signedOut.shares.shareNote(one, [one]), throwsA(isA<ShareError>().having((e) => e.message, 'message', startsWith('Sign in under Settings > Account to share'))));
      expect(service.shares, isEmpty);
      // And a share kept here goes nowhere signed out.
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      here.account.session = null;
      here.notes[0] = one.copyWith(body: '# Other words');
      expect(await here.shares.refreshShares(), 0);
    });

    testWidgets('are written again three seconds after the last of a run of saves, and once after launch', (tester) async {
      // The following keeps time with a timer, so this runs under the test binding's own clock: `pump` moves it.
      final one = note('n1', '# Words');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes);
      final saved = ValueNotifier<int>(0), changed = ValueNotifier<int>(0);
      var told = 0;
      here.shares.addListener(() => told += 1);
      here.shares.follow(saved: saved, changed: changed);
      here.shares.follow(saved: saved, changed: changed);
      // Once the app has settled: nothing changed, so nothing goes.
      await tester.pump(followWait * 4);
      expect(here.puts, hasLength(1));
      here.notes[0] = one.copyWith(body: '# Words, and more');
      for (var i = 0; i < 3; i += 1) {
        saved.value += 1;
        await tester.pump(const Duration(seconds: 2));
      }
      expect(here.puts, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(here.puts, hasLength(2));
      // Notes changed by sync: a chapter edited on another device reaches the share from here too.
      here.notes[0] = one.copyWith(body: '# Words from the Mac');
      changed.value += 1;
      await tester.pump(followWait);
      expect(here.puts, hasLength(3));
      // What was sent is kept in the settings, which tell whoever lists the shares.
      expect(told, greaterThanOrEqualTo(2));
      here.shares.dispose();
      saved.value += 1;
      await tester.pump(followWait);
      expect(here.puts, hasLength(3));
    });

    test('refuse what is more than a share can hold, in words a person can read', () async {
      final big = note('n1', '# Big\n\n${'x' * (shareLimit + 10)}');
      await expectLater(here.shares.shareNote(big, [big]), throwsA(isA<ShareError>().having((e) => e.message, 'message', startsWith('That is more than a share can hold'))));
      expect(here.prefs.value.shares, isEmpty);
    });
  });
}
