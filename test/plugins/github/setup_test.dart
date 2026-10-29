// GitHub's setup (lib/plugins/github/github_setup.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest of
// the plugins"): its steps and their addresses (unverified), the token's shape, the token kept where the page keeps
// it, the check through `GET /user` in plain words (works, 401 let go of, another refusal, no connection), and Set up
// at the head of the plugin's page. GitHub is a ground of the test's own: nothing is asked of the network.
import 'dart:io' show SocketException;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/github/github.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';

import 'support.dart';

const String token = 'github_pat_11ABCDEFG0123456789_abcdefghijklmnop';

void main() {
  late TestGround ground;

  setUp(() {
    useStored(MemoryStored());
    ground = useGround((request) async => FetchResponse.json(200, {'login': 'octocat'}));
  });
  tearDown(() => usePluginGround(PluginGround()));

  Future<SetupResult> check() => githubSetup().steps.whereType<SetupCheck>().single.run();

  test('an intro, an account in Advanced, the token made, pasted and checked, and a first thing to try', () {
    final setup = githubSetup();
    expect([for (final step in setup.steps) step.id], ['intro', 'account', 'key', 'paste', 'check', 'done']);
    expect([for (final step in setup.stepsFor(simple: true)) step.id], ['intro', 'key', 'paste', 'check', 'done']);
    final links = [for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.url, link.verified)];
    expect(links, [(githubSignUpUrl, false), (githubTokenUrl, false), (githubClassicTokensUrl, false)]);
    expect(githubPlugin.setup, isNotNull);
  });

  test('a token’s shape: a fine-grained or a classic one, whole, alone', () {
    expect(githubTokenShape(token), isNull);
    expect(githubTokenShape('ghp_abcdefghijklmnopqrstuvwxyz0123456789'), isNull);
    expect(githubTokenShape('github_pat_ abc'), 'Paste the token alone: it has no spaces in it.');
    expect(githubTokenShape('sk-ant-api03-abcdefghijklmnop'), 'That doesn’t look like a GitHub token. Those start with github_pat_ or ghp_.');
    expect(githubTokenShape('ghp_abc'), 'That token looks cut short. Copy all of it from GitHub.');
  });

  test('kept where the page keeps it, and needed until it is', () async {
    final setup = githubSetup();
    expect(setup.ready(), isFalse);
    expect(await setup.steps.whereType<SetupPaste>().single.save({'token': token}), isNull);
    expect(ground.secrets.held, {tokenSecret: token});
    expect(githubToken(), token);
    expect(setup.ready(), isTrue);
  });

  group('the check', () {
    test('works: one GET /user with the token, and whose it is', () async {
      await setGithubToken(token);
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your token works. It is octocat’s.'));
      expect([for (final asked in ground.asked) '${asked.method} ${asked.url}'], ['GET https://api.github.com/user']);
      expect(header(ground.asked.single, 'Authorization'), 'Bearer $token');
    });

    test('a 401 is let go of, and the token pasted again', () async {
      ground = useGround((request) async => FetchResponse.json(401, {'message': 'Bad credentials'}));
      await setGithubToken(token);
      final result = await check();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(result.words, 'GitHub didn’t accept that token. Copy it again from GitHub: all of it, from github_pat_ to the end.');
      expect(githubToken(), isEmpty);
      expect(ground.secrets.held.values.whereType<String>(), isEmpty);
    });

    test('another refusal is the plugin’s own words, the token kept', () async {
      ground = useGround((request) async => FetchResponse.json(403, {'message': 'rate limited'}));
      await setGithubToken(token);
      final result = await check();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'GitHub is limiting requests right now. Try again in a while, or add a token.', false));
      expect(githubToken(), token);
    });

    test('no connection: says so, the token kept', () async {
      ground = useGround((request) async => throw const SocketException('down'));
      await setGithubToken(token);
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.failed, 'GitHub couldn’t be reached. Check the connection, then check again.'));
      expect(githubToken(), token);
    });

    test('with no token kept, asks for it, and asks GitHub nothing', () async {
      final result = await check();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(ground.asked, isEmpty);
    });
  });

  testWidgets('the plugin’s page has Set up while there is no token, and Run setup again once there is', (tester) async {
    await pumpPane(tester, const GitHubPane());
    expect(find.text('Set up GitHub'), findsOneWidget);
    await setGithubToken(token);
    await settle(tester);
    expect(find.byKey(const ValueKey('plugin-setup-again')), findsOneWidget);
    await away(tester);
  });
}
