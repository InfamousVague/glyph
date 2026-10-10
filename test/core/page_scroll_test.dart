import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/page_scroll.dart';

/// How every page scrolls is said once (lib/core/page_scroll.dart): an iPhone's rubber band, a Mac's, and a list
/// that stops at its ends anywhere else, as each platform's own engine scrolls the web app's page.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('each platform has its own physics', () {
    expect(pagePhysicsFor(TargetPlatform.iOS), isA<BouncingScrollPhysics>());
    expect((pagePhysicsFor(TargetPlatform.iOS) as BouncingScrollPhysics).decelerationRate, ScrollDecelerationRate.normal);
    expect(pagePhysicsFor(TargetPlatform.macOS), isA<BouncingScrollPhysics>());
    expect((pagePhysicsFor(TargetPlatform.macOS) as BouncingScrollPhysics).decelerationRate, ScrollDecelerationRate.fast);
    for (final platform in [TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.fuchsia]) {
      expect(pagePhysicsFor(platform), isA<ClampingScrollPhysics>(), reason: '$platform');
    }
  });

  test('a page under a pull to refresh holds its top and stretches at its foot on an iPhone', () {
    final rest = pullRestPhysics(platform: TargetPlatform.iOS);
    expect(rest, isA<FootBouncingScrollPhysics>());
    FixedScrollMetrics at(double pixels) =>
        FixedScrollMetrics(minScrollExtent: 0, maxScrollExtent: 1000, pixels: pixels, viewportDimension: 600, axisDirection: AxisDirection.down, devicePixelRatio: 3);
    // Past the top: refused whole, as a list that stops refuses it.
    expect(rest.applyBoundaryConditions(at(0), -30), -30);
    expect(rest.applyBoundaryConditions(at(12), -30), -30);
    // Past the foot: nothing is refused, and the band takes it.
    expect(rest.applyBoundaryConditions(at(1000), 1040), 0);
    expect(rest.applyBoundaryConditions(at(500), 520), 0);
    // Android's is the page's own.
    expect(pullRestPhysics(platform: TargetPlatform.android), isA<ClampingScrollPhysics>());
  });

  Future<double> dragPastTheTop(WidgetTester tester, {ScrollBehavior? own}) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget page = SingleChildScrollView(controller: controller, child: const SizedBox(height: 3000, width: 300));
    // A screen with a behaviour of its own extends the app's, and says no physics.
    if (own != null) page = ScrollConfiguration(behavior: own, child: page);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ScrollConfiguration(behavior: const GhostScrollBehavior(), child: page),
    ));
    final finger = await tester.startGesture(const Offset(150, 200));
    await finger.moveBy(const Offset(0, 120));
    await tester.pump();
    final pulled = controller.offset;
    await finger.up();
    await tester.pumpAndSettle();
    expect(controller.offset, 0, reason: 'it comes back to its top');
    return pulled;
  }

  testWidgets('one rule reaches every scroller that names no physics: an iPhone’s stretches past its top', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await dragPastTheTop(tester), lessThan(0));
    expect(await dragPastTheTop(tester, own: const _Own()), lessThan(0));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('and Android’s stops there', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await dragPastTheTop(tester), 0);
    expect(await dragPastTheTop(tester, own: const _Own()), 0);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Own extends GhostScrollBehavior {
  const _Own();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
