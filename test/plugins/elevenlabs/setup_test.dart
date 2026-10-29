// ElevenLabs' setup (lib/plugins/elevenlabs/elevenlabs_setup.dart; Matt, 2026-10-29: "add the voiceover onboarding for
// the rest of the plugins"): its steps and their addresses (unverified), the key kept where the page keeps it, the
// check through `GET /v1/user` in plain words (works, refused and let go of, a key that may not read the account,
// credits spent, no connection), and Set up at the head of the plugin's page. ElevenLabs is a ground of the test's
// own: nothing is asked of the network.
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/elevenlabs/elevenlabs.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';

import '../github/support.dart';

void main() {
  late TestGround ground;

  setUp(() {
    useStored(MemoryStored());
    ground = useGround((request) async => FetchResponse.json(200, {
          'subscription': {'tier': 'creator', 'character_count': 10, 'character_limit': 100000},
        }));
  });
  tearDown(() => usePluginGround(PluginGround()));

  Future<void> keep() => elevenLabsSetup().steps.whereType<SetupPaste>().single.save({'key': 'sk_abcdefghijklmnopqrstuvwxyz'}).then((_) {});
  Future<SetupResult> check() => elevenLabsSetup().steps.whereType<SetupCheck>().single.run();

  test('an intro, an account, a key made, pasted and checked, and a first thing to try', () {
    final setup = elevenLabsSetup();
    expect([for (final step in setup.steps) step.id], ['intro', 'account', 'key', 'paste', 'check', 'done']);
    final links = [for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.url, link.verified)];
    expect(links, [(elevenSignUpUrl, false), (elevenKeysUrl, false)]);
    final key = setup.steps.whereType<SetupPaste>().single.fields.single;
    expect(key.shape!('sk_ abc'), 'Paste the key alone: it has no spaces in it.');
    expect(key.shape!('sk_abc'), 'That key looks cut short. Copy all of it from ElevenLabs.');
    expect(elevenLabsPlugin.setup, isNotNull);
  });

  test('kept where the page keeps it, and needed until it is', () async {
    final setup = elevenLabsSetup();
    expect(setup.ready(), isFalse);
    await keep();
    expect(ground.secrets.held, {apiKeySecret: 'sk_abcdefghijklmnopqrstuvwxyz'});
    expect(setup.ready(), isTrue);
  });

  group('the check', () {
    test('works: one GET /v1/user, nothing spent', () async {
      await keep();
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your key works. ElevenLabs is ready to read your notes.'));
      expect([for (final asked in ground.asked) '${asked.method} ${asked.url.path}'], ['GET /v1/user']);
    });

    test('a key ElevenLabs refuses is let go of, and pasted again', () async {
      ground = useGround((request) async => FetchResponse.json(401, {'detail': {'code': 'invalid_api_key', 'message': 'Invalid API key'}}));
      await keep();
      final result = await check();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'ElevenLabs refused that key. Copy it again from your ElevenLabs profile, under API Keys.', true));
      expect(hasElevenKey(), isFalse);
    });

    test('a key that may not read the account is kept, with the page’s words', () async {
      ground = useGround((request) async => FetchResponse.json(401, {'detail': {'code': 'missing_permissions', 'message': 'The API key you used is missing the permission user_read.'}}));
      await keep();
      final result = await check();
      expect(result.kind, SetupCheckKind.warn);
      expect(result.words, startsWith('Kept. This key may not read your account'));
      expect(hasElevenKey(), isTrue);
    });

    test('credits spent: a warning, the key kept', () async {
      ground = useGround((request) async => FetchResponse.json(402, {'detail': {'code': 'insufficient_credits', 'message': 'Not enough credits.'}}));
      await keep();
      final result = await check();
      expect(result.kind, SetupCheckKind.warn);
      expect(result.words, startsWith('The key works, but ElevenLabs says the credits are spent: '));
      expect(hasElevenKey(), isTrue);
    });

    test('no connection: the client’s words, the key kept', () async {
      ground = useGround((request) async => throw const SocketException('down'));
      await keep();
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.failed, elevenUnreachable));
      expect(hasElevenKey(), isTrue);
    });

    test('with no key kept, asks for it, and asks ElevenLabs nothing', () async {
      final result = await check();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(ground.asked, isEmpty);
    });
  });

  testWidgets('the plugin’s page has Set up while there is no key', (tester) async {
    await pumpPane(tester, const ElevenLabsPane());
    expect(find.text('Set up ElevenLabs'), findsOneWidget);
    await away(tester);
  });
}
