import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/own_templates.dart';
import 'package:ghost_md/notes/template_cards.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/editor_text.dart';
import '../support/render.dart';
import 'support.dart';

/// The templates on a new note's blank page (lib/notes/template_cards.dart), after the web's
/// `notes/TemplateCards.test.tsx`: a card for each, named by it and described by its sentence; A map at the top dimmed
/// with its reason where no note made here keeps a place, and not there at all where the device can never say where
/// it is; A day saying so when today's name is taken.
///
/// Not measured on the page (the cards stand on the editor's blank page, which the dev server would not show
/// without the editor's own doing): the sizes asserted are TemplateCards.module.css's, through the tokens.
void main() {
  setUpAll(loadAppFonts);

  final at = DateTime(2026, 9, 28, 14, 5);

  Future<List<String>> show(
    WidgetTester tester, {
    Set<String> taken = const {},
    List<NoteTemplate>? templates,
    bool yours = false,
    bool canLocate = true,
    bool localOnly = false,
    String? refused,
    Size size = const Size(390, 844),
    String theme = 'dark',
    List<HapticKind>? felt,
  }) async {
    final chosen = <String>[];
    await pumpApp(
      tester,
      size: size,
      prefs: AppPreferences(theme: theme),
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: HapticsProvider(
            enabled: true,
            impl: ([kind = HapticKind.light]) => felt?.add(kind),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: context.tokens.len('app-gutter-start')),
              child: TemplateCards(
                at: at,
                taken: taken,
                templates: templates,
                canLocate: canLocate,
                localOnly: localOnly,
                refused: refused,
                onChoose: (template) => chosen.add(template.id),
                onYours: yours ? () => chosen.add('yours') : null,
              ),
            ),
          ),
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await settle(tester);
    return chosen;
  }

  Finder card(String id) => find.byKey(ValueKey('template-$id'));
  List<String> cards(WidgetTester tester) => [
        for (final element in find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('template-')).evaluate())
          ((element.widget.key! as ValueKey<String>).value.substring('template-'.length)),
      ];
  /// Whether the card's picture draws [words]: one of the editor's lines in it shows them.
  bool draws(String id, String words) => find.descendant(of: card(id), matching: editorText(words)).evaluate().isNotEmpty;
  bool says(String id, String words) => find.descendant(of: card(id), matching: find.text(words)).evaluate().isNotEmpty;

  testWidgets('are eight, each named by its template and described by its sentence, and a press chooses it', (tester) async {
    final chosen = await show(tester);
    expect(cards(tester), ['day', 'meeting', 'checklist', 'book', 'map', 'reading', 'bug', 'feature']);
    expect(says('meeting', 'A meeting'), isTrue);
    expect(says('meeting', 'Named for this minute, with who was there, notes and to-dos.'), isTrue);
    await tester.scrollUntilVisible(card('reading'), 200);
    await tester.tap(card('reading'));
    expect(chosen, ['reading']);
    await away(tester);
  });

  testWidgets('draw the note’s top as it will be written: the day’s own name, the minute of a meeting', (tester) async {
    await show(tester);
    expect(draws('day', '2026-09-28'), isTrue);
    expect(draws('day', 'Monday 28 September'), isTrue);
    expect(draws('meeting', 'Meeting 2026-09-28 14.05'), isTrue);
    await away(tester);
  });

  testWidgets('say when today’s name is taken, and draw the heading A day will write', (tester) async {
    await show(tester, taken: {titleKey('2026-09-28')});
    expect(says('day', 'Today has a note by this name. This makes a second.'), isTrue);
    expect(draws('day', '2026-09-28 (2)'), isTrue);
    await away(tester);
    // Only A day says so: a second meeting in the same minute is still named for it, and says what it is.
    await show(tester, taken: {titleKey('Meeting 2026-09-28 14.05')});
    expect(says('meeting', 'Named for this minute, with who was there, notes and to-dos.'), isTrue);
    expect(says('day', 'Named for today, with a to-do to start.'), isTrue);
    expect(draws('meeting', '14.05 (2)'), isTrue);
    await away(tester);
  });

  testWidgets('dim A map at the top under Local only, as no button, and buzz at a press that makes nothing', (tester) async {
    final felt = <HapticKind>[];
    final chosen = await show(tester, localOnly: true, felt: felt);
    await tester.scrollUntilVisible(card('map'), 200);
    expect(says('map', 'Local only is on, so a note made here keeps no place.'), isTrue);
    expect(find.descendant(of: card('map'), matching: find.byType(GlacierPressable)), findsNothing);
    expect(find.descendant(of: card('map'), matching: find.byType(Opacity)), findsNWidgets(2));
    await tester.tap(card('map'));
    expect(chosen, isEmpty);
    expect(felt, [HapticKind.warning]);
    await away(tester);
  });

  testWidgets('dim it with where to allow location after a refusal that still stands', (tester) async {
    await show(tester, refused: 'Allow location for this site in the browser’s settings');
    expect(says('map', 'Allow location for this site in the browser’s settings for a note to keep its place.'), isTrue);
    await away(tester);
  });

  testWidgets('are your own templates once you have them, in their order, and end with the way to them', (tester) async {
    final walk = templateOf(makeNote('walk', body: newTemplatePageBody('A walk')));
    final day = templateOf(makeNote('d', body: templatePageBody(builtIns[0])));
    final chosen = await show(tester, taken: {titleKey('2026-09-28')}, templates: [walk, day], yours: true);
    expect(cards(tester), ['walk', 'd', 'yours']);
    expect(says('walk', 'One of your own.'), isTrue);
    // Still A day word for word: its rules, a taken name included.
    expect(says('d', 'Today has a note by this name. This makes a second.'), isTrue);
    expect(says('yours', 'Your templates'), isTrue);
    expect(says('yours', 'Change these or write your own. They are notes in a notebook.'), isTrue);
    await tester.tap(card('walk'));
    await tester.tap(card('yours'));
    expect(chosen, ['walk', 'yours']);
    await away(tester);
  });

  testWidgets('leave the map out where the device can never say where it is', (tester) async {
    await show(tester, canLocate: false);
    expect(cards(tester), ['day', 'meeting', 'checklist', 'book', 'reading', 'bug', 'feature']);
    await away(tester);
  });

  testWidgets('are one to a row on a phone, each picture 7rem tall, a space apart', (tester) async {
    await show(tester);
    final t = GlacierTheme.of(tester.element(card('day')));
    final day = tester.getRect(card('day')), meeting = tester.getRect(card('meeting'));
    // `padding-block-start: space-5` over the first.
    expect(day.top, closeTo(t.space(5), 0.01));
    expect(day.width, closeTo(390 - 2 * t.len('app-gutter-start'), 0.01));
    expect(meeting.top - day.bottom, closeTo(t.space(3), 0.01));
    expect(meeting.left, day.left);
    // A card: its padding, the picture (`--picture: 7rem`) and the space under it, then the name and the sentence,
    // a `space-1` between each.
    final name = tester.getRect(find.descendant(of: card('day'), matching: find.text('A day')));
    expect(name.top - day.top, closeTo(t.len('glacier-hairline') + t.space(3) + t.lenOf('7rem') + t.space(2) + t.space(1), 0.5));
    await away(tester);
  });

  testWidgets('are as many as fit 15rem from 600px, in a column of at most 56rem, with Your templates across the row under them', (tester) async {
    await show(tester, yours: true, size: const Size(1000, 800));
    final t = GlacierTheme.of(tester.element(card('day')));
    final first = tester.getRect(card('day')), second = tester.getRect(card('meeting')), third = tester.getRect(card('checklist')), fourth = tester.getRect(card('book'));
    // 56rem holds three of 15rem and their gaps: 896 = 3 x 288.6 + 2 x 15.
    expect(first.top, second.top);
    expect(second.top, third.top);
    expect(fourth.left, first.left);
    expect(fourth.top, greaterThan(first.bottom));
    expect(third.right - first.left, closeTo(t.lenOf('56rem'), 0.5));
    expect(second.left - first.right, closeTo(t.space(3), 0.01));
    // One height to a row, so its names sit on one line.
    expect(first.height, second.height);
    final yours = tester.getRect(card('yours'));
    expect([yours.left, yours.width], [first.left, closeTo(t.lenOf('56rem'), 0.5)]);
    await shot(tester, 'template-cards-wide-dark');
  });

  for (final theme in ['dark', 'light']) {
    testWidgets('on a phone, $theme', (tester) async {
      await show(tester, yours: true, theme: theme, localOnly: theme == 'light');
      await shot(tester, 'template-cards-phone-$theme');
    });
  }
}
