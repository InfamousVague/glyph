import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/find_bar/find_bar.dart';
import 'package:ghost_md/editor/find_bar/find_marks.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/sliver.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case test/editor/find_bar/fixtures/reference.mjs measured on the web page.
class BarFixture {
  BarFixture(this.name, this.json);

  factory BarFixture.read(String name) => BarFixture(name, jsonDecode(File('test/editor/find_bar/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  String get now => json['now'] as String;
  String get theme => json['theme'] as String;
  String get initial => json['initial'] as String;
  int get current => json['current'] as int;
  List<List<dynamic>> get steps => (json['steps'] as List).cast<List<dynamic>>();
  List<List<dynamic>> get matches => (json['matches'] as List).cast<List<dynamic>>();
  Map<String, dynamic> get bar => json['bar'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get rows => (json['rows'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get controls => json['controls'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get marks => (json['marks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());

  static List<String> names() =>
      Directory('test/editor/find_bar/fixtures').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList()..sort();
}

/// A colour as the page's computed style writes it: `oklch(…)`, `rgb(…)`, `rgba(…)` or `color(srgb r g b / a)`.
Color pageColor(String css, Tokens t) {
  final numbers = RegExp(r'-?[\d.]+(?:e-?\d+)?').allMatches(css.replaceFirst('srgb', '')).map((m) => double.parse(m.group(0)!)).toList();
  if (css.startsWith('color(srgb')) return Color.from(alpha: numbers.length > 3 ? numbers[3] : 1, red: numbers[0], green: numbers[1], blue: numbers[2]);
  if (css.startsWith('rgb')) return Color.from(alpha: numbers.length > 3 ? numbers[3] : 1, red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255);
  return t.colorOf(css);
}

/// How far two colours are apart: the most of their channels, in steps of 255 (the alpha counted the same way).
double colorGap(Color a, Color b) => <double>[(a.r - b.r).abs(), (a.g - b.g).abs(), (a.b - b.b).abs(), (a.a - b.a).abs()].reduce((x, y) => x > y ? x : y) * 255;

/// The most any edge of `a` is from the same edge of `b`.
double rectGap(Rect a, Rect b) => <double>[(a.left - b.left).abs(), (a.top - b.top).abs(), (a.right - b.right).abs(), (a.bottom - b.bottom).abs()].reduce((x, y) => x > y ? x : y);

/// The bar's keys by the names the page's controls are measured under.
const Map<String, Key> barKeys = <String, Key>{
  'find': FindBarKeys.find,
  'count': FindBarKeys.count,
  'previous': FindBarKeys.previous,
  'next': FindBarKeys.next,
  'replace': FindBarKeys.replace,
  'done': FindBarKeys.done,
  'replaceWith': FindBarKeys.replaceWith,
  'replaceOne': FindBarKeys.replaceOne,
  'all': FindBarKeys.all,
  'said': FindBarKeys.said,
};

/// And by what the page's own test calls them: an `aria-label`, or a button's word.
const Map<String, Key> barLabels = <String, Key>{
  'Find': FindBarKeys.find,
  'Replace with': FindBarKeys.replaceWith,
  'Previous match': FindBarKeys.previous,
  'Next match': FindBarKeys.next,
  'Replace': FindBarKeys.replace,
  'Done': FindBarKeys.done,
  'All': FindBarKeys.all,
};

/// The text field inside one of the bar's fields.
Finder editableOf(Key field) => find.descendant(of: find.byKey(field), matching: find.byType(EditableText));

/// What the bar's count says.
String countSaid(WidgetTester tester) => tester.widget<Text>(find.descendant(of: find.byKey(FindBarKeys.count), matching: find.byType(Text))).data ?? '';

/// Whether one of the bar's buttons can be pressed.
bool enabled(WidgetTester tester, Key key) => tester.widget<GlacierPressable>(find.byKey(key).evaluate().single.widget is GlacierPressable ? find.byKey(key) : find.descendant(of: find.byKey(key), matching: find.byType(GlacierPressable))).onPressed != null;

/// The note with the bar over it, as the page was measured: a screen 390 x 844 at two device pixels, the editor's
/// box at the screen's corner and the bar resting on its foot. Answers the view. `scrolls` draws the note as the
/// note screen will, a sliver in a scroll view as tall as the screen, and answers its controller too.
Future<(EditorView, ScrollController?)> pumpBar(WidgetTester tester, String doc, {String initial = '', String theme = 'light', VoidCallback? onClose, bool scrolls = false, bool bar = true}) async {
  final view = EditorView(
    wholeDocument: !scrolls,
    state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[findBarExtensions, history()])),
  );
  addTearDown(view.destroy);
  final controller = scrolls ? ScrollController() : null;
  if (controller != null) addTearDown(controller.dispose);
  await pumpApp(
    tester,
    prefs: AppPreferences(theme: theme),
    ratio: 2,
    home: Builder(
      // The page was measured in a browser emulating two device pixels to one, where a border is a whole number of
      // CSS pixels (test/editor/view/support.dart): one device pixel to the logical one here, the picture at two.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Stack(
            children: <Widget>[
              if (scrolls)
                Positioned.fill(child: CustomScrollView(controller: controller, slivers: <Widget>[EditorSliver(view: view)]))
              else
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view))),
                ),
              if (bar) Positioned(left: 0, right: 0, bottom: 0, child: FindBar(view: view, initial: initial, onClose: onClose ?? () {})),
            ],
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await settle(tester);
  return (view, controller);
}

/// Past the bar's entrance and whatever a search asked the note to draw or scroll to.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Types `text` into one of the bar's fields, as a person would: the field focused, its words replaced.
Future<void> typeInto(WidgetTester tester, Key field, String text) async {
  await tester.enterText(editableOf(field), text);
  await settle(tester);
}

/// Presses one of the bar's buttons.
Future<void> press(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await settle(tester);
}

/// Takes the bar and the note away, and puts back the binding's own switch for shadows, which `pumpApp` turned on.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
