import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/geotag.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/look.dart';
import 'package:ghost_md/core/note_names.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/note/byline.dart';
import 'package:ghost_md/note/height_memory.dart';
import 'package:ghost_md/note/note_place.dart';
import 'package:ghost_md/note/note_screen.dart' show withFrontMatterTitle;
import 'package:ghost_md/note/pinch_zoom.dart';
import 'package:ghost_md/note/version_history.dart';

/// The rules under a note's screen, each from the web module it ports: core/untouched.ts, core/geotag.ts,
/// core/noteNames.ts, core/look.ts, editor/heightMemory.ts, editor/notePlace.ts (its storage), editor/pinchZoom.ts,
/// core/authors.ts, and the words of editor/VersionHistory.tsx.
void main() {
  group('a note nobody has written in (core/untouched.ts)', () {
    const now = 1000000000000;
    UntouchedNotes notes([MemoryStored? kept]) => UntouchedNotes(kept: kept ?? MemoryStored(), clock: () => now);

    test('is untouched while its words are the words it was given, whatever its front matter says', () {
      final it = notes()..remember('a', const UntouchedRecord(title: 'Monday', words: '# Monday\n\n', at: now));
      expect(it.isUntouched('a', '# Monday\n\n'), isTrue);
      expect(it.isUntouched('a', '---\nlocation: 1.00,2.00\nlook: reading\n---\n# Monday\n'), isTrue, reason: 'a place or a look is not a word');
      expect(it.isUntouched('a', '# Monday\n\nMine.'), isFalse);
      expect(it.isUntouched('b', '# Monday\n\n'), isFalse, reason: 'no record');
    });

    test('is the person’s once it has a recording, a pin or an archive', () {
      final it = notes()..remember('a', const UntouchedRecord(title: 'T', words: 'T', at: now));
      expect(it.isUntouched('a', 'T', starred: true), isFalse);
      expect(it.isUntouched('a', 'T', recordingMs: 1200), isFalse);
      expect(it.isUntouched('a', 'T', archivedAt: now), isFalse);
    });

    test('keeps at most twenty, the newest, none older than a week, and forgets one that is the person’s', () {
      final kept = MemoryStored();
      final it = notes(kept);
      for (var n = 0; n < 25; n++) {
        it.remember('n$n', UntouchedRecord(title: 'T', words: 'T', at: now - n * 1000));
      }
      expect(it.records().length, 20);
      expect(it.recordOf('n0'), isNotNull);
      expect(it.recordOf('n24'), isNull);
      it.remember('old', const UntouchedRecord(title: 'T', words: 'T', at: now - 8 * 24 * 60 * 60000));
      expect(it.recordOf('old'), isNull);
      it.forget('n0');
      expect(it.recordOf('n0'), isNull);
      // Read by another run from the same storage, under the key the journal wrote first.
      expect(notes(kept).recordOf('n1')?.words, 'T');
      expect(kept.readText('glyph-entry-drafts'), isNotNull);
    });

    test('a record of another build’s shape is none', () {
      final kept = MemoryStored()..write('glyph-entry-drafts', {'a': {'title': 1}, 'b': {'title': 'T', 'words': 'W', 'at': now, 'journalId': 'j'}});
      expect(notes(kept).records().keys, ['b']);
      expect(notes(kept).recordOf('b')?.journalId, 'j');
    });

    test('a fresh note stays fresh through empty words and the app’s own, and is spoiled by the person’s', () {
      final it = notes()..markFresh('a');
      it.keepFresh('a', '');
      it.keepFresh('a', '---\nlook: map\n---\n  ');
      expect(it.isFresh('a'), isTrue);
      it.remember('a', const UntouchedRecord(title: 'Plans', words: '# Plans\n\n', at: now));
      it.keepFresh('a', '# Plans\n\n');
      expect(it.isFresh('a'), isTrue);
      it.keepFresh('a', '# Plans\n\nx');
      expect(it.isFresh('a'), isFalse);
      it.keepFresh('a', '');
      expect(it.isFresh('a'), isFalse, reason: 'typed in and emptied, it is never fresh again');
      expect(notes().isFresh('a'), isFalse, reason: 'kept in memory and nowhere else');
    });
  });

  group('where a note was written (core/geotag.ts)', () {
    test('is read from the two keys, rough when neither number has more than two decimals', () {
      expect(geoTagOf('---\nlocation: 38.7223,-9.1393\nplace: "Alfama, Lisbon"\n---\nWords'), const GeoTag(lat: 38.7223, lon: -9.1393, place: 'Alfama, Lisbon'));
      expect(geoTagOf('---\nlocation: [38.72, -9.14]\n---\n'), const GeoTag(lat: 38.72, lon: -9.14, rough: true));
      expect(geoTagOf('---\nlocation: "1,2"\n---\n')?.rough, isTrue);
      expect(geoTagOf('---\nlocation: somewhere\n---\n'), isNull);
      expect(geoTagOf('---\nlocation: 91,0\n---\n'), isNull);
      expect(geoTagOf('location: 1,2'), isNull, reason: 'no front matter');
    });

    test('is written into the front matter and taken out again, a block that held nothing else with it', () {
      const tag = GeoTag(lat: 38.7223, lon: -9.1393, place: 'Alfama,  Lisbon');
      final tagged = withGeoTag('# Here\n', tag);
      expect(tagged, '---\nlocation: 38.7223,-9.1393\nplace: "Alfama, Lisbon"\n---\n# Here\n');
      expect(geoTagOf(tagged), tag.named('Alfama, Lisbon'));
      expect(withGeoTag(tagged, null), '# Here\n');
      expect(withGeoTag('---\ntitle: T\n---\nx', const GeoTag(lat: 1, lon: 2, rough: true)), '---\ntitle: T\nlocation: 1.00,2.00\n---\nx');
      expect(withGeoTag(tagged, tag.named(null)), '---\nlocation: 38.7223,-9.1393\n---\n# Here\n', reason: 'a tag with no name takes the name off');
    });

    test('a fix is rounded to what it is good for, and said as its name or its numbers', () {
      expect(tagOf(const Fix(lat: 38.722252, lon: -9.139337, accuracy: 12, at: 0)), const GeoTag(lat: 38.7223, lon: -9.1393));
      expect(tagOf(const Fix(lat: 38.722252, lon: -9.139337, accuracy: 2500, at: 0)), const GeoTag(lat: 38.72, lon: -9.14, rough: true));
      expect(tagLabel(const GeoTag(lat: 38.72, lon: -9.14, rough: true)), 'Roughly 38.72, -9.14');
      expect(tagLabel(const GeoTag(lat: 38.7223, lon: -9.1393, place: 'Alfama')), 'Alfama');
      expect(sameTag(null, null), isTrue);
      expect(sameTag(const GeoTag(lat: 1, lon: 2), null), isFalse);
    });

    test('a geocoder’s answer becomes a few words: a road or a named place and its town, or for a rough tag the town and region', () {
      expect(shortPlace({'name': 'Miradouro', 'address': {'road': 'Rua A', 'city': 'Lisbon', 'country': 'Portugal'}}, rough: false), 'Miradouro, Lisbon');
      expect(shortPlace({'addresstype': 'building', 'name': '12', 'address': {'house_number': '12', 'road': 'Rua A', 'town': 'Sintra'}}, rough: false), 'Rua A, Sintra');
      expect(shortPlace({'address': {'city': 'Lisbon', 'state': 'Lisboa', 'country': 'Portugal'}}, rough: true), 'Lisbon, Lisboa');
      expect(shortPlace({'display_name': '12 Rua A, Alfama, Lisbon'}, rough: false), 'Rua A, Alfama');
      expect(shortPlace(const {}, rough: false), isNull);
    });
  });

  group('the names a blank page offers (core/noteNames.ts)', () {
    final at = DateTime(2026, 9, 28, 14, 5);

    test('are four, always in this order, the day in words first', () {
      final offers = nameOffers(at, const {});
      expect([for (final offer in offers) offer.name], ['Monday, 28 September 2026', '2026-09-28', '2026-09-28 14.05', '2026-W40']);
      expect([for (final offer in offers) offer.kind], NameKind.values);
      expect(offers[1].label, 'Name it for today, 2026-09-28.');
    });

    test('leave out a name another note has, the rest keeping their places', () {
      expect([for (final offer in nameOffers(at, {'monday 28 september 2026', '2026 w40'})) offer.kind], [NameKind.day, NameKind.minute]);
    });

    test('the day in words keys the day in English', () {
      expect(keysTheDay(at), isTrue);
      expect(keysTheDay(DateTime(2026, 1, 31)), isTrue);
    });

    group('in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);

      test('an American phone names the day with the month first', () {
        toldLocale = DateLocale.enUS;
        expect(longDate(at), 'Monday, September 28, 2026');
        expect(nameOffers(at, const {}).first.name, 'Monday, September 28, 2026');
        expect(keysTheDay(at), isTrue);
        // A note already named for the day in these words takes the offer away.
        expect([for (final offer in nameOffers(at, {'monday september 28 2026'})) offer.kind], [NameKind.day, NameKind.minute, NameKind.week]);
      });

      test('a British phone names it with the day first and no comma', () {
        toldLocale = DateLocale.enGB;
        expect(longDate(at), 'Monday 28 September 2026');
        expect(nameOffers(at, const {}).first.name, 'Monday 28 September 2026');
        expect(keysTheDay(at), isTrue);
        expect([for (final offer in nameOffers(at, {'monday 28 september 2026'})) offer.kind], [NameKind.day, NameKind.minute, NameKind.week]);
      });
    });
  });

  test('a look is one key with two values (core/look.ts)', () {
    expect(lookOf('---\nlook: Reading\n---\n# T'), Look.reading);
    expect(lookOf('---\nlook: fancy\n---\n# T'), isNull);
    expect(withLook('# T', Look.map), '---\nlook: map\n---\n# T');
    expect(withLook('---\nlook: map\n---\n# T', null), '# T');
  });

  test('a name is written first in the front matter, and an empty one takes the key off (core/frontMatter.ts)', () {
    expect(withFrontMatterTitle('{}', 'Plan'), '---\ntitle: "Plan"\n---\n{}');
    expect(withFrontMatterTitle('---\nbook: true\ntitle: Old\n---\n- [[One]]', 'New "name"'), '---\ntitle: "New \'name\'"\nbook: true\n---\n- [[One]]');
    expect(withFrontMatterTitle('---\ntitle: Old\n---\nx', '  '), 'x');
  });

  test('authors are read in order, none twice, and an AI the app knows wears the spark (core/authors.ts)', () {
    expect(authorsOf('---\nauthors: matt, "Claude", Matt\n---\n# T'), ['matt', 'Claude']);
    expect(authorsOf('# T'), isEmpty);
    expect(isKnownAi('claude'), isTrue);
    expect(isKnownAi('matt'), isFalse);
    expect(spokenNames(['a', 'b', 'c']), 'a, b and c');
  });

  group('a drawn block’s height (editor/heightMemory.ts)', () {
    testWidgets('is remembered by a short name for what it shows, the oldest let go, written once half a second after a change', (tester) async {
      final writes = <List<(String, double)>>[];
      final memory = HeightMemory(HeightStore(read: () => [['3.${0x1a47e90b.toRadixString(36)}', 120], 'junk', ['x', 'y']], write: writes.add), 2, (height) => height.roundToDouble());
      expect(shortKey('abc'), '3.${0x1a47e90b.toRadixString(36)}');
      expect(memory.known('abc'), 120, reason: 'read from storage the first time it is asked');
      expect(memory.known('never'), isNull);
      memory.keep('one', 200.4);
      memory.keep('one', 199.6);
      memory.keep('two', 50);
      await tester.pump(const Duration(milliseconds: 499));
      expect(writes, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(writes, hasLength(1), reason: 'changes within the wait ride along with the first');
      expect([for (final (_, height) in writes.single) height], [200, 50]);
      expect(memory.known('abc'), isNull, reason: 'past the cap, the oldest goes');
      memory.keep('two', 50);
      await tester.pump(const Duration(seconds: 1));
      expect(writes, hasLength(1), reason: 'a height that has not changed is not written again');
    });
  });

  group('where a note was left (editor/notePlace.ts)', () {
    test('is kept by the note, the most recent two hundred, and forgotten with null', () {
      final kept = MemoryStored();
      final places = NotePlaces(kept);
      expect(places.readPlace('a'), isNull);
      places.writePlace('a', const Place(120, 14.5), now: 1);
      expect(places.readPlace('a'), const Place(120, 14.5));
      for (var n = 0; n < placesKept; n++) {
        places.writePlace('n$n', Place(n, 0), now: 10 + n);
      }
      expect(places.readPlace('a'), isNull, reason: 'the least recently read is forgotten first');
      expect(places.readPlace('n0'), const Place(0, 0));
      places.writePlace('n0', null);
      expect(places.readPlace('n0'), isNull);
    });

    test('a bookmark is its own, and anything that is not a place is none', () {
      final kept = MemoryStored()..write('glyph-note-bookmarks', {'bad': 'x', 'half': {'pos': 3}});
      final places = NotePlaces(kept);
      expect(places.readBookmark('bad'), isNull);
      expect(places.readBookmark('half'), isNull);
      places.writeBookmark('a', const Place(40, 0));
      expect(places.readBookmark('a'), const Place(40, 0));
      expect(places.readPlace('a'), isNull);
      places.writeBookmark('a', null);
      expect(places.readBookmark('a'), isNull);
    });
  });

  group('a pinch (editor/pinchZoom.ts)', () {
    test('is held between 0.7 and 2, and anything that is not a number is 1', () {
      expect(clampZoom(0.2), zoomMin);
      expect(clampZoom(5), zoomMax);
      expect(clampZoom(double.nan), 1);
      expect(pinched(1, 100, 150), 1.5);
      expect(pinched(1.5, 100, 400), 2);
      expect(pinched(1.2, 0, 400), 1.2);
    });

    test('is kept to three decimals, and one within a fiftieth of 1 is no zoom', () {
      final kept = MemoryStored();
      expect(readZoom(kept), 1);
      writeZoom(1.23456, kept);
      expect(kept.readText('glyph-note-zoom'), '1.235');
      expect(readZoom(kept), 1.235);
      writeZoom(1.01, kept);
      expect(kept.readText('glyph-note-zoom'), isNull);
      kept.writeText('glyph-note-zoom', '9');
      expect(readZoom(kept), zoomMax);
    });

    test('counts two fingers, their distance and their middle', () {
      final fingers = PinchTracker()..put(1, const Offset(100, 100));
      expect(fingers.pinching, isFalse);
      expect(fingers.apart, 0);
      fingers.put(2, const Offset(100, 300));
      expect(fingers.pinching, isTrue);
      expect(fingers.apart, 200);
      expect(fingers.middle, const Offset(100, 200));
      fingers.lift(1);
      expect(fingers.middle, isNull);
    });
  });

  group('a version’s words (editor/VersionHistory.tsx, editor/versionWords.ts)', () {
    final now = DateTime(2026, 10, 7, 15).millisecondsSinceEpoch;

    test('say the day it was kept, its clock and who kept it', () {
      expect(versionDay(DateTime(2026, 10, 7, 9).millisecondsSinceEpoch, now: now), 'Today');
      expect(versionDay(DateTime(2026, 10, 6, 23).millisecondsSinceEpoch, now: now), 'Yesterday');
      expect(versionDay(DateTime(2026, 9, 28, 9).millisecondsSinceEpoch, now: now), 'Mon, 28 Sep');
      expect(versionDay(DateTime(2025, 12, 31, 9).millisecondsSinceEpoch, now: now), 'Wed, 31 Dec 2025');
      expect(versionClock(DateTime(2026, 10, 7, 9, 5).millisecondsSinceEpoch), '09:05');
      expect(authorName('me'), 'You');
      expect(authorName('sam'), 'sam');
      expect(agoText(now - 30000, now: now), 'just now');
      expect(agoText(now - 3 * 60000, now: now), '3 min ago');
      expect(agoText(now - 5 * 3600000, now: now), '5 hr ago');
      expect(agoText(now - 30 * 3600000, now: now), 'yesterday');
    });

    test('a change shows the lines that go and come with two lines round them, the rest folded', () {
      final before = [for (var n = 1; n <= 12; n++) 'line $n'].join('\n');
      final after = before.replaceFirst('line 6', 'line six');
      final rows = changeRows(before, after);
      expect([for (final row in rows) '${row.kind.name}:${row.text}'], [
        'fold:3 lines the same',
        'same:line 4',
        'same:line 5',
        'del:line 6',
        'add:line six',
        'same:line 7',
        'same:line 8',
        'fold:4 lines the same',
      ]);
      expect(changeRows(before, before).any((row) => row.kind == ChangeKind.add || row.kind == ChangeKind.del), isFalse);
      expect([for (final row in changeRows(null, 'a\nb')) row.kind], [ChangeKind.add, ChangeKind.add]);
    });
  });
}
