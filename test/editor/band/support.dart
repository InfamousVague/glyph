import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/editor/band/band.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case test/editor/band/fixtures/reference.mjs measured on the web page.
class BandFixture {
  BandFixture(this.name, this.json);

  factory BandFixture.read(String name) => BandFixture(name, jsonDecode(File('test/editor/band/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  String get theme => json['theme'] as String;
  Size get window => Size(((json['window'] as Map)['width'] as num).toDouble(), ((json['window'] as Map)['height'] as num).toDouble());
  double get top => (json['top'] as num).toDouble();
  double get inset => (json['inset'] as num).toDouble();
  bool get readOnly => json['readOnly'] as bool;
  List<String> get props => (json['props'] as List).cast<String>();
  List<String> get press => (json['press'] as List).cast<String>();
  Object? get scroll => json['scroll'];
  int get anchor => json['anchor'] as int;
  int get head => json['head'] as int;
  String get text => json['text'] as String;
  String get label => json['label'] as String;
  Rect get caret => rect(json['caret'] as Map<String, dynamic>);
  Rect get row => rect((json['row'] as Map<String, dynamic>)['rect'] as Map<String, dynamic>);
  Map<String, dynamic> get rowJson => json['row'] as Map<String, dynamic>;
  Map<String, dynamic> get menu => json['menu'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get items => (json['items'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());

  static List<String> names() =>
      Directory('test/editor/band/fixtures').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList()..sort();
}

/// The twelve marks the web app ships switched on, as the Style page drew them (fixtures/style.json): each under
/// its own icon. The delimiters are stand-ins but for the two the tests write with; the marks' own are
/// lib/editor/marks'.
List<BandFormat> pageFormats() {
  final style = BandFixture.read('style');
  const known = <String, String>{'Spoiler': '||', 'Highlight': '=='};
  final formats = <BandFormat>[];
  for (final item in style.items) {
    final label = item['label'] as String;
    if (const <String>{'Back', 'Bold', 'Italic', 'Struck', 'Code'}.contains(label)) continue;
    if (label == 'Heading') break;
    formats.add(BandFormat(label, known[label] ?? '\u{1F47B}${formats.length}\u{1F47B}', Lucide.all[item['iconName'] as String]!));
  }
  return formats;
}

/// A clipboard a test made: what a read answers (or throws), and every word written to it.
class FakeClipboard extends BandClipboard {
  FakeClipboard({this.answer, this.refuses = false, this.readable = true});

  ClipRead? answer;
  bool refuses;

  @override
  bool readable;

  final List<String> written = <String>[];

  @override
  Future<ClipRead> read() async {
    if (refuses) throw StateError('NotAllowedError');
    return answer ?? (clip: const Clip(), read: false);
  }

  @override
  Future<void> write(String words) async => written.add(words);
}

/// A band over an editor on the app's own screen, as a test asks for it.
class BandRig {
  BandRig(this.view, this.controller, this.clipboard);

  final EditorView view;
  final ContextBandController controller;
  final FakeClipboard clipboard;

  /// Every tick the band said, in order.
  final List<HapticKind> felt = <HapticKind>[];

  /// Every sentence it said.
  final List<String> said = <String>[];

  String get text => view.state.doc.toString();
}

/// Draws an editor over [doc] with a band above it, [top] under the window's top, on a window of [size] with a
/// status bar [inset] high. The band's optional rows are those given.
Future<BandRig> pumpBand(
  WidgetTester tester, {
  required String doc,
  int anchor = 0,
  int? head,
  double top = 200,
  double inset = 0,
  double keyboard = 0,
  Size size = const Size(390, 844),
  String theme = 'light',
  bool readOnly = false,
  double uiScale = 1,
  FakeClipboard? clipboard,
  FutureOr<void> Function()? onAddImage,
  Future<void> Function(String path)? onPasteImage,
  void Function(String text)? onFind,
  BandSend? send,
  void Function(({int from, int to}) range)? onComment,
  List<BandFormat> formats = const <BandFormat>[],
  BandFields? fields,
  bool boards = false,
}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, selection: EditorSelection.single(anchor, head), extensions: noteExtensions(readOnly: readOnly)),
  );
  addTearDown(view.destroy);
  final controller = ContextBandController();
  addTearDown(controller.dispose);
  final rig = BandRig(view, controller, clipboard ?? FakeClipboard());
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme, uiScale: uiScale),
    ratio: 2,
    home: Builder(
      // The page was measured at one device pixel to the CSS one where a border is concerned (test/editor/view).
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(top: top),
                  child: ContextBand(
                    view: view,
                    controller: controller,
                    clipboard: rig.clipboard,
                    onAddImage: onAddImage,
                    onPasteImage: onPasteImage,
                    say: rig.said.add,
                    onFind: onFind,
                    send: send,
                    onComment: onComment,
                    formats: formats,
                    fields: fields,
                    boards: boards,
                    felt: rig.felt.add,
                    child: EditorColumn(view: view),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding(top: inset * 2);
  tester.view.viewPadding = FakeViewPadding(top: inset * 2);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  await tester.pump();
  return rig;
}

/// A press and hold, heard as the input layer will say it: the band over the caret.
Future<void> hold(WidgetTester tester, BandRig rig, {Offset finger = const Offset(20, 20)}) async {
  rig.controller.openAt(rig.view, finger);
  await settle(tester);
}

/// Past the band's entrance and a Style page's.
Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var left = ms; left > 0; left -= 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The band's rows, in order.
List<BandItemBox> rows(WidgetTester tester) => tester.widgetList<BandItemBox>(find.byType(BandItemBox)).toList();

/// The words along the band.
List<String> words(WidgetTester tester) => <String>[for (final row in rows(tester)) row.label];

/// The row that says [label], by its word or its accessible name.
Finder row(String label) => find.byWidgetPredicate((widget) => widget is BandItemBox && (widget.label == label || widget.name == label));

/// Presses a row and lets what it does - a clipboard, a picture - finish.
Future<void> choose(WidgetTester tester, String label) async {
  final found = tester.widget<BandItemBox>(row(label));
  found.onPress();
  await tester.pump();
  await settle(tester);
}

/// A row's border box, as the page measures a `button`: without the room a group leaves before it.
Rect rowBox(WidgetTester tester, Finder item) => tester.getRect(find.descendant(of: item, matching: find.byType(DecoratedBox)).first);

Rect iconBox(WidgetTester tester, Finder item) => tester.getRect(find.descendant(of: item, matching: find.byType(AppIcon)));

Rect wordBox(WidgetTester tester, Finder item) => tester.getRect(find.descendant(of: item, matching: find.byType(Text)));

/// Takes the app off the screen, and gives the binding its own switch for shadows back.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
