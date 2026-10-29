/// Slack's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest
/// of the plugins"). Lovart's shape, in Slack's magenta, over the plugin's own channels (channels.dart): Slack is
/// reached by a channel's incoming webhook, so there is nothing to sign in to, and the "key" is the webhook.
///
/// 1. **Post notes to Slack**: what it does, and that only what is posted goes.
/// 2. **Make a webhook**: Slack's apps ([slackAppsUrl]), where an app is made, Incoming Webhooks turned on and a
///    webhook added to a channel; Slack's own guide to them beside it ([slackWebhooksGuideUrl]). Neither address was
///    opened while this was written (unverified).
/// 3. **Add the channel**: a name of the person's own ("#launch", [nameProblem]) and the webhook ([webhookProblem]),
///    kept by [addChannel] exactly as the page keeps them: the webhook in the secure store, the name in the plugin's
///    storage, both sealed to the account's other devices.
/// 4. **Send a test**: Slack has no way to read a webhook back, so the check is the page's own Test
///    ([postToChannel] with [slackTestText]): one short message in the channel. Said in plain words
///    ([slackSetupResult]); a webhook Slack refuses is forgotten again if this setup added it, and pasted again.
/// 5. **Try it**: Post to Slack, on a note's cog.
library;

import '../../art/lucide.g.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import 'channels.dart';
import 'manifest.dart' show SlackFailure;
import 'slack_pane.dart' show slackTestText;

/// Slack's apps, where one is made with an incoming webhook (unverified).
const String slackAppsUrl = 'https://api.slack.com/apps';

/// Slack's guide to incoming webhooks (unverified).
const String slackWebhooksGuideUrl = 'https://api.slack.com/messaging/webhooks';

/// The check's answer (see the header): a test sent to [channel], the last added where null. [added] is whether this
/// setup added it, so a refused webhook may be let go of; [post] the plugin's own [postToChannel] where null.
Future<SetupResult> slackSetupResult({Channel? channel, bool added = false, Future<void> Function(Channel channel, String text)? post}) async {
  final to = channel ?? (channels().isEmpty ? null : channels().last);
  if (to == null) return const SetupResult.failed('No channel is added yet. Paste its webhook first.', pasteAgain: true);
  try {
    await (post ?? postToChannel)(to, slackTestText);
    return SetupResult.ok('Sent a test to ${to.name}. It’s there in Slack now.');
  } on SlackFailure catch (failure) {
    // Slack's refusals as the plugin says them: this webhook will never post.
    final refused = {for (final status in const [403, 404, 410]) slackAnswer(status, '')}.contains(failure.message);
    if (refused && added) {
      await forgetChannel(to.id);
      return SetupResult.failed('${failure.message} It was taken out again.', pasteAgain: true);
    }
    return SetupResult.failed(failure.message, pasteAgain: refused);
  }
}

/// Slack's setup (see the header). [post] is a test's own Slack.
PluginSetup slackSetup({Future<void> Function(Channel channel, String text)? post}) {
  // The channel this run of the setup added, for its check.
  Channel? added;
  return PluginSetup(
    id: 'slack',
    name: 'Slack',
    hues: const ['magenta', 'purple', 'rose'],
    tiles: const [Lucide.hash, Lucide.send, Lucide.users, Lucide.link],
    ready: () => channels().isNotEmpty,
    watch: onPluginStorage,
    about: 'A few short steps: a webhook from Slack for a channel, and a test message to be sure it posts.',
    again: 'The steps from the start: a channel’s webhook, and a test message.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Post notes to Slack',
        icon: Lucide.hash,
        mark: false,
        points: [
          (Lucide.send, 'Post a note, or a meeting’s summary, to a channel, from the note’s cog'),
          (Lucide.users, 'A meeting’s action items to the channel you choose, once it is written up'),
          (Lucide.lock, 'Only what you post goes, straight from this device'),
        ],
      ),
      const SetupOpen(
        id: 'webhook',
        title: 'Make a webhook',
        icon: Lucide.link,
        links: [SetupLink('Open Slack apps', slackAppsUrl, verified: false), SetupLink('How webhooks work', slackWebhooksGuideUrl, verified: false)],
      ),
      SetupPaste(
        id: 'paste',
        title: 'Add the channel',
        icon: Lucide.clipboardPaste,
        fields: const [
          SetupField(id: 'name', label: 'Channel name', placeholder: '#launch', shape: nameProblem, secret: false),
          SetupField(id: 'webhook', label: 'Webhook', placeholder: 'https://hooks.slack.com/services/…', shape: webhookProblem),
        ],
        save: (values) async {
          try {
            added = await addChannel(values['name']!, values['webhook']!);
            return null;
          } on SlackFailure catch (failure) {
            return failure.message;
          }
        },
      ),
      SetupCheck(
        id: 'check',
        title: 'Send a test',
        icon: Lucide.send,
        checking: 'Posting a test to Slack…',
        run: () {
          // Still listed: one let go of by a refused test is not tried again.
          final mine = added != null && channelById(added!.id) != null ? added : null;
          return slackSetupResult(channel: mine, added: mine != null, post: post);
        },
      ),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
