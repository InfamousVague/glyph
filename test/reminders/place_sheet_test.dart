// Remind me at a place's sheet (lib/reminders/place_sheet.dart) and the search behind it (lib/core/geocode.dart
// `geocodeSearch`): the search sent, never typed, as the app, a second apart; what it finds named as a reverse lookup
// names a place; the places the note already has; here; and Local only, which offers no search. Nothing here asks
// OpenStreetMap.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/geocode.dart';
import 'package:ghost_md/reminders/place_sheet.dart';
import 'package:ghost_md/reminders/place_syntax.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../settings/support.dart';

/// Target in Hickory, as Nominatim's search answers with `format=jsonv2&addressdetails=1`: the shape of its answer,
/// written out here.
const String targets = '''
[{"lat":"35.7002","lon":"-81.3084","addresstype":"shop","name":"Target",
  "display_name":"Target, 1960, US 70, Hickory, Catawba County, North Carolina, 28602, United States",
  "address":{"shop":"Target","road":"US 70","city":"Hickory","state":"North Carolina","country":"United States"}},
 {"lat":"91","lon":"0","name":"Nowhere"},
 {"lat":"35.9","lon":"-81.5","addresstype":"shop","name":"Target","display_name":"Target, Lenoir, North Carolina",
  "address":{"shop":"Target","town":"Lenoir","state":"North Carolina"}}]''';

FetchResponse body(int status, String text) => FetchResponse(status, headers: const <String, String>{'content-type': 'application/json'}, bytes: Uint8List.fromList(utf8.encode(text)));

void main() {
  group('the search', () {
    test('asks Nominatim’s search for the words, eight at most', () {
      expect(searchUrl('  Target   Hickory ').toString(), 'https://nominatim.openstreetmap.org/search?format=jsonv2&q=Target+Hickory&limit=8&addressdetails=1');
      expect(() => searchUrl('   '), throwsA(isA<GeocodeError>()));
    });

    test('names each place found as a reverse lookup does, and leaves out what is not on Earth', () {
      final hits = searchHits(jsonDecode(targets));
      expect([for (final hit in hits) (hit.name, hit.lat, hit.lon)], [('Target, Hickory', 35.7002, -81.3084), ('Target, Lenoir', 35.9, -81.5)]);
      expect(hits.first.address, startsWith('Target, 1960, US 70, Hickory'));
      expect(() => searchHits({'error': 'no'}), throwsA(isA<GeocodeError>()));
    });

    test('asks as the app, in the phone’s language, and a second after the last ask', () async {
      final asked = <FetchRequest>[];
      final waits = <Duration>[];
      var clock = 1000;
      final search = geocodeSearch((request) async {
        asked.add(request);
        return body(200, targets);
      }, lang: () => 'en-US', version: '2.1.2', now: () => clock, wait: (duration) async => waits.add(duration));
      expect(await search('Target'), hasLength(2));
      clock += 300;
      await search('Target Hickory');
      expect(waits, [const Duration(milliseconds: 800)]);
      expect(asked.first.headers['User-Agent'], 'GhostMd/2.1.2 (https://ghostmarkdown.com)');
      expect(asked.first.headers['Accept-Language'], 'en-US');
      expect(asked.last.url.queryParameters['q'], 'Target Hickory');
    });

    test('a refusal or no answer is said', () async {
      expect(geocodeSearch((_) async => body(429, '[]'))('Target'), throwsA(isA<GeocodeError>().having((e) => e.message, 'message', 'OpenStreetMap answered 429.')));
      expect(geocodeSearch((_) async => throw const SocketLike())('Target'), throwsA(isA<GeocodeError>()));
    });
  });

  group('the note’s places', () {
    test('its place lines and its to-dos’ pins, each once, not in code', () {
      final body = [
        '# Errands',
        '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)',
        '- [ ] Buy diapers 📍 [Target](geo:35.7002,-81.3084)',
        '- [ ] Buy wipes 📍 [Target](geo:35.7002,-81.3084)',
        '```',
        '- [ ] Code 📍 [Costco](geo:35.7301,-81.3399)',
        '```',
      ].join('\n');
      expect([for (final mark in placesInNote(body)) mark.name], ['Cais do Sodré, Lisbon', 'Target']);
    });
  });

  group('the sheet', () {
    Future<PlaceMark?> pick(WidgetTester tester, {required String body, PlaceSearch? search, HerePlace? here, bool localOnly = false, required Future<void> Function() then}) async {
      PlaceMark? picked;
      var done = false;
      await pumpSettings(tester, PlaceSheet(body: body, search: search, here: here, localOnly: localOnly, onDone: (mark) {
        picked = mark;
        done = true;
      }));
      await tester.pumpAndSettle();
      await then();
      expect(done, isTrue);
      return picked;
    }

    testWidgets('a place searched for, sent from the field, picked from what it found', (tester) async {
      final searched = <String>[];
      final picked = await pick(
        tester,
        body: '- [ ] Buy diapers',
        search: (query) async {
          searched.add(query);
          return searchHits(jsonDecode(targets));
        },
        then: () async {
          await tester.enterText(find.byType(EditableText), 'Target');
          await tester.pump();
          expect(searched, isEmpty, reason: 'never as it is typed');
          await tester.tap(find.text('Search'));
          await tester.pumpAndSettle();
          expect(searched, ['Target']);
          await tester.tap(find.text('Target, Lenoir'));
          await tester.pumpAndSettle();
        },
      );
      expect(picked, PlaceMark.at(35.9, -81.5, name: 'Target, Lenoir'));
      await endSettings(tester);
    });

    testWidgets('a place the note has, or here', (tester) async {
      final fromNote = await pick(tester, body: '[Target](geo:35.7002,-81.3084)\n- [ ] Buy diapers', then: () async {
        expect(find.text('IN THIS NOTE'), findsOneWidget);
        await tester.tap(find.text('Target'));
        await tester.pumpAndSettle();
      });
      expect(fromNote, PlaceMark.at(35.7002, -81.3084, name: 'Target'));
      await endSettings(tester);
      final here = await pick(tester, body: '- [ ] Buy diapers', here: () async => PlaceMark.at(35.1, -81.2, name: 'Main Street, Hickory'), then: () async {
        await tester.tap(find.text('Here'));
        await tester.pumpAndSettle();
      });
      expect(here?.name, 'Main Street, Hickory');
      await endSettings(tester);
    });

    testWidgets('under Local only, no search, and it says why; Cancel picks nothing', (tester) async {
      final picked = await pick(tester, body: '- [ ] Buy diapers', localOnly: true, then: () async {
        expect(find.byType(SheetField), findsNothing);
        expect(find.textContaining('Searching for a place is off while Local only is on'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
      expect(picked, isNull);
      await endSettings(tester);
    });
  });
}

/// A connection that never came.
class SocketLike implements Exception {
  const SocketLike();
}
