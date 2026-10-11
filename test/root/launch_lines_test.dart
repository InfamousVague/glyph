// The launch screen's lines on a signed-in device, through the app's real opening (lib/root/opening.dart with the
// root under it, the account's real objects over the service in memory): each thing opening does has its line, in
// the page's order (launch/LaunchScreen.tsx: the notes, the update check where the build checks, the account's
// sync), each turns to its tick as it is done, and every tick stays until the screen goes.
//
// Matt, on his phone, twice (2026-10-09, 2026-10-11): "it only shows a check and the note count now". The sync's
// line is the engine's word, and the engine's first word came after the screen had gone: the launch pass starts
// once the core has opened, the root is made and the kept session read. A signed-in launch now says it is syncing
// from the moment it is, and ticks when the engine says the pass ended.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/launch/launch_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/opening.dart';

import '../account_ui/support.dart' show Device;
import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Finder line(String words) => find.descendant(of: find.byType(LaunchScreen), matching: find.text(words));

  /// The lines still turning: a line's mark turns while its step runs (lib/launch/launch_screen.dart `_Turn`).
  Finder turning() => find.descendant(of: find.byType(LaunchScreen), matching: find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Turn'));

  testWidgets('signed in, the screen says the notes and then the sync, each ticked as it is done, and both ticks stay until it goes', (tester) async {
    final device = (await tester.runAsync(() => Device.make()))!;
    final library = SampleLibrary.seeded();
    final count = library.value.where((note) => (note.archivedAt ?? 0) == 0).length;
    final opened = Completer<SampleLibrary>();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<SampleLibrary>(
        opened: opened.future,
        builder: (context, notes, seat, restart) => GhostRoot(launchSeat: seat, restart: restart, library: notes, workspaces: device.workspaces, services: device.services, clock: () => seedNow),
      ),
    );
    // Before the core has opened: the notes are being opened, and nothing else is known yet.
    expect(line('Opening your notes'), findsOneWidget);
    expect(line('Syncing your devices'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));

    // The root is under the screen: the notes are read and ticked, and the signed-in account is syncing.
    opened.complete(library);
    await tester.pump();
    await tester.pump();
    expect(line('$count notes'), findsOneWidget);
    expect(line('Syncing your devices'), findsOneWidget, reason: 'a signed-in launch says its sync from the moment it is one');
    expect(tester.getTopLeft(line('$count notes')).dy, lessThan(tester.getTopLeft(line('Syncing your devices')).dy), reason: 'in the page\'s order');
    expect(turning(), findsOneWidget, reason: 'the notes are ticked, the sync turns');

    // The screen waits for the sync's answer: well past its shortest stay it is still up, the ghost not yet
    // looking out, the line still turning.
    for (var i = 0; i < 75; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(LaunchScreen), findsOneWidget);
    expect(line('Syncing your devices'), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(find.descendant(of: find.byType(LaunchScreen), matching: find.byType(AnimatedOpacity)).first).opacity, 1);

    // The launch pass, for real, against the service: the engine says it is syncing, then that it is in sync.
    await tester.runAsync(() => device.engine!.syncNow());
    expect(device.engine!.status.value.phase, 'idle');
    await tester.pump();
    expect(line('In sync'), findsOneWidget);
    expect(line('Syncing your devices'), findsNothing);
    expect(turning(), findsNothing, reason: 'every line is ticked');

    // Both lines, ticked, at every frame until the screen has gone: the look and the wink (620 ms) and the fade
    // (260) begin only now, with the sync's tick on screen.
    var frames = 0;
    while (find.byType(LaunchScreen).evaluate().isNotEmpty && frames < 400) {
      expect(line('$count notes'), findsOneWidget);
      expect(line('In sync'), findsOneWidget);
      expect(turning(), findsNothing);
      await tester.pump(const Duration(milliseconds: 20));
      frames += 1;
    }
    expect(frames * 20, inInclusiveRange(860, 960), reason: 'the look, the wink and the fade, from the tick');
    expect(find.byType(LaunchScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a sync that never answers holds the screen three seconds and no longer', (tester) async {
    final device = (await tester.runAsync(() => Device.make()))!;
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<int>(
        opened: Future<int>.value(0),
        builder: (context, _, seat, restart) => GhostRoot(launchSeat: seat, restart: restart, library: SampleLibrary.seeded(), workspaces: device.workspaces, services: device.services, clock: () => seedNow),
      ),
    );
    var waited = 0;
    while (find.byType(LaunchScreen).evaluate().isNotEmpty && waited < 6000) {
      if (waited == 2900) expect(line('Syncing your devices'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      waited += 20;
    }
    // Three seconds, then the look, the wink and the fade.
    expect(waited, inInclusiveRange(3860, 3980));
    expect(find.byType(HomeScreen), findsOneWidget);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('signed out, or with nothing leaving the phone, there is no sync to say', (tester) async {
    final device = (await tester.runAsync(() => Device.make(signedIn: false)))!;
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostOpening<int>(
        opened: Future<int>.value(0),
        builder: (context, _, seat, restart) => GhostRoot(launchSeat: seat, restart: restart, library: SampleLibrary.seeded(), workspaces: device.workspaces, services: device.services, clock: () => seedNow),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(line('Syncing your devices'), findsNothing);
    expect(line('In sync'), findsNothing);
    for (var i = 0; i < 200 && find.byType(LaunchScreen).evaluate().isNotEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
