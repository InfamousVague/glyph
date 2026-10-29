// Notion's setup (lib/plugins/notion/notion_setup.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest of
// the plugins"): its steps, the sign-in started by the plugin's own code, the check through the claim, the account and
// Notion's search, each outcome in plain words, and Set up at the head of the plugin's page. On a phone of the test's
// own (support.dart): glyph-api's claim and Notion's search are what each test recorded.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';

import '../github/support.dart' show away, pumpPane;
import 'support.dart';

const String api = 'https://ghostmarkdown.com/api/notion';

void main() {
  late Phone phone;

  setUp(() {
    useStored(MemoryStored());
    phone = Phone()..use();
  });
  tearDown(() {
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  SetupAct signIn() => notionSetup().steps.whereType<SetupAct>().single;
  Future<SetupResult> check() => notionSetup().steps.whereType<SetupCheck>().single.run();

  test('an intro, the sign-in, the check and a first thing to try', () {
    final setup = notionSetup();
    expect([for (final step in setup.steps) step.id], ['intro', 'signin', 'check', 'done']);
    expect([for (final step in setup.steps) step.runtimeType.toString()], ['SetupIntro', 'SetupAct', 'SetupCheck', 'SetupDone']);
    expect((signIn().label, signIn().again, signIn().onward), ('Sign in with Notion', 'Sign in again', false));
    expect(notionPlugin.setup, isNotNull);
  });

  test('is needed until the sign-in is kept', () async {
    final setup = notionSetup();
    await setup.prepare!();
    expect(setup.ready(), isFalse);
    await notionHost.secrets.write(accountSecret, accountJson());
    expect(setup.ready(), isTrue);
  });

  test('the sign-in is the plugin’s own: Notion’s consent page through ghostmarkdown.com; a build too old says so', () async {
    expect(await signIn().run(), isNull);
    expect(phone.opened.single, startsWith('$api/start?state='));
    expect(phone.requests, isEmpty);
    phone.generation = 11;
    resetNotionClient();
    expect(await signIn().run(), 'Notion needs the newest Ghost.md. Install it from Settings > Updates.');
    expect(phone.opened, hasLength(1));
  });

  group('the check', () {
    test('signed in and boards shared: the workspace by name and how many boards, nothing changed', () async {
      await signIn().run();
      phone.answer = (request) async => request.url.path.endsWith('/claim')
          ? json(200, {'accessToken': 'secret', 'refreshToken': 'r1', 'botId': 'b', 'workspaceId': 'w', 'workspaceName': 'Studio', 'workspaceIcon': null})
          : json(200, {
              'results': [database('b1', 'Roadmap'), database('b2', 'Bugs')],
            });
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Signed in to Studio, with 2 boards to send tasks to.'));
      expect([for (final request in phone.requests) '${request.method} ${request.url.path}'], ['POST /api/notion/claim', 'POST /v1/search']);
    });

    test('still on Notion’s page: says so, and asks the claim again next time', () async {
      await signIn().run();
      phone.answer = (request) async => json(202, {'pending': true});
      final result = await check();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, false));
      expect(result.words, 'Notion is still waiting for you. Pick the boards Ghost.md may use on Notion’s page, press Allow, then check again.');
    });

    test('signed in with no boards shared: a warning, signed in all the same', () async {
      phone.secrets.held[accountSecret] = accountJson(workspace: null);
      phone.answer = (request) async => json(200, {'results': <Object?>[]});
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.warn, 'Signed in to Notion, but no boards were shared. Sign in again and tick the boards you want on Notion’s page.'));
    });

    test('refused on Notion: the service’s words, and the way back to the sign-in', () async {
      await signIn().run();
      phone.answer = (request) async => json(400, {'error': 'The sign-in was cancelled on Notion.'});
      final result = await check();
      expect((result.kind, result.words, result.pasteAgain), (SetupCheckKind.failed, 'The sign-in was cancelled on Notion.', true));
    });

    test('collected already by the page, as the app came back: signed in, and the boards read', () async {
      phone.secrets.held[accountSecret] = accountJson();
      phone.answer = (request) async => json(200, {
            'results': [database('b1', 'Roadmap')],
          });
      expect((await check()).words, 'Signed in to Studio, with 1 board to send tasks to.');
    });

    test('never signed in: says so, and back to the sign-in; nothing asked', () async {
      final result = await check();
      expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
      expect(result.words, 'Ghost.md isn’t signed in to Notion yet. Sign in first.');
      expect(phone.requests, isEmpty);
    });

    test('signed in, with the boards not read just now: a warning in the plugin’s words', () async {
      phone.secrets.held[accountSecret] = accountJson();
      phone.answer = (request) async => json(500, {'message': 'Internal error'});
      final result = await check();
      expect((result.kind, result.words), (SetupCheckKind.warn, 'Signed in to Studio. The boards couldn’t be read just now: Internal error'));
    });
  });

  testWidgets('the plugin’s page has Set up at its head while signed out', (tester) async {
    phone.answer = (request) async => json(202, {'pending': true});
    await pumpPane(tester, const NotionPane());
    expect(find.byKey(const ValueKey('plugin-setup-card')), findsOneWidget);
    expect(find.text('Set up Notion'), findsOneWidget);
    expect(find.text('A few short steps: sign in with Notion, pick the boards Ghost.md may use, and a check that it worked.'), findsOneWidget);
    await away(tester);
  });
}
