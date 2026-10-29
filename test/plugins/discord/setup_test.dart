// Discord's setup (lib/plugins/discord/discord_setup.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest
// of the plugins"): its steps and Discord's article (unverified), the channel added through the plugin's own
// addDiscordChannel, the check as the page's Test (one post), a webhook Discord no longer knows let go of and pasted
// again, and Set up at the head of the plugin's page. Discord is FakeDiscord (support.dart): nothing reaches Discord.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';

import 'support.dart';

void main() {
  late FakeDiscord discord;
  final hook = webhookOf('123456789012345678');

  setUp(() {
    useStored(MemoryStored());
    discord = FakeDiscord();
  });
  tearDown(() => usePluginGround(PluginGround()));

  test('an intro, the webhook made in Discord, the channel added, a test sent, and a first thing to try', () {
    final setup = discordSetup();
    expect([for (final step in setup.steps) step.id], ['intro', 'webhook', 'paste', 'check', 'done']);
    final links = [for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.url, link.verified)];
    expect(links, [(discordWebhooksHelpUrl, false)]);
    expect(setup.wordsOf(setup.steps[1], simple: false), contains('Edit Channel, then Integrations, then Webhooks'));
    expect(discordPlugin.setup, isNotNull);
  });

  test('adds the channel as the page does, refusing a webhook of another shape; then needed no more', () async {
    final setup = discordSetup();
    expect(setup.ready(), isFalse);
    final paste = setup.steps.whereType<SetupPaste>().single;
    expect(paste.fields.last.shape!('$hook?wait=true'), contains('with nothing after it'));
    expect(await paste.save({'name': '#launch', 'webhook': hook}), isNull);
    expect([for (final channel in discordChannels()) channel.name], ['#launch']);
    expect(setup.ready(), isTrue);
  });

  test('the check is the page’s Test: one post to the channel just added, pinging nobody', () async {
    final setup = discordSetup();
    await setup.steps.whereType<SetupPaste>().single.save({'name': '#launch', 'webhook': hook});
    final result = await setup.steps.whereType<SetupCheck>().single.run();
    expect((result.kind, result.words), (SetupCheckKind.ok, 'Sent a test to #launch. It’s there in Discord now.'));
    expect(discord.posts.single.url, hook);
    expect(discord.posts.single.body['content'], discordTestText);
    expect(discord.posts.single.body['allowed_mentions'], {'parse': <Object?>[]});
  });

  test('a webhook Discord no longer knows is let go of, if the setup added it, and pasted again', () async {
    final setup = discordSetup();
    await setup.steps.whereType<SetupPaste>().single.save({'name': '#launch', 'webhook': hook});
    discord.refuse = (404, unknownWebhook);
    final result = await setup.steps.whereType<SetupCheck>().single.run();
    expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
    expect(result.words, 'Discord no longer knows this webhook. Make a new one in Discord and add the channel again. It was taken out again.');
    expect(discordChannels(), isEmpty);
  });

  test('with no channel, asks for one, and posts nothing', () async {
    final result = await discordSetupResult();
    expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
    expect(discord.posts, isEmpty);
  });

  testWidgets('the plugin’s page has Set up while there is no channel', (tester) async {
    await pumpPane(tester, const DiscordPane());
    expect(find.text('Set up Discord'), findsOneWidget);
    await away(tester);
  });
}
