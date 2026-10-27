import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/guide/guide.dart';
import 'package:ghost_md/guide/guide_state.dart';
import 'package:ghost_md/guide/narration.dart';
import 'package:ghost_md/guide/narrator.dart';
import 'package:ghost_md/guide/pages.dart';
import 'package:ghost_md/guide/pages/band.dart';
import 'package:ghost_md/guide/pages/parts.dart';

import 'support.dart';

/// The tour read aloud (Matt, 2026-10-27: "a friendly elevenlabs v4 voice explaining each section"): the voice starts
/// with its page and stops as the page goes, keeps quiet once switched off and remembers that, and every page has its
/// words on screen as captions. And the tour's frame: its order, Skip, Back and Next, the mode it asks, and how it
/// is marked done.
class FakeVoice implements NarrationOutput {
  final List<String> calls = [];
  bool quiet = false;

  @override
  Future<bool> narrate(String key, Uint8List bytes) async {
    calls.add('narrate ${key.split('/').last}');
    return !quiet;
  }

  @override
  Future<void> hush() async => calls.add('hush');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));
  tearDown(() => useStored(MemoryStored()));

  Future<ByteData> anyFile(String asset) async => ByteData(8);
  int at(GuidePage page) => page.index;

  /// The guide at [index], read aloud into [voice], its page held by a notifier the test turns.
  Future<({ValueNotifier<int> shown, ValueNotifier<Preferences> store, List<String> closed})> guide(WidgetTester tester, FakeVoice voice, {int index = 0, Size size = const Size(390, 844)}) async {
    final shown = ValueNotifier<int>(index);
    final store = ValueNotifier<Preferences>(const Preferences(theme: 'light'));
    final narrator = Narrator(output: voice, load: anyFile);
    addTearDown(shown.dispose);
    addTearDown(store.dispose);
    addTearDown(narrator.dispose);
    final closed = <String>[];
    await pumpGuide(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: shown,
        builder: (context, now, _) => Guide(index: now, onIndex: (next) => shown.value = next, onClose: () => closed.add('close'), onAcademy: () => closed.add('academy'), preferences: store, narrator: narrator),
      ),
      size: size,
    );
    await tester.pump();
    await tester.pump();
    return (shown: shown, store: store, closed: closed);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('the tour', () {
    test('walks through what the app is, then asks, then hands over', () {
      expect(walkthroughPages, [GuidePage.welcome, GuidePage.speak, GuidePage.meetings, GuidePage.ai, GuidePage.sync, GuidePage.market, GuidePage.mode, GuidePage.model, GuidePage.start]);
      // Every page has its words, its colour and its signs.
      for (final page in walkthroughPages) {
        expect(narration[page], isNotEmpty, reason: page.name);
        expect(guideLooks[page]!.colours.length, greaterThanOrEqualTo(2), reason: page.name);
      }
    });

    testWidgets('shows each page’s spoken words on the page, as its captions', (tester) async {
      final it = await guide(tester, FakeVoice());
      for (final page in walkthroughPages) {
        it.shown.value = at(page);
        await settle(tester);
        expect(find.text(narration[page]!), findsOneWidget, reason: page.name);
        expect(find.byKey(ValueKey('guide-band-${page.name}')), findsOneWidget, reason: page.name);
      }
      await away(tester);
    });

    testWidgets('goes through every page with Next, back with Back, and Skip closes it from any of them', (tester) async {
      final it = await guide(tester, FakeVoice(), size: const Size(390, 2400));
      for (var i = 1; i < walkthroughPages.length; i++) {
        await tester.tap(find.text('Next'));
        await settle(tester);
        expect(it.shown.value, i);
      }
      expect(find.text('Start'), findsOneWidget);
      await tester.tap(find.widgetWithText(GuideWord, 'Back'));
      await settle(tester);
      expect(it.shown.value, walkthroughPages.length - 2);
      await tester.tap(find.widgetWithText(GuideWord, 'Skip'));
      expect(it.closed, ['close']);
      await away(tester);
    });

    testWidgets('writes the mode chosen on its page, and Simple takes the model page out of the count', (tester) async {
      final it = await guide(tester, FakeVoice(), index: at(GuidePage.mode), size: const Size(390, 1600));
      expect(find.bySemanticsLabel('Page ${at(GuidePage.mode) + 1} of 9'), findsOneWidget);
      await tester.tap(find.text('Advanced'));
      await settle(tester);
      expect((it.store.value.experience, it.store.value.experienceChosen), ('advanced', true));
      await tester.tap(find.text('Simple'));
      await settle(tester);
      expect((it.store.value.experience, it.store.value.experienceChosen), ('simple', true));
      expect(find.bySemanticsLabel('Page ${at(GuidePage.mode) + 1} of 8'), findsOneWidget);
      await away(tester);
    });

    testWidgets('sets the theme from its last page', (tester) async {
      final it = await guide(tester, FakeVoice(), index: at(GuidePage.start), size: const Size(390, 1600));
      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(it.store.value.theme, 'dark');
      await away(tester);
    });

    test('is marked done once closed, and does not open by itself again', () {
      expect(GuideController().open, isTrue);
      GuideController().close();
      expect(GuideController().open, isFalse);
      expect(stored.readText(guideSeenKey), '1');
    });
  });

  group('the voice', () {
    testWidgets('says each page as it shows, stopping the last one first, and stops when the guide goes', (tester) async {
      final voice = FakeVoice();
      final it = await guide(tester, voice);
      expect(voice.calls, ['hush', 'narrate welcome.mp3']);
      voice.calls.clear();
      it.shown.value = at(GuidePage.speak);
      await settle(tester);
      expect(voice.calls, ['hush', 'narrate speak.mp3']);
      voice.calls.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(voice.calls, contains('hush'));
      expect(voice.calls, isNot(contains(startsWith('narrate'))));
      await away(tester);
    });

    testWidgets('stops when switched off, keeps quiet on the pages after, remembers it, and starts again when switched on', (tester) async {
      final voice = FakeVoice();
      final it = await guide(tester, voice);
      voice.calls.clear();
      await tester.tap(find.byKey(const ValueKey('guide-voice')));
      await settle(tester);
      expect(voice.calls, ['hush']);
      expect(find.bySemanticsLabel('Read aloud'), findsOneWidget);
      expect(stored.readText(guideMutedKey), '1');
      voice.calls.clear();
      it.shown.value = at(GuidePage.meetings);
      await settle(tester);
      expect(voice.calls.where((call) => call.startsWith('narrate')), isEmpty);
      await away(tester);

      // A guide opened again later is still quiet.
      final again = FakeVoice();
      await guide(tester, again, index: at(GuidePage.sync));
      expect(again.calls.where((call) => call.startsWith('narrate')), isEmpty);
      await tester.tap(find.byKey(const ValueKey('guide-voice')));
      await settle(tester);
      expect(again.calls.last, 'narrate sync.mp3');
      expect(stored.readText(guideMutedKey), isNull);
      await away(tester);
    });

    testWidgets('stops when the app leaves the screen', (tester) async {
      final voice = FakeVoice();
      await guide(tester, voice);
      voice.calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(voice.calls, contains('hush'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(voice.calls.where((call) => call.startsWith('narrate')), isEmpty);
      await away(tester);
    });

    test('says nothing where the page has no file yet, or there is no player', () async {
      final voice = FakeVoice();
      final missing = Narrator(output: voice, load: (asset) async => throw FlutterError('No asset at $asset'));
      missing.show(GuidePage.welcome);
      await Future<void>.delayed(Duration.zero);
      expect(missing.saying, isNull);
      expect(voice.calls.where((call) => call.startsWith('narrate')), isEmpty);
      missing.dispose();
      final none = Narrator(useDefaultOutput: false, load: anyFile);
      none.show(GuidePage.welcome);
      await Future<void>.delayed(Duration.zero);
      expect(none.saying, isNull);
      none.dispose();
    });

    test('counts a page the device kept quiet as not being said', () async {
      final voice = FakeVoice()..quiet = true;
      final narrator = Narrator(output: voice, load: anyFile);
      narrator.show(GuidePage.welcome);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(voice.calls, ['hush', 'narrate welcome.mp3']);
      expect(narrator.saying, isNull);
      narrator.dispose();
    });
  });
}
