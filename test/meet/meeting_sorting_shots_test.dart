// Pictures of where every meeting goes (Matt, 2026-10-26: "All meetings plugins should sort meetings to the same place
// on the recordings but have different settings"; lib/meet/ui/meeting_settings.dart), for the eye: Settings ›
// Recording with its Meetings card, in Advanced and in Simple, and the Google Meet, Zoom and Discord pages, each with
// only its own and the row Where meetings go, on a phone and the Mac's window, light and dark. Written only by
// `flutter test --update-goldens test/meet/meeting_sorting_shots_test.dart`, into build/feature-shots/meeting-sorting/
// (not committed).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
import 'support.dart';

const String _out = 'build/feature-shots/meeting-sorting';

void main() {
  setUpAll(loadAppFonts);
  final skip = !autoUpdateGoldenFiles;
  tearDown(() {
    usePlugins(createRegistry(const []));
    debugDefaultTargetPlatformOverride = null;
  });

  /// The app as it is drawn now, written to [name].png.
  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('$_out/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  // Each page by its Settings id, the picture's name, and whether it is drawn in Simple.
  const shots = [
    ('recording', 'recording', false),
    ('recording', 'recording-simple', true),
    ('plugin:google-meet', 'meet-page', false),
    ('plugin:zoom', 'zoom-page', false),
    ('plugin:discord', 'discord-page', false),
  ];

  for (final (where, size, mac) in [('phone', const Size(390, 2400), false), ('mac', const Size(1280, 1800), true)]) {
    for (final (id, name, simple) in shots) {
      testWidgets('$name on the $where, light and dark', skip: skip, (tester) async {
        final at = DateTime(2026, 10, 26, 9, 0).millisecondsSinceEpoch;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final registry = createRegistry(builtIn, store: MemorySwitches());
          registry.setEnabled('discord', true);
          usePlugins(registry);
          final meet = FakeMeet(now: () => at)..paging = true;
          final service = await FakeService.start(seed: seeded);
          final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
          await device.mailIn!.newAddress();
          meet.meetings.addAll([
            {'id': 'a', 'title': 'Roadmap review, Q4', 'url': 'https://meet.google.com/abc-defg-hij', 'kind': 'meet', 'startsAt': at + 86400000 + 18000000, 'endsAt': at + 86400000 + 21600000, 'state': 'booked', 'detail': null},
            {'id': 'd', 'title': 'Retro', 'url': null, 'kind': 'meet', 'startsAt': at - 86400000, 'endsAt': at - 84600000, 'state': 'done', 'detail': null},
            {'id': 'z1', 'title': 'Design sync', 'url': 'https://us06web.zoom.us/j/83512345678?pwd=AbC.1', 'kind': 'zoom', 'startsAt': at + 3 * 3600000, 'endsAt': at + 4 * 3600000, 'state': 'booked', 'detail': null},
            {'id': 'z2', 'title': 'Customer call', 'url': null, 'kind': 'zoom', 'startsAt': at - 2 * 86400000, 'endsAt': at - 2 * 86400000 + 2700000, 'state': 'done', 'detail': null},
          ]);
          // A meeting whose recording stayed on this phone, for the card's footer.
          device.notes.held['retro'] = Note(id: 'retro', body: '# Retro\n\nGhost was in this meeting on 25 Oct, 09:00 to 09:30.\n', createdAt: at - 86400000, updatedAt: at, source: NoteSource.capture, recordingMs: 30 * 60000, segments: const []);
          await pumpApp(
            tester,
            size: size,
            prefs: Preferences(
              theme: theme,
              experience: simple ? 'simple' : 'advanced',
              experienceChosen: true,
              meetings: {'retro': at - 86400000},
              syncMeetingRecordings: false,
              syncMeetingRecordingsChosen: true,
              more: const {'meetingNotes': {'d': 'retro'}},
            ),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(
                services: device.services,
                child: SettingsSheet(
                  open: true,
                  onClose: () {},
                  onOpenNote: (_) {},
                  // The phone's meeting service, so its own rows head the card as they do on a Fold.
                  features: SettingsFeatures(signedIn: true, meetings: !mac, meetingSound: true, canNotifyMeetings: true, tapes: 117120000),
                  toPage: SettingsTarget(id, nonce: 1),
                ),
              ),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          await snap(tester, '$name-$where-$theme');
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
