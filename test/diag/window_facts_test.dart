import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/diag/window_facts.dart';

/// `diag/windowFacts.test.ts`, case for case: the Developer page's Window facts. An inset the window is not given
/// reads as 0px, the sizes read as sizes, and an engine is named without a version being made up.
void main() {
  group('windowFacts', () {
    testWidgets('reads the top inset as a length, the page and screen as sizes, and names the engine', (tester) async {
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.viewPadding = const FakeViewPadding(top: 96);
      addTearDown(tester.view.reset);
      late WindowFacts facts;
      await tester.pumpWidget(Builder(builder: (context) {
        facts = windowFacts(context);
        return const SizedBox.shrink();
      }));
      expect(facts.inset, matches(RegExp(r'px$')));
      expect(facts.inset, '36.57px');
      expect(facts.page, matches(RegExp(r'^[\d.]+ × [\d.]+ @[\d.]+$')));
      expect(facts.page, '411.43 × 891.43 @2.63');
      expect(facts.screen, matches(RegExp(r'^[\d.]+ × [\d.]+$')));
      // What draws a Flutter app, and the platform: no agent string to read a version from.
      expect(facts.engine, matches(RegExp(r'^(Impeller|Skia|Flutter) on \w+$')));
    });

    test('names a WebView by its Chrome, and marks it a WebView', () {
      // jsdom's agent string carries no Chrome, so the engine is the WebKit it does name.
      expect(engineWords('Mozilla/5.0 (darwin) AppleWebKit/537.36 (KHTML, like Gecko) jsdom/26.0.0'), 'AppleWebKit/537.36');
      expect(
        engineWords('Mozilla/5.0 (Linux; Android 16; SM-F976B Build/BP2A) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.51 Mobile Safari/537.36 wv'),
        'Chrome 140.0.7339.51 (WebView)',
      );
      expect(engineWords('curl/8.4'), 'unknown');
    });

    test('writes whole numbers whole, and an inset the window is not given as 0px', () {
      final facts = windowFactsOf(inset: 0, page: const Size(390, 844), ratio: 2, screen: const Size(390, 844), engine: '');
      expect(facts, (inset: '0px', page: '390 × 844 @2', screen: '390 × 844', engine: 'unknown'));
    });
  });
}
