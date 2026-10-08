import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import '../view/support.dart' show borderBox, drawnLines;

export '../view/support.dart' show borderBox, drawnLines;

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// One case test/editor/media/fixtures/reference.mjs measured on the web page.
class MediaFixture {
  MediaFixture(this.name, this.json);

  factory MediaFixture.read(String name) => MediaFixture(name, jsonDecode(File('test/editor/media/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  bool get dark => theme == 'dark';
  List<String> get use => (json['use'] as List).cast<String>();
  String get places => json['places'] as String;
  String get videos => json['videos'] as String;
  Map<String, dynamic>? get tape => json['tape'] as Map<String, dynamic>?;
  Map<String, dynamic> get prefs => json['prefs'] as Map<String, dynamic>;
  int? get caret => json['caret'] as int?;
  double get width => (json['width'] as num).toDouble();
  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get blocks => (json['blocks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get parts => (json['parts'] as List).cast<Map<String, dynamic>>();

  /// The page's parts of one name, in the page's order.
  List<Map<String, dynamic>> partsNamed(String name) => parts.where((part) => part['name'] == name).toList();

  static Rect rect(Map<String, dynamic> r) => Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());

  /// A picture the page was lent, as reference.mjs wrote it beside the fixtures.
  static List<int> picture(String name) => File('test/editor/media/fixtures/$name').readAsBytesSync();

  /// Every case the tool wrote whose name starts with one of `prefixes`.
  static List<String> names(List<String> prefixes) =>
      Directory('test/editor/media/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
          .where((name) => prefixes.any((prefix) => name == prefix || name.startsWith('$prefix-')))
          .toList()
        ..sort();
}

/// A note drawn as the page drew a fixture's: the theme, a screen 390 x 844 at two device pixels, the editor's box
/// at the screen's corner, with this piece's extensions in `more`. Answers the view.
Future<EditorView> pumpNote(WidgetTester tester, String doc, {List<Extension> more = const <Extension>[], NoteView display = NoteView.mixed, String theme = 'light', bool readOnly = false, int? caret, double width = 390}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(display: display, readOnly: readOnly, more: more),
    ),
  );
  addTearDown(view.destroy);
  await pumpApp(
    tester,
    prefs: AppPreferences(theme: theme),
    ratio: 2,
    home: Builder(
      // One device pixel to the logical one for layout, as test/editor/view/support.dart says and why.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: SingleChildScrollView(child: EditorColumn(view: view))),
          ),
        ),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  // pumpApp turns real shadows on for a picture, and the binding wants its switch back as a test ends: nothing
  // this piece draws casts one, so it is put back now for the tests that take no picture.
  debugDisableShadows = true;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  return view;
}

Future<EditorView> pumpMedia(WidgetTester tester, MediaFixture fixture, List<Extension> more) =>
    pumpNote(tester, fixture.doc, more: more, display: fixture.display, theme: fixture.theme, caret: fixture.caret, width: fixture.width);

/// Where a part is drawn: the box wearing `ValueKey<String>(name)`, each in the order they are in the tree. A span
/// of words answers its content area, which is what the page measures for one.
List<Rect> partRects(WidgetTester tester, String name) => <Rect>[
  for (final box in tester.renderObjectList<RenderBox>(find.byKey(ValueKey<String>(name), skipOffstage: false)))
    box is RenderInlineWords && _spans.contains(name) ? box.contentRect.shift(box.localToGlobal(Offset.zero)) : box.localToGlobal(Offset.zero) & box.size,
];

/// The parts that are inline spans on the page: their rectangle is the words' content area, not their line box.
const Set<String> _spans = <String>{'cm-shortLink', 'cm-itemMark-name'};

double off(Rect a, Rect b) => [(a.left - b.left).abs(), (a.top - b.top).abs(), (a.right - b.right).abs(), (a.bottom - b.bottom).abs()].reduce((x, y) => x > y ? x : y);

/// Holds the lines' boxes and what they show to the page's, and every named part's rectangle. Answers what
/// differs, and the worst distance.
({List<String> problems, double worst}) heldToPage(WidgetTester tester, MediaFixture fixture, List<String> partNames, {Set<String> notHeld = const <String>{}}) {
  final problems = <String>[];
  var worst = 0.0;
  final lines = drawnLines(tester);
  if (lines.length != fixture.lines.length) {
    problems.add('${lines.length} lines, the page ${fixture.lines.length}');
    return (problems: problems, worst: worst);
  }
  for (var i = 0; i < lines.length; i++) {
    final want = fixture.lines[i], line = lines[i];
    if (line.from != want['from']) problems.add('line $i starts at ${line.from}, the page\'s at ${want['from']}');
    final box = borderBox(line), wantBox = MediaFixture.rect(want['rect'] as Map<String, dynamic>);
    final d = off(box, wantBox);
    if (d > worst) worst = d;
    if (d > tolerance) problems.add('[line ${want['from']}] box $box, the page $wantBox');
    // What the line shows: the page's text with each widget's own words taken out is the display's with each
    // widget's placeholder taken out.
    final classes = line.spec.projection.className.split(' ').where((c) => c.isNotEmpty).toSet();
    final wantClasses = (want['classes'] as List).cast<String>().toSet();
    if (!(classes.length == wantClasses.length && classes.containsAll(wantClasses))) problems.add('[line ${want['from']}] classes $classes, the page $wantClasses');
  }
  for (final name in partNames) {
    final wanted = fixture.partsNamed(name);
    final drawn = partRects(tester, name);
    if (wanted.length != drawn.length) {
      problems.add('$name: ${drawn.length} drawn, the page ${wanted.length}');
      continue;
    }
    for (var i = 0; i < wanted.length; i++) {
      if (notHeld.contains('$name $i')) continue;
      final wantBox = MediaFixture.rect(wanted[i]['rect'] as Map<String, dynamic>);
      final d = off(drawn[i], wantBox);
      if (d > worst) worst = d;
      if (d > tolerance) problems.add('$name $i: ${drawn[i]}, the page $wantBox');
    }
  }
  return (problems: problems, worst: worst);
}

/// What a line shows, a widget as nothing: to hold against the page's text with its widgets' words taken out.
String shownOf(WidgetTester tester, int index) => drawnLines(tester)[index].spec.projection.display.replaceAll('￼', '');

/// Lets pictures decode (real work, off the test's clock) and the editor lay out again for their sizes.
Future<void> settlePictures(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

/// The page's block widgets held to the boxes wearing `names[i]` here, in order. Answers what differs.
List<String> blocksHeld(WidgetTester tester, MediaFixture fixture, String Function(Map<String, dynamic> block) keyOf) {
  final problems = <String>[];
  final seen = <String, int>{};
  for (final block in fixture.blocks) {
    final key = keyOf(block);
    final index = seen[key] = (seen[key] ?? -1) + 1;
    final drawn = partRects(tester, key);
    final want = MediaFixture.rect(block['rect'] as Map<String, dynamic>);
    if (index >= drawn.length) {
      problems.add('block $key $index is not drawn; the page $want');
    } else if (off(drawn[index], want) > tolerance) {
      problems.add('block $key $index: ${drawn[index]}, the page $want');
    }
  }
  return problems;
}
