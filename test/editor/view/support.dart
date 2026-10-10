import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case tool/editor_reference.mjs measured on the web page.
class Fixture {
  Fixture(this.name, this.json);

  factory Fixture.read(String name) => Fixture(name, jsonDecode(File('test/editor/view/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  bool get readOnly => json['readOnly'] as bool;
  bool get peek => json['peek'] as bool;
  bool get whole => json['whole'] as bool;
  int? get caret => json['caret'] as int?;
  int? get anchor => json['anchor'] as int?;
  double get width => (json['width'] as num).toDouble();
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get blocks => (json['blocks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get coords => (json['coords'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get hits => (json['hits'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());

  /// Every base case the tool wrote (not the `full/` ones, which are the whole web editor's).
  static List<String> names() =>
      Directory('test/editor/view/fixtures').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList()..sort();
}

/// The fixture's note drawn as the page drew it: the same theme, face and text size, on a screen 390 x 844 at two
/// device pixels, the editor's box at the screen's corner. Answers the view.
Future<EditorView> pumpFixture(WidgetTester tester, Fixture fixture) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: fixture.doc,
      // The page these were measured on had the view's own extensions and no other (tool/editor_reference.mjs):
      // a formula on it is its source set as code, not drawn.
      extensions: noteExtensions(display: fixture.display, readOnly: fixture.readOnly, maths: false),
    ),
  );
  addTearDown(view.destroy);
  final prefs = AppPreferences(theme: fixture.theme, noteFace: fixture.json['noteFace'] as String, textSize: fixture.json['textSize'] as String);
  Widget host;
  if (fixture.peek) {
    // NotePeek.tsx's box: `.peek { margin-block-start: var(--glacier-space-2) }` over the editor.
    host = Builder(
      builder: (context) => Padding(
        padding: EdgeInsets.only(top: fixture.whole ? 0 : context.tokens.space(2)),
        child: MarkdownView(markdown: fixture.doc, whole: fixture.whole, lines: null),
      ),
    );
  } else {
    host = EditorColumn(view: view);
  }
  await pumpApp(
    tester,
    prefs: prefs,
    ratio: 2,
    home: Builder(
      // The page was measured in a browser emulating two device pixels to one: its layout is in whole CSS pixels
      // where a border is concerned (0.35em of 10.8px is drawn 3px, not 3.5), where a real phone's is in device
      // pixels. So the editor is told one device pixel to the logical one here, and the picture is still taken at
      // two.
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
    view.dispatch(TransactionSpec(selection: EditorSelection.single(fixture.anchor ?? fixture.caret!, fixture.caret)));
    await tester.pump();
  }
  return view;
}

/// The lines drawn, in document order.
List<RenderEditorLine> drawnLines(WidgetTester tester) =>
    tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

/// A line's box as the page measures a `.cm-line`: its border box, which leaves its margins out.
Rect borderBox(RenderEditorLine line) {
  final look = line.spec.look;
  final at = line.localToGlobal(Offset.zero);
  return Rect.fromLTRB(at.dx + look.marginStart, at.dy, at.dx + line.size.width - look.marginEnd, at.dy + line.size.height);
}

/// The runs of a line as the page has them: the text of each stretch and the classes over it, a stretch no mark
/// covers being the line's own.
List<(String, Set<String>)> runsOf(RenderEditorLine line) {
  final runs = <(String, Set<String>)>[];
  final proj = line.spec.projection;
  for (final seg in proj.segments) {
    if (seg.displayLength == 0) continue;
    final classes = <String>{for (final mark in seg.marks) ...(mark.attrs['class'] ?? '').split(' ').where((c) => c.isNotEmpty)};
    final text = proj.display.substring(seg.displayFrom, seg.displayTo);
    if (runs.isNotEmpty && runs.last.$2.length == classes.length && runs.last.$2.containsAll(classes)) {
      runs[runs.length - 1] = (runs.last.$1 + text, classes);
    } else {
      runs.add((text, classes));
    }
  }
  return runs;
}
