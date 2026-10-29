import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart' show NoAiBackend, useAiBackend;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/format/body_hash.dart';
import 'package:ghost_md/format/gist.dart' show forgetGistRunner;
import 'package:ghost_md/format/results.dart' show Gist, keepGist;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_layout.dart';
import 'package:ghost_md/home/home_org_events.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/home/home_rows.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/notes/swipe_row.dart';
import 'package:ghost_md/shell/header_pane.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/shell/top_bar_tools.dart' show TopBarTools, TopBarToolsScope;
import 'package:glacier/glacier.dart';

import '../ai/fake_backend.dart';
import '../core/make_note.dart';
import '../support/render.dart';
import '../support/editor_text.dart';
import 'support.dart';

/// The home page (lib/home/home_screen.dart), over the library the store screenshots were taken over: what it
/// lists in each layout, its search and filters, its swipes and its pull, its dock, its empty pages, and where
/// things stand, held to what the web page measured (the dev server at 430x932 and 669x951, dark, the same notes at
/// the same moment; the numbers are that page's `getBoundingClientRect`s).
void main() {
  setUpAll(loadAppFonts);

  /// Takes the page down, and puts back the binding's switch for shadows that [pumpApp] turned on.
  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Finder words(String part) => find.textContaining(part, findRichText: true);

  /// The page's own scroller (the search field has one of its own inside it).
  final scroller = find.descendant(of: key('home-scroll'), matching: find.byType(Scrollable)).first;

  /// The filters' button, whatever it says is on: "Filters", "Filters: Pinned, Home".
  final filters = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.button == true && (widget.properties.label ?? '').startsWith('Filters'));

  /// Puts what [finder] finds a third of the way down the screen, clear of the header and the dock. The page builds
  /// only what is near the screen, so it is scrolled until the thing is there, and drawn where that left it before
  /// it is asked where it stands.
  Future<void> bring(WidgetTester tester, Finder finder) async {
    final position = tester.state<ScrollableState>(scroller).position;
    await tester.scrollUntilVisible(finder, 300, scrollable: scroller);
    await tester.pump();
    position.jumpTo((position.pixels + tester.getRect(finder).top - 300).clamp(0.0, position.maxScrollExtent));
    await tester.pump();
  }

  /// Everything the page lists from its top to its foot, in order: what [seen] finds as the page is scrolled down a
  /// screen at a time, each thing once. The page builds only what is near the screen, so what it lists is read by
  /// going down it, as a person does. The page is left at its top.
  Future<List<T>> down<T>(WidgetTester tester, List<T> Function() seen) async {
    final position = tester.state<ScrollableState>(scroller).position;
    position.jumpTo(0);
    await tester.pump();
    final found = <T>[];
    while (true) {
      for (final each in seen()) {
        if (!found.contains(each)) found.add(each);
      }
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo((position.pixels + position.viewportDimension * 0.5).clamp(0.0, position.maxScrollExtent));
      await tester.pump();
    }
    position.jumpTo(0);
    await tester.pump();
    return found;
  }

  /// The page at its foot, where the way to All notes is.
  Future<void> toFoot(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(scroller).position;
    // How far the page goes is known for certain only once its last rows are laid out: gone to twice.
    for (var i = 0; i < 3; i += 1) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
  }

  /// A choice of the filters' panel, by what it says: a radio, apart from a heading or the page's name that says the
  /// same words.
  Finder radio(String label) => find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label && widget.properties.checked != null);

  /// The page's headings, in order: "Pinned 1", "Recent", "Today 3".
  List<String> headings(WidgetTester tester) => [
        for (final heading in tester.widgetList<HomeHeading>(find.byType(HomeHeading))) heading.count == null ? heading.words : '${heading.words} ${heading.count}',
      ];

  // The web page's numbers here were measured before the header was condensed (Matt, 2026-10-17: "make the header of
  // the app more condensed by default"), and what that took off is worked out from the tokens it changed, at density
  // 1.1. The bar lost the step over its row, space-2 to space-1, and a little of its rings, space-10 * 0.74 to 0.68:
  // at 430 wide 4.50 + 2.70 = 7.20 (46.80 to 39.60), so the page, which pads by the bar to the whole pixel, pads by 40
  // where it padded by 47. The step from the bar to the search went from space-1 + space-2 + space-6 to space-1 +
  // space-3, 40.50 to 18.00: 22.50 less. Everything under the bar stands 7 + 22.50 higher.
  const barLess = 4.50 + 2.70;
  const lift = 7 + 22.50;
  // The opened Fold's (669 wide, in two panes, whose bar keeps a space-2 under its row): the bar 58.48 to 50.93, the
  // page padding by 58.48 (a fraction under a half is kept) and then by 51, 7.48; the step 42.44 to 18.86, 23.58 less.
  const foldLift = 7.48 + 23.58;

  /// Whether [rect] is where the web page had it, to [within] of a pixel each way.
  void at(Rect rect, double left, double top, double width, double height, {double within = 0.75, String? reason}) {
    expect(rect.left, closeTo(left, within), reason: '${reason ?? ''} left');
    expect(rect.top, closeTo(top, within), reason: '${reason ?? ''} top');
    expect(rect.width, closeTo(width, within), reason: '${reason ?? ''} width');
    expect(rect.height, closeTo(height, within), reason: '${reason ?? ''} height');
  }

  group('the notices above the notes', () {
    testWidgets('take no room, and no gap, while none has anything to say', (tester) async {
      // On the page a notice with nothing to say is not in the tree. Here the invitation's card is always handed
      // over and draws nothing until there is one: measured on the Fold, its gap put the first section 14px low.
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final bare = tester.getTopLeft(find.text('Pinned')).dy;
      await away(tester);
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, notices: const [SizedBox.shrink(), SizedBox.shrink()]));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Pinned')).dy, bare);
      await away(tester);
      // One that speaks takes its own height and one gap.
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, notices: const [SizedBox.shrink(), SizedBox(height: 30)]));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Pinned')).dy, greaterThan(bare + 30));
      await away(tester);
    });
  });

  group('what the page lists, in each layout', () {
    testWidgets('Spotlight: the pinned notes as lines, the four touched last as cards, then the rest by when', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      expect(await down(tester, () => headings(tester)), ['Pinned 1', 'Recent', 'Today 3', 'Yesterday 5', 'Earlier this week 7']);
      expect(await down(tester, () => [for (final line in tester.widgetList<HomeLine>(find.byType(HomeLine))) line.note.id]), ['weekend']);
      expect(await down(tester, () => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id]), ['prd11', 'standup', 'flat', 'open-tickets']);
      final rows = await down(tester, () => [for (final row in tester.widgetList<HomeRow>(find.byType(HomeRow))) row.note.id]);
      expect(rows.take(4), ['sprint', 'reading', 'groceries', 'house']);
      // Every note is on the page once: a line, a card or a row.
      expect(rows.length, 20 - 1 - 4);
      await toFoot(tester);
      expect(find.text('All notes · 20'), findsOneWidget);
      // The archive is never on the page.
      it.library.archive('flat', archived: true);
      await settle(tester);
      expect(await down(tester, () => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id]), isNot(contains('flat')));
      expect(key('card-flat'), findsNothing);
      await toFoot(tester);
      expect(find.text('All notes · 19'), findsOneWidget);
      await away(tester);
    });

    testWidgets('Cards: the notebooks, then the notes, each drawn small', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.cards));
      await settle(tester);
      expect(await down(tester, () => headings(tester)), ['Notebooks 2', 'Notes 18']);
      final cards = await down(tester, () => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id]);
      expect(cards.take(4), ['product', 'portugal', 'weekend', 'prd11']);
      expect(cards.length, 20);
      // A notebook's card: how many pages, and the first of them, numbered.
      expect(find.descendant(of: key('card-product'), matching: find.text('4 pages')), findsOneWidget);
      expect(find.descendant(of: key('card-product'), matching: find.text('Pricing page copy')), findsOneWidget);
      expect(find.byType(HomeRow), findsNothing);
      await away(tester);
    });

    testWidgets('Timeline: everything by when it was touched, a row each', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.timeline));
      await settle(tester);
      expect(await down(tester, () => headings(tester)), ['Today 8', 'Yesterday 5', 'Earlier this week 7']);
      final rows = await down(tester, () => [for (final row in tester.widgetList<HomeRow>(find.byType(HomeRow))) row.note.id]);
      expect(rows.take(8), ['prd11', 'standup', 'flat', 'open-tickets', 'sprint', 'reading', 'weekend', 'groceries']);
      expect(rows.length, 20);
      expect(find.byType(NoteCard), findsNothing);
      // A row says its notebook, its ticket's key and status, and how it starts.
      expect(words('Product ·'), findsWidgets);
      expect(find.descendant(of: key('row-prd11'), matching: find.text('PRD-11')), findsOneWidget);
      expect(find.descendant(of: key('row-prd11'), matching: find.text('In progress')), findsOneWidget);
      expect(find.descendant(of: key('row-standup'), matching: words('Summary')), findsOneWidget);
      await away(tester);
    });

    testWidgets('List: the notebooks then the notes, a row each, pinned first', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.list));
      await settle(tester);
      expect(await down(tester, () => headings(tester)), ['Notebooks 2', 'Notes 18']);
      final rows = await down(tester, () => [for (final row in tester.widgetList<HomeRow>(find.byType(HomeRow))) row.note.id]);
      expect(rows.take(4), ['product', 'portugal', 'weekend', 'prd11']);
      expect(rows.length, 20);
      expect(find.descendant(of: key('row-product'), matching: words('4 pages')), findsOneWidget);
      await away(tester);
    });

    testWidgets('says what a canvas, a journal and a recording are on their rows, and the meeting being recorded', (tester) async {
      final journal = exampleJournal(DateTime.fromMillisecondsSinceEpoch(seedNow));
      final library = SampleLibrary([
        ...seedLibrary(),
        makeNote('journal', body: journal.journal, createdAt: seedNow - 1000, updatedAt: seedNow - 1000),
        makeNote('entry', body: journal.entry, createdAt: seedNow - 2000, updatedAt: seedNow - 2000),
        makeNote('tape', body: '# Ideas on the walk\n\nThe app should open on the day.', source: NoteSource.capture, recordingMs: 40000, createdAt: seedNow - 3000, updatedAt: seedNow - 3000),
        makeNote('meeting', body: '# Meeting, 28 Sep 09:58', source: NoteSource.capture, createdAt: seedNow - 4000, updatedAt: seedNow - 4000),
      ], clock: () => seedNow);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.timeline, recording: 'meeting'));
      await settle(tester);
      expect(find.descendant(of: key('row-journal'), matching: words('1 entry')), findsOneWidget);
      expect(find.descendant(of: key('row-tape'), matching: words('0:40')), findsOneWidget);
      expect(find.descendant(of: key('row-meeting'), matching: words('Recording now')), findsOneWidget);
      await bring(tester, key('row-cabin-canvas'));
      expect(find.descendant(of: key('row-cabin-canvas'), matching: words('8 cards')), findsOneWidget);
      await away(tester);
    });

    testWidgets('stops Cards at the most it may draw, and sends the rest to All notes', (tester) async {
      final library = SampleLibrary([for (var i = 0; i < 50; i += 1) makeNote('n$i', body: '# Note $i', updatedAt: seedNow - i * 60000)], clock: () => seedNow);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.cards), ratio: 1);
      await settle(tester);
      final cards = await down(tester, () => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id]);
      expect(cards.length, cardsAtMost);
      // And of all of them only the ones near the screen are built.
      expect(tester.widgetList<NoteCard>(find.byType(NoteCard)).length, lessThan(cardsAtMost ~/ 2));
      await toFoot(tester);
      expect(find.text('2 more in All notes'), findsOneWidget);
      await away(tester);
    });
  });

  group('where things stand, as the web page measured them', () {
    testWidgets('on a phone (430x932): the search, the headings, a pinned line, the cards and the dock', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      // The header pane is the tab bar's height, and the page begins a short step under it.
      expect(tester.getSize(find.byType(HeaderPane)).height, closeTo(46.78 - barLess, 0.1));
      expect(tester.getRect(find.byType(EditableText)).left, closeTo(60.95, 0.75), reason: 'the field, past its mark');
      at(tester.getRect(find.bySemanticsLabel('Filters')), 362.53, 87.48 - lift, 44.98, 44.98, reason: 'filters button');
      at(tester.getRect(find.bySemanticsLabel('Search notebooks and notes').first), 22.48, 87.48 - lift, 331.06, 44.98, reason: 'search');
      at(tester.getRect(find.text('Pinned')), 46.23, 159.44 - lift, 44.94, 16, reason: 'Pinned');
      at(tester.getRect(key('line-weekend')), 22.48, 185.42 - lift, 385.03, 44.98, reason: 'the pinned line');
      at(tester.getRect(find.text('Weekend trip')), 56.47, 197.91 - lift, 101.73, 20, reason: 'its name');
      at(tester.getRect(find.descendant(of: key('line-weekend'), matching: find.text('1 hr ago'))), 359.23, 200.91 - lift, 43.78, 14, reason: 'its when');
      at(tester.getRect(find.text('Recent')), 46.23, 258.38 - lift, 45.27, 16, reason: 'Recent');
      at(tester.getRect(key('card-prd11')), 22.48, 283.36 - lift, 385.03, 249.44, reason: 'the first card');
      at(tester.getRect(key('card-standup')), 22.48, 546.28 - lift, 385.03, 207.05, reason: 'the second card');
      at(tester.getRect(key('card-flat')), 22.48, 766.81 - lift, 385.03, 168.69, reason: 'the third card');
      // Inside a card: its title, its notebook, its ticket's key and status, and when.
      expect(tester.getRect(find.text('Fix the sign-in loop')).top, closeTo(302.34 - lift, 0.75));
      at(tester.getRect(find.descendant(of: key('card-prd11'), matching: find.text('Product'))), 56.81, 331.53 - lift, 41.25, 14, reason: 'the notebook');
      at(tester.getRect(find.descendant(of: key('card-prd11'), matching: find.text('PRD-11'))), 41.47, 354.52 - lift, 41.48, 14, reason: 'the key');
      expect(tester.getRect(find.descendant(of: key('card-prd11'), matching: find.text('In progress'))).left, closeTo(102.57, 0.75));
      expect(tester.getRect(find.text('20 min ago')).top, closeTo(499.81 - lift, 0.75));
      // The words of the preview: a paragraph's two lines, then the to-dos hung on their boxes.
      at(tester.getRect(editorText('Signing').first), 41.47, 386.48 - lift, 347.06, 34.78, reason: 'the preview: two lines, 17.4 each');
      expect(editorTextRect(tester, 'Find').left, closeTo(80.63, 0.75), reason: 'a to-do hangs past "- [x] "');
      at(tester.getRect(key('dock-search')), 362.44, 815.86, 39.59, 39.59, reason: 'Search');
      at(tester.getRect(key('dock-add')), 362.44, 864.44, 39.59, 39.59, reason: '+');
      await away(tester);
    });

    testWidgets('on a phone, a timeline: the rows', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.timeline, speak: true));
      await settle(tester);
      at(tester.getRect(find.text('Today')), 22.48, 159.44 - lift, 39.78, 16, reason: 'Today');
      at(tester.getRect(key('row-prd11')), 22.48, 185.42 - lift, 385.03, 64.97, reason: 'a row');
      at(tester.getRect(key('row-standup')), 22.48, 251.39 - lift, 385.03, 64.97, reason: 'the next row, a hairline down');
      expect(tester.getRect(find.descendant(of: key('row-prd11'), matching: find.text('Fix the sign-in loop'))).topLeft, within(distance: 0.75, from: const Offset(56.47, 198.91 - lift)));
      at(tester.getRect(find.descendant(of: key('row-prd11'), matching: find.text('20 min ago'))), 343.73, 203.73 - lift, 59.28, 14, reason: 'when');
      at(tester.getRect(find.descendant(of: key('row-prd11'), matching: find.text('PRD-11'))), 120.5, 222.91 - lift, 41.48, 14, reason: 'the ticket in the lead');
      expect(tester.getRect(find.descendant(of: key('row-standup'), matching: words('Summary'))).top, closeTo(286.88 - lift, 0.75));
      // With Speak, the dock is three: Search, +, and Speak nearest the thumb.
      at(tester.getRect(key('dock-search')), 362.44, 767.28, 39.59, 39.59, reason: 'Search');
      at(tester.getRect(key('dock-add')), 362.44, 815.86, 39.59, 39.59, reason: '+');
      at(tester.getRect(key('dock-speak')), 362.44, 864.44, 39.59, 39.59, reason: 'Speak');
      await away(tester);
    });

    testWidgets('on an opened Fold (669x951): three cards across, one height, and the dock', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), size: const Size(669, 951), split: true);
      await settle(tester);
      at(tester.getRect(find.bySemanticsLabel('Filters')), 598.27, 100.91 - foldLift, 47.16, 47.16, reason: 'filters button');
      at(tester.getRect(key('line-weekend')), 23.58, 202.77 - foldLift, 621.84, 47.16, reason: 'the pinned line');
      at(tester.getRect(key('card-prd11')), 23.58, 304.63 - foldLift, 197.84, 261.05, reason: 'card 1');
      at(tester.getRect(key('card-standup')), 235.56, 304.63 - foldLift, 197.86, 261.05, reason: 'card 2');
      at(tester.getRect(key('card-flat')), 447.56, 304.63 - foldLift, 197.84, 261.05, reason: 'card 3');
      at(tester.getRect(key('card-open-tickets')), 23.58, 579.81 - foldLift, 197.84, 214.2, reason: 'card 4');
      // The dates of a row of cards: the short cards' stand together, under previews grown to their six lines.
      expect(tester.getRect(find.text('40 min ago')).top, closeTo(484.97 - foldLift, 0.75));
      expect(tester.getRect(find.text('48 min ago')).top, closeTo(484.97 - foldLift, 0.75));
      expect(tester.getRect(find.text('20 min ago')).top, closeTo(531.81 - foldLift, 0.75));
      expect(tester.getRect(find.text('Today')).top, closeTo(822.3 - foldLift, 1));
      at(tester.getRect(key('dock-add')), 598.23, 880.23, 41.48, 41.48, reason: '+');
      at(tester.getRect(key('dock-search')), 598.23, 829.33, 41.48, 41.48, reason: 'Search');
      await away(tester);
    });

    testWidgets('pads by the notch and the home bar where the phone has them', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), insets: true);
      await settle(tester);
      // pumpApp's phone: 36 at the top, 20 at the foot.
      expect(tester.getSize(find.byType(HeaderPane)).height, closeTo(36 + 46.78 - barLess, 0.1));
      expect(tester.getRect(find.bySemanticsLabel('Filters')).top, closeTo(36 + 87.48 - lift, 0.75));
      expect(tester.getRect(key('dock-add')).bottom, closeTo(932 - 20 - 17.98 - 9.99, 0.75));
      await away(tester);
    });
  });

  group('the search', () {
    testWidgets('ends at the keyboard, whose height the dock rides up by, as the page’s frame is padded by it', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final before = tester.getRect(key('dock-add'));
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final after = tester.getRect(key('dock-add'));
      expect(before.top - after.top, closeTo(300, 0.01));
      expect(after.left, before.left);
      await away(tester);
    });

    testWidgets('as the keyboard goes, the dock follows it down and stops on the home bar, never below it', (tester) async {
      // Matt: "When hiding the search the dock animates down but jitters and glitches at the end". The dock rode the
      // keyboard alone while any of it showed: its last frames, lower than the bar, dropped the dock below where it
      // rests, and it leapt back up by the bar's height as the keyboard went.
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), insets: true);
      await settle(tester);
      final rest = tester.getRect(key('dock-add')).bottom;
      final ratio = tester.view.devicePixelRatio;
      addTearDown(tester.view.resetViewInsets);
      final seen = <double>[];
      for (var up = 300; up >= 0; up -= 5) {
        tester.view.viewInsets = FakeViewPadding(bottom: up * ratio);
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(tester.getRect(key('dock-add')).bottom);
      }
      // pumpApp's phone has 20 at the foot: with the keys 300 up, the dock is 280 above where it rests.
      expect(rest - seen.first, closeTo(280, 0.75));
      for (var i = 0; i < seen.length; i++) {
        expect(seen[i], lessThanOrEqualTo(rest + 0.01), reason: 'frame $i, ${300 - 5 * i} of keyboard: below the bar');
        if (i > 0) expect(seen[i], greaterThanOrEqualTo(seen[i - 1] - 0.01), reason: 'frame $i: the dock went back up');
      }
      expect(seen.last, closeTo(rest, 0.01));
      await away(tester);
    });

    // Differs 12 (docs/PARITY.md): `useGists(cardsIn(plan).slice(0, GISTED))` (home/HomeScreen.tsx). The page asks
    // the phone for a line under the first sixteen cards it lays out, so its search and its filter decide whose is
    // written; a card past the sixteenth has none, written before or not.
    testWidgets('draws the line the phone wrote under each of its first sixteen cards, and none under a card past them, written or not', (tester) async {
      // `gists[note.id]` of `useGists(carded)`: the hook answers for the cards it was handed and no others
      // (format/gist.ts), so a line kept for the seventeenth card is not drawn.
      final before = stored;
      useStored(MemoryStored());
      addTearDown(() => useStored(before));
      forgetGistRunner();
      addTearDown(forgetGistRunner);
      final library = SampleLibrary([for (var i = 0; i < 20; i += 1) makeNote('n$i', body: '# Note $i\n\nWhat note $i says.', updatedAt: seedNow - i * 60000)], clock: () => seedNow);
      for (final note in library.value) {
        keepGist(note.id, Gist(text: 'The line of ${note.id}', forBody: bodyHash(note.body), model: 'qwen3.5-2b', len: note.body.length, head: note.body.split('\n').first));
      }
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.cards), ratio: 1);
      await settle(tester);
      final lines = await down(tester, () => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) (card.note.id, card.gist)]);
      expect(lines.length, 20);
      expect(homeGisted, 16);
      expect(lines.take(16), [for (var i = 0; i < 16; i += 1) ('n$i', 'The line of n$i')]);
      expect(lines.skip(16), [for (var i = 16; i < 20; i += 1) ('n$i', null)]);
      await away(tester);
    });

    testWidgets('lists what it found as lines, and asks the phone for no line under a card while it stands', (tester) async {
      final before = stored;
      useStored(MemoryStored());
      addTearDown(() => useStored(before));
      forgetGistRunner();
      final phone = FakeAiBackend()
        ..answers['ai_models'] = const [
          {'id': 'qwen3.5-2b', 'present': true},
        ]
        ..answers['ai_generate'] = const {'text': 'What the weekend is for', 'ms': 5, 'truncated': false, 'outputTokens': 6, 'thinking': false};
      addTearDown(() {
        forgetGistRunner();
        useAiBackend(const NoAiBackend());
      });
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      // The phone has its engine from here: what a search finds is a line each, and no card is shown to the runner.
      useAiBackend(phone);
      await tester.enterText(find.byType(EditableText), 'cabin friday');
      await settle(tester);
      expect(find.byType(NoteCard), findsNothing);
      expect(key('line-cabin-canvas'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 3));
      // No card on the page, so no line asked for while the search stands.
      expect(phone.requests, isEmpty);
      forgetGistRunner();
      await away(tester);
    });

    testWidgets('narrows the page as it is typed, every word anywhere in a note, and says when nothing has it', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'cabin friday');
      await settle(tester);
      // The trip's note and the canvas that lays the same weekend out: what was found, a line each, the nearest
      // first, with the words it matched under a note found by its words (lib/core/search_hits.dart).
      expect(headings(tester), ['Found 2']);
      expect(key('line-weekend'), findsOneWidget);
      expect(key('line-cabin-canvas'), findsOneWidget);
      expect(find.byType(NoteCard), findsNothing);
      // The count at the foot is the library's, not the search's.
      expect(find.text('All notes · 20'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'no note says this');
      await settle(tester);
      expect(headings(tester), isEmpty);
      expect(find.text('Nothing has “no note says this”.'), findsOneWidget);
      expect(find.text('Try fewer words, or look through All notes.'), findsOneWidget);

      // Its cross clears it, and the page is whole again.
      await tester.tap(find.bySemanticsLabel('Clear the search'));
      await settle(tester);
      expect(headings(tester).first, 'Pinned 1');
      expect(find.bySemanticsLabel('Clear the search'), findsNothing);
      await away(tester);
    });
  });

  group('the filters', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(filters);
      await settle(tester);
    }

    testWidgets('open from the button in a panel under it: what to show, with how many of each, and which workspace', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await open(tester);
      // Where the web page's panel stood: hung from the button's end, seventeen rem wide.
      expect(tester.getRect(find.text('SHOW')).topLeft, within(distance: 1.5, from: const Offset(153.97, 157.48 - lift)));
      expect(tester.getRect(find.text('Notebooks').last).topLeft, within(distance: 1.5, from: const Offset(183.63, 237.45 - lift)));
      expect(tester.getRect(find.text('New workspace')).topLeft, within(distance: 1.5, from: const Offset(183.63, 558.85 - lift)));
      for (final choice in ['All, 20', 'Notebooks, 2', 'Notes, 18', 'Pinned, 1', 'Every workspace', 'Work', 'Home']) {
        expect(radio(choice), findsOneWidget, reason: choice);
      }
      // Signed out, there is no New organization.
      expect(find.text('New organization'), findsNothing);
      // A press outside closes it (here in the page's gutter, where it lands on nothing else).
      await tester.tapAt(const Offset(8, 600));
      await settle(tester);
      expect(find.text('SHOW'), findsNothing);
      await away(tester);
    });

    testWidgets('name a folder with its organization before it, "HelloTrade › Designs", and list it under its organization', (tester) async {
      // Matt, 2026-10-20: "when filtering, instead of showing folders as orgs show them as Org -> Folder".
      final org = orgWorkspaceId('ht');
      final store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(
          WorkspaceSheet(list: [
            Workspace(id: org, name: 'HelloTrade'),
            const Workspace(id: 'w-work', name: 'Work'),
            Workspace(id: 'f-designs', name: 'Designs', parent: org),
          ]),
        ),
      );
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: store, asked: it.asked));
      await settle(tester);
      await open(tester);
      const labels = ['Every workspace', 'HelloTrade', 'HelloTrade › Designs', 'Work'];
      for (final label in labels) {
        expect(radio(label), findsOneWidget, reason: label);
      }
      expect(radio('Designs'), findsNothing, reason: 'a folder is never named alone, as if it were an organization');
      final tops = [for (final label in labels) tester.getRect(radio(label)).top];
      expect([...tops]..sort(), tops, reason: 'the folder sits under its organization, before the next workspace');
      await tester.tap(radio('HelloTrade › Designs'));
      await tester.tapAt(const Offset(8, 600));
      await settle(tester);
      expect(find.bySemanticsLabel('HelloTrade › Designs: every workspace'), findsOneWidget, reason: 'the chip says the path too');
      await away(tester);
    });

    testWidgets('show only what is chosen, ink the button, and name each choice in a chip whose cross takes it off', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await open(tester);
      await tester.tap(radio('Pinned, 1'));
      await settle(tester);
      // The panel stays for another choice: only the notebooks, the two of them touched last.
      await tester.tap(radio('Notebooks, 2'));
      await settle(tester);
      expect(headings(tester), ['Recent']);
      expect([for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id], ['product', 'portugal']);
      await tester.tap(radio('Pinned, 1'));
      await tester.tapAt(const Offset(8, 600));
      await settle(tester);
      expect(headings(tester), ['Pinned 1']);
      expect(find.bySemanticsLabel('Filters: Pinned'), findsOneWidget);
      at(tester.getRect(find.bySemanticsLabel('Pinned: show everything')), 22.48, 145.95 - lift, 106.64, 35.98, within: 1.5, reason: 'the chip');
      // Nothing pinned, said plainly.
      it.library.pin('weekend', pinned: false);
      await settle(tester);
      expect(find.text('Nothing is pinned.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Pinned: show everything'));
      await settle(tester);
      expect(find.bySemanticsLabel('Filters'), findsOneWidget);
      expect(headings(tester).first, 'Recent');
      await away(tester);
    });

    testWidgets('filter to a workspace, whose notes alone are listed and counted', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await open(tester);
      await tester.tap(radio('Home'));
      await tester.tapAt(const Offset(8, 600));
      await settle(tester);
      expect(it.workspaces.value.current?.name, 'Home');
      expect(headings(tester), ['Recent']);
      expect([for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id], ['flat', 'groceries', 'house']);
      expect(find.text('All notes · 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Filters: Home'), findsOneWidget);
      // Its chip under the search, where the web page's stood, and the notes a row further down for it.
      final chip = tester.getRect(find.bySemanticsLabel('Home: every workspace'));
      expect(chip.topLeft, within(distance: 0.75, from: const Offset(22.48, 145.95 - lift)));
      expect(chip.height, closeTo(35.98, 0.75));
      expect(tester.getRect(find.text('Recent')).top, closeTo(208.91 - lift, 0.75));
      // The panel offers its name and colour to change, and a new one.
      await open(tester);
      await tester.tap(find.text('Edit Home'));
      await settle(tester);
      expect(it.asked.said, ['edit Home']);
      expect(find.text('SHOW'), findsNothing, reason: 'the panel closes for the sheet');
      await open(tester);
      await tester.tap(find.text('New workspace'));
      await settle(tester);
      expect(it.asked.said, ['edit Home', 'new workspace']);
      // The chip's cross leaves the workspace.
      await tester.tap(find.bySemanticsLabel('Home: every workspace'));
      await settle(tester);
      expect(it.workspaces.value.current, isNull);
      await toFoot(tester);
      expect(find.text('All notes · 20'), findsOneWidget);
      await away(tester);
    });

    testWidgets('say a pinned note’s workspace in a pill, until the page is filtered to one', (tester) async {
      final it = seeded();
      it.workspaces.fileNote('weekend', 'home');
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      expect(find.descendant(of: key('line-weekend'), matching: find.text('Home')), findsOneWidget);
      it.workspaces.chooseWorkspace('home');
      await settle(tester);
      expect(find.descendant(of: key('line-weekend'), matching: find.text('Home')), findsNothing);
      await away(tester);
    });

    testWidgets('are walked with the arrow keys, each choice chosen as it is reached', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(find.bySemanticsLabel('Filters: Notebooks'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester);
      expect(find.bySemanticsLabel('Filters: Pinned'), findsOneWidget, reason: 'round the end');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('SHOW'), findsNothing);
      await away(tester);
    });
  });

  group('the swipes (docs/DESIGN.md §151)', () {
    Future<void> swipe(WidgetTester tester, Finder what, double dx) async {
      final gesture = await tester.startGesture(tester.getCenter(what));
      // Past the slop, then the rest: the row follows the finger from where it went down.
      await gesture.moveBy(Offset(dx.sign * 30, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx - dx.sign * 30, 0));
      await tester.pump();
      await gesture.up();
      await settle(tester);
    }

    testWidgets('right pins a note or unpins it, left archives it, and further left deletes it instead', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      // A card, 385 wide: a quarter of the way right is past the pin's detent.
      await swipe(tester, key('card-standup'), 110);
      expect(it.asked.said, ['swipe pin standup']);
      expect(it.library.noteOf('standup')!.starred, isTrue);
      expect(headings(tester).first, 'Pinned 2');
      // A line swipes too: back out of Pinned.
      await swipe(tester, key('line-standup'), 110);
      expect(it.library.noteOf('standup')!.starred, isFalse);
      // Left past the first detent: archived, and gone from the page.
      await swipe(tester, key('card-flat'), -110);
      expect(it.asked.said.last, 'swipe archive flat');
      expect(it.library.noteOf('flat')!.archivedAt, isNotNull);
      expect(key('card-flat'), findsNothing);
      // Further left, past the second: deleted.
      await swipe(tester, key('card-prd11'), -240);
      expect(it.asked.said.last, 'swipe delete prd11');
      expect(it.library.noteOf('prd11'), isNull);
      await away(tester);
    });

    testWidgets('do nothing short of the first detent, and never open the note they moved', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await swipe(tester, key('card-standup'), 60);
      expect(it.asked.said, isEmpty);
      await tester.tap(key('card-standup'));
      expect(it.asked.said, ['open standup']);
      await away(tester);
    });

    testWidgets('show the action in the gap as it nears, and name the one further along once armed', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final gesture = await tester.startGesture(tester.getCenter(key('card-standup')));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('ARCHIVE'), findsOneWidget);
      expect(find.text('Further to delete'), findsNothing, reason: 'not armed yet');
      // `.behind { place-items: center }`: the picture and its word stand in the middle of the card's height.
      final card = tester.getRect(key('card-standup')), word = tester.getRect(find.text('ARCHIVE'));
      expect(word.top, greaterThan(card.center.dy), reason: 'the word is under the picture, below the middle');
      expect(word.top - card.center.dy, lessThan(40));
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Further to delete'), findsOneWidget);
      await gesture.moveBy(const Offset(-140, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DELETE'), findsOneWidget);
      // Let go nowhere: the row goes home, and nothing is done.
      await gesture.cancel();
      await settle(tester);
      expect(it.asked.said, isEmpty);
      expect(find.text('DELETE'), findsNothing);
      await away(tester);
    });

    testWidgets('are not there where the page was given nothing to do with them', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, swipes: false));
      await settle(tester);
      expect(find.byType(SwipeRow), findsNothing);
      await away(tester);
    });

    testWidgets('are offered to a screen reader as each note’s own actions', (tester) async {
      final handle = tester.ensureSemantics();
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Weekend trip, 1 hr ago'));
      final actions = <String>[];
      void gather(SemanticsNode at) {
        final data = at.getSemanticsData();
        for (final id in data.customSemanticsActionIds ?? const <int>[]) {
          actions.add(CustomSemanticsAction.getAction(id)!.label!);
        }
        at.visitChildren((child) {
          gather(child);
          return true;
        });
      }

      gather(node);
      expect(actions, containsAll(['Unpin', 'Archive', 'Delete']));
      handle.dispose();
      await away(tester);
    });
  });

  group('a pull down from the top (docs/DESIGN.md §152)', () {
    testWidgets('refreshes once it is let go past the detent, and not short of it', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, refresh: true));
      await settle(tester);
      // Short of it: the page goes back up.
      var gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(it.asked.said, isEmpty);

      gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.bySemanticsLabel('Let go to refresh'), findsOneWidget);
      // The page comes down with the finger, at half its travel.
      expect(tester.getRect(find.bySemanticsLabel('Filters')).top, closeTo(87.48 - lift + 64 + (82 - 64) / 3, 1));
      await gesture.up();
      await tester.pump();
      expect(it.asked.said, ['refresh']);
      expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
      // It spins at least half a second, says it is done, and the page goes back up.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.bySemanticsLabel('Up to date'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(find.bySemanticsLabel('Filters')).top, closeTo(87.48 - lift, 0.75));
      await away(tester);
    });

    testWidgets('is a scroll, not a pull, from a page that is not at its top', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, refresh: true));
      await settle(tester);
      await tester.drag(key('home-scroll'), const Offset(0, -400));
      await settle(tester);
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(it.asked.said, isEmpty);
      await away(tester);
    });
  });

  group('the dock', () {
    testWidgets('writes, speaks and opens the palette, each by its own callback', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Write a note'));
      await tester.tap(find.bySemanticsLabel('Speak a voice note'));
      await tester.tap(find.bySemanticsLabel('Search and commands'));
      expect(it.asked.said, ['new', 'speak', 'search']);
      // Search on top, write in the middle, Speak last, nearest the thumb.
      expect(tester.getRect(key('dock-search')).top, lessThan(tester.getRect(key('dock-add')).top));
      expect(tester.getRect(key('dock-add')).top, lessThan(tester.getRect(key('dock-speak')).top));
      await settle(tester);
      await away(tester);
    });

    testWidgets('has no Speak where nothing records, and no Search until the palette is there', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, search: false));
      await settle(tester);
      expect(find.bySemanticsLabel('Write a note'), findsOneWidget);
      expect(find.bySemanticsLabel('Speak a voice note'), findsNothing);
      expect(find.bySemanticsLabel('Search and commands'), findsNothing);
      await away(tester);
    });

    testWidgets('turns its + a quarter when pressed, and leans its magnifier in', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final plus = await tester.startGesture(tester.getCenter(key('dock-add')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<AnimatedRotation>(find.descendant(of: key('dock-add'), matching: find.byType(AnimatedRotation))).turns, 0.25);
      await plus.up();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<AnimatedRotation>(find.descendant(of: key('dock-add'), matching: find.byType(AnimatedRotation))).turns, 0);
      final search = await tester.startGesture(tester.getCenter(key('dock-search')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.descendant(of: key('dock-search'), matching: find.byType(AnimatedScale))).scale, 0.9);
      await search.up();
      await tester.pump(const Duration(seconds: 1));
      await away(tester);
    });
  });

  group('what leaves the page', () {
    // The menu is a mouse's right-click and no finger's (docs/PARITY.md, Differs 30; notes/noteMenu.ts `byMouse`).
    testWidgets('a card, a row and a line open their note; the foot opens All notes; a mouse’s right-click asks for the menu and a long press does not', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      await tester.tap(key('line-weekend'));
      await tester.tap(key('card-prd11'));
      await tester.longPress(key('card-standup'));
      await tester.longPress(key('line-weekend'));
      await settle(tester);
      for (final on in ['card-standup', 'line-weekend']) {
        final mouse = await tester.startGesture(tester.getCenter(key(on)), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
        await mouse.up();
        await settle(tester);
      }
      await bring(tester, key('row-sprint'));
      await tester.tap(key('row-sprint'));
      await bring(tester, find.text('All notes · 20'));
      await tester.tap(find.text('All notes · 20'));
      expect(it.asked.said, ['open weekend', 'open prd11', 'menu standup', 'menu weekend', 'open sprint', 'all notes']);
      await settle(tester);
      await away(tester);
    });
  });

  group('an empty page', () {
    testWidgets('is a blank page with no search, and says how to fill it', (tester) async {
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), speak: true));
      await settle(tester);
      expect(find.byType(EditableText), findsNothing);
      // The words, as the page sets them (measured on the web page, less its ghost above them).
      final lead = tester.widget<Text>(find.text('A blank page.')).style!;
      expect(lead.fontSize, closeTo(34.15, 0.01));
      expect(lead.letterSpacing, closeTo(-0.854, 0.001));
      expect(tester.getRect(find.text('A blank page.')).height, closeTo(40.98, 0.6));
      expect(tester.getRect(find.text('Write it, or tap Speak and say it.')).height, closeTo(24.25, 0.75), reason: 'one line: 28ch holds it');
      expect(find.text('Write it, or tap Speak and say it.'), findsOneWidget);
      expect(find.text('All notes · 0'), findsNothing);
      await away(tester);
    });

    testWidgets('says the side key on a phone that has one, and + alone where nothing records', (tester) async {
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), sideKey: true));
      await settle(tester);
      expect(find.text('Write it, or hold the side key and say it.'), findsOneWidget);
      await away(tester);
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked()));
      await settle(tester);
      expect(find.text('Tap + to write it.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('in a workspace names it, and keeps the filters to leave it by', (tester) async {
      final workspaces = WorkspaceStore();
      final empty = workspaces.addWorkspace('Trips', 'amber')!;
      workspaces.chooseWorkspace(empty.id);
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: workspaces, asked: it.asked));
      await settle(tester);
      expect(find.text('Nothing in Trips yet.'), findsOneWidget);
      expect(find.bySemanticsLabel('Filters: Trips'), findsOneWidget);
      expect(find.bySemanticsLabel('Trips: every workspace'), findsOneWidget);
      await away(tester);
    });

    testWidgets('says nothing while the library is still being read', (tester) async {
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), loading: true));
      await settle(tester);
      expect(find.text('A blank page.'), findsNothing);
      await away(tester);
    });

    testWidgets('draws its ghost where one is handed in, by the scene the page is in', (tester) async {
      final asked = <HomeGhost>[];
      Widget ghost(BuildContext context, HomeGhost it) {
        asked.add(it);
        return const SizedBox(key: ValueKey('ghost'), width: 120, height: 40);
      }

      final it = seeded();
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), ghost: ghost));
      await settle(tester);
      // Stacked over its words on a phone, held to 38% of the window's height, a group's air over the words.
      expect([asked.last.scene, asked.last.lead, asked.last.heightShare], [HomeGhostScene.noNotes, true, 0.38]);
      expect(tester.getRect(key('ghost')).left, closeTo(22.48, 0.75));
      expect(tester.getRect(find.text('A blank page.')).top - tester.getRect(key('ghost')).bottom, closeTo(22.5, 0.75));
      await away(tester);

      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, ghost: ghost));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'zzzz');
      await settle(tester);
      expect([asked.last.scene, asked.last.lead, asked.last.heightShare], [HomeGhostScene.searchNothing, false, null]);
      // A small ghost, then the line (the web page's: the ghost's foot, then nine pixels to the words).
      expect(tester.getRect(key('ghost')).top, closeTo(172.94 - lift, 0.75));
      expect(tester.getRect(find.text('Nothing has “zzzz”.')).top - tester.getRect(key('ghost')).bottom, closeTo(9, 0.75));
      expect(tester.widget<Text>(find.text('Nothing has “zzzz”.')).style!.fontSize, closeTo(23.5, 0.01));
      at(tester.getRect(find.bySemanticsLabel('Clear the search')), 321.06, 96.48 - lift, 26.98, 26.98, reason: 'the cross in the search');
      await away(tester);

      // Wider, the ghost and its words stand side by side.
      await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), ghost: ghost), size: const Size(900, 700));
      await settle(tester);
      expect(asked.last.heightShare, isNull, reason: 'beside its words it may have a lead’s full share');
      expect(tester.getRect(key('ghost')).right, lessThan(tester.getRect(find.text('A blank page.')).left));
      await away(tester);
    });
  });

  group('a phone and a wider page', () {
    testWidgets('one card to a row on a phone held upright, and as many as fit twelve rem across past 600', (tester) async {
      expect(NoteCards.columnsFor(385, 430, gap: 13.5, least: 192), 1);
      expect(NoteCards.columnsFor(555, 599, gap: 13.5, least: 192), 1);
      expect(NoteCards.columnsFor(621.84, 669, gap: 14.15, least: 192), 3);
      expect(NoteCards.columnsFor(1024, 1280, gap: 16, least: 192), 5);

      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.cards), size: const Size(1280, 800), ratio: 1);
      await settle(tester);
      // The page keeps to 64rem, in the middle of the window.
      final product = tester.getRect(key('card-product')), portugal = tester.getRect(key('card-portugal'));
      expect(product.left, closeTo((1280 - 1024) / 2, 0.75));
      expect(portugal.top, product.top);
      expect(portugal.height, product.height, reason: 'the cards of a row are one height');
      await away(tester);
    });

    testWidgets('the rows’ layouts keep one readable column on a wide page', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.timeline), size: const Size(1280, 800), ratio: 1);
      await settle(tester);
      expect(tester.getRect(key('row-prd11')).width, closeTo(768, 0.75));
      expect(tester.getRect(key('row-prd11')).center.dx, closeTo(640, 0.75));
      await away(tester);
    });
  });

  group('the organizations', () {
    const orgs = [
      HomeOrg(id: 'acme', name: 'Acme', hue: 'violet', members: 3, here: [OrgPresence(client: 'c1', handle: 'ana', editingNote: 'weekend', editingTitle: 'Weekend trip'), OrgPresence(client: 'c2', handle: 'ali')]),
      HomeOrg(id: 'cabin', name: 'Cabin club', hue: 'moss', members: 1),
    ];

    testWidgets('are a small tile each, saying how many notes and members, and open on a tap', (tester) async {
      final it = seeded();
      it.workspaces.ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      it.workspaces.fileNote('weekend', 'org-acme');
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: orgs));
      await settle(tester);
      expect(headings(tester).first, 'Organizations');
      expect(find.text('1 note · 3 members'), findsOneWidget);
      expect(find.text('0 notes · 1 member'), findsOneWidget);
      // Who is in now is the organization's own page's to say, not the home page's.
      expect(find.textContaining('is editing'), findsNothing);
      await tester.tap(find.text('Cabin club'));
      expect(it.asked.said, ['organization cabin']);
      // Signed in, the filters' panel makes an organization beside a workspace.
      await tester.tap(find.bySemanticsLabel('Filters'));
      await settle(tester);
      await tester.tap(find.text('New organization'));
      await settle(tester);
      expect(it.asked.said.last, 'new organization');
      // Not while searching.
      await tester.enterText(find.byType(EditableText), 'trip');
      await settle(tester);
      expect(find.text('Organizations'), findsNothing);
      await away(tester);
    });

    testWidgets('filtered to one, the page says what has happened lately in it, over the notes on a phone', (tester) async {
      final it = seeded();
      it.workspaces.ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      it.workspaces.fileNote('weekend', 'org-acme');
      it.workspaces.fileNote('flat', 'org-acme');
      it.workspaces.chooseWorkspace('org-acme');
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: orgs));
      await settle(tester);
      // Inside one workspace there are no organization cards, only its own events.
      expect(find.text('Organizations'), findsNothing);
      expect(find.text('Recent in Acme'), findsOneWidget);
      expect(find.text('ana is editing Weekend trip'), findsOneWidget);
      expect(find.text('Flat changed'), findsOneWidget);
      expect(tester.getRect(find.text('Recent in Acme')).top, lessThan(tester.getRect(find.text('Pinned')).top));
      await tester.tap(find.text('Flat changed'));
      await tester.tap(find.text('Open Acme'));
      expect(it.asked.said, ['open flat', 'organization acme']);
      // "Edit" on an organization's workspace is the organization's screen.
      await tester.tap(filters);
      await settle(tester);
      await tester.tap(find.text('Edit Acme'));
      await settle(tester);
      expect(it.asked.said.last, 'organization acme');
      await away(tester);
    });

    // docs/CLAUDE_LIVE.md: "Claude is editing Roadmap" on the home page, as the AI it is.
    testWidgets('say an AI on a note as an AI, with its spark and what it is doing, and open the note', (tester) async {
      final it = seeded();
      it.workspaces.ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      it.workspaces.fileNote('weekend', 'org-acme');
      it.workspaces.chooseWorkspace('org-acme');
      const withClaude = [
        HomeOrg(id: 'acme', name: 'Acme', hue: 'violet', members: 3, here: [
          OrgPresence(client: 'c9', handle: 'Claude', hue: 'violet', ai: true, via: 'ana', editingNote: 'weekend', editingTitle: 'Weekend trip', doing: 'editing'),
          OrgPresence(client: 'c8', handle: 'Cursor', ai: true, via: 'ana', editingNote: 'weekend', editingTitle: 'Weekend trip', doing: 'reading'),
          OrgPresence(client: 'c1', handle: 'ana', editingNote: 'weekend', editingTitle: 'Weekend trip'),
        ]),
      ];
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: withClaude));
      await settle(tester);
      expect(find.text('Claude is editing Weekend trip'), findsOneWidget);
      expect(find.text('Cursor is reading Weekend trip'), findsOneWidget);
      expect(find.text('ana is editing Weekend trip'), findsOneWidget);
      // The AIs wear the spark, the person a dot.
      expect(find.byKey(const ValueKey('event-ai')), findsNWidgets(2));
      await tester.tap(find.text('Claude is editing Weekend trip'));
      expect(it.asked.said, ['open weekend']);
      await away(tester);
    });

    testWidgets('are not drawn for an account in none', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: const []));
      await settle(tester);
      expect(find.text('Organizations'), findsNothing);
      await away(tester);
    });
  });

  group('the seams for the smoke', () {
    testWidgets('hand the scroller, with where the header ends and the dock stands, to whoever draws the wisp; and the dock to its halo', (tester) async {
      final it = seeded();
      HomeEdge? given;
      HomeDock? docked;
      await pumpHome(
        tester,
        Home(
          library: it.library,
          workspaces: it.workspaces,
          asked: it.asked,
          headerEdge: (context, edge, scroller) {
            given = edge;
            return KeyedSubtree(key: const ValueKey('wisp'), child: scroller);
          },
          dockHalo: (context, it) {
            docked = it;
            return Stack(
              fit: StackFit.expand,
              children: [KeyedSubtree(key: const ValueKey('behind'), child: it.behind), Padding(padding: it.padding, child: Align(alignment: it.alignment, child: it.dock))],
            );
          },
        ),
      );
      await settle(tester);
      expect(given!.under, closeTo(47 - 7, 0.01), reason: 'the header pane, to the whole pixel the web measured, less the condensed bar\'s');
      expect(given!.foot, closeTo(0 + 17.99 + 39.59 * 4 + 8.99 * 5 + 26.98, 0.5));
      expect(given!.controller.hasClients, isTrue);
      expect(find.descendant(of: key('wisp'), matching: key('home-scroll')), findsOneWidget);
      // The halo's drawer has what scrolls behind the dock, the dock, and where it stands: a gutter in from the
      // bottom end corner, as the web page's `.dockSpot`.
      expect(find.descendant(of: key('behind'), matching: key('home-scroll')), findsOneWidget);
      expect(docked!.alignment, AlignmentDirectional.bottomEnd);
      expect(docked!.padding.resolve(TextDirection.ltr).right, closeTo(17.99, 0.01));
      expect(docked!.padding.resolve(TextDirection.ltr).bottom, closeTo(17.99, 0.01));
      at(tester.getRect(key('dock-add')), 362.44, 864.44, 39.59, 39.59, reason: 'the dock is where it was');
      await away(tester);
    });
  });

  group('how it moves', () {
    testWidgets('its cards and rows arrive from below, a beat apart, and stand still under reduced motion', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      double shown(String name) => tester.widget<Opacity>(find.descendant(of: key(name), matching: find.byType(Opacity)).first).opacity;
      await tester.pump(const Duration(milliseconds: 60));
      expect(shown('line-weekend'), greaterThan(0));
      expect(shown('card-flat'), 0, reason: 'the fourth thing on the page waits its beats');
      await settle(tester);
      expect(shown('card-flat'), 1);
      await away(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await tester.pump();
      expect(shown('card-flat'), 1);
      await away(tester);
    });

    testWidgets('another filter glides the page back to its top', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: HomeLayout.timeline));
      await settle(tester);
      await tester.drag(key('home-scroll'), const Offset(0, -500));
      await settle(tester);
      final position = tester.state<ScrollableState>(scroller).position;
      expect(position.pixels, greaterThan(300));
      it.workspaces.chooseWorkspace('work');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(position.pixels, greaterThan(0), reason: 'on its way, not jumped');
      await settle(tester);
      expect(position.pixels, 0);
      await away(tester);
    });
  });

  // Matt, 2026-10-28: "remove the search bar from the home page since it's redundant", with the header toolbar's
  // Grouped command, whose title pill is the search (lib/shell/header/grouped_command_row.dart), the default since
  // 2026-10-29 ("make the grouped command the default header layout"). The field and the filters' button go to the
  // bar only where a bar is over the page to hold them: drawn alone the page keeps both in every version.
  testWidgets('the page’s search field and filters go while a bar with a search pill is over it, the other versions keep them, and a page alone keeps them', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(() => headerToolbarChoice.set(HeaderToolbarVersion.fallback.id));
    final it = seeded();
    final slot = TopBarTools();
    addTearDown(slot.dispose);
    for (final under in [true, false]) {
      final home = Home(library: it.library, workspaces: it.workspaces, asked: it.asked);
      await pumpHome(tester, under ? TopBarToolsScope(notifier: slot, child: home) : home);
      await settle(tester);
      for (final version in HeaderToolbarVersion.values) {
        headerToolbarChoice.set(version.id);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Command centre too since 2.3.68 (Matt, 2026-10-29: "the search bar and filters is still showing on the homepage on
        // mobile when it shouldn't").
        final gone = under && version.searchPill;
        final why = '${version.label}, ${under ? 'under a bar' : 'alone'}';
        expect(find.bySemanticsLabel('Search notebooks and notes'), gone ? findsNothing : findsWidgets, reason: why);
        expect(find.bySemanticsLabel('Filters'), gone ? findsNothing : findsOneWidget, reason: why);
      }
      if (!under) {
        // The filters still open from where they stand, with Grouped command chosen and no bar to take them.
        headerToolbarChoice.set(HeaderToolbarVersion.groupedCommand.id);
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Filters'));
        await settle(tester);
        expect(radio('All, 20'), findsOneWidget);
      }
      await away(tester);
    }
    handle.dispose();
  });

  group('what a screen reader is told', () {
    testWidgets('the page’s name, its headings, each note in a sentence, and every control by what it does', (tester) async {
      final handle = tester.ensureSemantics();
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true));
      await settle(tester);
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Home')), matchesSemantics(label: 'Home', isHeader: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Pinned, 1')), matchesSemantics(label: 'Pinned, 1', isHeader: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Recent')), matchesSemantics(label: 'Recent', isHeader: true));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Weekend trip, 1 hr ago')),
        matchesSemantics(
          label: 'Weekend trip, 1 hr ago',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          // Its swipes, for a finger that cannot make them, and Move to…, for one that cannot carry it to a folder.
          customActions: const [CustomSemanticsAction(label: 'Unpin'), CustomSemanticsAction(label: 'Archive'), CustomSemanticsAction(label: 'Delete'), CustomSemanticsAction(label: 'Move to…')],
        ),
      );
      expect(find.bySemanticsLabel('Fix the sign-in loop, 20 min ago'), findsOneWidget);
      expect(find.bySemanticsLabel('Search notebooks and notes'), findsWidgets);
      for (final label in ['Filters', 'Write a note', 'Speak a voice note', 'Search and commands', 'New note']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      // A row says its name, its notebook, how it starts and when.
      await bring(tester, key('row-sprint'));
      expect(find.bySemanticsLabel('This sprint, query, 55 min ago'), findsOneWidget);
      // The filters: a dialog of radios, the chosen one checked.
      await tester.drag(key('home-scroll'), const Offset(0, 2000));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Filters'));
      await settle(tester);
      expect(tester.getSemantics(radio('All, 20')), matchesSemantics(label: 'All, 20', hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: true, hasTapAction: true));
      expect(tester.getSemantics(radio('Notebooks, 2')), matchesSemantics(label: 'Notebooks, 2', hasCheckedState: true, isInMutuallyExclusiveGroup: true, hasTapAction: true));
      handle.dispose();
      await away(tester);
    });
  });

  group('what the page builds, and when', () {
    /// A library of [count] notes touched a minute apart, the newest first: a long day of them.
    SampleLibrary long(int count) => SampleLibrary([for (var i = 0; i < count; i += 1) makeNote('n$i', body: '# Note $i\n\nWhat note $i says.', updatedAt: seedNow - i * 60000)], clock: () => seedNow);

    testWidgets('only the rows near the screen, of however many it lists, and each of the rest as it is scrolled to', (tester) async {
      final library = long(300);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.timeline));
      await settle(tester);
      // 300 rows under Today; a screen of them and a little more are there.
      expect(headings(tester), ['Today 300']);
      final built = tester.widgetList<HomeRow>(find.byType(HomeRow, skipOffstage: false)).length;
      expect(built, inInclusiveRange(10, 40));
      expect(find.byKey(const ValueKey('row-n0')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-n299'), skipOffstage: false), findsNothing);
      // Every one of them is on the page, in order, when it is gone down.
      final rows = await down(tester, () => [for (final row in tester.widgetList<HomeRow>(find.byType(HomeRow))) row.note.id]);
      expect(rows, [for (var i = 0; i < 300; i += 1) 'n$i']);
      // At its foot the last row is ruled off under, and the way to All notes follows it.
      await toFoot(tester);
      expect(find.byKey(const ValueKey('row-n299')), findsOneWidget);
      expect(find.text('All notes · 300'), findsOneWidget);
      expect(tester.getRect(find.text('All notes · 300')).top, greaterThan(tester.getRect(find.byKey(const ValueKey('row-n299'))).bottom));
      expect(tester.widgetList<HomeRow>(find.byType(HomeRow, skipOffstage: false)).length, lessThan(40));
      await away(tester);
    });

    testWidgets('nothing again for the same notes in a new list with new callbacks, and one row for one note changed', (tester) async {
      final library = long(40);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.timeline));
      await settle(tester);
      HomeRow row(String id) => tester.widget<HomeRow>(find.byKey(ValueKey('row-$id')));
      final first = row('n0'), second = row('n1');
      // Whoever hands the page its notes makes a new list of the same notes, and new callbacks, at every build.
      library.value = [...library.value];
      await tester.pump();
      expect(identical(row('n0'), first), isTrue, reason: 'the same notes: the page hands back the rows it made');
      expect(identical(row('n1'), second), isTrue);
      // The same notes read again from the library: new objects that say what the old ones said.
      library.value = [for (final note in library.value) note.copyWith()];
      await tester.pump();
      expect(identical(row('n0'), first), isTrue, reason: 'notes that say the same are the same notes');
      // One note pinned: the page is made again, and says so.
      library.pin('n1', pinned: true);
      await tester.pump();
      expect(identical(row('n0'), first), isFalse);
      expect(row('n1').note.starred, isTrue);
      await away(tester);
    });

    testWidgets('a callback handed over later is the one a row calls', (tester) async {
      final library = long(5);
      final first = Asked(), second = Asked();
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: first, layout: HomeLayout.timeline));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('row-n0')));
      expect(first.said, ['open n0']);
      // The same page, handed another's callbacks: the rows are the ones it made, and they call the new ones.
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: second, layout: HomeLayout.timeline));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('row-n1')));
      expect(first.said, ['open n0']);
      expect(second.said, ['open n1']);
      await away(tester);
    });

    testWidgets('a row arrives once: scrolled away and back it is there, and a row that changes its place arrives again', (tester) async {
      final library = long(120);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.timeline));
      // Arriving: the first row is on its way in.
      await tester.pump(const Duration(milliseconds: 100));
      double shown(String id) => tester.widget<Opacity>(find.descendant(of: find.byKey(ValueKey('row-$id')), matching: find.byType(Opacity)).first).opacity;
      expect(shown('n0'), inExclusiveRange(0, 1));
      await settle(tester);
      expect(shown('n0'), 1);
      final position = tester.state<ScrollableState>(scroller).position;
      // Far down the page: rows made only now, long after the page was. They have been on it all along.
      position.jumpTo(3000);
      await tester.pump();
      final far = tester.widgetList<HomeRow>(find.byType(HomeRow)).first.note.id;
      expect(shown(far), 1, reason: 'a row scrolled to is not arriving');
      // And back: the first row was taken down and is made again, arrived.
      expect(find.byKey(const ValueKey('row-n0'), skipOffstage: false), findsNothing);
      position.jumpTo(0);
      await tester.pump();
      expect(shown('n0'), 1, reason: 'a row scrolled back to does not arrive again');
      // A note touched goes to the top, and every row under it stands one lower: each is made again in its place.
      library.value = [for (final note in library.value) note.id == 'n3' ? note.copyWith(updatedAt: seedNow + 1) : note];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(shown('n3'), lessThan(1), reason: 'a row in a new place arrives there');
      await settle(tester);
      expect(shown('n3'), 1);
      await away(tester);
    });

    testWidgets('a pull lowers the rows that are there and builds none again', (tester) async {
      final library = long(60);
      await pumpHome(tester, Home(library: library, workspaces: WorkspaceStore(), asked: Asked(), layout: HomeLayout.timeline, refresh: true));
      await settle(tester);
      final before = tester.widget<HomeRow>(find.byKey(const ValueKey('row-n0')));
      final top = tester.getRect(find.byKey(const ValueKey('row-n0'))).top;
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(find.byKey(const ValueKey('row-n0'))).top, greaterThan(top + 20), reason: 'the page comes down with the finger');
      expect(identical(tester.widget<HomeRow>(find.byKey(const ValueKey('row-n0'))), before), isTrue, reason: 'and is not built again for it');
      // A row is pressed where it is drawn, not where it was laid out.
      // Let go short of the detent, the page goes back up.
      await gesture.moveBy(const Offset(0, -134));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(find.byKey(const ValueKey('row-n0'))).top, closeTo(top, 0.01));
      await away(tester);
    });
  });

  group('an organization’s events on a wide page', () {
    testWidgets('dock to the right of the notes, eighteen rem wide, the notes in the room that is left', (tester) async {
      final it = seeded();
      it.workspaces.ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      for (final id in ['weekend', 'flat', 'prd11', 'standup', 'sprint', 'reading']) {
        it.workspaces.fileNote(id, 'org-acme');
      }
      it.workspaces.chooseWorkspace('org-acme');
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: const [HomeOrg(id: 'acme', name: 'Acme', hue: 'violet', members: 3)]), size: const Size(1280, 800), ratio: 1);
      await settle(tester);
      final t = tester.element(key('home-scroll')).tokens;
      // The page's column: the window inside its gutters, held to 64rem and centred.
      final inner = 1280 - t.len('app-gutter-start') - t.len('app-gutter-end');
      final across = inner < t.lenOf('64rem') ? inner : t.lenOf('64rem');
      final left = t.len('app-gutter-start') + (inner - across) / 2;
      final events = tester.getRect(find.byType(HomeOrgEvents));
      expect(events.width, closeTo(t.lenOf('18rem'), 0.01));
      expect(events.right, closeTo(left + across, 0.01));
      // The notes beside it: from the column's start to a gap before the card.
      final heading = tester.getRect(find.byType(HomeHeading).first);
      expect(heading.left, closeTo(left, 0.01));
      expect(heading.right, closeTo(events.left - t.space(4), 0.01));
      // The two stand at one height: the card at the row's top, the first heading a section's air under it.
      expect(events.top, closeTo(heading.top - t.space(3), 0.01));
      // The cards of the notes are counted across the room the notes have, not the page's.
      final card = tester.getRect(find.byType(NoteCard).first);
      expect(card.left, closeTo(left, 0.01));
      expect(card.right, lessThanOrEqualTo(events.left - t.space(4) + 0.01));
      // And a line of the pinned runs the notes' whole width.
      final line = tester.getRect(find.byType(HomeLine).first);
      expect(line.left, closeTo(left, 0.01));
      expect(line.right, closeTo(events.left - t.space(4), 0.01));
      await tester.tap(find.text('Open Acme'));
      expect(it.asked.said, ['organization acme']);
      await away(tester);
    });
  });

  group('in the light', () {
    testWidgets('the page is ink on paper, from the same tokens', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), theme: 'light');
      await settle(tester);
      final t = tester.element(key('home-scroll')).tokens;
      expect(t.isDark, isFalse);
      expect(tester.widget<Text>(find.text('Weekend trip')).style!.color, t.color('app-ink'));
      expect(tester.widget<ColoredBox>(find.descendant(of: find.byType(HomeScreen), matching: find.byType(ColoredBox)).first).color, t.color('glacier-bg'));
      await away(tester);
    });
  });
}
