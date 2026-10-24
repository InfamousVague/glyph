// Settings › Appearance › Motion's "Blur at the edges" (the `wispEdge` preference, "Smoke at the edges" until the
// smoke gave way to a gradient blur: Matt, 2026-10-24, "replace the smoke effect with a gradient blur on all places
// that use the wisp smoke"), through the app put together: the art's own switch follows it, at launch and as it
// changes, and a page scrolled under its header wears the blur or does not by it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/root/ghost_root.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);
  tearDown(BlurEdgeSettings.instance.reset);

  Future<void> open(WidgetTester tester, {required bool blur}) async {
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', wispEdge: blur),
      home: GhostRoot(
        launch: false,
        core: (command, [args = const <String, Object?>{}]) async => null,
        library: SampleLibrary.seeded(),
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => DateTime(2026, 10, 24, 12).millisecondsSinceEpoch,
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  /// The home page's strips once it is scrolled under its header.
  Future<List<EdgeStrip>> scrolledHome(WidgetTester tester) async {
    final edge = find.byType(BlurEdge).first;
    final scroller = tester.stateList<ScrollableState>(find.descendant(of: edge, matching: find.byType(Scrollable))).first;
    scroller.position.jumpTo(200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return tester.renderObject<RenderEdgeStrips>(find.descendant(of: edge, matching: find.byType(EdgeStrips)).first).strips;
  }

  testWidgets('the edges blur with it on, and the art\'s switch follows it as it changes', (tester) async {
    await open(tester, blur: true);
    expect(BlurEdgeSettings.instance.wanted, isTrue);
    expect((await scrolledHome(tester)).whereType<EdgeBlurStrip>(), isNotEmpty);
    preferences.value = preferences.value.copyWith(wispEdge: false);
    await tester.pump();
    await tester.pump();
    expect(BlurEdgeSettings.instance.wanted, isFalse);
    expect(tester.renderObject<RenderEdgeStrips>(find.descendant(of: find.byType(BlurEdge).first, matching: find.byType(EdgeStrips)).first).strips, isEmpty);
    await close(tester);
  });

  testWidgets('the edges are clean with it off from the start', (tester) async {
    await open(tester, blur: false);
    expect(BlurEdgeSettings.instance.wanted, isFalse);
    expect(await scrolledHome(tester), isEmpty);
    await close(tester);
  });
}
