// A note keeping its place (lib/core/place_tags.dart): the cases of core/location.test.ts that are about the tag
// that waits, tagging the notes a person makes, the held box and the kept refusal, against a locator and a store
// that are this file's own. Nothing here asks a phone or OpenStreetMap.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/geotag.dart';
import 'package:ghost_md/core/location.dart' as where;
import 'package:ghost_md/core/location.dart' show LocateError, LocateFailure, LocationAccess, Locations, Locator, PlaceAnswer;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/place_tags.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';

const GeoTag london = GeoTag(lat: 51.5074, lon: -0.1278);

/// A phone that answers what the test says.
class _Phone implements Locator {
  LocationAccess state = LocationAccess.granted;
  where.Fix? at = const where.Fix(lat: 51.50741, lon: -0.12779, accuracy: 20, at: 1);
  LocateFailure? fails;
  int asked = 0;
  final List<bool> quiets = <bool>[];
  Completer<void>? gate;

  @override
  LocateFailure? cannot;

  @override
  bool get onPhone => true;

  @override
  Future<LocationAccess?> access() async => state;

  @override
  Future<where.Fix> fix({bool quiet = false}) async {
    asked += 1;
    quiets.add(quiet);
    await gate?.future;
    if (fails != null) throw LocateError(fails!);
    if (state == LocationAccess.ask && quiet) throw const LocateError(LocateFailure.unavailable);
    return at!;
  }

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  late _Phone phone;
  late Map<String, Note> notes;
  late Set<String> queued;
  late MemoryStored kept;
  late UntouchedNotes untouched;
  late PreferencesStore prefs;
  late List<String> lookups;
  late int now;
  late List<void Function()> later;
  late PlaceTags tags;

  Note note(String id, String body, {int revision = 1}) => Note(id: id, body: body, createdAt: 1, updatedAt: 1, source: NoteSource.editor, revision: revision);

  PlaceTags make() => PlaceTags(
        locations: Locations(
          locator: phone,
          lookup: ({required lat, required lon, required zoom}) async {
            lookups.add('$lat,$lon@$zoom');
            return const PlaceAnswer(name: 'Trafalgar Square', addresstype: 'square', address: <String, String?>{'city': 'London'});
          },
          localOnly: () => prefs.value.localOnly,
          mapTiles: () => prefs.value.mapTiles,
          placeNames: () => prefs.value.placeNames,
          wait: (_) async {},
        ),
        getNote: (id) async => notes[id],
        updateNote: (id, body, revision) async {
          final was = notes[id];
          if (was == null || was.revision != revision) throw StateError('the note changed');
          return notes[id] = note(id, body, revision: revision + 1);
        },
        refinePending: queued.contains,
        untouched: untouched,
        prefs: prefs,
        kept: kept,
        now: () => now,
        later: (wait, then) {
          later.add(then);
          return Timer(Duration.zero, () {});
        },
      );

  setUp(() {
    phone = _Phone();
    notes = <String, Note>{};
    queued = <String>{};
    kept = MemoryStored();
    now = 1000000;
    untouched = UntouchedNotes(kept: kept, clock: () => now);
    prefs = PreferencesStore();
    lookups = <String>[];
    later = <void Function()>[];
    tags = make();
  });

