// Pictures of Settings › Meetings with its Post to Slack (lib/plugins/slack/meetings_section.dart; Matt, 2026-10-26:
// "make the meetings plugin work hand in hand to sending meeting action items and a link to the meeting transcript to
// a specified slack channel"), for the eye: written only by `flutter test --update-goldens
// test/settings/meetings_slack_shots_test.dart`, into build/feature-shots/meetings-slack/ (not committed), on a phone
// and the Mac's window, light and dark, advanced and simple, with a channel chosen and one meeting whose post failed.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../account_ui/support.dart';
import '../meet/support.dart';
import '../plugins/slack/support.dart' show FakeSlack;

void main() {
  setUpAll(loadAppFonts);

  for (final (where, size, mac) in [('phone', const Size(390, 2900), false), ('mac', const Size(1280, 2200), true)]) {
    for (final simple in [false, true]) {
      testWidgets('meetings with Post to Slack on the $where${simple ? ', simple' : ''}, dark and light', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final at = DateTime(2026, 10, 26, 9, 0).millisecondsSinceEpoch;
        final before = plugins;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final slack = FakeSlack();
          usePlugins(createRegistry([slackPlugin], store: MemorySwitches({'slack': true})));
          await tester.runAsync(() async {
            final launch = await addChannel('#launch', 'https://hooks.slack.com/services/T0/B0/abc');
            await addChannel('#ops', 'https://hooks.slack.com/services/T0/B0/ops');
            chooseMeetingChannel(launch.id);
            // One meeting whose post Slack refused.
            slack.refuse = (404, 'no_service');
            var prefs = Preferences.defaults;
            // The app's poster, so Try now is drawn as it is in the app.
            await (meetingSlackPoster = MeetingSlackPoster(
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
            prefs: Preferences(theme: theme, experience: simple ? 'simple' : 'advanced', experienceChosen: true),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: const SettingsTarget('meetings', nonce: 1))),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/meetings-slack/meetings-$where${simple ? '-simple' : ''}-$theme.png'));
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
          usePlugins(before);
          meetingSlackPoster = null;
        }
      });
    }
  }
}
