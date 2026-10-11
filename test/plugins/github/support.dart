/// What the GitHub and Slack plugins' tests share: a ground of the test's own with recorded answers, a request as
/// the web tests read one, and a stage to draw a page of Settings or of a sheet on, at the place the web page was
/// measured in (tool notes in measured_test.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/sheet/flow.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import '../support.dart';

export '../../support/render.dart';
export '../support.dart' show TestGround, TestNote;

/// Puts a fresh ground under every plugin's host: memory for storage and secrets, and [answer] for the network.
TestGround useGround([Future<FetchResponse> Function(FetchRequest request)? answer]) {
  final ground = TestGround(answer: answer);
  usePluginGround(ground.ground);
  return ground;
}

/// A header of [request] by name, whatever its case; null without one (`new Headers(init.headers).get(name)`).
String? header(FetchRequest request, String name) {
  for (final MapEntry(:key, :value) in request.headers.entries) {
    if (key.toLowerCase() == name.toLowerCase()) return value;
  }
  return null;
}

/// The body [request] carried, read as JSON; null with none.
Object? sentJson(FetchRequest request) => request.body == null ? null : jsonDecode(request.text);

/// A plain-text answer, as GitHub's raw file contents are.
FetchResponse textAnswer(int status, [String text = '']) => FetchResponse(status, bytes: utf8.encode(text));

/// What the web page measured for a case: `name -> [{x, y, w, h, text, …}]` (`fixtures/<name>.json`).
Map<String, List<Map<String, Object?>>> webRects(String file) {
  final raw = (jsonDecode(File(file).readAsStringSync()) as Map).cast<String, Object?>();
  return {for (final MapEntry(:key, :value) in raw.entries) key: [for (final one in value as List) (one as Map).cast<String, Object?>()]};
}

double _n(Object? value) => (value as num).toDouble();

/// Holds [got] to the rectangle the page measured, to [by] (half a pixel): all of it, or the parts named in [parts]
/// (`x`, `y`, `w`, `h`), for a line of words whose box on the page is as wide as its column. [dy] and [dh] are how
/// much lower and taller the thing is known to be here than on the page, for a reason the caller gives.
void held(Rect got, Map<String, Object?> web, {String parts = 'xywh', required String what, double by = 0.5, double dy = 0, double dh = 0}) {
  final checks = {'x': (got.left, _n(web['x'])), 'y': (got.top - dy, _n(web['y'])), 'w': (got.width, _n(web['w'])), 'h': (got.height - dh, _n(web['h']))};
  for (final part in parts.split('')) {
    final (mine, theirs) = checks[part]!;
    expect((mine - theirs).abs(), lessThanOrEqualTo(by), reason: '$what: $part is $mine here and $theirs on the page (here $got, allowed $dy lower and $dh taller)');
  }
}

/// A page of Settings alone on a phone's screen, where the web page was measured: `.settingsScreen__pane` with the
/// plugin's hue, at the screen's top, inside the gutters.
Future<void> pumpPane(WidgetTester tester, Widget pane, {String theme = 'light'}) async {
  await pumpApp(
    tester,
    prefs: Preferences(theme: theme),
    home: Builder(
      builder: (context) {
        final t = context.tokens;
        return Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: t.color('glacier-bg'),
            child: Align(
              alignment: Alignment.topLeft,
              child: GlacierScope(
                attrs: const {'hue': 'graphite'},
                child: SettingsPaneScope(
                  finder: SettingsFinder(),
                  child: SingleChildScrollView(padding: EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end')), child: pane),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await settle(tester);
}

/// A page of a sheet alone, where the web page was measured: the sheet's paper from the screen's top, its blocks
/// [at] from the corner (the sheet's border and padding) and [width] wide.
Future<void> pumpSheetPage(WidgetTester tester, Widget page, {String theme = 'light', double at = 23.31, double width = 343.38}) async {
  await pumpApp(
    tester,
    prefs: Preferences(theme: theme),
    home: Builder(
      builder: (context) {
        final t = context.tokens;
        return ColoredBox(
          color: t.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: ColoredBox(
              color: t.color('app-paper-2'),
              child: Padding(
                padding: EdgeInsets.all(at),
                child: SizedBox(width: width, child: CssFlow(children: [page])),
              ),
            ),
          ),
        );
      },
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await settle(tester);
}

/// Past the arrivals, and whatever a tap set going.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Ends a test that drew with real shadows (pumpApp turns them on, and the binding checks the switch as it ends).
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// The word to press called [word] (a `RowAction`), inside [within] when given.
Finder action(String word, [Finder? within]) {
  final found = find.widgetWithText(RowAction, word);
  return within == null ? found : find.descendant(of: within, matching: found);
}

/// Whether the word called [word] can be pressed.
bool actionEnabled(WidgetTester tester, String word) => !tester.widget<RowAction>(action(word)).disabled;

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Every word drawn, run together: the page's `textContent`.
String textOf(WidgetTester tester) => [
      for (final text in tester.widgetList<RichText>(find.byType(RichText, skipOffstage: false))) text.text.toPlainText(),
    ].join('\n');
