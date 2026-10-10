import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:glacier/glacier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A test draws text as boxes unless the faces are loaded by hand. This loads the app's own (pubspec.yaml), so a
/// picture taken in a test is the picture the phone draws. (The icons are drawn from their paths, lib/art, and
/// need no face.)
Future<void> loadAppFonts() async {
  // Storage that answers, and holds nothing: without it the preferences' first read asks the real device, which
  // never answers under a test's clock, and every test that draws the app hangs. A test that wants something kept
  // sets its own values after this (`SharedPreferences.setMockInitialValues`), before it draws.
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
  // KaTeX's faces, which a formula is drawn in (lib/editor/maths): the formula package's own, named as a
  // package's faces are.
  final packages = (jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>)['packages'] as List<dynamic>;
  for (final package in packages.cast<Map<String, dynamic>>()) {
    if (package['name'] != 'flutter_math_fork') continue;
    var root = Uri.parse(package['rootUri'] as String).toFilePath();
    if (!root.endsWith('/')) root = '$root/';
    await pubspec('${root}pubspec.yaml', prefix: 'packages/flutter_math_fork/', root: root);
  }
}

/// The app on a phone's screen (or [size]), ready for a picture: real fonts, real shadows, the token sheets the app
/// loads, and [prefs] as the person's choices. [home] puts one screen under the app's theme in place of the app's own.
///
/// [ratio] is the density the picture is drawn at. [measuredAt] is the device pixel ratio of the page the test's
/// rectangles were read from: the fixtures in this repo were measured in a desktop Chromium at 1, and a page rounds
/// a line of `line-height: normal` in device pixels, so the lines are rounded at that ratio and not at the
/// picture's. A test held to the phone's own page says the phone's (the emulator's is 2.625).
Future<void> pumpApp(WidgetTester tester, {Size size = const Size(390, 844), AppPreferences prefs = const AppPreferences(theme: 'light'), double ratio = 2, double measuredAt = 1, Widget? home}) async {
  debugDisableShadows = false;
  debugFixturePixelRatio = measuredAt;
  addTearDown(() => debugFixturePixelRatio = null);
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
  tester.view.viewPadding = FakeViewPadding(top: 36 * ratio, bottom: 20 * ratio);
  addTearDown(tester.view.reset);
  // The preferences as a launch leaves them on a device that has kept nothing, then the test's own choices over
  // them. No storage is asked: a plugin's answer never arrives on a test's clock, and nothing is kept between tests.
  preferences.startWithoutStorage();
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
