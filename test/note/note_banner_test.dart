// A note's header banner on its page (lib/note/note_banner.dart, the note screen's `banner` seam, lib/core/banner.dart).
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/banner.dart';
import 'package:ghost_md/app/preferences.dart' show AppPreferences;
import 'package:glacier/glacier.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/lovart_badge.dart' show LovartBadge;
import 'package:ghost_md/note/note_banner.dart';
import 'package:ghost_md/note/note_screen.dart';

import '../support/render.dart';
import 'support.dart';

final Uint8List _png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 9, 9]);

void main() {
  setUpAll(loadAppFonts);
  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'banner${made += 1}', body)))!;

  testWidgets('the page asks for the banner its front matter names, and again as it changes while open', (tester) async {
    final world = NoteWorld();
    final asked = <String?>[];
    final seams = NoteSeams(banner: (context, id, name) {
      asked.add(name);
      return SizedBox(key: ValueKey('banner ${name ?? 'none'}'), height: name == null ? 1 : 40);
    });
    final screen = await pumpNote(tester, world, await seeded(tester, world, withBanner('# Trip\n\nWords.', 'lovart-a.png')), seams: seams);
    expect(find.byKey(const ValueKey('banner lovart-a.png')), findsOneWidget);
    final doc = screen.view!.state.doc.toString();
    // Taken off, as the cog's Header image or a hand would change the front matter.
    screen.view!.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: doc.length, insert: '# Trip\n\nWords.'), userEvent: 'input.type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('banner none')), findsOneWidget);
    screen.view!.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: screen.view!.state.doc.length, insert: withBanner('# Trip\n\nWords.', 'lovart-b.png')), userEvent: 'input.type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('banner lovart-b.png')), findsOneWidget);
    expect(asked, containsAllInOrder(<String?>['lovart-a.png', null, 'lovart-b.png']));
    await closeNote(tester);
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('a note\'s top with its banner, $theme', (tester) async {
      final store = MemoryPictureStore();
      final bytes = File('test/note/fixtures/banner-sample.png').readAsBytesSync();
      await tester.runAsync(() => store.keep('lovart-sample.png', bytes));
      await pumpApp(
        tester,
        size: const Size(420, 440),
        prefs: AppPreferences(theme: theme),
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                NoteBannerView(name: 'lovart-sample.png', store: store),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.tokens.len('app-gutter')),
                  child: Text('Cabin weekend', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: context.tokens.color('app-ink'))),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(context.tokens.len('app-gutter'), 8, context.tokens.len('app-gutter'), 0),
                  child: Text('The drive up, the key under the third stone, the wood to split before dark.', style: TextStyle(fontSize: 16, color: context.tokens.color('app-ink-2'))),
                ),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await expectLater(find.byType(ColoredBox).first, matchesGoldenFile('shots/note-banner-$theme.png'));
      debugDisableShadows = true;
    });
  }

  testWidgets('a notebook\'s index draws its banner over its chapters, a journal\'s does not', (tester) async {
    final world = NoteWorld();
    final asked = <String?>[];
    final seams = NoteSeams(banner: (context, id, name) {
      asked.add(name);
      return SizedBox(key: ValueKey('banner ${name ?? 'none'}'), height: 40);
    });
    await pumpNote(tester, world, await seeded(tester, world, withBanner('---\nbook: true\n---\n# Trip book\n\n1. [[Day one]]\n2. [[Day two]]', 'lovart-cover.png')), seams: seams);
    expect(find.byKey(const ValueKey('banner lovart-cover.png')), findsOneWidget);
    await closeNote(tester);
    asked.clear();
    await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\njournal: true\n---\n# Days\n\n- [[2026-10-27 09.00]]'), seams: seams);
    expect(asked, isEmpty);
    await closeNote(tester);
  });

  group('the banner', () {
    testWidgets('draws the kept picture four times as wide as tall, with Lovart\'s mark', (tester) async {
      final store = MemoryPictureStore();
      await tester.runAsync(() => store.keep('lovart-a.png', _png));
      await pumpApp(tester, size: const Size(420, 600), home: Align(alignment: Alignment.topCenter, child: NoteBannerView(name: 'lovart-a.png', store: store)));
      await tester.pump();
      final box = tester.getSize(find.byKey(const ValueKey('note-banner-lovart-a.png')));
      expect(box.width / box.height, closeTo(bannerAspect, 0.01));
      expect(find.byType(LovartBadge), findsOneWidget);
      debugDisableShadows = true;
    });

    testWidgets('is Lovart at work while one is made, and nothing with neither', (tester) async {
      await pumpApp(tester, home: const Align(alignment: Alignment.topCenter, child: NoteBannerView(name: null, store: null, making: true, prompt: 'n1')));
      expect(find.byKey(const ValueKey('note-banner-making')), findsOneWidget);
      await pumpApp(tester, home: const Align(alignment: Alignment.topCenter, child: NoteBannerView(name: null, store: null)));
      expect(find.byKey(const ValueKey('note-banner-making')), findsNothing);
      expect(find.byType(NoteBannerView), findsOneWidget);
      expect(tester.getSize(find.byType(NoteBannerView)), Size.zero);
      debugDisableShadows = true;
    });

    test('is drawn in the page\'s inks: white is the paper and black the ink', () {
      const ink = Color(0xFF101010), paper = Color(0xFFF5F0E6);
      final matrix = inkOnPaper(ink, paper).toString();
      expect(matrix, contains('matrix'));
      // Each channel: out = ink + (paper - ink) × in, so in 0 is the ink and in 1 the paper.
      double channel(double inkC, double paperC, double v) => inkC + (paperC - inkC) * v;
      expect(channel(ink.r, paper.r, 0), ink.r);
      expect(channel(ink.r, paper.r, 1), closeTo(paper.r, 1e-9));
    });
  });

  Future<Uint8List> png(Color fill, {Color? dots}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 128, 32), Paint()..color = fill);
    if (dots != null) {
      for (var x = 4.0; x < 128; x += 8) {
        canvas.drawCircle(Offset(x, 16), 3, Paint()..color = dots);
      }
    }
    final image = await recorder.endRecording().toImage(128, 32);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  testWidgets('a banner in colour is drawn in its own colours; one in black and white in the page\'s inks (Matt, 2026-10-26)', (tester) async {
    forgetBannerColours();
    final colour = (await tester.runAsync(() => png(const Color(0xFFFFFFFF), dots: const Color(0xFFD9482B))))!;
    final grey = (await tester.runAsync(() => png(const Color(0xFFFFFFFF), dots: const Color(0xFF222222))))!;
    expect((await tester.runAsync(() => pictureInColour(colour)))!, isTrue);
    expect((await tester.runAsync(() => pictureInColour(grey)))!, isFalse);
    final store = MemoryPictureStore({'lovart-colour.png': colour, 'lovart-grey.png': grey});
    Future<int> filters(String name) async {
      await pumpApp(tester, size: const Size(420, 300), prefs: const AppPreferences(theme: 'dark'), home: Align(alignment: Alignment.topCenter, child: NoteBannerView(key: ValueKey(name), name: name, store: store)));
      await tester.runAsync(() => bannerInColour(store, name));
      await tester.pump();
      return tester.widgetList(find.descendant(of: find.byType(NoteBannerView), matching: find.byType(ColorFiltered))).length;
    }
    expect(await filters('lovart-colour.png'), 0, reason: 'turned over, its reds would come out cyan');
    expect(await filters('lovart-grey.png'), 1, reason: 'black dots turn to light on the dark page, as before');
    debugDisableShadows = true;
  });

  test('a square picture with its drawing in a band is drawn at the band\'s shape, the drawing in the middle (Matt, 2026-10-26)', () {
    // Lovart's 1254×1254, the drawing across the middle: 10%–90% wide, 30%–60% high.
    const look = BannerLook(colour: true, aspect: 1, drawn: Rect.fromLTRB(0.1, 0.3, 0.9, 0.6));
    expect(look.shape, bannerWidest, reason: 'the drawing\'s own shape, 8:3, held to the widest');
    final at = look.alignmentIn(look.shape);
    // The box shows 1/2.5 of the height; centred on the drawing's middle, 0.45, it shows 0.25–0.65: all of it.
    final seen = 1 / look.shape, top = (at.y + 1) / 2 * (1 - seen);
    expect(top, lessThanOrEqualTo(0.3));
    expect(top + seen, greaterThanOrEqualTo(0.6));
    // A drawing as wide as a strip is held to the widest; one as tall as the picture to the tallest.
    expect(const BannerLook(colour: false, aspect: 1, drawn: Rect.fromLTRB(0, 0.45, 1, 0.5)).shape, bannerWidest);
    expect(const BannerLook(colour: false, aspect: 1, drawn: Rect.fromLTRB(0, 0, 1, 1)).shape, bannerTallest);
  });
}
