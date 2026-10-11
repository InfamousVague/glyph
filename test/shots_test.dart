import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';

import 'support/render.dart';

/// Pictures of the app's screens, drawn with the real faces, for looking at without a phone:
/// `flutter test --update-goldens test/shots_test.dart`, then open `test/shots/`.
void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('the kit gallery, $theme', (tester) async {
      // Tall enough for the whole page in one picture.
      await pumpApp(tester, size: const Size(390, 3300), prefs: AppPreferences(theme: theme), ratio: 1.5);
      await shot(tester, 'gallery-$theme');
    });
  }
}
