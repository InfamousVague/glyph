// A note keeping its place, through the app put together (lib/root/ghost_root.dart over lib/core/place_tags.dart):
// the + sheet's Note is the person's own and is tagged, a canvas is the app's and is not, the first ask is
// introduced, and a tagged note draws its map card. The phone and the geocoder are this file's own.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/geotag.dart';
import 'package:ghost_md/core/location.dart' as where;
import 'package:ghost_md/core/location.dart' show LocateError, LocateFailure, LocationAccess, Locator, PlaceAnswer;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/map_card.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

class _Phone implements Locator {
  LocationAccess state = LocationAccess.granted;
  int asked = 0;

  @override
  LocateFailure? get cannot => null;

  @override
  bool get onPhone => true;

  @override
  Future<LocationAccess?> access() async => state;

  @override
  Future<where.Fix> fix({bool quiet = false}) async {
    asked += 1;
    if (state != LocationAccess.granted) throw const LocateError(LocateFailure.refused);
    return const where.Fix(lat: 51.50741, lon: -0.12779, accuracy: 20, at: 1);
  }

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  setUpAll(loadAppFonts);
  final seedNow = DateTime(2026, 9, 12, 12).millisecondsSinceEpoch;

  Future<SampleLibrary> open(WidgetTester tester, _Phone phone, {bool tagNewNotes = true}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', tagNewNotes: tagNewNotes),
      home: GhostRoot(
        launch: false,
        library: library,
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        locator: phone,
        placeLookup: ({required lat, required lon, required zoom}) async => const PlaceAnswer(name: 'Trafalgar Square', addresstype: 'square', address: <String, String?>{'city': 'London'}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  NoteScreenState screenOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
  }

  testWidgets('a new note holds its map’s box, is tagged with its first words, and draws its card; a canvas is not asked for', (tester) async {
    final phone = _Phone();
    await open(tester, phone);
    tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
    await settle(tester);
    final screen = screenOf(tester);
    expect(phone.asked, 1);
    expect(screen.view!.state.doc.toString(), '', reason: 'a draft with no words is given no tag');
    // The tag waits, drawn quiet: a draft that may never be kept fetches no tiles.
    expect(tester.widget<MapCard>(find.byType(MapCard)).mode, MapCardMode.quiet);
    screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'Here'), userEvent: 'input.type'));
    await settle(tester);
    expect(geoTagOf(screen.view!.state.doc.toString()), const GeoTag(lat: 51.5074, lon: -0.1278, place: 'Trafalgar Square, London'));
    expect(tester.widget<MapCard>(find.byType(MapCard)).mode, MapCardMode.map);
    shellOf(tester).backToList();
    await settle(tester);

    tester.widget<NewSheet>(find.byType(NewSheet)).onCanvas!();
    await settle(tester);
    expect(phone.asked, 1, reason: 'a canvas is the app\'s making');
    await close(tester);
  });

  testWidgets('the first ask on a phone that never answered is said in the app’s words, and nothing is asked until Allow', (tester) async {
    final phone = _Phone()..state = LocationAccess.ask;
    await open(tester, phone);
    tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
    await settle(tester);
    expect(find.text('New notes can keep where they were written.'), findsOneWidget);
    expect(phone.asked, 0);
    expect(find.byType(MapPicture), findsNothing);
    phone.state = LocationAccess.granted;
    await tester.tap(find.text('Allow location'));
    await settle(tester);
    expect(phone.asked, 1);
    expect(find.byType(MapCard), findsOneWidget);
    await close(tester);
  });

  testWidgets('with Tag new notes off nothing is asked, and the More sheet still adds a location by hand', (tester) async {
    final phone = _Phone();
    await open(tester, phone, tagNewNotes: false);
    tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
    await settle(tester);
    expect(phone.asked, 0);
    final screen = screenOf(tester);
    screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'Here'), userEvent: 'input.type'));
    await settle(tester);
    screen.addLocation();
    await settle(tester);
    expect(geoTagOf(screen.view!.state.doc.toString())?.lat, 51.5074);
    await close(tester);
  });
}
