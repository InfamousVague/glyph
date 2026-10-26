/// What the Discord plugin's tests share: Discord's webhooks stood in for by a recorded `Fetcher`. Nothing here, or
/// in any test of the plugin, reaches Discord: every request is answered by [FakeDiscord].
library;

import 'dart:convert';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import '../github/support.dart';

export '../github/support.dart';

/// One post as Discord's webhook was asked it: where, and the body.
typedef DiscordPost = ({String url, Map<String, Object?> body});

/// Discord, on a fresh ground: every post it was sent, and what it answers (204, unless [answers] has the next
/// answer: a status, a body and headers, or [refuse] is set).
class FakeDiscord {
  FakeDiscord() {
    ground = useGround((request) async {
      if (answers.isNotEmpty) {
        final (status, body, headers) = answers.removeAt(0);
        return FetchResponse(status, headers: headers, bytes: utf8.encode(body));
      }
      final refused = refuse;
      return refused == null ? FetchResponse(204) : FetchResponse(refused.$1, bytes: utf8.encode(refused.$2));
    });
    discordFelt = ([kind = HapticKind.light]) => felt.add(kind);
    discordWait = (wait) async => waited.add(wait);
    discordKeptText = (_) => null;
    discordShareLink = null;
    discordCanShare = () => discordShareLink != null;
  }

  late final TestGround ground;

  /// What every post is answered with while it is set: a status and Discord's JSON body.
  (int, String)? refuse;

  /// Answers for the next posts, in order, before [refuse].
  final List<(int, String, Map<String, String>)> answers = [];
  final List<HapticKind> felt = [];

  /// The 429 waits the posts waited, in order.
  final List<Duration> waited = [];

  /// The posts so far, in order.
  List<DiscordPost> get posts => [for (final request in ground.asked) (url: request.url.toString(), body: (sentJson(request)! as Map).cast<String, Object?>())];

  /// What each post said.
  List<String> get said => [for (final post in posts) post.body['content']! as String];
}

/// A webhook of Discord's shape, by its id.
String webhookOf(String id, {String host = 'discord.com'}) => 'https://$host/api/webhooks/$id/${'aB3_-' * 13}x';

/// Discord's answer to a webhook that was deleted.
const String unknownWebhook = '{"message": "Unknown Webhook", "code": 10015}';

/// A request to Discord as the plugin must make it: a POST of JSON to the webhook, and to nowhere else.
bool isDiscordPost(FetchRequest request, String webhook) =>
    request.method == 'POST' && request.url.toString() == webhook && request.url.host.endsWith('discord.com') && header(request, 'Content-Type') == 'application/json';
