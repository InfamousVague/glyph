// The core this piece ports, case for case where a case is about something ported: core/placeRefs.test.ts (reading and
// writing a place; `withoutPlaces` is the share's, test/share), core/linkPreview.test.ts, core/images.test.ts (the
// reference, and the browser's store as MemoryPictureStore; the phone's picker, the Mac's panel and HEIC are the
// shell's), core/clips.test.ts and the parts of core/location.test.ts that lib/core/location.dart has (the gates, a
// place's name for the +, where a tapped map goes).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/link_preview.dart';
import 'package:ghost_md/core/location.dart';
import 'package:ghost_md/core/place_refs.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/media/clip_refs.dart';

const String cais = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';

void main() {
  group('a place line', () {
    test('is a line whose words are one link to a geo: address', () {
      expect(placeOfLine(cais), const PlaceLine(GeoTag(lat: 38.7057, lon: -9.1446, place: 'Cais do Sodré, Lisbon'), 'Cais do Sodré, Lisbon'));
    });

    test('is read whatever the line’s lead: a bullet, a number, a box, a quote', () {
      for (final lead in const <String>['- ', '3. ', '- [ ] ', '> ', '> - ']) {
        expect(placeOfLine('$lead$cais')?.tag.lat, 38.7057, reason: lead);
      }
    });

    test('is rough when its coordinates have two decimals or fewer', () {
      expect(placeOfLine('[Roughly 38.71, -9.14](geo:38.71,-9.14)')?.tag, const GeoTag(lat: 38.71, lon: -9.14, rough: true));
    });

    test('names no place when its words are only the coordinates', () {
      expect(placeOfLine('[38.7057, -9.1446](geo:38.7057,-9.1446)')?.tag.place, isNull);
    });

    test('is not a link inside other words, two links, or coordinates out of range', () {
      expect(placeOfLine('Met at $cais'), isNull);
      expect(placeOfLine('$cais $cais'), isNull);
      expect(placeOfLine('[Nowhere](geo:91.0,10.0)'), isNull);
      expect(placeOfLine('[Nowhere](geo:10.0,-181.0)'), isNull);
      expect(placeOfLine('[A site](https://example.com)'), isNull);
      expect(placeOfLine('![](image/x.jpg)'), isNull);
    });
  });

  group('writing a place', () {
    test('writes the name, or the coordinates, as the link’s words', () {
      expect(placeMarkdown(const GeoTag(lat: 38.7057, lon: -9.1446), 'Cais do Sodré, Lisbon'), cais);
      expect(placeMarkdown(const GeoTag(lat: 38.7057, lon: -9.1446)), '[38.7057, -9.1446](geo:38.7057,-9.1446)');
      expect(placeMarkdown(const GeoTag(lat: 38.71, lon: -9.14, rough: true)), '[Roughly 38.71, -9.14](geo:38.71,-9.14)');
    });

    test('keeps a name from breaking the link: brackets and line breaks out, and no longer than a title', () {
      expect(cleanPlaceName('The [Old] Pier\nNorth'), 'The Old Pier North');
      expect(cleanPlaceName('x' * 120), hasLength(80));
      final written = placeMarkdown(const GeoTag(lat: 1, lon: 2), r'A ] name [ with \ marks');
      expect(placeOfLine(written)?.words, 'A name with marks');
    });

    test('reads back what it writes', () {
      const tag = GeoTag(lat: -33.8568, lon: 151.2153);
      expect(placeOfLine(placeMarkdown(tag, 'Sydney Opera House'))?.tag, tag.named('Sydney Opera House'));
    });
  });

  group('the places in a note', () {
    test('are its place lines, outside code', () {
      const body = '# Lisbon\n\n$cais\n\n```\n[Code](geo:1.0,2.0)\n```\n\n- [Belém](geo:38.6916,-9.2160)';
      expect(placeLines(body).map((place) => (place.line, place.words)).toList(), <(int, String)>[(3, 'Cais do Sodré, Lisbon'), (9, 'Belém')]);
    });

    test('name the one at the very top: the first line with words, or the one under the title, past the front matter', () {
      expect(topPlaceLine(<String>[cais, 'words']), 1);
      expect(topPlaceLine(<String>['# Lisbon', '', cais]), 3);
      expect(topPlaceLine(<String>['---', 'title: x', '---', '# Lisbon', cais]), 5);
      expect(topPlaceLine(<String>['# Lisbon', 'words', cais]), isNull);
      expect(topPlaceLine(<String>['```', cais, '```']), isNull);
    });
  });

  group('a link’s title', () {
    const day = 24 * 60 * 60000;
    const urlA = 'https://www.airbnb.com/rooms/1234';
    late MemoryStored stored;
    late List<String> asked;
    late int now;
    late int ready;
    Future<LinkPreview> Function(String url) answer = (url) async => LinkPreview(url: url, title: 'Title of $url', site: 'Site');
    var allowed = true;

    KeptLinkPreviews make({bool native = true}) {
      final links = KeptLinkPreviews(
        stored,
        fetch: native
            ? (url) {
                asked.add(url);
                return answer(url);
              }
            : null,
        canAsk: () => allowed,
        now: () => now,
      );
      links.addListener(() => ready += 1);
      return links;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() {
      stored = MemoryStored();
      asked = <String>[];
      now = 1000 * day;
      ready = 0;
      allowed = true;
      answer = (url) async => LinkPreview(url: url, title: 'Title of $url', site: 'Site');
    });

    test('is asked of the app once, kept, and drawn at once the next time', () async {
      final links = make();
      expect(links.previewFor(urlA), isNull);
      links.wantPreview(urlA);
      links.wantPreview(urlA);
      await settle();
      expect(asked, <String>[urlA]);
      expect(ready, 1);
      expect(links.previewFor(urlA), const LinkPreview(url: urlA, title: 'Title of $urlA', site: 'Site'));
      // A reload reads it back from storage.
      expect(make().previewFor(urlA)?.title, 'Title of $urlA');
    });

    test('is asked again after a week, and not before', () async {
      final links = make();
      links.wantPreview(urlA);
      await settle();
      now = 1000 * day + 7 * day - 1;
      links.wantPreview(urlA);
      await settle();
      expect(asked, hasLength(1));
      now = 1000 * day + 7 * day;
      links.wantPreview(urlA);
      await settle();
      expect(asked, hasLength(2));
    });

    test('is nothing after a failure, and is asked again a day later', () async {
      answer = (url) async => throw StateError('the site did not answer');
      final links = make();
      links.wantPreview(urlA);
      await settle();
      expect(links.previewFor(urlA), isNull);
      expect(ready, 1);
      now = 1000 * day + day - 1;
      links.wantPreview(urlA);
      await settle();
      expect(asked, hasLength(1));
      now = 1000 * day + day;
      links.wantPreview(urlA);
      await settle();
      expect(asked, hasLength(2));
    });

    test('is never asked where nothing can read a page, with previews off, or with Nothing leaves the phone on', () async {
      make(native: false).wantPreview('https://a.example/');
      allowed = false;
      make().wantPreview('https://c.example/');
      await settle();
      expect(asked, isEmpty);
      expect(ready, 0);
      expect(noLinkPreviews.previewFor(urlA), isNull);
    });

    test('keeps the three hundred most recently asked', () async {
      final links = make();
      for (var i = 0; i < 301; i += 1) {
        now = 1000 * day + i;
        links.wantPreview('https://example.com/$i');
        await settle();
      }
      final kept = jsonDecode(stored.getItem('glyph-link-previews') ?? '{}') as Map<String, dynamic>;
      expect(kept.keys, hasLength(300));
      expect(kept['https://example.com/0'], isNull);
      expect(kept['https://example.com/300'], isNotNull);
    });
  });

  group('an address as a card says it', () {
    test('names the site without www, and the path short', () {
      const urlA = 'https://www.airbnb.com/rooms/1234';
      expect(siteOf(urlA), 'airbnb.com');
      expect(siteOf('not a url'), 'not a url');
      expect(pathOf(urlA), '/rooms/1234');
      expect(pathOf('https://example.com/'), '');
      expect(pathOf('https://example.com/${'a' * 40}?q=1'), '/${'a' * 30}…');
      expect(pathOf('nonsense'), '');
      expect(siteOf('https://www.airbnb.com/rooms/1234?x=1'), 'airbnb.com');
      expect(pathOf('https://www.airbnb.com/rooms/1234?x=1'), '/rooms/1234?x=1');
      expect(pathOf('https://example.com/${'a' * 60}'), hasLength(32));
    });
  });

  group('pictures in notes', () {
    test('writes and reads back the relative reference', () {
      final md = imageMarkdown('a1b2.jpg', 'the cabin');
      expect(md, '![the cabin](image/a1b2.jpg)');
      expect(imageNames('# Trip\n\n$md\n\n![](image/c3d4.png)\n\n![](http://elsewhere/x.png)'), <String>['a1b2.jpg', 'c3d4.png']);
    });
  });

  group('a picture in a store with no files (the page in a browser)', () {
    late MemoryPictureStore store;
    late int ready;
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() {
      store = MemoryPictureStore();
      ready = 0;
      store.addListener(() => ready += 1);
    });

    test('is kept when pasted, under a name of its own, and drawn at once', () async {
      final name = await store.save(Uint8List(4096), type: 'image/png');
      expect(name, endsWith('.jpg'));
      expect(store.kept[name], hasLength(4096));
      // Seen this run, so the editor has it without waiting for the database.
      expect(store.pictureOf(name)?.bytes, isNotNull);
    });

    test('is blank while it is fetched from storage, then says so and is drawn', () async {
      store = MemoryPictureStore(<String, Uint8List>{'cabin.jpg': Uint8List.fromList(<int>[1])})..addListener(() => ready += 1);
      expect(store.pictureOf('cabin.jpg'), isNull);
      await settle();
      expect(ready, 1);
      expect(store.pictureOf('cabin.jpg')?.bytes, <int>[1]);
    });

    test('stays blank, and says nothing, when storage has no picture by that name', () async {
      expect(store.pictureOf('nowhere.jpg'), isNull);
      await settle();
      expect(ready, 0);
      expect(store.pictureOf('nowhere.jpg'), isNull);
    });

    test('keeps a picture that arrived by sync, typed by its name, and draws it wherever a page is waiting', () async {
      await store.keep('shot.png', Uint8List.fromList(<int>[9, 8, 7]));
      expect(imageTypeOf('shot.png'), 'image/png');
      expect(ready, 1);
      expect(store.pictureOf('shot.png')?.bytes, <int>[9, 8, 7]);
      expect(await store.bytesOf('shot.png'), <int>[9, 8, 7]);
      expect(await store.bytesOf('missing.png'), isNull);
    });

    test('draws a share’s lent pictures without keeping them', () {
      store.lend(<String, Uint8List>{'lent.webp': Uint8List.fromList(<int>[1, 2])});
      expect(store.pictureOf('lent.webp')?.bytes, <int>[1, 2]);
      expect(store.kept, isEmpty);
      expect(ready, 1);
      store.lend(const <String, Uint8List>{});
      expect(ready, 1);
    });

    test('says a build with no way to adopt a picture cannot add one', () {
      expect(() => store.adopt('/cache/x.jpg'), throwsA(isA<StateError>().having((e) => e.message, 'message', cannotAddPictures)));
    });
  });

  group('a voice memo in a note', () {
    test('is written as a mark that says how long it is', () {
      expect(clipMarkdown(startMs: 12000, endMs: 19500), '![voice 0:08](tape:12000-19500)');
      expect(clipMarkdown(startMs: 0, endMs: 125000), '![voice 2:05](tape:0-125000)');
      expect(clipLength(const Clip(startMs: 1000, endMs: 1400)), '0:00');
    });

    test('rounds times and never ends before it starts', () {
      expect(clipMarkdown(startMs: -50, endMs: 900.6), '![voice 0:01](tape:0-901)');
      expect(clipMarkdown(startMs: 5000, endMs: 4000), '![voice 0:00](tape:5000-5000)');
    });

    test('is read back, and nothing else is', () {
      expect(parseClip('![voice 0:08](tape:12000-19500)'), const Clip(startMs: 12000, endMs: 19500));
      expect(parseClip('![a picture](image/abc.jpg)'), isNull);
      expect(parseClip('[notion](https://www.notion.so/x)'), isNull);
      expect(parseClip('![voice](tape:900-900)'), isNull);
      expect(parseClip('![voice](tape:9-x)'), isNull);
    });

    test('is found where it sits, bulleted or mid-sentence', () {
      const note = '- Milk ![voice 0:03](tape:0-3000)\n\nHe said ![voice 0:05](tape:8000-13000) and left.\n';
      final found = clipsIn(note);
      expect(found, hasLength(2));
      expect((found[0].startMs, found[0].endMs, found[0].tape), (0, 3000, null));
      expect(note.substring(found[1].from, found[1].to), '![voice 0:05](tape:8000-13000)');
      expect(hasClips('plain words'), isFalse);
    });

    test('says which tape it is a piece of, when it knows', () {
      expect(clipMarkdown(startMs: 1000, endMs: 4000, tape: 'k3f9x2'), '![voice 0:03](tape:1000-4000@k3f9x2)');
      expect(parseClip('![voice 0:03](tape:1000-4000@k3f9x2)'), const Clip(startMs: 1000, endMs: 4000, tape: 'k3f9x2'));
      // Nothing odd gets into a note's text.
      expect(clipMarkdown(startMs: 0, endMs: 1000, tape: 'no spaces here'), '![voice 0:01](tape:0-1000)');
    });

    test('plays only against the tape it was cut from', () {
      const mine = Clip(startMs: 0, endMs: 1000, tape: 'aaa');
      expect(playsOn(mine, 'aaa'), isTrue);
      expect(playsOn(mine, 'bbb'), isFalse);
      expect(playsOn(mine, null), isFalse);
      // A mark from before tapes were named plays against whatever recording the note has.
      expect(playsOn(const Clip(startMs: 0, endMs: 1000), 'aaa'), isTrue);
      expect(playsOn(const Clip(startMs: 0, endMs: 1000), null), isTrue);
    });
  });

  group('the tape a note holds', () {
    test('is remembered per note, and forgotten with the recording', () {
      final tapes = TapeIds(MemoryStored());
      expect(tapes.tapeId('a'), isNull);
      tapes.setTapeId('a', 'k3f9x2');
      tapes.setTapeId('b', 'zzz111');
      expect(tapes.tapeId('a'), 'k3f9x2');
      tapes.setTapeId('a', null);
      expect(tapes.tapeId('a'), isNull);
      expect(tapes.tapeId('b'), 'zzz111');
    });

    test('gets an id that is only ever compared with itself', () {
      expect(freshTapeId(), matches(RegExp(r'^[a-z0-9]{6,10}$')));
      expect(freshTapeId(), isNot(freshTapeId()));
    });
  });

  group('the gates', () {
    test('a fix is never asked under Local only, or where the device cannot find itself', () async {
      var localOnly = true;
      final none = Locations(localOnly: () => localOnly);
      expect(none.cannotLocate, LocateFailure.localOnly);
      await expectLater(() => none.locate(), throwsA(isA<LocateError>().having((e) => e.why, 'why', LocateFailure.localOnly)));
      localOnly = false;
      expect(none.cannotLocate, LocateFailure.none);
      expect(whyLocateFailed(const LocateError(LocateFailure.blocked)), LocateFailure.blocked);
      expect(whyLocateFailed(StateError('x')), LocateFailure.unavailable);
    });

    test('tiles are drawn with the switch on and never under Local only', () {
      var localOnly = false, tiles = true;
      final where = Locations(localOnly: () => localOnly, mapTiles: () => tiles);
      expect(where.canShowTiles, isTrue);
      tiles = false;
      expect(where.canShowTiles, isFalse);
      tiles = true;
      localOnly = true;
      expect(where.canShowTiles, isFalse);
    });

    test('a fix becomes a tag at four decimals, or two where it was rough', () {
      expect(tagOf(const Fix(lat: 51.507412, lon: -0.127812, accuracy: 20, at: 0)), const GeoTag(lat: 51.5074, lon: -0.1278));
      expect(tagOf(const Fix(lat: 51.507412, lon: -0.127812, accuracy: 2000, at: 0)), const GeoTag(lat: 51.51, lon: -0.13, rough: true));
    });
  });

  group('a place’s name for the + beside the line', () {
    const tag = GeoTag(lat: 51.5074, lon: -0.1278);
    PlaceAnswer square() => const PlaceAnswer(name: 'Trafalgar Square', address: <String, String?>{'city': 'London', 'road': 'Whitehall'});

    test('is asked once at three decimals, known after, and never asked again for a place that failed', () async {
      final asks = <(double, double, int)>[];
      var fail = false;
      final where = Locations(
        localOnly: () => false,
        lookup: ({required lat, required lon, required zoom}) async {
          asks.add((lat, lon, zoom));
          if (fail) throw StateError('offline');
          return square();
        },
        now: () => 0,
        wait: (_) async {},
      );
      expect(await Future.wait(<Future<String?>>[where.placeName(tag), where.placeName(tag)]), <String?>['Trafalgar Square, London', 'Trafalgar Square, London']);
      expect(asks, <(double, double, int)>[(51.507, -0.128, 15)]);
      expect(where.placeFor(tag), 'Trafalgar Square, London');
      expect(await where.placeName(tag), 'Trafalgar Square, London');
      expect(asks, hasLength(1));
      fail = true;
      const other = GeoTag(lat: 10.12, lon: 20.34, rough: true);
      expect(await where.placeName(other), isNull);
      expect(await where.placeName(other), isNull);
      expect(asks.last, (10.12, 20.34, 12));
      expect(asks, hasLength(2));
    });

    test('waits a second after the last ask, and asks nothing if asking stopped being allowed meanwhile', () async {
      var now = 0, localOnly = false;
      final waits = <Duration>[];
      var asks = 0;
      final where = Locations(
        localOnly: () => localOnly,
        lookup: ({required lat, required lon, required zoom}) async {
          asks += 1;
          return square();
        },
        now: () => now,
        wait: (wait) async {
          waits.add(wait);
          now += wait.inMilliseconds;
          localOnly = true;
        },
      );
      expect(await where.placeName(tag), isNotNull);
      expect(waits, isEmpty);
      expect(await where.placeName(const GeoTag(lat: 1.2345, lon: 2.3456)), isNull);
      expect(waits, <Duration>[const Duration(milliseconds: nominatimGapMs)]);
      expect(asks, 1);
    });

    test('reads a short name out of the answer: a named place or the road, then the settlement; never a house', () {
      expect(shortPlace(square(), false), 'Trafalgar Square, London');
      expect(shortPlace(const PlaceAnswer(name: 'The Laurels', addresstype: 'building', address: <String, String?>{'road': 'Rue de Rivoli', 'city': 'Paris'}), false), 'Rue de Rivoli, Paris');
      expect(shortPlace(const PlaceAnswer(address: <String, String?>{'village': 'Eidfjord', 'state': 'Vestland'}), true), 'Eidfjord, Vestland');
      expect(shortPlace(const PlaceAnswer(displayName: '12 High Street, Ambridge, Borsetshire'), false), 'High Street, Ambridge');
      expect(shortPlace(const PlaceAnswer(), false), isNull);
    });
  });

  group('where a tapped map goes', () {
    const named = GeoTag(lat: 51.5074, lon: -0.1278, place: 'Trafalgar Square, London');

    test('is the phone’s maps chooser, Apple Maps on the Mac, and openstreetmap.org everywhere else', () async {
      expect(placeUrl(named, MapsApp.androidGeo), 'geo:51.5074,-0.1278?q=51.5074,-0.1278(Trafalgar%20Square%2C%20London)');
      expect(placeUrl(named, MapsApp.appleMaps), 'https://maps.apple.com/?ll=51.5074,-0.1278&q=Trafalgar%20Square%2C%20London');
      expect(placeUrl(named), 'https://www.openstreetmap.org/?mlat=51.5074&mlon=-0.1278#map=15/51.5074/-0.1278');
      expect(placeUrl(const GeoTag(lat: 51, lon: -0.13, rough: true)), 'https://www.openstreetmap.org/?mlat=51&mlon=-0.13#map=12/51/-0.13');
      final opened = <String>[];
      await openPlace(named, (url) async => opened.add(url));
      expect(opened.single, startsWith('https://www.openstreetmap.org/'));
    });
  });
}
