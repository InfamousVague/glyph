import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';

import 'support/render.dart';

/// Pictures of the app's screens, drawn with the real faces, for looking at without a phone:
/// `flutter test --update-goldens test/shots_test.dart`, then open `test/shots/`.
void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['light', 'dark']) {
    testWidgets('the kit gallery, $theme', (tester) async {
      await pumpApp(tester, prefs: AppPreferences(theme: theme));
      await shot(tester, 'gallery-$theme');
    });
  }
}
