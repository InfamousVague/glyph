// Pictures of Settings › Meetings with recurring meetings and a long history (Matt, 2026-10-24: "show recurring
// meetings in the meetings UI and paginate the meeting history"), for the eye: written only by
// `flutter test --update-goldens test/settings/meetings_recurring_shots_test.dart`, into
// build/feature-shots/meetings-recurring/ (not committed), on a phone and the Mac's window, light and dark, each before
// and after Show more: the Recurring card with two series (one on New York's clock, one ending), those to come, and
// forty-five meetings over across a fortnight, twenty at first.
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

void main() {
  setUpAll(loadAppFonts);

  for (final (where, size, mac) in [('phone', const Size(390, 5200), false), ('mac', const Size(1280, 4400), true)]) {
    testWidgets('recurring and the history on the $where, dark and light, before and after Show more', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      // Saturday 24 October 2026, 9:00.
      final at = DateTime(2026, 10, 24, 9, 0).millisecondsSinceEpoch;
      const hour = 3600000;
      int day(int d, int h, int m) => DateTime(2026, 10, d, h, m).millisecondsSinceEpoch;
      int offset(int ms) => DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset.inMinutes;
      for (final theme in ['light', 'dark']) {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final meet = FakeMeet(now: () => at)..paging = true;
        final service = await FakeService.start(seed: seeded);
        usePlugins(createRegistry(builtIn, store: MemorySwitches()));
        addTearDown(() => usePlugins(createRegistry(const [])));
        final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
        await device.mailIn!.newAddress();
        final standup = day(26, 9, 30);
        final planning = DateTime(2026, 11, 10, 11, 0).millisecondsSinceEpoch;
        meet.series.addAll([
          {
            'id': 'stand',
            'title': 'Engineering Standup',
            'rule': 'Every weekday at 9:30',
            'time': '09:30',
            'zone': 'Europe/London',
            'offset': offset(standup),
            'next': {'id': 'occ', 'startsAt': standup, 'endsAt': standup + hour ~/ 4, 'state': 'booked', 'joins': true},
            'until': null,
            'count': null,
          },
          {
            'id': 'plan',
            'title': 'Roadmap planning',
            'rule': 'Monthly on the 2nd Tuesday at 11:00',
            'time': '11:00',
            'zone': 'America/New_York',
            'offset': offset(planning) + 60,
            'next': {'id': 'occ2', 'startsAt': planning, 'endsAt': planning + hour, 'state': 'skipped', 'joins': false},
            'until': DateTime(2027, 6, 30).millisecondsSinceEpoch,
            'count': null,
          },
        ]);
        meet.meetings.addAll([
          {'id': 'occ', 'title': 'Engineering Standup', 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': standup, 'endsAt': standup + hour ~/ 4, 'state': 'booked', 'detail': null, 'series': 'stand'},
          {'id': 'one', 'title': 'Hiring sync', 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': day(27, 14, 0), 'endsAt': day(27, 15, 0), 'state': 'booked', 'detail': null},
          {'id': 'occ2', 'title': 'Roadmap planning', 'url': null, 'startsAt': planning, 'endsAt': planning + hour, 'state': 'skipped', 'detail': null, 'series': 'plan'},
        ]);
        // Forty-five over, three or four a working day back over a fortnight: the stand-up, and others.
        final titles = ['Design review', 'Retro', null, 'Customer call', 'Planning poker'];
        var n = 0;
        for (var back = 0; n < 45; back++) {
          final date = DateTime(2026, 10, 24 - back);
          if (date.weekday == DateTime.sunday) continue;
          for (final (h, m) in [(16, 0), (13, 30), (9, 30), (8, 0)]) {
            final start = DateTime(date.year, date.month, date.day, h, m).millisecondsSinceEpoch;
            if (start + hour > at || n >= 45) continue;
            final standupOne = h == 9;
            meet.meetings.add({
              'id': 'p${n.toString().padLeft(2, '0')}',
              'title': standupOne ? 'Engineering Standup' : titles[n % titles.length],
              'url': null,
              'startsAt': start,
              'endsAt': start + (standupOne ? hour ~/ 4 : hour),
              'state': n % 9 == 4 ? 'failed' : (n % 11 == 7 ? 'skipped' : 'done'),
              'detail': n % 9 == 4 ? 'not_admitted' : null,
              if (standupOne) 'series': 'stand',
            });
            n++;
          }
        }
        device.notes.held['retro'] = Note(id: 'retro', body: '# Retro\n\nGhost was in this meeting.\n\n## Transcript\n\n**Sam:** Hello.\n', createdAt: at, updatedAt: at, source: NoteSource.capture, recordingMs: 30 * 60000, segments: const []);
        await pumpApp(
          tester,
          size: size,
          prefs: Preferences(theme: theme, meetings: {'retro': at - hour}, more: const {'meetingNotes': {'p00': 'retro'}}),
          home: BackScope(
            stack: BackStack(),
            child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: const SettingsTarget('plugin:google-meet', nonce: 1))),
          ),
        );
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        await settle(tester, 12);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/meetings-recurring/before-$where-$theme.png'));
        await tapKey(tester, 'meet-more');
        await settle(tester, 12);
        await Scrollable.ensureVisible(tester.element(find.text('RECURRING')), alignment: 0);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/meetings-recurring/after-$where-$theme.png'));
        await endSettings(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
