import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../support/render.dart';

/// Pictures of Settings' list and its Appearance page, for the move of the mode's choice onto Appearance and of
/// Appearance up under Account (Matt, 2026-10-24: "move the simple or advanced toggle under appearance and move
/// appearnce up in the settings to under account"): the list and the page on a phone, and the split view a Mac draws,
/// in Advanced and in Simple, light and dark. Written to `build/feature-shots/settings-appearance/<stage>-*.png` to
/// be looked at, not held as goldens; `--dart-define=SHOTS=before` names the pictures of the tree before a change.
void main() {
  setUpAll(loadAppFonts);

  const stage = String.fromEnvironment('SHOTS', defaultValue: 'after');

  Future<void> snap(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i++) {
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
    File('build/feature-shots/settings-appearance/$stage-$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  /// Settings over an empty page with no notch, as settings_shots_test.dart draws it; on a Mac, as the Mac's.
  Future<void> open(WidgetTester tester, String theme, {required Size size, bool mac = false, bool simple = false, SettingsTarget? toPage}) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpApp(
      tester,
      size: size,
      prefs: Preferences(theme: theme, experience: simple ? 'simple' : 'advanced', experienceChosen: true),
      home: BackScope(child: SettingsSheet(open: true, onClose: () {}, toPage: toPage, split: mac)),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  const phone = Size(390, 844);
  const tallPhone = Size(390, 1500);
  const mac = Size(1280, 800);
  const appearance = SettingsTarget('theme', nonce: 1);

  for (final theme in ['light', 'dark']) {
    // The old link, `experience`: its own page before, Appearance with the Mode card lit after.
    testWidgets('the mode\'s link on a phone, $theme', (tester) async {
      await open(tester, theme, size: phone, toPage: const SettingsTarget('experience', nonce: 1));
      await snap(tester, 'mode-link-phone-$theme');
    });

    for (final simple in [false, true]) {
      final mode = simple ? 'simple' : 'advanced';

      testWidgets('the list on a phone, $mode, $theme', (tester) async {
        await open(tester, theme, size: phone, simple: simple);
        await snap(tester, 'list-phone-$mode-$theme');
      });

      testWidgets('Appearance on a phone, $mode, $theme', (tester) async {
        await open(tester, theme, size: tallPhone, simple: simple, toPage: appearance);
        await snap(tester, 'appearance-phone-$mode-$theme');
      });

      testWidgets('Appearance on a Mac, $mode, $theme', (tester) async {
        await open(tester, theme, size: mac, mac: true, simple: simple, toPage: appearance);
        await snap(tester, 'appearance-mac-$mode-$theme');
      });
    }
  }
}
