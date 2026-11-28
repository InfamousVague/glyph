import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/art/loading_logo.dart';

import 'support/drawn_ink.dart';

/// The logo of the splash the app opens with (lib/art/loading_logo.dart): large, still, and drawn in the page's ink.
/// It turned for one release (0.12.54, Matt's film of it); the same day, Matt: "actually just do the static image,
/// the video doesn't look good". Pictures in build/themes/loading-logo.
void main() {
  test('the logo\'s picture is in the app: one picture, large, the logo white on black', () async {
    final file = File(LoadingLogo.asset);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), lessThan(100 * 1024), reason: 'a picture, not a film: under 100 KB');
    final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
    expect(codec.frameCount, 1, reason: 'still');
    final frame = await codec.getNextFrame();
    expect((frame.image.width, frame.image.height), (1240, 958));
    expect(frame.image.width / frame.image.height, closeTo(LoadingLogo.shape, 0.0001));
    // Large enough to be sharp across an unfolded phone: the splash draws it 300 wide at most, at up to 3.5 dots each.
    expect(frame.image.width, greaterThanOrEqualTo(300 * 3.5));
    // Solid, black round its edges (what the app draws as nothing) and the logo within, about a third of it white.
    final dots = (await frame.image.toByteData())!;
    var white = 0, black = 0;
    for (var i = 0; i < dots.lengthInBytes; i += 4) {
      expect(dots.getUint8(i + 3), 255, reason: 'solid, not see-through');
      if (dots.getUint8(i) > 247) white++;
      if (dots.getUint8(i) == 0) black++;
    }
    final all = dots.lengthInBytes / 4;
    expect(white / all, inInclusiveRange(0.3, 0.4));
    expect(black / all, inInclusiveRange(0.58, 0.7), reason: 'the black is none of anything: nothing nearly black to show as a haze');
    for (var x = 0; x < frame.image.width; x++) {
      expect(dots.getUint8(x * 4), 0, reason: 'the top row is black');
      expect(dots.getUint8(((frame.image.height - 1) * frame.image.width + x) * 4), 0, reason: 'the bottom row is black');
    }
    frame.image.dispose();
    codec.dispose();
    // And nothing of the film is carried any more.
    for (final gone in ['assets/art/loading-logo.webp', 'assets/art/loading-logo-still.webp', 'art/loading_logo.mp4']) {
      expect(File(gone).existsSync(), isFalse, reason: gone);
    }
  });

  test('a black and white picture is drawn in a colour: as solid as the picture is bright', () {
    final m = LoadingLogo.inked(const Color(0xFF204060));
    expect([m[4], m[9], m[14]], [0x20, 0x40, 0x60], reason: 'the colour\'s own red, green and blue, whatever the picture has');
    for (final i in [0, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 16, 17, 18, 19]) {
      expect(m[i], 0, reason: 'nothing of the picture\'s own colour, and how solid comes of its red alone ($i)');
    }
    expect(m[15], 1, reason: 'as solid as the picture is bright: none at its black, all at its white');
  });

  // On a light page, a dark one, and one that is neither black nor white: the logo in the ink, the page everywhere
  // else, and nothing of the picture's black.
  for (final (name, page, ink) in [
    ('light', const Color(0xFFFFFFFF), const Color(0xFF000000)),
    ('dark', const Color(0xFF000000), const Color(0xFFFFFFFF)),
    ('coloured', const Color(0xFFFDF6E3), const Color(0xFF2B6CB0)),
  ]) {
    testWidgets('it is drawn in the page\'s ink on the page ($name)', (tester) async {
      tester.view.physicalSize = const Size(300, 340) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ColoredBox(color: page, child: Center(child: LoadingLogo(width: 240, color: ink))));
      // Nothing in its place until the picture is read, and nothing wrong.
      expect(tester.getSize(find.byType(LoadingLogo)), Size(240, 240 / LoadingLogo.shape));
      expect(tester.takeException(), isNull);
      expect(find.byType(RawImage), findsNothing);
      await pictureShown(tester, find.byType(RawImage));
      final drawn = await Drawn.of(tester, tester.element(find.byType(LoadingLogo)));
      drawn.keep('build/themes/loading-logo/$name.png');
      final box = tester.getRect(find.byType(LoadingLogo));
      final shares = drawn.shares(box, ink: ink, page: page);
      // The logo is about a third of its picture and the page the rest (round it, and its letters): a black slab
      // where the logo should be would have no page in it, a logo not drawn no ink.
      expect(shares.ink, inInclusiveRange(0.25, 0.45), reason: '$shares');
      expect(shares.page, inInclusiveRange(0.5, 0.72), reason: '$shares');
      expect(shares.ink + shares.page, greaterThan(0.93), reason: 'only its edges are between the two: $shares');
      expect(shares.other, 0, reason: 'no colour but the ink, the page and between them: $shares');
      // The page untouched round it, to the last part in 255, and no line along the edges of its place.
      expect(drawn.at(const Offset(4, 4)), page);
      for (final edge in [Rect.fromLTWH(box.left, box.top, box.width, 2), Rect.fromLTWH(box.left, box.bottom - 2, box.width, 2), Rect.fromLTWH(box.left, box.top, 2, box.height), Rect.fromLTWH(box.right - 2, box.top, 2, box.height)]) {
        expect(drawn.not(edge, page), 0, reason: 'a line along $edge');
      }
      expect(drawn.not(Rect.fromLTWH(0, 0, 300, box.top), page), 0);
      expect(drawn.not(Rect.fromLTWH(0, box.bottom, 300, 340 - box.bottom), page), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a see-through ink is the solid one drawn see-through', (tester) async {
    await tester.pumpWidget(const Center(child: LoadingLogo(width: 240, color: Color(0x80204060))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, closeTo(0x80 / 255, 0.001));
    expect(LoadingLogo.inked(const Color(0x80204060)), LoadingLogo.inked(const Color(0xFF204060)));
    await tester.pumpWidget(const Center(child: LoadingLogo(width: 240, color: Color(0xFF204060))));
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('it is still: the same picture however long it is up, and whether or not the device is asked to move less', (tester) async {
    for (final less in [false, true]) {
      await tester.pumpWidget(MediaQuery(
        key: ValueKey(less),
        data: MediaQueryData(disableAnimations: less),
        child: const Center(child: LoadingLogo(width: 240, color: Color(0xFF112233))),
      ));
      expect((tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName, LoadingLogo.asset);
      await pictureShown(tester, find.byType(RawImage));
      final first = tester.widget<RawImage>(find.byType(RawImage)).image;
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.isCloneOf(first!), isTrue, reason: 'no next frame: it is one picture');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing of it asks to be drawn again');
    }
  });

  testWidgets('it says once when it is first on the page', (tester) async {
    final said = <bool>[];
    await tester.pumpWidget(Center(child: LoadingLogo(width: 240, color: const Color(0xFF000000), onShown: said.add)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(said, isEmpty, reason: 'not before the picture is read');
    await pictureShown(tester, find.byType(RawImage));
    await tester.pump();
    expect(said, [true]);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(said, [true], reason: 'once');
  });

  testWidgets('a build that can\'t read it leaves its place empty and says so', (tester) async {
    final said = <bool>[];
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _Nothing(),
      child: Center(child: LoadingLogo(width: 240, color: const Color(0xFF000000), onShown: said.add)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(said, [false]);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.getSize(find.byType(LoadingLogo)), Size(240, 240 / LoadingLogo.shape));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture is let go of once the logo is gone', (tester) async {
    await tester.pumpWidget(const Center(child: LoadingLogo(width: 240, color: Color(0xFF000000))));
    await pictureShown(tester, find.byType(RawImage));
    late Object key;
    await tester.runAsync(() async => key = await const AssetImage(LoadingLogo.asset).obtainKey(ImageConfiguration.empty));
    expect(imageCache.containsKey(key), isTrue);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(imageCache.containsKey(key), isFalse, reason: 'a few megabytes, not kept for as long as the app runs');
  });
}

/// A build with none of the app's pictures in it.
class _Nothing extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('no $key in this build');
}
