// Pictures of the Google Meet and Zoom plugins (lib/plugins/meetings/; Matt, 2026-10-26: "Make sure the Google Meet and
// the Zoom plugins are two different plugins", and the same day: "I want settings / meetings to be broken up into
// three plugins where each zoom, Google meets and discord handle their own meetings"), for the eye: each plugin's page
// in Settings over an account with meetings of both kinds, and each one's listing in the Market, on a phone and the
// Mac's window, light and dark. Written only by `flutter test --update-goldens test/plugins/meetings_shots_test.dart`,
// into build/feature-shots/meet-zoom-plugins/ (not committed).
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
import 'package:ghost_md/market/market_items.dart';
import 'package:ghost_md/market/market_screen.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../account_ui/support.dart';
import '../meet/support.dart';

const String _out = 'build/feature-shots/meet-zoom-plugins';

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

  for (final (where, size, mac) in [('phone', const Size(390, 2600), false), ('mac', const Size(1280, 2000), true)]) {
    for (final (id, name) in [('google-meet', 'meet'), ('zoom', 'zoom')]) {
      testWidgets('the $name page on the $where, light and dark', skip: skip, (tester) async {
        final at = DateTime(2026, 10, 26, 9, 0).millisecondsSinceEpoch;
        for (final theme in ['light', 'dark']) {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          usePlugins(createRegistry(builtIn, store: MemorySwitches()));
          final meet = FakeMeet(now: () => at)..paging = true;
          final service = await FakeService.start(seed: seeded);
          final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
          await device.mailIn!.newAddress();
          const zoomLink = 'https://us06web.zoom.us/j/83512345678?pwd=AbC.1';
          const meetLink = 'https://meet.google.com/abc-defg-hij';
          meet.meetings.addAll([
            {'id': 'a', 'title': 'Roadmap review, Q4', 'url': meetLink, 'kind': 'meet', 'startsAt': at + 86400000 + 18000000, 'endsAt': at + 86400000 + 21600000, 'state': 'booked', 'detail': null},
            {'id': 'd', 'title': 'Retro', 'url': null, 'kind': 'meet', 'startsAt': at - 86400000, 'endsAt': at - 84600000, 'state': 'done', 'detail': null},
            {'id': 'c', 'title': null, 'url': null, 'kind': 'meet', 'startsAt': at - 7200000, 'endsAt': at - 5400000, 'state': 'failed', 'detail': 'not_admitted'},
            {'id': 'z1', 'title': 'Design sync', 'url': zoomLink, 'kind': 'zoom', 'startsAt': at + 3 * 3600000, 'endsAt': at + 4 * 3600000, 'state': 'booked', 'detail': null},
            {'id': 'z2', 'title': 'Customer call', 'url': null, 'kind': 'zoom', 'startsAt': at - 2 * 86400000, 'endsAt': at - 2 * 86400000 + 2700000, 'state': 'done', 'detail': null},
            {'id': 'z3', 'title': 'Partner kickoff', 'url': null, 'kind': 'zoom', 'startsAt': at - 3 * 86400000, 'endsAt': at - 3 * 86400000 + 3600000, 'state': 'failed', 'detail': 'no_browser_join'},
          ]);
          device.notes.held['retro'] = Note(id: 'retro', body: '# Retro\n\nGhost was in this meeting on 25 Oct, 09:00 to 09:30.\n\n## Transcript\n\n**Sam:** Hello.\n', createdAt: at - 86400000, updatedAt: at, source: NoteSource.capture, recordingMs: 30 * 60000, segments: const []);
          device.notes.held['customer'] = Note(id: 'customer', body: '# Customer call\n\nGhost was in this meeting on 24 Oct, 09:00 to 09:45.\n\n## Transcript\n\n**Ana:** Thanks for joining.\n', createdAt: at - 2 * 86400000, updatedAt: at, source: NoteSource.capture, recordingMs: 45 * 60000, segments: const []);
          await pumpApp(
            tester,
            size: size,
            prefs: Preferences(theme: theme, meetings: {'retro': at - 86400000, 'customer': at - 2 * 86400000}, more: const {'meetingNotes': {'d': 'retro', 'z2': 'customer'}}),
            home: BackScope(
              stack: BackStack(),
              child: AccountScope(services: device.services, child: SettingsSheet(open: true, onClose: () {}, onOpenNote: (_) {}, toPage: SettingsTarget('plugin:$id', nonce: 1))),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await settle(tester, 12);
          await snap(tester, '$name-page-$where-$theme');
          await endSettings(tester);
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  for (final (where, size, mac) in [('phone', const Size(390, 1400), false), ('mac', const Size(1280, 900), true)]) {
    for (final theme in ['light', 'dark']) {
      for (final id in ['google-meet', 'zoom']) {
        testWidgets('the Market’s $id on the $where, $theme', skip: skip, (tester) async {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final registry = createRegistry(builtIn, store: MemorySwitches());
          await pumpApp(tester, size: size, prefs: Preferences(theme: theme), home: BackScope(child: MarketScreen(onBack: () {}, registry: registry, plugin: id, onPluginSettings: (_) {}, onLocalOnly: () {})));
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await tester.pump();
          await snap(tester, 'market-$id-$where-$theme');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          debugDisableShadows = true;
          debugDefaultTargetPlatformOverride = null;
        });
      }
      testWidgets('the Market’s plugins found by “meet” and “zoom” on the $where, $theme', skip: skip, (tester) async {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final registry = createRegistry(builtIn, store: MemorySwitches());
        await pumpApp(tester, size: size, prefs: Preferences(theme: theme), home: BackScope(child: MarketScreen(onBack: () {}, registry: registry, shelf: MarketShelf.plugins, onPluginSettings: (_) {}, onLocalOnly: () {})));
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        await tester.pump();
        // Connections, where the two are, beside Discord, GitHub, Notion, Slack and Webhooks.
        await tester.tap(find.text('Connections').first);
        await tester.pump(const Duration(milliseconds: 400));
        await snap(tester, 'market-connections-$where-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        debugDisableShadows = true;
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
