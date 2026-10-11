import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/looks/look.dart' show LookSheet;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case tool/blocks_reference.mjs measured on the web page.
class BlockFixture {
  BlockFixture(this.name, this.json);

  factory BlockFixture.read(String name) => BlockFixture(name, jsonDecode(File('$folder/$name.json').readAsStringSync()) as Map<String, dynamic>);

  static const String folder = 'test/editor/blocks/fixtures';

  final String name;
  final Map<String, dynamic> json;

  String get picture => '$folder/$name.png';
  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  bool get readOnly => json['readOnly'] as bool;
  int? get caret => json['caret'] as int?;
  int? get anchor => json['anchor'] as int?;

  /// How Mermaid answered on the page: `held` (not yet), `refused` (nothing to draw it), or null (it drew).
  String? get mermaid => json['mermaid'] as String?;
  double get width => (json['width'] as num).toDouble();
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get blocks => (json['blocks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get maths => (json['maths'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get colours => json['colours'] as Map<String, dynamic>;

  /// `coordsAtPos` for every position, where the case has them.
  List<Map<String, dynamic>> get coords => ((json['coords'] as List?) ?? const <dynamic>[]).cast<Map<String, dynamic>>();

  static Rect rect(Object? r) {
    final m = r! as Map<String, dynamic>;
    return Rect.fromLTRB((m['left'] as num).toDouble(), (m['top'] as num).toDouble(), (m['right'] as num).toDouble(), (m['bottom'] as num).toDouble());
  }

  /// A colour the page painted: red, green, blue and alpha, each of 255.
  static Color colour(Object? c) {
    final l = (c! as List).cast<num>();
    return Color.fromARGB(l[3].toInt(), l[0].toInt(), l[1].toInt(), l[2].toInt());
  }

  /// Every case the tool wrote, or those whose name has `only` in it.
  static List<String> names([String? only]) =>
      Directory(folder).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).where((name) => only == null || only.isEmpty || name.contains(only)).toList()..sort();
}

/// The fixture's note drawn as the page drew it: the same side of the page, code themes and text size, in a window
/// as wide as the page's and [tall], at two device pixels, the editor's box at the window's corner under
/// [boundary]. Answers the view.
///
/// [sheets] and [codeLight] are for a test that draws the note wrong on purpose: rules over the editor's own, and
/// another code theme than the page's.
Future<EditorView> pumpBlocks(WidgetTester tester, BlockFixture fixture, {required double tall, GlobalKey? boundary, List<Extension> more = const <Extension>[], List<LookSheet> sheets = const <LookSheet>[], String? codeLight}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: fixture.doc,
      // The page had the view's own extensions with `drawnMaths()` (which `noteExtensions` lists) and
      // `drawnMermaid()` (tool/blocks_reference.mjs).
      extensions: noteExtensions(display: fixture.display, readOnly: fixture.readOnly, more: <Extension>[drawnMermaid(), ...more]),
    ),
  );
  addTearDown(view.destroy);
  final prefs = AppPreferences(theme: fixture.theme, codeLight: codeLight ?? fixture.json['codeLight'] as String, codeDark: fixture.json['codeDark'] as String, noteFace: fixture.json['noteFace'] as String, textSize: fixture.json['textSize'] as String);
  await pumpApp(
    tester,
    size: Size(fixture.width, tall),
    prefs: prefs,
    ratio: 2,
    home: Builder(
      // One device pixel to the logical one for the layout, as the page's was (test/editor/view/support.dart): a
      // browser emulating two device pixels lays a border out in whole CSS pixels.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: fixture.width, child: SingleChildScrollView(child: EditorColumn(view: view, sheets: sheets))),
            ),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  if (fixture.caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(fixture.anchor ?? fixture.caret!, fixture.caret)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 20));
  return view;
}

/// The lines drawn, in document order.
List<RenderEditorLine> drawnLines(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

/// A line's box as the page measures a `.cm-line`: its border box, which leaves its margins out.
Rect borderBox(RenderEditorLine line) {
  final look = line.spec.look;
  final at = line.localToGlobal(Offset.zero);
  return Rect.fromLTRB(at.dx + look.marginStart, at.dy, at.dx + line.size.width - look.marginEnd, at.dy + line.size.height);
}

/// How far two rectangles are apart: the most of their four edges.
double apartOf(Rect a, Rect b) => [(a.left - b.left).abs(), (a.top - b.top).abs(), (a.right - b.right).abs(), (a.bottom - b.bottom).abs()].reduce((x, y) => x > y ? x : y);

/// How far two colours are apart: the most of their four channels, of 255. A colour nobody can see (no alpha) is
/// the same as any other such.
int coloursApart(Color a, Color b) {
  int of(double v) => (v * 255).round();
  if (of(a.a) == 0 && of(b.a) == 0) return 0;
  return [(of(a.r) - of(b.r)).abs(), (of(a.g) - of(b.g)).abs(), (of(a.b) - of(b.b)).abs(), (of(a.a) - of(b.a)).abs()].reduce((x, y) => x > y ? x : y);
}

String show(Rect r) => '[${_plain(r.left)},${_plain(r.top)} ${_plain(r.width)}x${_plain(r.height)}]';

String _plain(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
