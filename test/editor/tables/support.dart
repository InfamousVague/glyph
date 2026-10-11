import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case test/editor/tables/fixtures/reference.mjs measured on the web page.
class TableFixture {
  TableFixture(this.name, this.json);

  factory TableFixture.read(String name) => TableFixture(name, jsonDecode(File('test/editor/tables/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  String get noteFace => json['noteFace'] as String;
  String get textSize => json['textSize'] as String;
  bool get readOnly => json['readOnly'] as bool;
  int? get caret => json['caret'] as int?;

  /// How wide the page's editor came out: the screen's 390, or wider where a table would not fit, the growing
  /// editor on the page taking the table's width for its own.
  double get width => (json['width'] as num).toDouble();

  /// The screen the page was drawn on: a phone's 390, or the screen a case in a phone's own pixels says
  /// (`fixtures/phone/`, drawn by a Chromium launched at [ratio]: 475 is the Fold's cover screen at 2.625).
  double get screen => ((json['screen'] ?? 390) as num).toDouble();

  /// The device pixels to a CSS one the page was LAID OUT in: 1 for a case drawn by a browser told a scale to
  /// paint at (it lays out in whole CSS pixels), the phone's for one in `fixtures/phone/`.
  double get ratio => ((json['ratio'] ?? 1) as num).toDouble();
  bool get widened => (json['content'] as Map<String, dynamic>)['right'] != screen;
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get tables => (json['tables'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());

  static List<String> names() => <String>[
    for (final folder in const <String>['', 'phone/'])
      ...(Directory('test/editor/tables/fixtures/$folder').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => '$folder${f.uri.pathSegments.last.replaceAll('.json', '')}').toList()..sort()),
  ];
}

/// A note with its tables drawn, as the page drew it: a screen 390 x 844 at two device pixels, the editor's box at
/// the screen's corner (test/editor/view/support.dart's `pumpFixture`, with `drawnTables()` among the extensions).
Future<EditorView> pumpTables(
  WidgetTester tester,
  String doc, {
  String theme = 'light',
  String noteFace = 'maple',
  String textSize = 'large',
  NoteView display = NoteView.mixed,
  bool readOnly = false,
  int? caret,
  List<Extension> more = const <Extension>[],
  double screen = 390,
  double layoutRatio = 1,
}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(display: display, readOnly: readOnly, more: <Extension>[drawnTables(), ...more]),
    ),
  );
  addTearDown(view.destroy);
  // The input layer's part: asked for focus, the view has it.
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    size: Size(screen, 844),
    prefs: AppPreferences(theme: theme, noteFace: noteFace, textSize: textSize),
    ratio: layoutRatio == 1 ? 2 : layoutRatio,
    measuredAt: layoutRatio,
    home: Builder(
      // The page was measured in a browser emulating two device pixels to one, and lays out in whole CSS pixels
      // where a border is concerned: the editor is told one device pixel to the logical one, and the picture is
      // still taken at two (test/editor/view/support.dart).
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: layoutRatio),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: screen, child: SingleChildScrollView(child: EditorColumn(view: view))),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  return view;
}

Future<EditorView> pumpTableFixture(WidgetTester tester, TableFixture fixture) =>
    pumpTables(tester, fixture.doc, theme: fixture.theme, noteFace: fixture.noteFace, textSize: fixture.textSize, display: fixture.display, readOnly: fixture.readOnly, caret: fixture.caret, screen: fixture.screen, layoutRatio: fixture.ratio);

/// The lines drawn, in document order.
List<RenderEditorLine> drawnLines(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

/// The drawn tables' wraps, top to bottom.
List<Element> drawnWraps(WidgetTester tester) => find.byType(DrawnTable).evaluate().toList()..sort((a, b) => _top(a).compareTo(_top(b)));

double _top(Element element) => (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy;

/// A drawn table's own box (`table.cm-glyphTable`) inside its wrap.
RenderGlyphTable tableIn(WidgetTester tester, Element wrap) => tester.renderObject<RenderGlyphTable>(find.descendant(of: find.byElementPredicate((e) => identical(e, wrap)), matching: find.byType(GlyphTable)));

/// The first drawn table, or null when none is drawn.
RenderGlyphTable? drawnTable(WidgetTester tester) {
  final found = find.byType(GlyphTable);
  return found.evaluate().isEmpty ? null : tester.renderObject<RenderGlyphTable>(found.first);
}
