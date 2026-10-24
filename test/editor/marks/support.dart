import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/syntax/language.dart' show InlineFormatSyntax;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// A case tool/editor_reference.mjs measured on the web page with the whole web `Editor`: its lines, and every
/// drawn thing of pieces E and F (`marks`).
class Measured {
  Measured(this.name, this.json);

  factory Measured.read(String folder, String name) => Measured(name, jsonDecode(File('test/editor/$folder/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  bool get readOnly => json['readOnly'] as bool;
  bool get peek => json['peek'] as bool;
  int? get caret => json['caret'] as int?;
  String get today => json['today'] as String;
  double get width => (json['width'] as num).toDouble();
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get drawn => (json['marks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get coords => (json['coords'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());
}

/// The case's note drawn as the page drew it, with `formats` and `more` over the base editor. Answers the view.
Future<EditorView> pumpMeasured(WidgetTester tester, Measured fixture, {bool shaders = false, Iterable<InlineFormatSyntax> formats = const <InlineFormatSyntax>[], List<Extension> more = const <Extension>[], bool reducedMotion = false}) async {
  // Before the view is made: its plugins ask for the kit themselves, on the test's own clock, where a load never
  // ends.
  // The heat's shader and the noise of every seed it uses: a picture wants them, a rectangle does not.
  if (shaders) await tester.runAsync(() => WispKit.load(seeds: const <int>[7, 8, 9, 10, 11, 12]));
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: fixture.doc,
      extensions: noteExtensions(formats: formats, display: fixture.display, readOnly: fixture.readOnly, more: more),
    ),
  );
  addTearDown(view.destroy);
  final prefs = AppPreferences(theme: fixture.theme, noteFace: fixture.json['noteFace'] as String, textSize: fixture.json['textSize'] as String);
  final Widget host = fixture.peek
      ? Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.only(top: context.tokens.space(2)),
            child: MarkdownView(markdown: fixture.doc, lines: null, formats: formats, extensions: more),
          ),
        )
      : EditorColumn(view: view);
  if (reducedMotion) {
    // `prefers-reduced-motion: reduce`, where the kit's theme reads it.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await pumpApp(
    tester,
    prefs: prefs,
    ratio: 2,
    home: Builder(
      // One device pixel to the logical one for the layout, as the page's was (test/editor/view/support.dart).
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: fixture.width, child: SingleChildScrollView(child: host)),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  if (fixture.caret != null && !fixture.peek) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(fixture.caret!)));
    await tester.pump();
  }
  // What is measured after the first draw (the text above heated words) and drawn on the next.
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
  return view;
}

List<RenderEditorLine> drawnLines(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

Rect borderBox(RenderEditorLine line) {
  final look = line.spec.look;
  final at = line.localToGlobal(Offset.zero);
  return Rect.fromLTRB(at.dx + look.marginStart, at.dy, at.dx + line.size.width - look.marginEnd, at.dy + line.size.height);
}

/// The rectangle of the text `from`-`to` as the page measures a `<span>` over it: across from its first letter to
/// its last on each visual line, and as tall as the face's own box there. One rectangle for each visual line.
List<Rect> spanRects(EditorView view, int from, int to) {
  final line = view.lineAt(from)!;
  final at = line.localToGlobal(Offset.zero);
  final rects = <Rect>[];
  for (final rect in line.rectsForRange(from - line.from, to - line.from)) {
    // The height of the letters there: `coordsAtPos` of a position on that visual line.
    Rect? tall;
    for (var pos = from; pos < to && tall == null; pos++) {
      final c = line.coordsAtPos(pos - line.from, 1);
      if (c != null && c.top >= rect.top - 0.01 && c.bottom <= rect.bottom + 0.01) tall = c;
    }
    rects.add(Rect.fromLTRB(rect.left + at.dx, (tall?.top ?? rect.top) + at.dy, rect.right + at.dx, (tall?.bottom ?? rect.bottom) + at.dy));
  }
  return rects;
}

double worst(Rect a, Rect b) => [(a.left - b.left).abs(), (a.top - b.top).abs(), (a.right - b.right).abs(), (a.bottom - b.bottom).abs()].reduce((x, y) => x > y ? x : y);
