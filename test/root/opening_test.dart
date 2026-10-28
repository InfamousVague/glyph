// The app from its first frame (lib/root/opening.dart): the launch screen at once, over nothing, while the
// library's core opens, and the root under it the moment it has. One launch screen, begun once: what it waits for
// and how long it stays are lib/launch/launch_screen.dart's own, which test/launch holds; what is held here is that
// putting the root under it changes none of that.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/guide/guide.dart' show Guide;
import 'package:ghost_md/guide/guide_state.dart' show GuideController;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/launch/launch_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/opening.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Widget root(SampleLibrary library, {LaunchSeat? seat, VoidCallback? restart, bool launch = true, GuideController? guide}) => GhostRoot(
        launch: launch,
        guide: guide,
        launchSeat: seat,
        restart: restart,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
      );

  /// In frames, as a phone draws them: the ghost's chase runs off a ticker. Answers how long the launch screen stayed.
  Future<int> untilGone(WidgetTester tester, {int most = 4000}) async {
    var waited = 0;
    while (waited < most && find.byType(LaunchScreen).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 20));
      waited += 20;
    }
    return waited;
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the launch screen is up from the first frame, over nothing, and is the same screen once the root is under it', (tester) async {
    final opened = Completer<SampleLibrary>();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<SampleLibrary>(opened: opened.future, builder: (context, library, seat, restart) => root(library, seat: seat, restart: restart)),
    );
    // Nothing has opened: the screen says what it is waiting for, and there is no app under it yet.
    expect(find.byType(LaunchScreen), findsOneWidget);
    expect(find.text('Opening your notes'), findsOneWidget);
    expect(find.byType(GhostRoot), findsNothing);
    final screen = tester.state(find.byType(LaunchScreen));
    await tester.pump(const Duration(milliseconds: 300));
    // The core has opened: the root is made under the screen that was there, which says the notes it now has.
    final library = SampleLibrary.seeded();
    opened.complete(library);
    await tester.pump();
    await tester.pump();
    expect(find.byType(GhostRoot), findsOneWidget);
    expect(find.byType(LaunchScreen), findsOneWidget, reason: 'the root draws none of its own');
    expect(tester.state(find.byType(LaunchScreen)), same(screen), reason: 'one screen, begun once');
    expect(find.text('${library.value.length} notes'), findsOneWidget);
    expect(find.text('Opening your notes'), findsNothing);
    // And it hands over as it always has, to the home page.
    await untilGone(tester);
    expect(find.byType(LaunchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await away(tester);
  });

  testWidgets('the walkthrough, and its voice, wait under the launch screen and come once it has gone', (tester) async {
    final guide = GuideController()..show(0);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<SampleLibrary>(opened: Future.value(SampleLibrary.seeded()), builder: (context, library, seat, restart) => root(library, seat: seat, restart: restart, guide: guide)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(GhostRoot), findsOneWidget);
    expect(find.byType(LaunchScreen), findsOneWidget);
    expect(find.byType(Guide), findsNothing, reason: 'nothing of the tour is made, nor said, under the launch screen');
    await untilGone(tester);
    await tester.pump();
    expect(find.byType(Guide), findsOneWidget);
    guide.dispose();
    await away(tester);
  });

  testWidgets('it stays exactly as long as a root\'s own launch screen does, though the core opened a third of a second into it', (tester) async {
    // The root with its own launch screen, as a test's and a gallery's has it and as the app's had.
    await pumpApp(tester, prefs: const Preferences(theme: 'light'), home: root(SampleLibrary.seeded()));
    final own = await untilGone(tester);
    await away(tester);
    // The screen up first and the root under it 300 ms on: the notes were being opened meanwhile, which is what
    // the screen's shortest stay is for.
    final opened = Completer<SampleLibrary>();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<SampleLibrary>(opened: opened.future, builder: (context, library, seat, restart) => root(library, seat: seat, restart: restart)),
    );
    var waited = 0;
    for (; waited < 300; waited += 20) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    opened.complete(SampleLibrary.seeded());
    waited += await untilGone(tester);
    expect(waited, own);
    await away(tester);
  });

  testWidgets('a core that takes longer than the screen\'s whole stay keeps it up, saying so, and it leaves once the notes are there', (tester) async {
    final opened = Completer<SampleLibrary>();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<SampleLibrary>(opened: opened.future, builder: (context, library, seat, restart) => root(library, seat: seat, restart: restart)),
    );
    for (var i = 0; i < 200; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(LaunchScreen), findsOneWidget);
    expect(find.text('Opening your notes'), findsOneWidget);
    opened.complete(SampleLibrary.seeded());
    await untilGone(tester);
    expect(find.byType(LaunchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await away(tester);
  });

  testWidgets('started over, the launch screen is up again for the root made anew', (tester) async {
    late VoidCallback again;
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<int>(
        opened: Future<int>.value(0),
        builder: (context, _, seat, restart) {
          again = restart;
          return root(SampleLibrary.seeded(), seat: seat, restart: restart);
        },
      ),
    );
    await untilGone(tester);
    final first = tester.state(find.byType(GhostRoot));
    expect(find.byType(LaunchScreen), findsNothing);
    again();
    await tester.pump();
    expect(find.byType(LaunchScreen), findsOneWidget);
    expect(tester.state(find.byType(GhostRoot)), isNot(same(first)));
    // The root that went does not take the seat from the one that came: the screen reads the new root's notes.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: find.byType(LaunchScreen), matching: find.textContaining(' notes')), findsOneWidget);
    await untilGone(tester);
    expect(find.byType(LaunchScreen), findsNothing);
    await away(tester);
  });
}
