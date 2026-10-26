import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:ghost_md/plugins/discord/manifest.dart' show host;
import 'package:ghost_md/plugins/host.dart';

import 'support.dart';

/// Discord's channels on this device (lib/plugins/discord/channels.dart; Matt, 2026-10-26: "Add a new plugin to post
/// notes to discord chats"): a pasted webhook held to Discord's shapes, the webhook kept as a secret before the name
/// is kept, the post one message that pings nobody, Discord's 429 waited when it is short, and its refusals said in a
/// sentence. Every request is answered by the fake; none reaches Discord.
void main() {
  final hook = webhookOf('123456789012345678');

  late FakeDiscord discord;

  setUp(() => discord = FakeDiscord());
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Matcher refuses(Object message) => throwsA(isA<DiscordFailure>().having((f) => f.message, 'message', message));

  group('a pasted webhook', () {
    test('is one Discord hands out: either host, ptb. and canary. too, with or without the API’s version', () {
      expect(discordWebhookProblem(hook), isNull);
      expect(discordWebhookProblem('  $hook  '), isNull);
      for (final host in ['discordapp.com', 'ptb.discord.com', 'canary.discord.com', 'canary.discordapp.com']) {
        expect(allowedDiscordWebhook(webhookOf('123456789012345678', host: host)), isTrue, reason: host);
      }
      expect(allowedDiscordWebhook(hook.replaceFirst('/api/', '/api/v10/')), isTrue);
    });

    test('is refused, in a sentence, for anything else', () {
      expect(discordWebhookProblem(''), 'Paste the webhook URL Discord gave you.');
      expect(discordWebhookProblem(hook.replaceFirst('https', 'http')), contains('never http://'));
      expect(discordWebhookProblem(hook.replaceFirst('discord.com', 'discord.com.evil.example')), contains('isn’t a Discord webhook'));
      expect(discordWebhookProblem(hook.replaceFirst('discord.com', 'evil-discord.com')), contains('isn’t a Discord webhook'));
      expect(discordWebhookProblem('https://example.com/api/webhooks/1/abc'), contains('isn’t a Discord webhook'));
      expect(discordWebhookProblem('https://hooks.slack.com/services/T0/B0/x'), contains('isn’t a Discord webhook'));
      for (final odd in [
        '$hook?wait=true',
        '$hook?thread_id=1',
        '$hook#x',
        '$hook/slack',
        '$hook/github',
        'https://discord.com/api/webhooks/123456789012345678',
        'https://discord.com/api/webhooks/notanumber/${'a' * 68}',
        'https://discord.com/api/channels/123456789012345678/messages',
        'https://discord.com/api/webhooks/123456789012345678/../../users/@me',
        'https://user@discord.com/api/webhooks/123456789012345678/${'a' * 68}',
        'https://discord.com/api/webhooks/123456789012345678/${'a' * 68} ',
      ]) {
        expect(allowedDiscordWebhook(odd), isFalse, reason: odd);
      }
      expect(discordWebhookProblem('$hook?wait=true'), contains('with nothing after it'));
    });
  });

  group('a channel', () {
    test('hands its webhook to the secure store and keeps only its name and id here', () async {
      final channel = await addDiscordChannel('  #launch ', hook);
      expect(channel.name, '#launch');
      expect(channel.id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(discord.ground.secrets.held, {'glyph-discord-webhook:${channel.id}': hook});
      expect(discordChannels(), [channel]);
      expect(discord.ground.kept.getItem('glyph-discord-channels'), isNot(contains('discord.com')));
      expect(discord.ground.asked, isEmpty, reason: 'nothing was asked of Discord to add it');
    });

    test('is not listed when the store refuses its webhook', () async {
      usePluginGround(PluginGround(stored: () => discord.ground.kept, secrets: _Refusing()));
      await expectLater(addDiscordChannel('#launch', hook), refuses(contains('couldn’t keep the Discord webhook')));
      expect(discordChannels(), isEmpty);
    });

    test('refuses a name that is empty or taken, and a webhook that is not one, before the store is asked', () async {
      await addDiscordChannel('#launch', hook);
      final before = {...discord.ground.secrets.held};
      await expectLater(addDiscordChannel('  ', hook), refuses(contains('Give the channel a name')));
      await expectLater(addDiscordChannel('#LAUNCH', hook), refuses('There is a channel called #LAUNCH already.'));
      await expectLater(addDiscordChannel('#ops', 'https://example.com/hook'), refuses(contains('isn’t a Discord webhook')));
      expect(discord.ground.secrets.held, before);
    });

    test('is renamed here alone, and forgotten in the store and here', () async {
      final launch = await addDiscordChannel('#launch', hook);
      final ops = await addDiscordChannel('#ops', webhookOf('223456789012345678'));
      final before = {...discord.ground.secrets.held};
      renameDiscordChannel(launch.id, '#ship-it');
      expect(() => renameDiscordChannel(launch.id, '#ops'), refuses(contains('already')));
      expect([for (final c in discordChannels()) c.name], ['#ship-it', '#ops']);
      expect(discord.ground.secrets.held, before);
      await forgetDiscordChannel(launch.id);
      expect(discord.ground.secrets.held.keys, ['glyph-discord-webhook:${ops.id}']);
      await forgetDiscordChannel(ops.id);
      expect(discord.ground.kept.getItem('glyph-discord-channels'), isNull);
      expect(discord.ground.secrets.held, isEmpty);
    });

    test('reaches only what its manifest lists', () async {
      expect(() => host.storage.get<Object?>('glyph-slack-channels', null), throwsA(isA<PluginPermissionError>()));
      expect(() => host.secrets.held('glyph-slack-webhook:abc'), throwsA(isA<PluginPermissionError>()));
      await expectLater(host.fetch(FetchRequest(method: 'POST', url: Uri.parse('https://hooks.slack.com/services/T0/B0/x'))), throwsA(isA<PluginPermissionError>()));
      expect(discord.ground.asked, isEmpty);
    });
  });

  group('a post', () {
    test('is one message to the webhook, by the channel’s id, that pings nobody and unfurls no link', () async {
      final launch = await addDiscordChannel('#launch', hook);
      await postToDiscord(DiscordChannel(id: launch.id, name: 'whatever the page calls it'), '## Hello @everyone');
      final request = discord.ground.asked.single;
      expect(isDiscordPost(request, hook), isTrue);
      expect(sentJson(request), {
        'content': '## Hello @everyone',
        'allowed_mentions': {'parse': <Object?>[]},
        'flags': 4,
      });
      expect(request.timeout, const Duration(seconds: 20));
    });

    test('is refused past 2000 characters, and for nothing at all, before Discord is asked', () async {
      final launch = await addDiscordChannel('#launch', hook);
      await expectLater(postToDiscord(launch, 'x' * 2001), refuses('That is too long for one Discord message.'));
      await expectLater(postToDiscord(launch, '  '), refuses('There is nothing to post.'));
      await postToDiscord(launch, 'x' * 2000);
      expect(discord.ground.asked, hasLength(1));
    });

    test('waits out a short 429 and tries again, at most twice', () async {
      final launch = await addDiscordChannel('#launch', hook);
      discord.answers
        ..add((429, '{"message": "You are being rate limited.", "retry_after": 0.35, "global": false}', const {}))
        ..add((429, '{}', const {'Retry-After': '2'}));
      await postToDiscord(launch, 'Hello');
      expect(discord.waited, const [Duration(milliseconds: 350), Duration(seconds: 2)]);
      expect(discord.ground.asked, hasLength(3));

      // Three in a row: the third is not waited for.
      discord.waited.clear();
      for (var i = 0; i < 3; i++) {
        discord.answers.add((429, '{"retry_after": 1}', const {}));
      }
      await expectLater(postToDiscord(launch, 'Hello'), refuses('Discord asked for fewer posts. Try again in a second.'));
      expect(discord.waited, hasLength(2));
    });

    test('does not wait out a long 429: it says how long', () async {
      final launch = await addDiscordChannel('#launch', hook);
      discord.answers.add((429, '{"message": "You are being rate limited.", "retry_after": 42.5, "global": true}', const {}));
      await expectLater(postToDiscord(launch, 'Hello'), refuses('Discord asked for fewer posts. Try again in 43 seconds.'));
      expect(discord.waited, isEmpty);
      expect(discord.ground.asked, hasLength(1));
    });

    test('says Discord’s refusals in a sentence', () {
      expect(discordAnswer(204, ''), isNull);
      expect(discordAnswer(200, '{}'), isNull);
      expect(discordAnswer(404, unknownWebhook), 'Discord no longer knows this webhook. Make a new one in Discord and add the channel again.');
      expect(discordAnswer(401, '{"message": "Invalid Webhook Token", "code": 50027}'), contains('no longer knows this webhook'));
      expect(discordAnswer(403, '{"code": 50013}'), contains('refused the post'));
      expect(discordAnswer(400, '{"message": "Invalid Form Body", "code": 50035}'), 'Discord couldn’t read the message.');
      expect(discordAnswer(502, '<html>Bad gateway</html>'), 'Discord had a problem. Try again in a moment.');
      expect(discordAnswer(418, ''), 'Discord answered 418.');
    });

    test('says why when the network fails, or the channel’s webhook is gone', () async {
      final launch = await addDiscordChannel('#launch', hook);
      useGround((request) async => throw const SocketLike());
      // The new ground has no webhook: it was the old one's store.
      await expectLater(postToDiscord(launch, 'Hello'), refuses(contains('isn’t on this device')));
      final ground = useGround((request) async => throw TimeoutException('slow'));
      await ground.secrets.write('glyph-discord-webhook:${launch.id}', hook);
      await expectLater(postToDiscord(launch, 'Hello'), refuses('Discord took too long to answer. Try again.'));
      final offline = useGround((request) async => throw const SocketLike());
      await offline.secrets.write('glyph-discord-webhook:${launch.id}', hook);
      await expectLater(postToDiscord(launch, 'Hello'), refuses('Discord couldn’t be reached. Check the connection.'));
      // A store written some other way is held to the shapes again.
      await offline.secrets.write('glyph-discord-webhook:${launch.id}', 'https://example.com/steal');
      await expectLater(postToDiscord(launch, 'Hello'), refuses(contains('isn’t a Discord webhook')));
    });

    test('is not made on an iPhone, where Slack is not either', () async {
      final launch = await addDiscordChannel('#launch', hook);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await expectLater(postToDiscord(launch, 'Hello'), refuses('Discord is not available on iOS yet.'));
      expect(discord.ground.asked, isEmpty);
    });
  });
}

class SocketLike implements Exception {
  const SocketLike();
}

/// A secure store that takes every write and keeps none of them.
class _Refusing extends MemorySecureStore {
  @override
  Future<void> write(String key, String? value) async {}
}
