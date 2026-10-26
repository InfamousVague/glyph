// Lovart in the editor: the mark on the corner of a picture Lovart made (lib/editor/media/lovart_badge.dart), and the
// mark after a `{image: …}` while the plugin is on, a tap making that cue (lib/editor/ai/lovart_cues.dart). Pictures of
// both, light and dark, in build/feature-shots/lovart/ with --update-goldens.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/ai/lovart_cues.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/note_plugins.dart' show noteEditing;
import 'package:ghost_md/editor/media/images.dart' show KeptPicture;
import 'package:ghost_md/editor/media/lovart_badge.dart';
import 'package:ghost_md/editor/media/lovart_pending.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:glacier/glacier.dart';

import '../../plugins/support.dart';
import '../../support/render.dart';

/// A picture of [size], light or dark, as PNG bytes: a soft gradient with a few shapes, so a badge on it is seen as it
/// would be on a real one.
Future<Uint8List> paintedPng({required bool dark, Size size = const Size(360, 220)}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Offset.zero & size;
  final colors = dark ? const [Color(0xFF101828), Color(0xFF3B2A5A)] : const [Color(0xFFFFF4E0), Color(0xFFE7F0FF)];
  canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, colors));
  canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.45), 50, Paint()..color = dark ? const Color(0xFFE76F51) : const Color(0xFF2A9D8F));
  canvas.drawRect(Rect.fromLTWH(size.width * 0.55, size.height * 0.25, 110, 90), Paint()..color = dark ? const Color(0xFFF4A261) : const Color(0xFF264653));
  final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Lovart answering each prompt with one picture.
class FakeClient extends LovartClient {
  FakeClient(this.bytes) : super(accessKey: 'ak', secretKey: 'sk');
  final Uint8List bytes;
  final List<String> asked = [];

  @override
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) async {
    asked.add(prompt);
    return [bytes];
  }
}

/// A note on the screen with its cues marked, and pictures under it.
class Stage {
  bool on = true;
  final Set<String> busy = {};
  final ValueNotifier<int> told = ValueNotifier<int>(0);
  final List<String> pressed = [];
  void Function(ImageCue cue)? onPress;
  late final EditorView view;

  Future<void> show(WidgetTester tester, String doc, {String theme = 'light', PictureStore? pictures, List<String> below = const [], double width = 390, double height = 640}) async {
    view = EditorView(
      wholeDocument: true,
      state: EditorState.create(
        doc: doc,
        extensions: noteExtensions(
          more: <Extension>[
            lovartCues(LovartCueHooks(
              on: () => on,
              press: (cue) {
                pressed.add(cue.prompt);
                onPress?.call(cue);
              },
              making: busy.contains,
              changes: told,
            )),
          ],
        ),
      ),
    );
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: Size(width, height),
      ratio: 3,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => BackScope(
          child: ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EditorColumn(view: view),
                    for (final name in below)
                      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: KeptPicture(key: ValueKey(name), name: name, store: pictures, radius: 8)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void tell() => told.value += 1;
}

Finder get chip => find.byType(LovartCueChip);

void main() {
  setUpAll(loadAppFonts);

  group('the badge', () {
    testWidgets('is on a picture Lovart made, and on no other', (tester) async {
      final bytes = (await tester.runAsync(() => paintedPng(dark: false)))!;
      final pictures = MemoryPictureStore({'lovart-0b8e.png': bytes, 'photo.png': bytes});
      final stage = Stage();
      await stage.show(tester, '# Pictures', pictures: pictures, below: ['lovart-0b8e.png', 'photo.png']);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(find.descendant(of: find.byKey(const ValueKey('lovart-0b8e.png')), matching: find.byType(LovartBadge)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('photo.png')), matching: find.byType(LovartBadge)), findsNothing);
      expect(find.bySemanticsLabel('Made with Lovart'), findsOneWidget);
      // At the bottom right, inset from the corner.
      final picture = tester.getRect(find.descendant(of: find.byKey(const ValueKey('lovart-0b8e.png')), matching: find.byType(RawImage)));
      final badge = tester.getRect(find.byType(LovartBadge));
      expect((picture.right - badge.right, picture.bottom - badge.bottom), (lovartBadgeInset, lovartBadgeInset));
      expect(badge.size, const Size.square(lovartBadgeSize));
      await away(tester);
    });

    test('names a picture Lovart made by its name alone', () {
      expect(madeByLovart('lovart-1f2e.png'), isTrue);
      expect(madeByLovart('photo-lovart.png'), isFalse);
    });
  });

  group('the mark by a cue', () {
    testWidgets('is after a cue that is closed and has words, while the plugin is on, and never by a blank', (tester) async {
      final stage = Stage();
      await stage.show(tester, 'A cover {image: a fox in one line} and {?what day}\n{image: still typing');
      expect(chip, findsOneWidget);
      stage.on = false;
      stage.tell();
      await tester.pump();
      await tester.pump();
      expect(chip, findsNothing);
      stage.on = true;
      stage.tell();
      await tester.pump();
      await tester.pump();
      expect(chip, findsOneWidget);
      await away(tester);
    });

    testWidgets('turns while its cue is made', (tester) async {
      final stage = Stage();
      await stage.show(tester, '{image: a lamp}');
      expect(find.byKey(const ValueKey('lovart-cue')), findsOneWidget);
      stage.busy.add('{image: a lamp}');
      stage.tell();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('lovart-cue-busy')), findsOneWidget);
      await away(tester);
    });

    // Matt, 2026-10-26: "when hitting return start to generate the image, place a blurry abstract image with the lovart
    // logo and a loading circle around it".
    testWidgets('Return at the end of a cue’s line makes it; Return anywhere else does not', (tester) async {
      final stage = Stage();
      await stage.show(tester, 'The hero {image: a misty forest} goes on top.\n{image: a red chair}\n{image: a lamp} and more');
      Future<void> enterAt(int at) async {
        stage.view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: '\n'), userEvent: 'input'));
        await tester.pump();
        await tester.pump();
      }

