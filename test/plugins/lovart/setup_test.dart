// Lovart's setup (lib/plugins/lovart/lovart_setup.dart; Matt, 2026-10-28: "For each of the plugins add a small
// onboarding flow start with the lovart and Claude plugins walk the user through setting up an account and getting
// their keys and have the onboarding test setup to make sure it was successful"): its steps and their addresses, the
// keys pasted and kept where the page keeps them, the check through `POST /mode/query` said in the plugin's own words
// (works, 401, 402, no connection), the last step's switch, and Set up at the head of the plugin's page. Lovart is a
// ground of the test's own: nothing is asked of the network.
import 'dart:io' show SocketException;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' show host;
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../github/support.dart';

void main() {
  late TestGround ground;

  setUp(() => ground = useGround((request) async => FetchResponse.json(200, {'code': 0, 'data': {}})));
  tearDown(() => usePluginGround(PluginGround()));

  Future<void> keys() async {
    await host.secrets.write(accessKeySecret, 'ak-1');
    await host.secrets.write(secretKeySecret, 'sk-1');
  }

  group('the steps', () {
    test('an account, the keys, the check and a first try, at Lovart’s own addresses', () {
      final setup = lovartSetup();
      expect([for (final step in setup.steps) step.id], ['intro', 'account', 'keys', 'paste', 'check', 'done']);
      expect([for (final step in setup.steps) step.runtimeType.toString()], ['SetupIntro', 'SetupOpen', 'SetupOpen', 'SetupPaste', 'SetupCheck', 'SetupDone']);
      final links = [for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.label, link.url)];
      expect(links, [('Open lovart.ai', 'https://www.lovart.ai/'), ('Open Lovart', 'https://www.lovart.ai/home')]);
      expect(setup.wordsOf(setup.steps[2], simple: false), contains('Lovart Agent, then OpenClaw'));
      final intro = setup.steps.first as SetupIntro;
      expect(intro.points.last.$2, 'With your Lovart credits: about $lovartCreditsPerImage credits an image');
      expect(lovartPlugin.setup, isNotNull);
    });

    test('needs setting up until both keys are kept', () async {
      final setup = lovartSetup();
      expect(setup.ready(), isFalse);
      await keys();
      expect(setup.ready(), isTrue);
    });

    test('keeps the keys where the page keeps them, refusing one key twice and a key with spaces', () async {
      final paste = lovartSetup().steps.whereType<SetupPaste>().single;
      expect(paste.fields.first.shape!('ak 1'), 'Paste the key alone: it has no spaces in it.');
      expect(await paste.save({'access': 'ak-1', 'secret': 'ak-1'}), 'That is the same key twice: the secret key is the other one of the pair.');
      expect(ground.secrets.held, isEmpty);
      expect(await paste.save({'access': 'ak-1', 'secret': 'sk-1'}), isNull);
      expect(ground.secrets.held, {accessKeySecret: 'ak-1', secretKeySecret: 'sk-1'});
      expect(hasLovartKeys(), isTrue);
    });
  });

  group('the check', () {
    test('keys that work: one POST /mode/query, nothing spent, and “Your Lovart keys work.”', () async {
      await keys();
      final result = await lovartSetupResult();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your Lovart keys work.'));
      expect([for (final asked in ground.asked) '${asked.method} ${asked.url.path}'], ['POST /v1/openapi/mode/query']);
    });

    test('a 401 is the plugin’s own refusal, and the keys are let go of', () async {
      ground = useGround((request) async => FetchResponse.json(401, {'message': 'bad signature'}));
      await keys();
      final result = await lovartSetupResult();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'Lovart didn’t accept these keys. Copy both again from Lovart Agent › OpenClaw in Lovart.', true));
      expect(hasLovartKeys(), isFalse);
      expect(ground.secrets.held.values.whereType<String>(), isEmpty);
    });

    test('a 402 is Lovart’s own sentence, the keys kept, with the way back to Lovart', () async {
      ground = useGround((request) async => FetchResponse.json(402, {'code': 2012, 'message': 'Your plan does not include API access.'}));
      await keys();
      final result = await lovartSetupResult();
      expect((result.kind, result.words, result.link?.url), (SetupCheckKind.warn, 'Your plan does not include API access.', 'https://www.lovart.ai/home'));
      expect(hasLovartKeys(), isTrue);
      ground = useGround((request) async => FetchResponse.json(402, const {}));
      await keys();
      expect((await lovartSetupResult()).words, 'Lovart says your plan or credits don’t cover this.');
    });

    test('no connection is the client’s word for it, the keys kept', () async {
      ground = useGround((request) async => throw const SocketException('down'));
      await keys();
      final result = await lovartSetupResult();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, lovartUnreachable, false));
      expect(hasLovartKeys(), isTrue);
    });

    test('with no keys kept, asks for them', () async {
      final result = await lovartSetupResult();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(ground.asked, isEmpty);
    });
  });

  group('drawn', () {
    Finder field(String id) => find.descendant(of: find.byKey(ValueKey('setup-field-$id')), matching: find.byType(EditableText));

    testWidgets('pasted, kept and checked, then the last step’s switch is Header images for notes', (tester) async {
      final memory = SetupMemory(MemoryStored())..at('lovart', 'paste');
      await pumpPane(tester, PluginSetupSheet(setup: lovartSetup(), memory: memory, onClose: () {}));
      expect(find.text('Paste your keys'), findsOneWidget);
      await tester.enterText(field('access'), ' ak-typed ');
      await tester.enterText(field('secret'), 'sk-typed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settle(tester);
      expect(ground.secrets.held, {accessKeySecret: 'ak-typed', secretKeySecret: 'sk-typed'});
      expect(find.text('Your Lovart keys work.'), findsOneWidget);
      expect(textOf(tester), isNot(contains('sk-typed')));
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settle(tester);
      expect(find.text('Try it'), findsOneWidget);
      expect(find.text(lovartSampleCue), findsOneWidget);
      expect(bannersOn(), isTrue);
      await tester.ensureVisible(find.byKey(const ValueKey('lovart-try-banners')));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('lovart-try-banners')), matching: find.byType(GlacierSwitch)));
      await settle(tester);
      expect(bannersOn(), isFalse);
      expect(find.text('Off: banners are made only when you ask, from a note’s menu.'), findsOneWidget);
      // Nothing was made: the one request was the check.
      expect(ground.asked, hasLength(1));
      await away(tester);
    });

    testWidgets('a refused pair is said in the plugin’s words, and Paste again goes back for them', (tester) async {
      ground = useGround((request) async => FetchResponse.json(401, const {}));
      final memory = SetupMemory(MemoryStored())..at('lovart', 'paste');
      await pumpPane(tester, PluginSetupSheet(setup: lovartSetup(), memory: memory, onClose: () {}));
      await tester.enterText(field('access'), 'ak-wrong');
      await tester.enterText(field('secret'), 'sk-wrong');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settle(tester);
      expect(find.text('Lovart didn’t accept these keys. Copy both again from Lovart Agent › OpenClaw in Lovart.'), findsOneWidget);
      expect(hasLovartKeys(), isFalse);
      await tester.tap(find.byKey(const ValueKey('setup-paste-again')));
      await settle(tester);
      expect(find.text('Paste your keys'), findsOneWidget);
      await away(tester);
    });

    testWidgets('the plugin’s page has Set up while the keys are missing, and Run setup again once they are kept', (tester) async {
      await pumpPane(tester, const LovartPane());
      expect(find.byKey(const ValueKey('plugin-setup-card')), findsOneWidget);
      expect(find.text('Set up Lovart'), findsOneWidget);
      expect(find.byKey(const ValueKey('plugin-setup-again')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('plugin-setup-start')));
      await settle(tester);
      expect(find.byType(PluginSetupSheet), findsOneWidget);
      expect(find.text('Images by Lovart'), findsOneWidget);
      // Kept while the sheet is up (as from another device): the card turns to the row, and the sheet stays.
      await keys();
      await settle(tester);
      expect(find.byKey(const ValueKey('plugin-setup-card')), findsNothing);
      expect(find.byKey(const ValueKey('plugin-setup-again')), findsOneWidget);
      expect(find.byType(PluginSetupSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-skip')));
      await settle(tester);
      expect(find.byType(PluginSetupSheet), findsNothing);
      await tester.tap(find.text('Run'));
      await settle(tester);
      expect(find.text('Images by Lovart'), findsOneWidget);
      await away(tester);
    });

    testWidgets('left at its check, with keys from another device not read yet, opens there once they are, and checks once', (tester) async {
      // In the store, as the sync writes them, and not yet read by the host.
      await ground.secrets.write(accessKeySecret, 'ak-synced');
      await ground.secrets.write(secretKeySecret, 'sk-synced');
      final memory = SetupMemory(MemoryStored())..at('lovart', 'check');
      await pumpPane(tester, PluginSetupSheet(setup: lovartSetup(), memory: memory, onClose: () {}));
      expect(find.text('Check they work'), findsOneWidget);
      expect(find.text('Your Lovart keys work.'), findsOneWidget);
      expect(ground.asked, hasLength(1));
      await away(tester);
    });

    testWidgets('a setup left half way says Carry on', (tester) async {
      final memory = SetupMemory(MemoryStored())..at('lovart', 'keys');
      await pumpPane(tester, PluginSetupCard(setup: lovartSetup(), memory: memory));
      expect(find.text('Carry on'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plugin-setup-start')));
      await settle(tester);
      expect(find.text('Copy your keys'), findsOneWidget);
      await away(tester);
    });
  });
}
