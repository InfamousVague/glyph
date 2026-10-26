// Pictures of Settings › Account and Settings › Meetings (Matt, 2026-10-24: "remove the meetings stuff from the account
// page the account settings page is overwhelming move all google meet related stuff to under the meet section"), for
// the eye: written only by `flutter test --update-goldens test/settings/meetings_settings_shots_test.dart`, into
// build/feature-shots/meetings-settings/ (not committed), on a phone and the Mac's window, light and dark. The same
// file run over the tree before the move with `--dart-define=SHOTS_AS=before` (less `onOpenNote`, which that tree's
// sheet did not take) writes the pictures to set beside them.
// Settings › Meetings is the Google Meet plugin's page since 2026-10-26 (lib/plugins/meetings/), which these draw now.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../account_ui/support.dart';
import '../meet/support.dart';

/// `before` over the tree before the move, `after` (the default) over this one.
const String shotsAs = String.fromEnvironment('SHOTS_AS', defaultValue: 'after');

void main() {
  setUpAll(loadAppFonts);

  for (final (where, size, mac) in [('phone', const Size(390, 2600), false), ('mac', const Size(1280, 2000), true)]) {
    for (final page in ['account', 'meetings']) {
      testWidgets('$page on the $where, dark and light', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final at = DateTime(2026, 10, 24, 9, 0).millisecondsSinceEpoch;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final meet = FakeMeet();
          final service = await FakeService.start(seed: seeded);
          usePlugins(createRegistry(builtIn, store: MemorySwitches()));
          addTearDown(() => usePlugins(createRegistry(const [])));
          final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
          await device.mailIn!.newAddress();
          meet.meetings.addAll([
            {'id': 'd', 'title': 'Retro', 'url': null, 'startsAt': at - 86400000, 'endsAt': at - 84600000, 'state': 'done', 'detail': null},
            {'id': 'e', 'title': 'Planning', 'url': null, 'startsAt': at - 3600000, 'endsAt': at - 1800000, 'state': 'done', 'detail': null},
            {'id': 'c', 'title': null, 'url': null, 'startsAt': at - 7200000, 'endsAt': at - 5400000, 'state': 'failed', 'detail': 'not_admitted'},
            {'id': 'a', 'title': 'Roadmap review, Q4', 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': at + 86400000 + 18000000, 'endsAt': at + 86400000 + 21600000, 'state': 'booked', 'detail': null},
          ]);
          device.notes.held['retro'] = Note(id: 'retro', body: '# Retro\n\nGhost was in this meeting on 23 Oct, 09:00 to 09:30.\n\n## Transcript\n\n**Sam:** Hello.\n', createdAt: at - 86400000, updatedAt: at, source: NoteSource.capture, recordingMs: 160 * 60000, segments: const []);
          await pumpApp(
            tester,
            size: size,
            prefs: Preferences(theme: theme, meetings: {'retro': at - 86400000}, more: const {'meetingNotes': {'d': 'retro'}}),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: SettingsTarget(page == 'meetings' ? 'plugin:google-meet' : page, nonce: 1))),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/meetings-settings/$shotsAs-$page-$where-$theme.png'));
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
