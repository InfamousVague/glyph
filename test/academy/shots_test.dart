// Pictures of the Academy for the eye, beside the page's own where it has one (fixtures/web/<page>-<theme>.png, which
// fixtures/web_academy.mjs took in Chromium): `flutter test --update-goldens test/academy/shots_test.dart` writes
// test/academy/shots/. The screen is under a test's 36 px status bar, which the page was not. The catalog of courses
// (Matt, 2026-11-02: "redo the academy homepage to be easier to browse like codecademy lessons") is the app's own,
// and is drawn on a screen tall enough for the whole of it; a course's page and its end are the app's too, the end
// in place of the page's chapter end.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/courses.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/plugins/gantt/gantt.dart' show ganttPlugin;
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/projects/suite.dart' show ProjectSuite;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/core/stored.dart';

import 'reference_test.dart' show learnedSome;
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('the catalog, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme, size: const Size(390, 4600));
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

    testWidgets('the catalog with some of it learned, the top of it, $theme', (tester) async {
      freshDevice(learned: learnedSome);
      await showAcademy(tester, theme: theme, size: const Size(390, 1190));
      await shot(tester, 'contents-begun-$theme');
    });

    testWidgets('a course’s page, begun, $theme', (tester) async {
      freshDevice(learned: learnedSome);
      await showAcademy(tester, theme: theme);
      await press(tester, key('course:basics'));
      await shot(tester, 'course-$theme');
    });

    testWidgets('a course whose plugin is off, on its shelf and on its page, $theme', (tester) async {
      ProjectSuite.debugAllOn = false;
      addTearDown(() => ProjectSuite.debugAllOn = true);
      useStored(MemoryStored());
      usePlugins(createRegistry(const [marksPlugin, ganttPlugin], store: MemorySwitches()));
      await showAcademy(tester, theme: theme, size: const Size(390, 4600));
      await shot(tester, 'contents-off-$theme');
      ProjectSuite.debugAllOn = false;
      useStored(MemoryStored());
      usePlugins(createRegistry(const [marksPlugin, ganttPlugin], store: MemorySwitches()));
      await showAcademy(tester, theme: theme);
      await press(tester, key('course:gantt'));
      await shot(tester, 'course-off-$theme');
    });

    testWidgets('the end of a course, $theme', (tester) async {
      freshDevice(learned: learnedSome);
      await showAcademy(tester, theme: theme);
      await press(tester, key('course:todos'));
      await press(tester, key('academy-course-start'));
      for (var i = 0; i < courseById('todos')!.lessonIds.length; i++) {
        await press(tester, key('academy-next'));
      }
      await shot(tester, 'course-end-$theme');
    });

    testWidgets('a course learned, seen off by the ghost, $theme', (tester) async {
      final basics = courseById('basics')!.lessonIds;
      freshDevice(learned: basics.toSet());
      await showAcademy(tester, theme: theme);
      await press(tester, key('course:basics'));
      await press(tester, key('academy-course-start'));
      for (var i = 0; i < basics.length; i++) {
        await press(tester, key('academy-next'));
      }
      // The ghost's picture, which a test's clock never loads by itself.
      for (final element in find.byType(Image, skipOffstage: false).evaluate().toList()) {
        await tester.runAsync(() => precacheImage((element.widget as Image).image, element));
      }
      await settle(tester, 2);
      await shot(tester, 'course-learned-$theme');
    });

    testWidgets('the catalog in Simple, the rest behind More, $theme', (tester) async {
      freshDevice();
      await showAcademy(tester, theme: theme, size: const Size(390, 1190), simple: true);
      await shot(tester, 'contents-simple-$theme');
    });

    // The wide screens: an unfolded Fold, and a window on the Mac.
    for (final (name, size) in [('fold', const Size(884, 1104)), ('mac', const Size(1280, 800))]) {
      testWidgets('the catalog on the $name, $theme', (tester) async {
        freshDevice(learned: learnedSome);
        await showAcademy(tester, theme: theme, size: Size(size.width, name == 'fold' ? 2600 : 2000));
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
      final offered = courseLessonsNow();
      freshDevice(learned: {for (final lesson in offered.take(offered.indexOf(choice))) lesson.id});
      await showAcademy(tester, theme: theme);
      await press(tester, key('academy-go'));
      await press(tester, key('academy-show-me'));
      await shot(tester, 'lesson-choice-$theme');
    });
  }
}
