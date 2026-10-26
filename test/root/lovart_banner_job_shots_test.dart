// Pictures of Lovart's header images for the recent notes made as the app's own job, mid-run (lib/plugins/lovart/
// banner_run.dart; Matt, 2026-10-26: "Make the header generation async and a background task that runs while the app
// is generating the images"), for the eye: written only by `flutter test --update-goldens
// test/root/lovart_banner_job_shots_test.dart`, into build/feature-shots/lovart-banners-job/ (not committed): the
// line on home ("Making header images · 3 of 12", with Stop) and the Lovart page with the same run and its Stop, on a
// phone and the Mac's window, light and dark.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show SettingsFinder, SettingsPaneScope;
import 'package:glacier/glacier.dart';

import '../plugins/github/support.dart' show useGround;
import '../plugins/lovart/banners_test.dart' show GatedClient;
import '../support/render.dart';

const String _words = 'We drove down on Friday, stayed in the old house by the river, walked the market on Saturday morning, '
    'ate far too much at the corner place, and came home on Sunday with a bag of oranges and a plan to go back in spring.';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late GatedClient gated;

  setUp(() async {
    useGround();
    await lovart.host.secrets.write(lovart.accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(lovart.secretKeySecret, 'sk-1');
    lovartPictureStore = MemoryPictureStore();
    gated = GatedClient();
    lovartClient = () => gated;
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
    lovartBannerRun.value = null;
  });

  tearDown(() {
    gated.openAll();
    lovartPictureStore = null;
    lovartClient = () => LovartClient.kept();
    usePlugins(createRegistry(const []));
    debugDefaultTargetPlatformOverride = null;
  });

  /// A library of [count] notes to have a banner, the seeded ones given theirs already, and the run three in.
  SampleLibrary library(int count) {
    final it = SampleLibrary.seeded();
    lovart.host.storage.set(lovart.bannersDoneKey, [for (final note in it.value) note.id]);
    for (var i = 0; i < count; i += 1) {
      it.create('# Weekend away ${i + 1}\n\n$_words');
    }
    return it;
  }

  Future<void> threeIn(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i += 1) {
      gated.openOne();
      for (var j = 0; j < 10; j += 1) {
        await tester.pump();
      }
      await tester.pump();
    }
  }

  Future<void> picture(WidgetTester tester, String name) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/lovart-banners-job/$name.png'));
    gated.openAll();
    for (var i = 0; i < 40; i += 1) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }

  for (final (where, size, mac) in [('phone', const Size(390, 844), false), ('mac', const Size(1280, 800), true)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('the line on home mid-run, $where $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final notes = library(12);
        await pumpApp(
          tester,
          size: size,
          prefs: Preferences(theme: theme),
          home: GhostRoot(launch: false, library: notes, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
        );
        await tester.pump(const Duration(milliseconds: 100));
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        unawaited(lovartBannerJob!.start());
        await threeIn(tester);
        expect(find.textContaining('Making header images · 3 of 12', findRichText: true), findsWidgets);
        await picture(tester, 'home-$where-$theme');
      });

      testWidgets('the Lovart page mid-run, $where $theme', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final notes = library(12);
        lovartBannerJob = BannerJob(notes: () => notes.value, banners: LovartBanners(getNote: notes.get, update: notes.update));
        await pumpApp(
          tester,
          size: mac ? const Size(760, 1100) : const Size(390, 1100),
          prefs: Preferences(theme: theme),
          home: Builder(
            builder: (context) {
              final t = context.tokens;
              return Material(type: MaterialType.transparency, child: ColoredBox(
                color: t.color('glacier-bg'),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: GlacierScope(
                      attrs: const {'hue': 'graphite'},
                      child: SettingsPaneScope(
                        finder: SettingsFinder(),
                        child: SingleChildScrollView(padding: EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end'), top: t.space(6)), child: const LovartPane()),
                      ),
                    ),
                  ),
                ),
              ));
            },
          ),
        );
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        unawaited(lovartBannerJob!.start());
        await threeIn(tester);
        expect(find.textContaining('Making header images · 3 of 12'), findsOneWidget);
        await picture(tester, 'lovart-page-$where-$theme');
        lovartBannerJob = null;
      });
    }
  }
}
