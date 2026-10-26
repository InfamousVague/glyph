// Pictures of the Discord plugin (lib/plugins/discord/; Matt, 2026-10-26: "Add a new plugin to post notes to discord
// chats"), for the eye: written only by `flutter test --update-goldens test/plugins/discord/discord_shots_test.dart`,
// into build/feature-shots/discord/ (not committed). Its page in Settings, with two channels and meetings posting to
// one, and Settings › Meetings with Post to Slack and Post to Discord one under the other, a meeting whose Discord
// post was refused; each on a phone and the Mac's window, light and dark. Nothing is posted anywhere: the webhooks
// are answered by the fakes.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/discord/discord.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart' show addChannel, chooseMeetingChannel, slackPlugin;
import 'package:ghost_md/settings/panes/plugins_pane.dart' show pluginPageId;
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../../account_ui/support.dart';
import '../../meet/support.dart';
import 'support.dart' show FakeDiscord, unknownWebhook, webhookOf;

void main() {
  setUpAll(loadAppFonts);

  for (final (page, target) in [('page', pluginPageId('discord')), ('meetings', 'meetings')]) {
    for (final (where, size, mac) in [('phone', Size(390, page == 'page' ? 1500 : 3300), false), ('mac', Size(1280, page == 'page' ? 1100 : 2500), true)]) {
      testWidgets('the Discord $page on the $where, dark and light', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final at = DateTime(2026, 10, 26, 9, 0).millisecondsSinceEpoch;
        final before = plugins;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final discord = FakeDiscord();
          usePlugins(createRegistry([slackPlugin, discordPlugin], store: MemorySwitches({'slack': true, 'discord': true})));
          await tester.runAsync(() async {
            final slack = await addChannel('#launch', 'https://hooks.slack.com/services/T0/B0/abc');
            chooseMeetingChannel(slack.id);
            final launch = await addDiscordChannel('#launch', webhookOf('123456789012345678'));
            await addDiscordChannel('#design-crit', webhookOf('223456789012345678'));
            chooseDiscordMeetingChannel(launch.id);
            // One meeting whose post Discord refused, so the row and its Try now are drawn.
            discord.refuse = (404, unknownWebhook);
            var prefs = Preferences.defaults;
            await (meetingDiscordPoster = MeetingDiscordPoster(
              preferences: () => prefs,
              setPreferences: (change) => prefs = change(prefs),
              getNote: (id) async => Note(id: id, body: '# Roadmap review\n\n## Summary\nA review.\n\n- [ ] Draft the plan.', createdAt: at, updatedAt: at),
              kept: (_) => null,
            )).meetingSummarized('roadmap', '# Roadmap review');
          });
          final meet = FakeMeet();
          final service = await FakeService.start(seed: seeded);
          final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
          await device.mailIn!.newAddress();
          await pumpApp(
            tester,
            size: size,
            prefs: Preferences(theme: theme, experience: 'advanced', experienceChosen: true),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: SettingsTarget(target, nonce: 1))),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../../build/feature-shots/discord/discord-$page-$where-$theme.png'));
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
          usePlugins(before);
          meetingDiscordPoster = null;
        }
      });
    }
  }
}
