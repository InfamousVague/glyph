import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// `academy/AcademyScreen.test.tsx`, case for case. The Academy as a person takes it: its contents, a lesson, their
/// own line typed under it, the tick the moment the mark is in, and Next (with the page staying put until they
/// press it), then the end of the chapter, and the next.
void main() {
  setUpAll(loadAppFonts);

  final first = lessons[0], second = lessons[1];

  /// From the contents, Start or Continue: into the first lesson not learned.
  Future<void> carryOn(WidgetTester tester) => press(tester, key('academy-go'));

  /// How many bars run along the top (the page's `ol[aria-hidden] > li`).
  int bars(WidgetTester tester) => find.descendant(of: key('academy-bars'), matching: find.byType(AnimatedContainer)).evaluate().length;

  /// Whether a chapter's row can be pressed.
  bool disabled(WidgetTester tester, String chapter) => tester.widget<GlacierPressable>(key('chapter:$chapter')).onPressed == null;

  group('the Academy', () {
    testWidgets('opens on its chapters, and carries on at the first lesson not passed yet', (tester) async {
      freshDevice(learned: {first.id});
      await showAcademy(tester);
      expect(title(tester), 'Carry on learning');
      expect(find.descendant(of: key('academy-chapters'), matching: find.byType(GlacierPressable)), findsNWidgets(7));
      expect(find.text('Continue: ${second.title}'), findsOneWidget);
      await carryOn(tester);
      expect(title(tester), second.title);
      // Where it is in its chapter, and how much of the whole has been learned.
      expect(find.text('Chapter 1 · Markdown basics · 2 of ${lessonsIn('Markdown basics').length}'.toUpperCase()), findsOneWidget);
      expect(find.bySemanticsLabel('1 of ${lessons.length} learned'), findsOneWidget);
      await away(tester);
    });

    testWidgets('starts a chapter from the contents, at its first lesson not learned', (tester) async {
      final boards = lessonsIn('Boards and to-dos');
      freshDevice(learned: {boards[0].id});
      await showAcademy(tester);
      await press(tester, find.bySemanticsLabel('Chapter 5, Boards and to-dos'));
      expect(title(tester), boards[1].title);
      expect(bars(tester), boards.length);
      // Back is the contents, not out of the Academy.
      await press(tester, find.bySemanticsLabel('The Academy’s chapters'));
      expect(title(tester), 'Carry on learning');
      await away(tester);
    });

    testWidgets('ends a chapter on a page of its own, then goes on to the next', (tester) async {
      final basics = lessonsIn('Markdown basics');
      final more = lessonsIn('More Markdown');
      freshDevice(learned: {for (final lesson in basics.take(basics.length - 1)) lesson.id});
      await showAcademy(tester);
      await carryOn(tester);
      expect(title(tester), basics.last.title);
      expect(bars(tester), basics.length);
      await press(tester, find.text('Skip'));
      expect(title(tester), 'The end of the chapter.');
      // The skipped lesson can be taken from here.
      expect(find.descendant(of: key('again:${basics.last.id}'), matching: find.text(basics.last.title)), findsOneWidget);
      await press(tester, find.text('Next: More Markdown'));
      expect(title(tester), more[0].title);
      expect(find.text('Chapter 2 · More Markdown · 1 of ${more.length}'.toUpperCase()), findsOneWidget);
      expect(bars(tester), more.length);
      await away(tester);
    });

    testWidgets('says a chapter is learned when every lesson in it is', (tester) async {
      final places = lessonsIn('Links and places');
      freshDevice(learned: {for (final lesson in places.take(places.length - 1)) lesson.id});
      await showAcademy(tester);
      await press(tester, find.bySemanticsLabel('Chapter 4, Links and places'));
      await press(tester, find.text('Show me'));
      await press(tester, find.text('Next'));
      expect(title(tester), 'Chapter learned.');
      await away(tester);
    });

    testWidgets('leaves standard Markdown out for a person who knows it, and remembers that', (tester) async {
      freshDevice();
      await showAcademy(tester);
      final all = lessons.length;
      await press(tester, key('academy-skip-switch'));
      expect(readSkipStandard(), isTrue);
      final kept = lessons.where((lesson) => !lesson.standard).length;
      expect(find.bySemanticsLabel('0 of $kept learned'), findsOneWidget);
      expect(kept, lessThan(all));
      expect(disabled(tester, 'Markdown basics'), isTrue);
      expect(find.text('Skipped'), findsOneWidget);
      // Start is the first lesson Ghost.md has of its own, past every standard one.
      await carryOn(tester);
      expect(title(tester), lessons.firstWhere((lesson) => !lesson.standard).title);
      await away(tester);
    });

    testWidgets('teaches an effect with the note’s own drawing of it underneath', (tester) async {
      final heat = lessons.firstWhere((lesson) => lesson.id == 'heat');
      freshDevice(learned: {for (final lesson in lessons.take(lessons.indexOf(heat))) lesson.id});
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

    testWidgets('offers no lesson for a mark that is switched off, and counts without it', (tester) async {
      final registry = freshDevice(learned: {for (final lesson in lessons.where((lesson) => lesson.needs == null)) lesson.id});
      registry.setEnabled('marks', false);
      await showAcademy(tester);
      // Every lesson on offer is learned: the plugin's are not waiting to be taken.
      expect(title(tester), 'That is every mark.');
      final offered = lessons.where((lesson) => lesson.needs == null).length;
      expect(find.bySemanticsLabel('$offered of $offered learned'), findsOneWidget);
      expect(disabled(tester, 'Marks and effects'), isTrue);
      expect(find.text('A spoiler'), findsNothing);
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

    testWidgets('is the summary once everything is learned, with the cheat sheet and every chapter to take again', (tester) async {
      freshDevice(learned: {for (final lesson in lessons) lesson.id});
      final shown = await showAcademy(tester);
      expect(title(tester), 'That is every mark.');
      await press(tester, find.text('Cheat sheet'));
      expect(shown.cheatSheet, 1);
      await press(tester, find.bySemanticsLabel('Chapter 1, Markdown basics'));
      expect(title(tester), first.title);
      await away(tester);
    });

    testWidgets('forgets every lesson on Start again, and opens the first', (tester) async {
      freshDevice(learned: {for (final lesson in lessons) lesson.id});
      await showAcademy(tester);
      await press(tester, find.text('Start again'));
      expect(readProgress(), isEmpty);
      expect(title(tester), first.title);
      await away(tester);
    });

    testWidgets('closes on its arrow and on the back gesture from the contents', (tester) async {
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
    testWidgets('steps back to the contents on the back gesture from a lesson, and only then out', (tester) async {
      freshDevice();
      final shown = await showAcademy(tester);
      await carryOn(tester);
      final stack = BackScope.of(tester.element(find.byType(AcademyScreen)));
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
      expect(find.bySemanticsLabel('0 of ${lessons.length} learned'), findsOneWidget);
      registry.setEnabled('marks', false);
      await settle(tester, 2);
      expect(find.bySemanticsLabel('0 of ${lessons.where((lesson) => lesson.needs == null).length} learned'), findsOneWidget);
      expect(disabled(tester, 'Marks and effects'), isTrue);
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
      freshDevice(learned: {for (final lesson in lessons.take(lessons.indexOf(choice))) lesson.id});
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
}
