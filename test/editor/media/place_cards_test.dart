// editor/placeCards.test.ts and editor/MapCard.test.tsx, case for case where a case is about what is drawn. Leaflet
// is the seam `MapTilesBuilder` here, so the page's cases about Leaflet itself (its lazy import, its options, its
// redraw for a new width, its weight in the bundle) have no counterpart; what the card does round a map (asks for
// it only in map mode, at the tag's zoom, fades in when it has loaded, stays quiet when it has not, credits it) is
// held with a builder that says when it was asked.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/place_refs.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/media/map_card.dart';
import 'package:ghost_md/editor/media/place_cards.dart';
import 'package:ghost_md/editor/view/drawn_block.dart';

import '../../support/render.dart';
import 'support.dart';

const String cais = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
const Key card = ValueKey<String>('cm-placeCard'), box = ValueKey<String>('card');
const GeoTag london = GeoTag(lat: 51.5074, lon: -0.1278);
const GeoTag square = GeoTag(lat: 51.5074, lon: -0.1278, place: 'Trafalgar Square, London');

Future<void> pumpCard(WidgetTester tester, Widget child) async {
  await pumpApp(tester, home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 360, child: child)));
  debugDisableShadows = true;
  await tester.pump();
}

/// Whether a chip on the card says `text`.
bool Function(String text) hasOn(WidgetTester tester) =>
    (text) => tester.widgetList<InlineWords>(find.byType(InlineWords)).any((words) => words.text == text);