  group('the tag that waits', () {
    test('is kept and read back, and forgotten when set to nothing', () {
      expect(tags.pendingTag('n1'), isNull);
      tags.setPendingTag('n1', const GeoTag(lat: 51.51, lon: -0.13, rough: true));
      expect(tags.pendingTag('n1'), const GeoTag(lat: 51.51, lon: -0.13, rough: true));
      tags.setPendingTag('n1', null);
      expect(tags.pendingTag('n1'), isNull);
      expect(kept.getItem('glyph-geotag-pending'), isNull);
    });

    test('lives a day, and longer while its pass is still queued', () {
      tags.setPendingTag('n1', london);
      tags.setPendingTag('n2', london);
      queued.add('n2');
      now += pendingTagMs + 1;
      expect(tags.pendingTag('n1'), isNull);
      expect(tags.pendingTag('n2'), london);
    });

    test('lands only in a note with words, with no pass queued and no review live', () {
      tags.setPendingTag('n1', london);
      expect(tags.settleTag('n1', '', reviewing: false), isNull);
      expect(tags.settleTag('n1', 'Words.\n', reviewing: true), isNull);
      queued.add('n1');
      expect(tags.settleTag('n1', 'Words.\n', reviewing: false), isNull);
      queued.clear();
      expect(tags.settleTag('n1', 'Words.\n', reviewing: false), '---\nlocation: 51.5074,-0.1278\n---\nWords.\n');
    });

    test('does not land on an entry nobody has written in', () {
      const body = '---\ntitle: "2026-09-28 14.05"\n---\n# Monday\n\n**14:05** ';
      untouched.remember('e1', UntouchedRecord(journalId: 'diary', title: '2026-09-28 14.05', words: '# Monday\n\n**14:05** ', at: now));
      tags.setPendingTag('e1', london);
      expect(tags.settleTag('e1', body, reviewing: false), isNull);
      expect(tags.settleTag('e1', '${body}Rain.', reviewing: false), isNotNull);
    });

    test('is written into a closed note at the sweep, its name asked once it is in', () async {
      notes['n1'] = note('n1', 'Words.\n');
      notes['blank'] = note('blank', '');
      tags.setPendingTag('n1', london);
      tags.setPendingTag('blank', london);
      tags.setPendingTag('gone', london);
      expect(await tags.settleWaitingTags(), 1);
      expect(geoTagOf(notes['n1']!.body)?.lat, london.lat);
      // A draft keeps waiting; a note that is gone takes its tag with it.
      expect(tags.pendingTag('blank'), london);
      expect(tags.pendingTag('gone'), isNull);
      await pumpEventQueue();
      expect(lookups, ['51.507,-0.128@15']);
      expect(geoTagOf(notes['n1']!.body)!.place, 'Trafalgar Square, London');
    });

    test('waits while a pass is queued for its note', () async {
      notes['n1'] = note('n1', 'Words.\n');
      tags.setPendingTag('n1', london);
      queued.add('n1');
      expect(await tags.settleWaitingTags(), 0);
      expect(geoTagOf(notes['n1']!.body), isNull);
      queued.clear();
      expect(await tags.settleWaitingTags(), 1);
    });

    test('never writes over a place the note already says', () async {
      notes['n1'] = note('n1', '---\nlocation: 48.8566,2.3522\n---\nWords.\n');
      tags.setPendingTag('n1', london);
      expect(await tags.settleWaitingTags(), 0);
      expect(geoTagOf(notes['n1']!.body), const GeoTag(lat: 48.8566, lon: 2.3522));
      expect(tags.pendingTag('n1'), isNull);
    });
  });

