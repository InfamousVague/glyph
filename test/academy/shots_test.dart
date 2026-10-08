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
