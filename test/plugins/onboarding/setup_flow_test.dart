// A plugin's setup, as a flow (lib/plugins/onboarding/; Matt, 2026-10-28: "For each of the plugins add a small
// onboarding flow start with the lovart and Claude plugins walk the user through setting up an account and getting
// their keys and have the onboarding test setup to make sure it was successful"): Back and Next through its steps, the
// dots, Open handing its address to the browser, the keys pasted, shown and checked for shape, the check run as its step
// shows and said in words, Skip and Done remembered, a setup put away opening where it was, Simple's shorter run, and
// the words each step says. Over a setup of the test's own, with nothing kept anywhere but in memory.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/market/market_cards.dart' show MarketButton;
import 'package:ghost_md/plugins/claude/claude.dart' show claudeSetup;
import 'package:ghost_md/plugins/lovart/lovart.dart' show lovartCreditsPerImage, lovartSetup;
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';

import '../../settings/support.dart';

/// A setup of the test's own: a key in memory, a check that says what [answer] is.
class FakeSetup {
  FakeSetup();

  String? key;
  final List<VoidCallback> listeners = [];
  SetupResult answer = const SetupResult.ok('It works.');
  int checks = 0;
  final List<Map<String, String>> saved = [];

  void _told() {
    for (final listener in [...listeners]) {
      listener();
    }
  }

  PluginSetup get setup => PluginSetup(
        id: 'fake',
        name: 'Fake',
        hues: const ['indigo', 'purple'],
        tiles: const [Lucide.sparkles, Lucide.keyRound],
        ready: () => key != null,
        watch: (listener) {
          listeners.add(listener);
          return () => listeners.remove(listener);
        },
        steps: [
          const SetupIntro(id: 'intro', title: 'What it is', icon: Lucide.sparkles, points: [(Lucide.image, 'A point')]),
          const SetupOpen(id: 'account', title: 'An account', icon: Lucide.userPlus, links: [SetupLink('Open fake.example', 'https://www.fake.example/sign-up/'), SetupLink('Billing', 'https://fake.example/billing')]),
          const SetupOpen(id: 'more', title: 'Only in Advanced', icon: Lucide.gauge, advanced: true, links: [SetupLink('Open more', 'https://fake.example/more')]),
          SetupPaste(
            id: 'paste',
            title: 'Paste it',
            icon: Lucide.clipboardPaste,
            fields: [SetupField(id: 'key', label: 'Key', placeholder: 'fk-…', shape: (text) => text.startsWith('fk-') ? null : 'Those start with fk-.')],
            save: (values) async {
              saved.add(values);
              key = values['key'];
              _told();
              return null;
            },
          ),
          SetupCheck(
            id: 'check',
            title: 'Check it',
            icon: Lucide.shieldCheck,
            run: () async {
              checks += 1;
              return answer;
            },
          ),
          const SetupDone(id: 'done', title: 'Done', icon: Lucide.wandSparkles),
        ],
      );
}

