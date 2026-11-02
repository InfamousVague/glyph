import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/academy/courses.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:ghost_md/plugins/gantt/gantt.dart' show ganttPlugin;
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/projects/suite.dart' show ProjectSuite;
import 'package:ghost_md/plugins/registry.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// `academy/AcademyScreen.test.tsx`, case for case where the page had them, and the catalog of courses that took the
/// place of its contents (Matt, 2026-11-02: "redo the academy homepage to be easier to browse like codecademy
/// lessons"). The Academy as a person takes it: its catalog, a course, a lesson, their own line typed under it, the
/// tick the moment the mark is in, and Next (with the page staying put until they press it), then the end of the
/// course, and the next; and a course whose plugin is off, found on its shelf and turned on there.
void main() {
  setUpAll(loadAppFonts);

  final first = lessons[0], second = lessons[1];

  /// Every lesson on offer with every plugin on, as the catalog counts them.
  List<Lesson> offered() => courseLessonsNow();

  /// From the catalog, Start or Resume: into the first lesson not learned.
  Future<void> carryOn(WidgetTester tester) => press(tester, key('academy-go'));

  /// Opens [course]'s page from its card, and starts it.
  Future<void> startCourse(WidgetTester tester, String course) async {
    await press(tester, key('course:$course'));
    await press(tester, key('academy-course-start'));
  }

  /// How many bars run along the top (the page's `ol[aria-hidden] > li`).
  int bars(WidgetTester tester) => find.descendant(of: key('academy-bars'), matching: find.byType(AnimatedContainer)).evaluate().length;

  /// Whether a course's card can be pressed.
  bool disabled(WidgetTester tester, String course) => tester.widget<GlacierPressable>(key('course:$course')).onPressed == null;

  group('the Academy', () {
    testWidgets('opens on its catalog, and carries on at the first lesson not passed yet', (tester) async {
      freshDevice(learned: {first.id});
      await showAcademy(tester, size: const Size(390, 6000));
      expect(title(tester), 'Carry on learning');
      // Every course on a card, the ones whose plugin is off among them.
      for (final course in courses) {
        expect(key('course:${course.id}'), findsOneWidget, reason: course.id);
      }
      expect(tester.widget<Text>(key('academy-continue-course')).data, 'Markdown basics');
      expect(find.text('Next: ${second.title}'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      await carryOn(tester);
      expect(title(tester), second.title);
      // Where it is in its course, and how much of the whole has been learned.
      expect(find.text('Markdown basics · 2 of ${courseById('basics')!.lessonIds.length}'.toUpperCase()), findsOneWidget);
      expect(find.bySemanticsLabel('1 of ${offered().length} learned'), findsOneWidget);
      await away(tester);
    });

    testWidgets('opens a course from its card, starts it at its first lesson not learned, and goes back a level at a time', (tester) async {
      final todos = courseById('todos')!.all;
      freshDevice(learned: {todos[0].id});
      await showAcademy(tester);
      await press(tester, key('course:todos'));
      expect(title(tester), 'To-dos that do more');
      // Its lessons, each with its tick.
      for (final lesson in todos) {
        expect(key('again:${lesson.id}'), findsOneWidget, reason: lesson.id);
      }
      expect(find.text('Resume'), findsOneWidget);
      await press(tester, key('academy-course-start'));
      expect(title(tester), todos[1].title);
      expect(bars(tester), todos.length);
      // Back is the course, then the catalog, not out of the Academy.
      await press(tester, find.bySemanticsLabel('The course’s lessons'));
      expect(title(tester), 'To-dos that do more');
      await press(tester, find.bySemanticsLabel('All courses'));
      expect(title(tester), 'Carry on learning');
      await away(tester);
    });

    testWidgets('takes any lesson of a course from its page', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await press(tester, key('course:queries'));
      await press(tester, key('again:queryShow'));
      expect(title(tester), 'Show it another way');
      await away(tester);
    });

    testWidgets('ends a course on a page of its own, then goes on to the next', (tester) async {
      final basics = courseById('basics')!.all;
      final more = courseById('more')!.all;
      freshDevice(learned: {for (final lesson in basics.take(basics.length - 1)) lesson.id});
      await showAcademy(tester);
      await carryOn(tester);
      expect(title(tester), basics.last.title);
      expect(bars(tester), basics.length);
      await press(tester, find.text('Skip'));
      expect(title(tester), 'The end of the course.');
      // The skipped lesson can be taken from here.
      expect(find.descendant(of: key('again:${basics.last.id}'), matching: find.text(basics.last.title)), findsOneWidget);
      await press(tester, find.text('Next: More Markdown'));
      expect(title(tester), more[0].title);
      expect(find.text('More Markdown · 1 of ${more.length}'.toUpperCase()), findsOneWidget);
      expect(bars(tester), more.length);
      await away(tester);
    });

    testWidgets('says a course is learned when every lesson in it is', (tester) async {
      final links = courseById('links')!.all;
      freshDevice(learned: {for (final lesson in links.take(links.length - 1)) lesson.id});
      await showAcademy(tester);
      await startCourse(tester, 'links');
      expect(title(tester), links.last.title);
      await press(tester, find.text('Show me'));
      await press(tester, find.text('Next'));
      expect(title(tester), 'Course learned.');
      await away(tester);
    });

    testWidgets('leaves standard Markdown out for a person who knows it, and remembers that', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await press(tester, key('academy-skip-switch'));
      expect(readSkipStandard(), isTrue);
      final kept = courseLessonsNow(true).length;
      expect(find.bySemanticsLabel('0 of $kept learned'), findsOneWidget);
      expect(kept, lessThan(offered().length));
      expect(disabled(tester, 'basics'), isTrue);
      expect(find.text('Skipped'), findsOneWidget);
      // Start is the first lesson Ghost has of its own, past every standard one.
      await carryOn(tester);
      expect(title(tester), lessons.firstWhere((lesson) => !lesson.standard).title);
      await away(tester);
    });

    testWidgets('teaches an effect with the note’s own drawing of it underneath', (tester) async {
      final heat = lessons.firstWhere((lesson) => lesson.id == 'heat');
      freshDevice(learned: {for (final lesson in offered().take(offered().indexOf(heat))) lesson.id});
      await showAcademy(tester);
      await carryOn(tester);
      expect(title(tester), 'Heat');
      await typeInto(tester, '🔥🔥too hot🔥🔥');
      expect(find.text(heat.praise), findsOneWidget);
      expect(readProgress(), contains('heat'));
      // The note's own editor is what draws it, over the words typed.
      expect(tester.widget<Editor>(find.byType(Editor)).view.state.doc.toString(), '🔥🔥too hot🔥🔥');
      await away(tester);
    });

    testWidgets('offers no lesson for a mark that is switched off, counts without it, and offers to turn it on', (tester) async {
      final registry = freshDevice();
      registry.setEnabled('marks', false);
      final without = offered();
      freshDevice(learned: {for (final lesson in without) lesson.id}).setEnabled('marks', false);
      await showAcademy(tester, size: const Size(390, 6000));
      // Every lesson on offer is learned: the plugin's are not waiting to be taken.
      expect(title(tester), 'That is every mark.');
      expect(find.bySemanticsLabel('${without.length} of ${without.length} learned'), findsOneWidget);
      expect(without.every((lesson) => lesson.needs == null), isTrue);
      // The plugin's courses are on their shelf all the same, each asking for it.
      expect(key('course:marks'), findsOneWidget);
      expect(find.text('Needs Marks'), findsNWidgets(2));
      expect(find.text('A spoiler'), findsNothing);
      await press(tester, find.descendant(of: key('course-turn-on:effects'), matching: find.text('Turn on Marks')));
      expect(find.text('Needs Marks'), findsNothing);
      expect(find.bySemanticsLabel('${without.length} of ${offered().length} learned'), findsOneWidget);
      await away(tester);
    });

    testWidgets('ticks a lesson the moment its mark is typed, once, and waits for Next', (tester) async {
      freshDevice();
      final shown = await showAcademy(tester);
      await carryOn(tester);
      expect(title(tester), first.title);
      expect(find.text('Skip'), findsOneWidget);
      shown.haptics.clear();
      await typeInto(tester, 'weekend');
      expect(readProgress(), isNot(contains(first.id)));
      await typeInto(tester, '# weekend');
      expect(find.text(first.praise), findsOneWidget);
      expect(readProgress(), contains(first.id));
      expect(shown.haptics, [HapticKind.success]);
      // Carrying on playing is not passing again.
      await typeInto(tester, '# weekend trip');
      expect(shown.haptics, [HapticKind.success]);
      // Still on the lesson: passing it never moves the page on by itself.
      expect(title(tester), first.title);
      await press(tester, find.text('Next'));
      expect(title(tester), second.title);
      await away(tester);
    });

    testWidgets('writes the example into the field on Show me, and passes it', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await carryOn(tester);
      await press(tester, find.text('Show me'));
      expect(field(tester), first.example);
      expect(find.text(first.praise), findsOneWidget);
      await away(tester);
    });

    testWidgets('starts each lesson on a clean page, with its hint put away', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await carryOn(tester);
      await press(tester, find.text('Show me a hint'));
      expect(find.text(first.hint), findsOneWidget);
      await typeInto(tester, 'not a title');
      await press(tester, find.text('Skip'));
      expect(title(tester), second.title);
      expect(field(tester), '');
      expect(find.text(first.hint), findsNothing);
      expect(find.text('Show me a hint'), findsOneWidget);
      // Skipped is not learned.
      expect(readProgress(), isNot(contains(first.id)));
      await away(tester);
    });

    testWidgets('is the summary once everything is learned, with the cheat sheet and every course to take again', (tester) async {
      freshDevice(learned: {for (final lesson in academyLessons) lesson.id});
      final shown = await showAcademy(tester);
      expect(title(tester), 'That is every mark.');
      expect(key('academy-continue'), findsNothing);
      await press(tester, find.text('Cheat sheet'));
      expect(shown.cheatSheet, 1);
      await press(tester, key('course:basics'));
      expect(find.text('Take it again'), findsOneWidget);
      await press(tester, key('academy-course-start'));
      expect(title(tester), first.title);
      await away(tester);
    });

    testWidgets('forgets every lesson on Start again, and opens the first', (tester) async {
      freshDevice(learned: {for (final lesson in academyLessons) lesson.id});
      await showAcademy(tester);
      await press(tester, find.text('Start again'));
      expect(readProgress(), isEmpty);
      expect(title(tester), first.title);
      await away(tester);
    });

    testWidgets('closes on its arrow and on the back gesture from the catalog', (tester) async {
      freshDevice();
      final shown = await showAcademy(tester);
      await press(tester, find.bySemanticsLabel('Close the Academy'));
      BackScope.of(tester.element(find.byType(AcademyScreen))).goBack();
      await tester.pump();
      expect(shown.done, 2);
      await away(tester);
    });
  });

  group('the Academy, further than the page’s tests go', () {
    testWidgets('steps back on the back gesture a level at a time: a lesson to its course, the course to the catalog, then out', (tester) async {
      freshDevice();
      final shown = await showAcademy(tester);
      await carryOn(tester);
      final stack = BackScope.of(tester.element(find.byType(AcademyScreen)));
      stack.goBack();
      await settle(tester);
      expect(title(tester), 'Markdown basics');
      stack.goBack();
      await settle(tester);
      expect(title(tester), 'Learn what a note can hold');
      expect(shown.done, 0);
      stack.goBack();
      expect(shown.done, 1);
      await away(tester);
    });

    testWidgets('takes a plugin’s lessons away the moment its marks are switched off', (tester) async {
      final registry = freshDevice();
      await showAcademy(tester);
      final all = offered().length;
      expect(find.bySemanticsLabel('0 of $all learned'), findsOneWidget);
      registry.setEnabled('marks', false);
      await settle(tester, 2);
      expect(find.bySemanticsLabel('0 of ${offered().length} learned'), findsOneWidget);
      expect(offered().length, lessThan(all));
      await tester.ensureVisible(key('course-turn-on:marks'));
      expect(key('course-turn-on:marks'), findsOneWidget);
      await away(tester);
    });

    testWidgets('keeps what is learned under the page’s own key', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await carryOn(tester);
      await press(tester, find.text('Show me'));
      expect(stored.readText('glyph-academy'), '["title"]');
      await away(tester);
    });

    testWidgets('squeezes a long praise beside Next, as the page’s foot does, and never runs off the card', (tester) async {
      final choice = lessons.firstWhere((lesson) => lesson.id == 'choice');
      freshDevice(learned: {for (final lesson in offered().take(offered().indexOf(choice))) lesson.id});
      await showAcademy(tester);
      await carryOn(tester);
      await press(tester, find.text('Show me'));
      expect(find.text(choice.praise), findsOneWidget);
      final foot = tester.getRect(key('academy-foot')), next = tester.getRect(key('academy-next')), praise = tester.getRect(key('academy-praise'));
      expect(next.right, closeTo(foot.right, 0.01));
      expect(praise.left, closeTo(foot.left, 0.01));
      expect(praise.right, lessThan(next.left));
      expect(tester.takeException(), isNull);
      await away(tester);
    });
  });

  group('the catalog', () {
    testWidgets('keeps a course whose plugin is off on its shelf, says so, and turns the plugin on from its page', (tester) async {
      ProjectSuite.debugAllOn = false;
      addTearDown(() => ProjectSuite.debugAllOn = true);
      useStored(MemoryStored());
      final registry = createRegistry(const [marksPlugin, ganttPlugin], store: MemorySwitches());
      usePlugins(registry);
      await showAcademy(tester);
      expect(courseOpen(courseById('gantt')!), isFalse);
      await tester.ensureVisible(key('course:gantt'));
      expect(find.descendant(of: key('course:gantt'), matching: find.text('Needs Gantt and timelines')), findsOneWidget);
      expect(key('course-turn-on:gantt'), findsOneWidget);
      // Its lessons are not on offer, nor counted, until it is on.
      expect(find.bySemanticsLabel('0 of ${offered().length} learned'), findsOneWidget);
      expect(offered().any((lesson) => lesson.id == 'gantt'), isFalse);
      await press(tester, key('course:gantt'));
      expect(title(tester), 'Gantt and timelines');
      expect(key('academy-needs'), findsOneWidget);
      expect(key('academy-course-start'), findsNothing);
      // Its lessons listed, and none of them to be pressed yet.
      expect(tester.widget<GlacierPressable>(key('again:gantt')).onPressed, isNull);
      await press(tester, find.descendant(of: key('academy-turn-on'), matching: find.text('Turn on Gantt')));
      expect(registry.isEnabled('gantt'), isTrue);
      expect(key('academy-needs'), findsNothing);
      await press(tester, key('academy-course-start'));
      expect(title(tester), 'A Gantt chart');
      await press(tester, find.text('Show me'));
      expect(find.text('That is a Gantt chart.'), findsOneWidget);
      expect(readProgress(), contains('gantt'));
      await away(tester);
    });

    testWidgets('narrows to a shelf by its chip, and back to all of them', (tester) async {
      freshDevice();
      await showAcademy(tester, size: const Size(390, 6000));
      expect(key('course:basics'), findsOneWidget);
      await press(tester, key('shelf:plugins'));
      expect(key('course:basics'), findsNothing);
      expect(key('course:lines'), findsNothing);
      expect(key('course:gantt'), findsOneWidget);
      expect(key('course:effects'), findsOneWidget);
      await press(tester, key('shelf:ghost'));
      expect(key('course:lines'), findsOneWidget);
      expect(key('course:gantt'), findsNothing);
      await press(tester, key('shelf:all'));
      expect(key('course:basics'), findsOneWidget);
      expect(key('course:gantt'), findsOneWidget);
      await away(tester);
    });

    testWidgets('lays its cards one across on a phone, two on the opened Fold and three on the Mac, a row as tall as its tallest', (tester) async {
      for (final (size, across) in [(const Size(390, 6000), 1), (const Size(884, 4000), 2), (const Size(1280, 4000), 3)]) {
        freshDevice();
        await showAcademy(tester, size: size);
        final ghost = [for (final id in ['lines', 'todos', 'links', 'queries']) tester.getRect(key('course:$id'))];
        final rows = ghost.map((rect) => rect.top.round()).toSet();
        expect(rows, hasLength((ghost.length / across).ceil()), reason: '$size');
        if (across > 1) expect(ghost[1].height, closeTo(ghost[0].height, 0.01), reason: '$size');
        expect(tester.takeException(), isNull);
        await away(tester);
      }
    });

    testWidgets('opens a course far down the catalog at its top, and goes back to the catalog where it was left', (tester) async {
      freshDevice();
      await showAcademy(tester);
      await tester.ensureVisible(key('course:effects'));
      await tester.pump();
      final down = tester.getRect(key('course:effects')).top;
      await press(tester, key('course:effects'));
      expect(title(tester), 'Effects');
      expect(tester.getRect(key('academy-title')).top, lessThan(844));
      expect(tester.getRect(key('academy-back')).top, greaterThan(0));
      await press(tester, find.bySemanticsLabel('All courses'));
      expect(tester.getRect(key('course:effects')).top, closeTo(down, 1));
      await away(tester);
    });

    testWidgets('has no chips in Simple, and the Markdown shelf up front', (tester) async {
      freshDevice();
      await showAcademy(tester, simple: true, size: const Size(390, 3000));
      expect(key('academy-shelves'), findsNothing);
      expect(key('course:basics'), findsOneWidget);
      expect(key('course:gantt'), findsNothing);
      await away(tester);
    });
  });
}
