import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/art/shapes.dart';
import 'package:ghost_md/art/wisp_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/guide.dart';
import 'package:ghost_md/guide/pages/parts.dart';
import 'package:ghost_md/home/home_parts.dart' show CssLines;

import 'support.dart';

/// The walkthrough held to the page: each of its four pages, and the first with its "Not yet" line, against the
/// rectangles Chromium gave the web app's own `Guide` at 390 x 844 (test/guide/fixtures/*.json, `getBoundingClientRect`
/// to a hundredth), to half a pixel. A paragraph's box is held by its corner and its height: the page's is as wide as
/// its column, a `Text`'s as wide as its longest line.
void main() {
  setUpAll(loadAppFonts);

  Future<Map<String, List<Map<String, dynamic>>>> show(WidgetTester tester, String name, int index, {bool tooSoon = false, GuideModelsOf? models, Preferences prefs = const Preferences(theme: 'light')}) async {
    final want = fixture(name);
    final store = ValueNotifier<Preferences>(prefs);
    addTearDown(store.dispose);
    await pumpGuide(
      tester,
      Guide(index: index, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, tooSoon: tooSoon, preferences: store, models: models?.call(), random: PickedNudge(want['nudge']!.first['text'] as String)),
      prefs: prefs,
    );
    await wait(tester, 3200);
    return want;
  }

  Rect rect(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Finder word(String text) => find.widgetWithText(GuideWord, text);
  Finder pill(String text) => find.widgetWithText(AppPill, text);
  /// A block of text as the stylesheet's `line-height` sizes it.
  Finder lines(Finder inner) => find.ancestor(of: inner, matching: find.byType(CssLines)).first;
  Finder boxOf(Finder inner) => find.ancestor(of: inner, matching: find.byType(Container)).first;

  void frame(WidgetTester tester, Map<String, List<Map<String, dynamic>>> want, {required String skip, required String next}) {
    // The dots.
    final dots = find.descendant(of: find.bySemanticsLabel(RegExp(r'^Page \d of 4$')), matching: find.byType(AnimatedContainer));
    expect(dots, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      expectRect(rect(tester, dots.at(i)), want['dots']![i], 'dot $i');
    }
    expectRect(rect(tester, word(skip)), want['skip']!.single, skip);
    expectRect(rect(tester, word('Back')), want['nav']!.single, 'Back');
    expectRect(rect(tester, pill(next)), want['next']!.single, next);
    // The nudge waits in the same place, as wide as its own words.
    final nudge = want['nudge']!.single;
    final got = rect(tester, pill(nudge['text'] as String));
    expect((got.width - (nudge['w'] as num)).abs(), lessThanOrEqualTo(0.5), reason: 'the nudge is ${got.width} wide for ${nudge['w']}');
    expect((got.right - ((nudge['x'] as num) + (nudge['w'] as num))).abs(), lessThanOrEqualTo(0.5));
  }

  void choices(WidgetTester tester, Map<String, List<Map<String, dynamic>>> want) {
    final rows = find.byType(GuideChoice);
    expect(rows, findsNWidgets(want['choice']!.length));
    for (var i = 0; i < want['choice']!.length; i++) {
      final row = rows.at(i);
      expectRect(rect(tester, find.descendant(of: row, matching: find.byType(AnimatedContainer))), want['choice']![i], 'row $i');
      expectRect(rect(tester, find.descendant(of: row, matching: find.byType(GuideSwatch))), want['swatch']![i], 'swatch $i');
      final texts = find.descendant(of: row, matching: find.byType(Text));
      // The swatch's words, then the label and the hint.
      expectRect(rect(tester, lines(texts.at(1))), want['stepTitle']![i], 'label $i', width: false);
      expectRect(rect(tester, lines(texts.at(2))), want['note']![i], 'hint $i', width: false);
    }
  }

  testWidgets('the welcome page', (tester) async {
    final want = await show(tester, 'welcome', 0);
    frame(tester, want, skip: 'Skip', next: 'Next');
    expectRect(rect(tester, lines(find.byType(WispText))), want['title']!.single, 'the title', width: false);
    expectRect(rect(tester, lines(find.textContaining('Notes you type or say.'))), want['lead']!.single, 'the lead', width: false);
    for (final (i, label) in ['Say it or type it', 'Plain Markdown files', 'The same on every device'].indexed) {
      expectRect(rect(tester, boxOf(find.text(label))), want['promise']![i], label);
    }
    final icons = find.descendant(of: find.byType(Wrap), matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle));
    for (var i = 0; i < 3; i++) {
      expectRect(rect(tester, icons.at(i)), want['promiseIcon']![i], 'icon $i');
    }
    await away(tester);
  });

  testWidgets('the welcome page with its line for a reader who came too soon', (tester) async {
    final want = await show(tester, 'too-soon', 0, tooSoon: true);
    frame(tester, want, skip: 'Skip', next: 'Next');
    final wisps = find.byType(WispText);
    expectRect(rect(tester, lines(wisps.at(0))), want['tooSoon']!.single, 'the line', width: false);
    expectRect(rect(tester, lines(wisps.at(1))), want['title']!.single, 'the title', width: false);
    expectRect(rect(tester, boxOf(find.text('Say it or type it'))), want['promise']!.first, 'the first promise');
    await away(tester);
  });

  testWidgets('the theme page', (tester) async {
    // The page was measured with Light chosen: the second row is the one printed in reverse.
    final want = await show(tester, 'theme', 1);
    frame(tester, want, skip: 'Skip', next: 'Next');
    expectRect(rect(tester, lines(find.text('Light or dark?'))), want['title']!.single, 'the title', width: false);
    expectRect(rect(tester, lines(find.textContaining('Pick one to see it.'))), want['lead']!.single, 'the lead', width: false);
    choices(tester, want);
    await away(tester);
  });

  testWidgets('the model page', (tester) async {
    final want = await show(tester, 'model', 2);
    frame(tester, want, skip: 'Skip', next: 'Next');
    expectRect(rect(tester, lines(find.text('Choose your model'))), want['title']!.single, 'the title', width: false);
    expectRect(rect(tester, lines(find.textContaining('It rewrites your notes'))), want['lead']!.single, 'the lead', width: false);
    choices(tester, want);
    await away(tester);
  });

  testWidgets('the model page’s line about the download, scrolled to its end', (tester) async {
    final want = await show(tester, 'model-fine', 2, models: () => FakeGuideModels());
    final scroller = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroller.position.jumpTo(scroller.position.maxScrollExtent);
    await wait(tester, 600);
    choices(tester, want);
    final get = word('get it now');
    expectRect(rect(tester, get), want['action']!.single, 'get it now');
    expectRect(rect(tester, find.ancestor(of: get, matching: find.byType(DecoratedBox)).first), want['fine']!.single, 'the line');
    await away(tester);
  });

  testWidgets('the last page', (tester) async {
    final want = await show(tester, 'start', 3);
    frame(tester, want, skip: 'Close', next: 'Start');
    expectRect(rect(tester, find.byType(TipsShape)), want['art']!.single, 'the picture');
    expectRect(rect(tester, lines(find.text('Learn it, or just start.'))), want['title']!.single, 'the title', width: false);
    expectRect(rect(tester, lines(find.textContaining('The marks, the words you can say'))), want['lead']!.single, 'the lead', width: false);
    expectRect(rect(tester, pill('Take the Ghost.md Academy')), want['learn']!.single, 'the Academy');
    await away(tester);
  });
}

typedef GuideModelsOf = FakeGuideModels Function();
