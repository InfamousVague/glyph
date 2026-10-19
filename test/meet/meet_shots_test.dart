// Pictures of Settings › Account › Ghost in meetings, for the eye (docs/MEET.md, "On the device"): written only by
// `flutter test --update-goldens test/meet/meet_shots_test.dart`, into build/feature-shots/meet/ (not committed), at the
// phone's size and the Fold's inner one, dark and light.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/ui_state.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';

import '../account_ui/support.dart';
import 'support.dart';

const Size fold = Size(900, 1000);
const Size phoneShot = Size(430, 932);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Ghost in meetings, phone and Fold, dark and light', (tester) async {
    if (!autoUpdateGoldenFiles) return;
    final at = DateTime(2026, 10, 18, 9, 0).millisecondsSinceEpoch;
    for (final (size, name) in [(phoneShot, 'phone'), (fold, 'fold')]) {
      for (final theme in ['dark', 'light']) {
        final meet = FakeMeet();
        final service = await FakeService.start(seed: seeded);
        final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
        await device.mailIn!.newAddress();
        meet.meetings.addAll([
          {'id': 'd', 'title': 'Retro', 'url': null, 'startsAt': at - 86400000, 'endsAt': at - 84600000, 'state': 'done', 'detail': null},
          {'id': 'c', 'title': null, 'url': null, 'startsAt': at - 7200000, 'endsAt': at - 5400000, 'state': 'failed', 'detail': 'not_admitted'},
          {'id': 'b', 'title': 'Standup', 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': at - 600000, 'endsAt': at + 600000, 'state': 'in_call', 'detail': null},
          {'id': 'a', 'title': 'Roadmap review, Q4', 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': at + 86400000 + 18000000, 'endsAt': at + 86400000 + 21600000, 'state': 'booked', 'detail': null},
        ]);
        await pumpApp(tester, size: size, ratio: 3, prefs: Preferences(theme: theme), home: BackScope(stack: BackStack(), child: AccountScope(services: device.services, child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: AccountPane(services: device.services))))));
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        await settle(tester, 12);
        await Scrollable.ensureVisible(tester.element(find.byType(MeetCard)), alignment: 0.05);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/meet/meet-card-$name-$theme.png'));
        await endSettings(tester);
      }
    }
  });
}
