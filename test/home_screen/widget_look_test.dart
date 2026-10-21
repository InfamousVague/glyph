// The home-screen widgets' look (android/app/src/main/res, docs/WIDGETS_ANDROID.md) is the app's own: every colour, length
// and icon in those files is what tool/widget_look.dart makes of the stylesheets and the icons' paths as they are now.
//
//   GHOST_WRITE=1 flutter test test/home_screen/widget_look_test.dart    writes them again
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/widget_look.dart' as look;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final files = look.generate();

  if (Platform.environment['GHOST_WRITE'] == '1') {
    for (final MapEntry(key: path, value: text) in files.entries) {
      File(path).writeAsStringSync(text);
    }
  }

  for (final MapEntry(key: path, value: text) in files.entries) {
    test('$path is what the stylesheets and the icons make', () {
      final file = File(path);
      expect(file.existsSync() && file.readAsStringSync() == text, isTrue, reason: '$path has drifted: GHOST_WRITE=1 flutter test test/home_screen/widget_look_test.dart');
    });
  }

  test("an icon's path as Android reads it: an arc's flags each a number of their own", () {
    expect(look.androidPath('M20.001 19A2 2 0 0022 17V5a2 2 0 00-1.999-2z'), 'M 20.001 19 A 2 2 0 0 0 22 17 V 5 a 2 2 0 0 0 -1.999 -2 z');
    expect(look.androidPath('M12 2H12A3 3 0 0 1 15 5'), 'M 12 2 H 12 A 3 3 0 0 1 15 5');
    expect(look.androidPath('m.5.5-.62-.62'), 'm .5 .5 -.62 -.62');
  });

  test('the two looks are each other in reverse, and each attribute is a colour in every theme', () {
    final tokens = files['${look.res}/values/ghost_widget_tokens.xml']!, night = files['${look.res}/values-night/ghost_widget_tokens.xml']!;
    String colour(String name) => RegExp('<color name="$name">(#[0-9A-F]{8})</color>').firstMatch(tokens)!.group(1)!;
    expect(colour('ghost_w_light_paper'), '#FFFDFDFD');
    expect(colour('ghost_w_dark_paper'), '#FF040404');
    expect(colour('ghost_w_light_ink'), '#FF0D0D0D');
    expect(colour('ghost_w_dark_ink'), '#FFF3F3F3');
    expect(colour('ghost_w_dark_on_ink'), colour('ghost_w_dark_paper'), reason: 'what is drawn on the ink is the page');
    for (final (name, _, _) in look.colours) {
      expect(tokens.contains('<attr name="$name" format="color" />'), isTrue, reason: '$name an attribute');
      expect('<item name="$name">'.allMatches(tokens).length, 3, reason: '$name in Light, Dark and System');
      expect(night.contains('<item name="$name">@color/${look.colourIn('dark', name)}</item>'), isTrue, reason: '$name dark in the night System');
    }
  });
}