  group('a new note', () {
    test('is tagged through its screen when one watches, and written when none does', () async {
      notes['closed'] = note('closed', 'Words.\n');
      final events = <TagEvent>[];
      final off = tags.watchTag('open', events.add);
      expect(await tags.tagNewNotesIfWanted(['open', 'closed'], (reviewing: false)), isNull);
      expect(events.whereType<TagPending>(), hasLength(1));
      expect(tags.pendingTag('open'), london);
      expect(geoTagOf(notes['closed']!.body)?.lon, london.lon);
      off();
    });

    test('is not tagged with the switch off, or under Local only, and nothing is asked', () async {
      prefs.update((p) => p.copyWith(tagNewNotes: false));
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false)), isNull);
      prefs.update((p) => p.copyWith(tagNewNotes: true, localOnly: true));
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false)), isNull);
      expect(phone.asked, 0);
      expect(tags.pendingTag('n1'), isNull);
    });

    test('is introduced before the first prompt, once a run, and the press makes the ask', () async {
      phone.state = LocationAccess.ask;
      final allows = <void Function()>[];
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false), introduce: allows.add), isNull);
      expect(await tags.tagNewNotesIfWanted(['n2'], (reviewing: false), introduce: allows.add), isNull);
      expect(allows, hasLength(1));
      expect(phone.asked, 0);
      final events = <TagEvent>[];
      final off = tags.watchTag('n1', events.add);
      allows.single();
      expect(tags.heldFor('n1'), Held.waiting);
      await pumpEventQueue();
      expect(phone.asked, 1);
      expect(tags.pendingTag('n1'), london);
      expect(tags.heldFor('n1'), isNull);
      off();
    });

    test('a refusal is kept, said for the notes made since, and not asked again until location is allowed', () async {
      phone.fails = LocateFailure.refused;
      phone.state = LocationAccess.ask;
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false)), LocateFailure.refused);
      expect(tags.autoTagRefusal(), LocateFailure.refused);
      expect(tags.refusedFor(now), LocateFailure.refused);
      expect(tags.refusedFor(now - refusalReachMs - 1), isNull);
      expect(await tags.refusalStanding(), isTrue);
      expect(await tags.tagNewNotesIfWanted(['n2'], (reviewing: false)), LocateFailure.refused);
      expect(phone.asked, 1);
      // Allowed in the phone's settings since: the refusal is forgotten and the ask made.
      phone
        ..state = LocationAccess.granted
        ..fails = null;
      expect(await tags.tagNewNotesIfWanted(['n2'], (reviewing: false)), isNull);
      expect(tags.autoTagRefusal(), isNull);
      expect(phone.asked, 2);
    });

    test('is asked quietly over a locked phone', () async {
      phone.state = LocationAccess.ask;
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false), quiet: true, introduce: (_) => fail('no introduction over a lock screen')), LocateFailure.unavailable);
      expect(phone.quiets, [true]);
      // Nobody refused anything: the next new note may ask.
      expect(tags.autoTagRefusal(), isNull);
    });

    test('a tag for a note under review waits', () async {
      notes['n1'] = note('n1', 'Words.\n');
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: true)), isNull);
      expect(geoTagOf(notes['n1']!.body), isNull);
      expect(tags.pendingTag('n1'), london);
    });

    test('a rough fix is a rough tag', () async {
      phone.at = const where.Fix(lat: 51.50741, lon: -0.12779, accuracy: 2500, at: 1);
      final off = tags.watchTag('n1', (_) {});
      await tags.tagNewNotesIfWanted(['n1'], (reviewing: false));
      expect(tags.pendingTag('n1'), const GeoTag(lat: 51.51, lon: -0.13, rough: true));
      off();
    });
  });

  group('the held box', () {
    test('is held where a fix is expected, and let go once the tag has it', () async {
      expect(await tags.willLocate(), isTrue);
      final events = <TagEvent>[];
      final off = tags.watchTag('n1', events.add);
      tags.holdFor(['n1']);
      expect(tags.heldFor('n1'), Held.waiting);
      await tags.tagNewNotesIfWanted(['n1'], (reviewing: false));
      expect(tags.heldFor('n1'), isNull);
      expect(events.whereType<TagHeld>(), hasLength(2));
      off();
    });

    test('says none is coming when the fix fails, until the note is left', () async {
      phone.fails = LocateFailure.timeout;
      final off = tags.watchTag('n1', (_) {});
      tags.holdFor(['n1']);
      expect(await tags.tagNewNotesIfWanted(['n1'], (reviewing: false)), LocateFailure.timeout);
      expect(tags.heldFor('n1'), Held.missed);
      // A timeout is nobody's refusal.
      expect(tags.autoTagRefusal(), isNull);
      off();
      expect(tags.heldFor('n1'), isNull);
    });

    test('is not expected with the prompt unanswered, the switch off, or a refusal standing', () async {
      phone.state = LocationAccess.ask;
      expect(await tags.willLocate(), isFalse);
      phone.state = LocationAccess.granted;
      prefs.update((p) => p.copyWith(tagNewNotes: false));
      expect(await tags.willLocate(), isFalse);
      prefs.update((p) => p.copyWith(tagNewNotes: true));
      phone.state = LocationAccess.blocked;
      tags.rememberRefusal(LocateFailure.blocked);
      expect(await tags.willLocate(), isFalse);
    });
  });

  group('a note left', () {
    test('has its waiting tag written once its last save has landed', () async {
      final off = tags.watchTag('n1', (_) {});
      await tags.tagNewNotesIfWanted(['n1'], (reviewing: false));
      notes['n1'] = note('n1', 'Typed just before leaving.\n');
      off();
      expect(later, hasLength(1));
      later.single();
      await pumpEventQueue();
      expect(geoTagOf(notes['n1']!.body)?.lat, london.lat);
      expect(tags.pendingTag('n1'), isNull);
    });

    test('a fix that comes after it was left is kept and written where it may land', () async {
      notes['n1'] = note('n1', 'Words.\n');
      tags.landTag('n1', london);
      await pumpEventQueue();
      expect(geoTagOf(notes['n1']!.body)?.lat, london.lat);
    });
  });

  group('a name', () {
    test('is told to the screen that watches, and kept on a tag still waiting', () async {
      final events = <TagEvent>[];
      final off = tags.watchTag('n1', events.add);
      tags.setPendingTag('n1', london);
      tags.wantPlace('n1', london);
      await pumpEventQueue();
      final named = events.whereType<TagPlace>().single;
      expect(named.place, 'Trafalgar Square, London');
      expect(tags.pendingTag('n1')!.place, 'Trafalgar Square, London');
      off();
    });

    test('is not asked with Place names off, or for a tag that has one', () async {
      prefs.update((p) => p.copyWith(placeNames: false));
      tags.wantPlace('n1', london);
      tags.wantPlace('n1', london.named('Somewhere'));
      await pumpEventQueue();
      expect(lookups, isEmpty);
    });
  });

  test('a press asks only where the prompt was never answered', () async {
    expect(await tags.askFromPress(), isNull);
    expect(phone.asked, 0);
    phone
      ..state = LocationAccess.ask
      ..fails = LocateFailure.refused;
    expect(await tags.askFromPress(), LocateFailure.refused);
    expect(tags.autoTagRefusal(), LocateFailure.refused);
  });

  test('where location is allowed again is the phone\'s settings on a phone', () {
    expect(tags.allowLocationWhere(), 'Allow location for Ghost.md in the phone’s settings');
  });
}
