import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/bottom_nudge.dart';
import 'package:ghost_md/guide/guide_models.dart';

import '../support/render.dart';

export '../support/render.dart';

/// The back stack a test's guide is under: `testBack.goBack()` is the phone's back gesture.
late BackStack testBack;

/// Puts [child] under the app's theme and a back scope of the test's own, at 390 x 844 with no insets, as the
/// page's reference measurements were taken (test/guide/fixtures, written by the scratch script the fixtures' header
/// names: the web app's own Guide mounted alone in Chromium on its dev server).
Future<void> pumpGuide(WidgetTester tester, Widget child, {Size size = const Size(390, 844), Preferences prefs = const Preferences(theme: 'light'), bool still = false}) async {
  testBack = BackStack();
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await pumpApp(tester, size: size, prefs: prefs, home: BackScope(stack: testBack, child: child));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
}

/// Waits for the pictures on the screen (the ghost in the first and last pages' bands), which a test's clock never
/// loads by itself.
Future<void> loadPictures(WidgetTester tester) async {
  for (final element in find.byType(Image, skipOffstage: false).evaluate().toList()) {
    final image = (element.widget as Image).image;
    await tester.runAsync(() => precacheImage(image, element));
  }
  await tester.pump();
}

/// In frames, as a phone would draw them.
Future<void> wait(WidgetTester tester, int ms) async {
  for (var left = ms; left > 0; left -= 50) {
    await tester.pump(Duration(milliseconds: left < 50 ? left : 50));
  }
}

/// Ends a test that drew with real shadows ([pumpApp] turns them on, and the binding checks the switch as it ends).
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// What the page measured for one screen: `name -> [{x, y, w, h, text, ...}]`.
Map<String, List<Map<String, dynamic>>> fixture(String name) {
  final read = jsonDecode(File('test/guide/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in read.entries)
      if (entry.value is List) entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
  };
}

/// Holds a rect to the one the page measured, to half a pixel. [width] and [height] false leave that side out, for
/// a paragraph, whose box on the page is as wide as its column and here as wide as its longest line.
void expectRect(Rect got, Map<String, dynamic> want, String what, {bool width = true, bool height = true, double by = 0.5}) {
  final x = (want['x'] as num).toDouble(), y = (want['y'] as num).toDouble(), w = (want['w'] as num).toDouble(), h = (want['h'] as num).toDouble();
  final wrong = <String>[
    if ((got.left - x).abs() > by) 'x ${got.left.toStringAsFixed(2)} for $x',
    if ((got.top - y).abs() > by) 'y ${got.top.toStringAsFixed(2)} for $y',
    if (width && (got.width - w).abs() > by) 'w ${got.width.toStringAsFixed(2)} for $w',
    if (height && (got.height - h).abs() > by) 'h ${got.height.toStringAsFixed(2)} for $h',
  ];
  expect(wrong, isEmpty, reason: what);
}

/// A random that always answers the nudge whose words the page happened to pick.
class PickedNudge implements math.Random {
  PickedNudge(String words) : _at = nudges.indexOf(words);
  final int _at;

  @override
  int nextInt(int max) => _at < 0 ? 0 : _at;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// The phone, as the model page reads it: a test sets what is here or coming and counts what was asked for.
class FakeGuideModels extends ChangeNotifier implements GuideModels {
  FakeGuideModels({this.offered = true, Set<String>? here, this.download, this.problem}) : here = here ?? {};

  @override
  bool offered;
  Set<String> here;
  @override
  GuideDownload? download;
  @override
  String? problem;
  final List<String> fetched = [];

  @override
  bool present(String id) => here.contains(id);

  @override
  void fetch(String id) => fetched.add(id);

  void told() => notifyListeners();
}

/// A bundle that reads the app's assets from the repository's own folder, as the built app's bundle holds them.
class DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final file = File(key);
    if (!file.existsSync()) throw FlutterError('No asset at $key');
    return ByteData.sublistView(file.readAsBytesSync());
  }
}
