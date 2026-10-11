import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/slack/manifest.dart' show host;
import 'package:ghost_md/plugins/slack/slack.dart';

import 'support.dart';

/// Slack's channels on this device: a pasted webhook judged by its shape, the webhook kept as a secret before the
/// name is kept, and the plugin's storage holding names and ids only. A port of
/// `src/app/plugins/slack/channels.test.ts`, case for case, and of the four tests of `src-tauri/src/slack.rs`,
/// whose work is channels.dart's here.
///
/// What differs: where the page's cases counted the commands handed to Rust, these read the secure store and the
/// requests Slack was sent.
void main() {
  const hook = 'https://hooks.slack.com/services/T0001/B0001/abcDEF123';

  late FakeSlack slack;

  setUp(() => slack = FakeSlack());

  Matcher refuses(Object message) => throwsA(isA<SlackFailure>().having((f) => f.message, 'message', message));

  group('a pasted webhook', () {
    test('is one Slack hands out: https, hooks.slack.com, services or workflows', () {
      expect(webhookProblem(hook), isNull);
      expect(webhookProblem('  $hook  '), isNull);
      expect(webhookProblem('https://hooks.slack.com/workflows/T0001/A0001/123/xyz'), isNull);
    });

    test('is refused, in a sentence, for anything else', () {
      expect(webhookProblem(''), 'Paste the webhook Slack gave you.');
      expect(webhookProblem('http://hooks.slack.com/services/T0/B0/x'), contains('never http://'));
      expect(webhookProblem('https://hooks.slack.com.evil.example/services/T0/B0/x'), contains('isn’t a Slack webhook'));
      expect(webhookProblem('https://example.com/services/T0/B0/x'), contains('isn’t a Slack webhook'));
      expect(webhookProblem('https://hooks.slack.com/api/chat.postMessage'), contains('isn’t a Slack incoming webhook'));
      expect(webhookProblem('https://hooks.slack.com/services/'), contains('isn’t a Slack incoming webhook'));
      expect(webhookProblem('https://hooks.slack.com/services/T0/B0/x?then=elsewhere'), contains('isn’t a Slack incoming webhook'));
      expect(webhookProblem('https://hooks.slack.com/services/../api/x'), contains('isn’t a Slack incoming webhook'));
    });
  });

  group('a channel', () {
    test('needs the newest binary and the app', () async {
      expect(await slackAvailable(), isTrue);
      // A ground that says this build is older than the manifest asks for.
      usePluginGround(PluginGround(stored: MemoryStored.new, hasNativeGeneration: (wanted) async => wanted < 25));
      expect(await slackAvailable(), isFalse);
      expect(slackReadyNow(), isFalse);
    });

    test('hands its webhook to the secure store and keeps only its name and id here', () async {
      final channel = await addChannel('  #launch ', hook);
      expect(channel.name, '#launch');
      expect(channel.id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(slack.ground.secrets.held, {'glyph-slack-webhook:${channel.id}': hook});
      expect(channels(), [channel]);
      expect(slack.ground.kept.getItem('glyph-slack-channels'), isNot(contains('hooks.slack.com')));
      // Nothing was asked of Slack to add it.
      expect(slack.ground.asked, isEmpty);
    });

    test('is not listed when the store refuses its webhook', () async {
      usePluginGround(PluginGround(stored: () => slack.ground.kept, secrets: _Refusing()));
      await expectLater(addChannel('#launch', hook), refuses('cannot keep the Slack webhook on this device.'));
      expect(channels(), isEmpty);
    });

    test('refuses a name that is empty or taken, and a webhook that is not one, before the store is asked', () async {
      await addChannel('#launch', hook);
      final before = {...slack.ground.secrets.held};
      await expectLater(addChannel('  ', hook), refuses(contains('Give the channel a name')));
      await expectLater(addChannel('#LAUNCH', hook), refuses('There is a channel called #LAUNCH already.'));
      await expectLater(addChannel('#ops', 'https://example.com/hook'), refuses(contains('isn’t a Slack webhook')));
      expect(slack.ground.secrets.held, before);
    });

    test('is renamed here alone, and forgotten in the store and here', () async {
      final launch = await addChannel('#launch', hook);
      final ops = await addChannel('#ops', hook);
      final before = {...slack.ground.secrets.held};
      renameChannel(launch.id, '#ship-it');
      expect(() => renameChannel(launch.id, '#ops'), refuses(contains('already')));
      expect([for (final c in channels()) c.name], ['#ship-it', '#ops']);
      expect(slack.ground.secrets.held, before, reason: 'a new name changes nothing of the webhooks');
      await forgetChannel(launch.id);
      expect(slack.ground.secrets.held.keys, ['glyph-slack-webhook:${ops.id}']);
      expect(channels(), [ops]);
      await forgetChannel(ops.id);
      expect(slack.ground.kept.getItem('glyph-slack-channels'), isNull);
      expect(slack.ground.secrets.held, isEmpty);
    });

    test('is posted to by its id, never by its webhook', () async {
      final launch = await addChannel('#launch', hook);
      // The caller names the channel; the webhook is read from the store for this post alone.
      await postToChannel(Channel(id: launch.id, name: 'whatever the page calls it'), '*Hello*');
      final request = slack.ground.asked.single;
      expect(isWebhookPost(request, hook), isTrue);
      expect(sentJson(request), {'text': '*Hello*'});
      expect(request.timeout, const Duration(seconds: 20));
    });

    test('reaches only what its manifest lists', () async {
      await expectLater(host.invoke<void>('notion_request'), throwsA(isA<PluginPermissionError>().having((e) => e.message, 'message', contains('didn\'t declare the native command “notion_request”'))));
      expect(() => host.storage.get<Object?>('glyph-notes', null), throwsA(isA<PluginPermissionError>()));
      expect(() => host.secrets.held('glyph-github-token'), throwsA(isA<PluginPermissionError>()));
      await expectLater(host.fetch(FetchRequest(method: 'POST', url: Uri.parse('https://example.com/collect'))), throwsA(isA<PluginPermissionError>()));
      expect(slack.ground.asked, isEmpty);
    });
  });

  // src-tauri/src/slack.rs's own tests, whose work is Dart here.
  group('what Rust did', () {
    test('only Slack’s webhooks are posted to', () {
      expect(allowedWebhook('https://hooks.slack.com/services/T000/B000/XXXXXXXX'), isTrue);
      expect(allowedWebhook('https://hooks.slack.com/workflows/T000/A000/123/abc_DEF-9'), isTrue);
      expect(allowedWebhook('http://hooks.slack.com/services/T000/B000/XXXX'), isFalse, reason: 'never in the clear');
      expect(allowedWebhook('https://hooks.slack.com.evil.example/services/T000/B000/XXXX'), isFalse);
      expect(allowedWebhook('https://evil.example/https://hooks.slack.com/services/T000'), isFalse);
      expect(allowedWebhook('https://user@hooks.slack.com/services/T000/B000/XXXX'), isFalse);
      expect(allowedWebhook('https://hooks.slack.com/api/chat.postMessage'), isFalse);
      expect(allowedWebhook('https://hooks.slack.com/services/'), isFalse, reason: 'a prefix alone is not a webhook');
      expect(allowedWebhook('https://hooks.slack.com/services/../api/T000'), isFalse);
      expect(allowedWebhook('https://hooks.slack.com/services/T000/B000/XXXX?redirect=evil'), isFalse);
      expect(allowedWebhook('https://hooks.slack.com/services/T000/B000/XXXX#x'), isFalse);
      expect(allowedWebhook('https://HOOKS.SLACK.COM/services/T000/B000/XXXX'), isFalse, reason: 'spelled as Slack hands it out');
      expect(allowedWebhook(' https://hooks.slack.com/services/T000/B000/XXXX'), isFalse, reason: 'trimmed before it is asked');
      expect(allowedWebhook('https://hooks.slack.com/services/${'a' * 257}'), isFalse);
      expect(allowedId('a1-b2'), isTrue);
      expect(allowedId('../x'), isFalse);
      expect(allowedId(''), isFalse);
      expect(allowedId('a' * 65), isFalse);
    });

    test('a webhook is kept trimmed by its id and forgotten whole', () async {
      final a = await addChannel('#a', ' https://hooks.slack.com/services/T0/B0/aaa ');
      final b = await addChannel('#b', 'https://hooks.slack.com/services/T0/B0/bbb');
      expect(slack.webhookOf(a), 'https://hooks.slack.com/services/T0/B0/aaa', reason: 'kept trimmed');
      expect(await keptWebhooks(), [a.id, b.id]);
      await forgetChannel(a.id);
      await expectLater(postToChannel(a, 'hello'), refuses(contains("isn't on this device")));
      await forgetChannel('nobody');
      await forgetChannel(b.id);
      expect(slack.ground.secrets.held, isEmpty, reason: 'the last one forgotten leaves nothing');
      expect(slack.ground.asked, isEmpty);
    });

    test('a store written some other way is held to the list too', () async {
      final channel = await addChannel('#launch', hook);
      slack.ground.secrets.held['glyph-slack-webhook:${channel.id}'] = 'https://evil.example/collect';
      await expectLater(postToChannel(channel, 'hello'), refuses(contains("isn't a Slack incoming webhook")));
      // A channel listed with nothing kept for it cannot post, and is not among those that can.
      slack.ground.secrets.held.clear();
      expect(await keptWebhooks(), isEmpty);
      await expectLater(postToChannel(channel, 'hello'), refuses(contains("isn't on this device")));
      expect(slack.ground.asked, isEmpty, reason: 'nothing was sent anywhere');
    });

    test('Slack’s answers are sentences', () {
      expect(slackAnswer(200, 'ok'), isNull);
      expect(slackAnswer(404, 'no_service'), startsWith('Slack no longer knows this webhook.'));
      expect(slackAnswer(410, 'channel_is_archived'), contains('archived'));
      expect(slackAnswer(403, 'action_prohibited'), startsWith('Slack refused the post.'));
      expect(slackAnswer(400, 'invalid_payload'), "Slack couldn't read the message.");
      expect(slackAnswer(429, ''), contains('Try again in a minute'));
      expect(slackAnswer(503, ''), startsWith('Slack had a problem.'));
      expect(slackAnswer(302, ''), 'Slack answered 302.', reason: 'a redirect is not a success');
    });

    test('a post that is refused, too long, or never answered says so', () async {
      final channel = await addChannel('#launch', hook);
      slack.refuse = (404, 'no_service\n');
      await expectLater(postToChannel(channel, 'hello'), refuses('Slack no longer knows this webhook. Make a new one in Slack and add the channel again.'));
      slack.refuse = null;
      slack.ground.asked.clear();
      await expectLater(postToChannel(channel, 'x' * 200001), refuses('That is too long for one Slack message.'));
      expect(slack.ground.asked, isEmpty);
      usePluginGround(PluginGround(stored: () => slack.ground.kept, secrets: slack.ground.secrets, fetch: (request) async => throw const FormatException('no route to host')));
      await expectLater(postToChannel(channel, 'hello'), refuses("Slack couldn't be reached. Check the connection."));
      usePluginGround(PluginGround(stored: () => slack.ground.kept, secrets: slack.ground.secrets, fetch: (request) async => throw TimeoutException('no answer')));
      await expectLater(postToChannel(channel, 'hello'), refuses('Slack took too long to answer. Try again.'));
    });
  });
}

/// A secure store that keeps nothing and says so.
class _Refusing implements SecureStore {
  @override
  Future<String?> read(String name) async => null;

  @override
  Future<void> write(String name, String? value) async => throw StateError('disk full');
}
