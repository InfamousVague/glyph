import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';

import '../support/header_bar.dart';
import '../support/render.dart';
import 'support.dart';

/// Pictures of a note's screen and its More sheet, drawn with the real faces, for looking at beside the web page's
/// own (test/note/reference/web-note-*.png, web-sheet-*.png): `flutter test --update-goldens
/// test/note/note_shots_test.dart`, then open `test/note/shots/`.
void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    for (final width in [390, 840]) {
      final size = Size(width.toDouble(), width == 390 ? 844 : 900);
      final body = webNote(width)['body'] as String;

      Future<void> picture(WidgetTester tester, String name) async {
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }

      testWidgets('a note at $width, $theme', (tester) async {
        final world = NoteWorld();
        final note = await tester.runAsync(() => seedNote(world, 'lisbon', body));
        await pumpNote(tester, world, note!, size: size, theme: theme, seams: measuredSeams(world.asked), speak: true);
        await picture(tester, 'note-$width-$theme');
        await closeNote(tester);
      });

      testWidgets('its More sheet at $width, $theme', (tester) async {
        if (width == 840) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final world = NoteWorld();
        final note = await tester.runAsync(() => seedNote(world, 'lisbon', body));
        await pumpNote(tester, world, note!, size: size, theme: theme, seams: measuredSeams(world.asked), speak: true);
        // More from the default bar, Grouped command: its row under ••• on a phone.
        await pressInBar(tester, 'more', label: 'More for this note');
        await picture(tester, 'sheet-$width-$theme');
        await closeNote(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('a new note’s blank page', (tester) async {
    final world = NoteWorld();
    final note = world.library.create('');
    await pumpNote(tester, world, note);
    // The ghost is a picture read from the app's assets, which a test's clock never finishes.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/note-blank.png'));
    await closeNote(tester);
  });
}
