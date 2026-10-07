import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/root/ghost_root.dart';

import '../support/render.dart';

/// The app put together, as pictures: each is looked at beside the web app's own screen.
void main() {
  setUpAll(loadAppFonts);

  for (final (name, size) in [('phone', const Size(390, 844)), ('fold', const Size(840, 900))]) {
    for (final theme in ['dark', 'light']) {
      testWidgets('home, $name, $theme', (tester) async {
        await pumpApp(tester, size: size, prefs: Preferences(theme: theme), home: const GhostRoot(launch: false));
        await shot(tester, 'root-home-$name-$theme', settle: const Duration(seconds: 8));
      });
    }
  }
}
