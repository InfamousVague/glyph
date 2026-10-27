import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/notes/tabs/tab_row.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/top_bar.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// The tab row's end where the next tab is cut off, soft in every look the edges wear (lib/art/edge_strips.dart
/// [edgeLook]), on the shell as the shots draw it (test/shell/shots_test.dart): a phone reading Groceries with three
/// tabs open, the third past the row's right end, in each of the bar's four styles.
///
/// The shots redrawn 2026-10-27 had lost the blur there: they were drawn before Android's edges were backdrop bands
/// (bb613263), and the test's engine, which cannot filter by a shader, draws Android's edges as their fade. Android
/// itself had its band there all along; the fade had the row's own 12px alone, and the next tab's pill stood crisp
/// up to it. Now the fade runs the blur's whole depth ([fadedEnds]); build/feature-shots/tab-strip-end/ has the end
/// before and after. These fail if a look's end goes back to a crisp tab: no band on Android, no long fade where
/// nothing is blurred, no strip on the Mac.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugEdgeLook = null);

  /// The shell on a phone reading Groceries, its tab row past the screen's right edge; the row's soft box.
  Future<Finder> reading(WidgetTester tester, TopBarStyle style) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light'),
      home: AppShell(sheet: sheet, notes: library, workspaces: spaces, topBar: style, openNotes: const ['weekend', 'groceries', 'standup'], onNew: () {}, onDeleteNote: (_) {}),
    );
    await tester.pump(const Duration(milliseconds: 300));
    tester.state<AppShellState>(find.byType(AppShell)).openNote('groceries');
    await tester.pump(const Duration(milliseconds: 400));
    final sides = find.descendant(of: find.byType(TabRow), matching: find.byType(BlurSides));
    expect(sides, findsOneWidget, reason: 'the row has tabs past an end');
    final it = tester.widget<BlurSides>(sides);
    expect((it.start, it.end), (false, true), reason: 'at its start: the right end cut off, the left not');
    return sides;
  }

  /// The row's box, and a mask layer the size of it ([EdgeMasked]): the row going into the ground at its end.
  void masked(WidgetTester tester, Finder sides) {
    final size = tester.getSize(sides);
    expect(tester.layers.whereType<ShaderMaskLayer>().where((layer) => layer.maskRect?.size == size), isNotEmpty, reason: 'the row is drawn through its mask');
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final style in TopBarStyle.values) {
    group('the ${style.label} bar on a phone', () {
      testWidgets('where nothing can be blurred, the cut-off end fades over the blur\'s whole depth', (tester) async {
        debugEdgeLook = EdgeLook.fade;
        final sides = await reading(tester, style);
        final wide = tester.getSize(sides).width;
        final mask = tester.renderObject<RenderEdgeMasked>(find.descendant(of: sides, matching: find.byType(EdgeMasked)));
        final end = mask.strips.whereType<EdgeBlurStrip>().single;
        expect((end.side, end.rect.right), (EdgeSide.right, wide));
        final fade = end.fade!;
        expect(fade.at(wide - blurSidesDepth), 1, reason: 'whole at the blur\'s inner end');
        expect(fade.at(wide - blurSidesDepth / 2), closeTo(0.5, 1e-9), reason: 'half gone halfway, where the row\'s own 12px fade alone left it whole');
        expect(fade.at(wide - blurSidesFade), lessThan(0.5));
        expect(fade.at(wide), 0, reason: 'gone at the edge');
        expect(fade.at(0), 1, reason: 'the start is not cut off');
        masked(tester, sides);
        expect(find.descendant(of: sides, matching: find.byType(EdgeBackdropBand)), findsNothing);
        await away(tester);
      });

      testWidgets('on Android, the cut-off end is a backdrop band over the row\'s fade', (tester) async {
        debugEdgeLook = EdgeLook.backdrop;
        final sides = await reading(tester, style);
        final box = tester.getRect(sides);
        final bands = find.descendant(of: sides, matching: find.byType(EdgeBackdropBand));
        expect(bands, findsOneWidget, reason: 'one band, at the end with a tab past it');
        final band = tester.renderObject<RenderEdgeBackdropBand>(bands);
        expect(band.localToGlobal(Offset.zero) & band.size, Rect.fromLTRB(box.right - blurSidesDepth, box.top, box.right, box.bottom));
        expect((band.side, band.sigma, band.clear), (EdgeSide.right, blurSidesSigma, blurSidesFade));
        expect(find.descendant(of: sides, matching: find.ancestor(of: bands, matching: find.byType(BackdropGroup))), findsOneWidget, reason: 'read in the row\'s own group');
        final end = tester.renderObject<RenderEdgeMasked>(find.descendant(of: sides, matching: find.byType(EdgeMasked))).strips.whereType<EdgeBlurStrip>().single;
        expect(end.fade!.clearFrom - end.fade!.wholeUntil, blurSidesFade, reason: 'under the band, the row\'s own short fade: the band\'s blur does the rest');
        masked(tester, sides);
        await away(tester);
      });

      testWidgets('on the Mac, the cut-off end is a strip of the row blurred', variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
        final sides = await reading(tester, style);
        final wide = tester.getSize(sides).width;
        final strips = tester.renderObject<RenderEdgeStrips>(find.descendant(of: sides, matching: find.byWidgetPredicate((widget) => widget is EdgeStrips))).strips;
        final end = strips.whereType<EdgeBlurStrip>().single;
        expect((end.side, end.rect.right, end.sigma), (EdgeSide.right, wide, blurSidesSigma));
        expect(end.rect.width, greaterThanOrEqualTo(blurSidesDepth), reason: 'the blur\'s depth, or the row\'s fade where that is longer (a desktop\'s)');
        expect(find.descendant(of: sides, matching: find.byType(EdgeBackdropBand)), findsNothing);
        await away(tester);
      });
    });
  }
}
