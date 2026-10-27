import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/art/packs/licences.g.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/market/market_icons.dart' show appGlyphNames, packCoverage;
import 'package:ghost_md/sync/prefs.dart' show pickSynced, syncedPrefs;

import '../../tool/icons/path_data.dart';
import '../support/render.dart';

/// The icon packs and their three styles (Matt, 2026-10-27: "I would like you to add three icon styles (outline,
/// solid and filled) and add a few different icon packs for the app to choose from"; lib/art/icon_packs.dart): the
/// generator's map (tool/icons/map.json) against the app's own glyphs and the tables made from it, the path data's
/// move onto the 24 grid, how each pack draws each style, every icon redrawn the moment a pack or a style is chosen,
/// the two preferences travelling, and the packs' licences among the app's.
void main() {
  final map = jsonDecode(File('tool/icons/map.json').readAsStringSync()) as Map<String, dynamic>;
  final icons = (map['icons'] as Map).cast<String, Map<String, dynamic>>();
  final drawn = (map['drawn'] as Map).cast<String, String>();
  const packIds = ['phosphor', 'tabler', 'material', 'remix'];

  group('the map', () {
    test('has a line for every glyph the app draws, and none for one it does not', () {
      expect(icons.keys.toSet(), appGlyphNames);
      // Lucide's every one, and what each of the app's own drawings draws.
      for (final icon in Lucide.all.values) {
        expect(icons, contains(icon.name));
      }
      expect(drawn.keys.toSet(), {...AppIcons.all.keys, 'House'});
      for (final entry in AppIcons.all.entries) {
        expect(drawn[entry.key], entry.value.like, reason: entry.key);
      }
    });

    test('names each pack for each glyph, or nothing, and every glyph resolves in the pack or falls back to Lucide', () {
      for (final pack in iconPacks.skip(1)) {
        expect(packIds, contains(pack.id));
        final table = pack.glyphs!;
        // The table is the map's names that are not null, and only those.
        expect(table.keys.toSet(), {for (final MapEntry(:key, :value) in icons.entries) if (value[pack.id] != null) key}, reason: pack.id);
        for (final name in appGlyphNames) {
          for (final style in IconStyle.values) {
            final look = IconLook(pack.id, style);
            final entry = packGlyphsFor(look, name);
            expect(entry == null, icons[name]![pack.id] == null, reason: '${pack.id} $name');
            if (entry != null) expect(drawingFor(entry, style).glyph.paths, isNotEmpty);
          }
        }
      }
    });

    test('says at the head of each table how many fell back, as many as the map leaves out', () {
      for (final id in packIds) {
        final head = File('lib/art/packs/$id.g.dart').readAsLinesSync().take(6).join('\n');
        final out = icons.values.where((each) => each[id] == null).length;
        expect(head, contains('; $out drawn as Lucide\'s'), reason: id);
        expect(packCoverage(iconPackOf(id)).lucides.length, out, reason: id);
      }
      // Lucide draws them all; the four between them nearly all (tool/icons/map.json).
      expect(packCoverage(iconPacks.first).lucides, isEmpty);
      expect({for (final id in packIds) id: packCoverage(iconPackOf(id)).own}, {'phosphor': 217, 'tabler': 227, 'material': 222, 'remix': 217});
    });

    test('pins every source and keeps every licence', () {
      final sources = (map['sources'] as Map).cast<String, Map<String, dynamic>>();
      for (final source in sources.values) {
        expect(source['version'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
        expect(['MIT', 'Apache-2.0'], contains(source['licence']));
      }
      for (final id in ['lucide', ...packIds]) {
        expect(File('tool/icons/licences/$id.txt').existsSync(), isTrue, reason: id);
        expect(iconPackLicenceTexts[id], File('tool/icons/licences/$id.txt').readAsStringSync(), reason: id);
      }
      expect(iconPackChoices, [for (final pack in iconPacks) pack.id]);
      expect(iconStyleChoices, [for (final style in IconStyle.values) style.name]);
    });
  });

  group('the path data, onto the 24 grid', () {
    test('scales and moves every command, keeping each relative or absolute, whichever is shorter', () {
      // Material Symbols' grid: 960 across, the origin a height above.
      expect(rescalePath('M480-80q-33 0-56.5-23.5T400-160h160Z', scale: 0.025, dy: 24), 'M12 22q-.82 0-1.41-.59T10 20h4Z');
      // Phosphor's: 256 across, an arc's radii scaled and its flags kept.
      expect(rescalePath('M128,216a24,24,0,0,1-22.62-16h45.24A24,24,0,0,1,128,216Z', scale: 24 / 256), 'M12 20.25a2.25 2.25 0 01-2.12-1.5h4.24A2.25 2.25 0 0112 20.25Z');
      // Nothing to move: the same path, its numbers to hundredths.
      expect(rescalePath('M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0'), 'M3 12a9 9 0 1018 0A9 9 0 103 12');
    });

    test('never drifts down a chain of relative steps', () {
      // A hundred steps of a third: rounded one by one they would end a third of a unit out.
      final d = 'M0 0${List.filled(100, 'l.3333 0').join()}';
      final out = rescalePath(d);
      final path = parseSvgPath(out);
      expect(path.getBounds().right, closeTo(33.33, 0.01));
    });

    testWidgets('draws what the source drew', (tester) async {
      // Phosphor's bell, as the generator moves it, drawn against the source scaled by the canvas.
      const source = 'M221.8,175.94C216.25,166.38,208,139.33,208,104a80,80,0,1,0-160,0c0,35.34-8.26,62.38-13.81,71.94A16,16,0,0,0,48,200H88.81a40,40,0,0,0,78.38,0H208a16,16,0,0,0,13.8-24.06ZM128,216a24,24,0,0,1-22.62-16h45.24A24,24,0,0,1,128,216ZM48,184c7.7-13.24,16-43.92,16-80a64,64,0,1,1,128,0c0,36.05,8.28,66.73,16,80Z';
      final moved = rescalePath(source, scale: 24 / 256);
      Future<List<int>> draw(String d, double scale) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(scale);
        canvas.drawPath(parseSvgPath(d), ui.Paint()..color = const ui.Color(0xFF000000));
        final image = await recorder.endRecording().toImage(96, 96);
        final data = await image.toByteData();
        return [for (var i = 3; i < data!.lengthInBytes; i += 4) data.getUint8(i)];
      }

      final (a, b) = (await tester.runAsync(() async => (await draw(source, 96 / 256), await draw(moved, 4))))!;
      var worst = 0;
      for (var i = 0; i < a.length; i++) {
        worst = (a[i] - b[i]).abs() > worst ? (a[i] - b[i]).abs() : worst;
      }
      expect(worst, lessThan(64), reason: 'a quarter of a pixel’s ink at most, at 96 points');
    });

    test('walks curves and arcs into lines for the wash’s rule, so a circle written as two arcs has a body', () {
      expect(walkPath('M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0').bounds!.area, 0);
      final flat = walkPath(flattenPath('M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0'));
      expect(flat.closed, isTrue);
      expect(flat.bounds!.area, closeTo(324, 4));
    });
  });

  group('how each pack draws each style', () {
    PackGlyphs of(String pack, String name) => iconPackOf(pack).glyphs![name]!;

    test('Phosphor: regular, bold and fill, its own three, the duotone layer as the wash where the app has one', () {
      final bell = of('phosphor', 'bell');
      expect(drawingFor(bell, IconStyle.outline).ink, IconInk.shapes);
      expect(drawingFor(bell, IconStyle.outline).under, same(bell.back));
      expect(drawingFor(bell, IconStyle.solid).glyph, same(bell.solid));
      expect(drawingFor(bell, IconStyle.filled).glyph, same(bell.filled));
      expect(drawingFor(bell, IconStyle.filled).under, isNull);
      // A tick has no body in the app, so no wash in Phosphor either.
      expect(of('phosphor', 'check').back, isNull);
      expect(drawingFor(of('phosphor', 'check'), IconStyle.outline, body: false).under, isNull);
    });

    test('Tabler: lines stroked as Lucide’s, heavier for Solid, its filled set where it has one and the body filled where not', () {
      final clock = of('tabler', 'clock');
      expect(clock.outline.shapes, isFalse);
      expect(clock.outline.wash, [0]);
      expect(drawingFor(clock, IconStyle.solid).ink, IconInk.heavyLines);
      expect(drawingFor(clock, IconStyle.filled).ink, IconInk.shapes);
      final noFill = iconPackOf('tabler').glyphs!.values.firstWhere((each) => each.filled == null && each.outline.wash.isNotEmpty);
      expect(drawingFor(noFill, IconStyle.filled).ink, IconInk.cutLines);
    });

    test('Material Symbols: 400, 700 and filled, all its own', () {
      final bell = of('material', 'bell');
      expect([bell.solid, bell.filled], everyElement(isNotNull));
      expect(drawingFor(bell, IconStyle.outline).under, same(bell.filled));
    });

    test('Remix: line and fill its own, Solid the line thickened, and a letter drawn one way its Solid in Filled', () {
      final bell = of('remix', 'bell');
      expect(drawingFor(bell, IconStyle.solid).ink, IconInk.thickShapes);
      expect(drawingFor(bell, IconStyle.filled).glyph, same(bell.filled));
      final bold = of('remix', 'bold');
      expect(bold.filled, isNull);
      expect(drawingFor(bold, IconStyle.filled).ink, IconInk.thickShapes);
    });

    test('Lucide: its line, heavier for Solid, and Filled made of its body', () {
      final bell = Lucide.bell;
      expect(lucideDrawing(bell.shapes, bell.wash, IconStyle.solid).ink, IconInk.heavyLines);
      expect(lucideDrawing(bell.shapes, bell.wash, IconStyle.filled).ink, IconInk.cutLines);
      expect(IconLook.standard.isStandard, isTrue);
      expect(const IconLook('lucide', IconStyle.solid).isStandard, isFalse);
      // A pack this build does not have is Lucide.
      expect(iconPackOf('someday').id, 'lucide');
      expect(IconStyle.of('wavy'), IconStyle.outline);
    });
  });

  group('drawn', () {
    setUpAll(loadAppFonts);

    CustomPainter painterOf(WidgetTester tester, Finder icon) => tester.widget<CustomPaint>(find.descendant(of: icon, matching: find.byType(CustomPaint)).first).painter!;

    testWidgets('Lucide’s outline as it always was, and every icon redrawn the moment a pack or a style is chosen', (tester) async {
      await pumpApp(
        tester,
        prefs: const Preferences(theme: 'light'),
        home: const Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(Lucide.bell, key: ValueKey('kit')), DrawnIconView(AppIcons.clock, key: ValueKey('drawn'), size: 20), HouseIcon(key: ValueKey('house'))]),
        ),
      );
      expect(painterOf(tester, find.byKey(const ValueKey('kit'))), isA<DrawnIconPainter>());
      expect((painterOf(tester, find.byKey(const ValueKey('drawn'))) as DrawnIconPainter).strokeWidth, 2.4);

      // Phosphor, filled: the kit's icon, the app's own drawing and the house are Phosphor's fill.
      preferences.update((now) => now.copyWith(iconPack: 'phosphor', iconStyle: 'filled'));
      await tester.pump();
      for (final key in ['kit', 'drawn', 'house']) {
        final painter = painterOf(tester, find.byKey(ValueKey(key)));
        expect(painter, isA<PackIconPainter>(), reason: key);
        expect((painter as PackIconPainter).drawing.ink, IconInk.shapes, reason: key);
      }
      expect((painterOf(tester, find.byKey(const ValueKey('kit'))) as PackIconPainter).drawing.glyph, same(iconPackOf('phosphor').glyphs!['bell']!.filled));

      // Lucide, Solid: the drawings heavier; Filled, the clock's body filled with its hands cut out.
      preferences.update((now) => now.copyWith(iconPack: 'lucide', iconStyle: 'solid'));
      await tester.pump();
      expect((painterOf(tester, find.byKey(const ValueKey('kit'))) as PackIconPainter).drawing.ink, IconInk.heavyLines);
      expect((painterOf(tester, find.byKey(const ValueKey('drawn'))) as DrawnIconPainter).strokeWidth, 2.4 + solidStroke);
      preferences.update((now) => now.copyWith(iconStyle: 'filled'));
      await tester.pump();
      final clock = painterOf(tester, find.byKey(const ValueKey('drawn'))) as DrawnIconPainter;
      expect((clock.filled, clock.cut), (true, AppIcons.clock.cut));

      // Back to the outline: as it always was.
      preferences.update((now) => now.copyWith(iconStyle: 'outline'));
      await tester.pump();
      expect(painterOf(tester, find.byKey(const ValueKey('kit'))), isA<DrawnIconPainter>());
      debugDisableShadows = true;
    });

    testWidgets('a glyph a pack has not got is Lucide’s, in the chosen style', (tester) async {
      await pumpApp(tester, prefs: const Preferences(theme: 'light', iconPack: 'phosphor', iconStyle: 'filled'), home: const Center(child: AppIcon(Lucide.bookmarkCheck, key: ValueKey('kit'))));
      final drawing = (painterOf(tester, find.byKey(const ValueKey('kit'))) as PackIconPainter).drawing;
      expect((drawing.fallback, drawing.ink), (true, IconInk.cutLines));
      expect(drawing.glyph.paths, same(Lucide.bookmarkCheck.shapes));
      debugDisableShadows = true;
    });

    testWidgets('every style of every pack paints', (tester) async {
      await pumpApp(
        tester,
        prefs: const Preferences(theme: 'light'),
        home: Wrap(children: [
          for (final pack in iconPacks)
            for (final style in IconStyle.values)
              for (final name in iconPreviewNames) AppIcon(Lucide.all[name]!, size: 12, look: IconLook(pack.id, style)),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AppIcon), findsNWidgets(iconPacks.length * 3 * iconPreviewNames.length));
      debugDisableShadows = true;
    });
  });

  group('the preferences', () {
    test('keep the pack and the style, travel with the person, and read one this build cannot draw as Lucide’s outline', () {
      const chosen = Preferences(iconPack: 'tabler', iconStyle: 'filled');
      final read = Preferences.fromJson(jsonDecode(jsonEncode(chosen.toJson())));
      expect((read.iconPack, read.iconStyle), ('tabler', 'filled'));
      expect(Preferences.fromJson({'iconPack': 'heroicons', 'iconStyle': 'duotone'}).iconPack, 'lucide');
      expect(Preferences.fromJson({'iconPack': 'heroicons', 'iconStyle': 'duotone'}).iconStyle, 'outline');
      expect(syncedPrefs, containsAll(['iconPack', 'iconStyle']));
      expect(pickSynced(chosen.toJson()), allOf(containsPair('iconPack', 'tabler'), containsPair('iconStyle', 'filled')));
      // Not a page attribute: the web's stamps stay as they were.
      expect(chosen.attrs.keys, isNot(anyOf(contains('icon-pack'), contains('icons'))));
    });
  });

  test('the packs’ licences are among the app’s', () async {
    registerIconPackLicences();
    registerIconPackLicences();
    final packages = <String>[];
    await for (final licence in LicenseRegistry.licenses) {
      packages.addAll(licence.packages);
    }
    expect(packages, containsAll(['Lucide icons', 'Phosphor icons', 'Tabler icons', 'Material Symbols icons', 'Remix Icon icons']));
    expect(packages.where((p) => p == 'Phosphor icons'), hasLength(1));
  });
}
