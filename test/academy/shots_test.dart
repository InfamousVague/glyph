// Pictures of the Academy for the eye, beside the page's own (fixtures/web/<page>-<theme>.png, which
// fixtures/web_academy.mjs took in Chromium): `flutter test --update-goldens test/academy/shots_test.dart` writes
// test/academy/shots/. The screen is under a test's 36 px status bar, which the page was not. The contents are drawn
// on a screen as tall as the page was long, so the whole of both can be looked at side by side.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/lessons.dart';

import 'reference_test.dart' show learnedSome;
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('the contents, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme, size: const Size(390, 1190));
      await shot(tester, 'contents-$theme');
    });

    testWidgets('a lesson, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme);
      await press(tester, key('academy-go'));
      await shot(tester, 'lesson-$theme');
    });

    testWidgets('a lesson passed, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme);
      await press(tester, key('academy-go'));
      await press(tester, key('academy-show-me'));
      await shot(tester, 'lesson-passed-$theme');
    });

    testWidgets('the contents with some of it learned, $theme', (tester) async {
      freshDevice(learned: learnedSome);
      await showAcademy(tester, theme: theme, size: const Size(390, 1190));
      await shot(tester, 'contents-begun-$theme');
    });

    testWidgets('the end of a chapter, $theme', (tester) async {
      freshDevice(learned: learnedSome);
      await showAcademy(tester, theme: theme);
      await press(tester, key('chapter:Links and places'));
      await press(tester, key('academy-next'));
      await shot(tester, 'chapter-end-$theme');
    });

    testWidgets('a chapter learned, seen off by the ghost, $theme', (tester) async {
      freshDevice(learned: {for (final lesson in lessonsIn('Markdown basics')) lesson.id});
      await showAcademy(tester, theme: theme);
      await press(tester, key('chapter:Markdown basics'));
      for (var i = 0; i < lessonsIn('Markdown basics').length; i++) {
        await press(tester, key('academy-next'));
      }
      // The ghost's picture, which a test's clock never loads by itself.
      for (final element in find.byType(Image, skipOffstage: false).evaluate().toList()) {
        await tester.runAsync(() => precacheImage((element.widget as Image).image, element));
      }
      await settle(tester, 2);
      await shot(tester, 'chapter-learned-$theme');
    });

    testWidgets('the contents in Simple, the rest behind More, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme, size: const Size(390, 1190), simple: true);
      await shot(tester, 'contents-simple-$theme');
    });

    // The wide screens: an unfolded Fold, and a window on the Mac.
    for (final (name, size) in [('fold', const Size(884, 1104)), ('mac', const Size(1280, 800))]) {
      testWidgets('the contents on the $name, $theme', (tester) async {
        freshDevice(learned: learnedSome);
        await showAcademy(tester, theme: theme, size: size);
        await shot(tester, 'contents-$name-$theme');
      });

      testWidgets('a lesson on the $name, $theme', (tester) async {
        freshDevice(learned: learnedSome);
        await showAcademy(tester, theme: theme, size: size);
        await press(tester, key('academy-go'));
        await press(tester, key('academy-show-me'));
        await shot(tester, 'lesson-$name-$theme');
      });
    }

    testWidgets('a choice picked and a long praise, $theme', (tester) async {
      final choice = lessons.firstWhere((lesson) => lesson.id == 'choice');
      freshDevice(learned: {for (final lesson in lessons.take(lessons.indexOf(choice))) lesson.id});
      await showAcademy(tester, theme: theme);
      await press(tester, key('academy-go'));
      await press(tester, key('academy-show-me'));
      await shot(tester, 'lesson-choice-$theme');
    });
  }
}
