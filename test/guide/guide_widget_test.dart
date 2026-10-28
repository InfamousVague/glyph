import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/art/wisp_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/bottom_nudge.dart';
import 'package:ghost_md/guide/guide.dart';
import 'package:ghost_md/guide/pages.dart';
import 'package:ghost_md/guide/pages/parts.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// `guide/Guide.test.tsx`, case for case. jsdom lays nothing out, so the page's test said a page was long by faking
/// its heights; here a page is long because the window is short (the welcome page on a screen 420 tall), and it is
/// scrolled by its own scroller.
void main() {
  setUpAll(loadAppFonts);

  const short = Size(390, 420);
  int at(GuidePage page) => page.index;

  /// The guide at a page the test can turn, with what it called counted.
  Future<({List<int> turned, List<String> calls, Future<void> Function(int) again})> guide(WidgetTester tester, int index, {bool tooSoon = false, Size size = const Size(390, 844)}) async {
    final shown = ValueNotifier<int>(index);
    addTearDown(shown.dispose);
    final store = ValueNotifier<Preferences>(const Preferences(theme: 'light'));
    addTearDown(store.dispose);
    final turned = <int>[];
    final calls = <String>[];
    await pumpGuide(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: shown,
        builder: (context, now, _) => Guide(index: now, onIndex: turned.add, onClose: () => calls.add('close'), onAcademy: () => calls.add('academy'), tooSoon: tooSoon, preferences: store),
      ),
      size: size,
    );
    await tester.pump();
    return (
      turned: turned,
      calls: calls,
      again: (int next) async {
        shown.value = next;
        await tester.pump();
        await tester.pump();
      },
    );
  }

  Finder pill(String text) => find.widgetWithText(AppPill, text);
  Finder word(String text) => find.widgetWithText(GuideWord, text);
  Finder nudge() => find.byWidgetPredicate((w) => w is AppPill && w.icon != null && w.child is Text && nudges.contains((w.child as Text).data));

  /// `data-shown`: there and pressable, or faded out and out of reach.
  bool shown(WidgetTester tester, Finder button) {
    final opacity = tester.widget<AnimatedOpacity>(find.ancestor(of: button, matching: find.byType(AnimatedOpacity)).first).opacity;
    final ignoring = tester.widget<IgnorePointer>(find.ancestor(of: button, matching: find.byType(IgnorePointer)).first).ignoring;
    expect(opacity == 1, !ignoring, reason: 'what is seen can be pressed, and nothing else');
    return opacity == 1;
  }

  Future<void> toTheEnd(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
  }

  /// Every word on the screen, the smoke's among them.
  String words(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.byType(Text))) text.data ?? text.textSpan?.toPlainText() ?? '',
    for (final text in tester.widgetList<WispText>(find.byType(WispText))) text.text,
  ].join('\n');

  group('the walkthrough', () {
    testWidgets('keeps Next at the bottom of a long page, and after a moment nudges the reader down to it', (tester) async {
      await guide(tester, at(GuidePage.welcome), size: short);
      expect(shown(tester, pill('Next')), isFalse);
      // Said to no one while it waits.
      expect(tester.widget<ExcludeSemantics>(find.ancestor(of: pill('Next'), matching: find.byType(ExcludeSemantics)).first).excluding, isTrue);
      expect(shown(tester, nudge()), isFalse);
      await tester.pump(nudgeAfter - const Duration(milliseconds: 1));
      expect(shown(tester, nudge()), isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shown(tester, nudge()), isTrue);
      // Read to the end: Next is there, and the nudge has done its job.
      await toTheEnd(tester);
      expect(shown(tester, pill('Next')), isTrue);
      expect(tester.widget<ExcludeFocus>(find.ancestor(of: pill('Next'), matching: find.byType(ExcludeFocus)).first).excluding, isFalse);
      expect(shown(tester, nudge()), isFalse);
      await away(tester);
    });

    testWidgets('shows Next at once on a page that fits the screen', (tester) async {
      await guide(tester, at(GuidePage.market));
      expect(shown(tester, pill('Next')), isTrue);
      await tester.pump(nudgeAfter);
      expect(shown(tester, nudge()), isFalse);
      await away(tester);
    });

    testWidgets('takes the reader down when the nudge is pressed', (tester) async {
      // Not a case of the page's: there the press was `scrollTo`, which jsdom does not do.
      await guide(tester, at(GuidePage.welcome), size: short);
      await tester.pump(nudgeAfter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(nudge());
      await wait(tester, 1200);
      expect(shown(tester, pill('Next')), isTrue);
      await away(tester);
    });

    testWidgets('steps with Next and Back, and the back gesture steps back until the first page, where it closes the guide', (tester) async {
      final it = await guide(tester, at(GuidePage.market));
      await tester.tap(pill('Next'));
      expect(it.turned.last, at(GuidePage.market) + 1);
      await tester.tap(word('Back'));
      expect(it.turned.last, at(GuidePage.market) - 1);
      it.turned.clear();
      testBack.goBack();
      expect(it.turned, [at(GuidePage.market) - 1]);
      expect(it.calls, isEmpty);
      await it.again(0);
      expect(tester.widget<GuideWord>(word('Back')).onPressed, isNull);
      expect(tester.widget<Visibility>(find.ancestor(of: word('Back'), matching: find.byType(Visibility))).visible, isFalse);
      testBack.goBack();
      expect(it.calls, ['close']);
      await away(tester);
    });

    testWidgets('says where the reader is, and offers Skip until the last page, which offers Close, the Academy and Start', (tester) async {
      final it = await guide(tester, at(GuidePage.market));
      expect(find.bySemanticsLabel('Page ${at(GuidePage.market) + 1} of ${walkthroughPages.length}'), findsOneWidget);
      await tester.tap(word('Skip'));
      expect(it.calls, ['close']);
      await it.again(walkthroughPages.length - 1);
      await wait(tester, 400);
      expect(words(tester), contains('You’re ready.'));
      await tester.tap(pill('Take the Ghost Academy'));
      expect(it.calls, ['close', 'academy']);
      // The last page asks light or dark under its words, so Start waits for the bottom like any Next.
      await toTheEnd(tester);
      await tester.tap(pill('Start'));
      expect(it.calls, ['close', 'academy', 'close']);
      expect(word('Close'), findsOneWidget);
      await away(tester);
    });

    testWidgets('opens with one line for a reader who held the side key too soon', (tester) async {
      await guide(tester, 0, tooSoon: true);
      expect(words(tester), contains('Not yet, finish reading.'));
      final line = find.byWidgetPredicate((w) => w is WispText && w.text == 'Not yet, finish reading.');
      // Said as it arrives (`role="status"`).
      expect(tester.widget<Semantics>(find.ancestor(of: line, matching: find.byType(Semantics)).first).properties.liveRegion, isTrue);
      await away(tester);
      await guide(tester, 0);
      expect(words(tester), isNot(contains('Not yet, finish reading.')));
      await away(tester);
    });

    testWidgets('teaches no page of marks and no habits: those are the Academy’s', (tester) async {
      // The side key may be named now: the page on speaking a note says it is one way to start (Matt, 2026-10-27,
      // the brief for the tour: "speaking a note (the recorder / side key / mic)").
      final it = await guide(tester, 0);
      for (final page in walkthroughPages) {
        await it.again(at(page));
        expect(words(tester), isNot(matches(RegExp('Every mark, side by side|A few habits'))), reason: page.name);
      }
      await away(tester);
    });

    testWidgets('stands still for a reader who asked for less motion', (tester) async {
      // Not a case of the page's test: `prefers-reduced-motion` in the stylesheet, held here.
      final store = ValueNotifier<Preferences>(const Preferences(theme: 'light'));
      addTearDown(store.dispose);
      await pumpGuide(tester, Guide(index: 0, onIndex: (_) {}, onClose: () {}, onAcademy: () {}, preferences: store), still: true);
      await tester.pump();
      expect(GlacierTheme.of(tester.element(find.byType(Guide))).reducedMotion, isTrue);
      // Nothing is on its way in: the promises are whole at once.
      expect(find.ancestor(of: find.text('Say it or type it'), matching: find.byType(Opacity)), findsNothing);
      expect(find.ancestor(of: find.text('Say it or type it'), matching: find.byType(Transform)), findsNothing);
      await away(tester);
    });
  });

  group('swiping through the walkthrough', () {
    /// A quick sideways drag across the guide, `dx` pixels: left is forward, right is back.
    Future<void> swipe(WidgetTester tester, double dx) async {
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(Offset(dx, 0));
      await gesture.up();
      await tester.pump();
    }

    testWidgets('goes forward on a swipe left only once the page is read to the bottom, as Next does', (tester) async {
      final it = await guide(tester, at(GuidePage.welcome), size: short);
      await swipe(tester, -120);
      expect(it.turned, isEmpty);
      await toTheEnd(tester);
      await swipe(tester, -120);
      expect(it.turned, [at(GuidePage.welcome) + 1]);
      await away(tester);
    });

    testWidgets('goes back on a swipe right, and never forward from the last page', (tester) async {
      final it = await guide(tester, walkthroughPages.length - 1);
      await swipe(tester, -120);
      expect(it.turned, isEmpty);
      expect(it.calls, isEmpty);
      await swipe(tester, 120);
      expect(it.turned, [walkthroughPages.length - 2]);
      await away(tester);
    });
  });
}
