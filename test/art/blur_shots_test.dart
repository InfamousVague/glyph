import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Pictures of every place the wisp's smoke was drawn, now a gradient blur (Matt, 2026-10-24: "replace the smoke
/// effect with a gradient blur on all places that use the wisp smoke", then "remove the smoke on mac too so all
/// versions get blur"): the home page scrolled under its header with its foot and the dock's halo, a note scrolled
/// under its header with its page dock, and the art gallery with every box scrolled (a page under a header and one
/// under the status bar, a column, a board's lanes, the tab row's ends, the dock's halo, words arriving). On a
/// phone (390 by 844), the Fold opened out (884 by 1104) and a Mac (1280 by 800), light and dark. Written to
/// `build/feature-shots/phone-blur/<stage>-<place>-<size>-<theme>.png` to be looked at, not held as goldens;
/// `--dart-define=SHOTS=before` names the pictures of the tree before the change, which draws this file unchanged.
void main() {
  setUpAll(loadAppFonts);

  const stage = String.fromEnvironment('SHOTS', defaultValue: 'after');
  final now = DateTime(2026, 10, 24, 12).millisecondsSinceEpoch;

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> snap(WidgetTester tester, String name, {bool settled = true}) async {
    if (settled) await settle(tester, 4);
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/phone-blur/$stage-$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
    debugDefaultTargetPlatformOverride = null;
  }

  /// The app put together over the seeded library, on [platform], with what the edges are drawn with loaded first:
  /// the smoke's programs came on the machine's clock, not the test's.
  Future<void> open(WidgetTester tester, String theme, Size size, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.runAsync(() => WispKit.load(seeds: const [3, 5]));
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme),
      home: GhostRoot(
        launch: false,
        core: (command, [args = const <String, Object?>{}]) async => null,
        library: SampleLibrary.seeded(),
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => now,
      ),
    );
    await settle(tester);
  }

  /// The outermost vertical scroller under [of] that can scroll, put [by] px down, or half its way where that is less,
  /// so there is still more below for its foot.
  Future<void> scroll(WidgetTester tester, Finder of, double by) async {
    final scrollers = tester.stateList<ScrollableState>(find.descendant(of: of, matching: find.byType(Scrollable))).where((s) => s.position.axis == Axis.vertical && s.position.maxScrollExtent > 40).toList();
    scrollers.first.position.jumpTo(by < scrollers.first.position.maxScrollExtent / 2 ? by : scrollers.first.position.maxScrollExtent / 2);
    await tester.pump();
    await settle(tester, 3);
  }

  const sizes = <(String, Size, TargetPlatform)>[
    ('phone', Size(390, 844), TargetPlatform.android),
    ('fold', Size(884, 1104), TargetPlatform.android),
    ('mac', Size(1280, 800), TargetPlatform.macOS),
  ];

  for (final theme in ['light', 'dark']) {
    for (final (name, size, platform) in sizes) {
      testWidgets('the home page scrolled, on the $name, $theme', (tester) async {
        await open(tester, theme, size, platform);
        await scroll(tester, find.byType(AppShell), 240);
        await snap(tester, 'home-$name-$theme');
      });

      testWidgets('a note scrolled, on the $name, $theme', (tester) async {
        await open(tester, theme, size, platform);
        final library = tester.widget<GhostRoot>(find.byType(GhostRoot)).library!;
        tester.state<AppShellState>(find.byType(AppShell)).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
        await settle(tester);
        await scroll(tester, find.byType(NoteScreen), 220);
        await snap(tester, 'note-$name-$theme');
      });

      testWidgets('the art gallery, every box scrolled, on the $name, $theme', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.runAsync(() => WispKit.load(seeds: const [3, 5, 1, 8, 15, 22, 29, 36]));
        await pumpApp(tester, size: Size(size.width, 4200), prefs: Preferences(theme: theme), ratio: 1.5, home: const ArtGallery());
        await settle(tester);
        // Every box that scrolls, scrolled: the page's own is the first and stays where it is.
        for (final scroller in tester.stateList<ScrollableState>(find.byType(Scrollable)).skip(1)) {
          if (scroller.position.maxScrollExtent > 60) scroller.position.jumpTo(60);
        }
        await tester.pump();
        // The headline mid-arrival: its first letters set, the newest still coming in.
        await tester.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await snap(tester, 'gallery-$name-$theme', settled: false);
      });
    }
  }
}
