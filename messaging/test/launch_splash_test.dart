import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/art/loading_logo.dart';
import 'package:ghost_messaging/desktop/ui/launch_splash.dart';
import 'package:ghost_messaging/ui/common.dart' show GhostLogo;
import 'package:glacier/glacier.dart';

import 'support/drawn_ink.dart';
import 'support/list_harness.dart';

/// The launch splash (lib/desktop/ui/launch_splash.dart; Matt, 2026-11-20): the logo, what it is doing, and a bar
/// while an update comes down, in a window 300 by 340. Pictures in build/themes/launch-splash.
///
/// The logo (lib/art/loading_logo.dart, test/loading_logo_test.dart) is by itself, in the page's ink, and most of
/// the window across (Matt, 2026-11-27: "remove the uplink logo from the squircle on the loading page", and "make it
/// larger so it is visible"). It is still, breathing a little as the splash waits: his film of it turning stood here
/// for one release, and "actually just do the static image, the video doesn't look good".
/// The app's own letters, so the pictures say what the splash says.
Future<void> _fonts() async {
  final loader = FontLoader('Inter Variable')..addFont(File('assets/fonts/InterVariable-latin.ttf').readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  for (final dark in [false, true]) {
    testWidgets('it says what it is doing, with a bar for a download (${dark ? 'dark' : 'light'})', (tester) async {
      final sheet = await loadSheet(tester);
      final step = ValueNotifier<SplashStep>((words: 'Checking for updates', progress: null));
      await pumpScreen(tester, sheet, LaunchSplash(step: step), AppState()..set('theme', dark ? 'dark' : 'light'), size: const Size(300, 340));
      await pictureShown(tester, find.byType(RawImage));
      expect(find.text('Checking for updates'), findsOneWidget);
      expect(find.byType(GhostLogo), findsNothing, reason: 'no tile behind the logo');
      final t = tester.element(find.byType(LaunchSplash)).tokens;
      final logo = tester.widget<LoadingLogo>(find.byKey(const ValueKey('splash-logo')));
      expect(logo.color, t.color('app-ink'), reason: 'the page\'s ink: the picture is white, and the light page is too');
      // Larger: its picture 240 across, the logo in it 232, where the mark was 128 across and the logo in it 115.
      final size = tester.getSize(find.byType(LoadingLogo));
      expect(size, Size(240, 240 / LoadingLogo.shape));
      expect(size.width * LoadingLogo.filled, greaterThan(115 * 2), reason: 'twice what it was');
      // It breathes: a little smaller to a little larger.
      final breath = tester.widget<ScaleTransition>(find.ancestor(of: find.byType(LoadingLogo), matching: find.byType(ScaleTransition)));
      final sizes = <double>{};
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        sizes.add(breath.scale.value);
      }
      expect(sizes.reduce((a, b) => a < b ? a : b), closeTo(0.94, 0.01));
      expect(sizes.reduce((a, b) => a > b ? a : b), closeTo(1.04, 0.01));
      // Where it is now, as drawn, and the most room it ever takes.
      final box = tester.getRect(find.byType(LoadingLogo));
      final most = Rect.fromCenter(center: box.center, width: size.width * 1.04, height: size.height * 1.04);
      expect(box.width / size.width, inInclusiveRange(0.94, 1.04));
      // And it all stands in the window, with room round it: the logo at its largest, the words, the bar's place.
      final words = tester.getRect(find.byKey(const ValueKey('splash-words')));
      expect(most.left, greaterThanOrEqualTo(20));
      expect(most.right, lessThanOrEqualTo(300 - 20));
      expect(most.top, greaterThanOrEqualTo(24));
      expect(words.top, greaterThan(most.bottom + 4), reason: 'clear of the logo at its largest');
      expect(words.bottom, lessThanOrEqualTo(340 - 40), reason: 'the bar goes under the words');
      var drawn = await Drawn.of(tester, find.byType(WidgetsApp).evaluate().single);
      drawn.keep('build/themes/launch-splash/checking-${dark ? 'dark' : 'light'}.png');
      // Drawn in the ink on the page, and nothing but the page round it.
      final page = t.color('glacier-bg');
      final shares = drawn.shares(box, ink: logo.color, page: page);
      expect(shares.ink, inInclusiveRange(0.25, 0.45), reason: '$shares');
      expect(shares.page, inInclusiveRange(0.5, 0.75), reason: '$shares');
      expect(shares.other, 0, reason: '$shares');
      expect(drawn.not(Rect.fromLTWH(0, 0, 300, most.top - 2), page), 0, reason: 'above the logo');
      expect(drawn.not(Rect.fromLTWH(0, 0, most.left - 2, 340), page), 0, reason: 'left of it');
      expect(drawn.not(Rect.fromLTWH(most.right + 2, 0, 300 - most.right - 2, 340), page), 0, reason: 'right of it');
      step.value = (words: 'Downloading 0.9.38', progress: 0.42);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Downloading 0.9.38'), findsOneWidget);
      final bar = tester.getRect(find.byType(GlacierProgressBar));
      expect(bar.top, greaterThan(words.bottom));
      expect(bar.bottom, lessThanOrEqualTo(340 - 24));
      drawn = await Drawn.of(tester, find.byType(WidgetsApp).evaluate().single);
      drawn.keep('build/themes/launch-splash/downloading-${dark ? 'dark' : 'light'}.png');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a computer asked to move less has the logo as it is, not breathing', (tester) async {
    final sheet = await loadSheet(tester);
    final step = ValueNotifier<SplashStep>((words: 'Checking for updates', progress: null));
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpScreen(tester, sheet, LaunchSplash(step: step), AppState(), size: const Size(300, 340));
    expect(find.byType(LoadingLogo), findsOneWidget);
    expect(find.ancestor(of: find.byType(LoadingLogo), matching: find.byType(ScaleTransition)), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'nothing moving');
    expect(tester.takeException(), isNull);
  });
}
