/// What the Slack plugin's tests share: Slack's webhooks stood in for by a recorded `Fetcher`.
library;

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import '../github/support.dart';

export '../github/support.dart';

/// One post as Slack's webhook was asked it: where, and the message.
typedef Post = ({String url, Object? text});

/// Slack, on a fresh ground: every post it was sent, and what it answers (`ok`, unless [refuse] is set to a status
/// and the short code Slack would write).
class FakeSlack {
  FakeSlack() {
    ground = useGround((request) async {
      final refused = refuse;
      return refused == null ? textAnswer(200, 'ok') : textAnswer(refused.$1, refused.$2);
    });
    slackFelt = ([kind = HapticKind.light]) => felt.add(kind);
    setSlackReady(true);
    slackOrgs = SlackOrgs.none;
  }

  late final TestGround ground;
  (int, String)? refuse;
  final List<HapticKind> felt = [];

  /// The posts so far, in order.
  List<Post> get posts => [for (final request in ground.asked) (url: request.url.toString(), text: (sentJson(request) as Map?)?['text'])];

  /// The webhook kept for a channel, as the secure store has it.
  String? webhookOf(Channel channel) => ground.secrets.held['glyph-slack-webhook:${channel.id}'];
}

/// A request to Slack as the plugin must make it: a POST of JSON to the webhook, and to nowhere else.
bool isWebhookPost(FetchRequest request, String webhook) =>
    request.method == 'POST' && request.url.toString() == webhook && request.url.host == 'hooks.slack.com' && header(request, 'Content-Type') == 'application/json';