      final doc = stage.view.state.doc;
      // In the middle of a line with a cue in it, and at the end of one whose last words are not the cue: nothing.
      await enterAt(doc.line(1).from + 4);
      await enterAt(stage.view.state.doc.line(4).to);
      expect(stage.pressed, isEmpty);
      // At the end of a line that ends in its cue: that cue.
      await enterAt(stage.view.state.doc.line(3).to);
      expect(stage.pressed, ['a red chair']);
      // Not again while it is being made.
      stage.busy.add('{image: a red chair}');
      stage.tell();
      await tester.pump();
      await enterAt(stage.view.state.doc.line(3).to);
      expect(stage.pressed, ['a red chair']);
      // With the plugin off, Return is only Return.
      stage
        ..on = false
        ..busy.clear();
      stage.tell();
      await tester.pump();
      await enterAt(stage.view.state.doc.line(3).to);
      expect(stage.pressed, ['a red chair']);
      await away(tester);
    });

    testWidgets('while a cue is made, a blurred stand-in with Lovart’s mark and a turning ring is under its line, and goes when it is done', (tester) async {
      final stage = Stage();
      await stage.show(tester, '{image: a red chair}\nAfter it.');
      expect(find.byType(LovartPending), findsNothing);
      stage.busy.add('{image: a red chair}');
      stage.tell();
      await tester.pump();
      await tester.pump();
      expect(find.byType(LovartPending), findsOneWidget);
      expect(find.byKey(const ValueKey('lovart-working')), findsOneWidget);
      expect(find.bySemanticsLabel('Lovart is making: a red chair'), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);
      // Under the cue's line: below the cue's mark.
      expect(tester.getRect(find.byType(LovartPending)).top, greaterThanOrEqualTo(tester.getRect(chip).bottom));
      // Nothing of it is in the note.
      expect(stage.view.state.doc.toString(), '{image: a red chair}\nAfter it.');
      stage.busy.clear();
      stage.tell();
      await tester.pump();
      await tester.pump();
      expect(find.byType(LovartPending), findsNothing);
      await away(tester);
    });

    testWidgets('a tap makes that cue into its picture, with Lovart', (tester) async {
      final bytes = (await tester.runAsync(() => paintedPng(dark: false)))!;
      final ground = TestGround();
      usePluginGround(ground.ground);
      addTearDown(() => usePluginGround(PluginGround()));
      final pictures = MemoryPictureStore();
      lovartPictureStore = pictures;
      addTearDown(() => lovartPictureStore = null);
      final fake = FakeClient(bytes);
      lovartClient = () => fake;
      addTearDown(() => lovartClient = () => LovartClient.kept());
      await lovart.host.secrets.write(accessKeySecret, 'ak');
      await lovart.host.secrets.write(secretKeySecret, 'sk');

      final stage = Stage();
      final said = <String>[];
      await stage.show(tester, 'First {image: a red chair}\nThen {image: a blue lamp}');
      stage.onPress = (cue) => makeCue(noteEditing('n1', stage.view, () => stage.view.state.doc.toString(), said.add), cue);
      expect(chip, findsNWidgets(2));
      await tester.tap(chip.last);
      await tester.pump();
      await tester.pump();
      expect(stage.pressed, ['a blue lamp']);
      expect(fake.asked, ['a blue lamp\n\nMake one image.']);
      final name = pictures.kept.keys.single;
      expect(stage.view.state.doc.toString(), 'First {image: a red chair}\nThen\n![a blue lamp](image/$name)');
      expect(said, isEmpty);
      await away(tester);
    });
  });

  group('pictures', () {
    for (final theme in const ['light', 'dark']) {
      testWidgets('the badge and the mark by a cue, $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final light = (await tester.runAsync(() => paintedPng(dark: false)))!;
        final dark = (await tester.runAsync(() => paintedPng(dark: true)))!;
        final pictures = MemoryPictureStore({'lovart-light.png': light, 'lovart-dark.png': dark});
        final stage = Stage();
        await stage.show(
          tester,
          '# Homepage ideas\n\nThe hero {image: a misty forest at dawn, soft light} goes on top.\n\n{image: three logo marks for a fox brand}\n\nAnd a blank stays a blank: {?what day}',
          theme: theme,
          pictures: pictures,
          below: ['lovart-light.png', 'lovart-dark.png'],
          height: 1400,
        );
        stage.busy.add('{image: three logo marks for a fox brand}');
        stage.tell();
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        Directory('build/feature-shots/lovart').createSync(recursive: true);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../../build/feature-shots/lovart/lovart-$theme.png'));
        await away(tester);
      });
    }
  });
}

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
