import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/launch/eyes.dart';
import 'package:ghost_md/launch/launch_screen.dart';

import '../support/render.dart';

/// `launch/LaunchScreen.test.tsx`, case for case, on the phone's clock: where jsdom had no geometry and so a ghost
/// that never moved, this one looks out and winks (eyes.dart `lookOutMs` + `winkMs`) before the screen fades.
void main() {
  setUpAll(loadAppFonts);

  const still = Duration(milliseconds: lookOutMs + winkMs);

  LaunchUpdates updates({bool checking = false, String? readyBuild, String? apkVersion, String? lastError, VoidCallback? check, VoidCallback? reload}) =>
      LaunchUpdates(checking: checking, readyBuild: readyBuild, apkVersion: apkVersion, lastError: lastError, check: check ?? () {}, reload: reload ?? () {});

  Future<void> show(WidgetTester tester, Widget screen) => pumpApp(tester, home: screen);

  /// The screen again with new answers, as the app would give them.
  Future<void> again(WidgetTester tester, Widget screen) async {
    await pumpApp(tester, home: screen);
  }

  /// A claim that is given once for a build, as `claimAutoReload` keeps it.
  bool Function(String) once() {
    final taken = <String>{};
    return taken.add;
  }

  Future<void> wait(WidgetTester tester, int ms) async {
    // In frames, as a phone would draw them: the chase runs off a ticker.
    for (var left = ms; left > 0; left -= 50) {
      await tester.pump(Duration(milliseconds: left < 50 ? left : 50));
    }
  }

  Future<void> away(WidgetTester tester) async {
    // pumpApp turned the shadows on for a picture; the binding wants its own switch back as a test ends.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the screen opening shows', () {
    testWidgets('says what it is doing, ticks each step off, asks for the update check at once, and hands over when done', (tester) async {
      var asked = 0;
      var done = 0;
      await show(tester, LaunchScreen(loading: true, notes: 0, updates: updates(check: () => asked += 1), onDone: () => done += 1));
      expect(asked, 1);
      expect(find.text('Opening your notes'), findsOneWidget);
      // The check starts, then answers; the notes are read.
      await again(tester, LaunchScreen(loading: false, notes: 12, updates: updates(checking: true), sync: SyncPhase.syncing, onDone: () => done += 1));
      expect(find.text('12 notes'), findsOneWidget);
      expect(find.text('Checking for updates'), findsOneWidget);
      expect(find.text('Syncing your devices'), findsOneWidget);
      await again(tester, LaunchScreen(loading: false, notes: 12, updates: updates(), sync: SyncPhase.idle, onDone: () => done += 1));
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.text('In sync'), findsOneWidget);
      await wait(tester, 1000);
      // Ready: the ghost looks out and winks first, then the fade.
      expect(done, 0);
      await wait(tester, still.inMilliseconds);
      expect(done, 0);
      await wait(tester, 300);
      expect(done, 1);
      await away(tester);
    });

    testWidgets('stops holding the door for an update check that never answers, three seconds on', (tester) async {
      var done = 0;
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(checking: true), onDone: () => done += 1));
      await wait(tester, 2900);
      expect(find.text('Checking for updates'), findsOneWidget);
      await wait(tester, 100 + still.inMilliseconds - 100);
      expect(done, 0);
      await wait(tester, 100 + 300);
      expect(done, 1);
      await away(tester);
    });

    testWidgets('takes an update found while it is up: says so, reloads, and does not hand over meanwhile', (tester) async {
      var done = 0;
      var reloads = 0;
      final claim = once();
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(checking: true, reload: () => reloads += 1), claimAutoReload: claim, onDone: () => done += 1));
      await again(tester, LaunchScreen(loading: false, notes: 2, updates: updates(readyBuild: '20261007020000', reload: () => reloads += 1), claimAutoReload: claim, onDone: () => done += 1));
      expect(find.text('Updating Ghost.md'), findsOneWidget);
      expect(reloads, 0);
      await wait(tester, 500);
      expect(reloads, 1);
      await wait(tester, 4000);
      expect(done, 0);
      await away(tester);
    });

    testWidgets('takes a build once: back on the old page with the same build still waiting, it opens as it used to', (tester) async {
      var reloads = 0;
      final claim = once();
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(readyBuild: '20261007020000', reload: () => reloads += 1), claimAutoReload: claim, onDone: () {}));
      await wait(tester, 500);
      expect(reloads, 1);
      await away(tester);
      // The launch after the reload, where the new build did not come up.
      var done = 0;
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(checking: true, reload: () => reloads += 1), claimAutoReload: claim, onDone: () => done += 1));
      await again(tester, LaunchScreen(loading: false, notes: 2, updates: updates(readyBuild: '20261007020000', reload: () => reloads += 1), claimAutoReload: claim, onDone: () => done += 1));
      expect(find.text('An update is ready for next time'), findsOneWidget);
      await wait(tester, 1000 + still.inMilliseconds + 300);
      expect(reloads, 1);
      expect(done, 1);
      await away(tester);
    });

    testWidgets('leaves an update for later when the app was opened to record, or while a recording runs', (tester) async {
      var reloads = 0;
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(readyBuild: '20261007020000', reload: () => reloads += 1), claimAutoReload: once(), holdUpdate: true, onDone: () {}));
      await wait(tester, 1000);
      expect(reloads, 0);
      await away(tester);
      await show(tester, LaunchScreen(loading: false, notes: 2, updates: updates(readyBuild: '20261007020000', reload: () => reloads += 1), claimAutoReload: once(), recording: () => true, onDone: () {}));
      await wait(tester, 1000);
      expect(reloads, 0);
      await away(tester);
    });

    testWidgets('shows no update line where no check runs, and doesn’t wait for one', (tester) async {
      var done = 0;
      await show(tester, LaunchScreen(loading: false, notes: 3, updates: updates(), onDone: () => done += 1));
      expect(find.text('Checking for updates'), findsOneWidget);
      await wait(tester, 600);
      expect(find.text('Checking for updates'), findsNothing);
      expect(find.text('3 notes'), findsOneWidget);
      await wait(tester, 400 + still.inMilliseconds + 300);
      expect(done, 1);
      await away(tester);
    });

    testWidgets('says what the check found', (tester) async {
      await show(tester, LaunchScreen(loading: false, notes: 1, updates: updates(checking: true), onDone: () {}));
      expect(find.text('1 note'), findsOneWidget);
      await again(tester, LaunchScreen(loading: false, notes: 1, updates: updates(apkVersion: '1.16.0'), sync: SyncPhase.error, onDone: () {}));
      expect(find.text('Ghost.md 1.16.0 is out'), findsOneWidget);
      expect(find.text('Sync will try again'), findsOneWidget);
      await again(tester, LaunchScreen(loading: false, notes: 1, updates: updates(lastError: 'offline'), onDone: () {}));
      expect(find.text('Couldn’t check for updates'), findsOneWidget);
      await away(tester);
    });
  });

  group('where it sits', () {
    // What the web app's page measured at 390 x 844 (Chromium, getBoundingClientRect, 2026-10-07) with one line up:
    // svg 131, 280.28, 128 x 128; h1 133.45, 430.59, 123.09 x 34 (28.08px, bold, -0.702px); ul 160.31, 491.38,
    // 69.36 x 72.33 (13.39px); the mark 160.31, 520.53, 14.72 x 14 with its 14 px icon at 160.67.
    testWidgets('is the web page\'s, to the half pixel', (tester) async {
      await show(tester, LaunchScreen(loading: false, notes: 0, onDone: () {}));
      await wait(tester, 600);
      void near(Rect got, List<double> want, {double by = 0.5}) {
        expect(got.left, closeTo(want[0], by), reason: '$got left');
        expect(got.top, closeTo(want[1], by), reason: '$got top');
        expect(got.width, closeTo(want[2], by), reason: '$got width');
        expect(got.height, closeTo(want[3], by), reason: '$got height');
      }

      near(tester.getRect(find.byKey(const ValueKey('launch-chase'))), [131, 280.28, 128, 128]);
      near(tester.getRect(find.text('Ghost.md')), [133.45, 430.59, 123.09, 34]);
      near(tester.getRect(find.byKey(const ValueKey('launch-lines'))), [160.31, 491.38, 69.36, 72.33]);
      near(tester.getRect(find.byKey(const ValueKey('launch-mark'))), [160.31, 520.53, 14.72, 14]);
      final mark = tester.getRect(find.descendant(of: find.byKey(const ValueKey('launch-mark')), matching: find.byType(CustomPaint)));
      near(mark, [160.67, 520.53, 14, 14]);
      await away(tester);
    });
  });

  group('the ghost on the screen', () {
    testWidgets('asked for less motion, there is no wink to wait for', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var done = 0;
      await show(tester, LaunchScreen(loading: false, notes: 3, updates: updates(), onDone: () => done += 1));
      await wait(tester, 900);
      expect(done, 0);
      await wait(tester, 50 + 300);
      expect(done, 1);
      await away(tester);
    });

    testWidgets('is announced as the app opening, and its drawing is not read out', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester, LaunchScreen(loading: true, notes: 0, onDone: () {}));
      expect(find.bySemanticsLabel('Opening Ghost.md'), findsOneWidget);
      handle.dispose();
      await away(tester);
    });

    for (final theme in ['light', 'dark']) {
      testWidgets('the picture, $theme', (tester) async {
        await tester.runAsync(() async {});
        await pumpApp(
          tester,
          prefs: AppPreferences(theme: theme),
          home: LaunchScreen(loading: false, notes: 128, updates: updates(checking: true), sync: SyncPhase.syncing, onDone: () {}),
        );
        // The picture is decoded off the test's clock.
        await tester.runAsync(() => precacheImage(const AssetImage('assets/launch/ghost-icon-eyeless.webp'), tester.element(find.byType(LaunchScreen))));
        await tester.pump();
        await shot(tester, 'launch-$theme', settle: const Duration(milliseconds: 700));
      });
    }
  });
}
