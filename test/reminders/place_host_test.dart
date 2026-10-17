// The channel `ghost_md/places` (lib/reminders/place_host.dart, android/…/reminders/Places.kt), heard by a phone of
// the test's own: each method's name and what it carries, and what an answer is read as. And the permission's steps
// (lib/reminders/place_access.dart): the location while in use first, the app's own words, then "all the time".

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/reminders/place_access.dart';
import 'package:ghost_md/reminders/place_host.dart';
import 'package:ghost_md/reminders/place_plan.dart';

import '../support/fake_places.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('the channel', () {
    final calls = <MethodCall>[];
    Object? Function(MethodCall call) answer = (_) => null;
    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(placesChannel, (call) async {
        calls.add(call);
        return answer(call);
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(placesChannel, null));

    test('set carries the whole set as a list of places; clear carries nothing', () async {
      answer = (_) => true;
      final host = PhonePlaceHost(android: true);
      final places = placesIn([Note(id: 'a', body: '# Errands\n- [ ] Buy diapers 📍 [Target](geo:35.7002,-81.3084)', createdAt: 1, updatedAt: 1)]);
      expect(await host.set(places), isTrue);
      expect(await host.clear(), isTrue);
      expect([for (final call in calls) call.method], ['set', 'clear']);
      expect(calls.first.arguments, [
        {
          'id': places.single.id,
          'lat': 35.7002,
          'lon': -81.3084,
          'radius': 150.0,
          'title': 'Buy diapers — you’re at Target',
          'text': 'Errands',
          'place': 'Target',
          'noteId': 'a',
          'line': 2,
          'words': 'Buy diapers',
        },
      ]);
      expect(calls.last.arguments, isNull);
    });

    test('the access read from its word, each prompt asked by name', () async {
      final words = {'access': 'whileUsing', 'askForeground': 'approximate', 'askBackground': 'always'};
      answer = (call) => words[call.method];
      final host = PhonePlaceHost(android: true);
      expect(await host.access(), PlaceAccess.whileUsing);
      expect(await host.askForeground(), PlaceAccess.approximate);
      expect(await host.askBackground(), PlaceAccess.always);
      for (final (said, read) in [('blocked', PlaceAccess.blocked), ('ask', PlaceAccess.ask), ('nonsense', PlaceAccess.ask)]) {
        expect(placeAccessOf(said), read);
      }
    });

    test('where the phone last was, or null for anything else; Settings opened', () async {
      answer = (call) => switch (call.method) {
        'lastKnown' => {'lat': 35.7, 'lon': -81.3},
        'openSettings' => true,
        _ => null,
      };
      final host = PhonePlaceHost(android: true);
      expect(await host.lastKnown(), (lat: 35.7, lon: -81.3));
      expect(await host.openSettings(), isTrue);
      answer = (_) => {'lat': 'north'};
      expect(await host.lastKnown(), isNull);
    });

    test('a phone with no half, or one that is not Android, answers nothing and is asked nothing', () async {
      messenger.setMockMethodCallHandler(placesChannel, null);
      final none = PhonePlaceHost(android: true);
      expect(await none.access(), isNull);
      expect(await none.set(const []), isFalse);
      expect(await none.askBackground(), PlaceAccess.ask);
      final mac = PhonePlaceHost(android: false);
      expect(await mac.access(), isNull);
      expect(await mac.lastKnown(), isNull);
    });

    test('a refusal from the phone is a false, not a throw', () async {
      messenger.setMockMethodCallHandler(placesChannel, (call) async => throw PlatformException(code: 'no'));
      expect(await PhonePlaceHost(android: true).set(const []), isFalse);
    });
  });

  group('the permission', () {
    test('each access’s next step', () {
      expect(placeStepFor(PlaceAccess.always), PlaceStep.done);
      expect(placeStepFor(PlaceAccess.ask), PlaceStep.askForeground);
      expect(placeStepFor(PlaceAccess.approximate), PlaceStep.askForeground);
      expect(placeStepFor(PlaceAccess.whileUsing), PlaceStep.explainBackground);
      expect(placeStepFor(PlaceAccess.blocked), PlaceStep.settings);
      expect([for (final access in PlaceAccess.values) placeAccessWarns(access)], [false, true, true, true, true]);
      expect(placeAccessWarns(null), isFalse);
      expect(placeAccessWords(PlaceAccess.always), isNull);
      expect(placeAccessWords(PlaceAccess.whileUsing), contains('Allow location all the time'));
    });

    test('never asked: the prompt while in use, the app’s words, then all the time', () async {
      final phone = FakePlaces()..now = PlaceAccess.ask;
      var explained = 0;
      final access = await PlaceAccessFlow(host: phone, explain: () async => (explained += 1) > 0).run();
      expect(access, PlaceAccess.always);
      expect(phone.asked, ['foreground', 'background']);
      expect(explained, 1);
      expect(placeWarning.value, isFalse);
    });

    test('the app’s words put away: nothing more is asked, and the chips warn', () async {
      final phone = FakePlaces()..now = PlaceAccess.whileUsing;
      expect(await PlaceAccessFlow(host: phone, explain: () async => false).run(), PlaceAccess.whileUsing);
      expect(phone.asked, isEmpty);
      expect(placeWarning.value, isTrue);
    });

    test('the prompt while in use refused: no words, no second prompt', () async {
      final phone = FakePlaces()
        ..now = PlaceAccess.ask
        ..afterForeground = PlaceAccess.ask;
      var explained = false;
      expect(await PlaceAccessFlow(host: phone, explain: () async => explained = true).run(), PlaceAccess.ask);
      expect(phone.asked, ['foreground']);
      expect(explained, isFalse);
    });

    test('approximate only: the prompt again for precise, then all the time; still approximate, it stops', () async {
      final phone = FakePlaces()..now = PlaceAccess.approximate;
      expect(await PlaceAccessFlow(host: phone, explain: () async => true).run(), PlaceAccess.always);
      expect(phone.asked, ['foreground', 'background']);
      final stays = FakePlaces()
        ..now = PlaceAccess.approximate
        ..afterForeground = PlaceAccess.approximate;
      expect(await PlaceAccessFlow(host: stays, explain: () async => true).run(), PlaceAccess.approximate);
      expect(stays.asked, ['foreground']);
    });

    test('allowed already: nothing asked; refused for good: nothing asked either, and the chips warn', () async {
      final allowed = FakePlaces();
      expect(await PlaceAccessFlow(host: allowed, explain: () async => true).run(), PlaceAccess.always);
      expect(allowed.asked, isEmpty);
      final blocked = FakePlaces()..now = PlaceAccess.blocked;
      expect(await PlaceAccessFlow(host: blocked, explain: () async => true).run(), PlaceAccess.blocked);
      expect(blocked.asked, isEmpty);
      expect(placeWarning.value, isTrue);
    });

    test('no phone half: nothing', () async {
      final none = FakePlaces()..now = null;
      expect(await PlaceAccessFlow(host: none, explain: () async => true).run(), isNull);
      expect(none.asked, isEmpty);
    });
  });
}
