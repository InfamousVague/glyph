import 'package:flutter/widgets.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart' show MeetingsSlackSection, addChannel, slackPlugin;
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import 'support.dart';

/// Post to Discord, on the Discord page since Settings › Meetings became the meeting plugins' pages
/// (lib/plugins/discord/meetings_section.dart, discord_pane.dart; Matt, 2026-10-26): drawn only with a channel, the
/// switch off until a channel is chosen, Simple's More, beside Slack's section, and a meeting that did not post said
/// with Discord's reason and Try now.
void main() {
  setUpAll(loadAppFonts);

  final hook = webhookOf('123456789012345678');

  late FakeDiscord discord;
  late Registry before;

  setUp(() {
    discord = FakeDiscord();
    before = plugins;
    usePlugins(createRegistry([slackPlugin, discordPlugin], store: MemorySwitches({'discord': true, 'slack': true})));
  });

  tearDown(() {
    usePlugins(before);
    meetingDiscordPoster = null;
  });

  Finder switchOf(String label) => find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == label);
  Finder pick(String label) => find.byWidgetPredicate((w) => w is Pick && w.label == label);

  Future<void> pumpSection(WidgetTester tester, {bool simple = false}) async {
    await pumpPane(tester, PaneBody(children: [MeetingsSlackSection(prefs: preferences), MeetingsDiscordSection(prefs: preferences)]));
    if (simple) {
      preferences.value = preferences.value.choosing('simple');
      await settle(tester);
    }
  }

  testWidgets('is not drawn with no channel, nor with the plugin off', (tester) async {
    await pumpSection(tester);
    expect(textOf(tester), isNot(contains('Post to Discord')));
    await addDiscordChannel('#launch', hook);
    await settle(tester);
    expect(textOf(tester), contains('Post meetings to Discord'));
    plugins.setEnabled('discord', false);
    await settle(tester);
    expect(find.byType(GlacierSwitch), findsNothing);
    await away(tester);
  });

  testWidgets('is off until a channel is chosen, then on, with the share link on and its warning', (tester) async {
    await addDiscordChannel('#launch', hook);
    await addDiscordChannel('#ops', webhookOf('223456789012345678'));
    await pumpSection(tester);
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Discord')).checked, isFalse);
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Discord')).disabled, isTrue);
    expect(textOf(tester), contains('Choose a channel below first.'));
    expect(tester.widget<GlacierSwitch>(switchOf('Include a share link on Discord')).checked, isTrue);
    await press(tester, action('Choose'));
    await press(tester, pick('Post meetings to #ops on Discord'));
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Discord')).checked, isTrue);
    expect(textOf(tester), contains('go to #ops once, as soon as it is written up'));
    await tester.tap(switchOf('Include a share link on Discord'));
    await settle(tester);
    expect(discordMeetingSettings().share, isFalse);
    await away(tester);
  });

  testWidgets('sits under Post to Slack where both are set up, each with its own switch', (tester) async {
    await addChannel('#slack-launch', 'https://hooks.slack.com/services/T0/B0/abc');
    await addDiscordChannel('#launch', hook);
    await pumpSection(tester);
    final slack = tester.getTopLeft(find.text('Post meetings to Slack'));
    final ours = tester.getTopLeft(find.text('Post meetings to Discord'));
    expect(ours.dy, greaterThan(slack.dy));
    await tester.tap(switchOf('Post meetings to Discord'));
    await settle(tester);
    expect(postsMeetingsToDiscord(), isTrue);
    expect(tester.widget<GlacierSwitch>(switchOf('Post meetings to Slack')).checked, isFalse);
    await away(tester);
  });

  testWidgets('keeps the channel and the share link behind More in Simple', (tester) async {
    await addDiscordChannel('#launch', hook);
    await pumpSection(tester, simple: true);
    expect(switchOf('Post meetings to Discord'), findsOneWidget);
    expect(switchOf('Include a share link on Discord'), findsNothing);
    await press(tester, action('Show'));
    expect(switchOf('Include a share link on Discord'), findsOneWidget);
    await away(tester);
  });

  testWidgets('says a meeting that did not post, with Discord’s reason, and Try now posts it', (tester) async {
    await addDiscordChannel('#launch', hook);
    setDiscordMeetingPosts(true);
    var prefs = Preferences.defaults;
    final poster = meetingDiscordPoster = MeetingDiscordPoster(
      preferences: () => prefs,
      setPreferences: (change) => prefs = change(prefs),
      getNote: (id) async => Note(id: id, body: '# Standup\n\n## Summary\nA standup.\n\n- [ ] Ship it.', createdAt: 1, updatedAt: 1),
      kept: (_) => null,
    );
    discord.refuse = (404, unknownWebhook);
    await tester.runAsync(() => poster.meetingSummarized('n1', '# Standup'));
    await pumpSection(tester);
    expect(textOf(tester), contains('Not posted: “Standup”'));
    expect(textOf(tester), contains('Discord no longer knows this webhook'));
    expect(textOf(tester), contains('tried 1 of 5'));
    discord.refuse = null;
    await tester.runAsync(() async {
      await tester.tap(action('Try now'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(textOf(tester), isNot(contains('Not posted')));
    expect(discord.said.last, contains('- Ship it.'));
    await away(tester);
  });

  group('the Discord page', () {
    testWidgets('lists no channels, adds one by name and webhook, and refuses a webhook that is not one', (tester) async {
      await pumpPane(tester, const DiscordPane());
      expect(textOf(tester), contains('No channels yet'));
      await tester.enterText(find.byType(EditableText).first, '#launch');
      await tester.enterText(find.byType(EditableText).last, 'https://hooks.slack.com/services/T0/B0/x');
      await settle(tester);
      expect(textOf(tester), contains('That isn’t a Discord webhook.'));
      expect(actionEnabled(tester, 'Add it'), isFalse);
      await tester.enterText(find.byType(EditableText).last, hook);
      await settle(tester);
      expect(actionEnabled(tester, 'Add it'), isTrue);
      // Below the setup's card at the page's head.
      await tester.ensureVisible(action('Add it'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(action('Add it'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(textOf(tester), contains('Added #launch. Send it a test to be sure it posts.'));
      expect(discordChannels().single.name, '#launch');
      expect(textOf(tester), isNot(contains(hook)), reason: 'once kept, no page shows the webhook again');
      await tester.ensureVisible(action('Test'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(action('Test'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle(tester);
      expect(textOf(tester), contains('Sent a test to #launch.'));
      expect(discord.said, [discordTestText]);
      await away(tester);
    });

    testWidgets('has Post to Discord itself, where meetings are set to go', (tester) async {
      await addDiscordChannel('#launch', hook);
      await pumpPane(tester, const DiscordPane());
      expect(find.byType(MeetingsDiscordSection), findsOneWidget);
      expect(textOf(tester), contains('Post meetings to Discord'));
      expect(textOf(tester), isNot(contains('Settings › Meetings')));
      setDiscordMeetingPosts(true);
      await settle(tester);
      expect(textOf(tester), contains('#launch'));
      await away(tester);
    });
  });
}
