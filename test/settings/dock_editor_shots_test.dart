import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../support/render.dart';

/// Pictures of Appearance's Dock card (Matt, 2026-10-27: "build the dock editor"), found by Settings' search as a
/// link lands on it: on a phone, in Advanced and in Simple, light and dark, as it comes and with a dock chosen.
/// Written to `build/feature-shots/dock-editor/*.png` to be looked at, not held as goldens.
void main() {
  setUpAll(loadAppFonts);

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
    File('build/feature-shots/dock-editor/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  final chosen = DockPrefs(phone: DockLayout.defaults.moved('search', 0).showing('market', false).showing('claude', false));

  for (final theme in ['light', 'dark']) {
    for (final simple in [false, true]) {
      for (final (named, dock) in [('default', DockPrefs.defaults), ('chosen', chosen)]) {
        final mode = simple ? 'simple' : 'advanced';
        testWidgets('the Dock card, $mode, $named, $theme', (tester) async {
          await pumpApp(
            tester,
            size: const Size(390, 844),
            prefs: Preferences(theme: theme, experience: mode, experienceChosen: true, dock: dock),
            home: BackScope(child: SettingsSheet(open: true, onClose: () {}, toPage: const SettingsTarget('theme', setting: 'Dock', nonce: 1))),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await tester.pump();
          await snap(tester, '$mode-$named-$theme');
        });
      }
    }
  }
}
