import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart' show GhostApp;
import 'package:ghost_md/activity/activity_ring.dart' show ActivityRing;
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/notes/tabs/bar_icon.dart' show BarGlyph;
import 'package:ghost_md/notes/tabs/bar_parts.dart' show BarRing, BarWord;
import 'package:ghost_md/notes/tabs/tab_parts.dart' show HomeTab;
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/app_tab_bar.dart' show AppTabBar;
import 'package:ghost_md/shell/header/header_kit.dart' show HeaderGlyph;
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/shell/page_dock.dart' show dockScrolledScale;
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/screen.dart' show ScreenNotes;
import 'package:glacier/glacier.dart' show GlacierPressable, GlacierTheme;
import 'package:ghost_md/shell/pop_menu.dart' show PopMenu;
import 'package:ghost_md/shell/top_bar.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// The header toolbar's six versions (lib/shell/header_toolbar.dart; Matt, 2026-10-28: "Add a few ways to redo the
/// header toolbar icons … add a developer setting to switch between 5 versions"): each drawn on a phone, the opened
/// Fold and the Mac without running over, every control the bar was given within reach of a press, a press doing
/// what the control does, and Developer's choice redrawing the bar at once.
///
/// The note is a stand-in that hands the bar what a note's screen hands it (lib/note/note_screen.dart): its tools,
/// its More as the tail, and the model they are drawn from, with every spare action a note can have.
///
/// Pictures, not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/shell/header_toolbar_test.dart` writes all
/// six on a note and at home, folded, unfolded and on the Mac, light and dark, into build/feature-shots/
/// header-toolbar/, and then `contact-sheet.png` there: the six on a note on the opened Fold, one under another.
void main() {
  setUpAll(loadAppFonts);

  /// A test of the app drawn with real shadows (`pumpApp`), which gives them back before the test is over.
  void barTest(String description, Future<void> Function(WidgetTester tester) body, {bool skip = false}) => testWidgets(description, (tester) async {
        await body(tester);
        debugDisableShadows = true;
      }, skip: skip);
  tearDown(() => headerToolbarChoice.set(HeaderToolbarVersion.fallback.id));

  const three = ['weekend', 'groceries', 'standup'];

  // The three windows: the Fold folded and opened, and the Mac's.
  const folded = (name: 'folded', size: Size(390, 844), mobile: true, fine: false);
  const unfolded = (name: 'unfolded', size: Size(880, 1000), mobile: true, fine: false);
  const mac = (name: 'mac', size: Size(1280, 800), mobile: false, fine: true);
  const windows = [folded, unfolded, mac];

  Future<AppShellState> pumpShell(
    WidgetTester tester, {
    HeaderToolbarVersion? version,
    required ({String name, Size size, bool mobile, bool fine}) window,
    String theme = 'light',
    TopBarStyle style = TopBarStyle.classic,
    List<String>? log,
    bool note = true,
  }) async {
    final said = log ?? <String>[];
    final sheet = await appSheet(tester);
    // A shell of its own each time: one pumped over another keeps the first one's screen.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await pumpApp(
      tester,
      size: window.size,
      prefs: Preferences(theme: theme),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        topBar: style,
        headerToolbar: version,
        openNotes: three,
        unread: true,
        mobile: window.mobile,
        finePointer: window.fine,
        organizations: const [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')],
        onNew: () => said.add('new'),
        onSearch: () => said.add('search'),
        onSettings: () => said.add('settings'),
        onOrganizations: () => said.add('organizations'),
        onDeleteNote: (_) {},
        noteBuilder: (context, shell, screen) => _StandInNote(note: screen.note, log: said.add),
        // The home page hands the bar its Filters, as lib/home/home_screen.dart does; only Grouped command draws them.
        homeBuilder: (context, shell) => TopBarFill(
          filters: (face) => GlacierPressable(onPressed: () => said.add('filters'), semanticLabel: 'Filters', builder: (context, state) => face(context, state, open: false, on: false)),
          child: HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
        ),
        asideBuilder: (context, shell) => const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final app = tester.state<AppShellState>(find.byType(AppShell));
    if (note) {
      app.openNote('groceries');
      // The note hands its tools over a frame after it builds.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return app;
  }

  // The activity ring is the app's own in every version, today's too (Matt, 2026-10-29: "Keep the activity indicator
  // always showing"): not one of a version's controls.
  Finder headerKeys() => find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('header:') && widget.key != ActivityRing.key_);

  Set<String> drawn(WidgetTester tester) => {for (final element in headerKeys().evaluate()) (element.widget.key! as ValueKey<String>).value.substring('header:'.length)};

  /// Every control in reach: those in the row, and those in each menu the row opens.
  Future<Set<String>> reachable(WidgetTester tester) async {
    final ids = drawn(tester);
    for (final trigger in const ['overflow', 'you', 'search']) {
      final found = find.byKey(HeaderAct.keyOf(trigger));
      final count = found.evaluate().length;
      for (var at = 0; at < count; at++) {
        final before = drawn(tester);
        await tester.tap(found.at(at), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        final after = drawn(tester);
        ids.addAll(after);
        // Shut again, by the trigger, where a menu opened.
        if (after.length > before.length) {
          await tester.tap(find.byKey(HeaderAct.keyOf(trigger)).at(at), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
        }
      }
    }
    return ids;
  }

  /// Presses [id] where it is: in the row, or in the menu that holds it.
  Future<void> press(WidgetTester tester, String id) async {
    if (find.byKey(HeaderAct.keyOf(id)).evaluate().isEmpty) {
      for (final trigger in const ['overflow', 'you']) {
        final found = find.byKey(HeaderAct.keyOf(trigger));
        for (var at = 0; at < found.evaluate().length; at++) {
          await tester.tap(found.at(at), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
          if (find.byKey(HeaderAct.keyOf(id)).evaluate().isNotEmpty) break;
          await tester.tap(find.byKey(HeaderAct.keyOf(trigger)).at(at), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
        }
        if (find.byKey(HeaderAct.keyOf(id)).evaluate().isNotEmpty) break;
      }
    }
    await tester.ensureVisible(find.byKey(HeaderAct.keyOf(id)).last);
    await tester.pump();
    await tester.tap(find.byKey(HeaderAct.keyOf(id)).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  const noteTools = {'view', 'share', 'history', 'links', 'comment', 'bookmark', 'pin', 'archive', 'speak', 'more'};
  const way = {'home', 'sidebar', 'folders', 'back', 'forward', 'aside'};
  const yours = {'organizations', 'org:o1', 'bell', 'settings'};

  final others = [for (final version in HeaderToolbarVersion.values) if (version != HeaderToolbarVersion.today) version];

  group('every version', () {
    for (final version in HeaderToolbarVersion.values) {
      for (final window in windows) {
        for (final style in TopBarStyle.values) {
          barTest('${version.number} ${version.label}, ${style.label}, ${window.name}: a note and home draw inside the window', (tester) async {
            for (final note in [true, false]) {
              await pumpShell(tester, version: version, window: window, style: style, note: note);
              expect(tester.takeException(), isNull);
              // Home is always in the bar itself, never in a menu (Matt, 2026-10-28: "Also always show the home button
              // on the top bar"): today's ring, the Masthead's word or the Ledger's pinned tab; a version's own button.
              final home = version == HeaderToolbarVersion.today
                  ? find.byWidgetPredicate((widget) => (widget is BarRing && widget.glyph == BarGlyph.house) || (widget is BarWord && widget.word == 'Home') || widget is HomeTab)
                  : find.byKey(HeaderAct.keyOf('home'));
              expect(home, findsOneWidget, reason: 'Home on ${note ? 'a note' : 'home'}');
              final at = tester.getRect(home);
              expect(at.left >= -0.5 && at.right <= window.size.width + 0.5 && at.top >= 0, isTrue, reason: 'Home at $at');
              expect(find.byType(PopMenu), findsNothing, reason: 'no menu open: Home is in the row');
              // The home page's Filters beside the title pill in Grouped command at home, and nowhere else (Matt,
              // 2026-10-29: "when on the homepage add it next to the command search bar in the top bar").
              final filters = find.byKey(HeaderAct.keyOf('filters'));
              expect(filters, version.searchPill && !note ? findsOneWidget : findsNothing, reason: 'Filters ${note ? 'on a note' : 'at home'}');
              if (filters.evaluate().isNotEmpty) {
                final rect = tester.getRect(filters);
                expect(rect.right <= window.size.width + 0.5 && (rect.width - rect.height).abs() < 0.5, isTrue, reason: 'Filters a circle in the window, $rect');
                expect(rect.left, greaterThan(tester.getRect(find.byKey(HeaderAct.keyOf('search'))).right), reason: 'after the title pill');
              }
              for (final element in headerKeys().evaluate()) {
                final box = element.renderObject;
                if (box is! RenderBox || !box.hasSize || !box.attached) continue;
                final rect = box.localToGlobal(Offset.zero) & box.size;
                expect(rect.left >= -0.5 && rect.right <= window.size.width + 0.5, isTrue, reason: '${element.widget.key} at $rect on a ${window.size.width} window');
              }
            }
          });
        }
      }
    }
  });

  // A Mac's window at a phone's width (it narrows to 360, macos/Runner/MainFlutterWindow.swift), its window buttons at
  // the bar's start: Grouped command's search pill was squeezed under its glass in the Islands and ran over, which with
  // Grouped command the default (Matt, 2026-10-29: "make the grouped command the default header layout") is what a
  // narrowed Mac draws. The two with a pill; the others' rows at this width are their own.
  const narrowMac = (name: 'mac-narrow', size: Size(390, 700), mobile: false, fine: true);
  for (final version in [for (final version in HeaderToolbarVersion.values) if (version.searchPill) version]) {
    for (final style in TopBarStyle.values) {
      barTest('${version.number} ${version.label}, ${style.label}, a Mac’s window at a phone’s width: a note and home draw inside it, the pill too', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          for (final note in [true, false]) {
            await pumpShell(tester, version: version, window: narrowMac, style: style, note: note);
            expect(tester.takeException(), isNull, reason: note ? 'a note' : 'home');
            final pill = tester.getRect(find.byKey(HeaderAct.keyOf('search')));
            expect(pill.left >= 0 && pill.right <= narrowMac.size.width, isTrue, reason: 'the pill at $pill');
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  group('every control in reach', () {
    for (final version in others) {
      for (final window in windows) {
        barTest('${version.number} ${version.label} on a note, ${window.name}', (tester) async {
          await pumpShell(tester, version: version, window: window);
          // A phone reading a note gives the bar no bell, Settings or organizations (the shell's `quietBar`).
          final wanted = {...way, ...noteTools, if (!window.mobile) ...yours};
          final got = await reachable(tester);
          expect(got.containsAll(wanted), isTrue, reason: 'missing ${wanted.difference(got)}');
        });

        barTest('${version.number} ${version.label} at home, ${window.name}', (tester) async {
          await pumpShell(tester, version: version, window: window, note: false);
          final wanted = {...way, ...yours};
          final got = await reachable(tester);
          expect(got.containsAll(wanted), isTrue, reason: 'missing ${wanted.difference(got)}');
          expect(got.intersection(noteTools), isEmpty, reason: 'no note is up');
        });
      }
    }

    barTest('1 Today’s bar keeps its rings and their labels', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, version: HeaderToolbarVersion.today, window: mac);
      expect(headerKeys(), findsNothing);
      for (final label in ['Home', 'All your notes', 'More: all notes by folder, a new note', 'Back to where you were', 'Forward again', 'Organizations', 'Notifications, something new', 'Settings', 'Side panel', 'More for this note', 'Showing the formatted note. Show the marks.']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      semantics.dispose();
    });

    for (final version in others) {
      barTest('${version.number} ${version.label}: a press does what the control does, in the row or its menu', (tester) async {
        final log = <String>[];
        await pumpShell(tester, version: version, window: mac, log: log);
        await press(tester, 'view');
        await press(tester, 'history');
        await press(tester, 'speak');
        await press(tester, 'settings');
        await press(tester, 'more');
        expect(log, ['switch', 'history', 'speak', 'settings', 'more']);
      });

      barTest('${version.number} ${version.label}: the labels a screen reader hears are today’s', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpShell(tester, version: version, window: mac);
        final got = await reachable(tester);
        expect(got, contains('back'));
        expect(find.bySemanticsLabel('Back to where you were'), findsWidgets);
        semantics.dispose();
      });
    }
  });

  // Matt, 2026-10-28, after the contact sheet on 2.3.61: "Make a version that combines the command center and grouped
  // sections".
  group('6 Grouped command', () {
    const version = HeaderToolbarVersion.groupedCommand;

    barTest('on the Mac: all four ways around, the title pill, the view and the two most used, ••• and you', (tester) async {
      final log = <String>[];
      await pumpShell(tester, version: version, window: mac, log: log);
      final row = drawn(tester);
      expect(row.containsAll({'home', 'sidebar', 'back', 'forward', 'search', 'view', 'share', 'history', 'overflow', 'you'}), isTrue, reason: '$row');
      // The rest of the note's, and the aside, are one press away.
      expect(row.intersection({'links', 'comment', 'bookmark', 'pin', 'archive', 'speak', 'more', 'aside', 'bell', 'settings'}), isEmpty, reason: '$row');
      // The pill is the note's name, and opens the palette.
      expect(find.text('Groceries').evaluate().length, greaterThan(1));
      await tester.tap(find.byKey(HeaderAct.keyOf('search')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['search']);
    });

    for (final window in [folded, unfolded]) {
      barTest('on the Fold ${window.name}, at home and on a note', (tester) async {
        await pumpShell(tester, version: version, window: window);
        final wide = window.size.width >= 600;
        final row = drawn(tester);
        expect(row.containsAll({'sidebar', 'back', 'search', 'view', 'overflow'}), isTrue, reason: '$row');
        if (!wide) {
          // Narrow: Home and the sidebar, then Back; the view and •••; Forward and every action one press away.
          expect(row, contains('home'));
          expect(row.intersection({'forward', 'share', 'history'}), isEmpty, reason: '$row');
        }
        final reached = await reachable(tester);
        expect(reached.containsAll({...way, ...noteTools}), isTrue, reason: 'missing ${{...way, ...noteTools}.difference(reached)}');

        await pumpShell(tester, version: version, window: window, note: false);
        final home = drawn(tester);
        expect(home.containsAll({'home', 'sidebar', 'search', 'filters', 'you'}), isTrue, reason: '$home');
        // At home on a narrow window Back is put away for the Filters' circle; Home and Filters never are.
        expect(home.contains('back'), wide, reason: '$home');
        expect((await reachable(tester)).contains('back'), isTrue);
        // At home, ••• is a pill of its own for what the way around put away, and the aside.
        expect(home, contains('overflow'));
        expect(home.intersection(noteTools), isEmpty);
      });
    }

    // Matt, 2026-10-30: "The colors for the dropdown more menu are missing on general deployments though I see the
    // colored icons on my end": he was on Command centre, whose ••• wears each row's hue; the default's was grey.
    barTest('its ••• wears each row’s hue, as Command centre’s does, never the muted grey', (tester) async {
      await pumpShell(tester, version: version, window: folded);
      await tester.tap(find.byKey(HeaderAct.keyOf('overflow')));
      await tester.pump(const Duration(milliseconds: 300));
      final t = GlacierTheme.of(tester.element(find.byKey(HeaderAct.keyOf('overflow'))));
      final glyphs = tester.widgetList<HeaderGlyph>(find.byType(HeaderGlyph)).where((glyph) => glyph.size == 16).toList();
      expect(glyphs, isNotEmpty);
      for (final glyph in glyphs) {
        expect(glyph.color, isNot(t.color('glacier-text-muted')), reason: glyph.act.id);
      }
      expect({for (final glyph in glyphs) glyph.color}.length, greaterThan(1), reason: 'more than one hue');
    });

    barTest('Developer’s choice switches the bar to it', (tester) async {
      // From today's bar, the one choice that draws none of these (chosen once the app is up: a launch reads the
      // device's word, nothing, the default).
      await pumpShell(tester, window: unfolded);
      headerToolbarChoice.set(HeaderToolbarVersion.today.id);
      await tester.pump(const Duration(milliseconds: 100));
      expect(headerKeys(), findsNothing);
      headerToolbarChoice.set(version.id);
      await tester.pump(const Duration(milliseconds: 100));
      expect(headerToolbarVersion, version);
      expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget);
      expect(find.byKey(HeaderAct.keyOf('view')), findsOneWidget);
    });
  });

  // Matt, 2026-10-28: "the grouped ones need a bit of space between the home sidebar and navigation buttons also make
  // the buttons circular instead of pill shaped for each item like the home item shows as a pill even though it's a
  // single icon".
  for (final version in [HeaderToolbarVersion.grouped, HeaderToolbarVersion.groupedCommand]) {
    for (final window in windows) {
      barTest('${version.number} ${version.label}, ${window.name}: every button a circle, and a gap between where you are and where you have been', (tester) async {
        for (final note in [true, false]) {
          await pumpShell(tester, version: version, window: window, note: note);
          Rect rectOf(String id) => tester.getRect(find.byKey(HeaderAct.keyOf(id)).first);
          final row = drawn(tester);
          for (final id in row.where((id) => id != 'search')) {
            final rect = rectOf(id);
            expect((rect.width - rect.height).abs(), lessThan(0.5), reason: '$id is $rect, not a circle');
          }
          if (row.contains('sidebar') && row.contains('back')) {
            final apart = rectOf('back').left - rectOf('sidebar').right;
            expect(apart, greaterThanOrEqualTo(8), reason: 'the two pills $apart apart');
          }
        }
      });
    }
  }

  // Matt, 2026-10-29: "make the header icons and searchbar just a touch smaller to match the size of the buttons in the
  // dock when smaller" (after 2026-10-28's "a size larger"): Grouped command's rings, glyphs and title pill are the
  // home page's dock's at the scale it shrinks to while the page scrolls.
  for (final window in windows) {
    barTest('6 Grouped command is the dock’s size when it is smaller, a step up on a phone, ${window.name}', (tester) async {
      await pumpShell(tester, version: HeaderToolbarVersion.groupedCommand, window: window, note: false);
      final t = GlacierTheme.of(tester.element(find.byType(AppTabBar)));
      // On a phone a small step larger (Matt, 2026-10-29: "Make the header icons and search bar slightly larger on
      // mobile"): 2.5px on the rings, 1.5 on the glyphs.
      final phone = window.size.width < 600;
      final ring = t.len('app-ring') * dockScrolledScale + (phone ? 2.5 : 0);
      // The circles that stand alone are the ring across: you, Filters, ••• at home; the title pill is the ring high.
      for (final id in ['you', 'filters', 'search']) {
        final rect = tester.getRect(find.byKey(HeaderAct.keyOf(id)));
        expect((rect.height - ring).abs(), lessThan(1), reason: '$id is ${rect.height}, the dock smaller is $ring');
      }
      double glyphIn(String id) => tester.widget<HeaderGlyph>(find.descendant(of: find.byKey(HeaderAct.keyOf(id)), matching: find.byType(HeaderGlyph)).first).size;
      final glyph = t.lenOf('1.15rem') * dockScrolledScale + (phone ? 1.5 : 0);
      for (final id in ['home', 'sidebar', 'you']) {
        expect((glyphIn(id) - glyph).abs(), lessThan(0.01), reason: id);
      }
      // A touch smaller than it was (34-42px), and its title's words the small size, as Command centre's are (Matt,
      // 2026-10-29: "the text in the top searchbar is a bit too large").
      expect(ring, lessThan(t.lenOf('calc(var(--glacier-space-10) * 0.85)')));
      double words() {
        final found = find.descendant(of: find.byKey(HeaderAct.keyOf('search')), matching: find.byType(RichText));
        return tester.widget<RichText>(found.first).text.style?.fontSize ?? 0;
      }

      final large = words();
      // The words a size up on a phone, md, and the small size elsewhere, sm.
      expect(large, t.fontSize(phone ? 'md' : 'sm'));
      await pumpShell(tester, version: HeaderToolbarVersion.command, window: window, note: false);
      expect(large, words());
    });

    // Command centre's bar on a phone the same small step larger, its rings with Grouped command's there; elsewhere as
    // it was.
    barTest('4 Command centre a step up on a phone and as it was elsewhere, ${window.name}', (tester) async {
      await pumpShell(tester, version: HeaderToolbarVersion.command, window: window, note: false);
      final t = GlacierTheme.of(tester.element(find.byType(AppTabBar)));
      final phone = window.size.width < 600;
      final ring = phone ? t.len('app-ring') * dockScrolledScale + 2.5 : t.lenOf('calc(var(--glacier-space-10) * 0.68)');
      for (final id in ['home', 'filters', 'search', 'overflow']) {
        final rect = tester.getRect(find.byKey(HeaderAct.keyOf(id)).first);
        expect((rect.height - ring).abs(), lessThan(1), reason: '$id is ${rect.height}, wanted $ring');
      }
      if (phone) expect(ring, greaterThan(t.lenOf('calc(var(--glacier-space-10) * 0.68)') + 2));
      double glyphIn(String id) => tester.widget<HeaderGlyph>(find.descendant(of: find.byKey(HeaderAct.keyOf(id)), matching: find.byType(HeaderGlyph)).first).size;
      expect(glyphIn('home'), 19 + (phone ? 1.5 : 0));
      // Home and Filters always in the row (a new note is under ••• now); the pill a word on a phone.
      expect(find.descendant(of: find.byKey(HeaderAct.keyOf('search')), matching: find.text(phone ? 'Search' : 'Search or run a command')), findsOneWidget);
    });
  }

  // Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as the + button in the header". Every
  // note by folder (2026-10-29: "add a folder icon to the top near home and sidebar") and a new note are the first two
  // rows of the bar's •••, on a note and at home, in every version; today's bar, which had no ••• of its own, has one
  // after the sidebar's icon. Neither is in the row, and the tabs have no + after them.
  for (final version in HeaderToolbarVersion.values) {
    for (final window in windows) {
      for (final note in [true, false]) {
        barTest('${version.number} ${version.label}, ${window.name}, ${note ? 'a note' : 'home'}: every note by folder and a new note are under •••, first, and do what they say', (tester) async {
          final semantics = tester.ensureSemantics();
          final said = <String>[];
          final app = await pumpShell(tester, version: version, window: window, note: note, log: said);
          expect(find.byKey(HeaderAct.keyOf('folders')), findsNothing, reason: 'not in the row');
          expect(find.byKey(HeaderAct.keyOf('new')), findsNothing, reason: 'not in the row');
          expect(find.bySemanticsLabel('All notes, by folder'), findsNothing);
          expect(find.bySemanticsLabel('New note'), findsNothing, reason: 'no + after the tabs');
          Future<void> open() async {
            if (version == HeaderToolbarVersion.today) {
              await tester.tap(find.bySemanticsLabel('More: all notes by folder, a new note'));
              await tester.pump(const Duration(milliseconds: 400));
            } else {
              final before = drawn(tester);
              // The bar's ••• (the note's pill's, or at home a circle of its own), or the menu that version has for it.
              for (final trigger in const ['overflow', 'search']) {
                final found = find.byKey(HeaderAct.keyOf(trigger));
                if (found.evaluate().isEmpty) continue;
                await tester.tap(found.last, warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 400));
                if (find.byKey(HeaderAct.keyOf('folders')).evaluate().isNotEmpty) break;
                if (drawn(tester).length > before.length) {
                  await tester.tap(found.last, warnIfMissed: false);
                  await tester.pump(const Duration(milliseconds: 400));
                }
              }
            }
          }

          final before = drawn(tester);
          await open();
          expect(find.byKey(HeaderAct.keyOf('folders')), findsOneWidget, reason: 'under •••');
          expect(find.byKey(HeaderAct.keyOf('new')), findsOneWidget, reason: 'under •••');
          // The first two rows: every note by folder, then a new note, then the rest.
          final folders = tester.getRect(find.byKey(HeaderAct.keyOf('folders')));
          final make = tester.getRect(find.byKey(HeaderAct.keyOf('new')));
          expect(folders.top, lessThan(make.top));
          for (final id in drawn(tester).difference(before).difference({'folders', 'new'})) {
            expect(tester.getRect(find.byKey(HeaderAct.keyOf(id)).last).top, greaterThan(make.top), reason: '$id after them');
          }
          await tester.tap(find.byKey(HeaderAct.keyOf('new')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(said, contains('new'));
          await open();
          await tester.tap(find.byKey(HeaderAct.keyOf('folders')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(app.screen, const ScreenNotes(icons: true));
          semantics.dispose();
        });
      }
    }
  }

  barTest('Developer’s choice switches the bar at once, nothing restarted', (tester) async {
    final app = await pumpShell(tester, window: unfolded);
    // Nothing chosen is Grouped command (Matt, 2026-10-29: "make the grouped command the default header layout").
    expect(headerToolbarVersion, HeaderToolbarVersion.groupedCommand);
    expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget);
    headerToolbarChoice.set(HeaderToolbarVersion.today.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(headerKeys(), findsNothing);
    final note = tester.state(find.byType(_StandInNote));
    for (final version in others) {
      headerToolbarChoice.set(version.id);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(HeaderAct.keyOf('view')), findsOneWidget, reason: version.label);
      // The same note's screen, the same shell: the bar alone was drawn again.
      expect(tester.state(find.byType(_StandInNote)), same(note));
      expect(tester.state<AppShellState>(find.byType(AppShell)), same(app));
    }
    headerToolbarChoice.set(HeaderToolbarVersion.today.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(headerKeys(), findsNothing);
    // And back to the default, as nothing chosen.
    headerToolbarChoice.set(HeaderToolbarVersion.fallback.id);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(HeaderAct.keyOf('search')), findsOneWidget);
    expect(tester.state<AppShellState>(find.byType(AppShell)), same(app));
  });

  test('a version is kept by its word, and a word this build does not know is the default, Grouped command', () {
    for (final version in HeaderToolbarVersion.values) {
      expect(HeaderToolbarVersion.parse(version.id), version);
    }
    expect(HeaderToolbarVersion.fallback, HeaderToolbarVersion.groupedCommand);
    expect(HeaderToolbarVersion.parse('strip'), HeaderToolbarVersion.groupedCommand);
    expect(HeaderToolbarVersion.parse(null), HeaderToolbarVersion.groupedCommand);
    headerToolbarChoice.set('nonsense');
    expect(headerToolbarChoice.value, 'groupedCommand');
    expect(headerToolbarVersion, HeaderToolbarVersion.groupedCommand);
    // Today's bar is still a choice, and Matt's numbers stand; Developer lists the default first.
    headerToolbarChoice.set('today');
    expect(headerToolbarVersion, HeaderToolbarVersion.today);
    expect([for (final version in HeaderToolbarVersion.values) version.number], [1, 2, 3, 4, 5, 6]);
    expect(HeaderToolbarVersion.offered, [HeaderToolbarVersion.groupedCommand, HeaderToolbarVersion.today, HeaderToolbarVersion.grouped, HeaderToolbarVersion.tiles, HeaderToolbarVersion.command, HeaderToolbarVersion.labelled]);
  });

  // ---- the pictures --------------------------------------------------------------------------------------------

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = '../../build/feature-shots/header-toolbar';
  for (final version in HeaderToolbarVersion.values) {
    for (final window in windows) {
      for (final theme in ['light', 'dark']) {
        barTest('a picture: ${version.number} ${version.label} on a note and at home, ${window.name}, $theme', (tester) async {
          // The Mac's window buttons are drawn where the bar begins: the app's own word for a Mac.
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            for (final note in [true, false]) {
              await pumpShell(tester, version: version, window: window, theme: theme, note: note);
              await tester.pump(const Duration(milliseconds: 600));
              await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/${version.number}-${version.id}-${note ? 'note' : 'home'}-${window.name}-$theme.png'));
            }
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        }, skip: !shots);
      }
    }
  }

  // One picture for Matt: the six on a note on the opened Fold, the bar and the page's head of each, one under
  // another with its number and name. Made from the pictures above, so it runs after them.
  for (final theme in ['light', 'dark']) {
    barTest('a picture: the contact sheet of the six on a note, unfolded, $theme', (tester) async {
      await tester.runAsync(() async {
        const ratio = 2.0, keep = 230.0, band = 44.0, width = 880.0;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final count = HeaderToolbarVersion.values.length;
        final height = count * (keep + band) * ratio;
        final paper = theme == 'light' ? const Color(0xFFF6F4EF) : const Color(0xFF151413);
        final ink = theme == 'light' ? const Color(0xFF1B1A18) : const Color(0xFFEDEAE4);
        canvas.drawRect(Rect.fromLTWH(0, 0, width * ratio, height), Paint()..color = paper);
        for (final version in HeaderToolbarVersion.values) {
          final file = File('build/feature-shots/header-toolbar/${version.number}-${version.id}-note-unfolded-$theme.png');
          final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
          final image = (await codec.getNextFrame()).image;
          final top = version.index * (keep + band) * ratio;
          final words = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Inter Variable', fontSize: 15 * ratio, fontWeight: FontWeight.w600))
            ..pushStyle(ui.TextStyle(color: ink))
            ..addText('${version.number}  ${version.label}');
          final paragraph = words.build()..layout(const ui.ParagraphConstraints(width: width * ratio));
          canvas.drawParagraph(paragraph, Offset(16 * ratio, top + (band * ratio - paragraph.height) / 2));
          canvas.drawImageRect(image, Rect.fromLTWH(0, 0, width * ratio, keep * ratio), Rect.fromLTWH(0, top + band * ratio, width * ratio, keep * ratio), Paint());
          canvas.drawRect(Rect.fromLTWH(0, top + (band + keep) * ratio - 2, width * ratio, 2), Paint()..color = ink.withValues(alpha: 0.18));
        }
        final sheet = await recorder.endRecording().toImage((width * ratio).round(), height.round());
        final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
        File('build/feature-shots/header-toolbar/contact-sheet${theme == 'light' ? '' : '-dark'}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }, skip: !shots);
  }
}

/// What a note's screen hands the bar (lib/note/note_screen.dart `TopBarFill`): its tools drawn from a model, its
/// More as the tail, and the model, with every spare action a note can have.
class _StandInNote extends StatefulWidget {
  const _StandInNote({required this.note, required this.log});
  final Note note;
  final ValueChanged<String> log;

  @override
  State<_StandInNote> createState() => _StandInNoteState();
}

class _StandInNoteState extends State<_StandInNote> {
  late final ValueNotifier<NoteToolsModel> _model = ValueNotifier(_made(page: true));
  late final Widget _tools = NoteTools(model: _model);
  late final Widget _more = NoteMore(onMore: () => widget.log('more'));

  NoteToolsModel _made({required bool page}) => NoteToolsModel(
        kind: NoteKind.words,
        page: page,
        switchable: true,
        onSwitch: () {
          widget.log('switch');
          _model.value = _made(page: !_model.value.page);
        },
        onMore: () => widget.log('more'),
        more: false,
        actions: [
          ToolAction(id: 'share', label: 'Share', icon: Lucide.share2, onPress: () => widget.log('share')),
          ToolAction(id: 'history', label: 'Version history', icon: Lucide.history, onPress: () => widget.log('history')),
          ToolAction(id: 'links', label: 'Linked from 3 notes', icon: Lucide.link2, count: 3, onPress: () => widget.log('links')),
          ToolAction(id: 'comment', label: 'Comment', icon: Lucide.messageSquarePlus, onPress: () => widget.log('comment')),
          ToolAction(id: 'bookmark', label: 'Bookmark this line', icon: Lucide.bookmark, on: false, onPress: () => widget.log('bookmark')),
          ToolAction(id: 'pin', label: 'Pin to the top', icon: Lucide.pin, on: false, onPress: () => widget.log('pin')),
          ToolAction(id: 'archive', label: 'Archive', icon: Lucide.archive, onPress: () => widget.log('archive')),
          ToolAction(id: 'speak', label: 'Talk into this note', icon: Lucide.mic, onPress: () => widget.log('speak')),
        ],
      );

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TopBarFill(tools: _tools, tail: _more, model: _model, child: NotePlaceholder(note: widget.note));
}
