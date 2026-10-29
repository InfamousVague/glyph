/// Discord's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the
/// rest of the plugins"). Slack's (lib/plugins/slack/slack_setup.dart), in Discord's indigo, over the plugin's own
/// channels (channels.dart): a channel's webhook, made in Discord, is all there is to it. Ghost in Discord calls is
/// linked on the plugin's page with a code (calls_section.dart), and the last step says where.
///
/// 1. **Post notes to Discord**: what it does, and that only what is posted goes.
/// 2. **Make a webhook**: in Discord, a channel's Edit Channel › Integrations › Webhooks › New Webhook, then Copy
///    Webhook URL (channels.dart has the same path). Discord gives that page no address, so the button opens Discord's
///    own article on webhooks ([discordWebhooksHelpUrl]; unverified: not opened while this was written).
/// 3. **Add the channel**: a name of the person's own ([discordNameProblem]) and the webhook
///    ([discordWebhookProblem]), kept by [addDiscordChannel] as the page keeps them.
/// 4. **Send a test**: the page's own Test ([postToDiscord] with [discordTestText]), one short message. A webhook
///    Discord no longer knows is forgotten again if this setup added it, and pasted again ([discordSetupResult]).
/// 5. **Try it**: Post to Discord, on a note's cog; Link Discord, on this page, for Ghost in calls.
library;

import '../../art/lucide.g.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import 'channels.dart';
import 'discord_pane.dart' show discordTestText;
import 'manifest.dart' show DiscordFailure;

/// Discord's article on webhooks (unverified).
const String discordWebhooksHelpUrl = 'https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks';

/// The check's answer (see the header): a test sent to [channel], the last added where null. [added] is whether this
/// setup added it; [post] the plugin's own [postToDiscord] where null.
Future<SetupResult> discordSetupResult({DiscordChannel? channel, bool added = false, Future<void> Function(DiscordChannel channel, String text)? post}) async {
  final list = discordChannels();
  final to = channel ?? (list.isEmpty ? null : list.last);
  if (to == null) return const SetupResult.failed('No channel is added yet. Paste its webhook first.', pasteAgain: true);
  try {
    await (post ?? postToDiscord)(to, discordTestText);
    return SetupResult.ok('Sent a test to ${to.name}. It’s there in Discord now.');
  } on DiscordFailure catch (failure) {
    // Discord's refusals as the plugin says them: this webhook will never post.
    final refused = {for (final status in const [403, 404]) discordAnswer(status, '')}.contains(failure.message);
    if (refused && added) {
      await forgetDiscordChannel(to.id);
      return SetupResult.failed('${failure.message} It was taken out again.', pasteAgain: true);
    }
    return SetupResult.failed(failure.message, pasteAgain: refused);
  }
}

/// Discord's setup (see the header). [post] is a test's own Discord.
PluginSetup discordSetup({Future<void> Function(DiscordChannel channel, String text)? post}) {
  // The channel this run of the setup added, for its check.
  DiscordChannel? added;
  return PluginSetup(
    id: 'discord',
    name: 'Discord',
    hues: const ['indigo', 'blue', 'purple'],
    tiles: const [Lucide.messageSquare, Lucide.send, Lucide.users, Lucide.link],
    ready: () => discordChannels().isNotEmpty,
    watch: onPluginStorage,
    about: 'A few short steps: a webhook from Discord for a channel, and a test message to be sure it posts.',
    again: 'The steps from the start: a channel’s webhook, and a test message.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Post notes to Discord',
        icon: Lucide.messageSquare,
        points: [
          (Lucide.send, 'Post a note, or a meeting’s summary, to a channel, from the note’s cog'),
          (Lucide.users, 'A meeting’s action items to the channel you choose, once it is written up'),
          (Lucide.lock, 'Only what you post goes, straight from this device, and it pings nobody'),
        ],
      ),
      const SetupOpen(id: 'webhook', title: 'Make a webhook', icon: Lucide.link, links: [SetupLink('How webhooks work', discordWebhooksHelpUrl, verified: false)]),
      SetupPaste(
        id: 'paste',
        title: 'Add the channel',
        icon: Lucide.clipboardPaste,
        fields: const [
          SetupField(id: 'name', label: 'Channel name', placeholder: '#launch', shape: discordNameProblem, secret: false),
          SetupField(id: 'webhook', label: 'Webhook', placeholder: 'https://discord.com/api/webhooks/…', shape: discordWebhookProblem),
        ],
        save: (values) async {
          try {
            added = await addDiscordChannel(values['name']!, values['webhook']!);
            return null;
          } on DiscordFailure catch (failure) {
            return failure.message;
          }
        },
      ),
      SetupCheck(
        id: 'check',
        title: 'Send a test',
        icon: Lucide.send,
        checking: 'Posting a test to Discord…',
        run: () {
          // Still listed: one let go of by a refused test is not tried again.
          final mine = added != null && discordChannelById(added!.id) != null ? added : null;
          return discordSetupResult(channel: mine, added: mine != null, post: post);
        },
      ),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
