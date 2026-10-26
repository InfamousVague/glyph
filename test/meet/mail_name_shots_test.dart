// Pictures of a mail address of one's own name on Settings › Meetings' invite card (Matt, 2026-10-24: "i'd like you
// to add the ability to create our own custom name for the email if the name is available like
// matt@in.ghostmarkdown.com"), for the eye: written only by `flutter test --update-goldens
// test/meet/mail_name_shots_test.dart`, into build/feature-shots/mail-name/ (not committed), on a phone and the Mac's
// window, light and dark: a name available, a name taken, and the question before switching.
// Settings › Meetings is the Google Meet plugin's page since 2026-10-26 (lib/plugins/meetings/), which these draw now.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../account_ui/support.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final (where, size, mac) in [('phone', const Size(390, 1500), false), ('mac', const Size(1280, 1100), true)]) {
    for (final (state, typed) in [('available', 'matt'), ('taken', 'sam'), ('asking', 'matt')]) {
      testWidgets('$state on the $where, dark and light', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        final at = DateTime(2026, 10, 24, 9, 0).millisecondsSinceEpoch;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final meet = FakeMeet();
          final service = await FakeService.start(seed: seeded);
          service.mailNamesTaken.add('sam');
          usePlugins(createRegistry(builtIn, store: MemorySwitches()));
          addTearDown(() => usePlugins(createRegistry(const [])));
          final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
          await device.mailIn!.newAddress();
          await pumpApp(
            tester,
            size: size,
            prefs: Preferences(theme: theme),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: const SettingsTarget('plugin:google-meet', nonce: 1))),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          await tapKey(tester, 'meet-name-open');
          await settle(tester);
          await typeInto(tester, 'A name of your own for the address', typed);
          await tester.pump(meetNameSettle + const Duration(milliseconds: 20));
          await settle(tester);
          if (state == 'asking') {
            await tapKey(tester, 'meet-name-use');
            await settle(tester);
          }
          // The caret's blink and the settle of the sheet, out of the picture.
          FocusManager.instance.primaryFocus?.unfocus();
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/mail-name/$state-$where-$theme.png'));
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
