// Claude's setup (lib/plugins/claude/claude_setup.dart; Matt, 2026-10-28: "For each of the plugins add a small
// onboarding flow start with the lovart and Claude plugins walk the user through setting up an account and getting
// their keys and have the onboarding test setup to make sure it was successful"): its steps and the Console's
// addresses, the key's shape, the key kept where the page keeps it, the check said in plain words (works, 401, 403,
// 429 and credit, no connection), the two settings at the end, and Set up on the plugin's page. Anthropic is a check of
// the test's own: nothing is asked of the network.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';

import '../../settings/support.dart';

void main() {
  setUpAll(loadAppFonts);

  late ClaudeSettings settings;
  late List<String> asked;
  ClaudeError? answer;

  setUp(() {
    settings = ClaudeSettings(MemorySecureStore());
    asked = [];
    answer = null;
  });

  PluginSetup setup() => claudeSetup(
        settings: settings,
        check: (key) async {
          asked.add(key);
          return answer;
        },
      );

  const key = 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz';

  group('the steps', () {
    test('an account, a key, the check and the settings, at the Console’s own addresses', () {
      final made = setup();
      expect([for (final step in made.steps) step.id], ['intro', 'account', 'key', 'paste', 'check', 'done']);
      final links = [for (final step in made.steps.whereType<SetupOpen>()) for (final link in step.links) (link.label, link.url)];
      expect(links, [
        ('Open the Console', 'https://console.anthropic.com/'),
        ('Billing', 'https://console.anthropic.com/settings/billing'),
        ('Open API keys', 'https://console.anthropic.com/settings/keys'),
      ]);
      expect(made.wordsOf(made.steps[1], simple: false), contains('Billing'));
      expect(made.wordsOf(made.steps[2], simple: false), contains('Create Key'));
      expect(claudePlugin.setup, isNotNull);
    });

    test('checks a key’s shape before it is kept: sk-ant-, whole, no spaces', () {
      expect(claudeKeyShape(key), isNull);
      expect(claudeKeyShape('sk-proj-abcdefghijklmnopqrstuvwxyz'), 'That doesn’t look like an Anthropic API key. Those start with sk-ant-.');
      expect(claudeKeyShape('sk-ant-abc'), 'That key looks cut short. Copy all of it from the Console.');
      expect(claudeKeyShape('sk-ant-api03 abcdefghijklmnopqrstuvwxyz'), 'Paste the key alone: it has no spaces in it.');
    });

    test('keeps the key where the page keeps it, and is needed until it is', () async {
      final made = setup();
      expect(made.ready(), isFalse);
      expect(await made.steps.whereType<SetupPaste>().single.save({'key': key}), isNull);
      expect(settings.key, key);
      expect(await settings.store.read(claudeKeyName), key);
      expect(made.ready(), isTrue);
    });
  });

  group('the check', () {
    Future<SetupResult> check() async {
      await settings.setKey(key);
      return setup().steps.whereType<SetupCheck>().single.run();
    }

    test('a key that works: one look at the models, and Claude is ready', () async {
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your key works. Claude is ready.'));
      expect(asked, [key]);
    });

    test('401: that key isn’t right, and it is let go of', () async {
      answer = errorOf(401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');
      final result = await check();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'That key isn’t right. Copy it again from API keys in the Console: all of it, from sk-ant- to the end.', true));
      expect(settings.hasKey, isFalse);
    });

    test('403: a key that may not use the API, in plain words', () async {
      answer = errorOf(403, '{"type":"error","error":{"type":"permission_error","message":"Your API key does not have permission to use the specified resource."}}');
      final result = await check();
      expect(result.words, 'Anthropic says this key may not use the API. Make a new key in the Console, in a workspace that can, and paste that.');
      expect(result.pasteAgain, isTrue);
    });

    test('429, 402 or a word of credit: the key works but there is no credit, with Billing', () async {
      for (final wrong in [
        errorOf(429, '{"type":"error","error":{"type":"rate_limit_error","message":"Rate limited"}}'),
        errorOf(402, '{"type":"error","error":{"type":"billing_error","message":"Billing issue"}}'),
        errorOf(400, '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}'),
      ]) {
        answer = wrong;
        final result = await check();
        expect((result.kind, result.words, result.link?.url), (SetupCheckKind.warn, 'The key works but the account has no credit yet; add some under Billing.', 'https://console.anthropic.com/settings/billing'), reason: '${wrong.status}');
        expect(settings.hasKey, isTrue);
      }
    });

    test('no connection, or no answer in time, is said as the connection', () async {
      answer = const ClaudeError('Claude could not be reached. Check the connection.');
      expect((await check()).words, 'Anthropic couldn’t be reached. Check the connection, then check again.');
      answer = const ClaudeError('Claude took too long to answer.');
      expect((await check()).words, 'Anthropic took too long to answer. Check the connection, then check again.');
      expect(settings.hasKey, isTrue);
    });

    test('with no key kept, asks for one and asks Anthropic nothing', () async {
      final result = await setup().steps.whereType<SetupCheck>().single.run();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(asked, isEmpty);
    });
  });

  group('drawn', () {
    Finder field() => find.descendant(of: find.byKey(const ValueKey('setup-field-key')), matching: find.byType(EditableText));

    testWidgets('a key of the wrong shape is said before anything is kept; the right one is kept, checked and set up', (tester) async {
      final memory = SetupMemory(MemoryStored())..at('claude', 'paste');
      await pumpSettings(tester, PluginSetupSheet(setup: setup(), memory: memory, onClose: () {}));
      expect(find.text('Paste your key'), findsOneWidget);
      await tester.enterText(field(), 'sk-proj-abcdefghijklmnopqrstuvwxyz');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(find.text('That doesn’t look like an Anthropic API key. Those start with sk-ant-.'), findsOneWidget);
      expect(settings.hasKey, isFalse);
      expect(asked, isEmpty);
      await tester.enterText(field(), key);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(settings.key, key);
      expect(asked, [key]);
      expect(find.text('Your key works. Claude is ready.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      // The two settings, each with its default in a line.
      expect(find.text('Your settings'), findsOneWidget);
      expect(find.text('On by default: each meeting’s transcript goes from this device to Anthropic under your key, and Claude writes it up.'), findsOneWidget);
      expect(find.text('Sonnet 5.5 unless you choose another: quick and able. Each is billed at its own price.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('claude-setup-meetings')));
      await settleSettings(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-setup-meetings')), matching: find.byType(GlacierSwitch)));
      await settleSettings(tester);
      expect(settings.meetings, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('claude-setup-model:claude-opus-5-5')));
      await settleSettings(tester);
      await tester.tap(find.byKey(const ValueKey('claude-setup-model:claude-opus-5-5')));
      await settleSettings(tester);
      expect(settings.model, 'claude-opus-5-5');
      await endSettings(tester);
    });

    testWidgets('the plugin’s page has Set up under its head while there is no key, and Run setup again once there is', (tester) async {
      await pumpSettings(tester, SingleChildScrollView(child: ClaudePane(inApp: ClaudeInApp(settings: settings, phone: false), setup: PluginSetupCard(setup: setup()))), size: const Size(390, 3000));
      expect(find.byKey(const ValueKey('plugin-setup-card')), findsOneWidget);
      expect(find.text('Set up Claude'), findsOneWidget);
      // Under the page's head, over the In the app part.
      expect(tester.getTopLeft(find.byKey(const ValueKey('plugin-setup-card'))).dy, lessThan(tester.getTopLeft(find.text('In the app')).dy));
      await tester.tap(find.byKey(const ValueKey('plugin-setup-start')));
      await settleSettings(tester);
      expect(find.text('Claude, with your own key'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-skip')));
      await settleSettings(tester);
      await settings.setKey(key);
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('plugin-setup-card')), findsNothing);
      expect(find.byKey(const ValueKey('plugin-setup-again')), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('the app’s page builder puts Set up on it', (tester) async {
      await pumpSettings(tester, SingleChildScrollView(child: Builder(builder: claudePlugin.settings!.pane)), size: const Size(390, 4000));
      expect(find.byType(PluginSetupCard), findsOneWidget);
      await endSettings(tester);
    });
  });
}