void main() {
  setUpAll(loadAppFonts);

  late FakeSetup fake;
  late MemoryStored kept;
  late SetupMemory memory;
  late List<String> opened;
  late List<String> closed;
  String clipboard = '';

  setUp(() {
    fake = FakeSetup();
    kept = MemoryStored();
    memory = SetupMemory(kept);
    opened = [];
    closed = [];
    clipboard = '';
  });

  /// The sheet over an empty page, on [size], as [prefs] say; put away, it is no longer built.
  Future<void> pumpSheet(WidgetTester tester, {PluginSetup? setup, bool fromStart = false, Size size = phone, Preferences prefs = const Preferences(theme: 'light')}) async {
    final up = ValueNotifier(true);
    addTearDown(up.dispose);
    final shown = setup ?? fake.setup;
    // A sheet of its own each time: the app's root is the same widget from one pump to the next.
    final sheetKey = UniqueKey();
    await pumpSettings(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: up,
        builder: (context, open, _) => open
            ? PluginSetupSheet(
                key: sheetKey,
                setup: shown,
                fromStart: fromStart,
                memory: memory,
                open: (url) async => opened.add(url),
                paste: () async => clipboard,
                onClose: () {
                  closed.add(memory.ended(shown.id)?.name ?? 'left');
                  up.value = false;
                },
              )
            : const SizedBox.shrink(),
      ),
      size: size,
      prefs: prefs,
    );
  }

  String title(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('setup-title'))).data!;
  String dots(WidgetTester tester) => tester.getSemantics(find.byKey(const ValueKey('setup-dots'))).label;

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('setup-next')));
    await settleSettings(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('setup-back')));
    await settleSettings(tester);
  }

  Finder field(String id) => find.descendant(of: find.byKey(ValueKey('setup-field-$id')), matching: find.byType(EditableText));

  testWidgets('goes through its steps with Back and Next, the dots saying where, each remembered as it shows', (tester) async {
    await pumpSheet(tester, prefs: const Preferences(theme: 'light', experience: 'advanced', experienceChosen: true));
    expect(title(tester), 'What it is');
    expect(dots(tester), 'Step 1 of 6');
    expect(find.byKey(const ValueKey('setup-back')), findsNothing);
    expect(find.text('A point'), findsOneWidget);
    expect(tester.widget<MarketButton>(find.byKey(const ValueKey('setup-next'))).label, 'Start');
    await next(tester);
    expect((title(tester), dots(tester), memory.leftAt('fake')), ('An account', 'Step 2 of 6', 'account'));
    // Open hands the address to the browser; the addresses are written small, as they are typed.
    await tester.tap(find.byKey(const ValueKey('setup-open-0')));
    await tester.tap(find.byKey(const ValueKey('setup-open-1')));
    await tester.pump();
    expect(opened, ['https://www.fake.example/sign-up/', 'https://fake.example/billing']);
    expect(find.text('fake.example/sign-up · fake.example/billing'), findsOneWidget);
    await next(tester);
    expect(title(tester), 'Only in Advanced');
    await back(tester);
    expect((title(tester), memory.leftAt('fake')), ('An account', 'account'));
    // The back gesture steps back too, and at the first step puts the sheet away, left there.
    testBack.goBack();
    await settleSettings(tester);
    expect(title(tester), 'What it is');
    testBack.goBack();
    await settleSettings(tester);
    expect(closed, ['left']);
    expect(find.byType(PluginSetupSheet), findsNothing);
    await endSettings(tester);
  });

  testWidgets('keeps a key of the right shape, pasted and shown, then checks it, and Done ends it', (tester) async {
    memory.at('fake', 'paste');
    await pumpSheet(tester);
    expect(title(tester), 'Paste it');
    // Nothing typed, nothing to keep.
    expect(tester.widget<MarketButton>(find.byKey(const ValueKey('setup-next'))).onPress, isNull);
    clipboard = '  nope  ';
    await tester.tap(find.byKey(const ValueKey('setup-paste-key')));
    await tester.pump();
    expect(tester.widget<EditableText>(field('key')).controller.text, 'nope');
    expect(tester.widget<EditableText>(field('key')).obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('setup-show-key')));
    await tester.pump();
    expect(tester.widget<EditableText>(field('key')).obscureText, isFalse);
    await next(tester);
    expect(find.text('Those start with fk-.'), findsOneWidget);
    expect(fake.saved, isEmpty);
    clipboard = 'fk-123';
    await tester.tap(find.byKey(const ValueKey('setup-paste-key')));
    await tester.pump();
    await next(tester);
    expect(fake.saved, [
      {'key': 'fk-123'},
    ]);
    // The check runs as its step shows, and says what it found.
    expect((title(tester), fake.checks), ('Check it', 1));
    expect(find.text('It works.'), findsOneWidget);
    await next(tester);
    expect(title(tester), 'Done');
    expect(find.byKey(const ValueKey('setup-skip')), findsNothing);
    await next(tester);
    expect(closed, ['done']);
    expect(memory.ended('fake'), SetupEnd.done);
    expect(memory.leftAt('fake'), isNull);
    await endSettings(tester);
  });

  testWidgets('a check that fails says why, checks again, and sends refused keys back to be pasted', (tester) async {
    fake.key = 'fk-old';
    fake.answer = const SetupResult.failed('That key isn’t right.', pasteAgain: true);
    memory.at('fake', 'check');
    await pumpSheet(tester);
    expect(title(tester), 'Check it');
    expect(find.text('That key isn’t right.'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-paste-again')), findsOneWidget);
    expect(tester.widget<MarketButton>(find.byKey(const ValueKey('setup-next'))).label, 'Check again');
    fake.answer = const SetupResult.warn('Works, but add credit.', link: SetupLink('Open Billing', 'https://fake.example/billing'));
    await next(tester);
    expect(fake.checks, 2);
    expect(find.text('Works, but add credit.'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-paste-again')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('setup-result-link')));
    await tester.pump();
    expect(opened, ['https://fake.example/billing']);
    // A warning goes on.
    expect(tester.widget<MarketButton>(find.byKey(const ValueKey('setup-next'))).label, 'Next');
    // Back to the keys, a new one kept, and refused: Paste again goes back for it.
    await back(tester);
    expect(title(tester), 'Paste it');
    await tester.enterText(field('key'), 'fk-new');
    await tester.pump();
    fake.answer = const SetupResult.failed('Refused.', pasteAgain: true);
    await next(tester);
    expect((title(tester), fake.checks, find.text('Refused.').evaluate().length), ('Check it', 3, 1));
    await tester.tap(find.byKey(const ValueKey('setup-paste-again')));
    await settleSettings(tester);
    expect(title(tester), 'Paste it');
    await endSettings(tester);
  });

  testWidgets('Skip puts it away as skipped, and the next time it starts again from the top', (tester) async {
    memory.at('fake', 'account');
    await pumpSheet(tester);
    expect(title(tester), 'An account');
    await tester.tap(find.byKey(const ValueKey('setup-skip')));
    await settleSettings(tester);
    expect(closed, ['skipped']);
    expect(memory.ended('fake'), SetupEnd.skipped);
    await pumpSheet(tester);
    expect(title(tester), 'What it is');
    await endSettings(tester);
  });

  testWidgets('opens where it was left, but at the keys while none are kept, and from the top for Run setup again', (tester) async {
    memory.at('fake', 'done');
    await pumpSheet(tester);
    // Left at the end with no key kept: the keys again.
    expect(title(tester), 'Paste it');
    fake.key = 'fk-1';
    memory.at('fake', 'done');
    await pumpSheet(tester);
    expect(title(tester), 'Done');
    await pumpSheet(tester, fromStart: true);
    expect(title(tester), 'What it is');
    await endSettings(tester);
  });

  testWidgets('Simple leaves out the Advanced steps and the intro’s points', (tester) async {
    await pumpSheet(tester, prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true));
    expect(dots(tester), 'Step 1 of 5');
    expect(find.text('A point'), findsNothing);
    await next(tester);
    await next(tester);
    expect(title(tester), 'Paste it');
    await endSettings(tester);
  });

  test('remembers each plugin’s place on its own, in the device’s memory', () {
    memory.at('lovart', 'paste');
    memory.end('claude', 'done', SetupEnd.done);
    expect((memory.leftAt('lovart'), memory.leftAt('claude'), memory.ended('claude')), ('paste', null, SetupEnd.done));
    expect(SetupMemory(kept).leftAt('lovart'), 'paste');
    expect(kept.readText(SetupMemory.key), isNotNull);
    memory.forget('lovart');
    expect(memory.leftAt('lovart'), isNull);
  });

  test('every step of the shipped setups has words, and Lovart’s say its credits as the client counts them', () {
    for (final setup in [lovartSetup(), claudeSetup()]) {
      for (final step in setup.steps) {
        for (final simple in [false, true]) {
          expect(setup.wordsOf(step, simple: simple), isNotEmpty, reason: '${setup.id}-${step.id}');
        }
      }
    }
    expect(setupWords('lovart-intro'), contains('about $lovartCreditsPerImage credits an image'));
    expect(setupWords('lovart-intro', simple: true), contains('about $lovartCreditsPerImage credits an image'));
    // One line each, in single quotes: what tool/plugin_setup_voice.py reads.
    expect(setupVoice.values.where((words) => words.contains('\n') || words.contains("'")), isEmpty);
    expect(setupVoiceAsset('lovart-intro'), 'assets/plugin-setup/lovart-intro.mp3');
  });

  test('says an address as it is typed', () {
    expect(shortAddress('https://console.anthropic.com/settings/keys'), 'console.anthropic.com/settings/keys');
    expect(shortAddress('https://www.lovart.ai/'), 'lovart.ai');
  });
}
