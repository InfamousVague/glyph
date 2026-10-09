// A note keeping its place, on its screen (lib/note/note_screen.dart over lib/core/place_tags.dart): what
// editor/NoteScreen.tsx does with `addLocation`, `removeLocation`, `settle` and `namePlace`, with a phone and a
// geocoder that are this file's own.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/geotag.dart';
import 'package:ghost_md/core/location.dart' as where;
import 'package:ghost_md/core/location.dart' show LocateError, LocateFailure, LocationAccess, Locations, Locator, PlaceAnswer;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/place_tags.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/map_card.dart' show MapPicture;
import 'package:ghost_md/note/note_screen.dart';

import '../support/render.dart';
import 'support.dart';

class _Phone implements Locator {
  LocateFailure? fails;
  LocationAccess state = LocationAccess.granted;

  @override
  LocateFailure? get cannot => null;

  @override
  bool get onPhone => true;

  @override
  Future<LocationAccess?> access() async => state;

  @override
  Future<where.Fix> fix({bool quiet = false}) async => fails != null ? throw LocateError(fails!) : const where.Fix(lat: 51.50741, lon: -0.12779, accuracy: 20, at: 1);

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'place${made += 1}', body)))!;
  String doc(NoteScreenState screen) => screen.view!.state.doc.toString();
  NoteSeams seams() => NoteSeams(
        mapCard: (context, tag, {required header, required quiet, required arrive, required leave, onLeft}) {
          if (leave) WidgetsBinding.instance.addPostFrameCallback((_) => onLeft?.call());
          return Text('map ${tagLabel(tag)}${quiet ? ' quiet' : ''}${leave ? ' leaving' : ''}', textDirection: TextDirection.ltr);
        },
      );

  PlaceTags tagsOver(NoteWorld world, _Phone phone, {bool names = true}) => PlaceTags(
        locations: Locations(
          locator: phone,
          lookup: names ? ({required lat, required lon, required zoom}) async => const PlaceAnswer(name: 'Trafalgar Square', addresstype: 'square', address: <String, String?>{'city': 'London'}) : null,
          localOnly: () => world.prefs.value.localOnly,
          wait: (_) async {},
        ),
        getNote: world.library.get,
        updateNote: world.library.update,
        untouched: world.untouched,
        prefs: world.prefs,
        kept: world.device,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Add my location writes the tag as one change, asks its name once it is in, and Remove takes both keys out', (tester) async {
    final world = NoteWorld();
    final tags = tagsOver(world, _Phone());
    final screen = await pumpNote(tester, world, await seeded(tester, world, 'Words'), seams: seams(), tags: tags);
    screen.addLocation();
    await settle(tester);
    expect(doc(screen), '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\nWords');
    expect(find.text('map Trafalgar Square, London'), findsOneWidget);
    expect(tags.pendingTag(screen.widget.note.id), isNull);
    screen.removeLocation();
    await tester.pump();
    expect(doc(screen), 'Words');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('map '), findsNothing);
    await tester.pump(const Duration(milliseconds: 450));
    await closeNote(tester);
  });

  testWidgets('a new note’s tag waits for its first words, drawn quiet meanwhile, and lands with them', (tester) async {
    final world = NoteWorld();
    final tags = tagsOver(world, _Phone(), names: false);
    final note = await seeded(tester, world, '');
    final screen = await pumpNote(tester, world, note, seams: seams(), tags: tags);
    await tester.runAsync(() => tags.tagNewNotesIfWanted([note.id], (reviewing: false)));
    await settle(tester);
    expect(doc(screen), '', reason: 'a draft with no words gets no file, and no tag');
    expect(find.text('map 51.5074, -0.1278 quiet'), findsOneWidget);
    screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'Hi'), userEvent: 'input.type'));
    await settle(tester);
    expect(doc(screen), '---\nlocation: 51.5074,-0.1278\n---\nHi');
    expect(tags.pendingTag(note.id), isNull);
    await tester.pump(const Duration(milliseconds: 450));
    await closeNote(tester);
  });

  testWidgets('a new note left without a word takes its waiting tag with it', (tester) async {
    final world = NoteWorld();
    final tags = tagsOver(world, _Phone(), names: false);
    final note = await seeded(tester, world, '');
    await pumpNote(tester, world, note, seams: seams(), tags: tags);
    await tester.runAsync(() => tags.tagNewNotesIfWanted([note.id], (reviewing: false)));
    await settle(tester);
    expect(tags.pendingTag(note.id), isNotNull);
    await closeNote(tester);
    expect(tags.pendingTag(note.id), isNull);
  });

  testWidgets('the box is held while a fix is on its way and says so when none comes', (tester) async {
    final world = NoteWorld();
    final phone = _Phone()..fails = LocateFailure.timeout;
    final tags = tagsOver(world, phone);
    final note = await seeded(tester, world, '');
    tags.holdFor([note.id]);
    await pumpNote(tester, world, note, seams: seams(), tags: tags);
    expect(find.byType(MapPicture), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chip-why')), findsNothing);
    await tester.runAsync(() => tags.tagNewNotesIfWanted([note.id], (reviewing: false)));
    await settle(tester);
    expect(tester.widget<MapPicture>(find.byType(MapPicture)).why, 'No place yet.');
    await closeNote(tester);
  });

  testWidgets('the More sheet’s row is the screen’s own, and a refusal is kept for the notes made since', (tester) async {
    final world = NoteWorld();
    final phone = _Phone()..fails = LocateFailure.refused;
    final tags = tagsOver(world, phone);
    final screen = await pumpNote(tester, world, await seeded(tester, world, 'Words'), seams: seams(), tags: tags);
    screen.addLocation();
    await settle(tester);
    expect(tags.autoTagRefusal(), LocateFailure.refused);
    expect(doc(screen), 'Words');
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Add my location'), findsOneWidget);
    // A note made since the refusal is told why it was not tagged; one older than it was never going to be.
    expect(tags.refusedFor(DateTime.now().millisecondsSinceEpoch), LocateFailure.refused);
    expect(tags.refusedFor(0), isNull);
    await closeNote(tester);
  });
}
