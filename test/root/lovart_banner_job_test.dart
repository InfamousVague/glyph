// Lovart's header images for the recent notes as the app's own job, the app put together (lib/root,
// lib/plugins/lovart/banner_run.dart; Matt, 2026-10-26: "Make the header generation async and a background task that
// runs while the app is generating the images"): the line on home with Stop while it runs, the toast as it ends, and a
// note open in its editor given its banner without losing what is being typed.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_chips.dart' show ActivityChips, ActivityChipsState;
import 'package:ghost_md/app/ghost_app.dart' show GhostApp;
import 'package:ghost_md/core/banner.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart' show HomeScreen;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart';

import '../plugins/github/support.dart' show useGround;
import '../plugins/lovart/banners_test.dart' show GatedClient;
import '../support/render.dart';

const String _words = 'We drove down on Friday, stayed in the old house by the river, walked the market on Saturday morning, '
    'ate far too much at the corner place, and came home on Sunday with a bag of oranges and a plan to go back in spring.';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late SampleLibrary library;
  late GatedClient gated;

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    useGround();
    await lovart.host.secrets.write(lovart.accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(lovart.secretKeySecret, 'sk-1');
    lovartPictureStore = MemoryPictureStore();
    gated = GatedClient();
    lovartClient = () => gated;
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
    lovartBannerRun.value = null;
    library = SampleLibrary.seeded();
    // The seeded notes count as given one, so the run is the notes a test makes.
    lovart.host.storage.set(lovart.bannersDoneKey, [for (final note in library.value) note.id]);
  });

  tearDown(() {
    gated.openAll();
    lovartPictureStore = null;
    lovartClient = () => LovartClient.kept();
    usePlugins(createRegistry(const []));
  });

  Future<void> pumpRoot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> leave(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the run is the root\'s: its line on home with Stop while it runs, the ring in the header, and nothing said of a run the person stopped', (tester) async {
    for (var i = 0; i < 6; i += 1) {
      library.create('# Trip $i\n\n$_words');
    }
    await pumpRoot(tester);
    expect(lovartBannerJob, isNotNull);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing);
    final running = lovartBannerJob!.start();
    await settle(tester, 2);
    expect(find.textContaining('Making header images · 0 of 6', findRichText: true), findsOneWidget);
    gated.openOne();
    await settle(tester, 2);
    expect(find.textContaining('Making header images · 1 of 6', findRichText: true), findsOneWidget);
    // On the app's record of running work: the ring in the header (docs/ACTIVITY.md).
    expect(find.byKey(const ValueKey('header:activity')), findsOneWidget);
    // Its Stop, on the line.
    await tester.tap(find.byKey(const ValueKey('job-notice-action')));
    gated.openAll();
    await running;
    await settle(tester, 3);
    expect(lovartBannerRun.value!.asked, isTrue);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing, reason: 'a run the person stopped leaves no line');
    // It was a toast; a Stop the person pressed is said by nothing now, and its chip is not drawn.
    expect(find.text('Header images stopped · 4 made · about 24 credits'), findsNothing);
    await leave(tester);
  });

  testWidgets('a run that ends says so by its chip, once for the whole run (docs/ACTIVITY.md, Results)', (tester) async {
    for (var i = 0; i < 3; i += 1) {
      library.create('# Trip $i\n\n$_words');
    }
    await pumpRoot(tester);
    gated.open = true;
    await lovartBannerJob!.start();
    await settle(tester, 3);
    expect(find.text('Header images made for 3 notes · about 18 credits'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-chips')), findsOneWidget);
    await leave(tester);
  });

  testWidgets('stopped for credits, the line says why until Hide', (tester) async {
    library.create('# Trip\n\n$_words');
    await pumpRoot(tester);
    gated
      ..open = true
      ..fails = const LovartFailure('Your Lovart credits have run out.');
    await lovartBannerJob!.start();
    await settle(tester, 3);
    expect(find.text('Header images stopped at 0 of 1: Your Lovart credits have run out.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('job-notice-action')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('job-notice')), findsNothing);
    await leave(tester);
  });

  testWidgets('a note open in its editor gets its banner as an edit there, and keeps what is typed before and while it is made', (tester) async {
    final note = library.create('# Trip\n\n$_words');
    await pumpRoot(tester);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote(note.id);
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    void type(String words) {
      final end = view.state.doc.length;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: words), userEvent: 'input.type'));
    }

    type('\n\nTyped before.');
    final running = lovartBannerJob!.start();
    await tester.pump();
    // Lovart at work; the person types on, and the save's debounce passes.
    type(' Typed while it was made.');
    await settle(tester, 6);
    expect(bannerOf(library.noteOf(note.id)!.body), isNull);
    gated.openAll();
    await running;
    await tester.pump();
    final body = screen.body;
    expect(bannerOf(body), isNotNull, reason: 'the banner landed in the open editor');
    expect(body, endsWith('$_words\n\nTyped before. Typed while it was made.'));
    expect(lovartBannerRun.value!.made, 1);
    // Typing goes on after it, and every word is saved: the editor's saving was never refused.
    type(' And after.');
    await settle(tester, 10);
    final kept = library.noteOf(note.id)!.body;
    expect(bannerOf(kept), bannerOf(body));
    expect(kept, endsWith('Typed before. Typed while it was made. And after.'));
    shell.backToList();
    await settle(tester, 10);
    expect(library.noteOf(note.id)!.body, kept);
    await leave(tester);
  });

  // The result chips never over the page's own controls (2026-10-29, on Grouped command becoming the default: "the
  // result chips must never cover a page's own controls"). The run stopped for credits gives both the home page's
  // line, with Hide, and a chip saying the same, hung under the header at the end; with no search field on the page
  // the line stands at its top, where the chip hung over its Hide. Now the chip stands under the line, in every
  // version of the bar, on a phone, the opened Fold and the Mac, and Hide takes the press.
  const windows = [(name: 'phone', size: Size(390, 844), mac: false), (name: 'unfolded', size: Size(880, 1000), mac: false), (name: 'mac', size: Size(1280, 800), mac: true)];
  for (final version in HeaderToolbarVersion.offered) {
    for (final window in windows) {
      testWidgets('${version.number} ${version.label}, ${window.name}: the chip stands clear of the line, and Hide takes the press', (tester) async {
        if (window.mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => headerToolbarChoice.set(HeaderToolbarVersion.fallback.id));
        library.create('# Trip\n\n$_words');
        await pumpRoot(tester, size: window.size);
        headerToolbarChoice.set(version.id);
        await settle(tester, 2);
        gated
          ..open = true
          ..fails = const LovartFailure('Your Lovart credits have run out.');
        await lovartBannerJob!.start();
        await settle(tester, 4);
        final chips = find.byKey(const ValueKey('activity-chips'));
        final line = find.byKey(const ValueKey('job-notice'));
        expect(chips, findsOneWidget, reason: 'the chip says it too');
        expect(line, findsOneWidget);
        // The line's words and its Hide, not the room the line leaves under itself.
        final chip = tester.getRect(chips), words = tester.getRect(find.descendant(of: line, matching: find.byType(RichText)).first);
        expect(chip.overlaps(words), isFalse, reason: 'the chip at $chip, the line at $words');
        expect(tester.getRect(find.byKey(const ValueKey('job-notice-action'))).overlaps(chip), isFalse);
        if (version == HeaderToolbarVersion.fallback && Platform.environment.containsKey('FEATURE_SHOTS')) {
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/header-default/chip-clear-of-job-notice-${window.name}.png'));
        }
        // A press on Hide is Hide's, not the chip's.
        final hit = tester.hitTestOnBinding(tester.getCenter(find.byKey(const ValueKey('job-notice-action'))));
        expect(hit.path.any((entry) => entry.target == tester.renderObject(find.byKey(const ValueKey('job-notice-action')))), isTrue, reason: 'Hide is under the finger');
        await tester.tap(find.byKey(const ValueKey('job-notice-action')));
        await settle(tester, 2);
        expect(line, findsNothing);
        // With the line gone the chip goes back up to where it hangs.
        if (chips.evaluate().isNotEmpty) expect(tester.state<ActivityChipsState>(find.byType(ActivityChips)).drop, 0);
        await leave(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('the chip goes back up as the line scrolls away under the header, and down again as it comes back', (tester) async {
    for (var i = 0; i < 8; i += 1) {
      library.create('# Trip $i\n\n$_words');
    }
    await pumpRoot(tester);
    gated
      ..open = true
      ..fails = const LovartFailure('Your Lovart credits have run out.');
    await lovartBannerJob!.start();
    await settle(tester, 4);
    final chips = tester.state<ActivityChipsState>(find.byType(ActivityChips));
    expect(chips.drop, greaterThan(0), reason: 'under the line');
    final page = find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable)).first;
    tester.state<ScrollableState>(page).position.jumpTo(400);
    await settle(tester, 2);
    expect(chips.drop, 0, reason: 'the line is gone under the header');
    tester.state<ScrollableState>(page).position.jumpTo(0);
    await settle(tester, 2);
    expect(chips.drop, greaterThan(0));
    expect(tester.getRect(find.byKey(const ValueKey('activity-chips'))).overlaps(tester.getRect(find.descendant(of: find.byKey(const ValueKey('job-notice')), matching: find.byType(RichText)).first)), isFalse);
    await leave(tester);
  });
}
