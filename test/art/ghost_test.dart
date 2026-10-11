import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/art.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The ghost and the mark, case for case with the web app's art/Ghost.test.tsx: a picture for every scene, drawn in
/// the page's ink through its picture, hidden from a screen reader, at the size asked.
void main() {
  test('has a picture for every scene, each its own file, in the bundle', () {
    final files = GhostScene.values.map((scene) => scene.asset).toList();
    expect(files, hasLength(14));
    expect(files.toSet(), hasLength(14));
    for (final file in files) {
      expect(File(file).existsSync(), isTrue, reason: file);
    }
    // And each is the web app's own, byte for byte, where that checkout is beside this one.
    final theirs = Directory('tauri/src/app/art/ghosts');
    if (theirs.existsSync()) {
      for (final scene in GhostScene.values) {
        expect(File(scene.asset).readAsBytesSync(), File('${theirs.path}/${scene.file}.webp').readAsBytesSync(), reason: scene.file);
      }
    }
  });

  test('keeps each picture\'s own shape, cropped to its drawing', () {
    expect(GhostScene.noNotes.ratio, closeTo(811 / 1024, 1e-12));
    expect(GhostScene.emptyCanvas.ratio, closeTo(1024 / 697, 1e-12));
    expect(GhostScene.values.where((scene) => scene.ratio == 1), isEmpty);
  });

  test('is as wide as its column, up to a share of the window\'s height and a ceiling', () {
    const scene = GhostScene.noNotes;
    double width(GhostSize size, {double available = 2000, double window = 800, double? share}) =>
        Ghost.widthFor(scene, size, available: available, windowHeight: window, rem: 16, heightShare: share);
    // Small: 40% of the height, at the picture's own shape; lead: 45%.
    expect(width(GhostSize.small), closeTo(0.40 * 800 * scene.ratio, 1e-9));
    expect(width(GhostSize.lead), closeTo(0.45 * 800 * scene.ratio, 1e-9));
    // Never wider than its column, nor than 28rem and 36rem on a tall screen.
    expect(width(GhostSize.small, available: 200), 200);
    expect(width(GhostSize.small, window: 4000), 28 * 16);
    expect(width(GhostSize.lead, window: 4000), 36 * 16);
    // In a card: 3rem tall, whatever the room.
    expect(width(GhostSize.tiny, available: 20), closeTo(3 * 16 * scene.ratio, 1e-9));
    // And a screen's own stylesheet may hold it lower, as the home page's does on a phone.
    expect(width(GhostSize.lead, share: 0.38), closeTo(0.38 * 800 * scene.ratio, 1e-9));
  });

  testWidgets('is drawn in the page\'s ink through its picture, hidden from a screen reader, at the size asked', (tester) async {
    await pumpApp(
      tester,
      prefs: const AppPreferences(theme: 'dark'),
      home: const Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, child: Ghost(scene: GhostScene.noNotes, size: GhostSize.lead, align: GhostAlign.center))),
    );
    final picture = tester.widget<Image>(find.byType(Image));
    final tokens = tester.element(find.byType(Ghost)).tokens;
    // The quiet ink, laid in through the picture's dots.
    expect(picture.color, tokens.color('app-ink-3'));
    expect(picture.colorBlendMode, BlendMode.srcIn);
    expect((picture.image as AssetImage).assetName, GhostScene.noNotes.asset);
    final size = tester.getSize(find.byType(Image));
    expect(size.width / size.height, closeTo(GhostScene.noNotes.ratio, 1e-3));
    // In the middle of its column.
    final box = tester.getRect(find.byType(Image));
    expect(box.center.dx, closeTo(150, 0.5));
    expect(tester.getSemantics(find.byType(Ghost)).label, isEmpty);
    debugDisableShadows = true;
  });

  testWidgets('is small and at the start unless told otherwise, and takes the ink it is given', (tester) async {
    await pumpApp(
      tester,
      home: const Align(alignment: Alignment.topLeft, child: SizedBox(width: 300, child: Ghost(scene: GhostScene.welcome, color: Color(0xFF123456)))),
    );
    expect(tester.widget<Image>(find.byType(Image)).color, const Color(0xFF123456));
    expect(tester.getRect(find.byType(Image)).left, 0);
    expect(tester.getSize(find.byType(Image)).width, closeTo(Ghost.widthFor(GhostScene.welcome, GhostSize.small, available: 300, windowHeight: 844, rem: 16), 0.5));
    debugDisableShadows = true;
  });

  test('the mark is its six shapes: a wisp, an outline, the paper and the fold inside it, and two eyes', () {
    expect(ghostMarkShapes.map((shape) => shape.part.name).toList(), ['wisp', 'outline', 'body', 'fold', 'eye', 'eye']);
    expect(ghostMarkShapes.where((shape) => shape.ink).length, 4);
    expect(ghostMarkBox, [133.5, 120, 1167, 1167]);
    for (final shape in ghostMarkShapes) {
      // Every shape lies inside the mark's own box.
      final bounds = svgPath(shape.d).getBounds();
      expect(bounds.left, greaterThanOrEqualTo(ghostMarkBox[0]));
      expect(bounds.bottom, lessThanOrEqualTo(ghostMarkBox[1] + ghostMarkBox[3]));
    }
  });

  testWidgets('the mark turns over with the theme: its lines in the page\'s ink, its paper in the page\'s paper', (tester) async {
    await pumpApp(tester, prefs: const AppPreferences(theme: 'dark'), home: const Center(child: GhostMark(size: 80)));
    expect(tester.getSize(find.byType(GhostMark)), const Size(80, 80));
    expect(tester.takeException(), isNull);
    debugDisableShadows = true;
  });
}
