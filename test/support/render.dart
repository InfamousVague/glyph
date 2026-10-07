import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/main.dart';
import 'package:glacier/glacier.dart';

/// A test draws text as boxes unless the faces are loaded by hand. This loads the app's own (pubspec.yaml) and each
/// package's icon font, so a picture taken in a test is the picture the phone draws.
Future<void> loadAppFonts() async {
  Future<void> family(String name, Iterable<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(File(file).readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }

  Future<void> pubspec(String path, {String prefix = '', String root = ''}) async {
    String? current;
    final found = <String, List<String>>{};
    for (final line in File(path).readAsLinesSync()) {
      final name = RegExp(r'^\s*- family:\s*(.+)$').firstMatch(line);
      final asset = RegExp(r'^\s*- asset:\s*(.+)$').firstMatch(line);
      if (name != null) current = name.group(1)!.trim();
      if (asset != null && current != null) found.putIfAbsent(current, () => []).add('$root${asset.group(1)!.trim()}');
    }
    for (final entry in found.entries) {
      await family('$prefix${entry.key}', entry.value);
    }
  }

  await pubspec('pubspec.yaml');
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final package in (config['packages'] as List).cast<Map<String, dynamic>>()) {
    if (package['name'] != 'lucide_icons_flutter') continue;
    final at = Uri.parse(package['rootUri'] as String).toFilePath();
    final root = at.endsWith('/') ? at : '$at/';
    await pubspec('${root}pubspec.yaml', prefix: 'packages/lucide_icons_flutter/', root: root);
  }
}

/// The app on a phone's screen (or [size]), ready for a picture: real fonts, real shadows, the token sheets the app
/// loads, and [prefs] as the person's choices. [home] puts one screen under the app's theme in place of the app's own.
Future<void> pumpApp(WidgetTester tester, {Size size = const Size(390, 844), AppPreferences prefs = const AppPreferences(theme: 'light'), double ratio = 2, Widget? home}) async {
  debugDisableShadows = false;
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
  tester.view.viewPadding = FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
  addTearDown(tester.view.reset);
  preferences.value = prefs;
  final sheet = await tester.runAsync(() => loadTokenSheet(more: appStyleSheets));
  await tester.pumpWidget(home == null ? GhostApp(sheet: sheet!) : GhostApp(sheet: sheet!, home: home));
  await tester.pump();
}

/// Writes or checks `test/shots/<name>.png` (`flutter test --update-goldens` writes). Call it last: it puts back the
/// test binding's own switch for shadows, which [pumpApp] turned on and the binding checks as a test ends.
Future<void> shot(WidgetTester tester, String name, {Duration settle = const Duration(seconds: 1)}) async {
  // Past the entrances, so the picture is the screen at rest; what loops (a working bar) is caught where it stands.
  for (var i = 0; i < 4; i++) {
    await tester.pump(settle ~/ 4);
  }
  await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
