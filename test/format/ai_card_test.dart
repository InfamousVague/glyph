// The AI card (lib/format/ai_card.dart). A port of `src/app/format/AiCard.test.tsx`, case for case, and pictures in
// shots/ to lay beside the page (AiCard.module.css, Thinking.module.css).
//
// The page's first case counted on jsdom's own `navigator.hardwareConcurrency` for a reading; here the phone's facts
// are handed in.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/format/ai_card.dart';
import 'package:ghost_md/format/device_facts.dart';
import 'package:ghost_md/format/thinking.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

Future<void> show(WidgetTester tester, Widget card, {String theme = 'light'}) async {
  await pumpApp(
    tester,
    prefs: AppPreferences(theme: theme),
    home: Builder(
      builder: (context) => ColoredBox(color: context.tokens.color('app-paper'), child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 96), child: card))),
    ),
  );
  debugDisableShadows = true;
  await tester.pump(const Duration(milliseconds: 400));
}

String words(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byType(Text))) text.semanticsLabel ?? text.data ?? ''].join(' | ');

/// How full each reading's bar is, by its label.
Map<String, double> bars(WidgetTester tester) => {
      for (final element in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ai-card-bar-')).evaluate())
        ((element.widget.key! as ValueKey<String>).value.substring('ai-card-bar-'.length)): tester.widget<FractionallySizedBox>(find.ancestor(of: find.byWidget(element.widget), matching: find.byType(FractionallySizedBox)).first).widthFactor!,
    };

Future<void> end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const hardware = Hardware(rssBytes: 3100000000, freeBytes: 5000000000, totalBytes: 12000000000, cpuPercent: 640, threads: 6, cores: 8, tempC: 41);

void main() {
  setUpAll(loadAppFonts);

  group('the AI card', () {
    testWidgets('names the model, says it runs on the phone, and what it is doing', (tester) async {
      await show(
        tester,
        const AiCard(model: 'qwen3.5-4b', phase: Phase.prefill, doing: 'Formatting', promptTokens: 684, promptTokensDone: 256, outputTokens: 0, tokensPerSecond: 0, elapsedMs: 4000, facts: DeviceFacts(cores: 8, memoryGb: null, battery: null)),
      );
      expect(words(tester), contains('Qwen3.5 4B'));
      expect(words(tester), contains('On this phone'));
      expect(words(tester), contains('Reading the note, 256 of 684.'));
      expect(words(tester), contains('Nothing leaves the phone.'));
      expect(words(tester), contains('Cores'));
      await end(tester);
    });

    testWidgets('shows the engine’s readings when a binary reports them, with bars for the shares', (tester) async {
      await show(tester, const AiCard(model: 'qwen3.5-2b', phase: Phase.generating, doing: 'Summarizing', promptTokens: 100, promptTokensDone: 100, outputTokens: 42, tokensPerSecond: 7.3, elapsedMs: 32000, hardware: hardware));
      final text = words(tester);
      expect(text, contains('Summarizing, 7.3 tokens a second, 0:32.'));
      expect(text, contains('6 of 8'));
      expect(text, contains('640%'));
      expect(text, contains('3.1 GB of 12.0 GB'));
      expect(text, contains('41 °C'));
      expect(text, contains('42 tokens'));
      expect(bars(tester)['CPU'], 0.8); // 640 of 800
      expect(bars(tester)['Cores'], 0.75); // 6 of 8
      await end(tester);
    });

    testWidgets('leaves out what nothing reports', (tester) async {
      await show(tester, const AiCard(model: 'qwen3.5-4b', phase: Phase.loading, doing: 'Enhancing', promptTokens: 0, promptTokensDone: 0, outputTokens: 0, tokensPerSecond: 0, elapsedMs: 0));
      expect(words(tester), isNot(contains('CPU')));
      expect(words(tester), isNot(contains('°C')));
      expect(words(tester), contains('Loading Qwen3.5 4B.'));
      await end(tester);
    });
  });

  group('how it is drawn', () {
    testWidgets('the reader 4.5rem square beside the words, the card inside the gutters with its own room', (tester) async {
      await show(tester, const AiCard(model: 'qwen3.5-2b', phase: Phase.generating, doing: 'Summarizing', promptTokens: 100, promptTokensDone: 100, outputTokens: 42, tokensPerSecond: 7.3, elapsedMs: 32000, hardware: hardware));
      final t = tester.element(find.byType(AiCard)).tokens;
      final card = tester.getRect(find.byKey(const ValueKey<String>('ai-card')));
      expect(card.left, closeTo(t.len('app-gutter'), 0.01));
      expect(390 - card.right, closeTo(t.len('app-gutter'), 0.01));
      final reader = tester.getRect(find.byType(Thinking));
      expect(reader.width, closeTo(72, 0.01));
      expect(reader.height, closeTo(72, 0.01));
      // padding: var(--glacier-space-4), inside the hairline.
      expect(reader.left - card.left, closeTo(t.space(4) + t.len('glacier-hairline'), 0.3));
      expect(reader.top - card.top, closeTo(t.space(4) + t.len('glacier-hairline'), 0.3));
      // The words start a space-4 after the reader.
      final line = tester.getRect(find.byKey(const ValueKey<String>('ai-card-line')));
      expect(line.left - reader.right, closeTo(t.space(4), 0.01));
      final said = tester.widget<Text>(find.byKey(const ValueKey<String>('ai-card-line')));
      expect((said.style!.fontSize, said.style!.color), (t.fontSize('sm'), t.color('app-ink-2')));
      await end(tester);
    });

    testWidgets('holds still for a reader who asked for less motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await show(tester, const AiCard(model: 'qwen3.5-4b', phase: Phase.prefill, doing: 'Formatting', promptTokens: 684, promptTokensDone: 256, outputTokens: 0, tokensPerSecond: 0, elapsedMs: 4000));
      expect(tester.hasRunningAnimations, isFalse);
      await end(tester);
    });
  });

  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the card on a page while the model writes, $theme', (tester) async {
        await show(
          tester,
          const AiCard(
            model: 'qwen3.5-2b',
            phase: Phase.generating,
            doing: 'Summarizing',
            promptTokens: 100,
            promptTokensDone: 100,
            outputTokens: 42,
            tokensPerSecond: 7.3,
            elapsedMs: 32000,
            hardware: hardware,
            facts: DeviceFacts(cores: 8, memoryGb: 12, battery: BatteryReading(level: 0.81, charging: true)),
          ),
          theme: theme,
        );
        await shot(tester, 'ai-card-writing-$theme', settle: Duration.zero);
      });
    }

    testWidgets('the card while the model loads: the reader’s eyes shut, the note waiting, light', (tester) async {
      await show(tester, const AiCard(model: 'qwen3.5-4b', phase: Phase.loading, doing: 'Enhancing', promptTokens: 0, promptTokensDone: 0, outputTokens: 0, tokensPerSecond: 0, elapsedMs: 0, facts: DeviceFacts(cores: 8, memoryGb: 12, battery: null)));
      await shot(tester, 'ai-card-loading-light', settle: Duration.zero);
    });

    testWidgets('the reader alone, as a whole stage, reading', (tester) async {
      await show(tester, const Thinking(phase: Phase.prefill));
      await shot(tester, 'thinking-reading-light', settle: Duration.zero);
    });
  });
}