void main() {
  setUpAll(loadAppFonts);

  group('a map card under a place line', () {
    testWidgets('is drawn under a line that is a place, in any lead, and under nothing else', (tester) async {
      await pumpNote(tester, 'Lunch\n$cais\n- $cais\nMet at $cais\n[site](https://example.com)', more: <Extension>[placeCards(PlaceMode.live)]);
      expect(find.byKey(card), findsNWidgets(2));
    });

    testWidgets('is not drawn in fenced code, or where the editor draws no cards at all', (tester) async {
      await pumpNote(tester, '```\n$cais\n```', more: <Extension>[placeCards(PlaceMode.live)]);
      expect(find.byKey(card), findsNothing);
      await pumpNote(tester, cais, more: <Extension>[placeCards(PlaceMode.off)]);
      expect(find.byKey(card), findsNothing);
    });

    testWidgets('leaves a place’s line in fenced code as the code was written, unfolded', (tester) async {
      await pumpNote(tester, 'Lunch\n```\n$cais\n```', more: <Extension>[placeCards(PlaceMode.live)]);
      expect(shownOf(tester, 2), cais);
    });

    testWidgets('is the map card itself, with no place chip since the line says the name, and a press on it is not the note’s', (tester) async {
      final opened = <GeoTag>[];
      final view = await pumpNote(tester, 'Lunch\n$cais', more: <Extension>[placeCards(PlaceMode.live, onOpen: opened.add)]);
      expect(find.bySemanticsLabel('Open Cais do Sodré, Lisbon on a map'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chip-where')), findsNothing);
      final hit = view.hitAt(tester.getCenter(find.byKey(box)));
      expect(isDrawnBlock(hit?.block), isTrue);
      await tester.tap(find.byKey(box));
      expect(opened.single.place, 'Cais do Sodré, Lisbon');
    });
  });

  group('a place at the very top of a note', () {
    testWidgets('is drawn as the note’s header, and a place further down as the card', (tester) async {
      await pumpNote(tester, '# Lisbon\n$cais\nwords\n$cais', more: <Extension>[placeCards(PlaceMode.ask)]);
      final heights = tester.renderObjectList<RenderBox>(find.byKey(box)).map((b) => b.size.height).toList();
      expect(heights, <Object>[160, closeTo(115.2, 0.05)]);
    });

    testWidgets('becomes the card once words are put above it', (tester) async {
      final view = await pumpNote(tester, '# Lisbon\n$cais', more: <Extension>[placeCards(PlaceMode.ask)]);
      expect(tester.getSize(find.byKey(box)).height, 160);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 9, insert: 'words\n')));
      await tester.pump();
      expect(tester.getSize(find.byKey(box)).height, closeTo(115.2, 0.05));
    });
  });

  group('what the card draws', () {
    test('on the note screen: the map where tiles may be fetched, quiet with the reason where not', () {
      expect(placeLook(PlaceMode.live, localOnly: false, mapTiles: true), (mode: MapCardMode.map, quietWhy: null));
      expect(placeLook(PlaceMode.live, localOnly: true, mapTiles: true), (mode: MapCardMode.quiet, quietWhy: QuietWhy.localOnly));
      expect(placeLook(PlaceMode.live, localOnly: false, mapTiles: false), (mode: MapCardMode.quiet, quietWhy: QuietWhy.off));
    });

    test('on a shared page: nothing fetched until the reader asks', () {
      expect(placeLook(PlaceMode.ask, localOnly: false, mapTiles: true), (mode: MapCardMode.ask, quietWhy: null));
    });

    testWidgets('follows Local only as it changes', (tester) async {
      final localOnly = ValueNotifier<bool>(false);
      await pumpNote(tester, 'Lunch\n$cais', more: <Extension>[placeCards(PlaceMode.live, switches: () => (localOnly: localOnly.value, mapTiles: true), changed: localOnly)]);
      expect(find.byKey(const ValueKey<String>('chip-why')), findsNothing);
      localOnly.value = true;
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('chip-why')), findsOneWidget);
    });

    testWidgets('on a shared page: "Show the map" turns the card into a map, which is asked for only then', (tester) async {
      final asked = <int>[];
      Widget tiles(BuildContext context, {required GeoTag tag, required int zoom, required VoidCallback onLoaded}) {
        asked.add(zoom);
        return const SizedBox.expand();
      }

      await pumpNote(tester, 'Lunch\n$cais', more: <Extension>[placeCards(PlaceMode.ask, tiles: tiles)]);
      expect(asked, isEmpty);
      await tester.tap(find.byKey(box));
      await tester.pump();
      expect(asked, <int>[15]);
      expect(find.byKey(const ValueKey<String>('chip-show')), findsNothing);
    });
  });

  group('the place line', () {
    testWidgets('reads as its name off the caret’s line, and as written on it while the note is being written', (tester) async {
      final view = await pumpNote(tester, 'Lunch\n$cais', more: <Extension>[placeCards(PlaceMode.live)]);
      expect(shownOf(tester, 1), 'Cais do Sodré, Lisbon');
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      await tester.pump();
      expect(shownOf(tester, 1), cais);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      expect(shownOf(tester, 1), 'Cais do Sodré, Lisbon');
    });

    testWidgets('reads as its name everywhere in a view that cannot be edited, even where no card is drawn', (tester) async {
      final view = await pumpNote(tester, 'Lunch\n$cais', more: <Extension>[placeCards(PlaceMode.off)], readOnly: true);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(7)));
      await tester.pump();
      expect(shownOf(tester, 1), 'Cais do Sodré, Lisbon');
    });
  });

  // ---- editor/MapCard.test.tsx ----

  group('the quiet card', () {
    testWidgets('shows the pin and the coordinates, asks for no map, and credits nobody until there is a place', (tester) async {
      var asked = 0;
      await pumpCard(
        tester,
        MapCard(
          tag: london,
          mode: MapCardMode.quiet,
          tiles: (context, {required tag, required zoom, required onLoaded}) {
            asked += 1;
            return const SizedBox.expand();
          },
        ),
      );
      expect(find.byKey(const ValueKey<String>('mark')), findsOneWidget);
      expect(hasOn(tester)('51.5074, -0.1278'), isTrue);
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsNothing);
      expect(asked, 0);
      await pumpCard(tester, const MapCard(tag: square, mode: MapCardMode.quiet));
      expect(hasOn(tester)('Trafalgar Square, London'), isTrue);
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsOneWidget);
    });

    testWidgets('says why it is quiet, and draws a ring for a rough tag, as wide as the area its decimals leave open', (tester) async {
      await pumpCard(tester, const MapCard(tag: GeoTag(lat: 51.51, lon: -0.13, rough: true), mode: MapCardMode.quiet, quietWhy: QuietWhy.localOnly));
      expect(hasOn(tester)('Local only is on.'), isTrue);
      expect(hasOn(tester)('Roughly 51.51, -0.13'), isTrue);
      // 2r + 4, r 14 at London's latitude.
      expect(tester.getSize(find.byKey(const ValueKey<String>('mark'))), const Size.square(2.0 * 14 + 4));
      expect(ringRadius(51.51), 14);
      expect(ringRadius(38.71), 12);
      expect(ringRadius(0), 10);
      expect(ringRadius(70), 18);
      await pumpCard(tester, const MapCard(tag: london, mode: MapCardMode.quiet, quietWhy: QuietWhy.off));
      expect(hasOn(tester)('Map off in Settings.'), isTrue);
    });

    testWidgets('leaves on its beat when the tag is taken off, and is then let go', (tester) async {
      var left = 0;
      await pumpCard(tester, MapCard(tag: london, mode: MapCardMode.quiet, onLeft: () => left += 1));
      await pumpCard(tester, MapCard(tag: london, mode: MapCardMode.quiet, leave: true, onLeft: () => left += 1));
      await tester.pump(const Duration(milliseconds: 299));
      expect(left, 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(left, 1);
    });

    testWidgets('opens the place on a tap', (tester) async {
      final opened = <GeoTag>[];
      await pumpCard(tester, MapCard(tag: square, mode: MapCardMode.quiet, onOpen: opened.add));
      expect(find.bySemanticsLabel('Open Trafalgar Square, London on a map'), findsOneWidget);
      await tester.tap(find.byKey(box));
      expect(opened, <GeoTag>[square]);
    });

    testWidgets('leaves the place’s chip off under a place line, which says the name already, and still names it to a tap', (tester) async {
      await pumpCard(tester, const MapCard(tag: square, mode: MapCardMode.quiet, where: false));
      expect(find.byKey(const ValueKey<String>('chip-where')), findsNothing);
      expect(find.bySemanticsLabel('Open Trafalgar Square, London on a map'), findsOneWidget);
    });
  });

  group('the picture', () {
    testWidgets('is the card’s own box with no map in it: nothing to press, nothing read out', (tester) async {
      await pumpCard(tester, const MapPicture(pin: true, why: 'Finding where you are.'));
      expect(tester.getSize(find.byKey(box)).height, closeTo(115.2, 0.05));
      expect(find.byKey(const ValueKey<String>('mark')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chip-why')), findsOneWidget);
      expect(find.bySemanticsLabel('Finding where you are.'), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('draws a map note’s card as its header, the size a card is told', (tester) async {
      await pumpCard(tester, const MapPicture(size: MapSize.header));
      expect(tester.getSize(find.byKey(box)).height, 160);
      await pumpCard(tester, const MapCard(tag: london, mode: MapCardMode.quiet, size: MapSize.header, scale: 0.5));
      expect(tester.getSize(find.byKey(box)).height, 80);
    });
  });

  group('the reader’s ask', () {
    testWidgets('offers the map and hands the tap to the caller, opening nothing and asking for no map', (tester) async {
      var shown = 0, asked = 0;
      final opened = <GeoTag>[];
      await pumpCard(
        tester,
        MapCard(
          tag: london,
          mode: MapCardMode.ask,
          onShow: () => shown += 1,
          onOpen: opened.add,
          tiles: (context, {required tag, required zoom, required onLoaded}) {
            asked += 1;
            return const SizedBox.expand();
          },
        ),
      );
      expect(find.bySemanticsLabel('Show the map'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chip-show')), findsOneWidget);
      await tester.tap(find.byKey(box));
      expect(shown, 1);
      expect(opened, isEmpty);
      expect(asked, 0);
    });
  });

  group('the map', () {
    testWidgets('is asked for at a street’s zoom, fades in once it has loaded, and is credited then', (tester) async {
      final zooms = <int>[];
      VoidCallback? loaded;
      Widget tiles(BuildContext context, {required GeoTag tag, required int zoom, required VoidCallback onLoaded}) {
        zooms.add(zoom);
        loaded = onLoaded;
        return const ColoredBox(color: Color(0xFF808080));
      }

      await pumpCard(tester, MapCard(tag: london, mode: MapCardMode.map, tiles: tiles));
      expect(zooms, <int>[15]);
      // Loading is the quiet card: the pin in the second ink, no credit, the map not yet seen.
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsNothing);
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity, 0);
      loaded!();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity, 1);
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('mark-over')), findsOneWidget);
    });

    testWidgets('stays the quiet card when no tile came at all, and with nothing to draw a map', (tester) async {
      await pumpCard(tester, MapCard(tag: london, mode: MapCardMode.map, tiles: (context, {required tag, required zoom, required onLoaded}) => const SizedBox.expand()));
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsNothing);
      await pumpCard(tester, const MapCard(tag: london, mode: MapCardMode.map));
      expect(find.byKey(const ValueKey<String>('mark')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('chip-credit')), findsNothing);
    });

    testWidgets('draws a rough tag a district wide, at zoom 11, with a ring', (tester) async {
      final zooms = <int>[];
      await pumpCard(
        tester,
        MapCard(
          tag: const GeoTag(lat: 51.51, lon: -0.13, rough: true),
          mode: MapCardMode.map,
          tiles: (context, {required tag, required zoom, required onLoaded}) {
            zooms.add(zoom);
            return const SizedBox.expand();
          },
        ),
      );
      expect(zooms, <int>[11]);
      expect(zoomOf(true), 11);
      expect(zoomOf(false), 15);
      expect(tester.getSize(find.byKey(const ValueKey<String>('mark'))), const Size.square(32));
    });
  });
}
