import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/boards/boards.dart' show rememberBoardHeights;
import 'package:ghost_md/editor/items/tags.dart';
import 'package:ghost_md/editor/items/task_fields.dart' show fieldsLocale, fieldsToday;
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case test/editor/queries/fixtures/reference.mjs measured on the web page, a query's or a ticket's.
class PageFixture {
  PageFixture(this.name, this.json);

  factory PageFixture.read(String folder, String name) => PageFixture(name, jsonDecode(File('$folder/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  String get theme => json['theme'] as String;
  bool get readOnly => json['readOnly'] as bool;
  int? get caret => json['caret'] as int?;
  String get today => json['today'] as String;
  String get locale => json['locale'] as String;
  bool get add => json['add'] as bool? ?? false;
  bool get more => json['more'] as bool? ?? false;
  String? get compose => json['compose'] as String?;
  double? get scroll => (json['scroll'] as num?)?.toDouble();

  List<QueryNote> get library => <QueryNote>[
    for (final note in (json['library'] as List).cast<Map<String, dynamic>>()) QueryNote(id: note['id'] as String, body: note['body'] as String, createdAt: note['createdAt'] as int, updatedAt: note['updatedAt'] as int),
  ];

  /// The note the page had open, as its library held it the day it was measured. The page's queries read an open
  /// note the store has not got as made that moment (`withOpen`: `Date.now()`), which was the fixture's [today];
  /// read at the moment a test runs, a list of notes says "Today" for it on that one day and the weekday on every
  /// day after. So a test holds it in the library, at noon of the fixture's day, where the page's own stood.
  QueryNote get open {
    final noon = DateTime.parse('${today}T12:00:00').millisecondsSinceEpoch;
    return QueryNote(id: 'here', body: doc, createdAt: noon, updatedAt: noon);
  }

  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get blocks => (json['blocks'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get titles => (json['titles'] as List).cast<Map<String, dynamic>>();

  /// A block's parts by the name the page's stylesheet gives each (its first class, or its tag where it has none).
  static Map<String, List<Map<String, dynamic>>> partsOf(Map<String, dynamic> block) {
    final byName = <String, List<Map<String, dynamic>>>{};
    for (final part in (block['parts'] as List).cast<Map<String, dynamic>>()) {
      final names = (part['names'] as List).cast<String>();
      byName.putIfAbsent(names.isNotEmpty ? names.first : part['tag'] as String, () => <Map<String, dynamic>>[]).add(part);
    }
    return byName;
  }

  static Rect rect(Object? r) {
    final m = r! as Map<String, dynamic>;
    return Rect.fromLTRB((m['left'] as num).toDouble(), (m['top'] as num).toDouble(), (m['right'] as num).toDouble(), (m['bottom'] as num).toDouble());
  }

  /// Every case of `folder`, and after them those drawn in a phone's own pixels (`phone/<name>`).
  static List<String> names(String folder) => <String>[
    for (final under in const <String>['', 'phone/'])
      if (Directory('$folder/$under').existsSync())
        ...(Directory('$folder/$under').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => '$under${f.uri.pathSegments.last.replaceAll('.json', '')}').toList()..sort()),
  ];

  /// The screen the page was drawn on, and the device pixels to a CSS one it was LAID OUT in: 390 and 1 for a
  /// browser told a scale to paint at, the phone's own for a case in `phone/` (Chromium launched at the scale).
  double get screen => ((json['screen'] ?? 390) as num).toDouble();
  double get ratio => ((json['ratio'] ?? 1) as num).toDouble();
}

const String queryFixtures = 'test/editor/queries/fixtures';

/// What a test's screen was asked to do, in order.
class Asked {
  final List<(String noteId, int? line)> opened = <(String, int?)>[];
  final List<(String noteId, NoteChange change)> written = <(String, NoteChange)>[];
  final List<(TicketDraft draft, String title, String? from)> added = <(TicketDraft, String, String?)>[];
}

/// The options a test hands its queries: the library, the open note called `here`, and everything asked of the
/// screen kept in [asked].
QueryOptions optionsOver(List<QueryNote> Function() library, Asked asked, {bool? adds}) => QueryOptions(
  notes: library,
  noteId: 'here',
  open: (noteId, line) => asked.opened.add((noteId, line)),
  write: (noteId, change) => asked.written.add((noteId, change)),
  add: adds == null
      ? null
      : (draft, title, from) async {
          asked.added.add((draft, title, from));
          return adds;
        },
);

/// A note with its queries drawn, as the page drew it: a screen 390 x 844 at two device pixels, the editor's box at
/// the screen's corner (test/editor/boards/support.dart's `pumpBoards`, with `queries()` among the extensions).
Future<EditorView> pumpQueries(
  WidgetTester tester,
  String doc, {
  QueryOptions? options,
  String theme = 'light',
  bool readOnly = false,
  int? caret,
  String today = '2026-10-08',
  String locale = 'en-US',
  List<Extension> more = const <Extension>[],
  bool shadows = false,
  double screen = 390,
  double layoutRatio = 1,
}) async {
  rememberBoardHeights = false;
  queriesWatchMidnight = false;
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(
        readOnly: readOnly,
        more: <Extension>[tags(), wikiLinks(), queries(() => options), fieldsToday.of(() => today), fieldsLocale.of(locale), ...more],
      ),
    ),
  );
  addTearDown(view.destroy);
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    size: Size(screen, layoutRatio == 1 ? 844 : 2300),
    prefs: AppPreferences(theme: theme),
    ratio: layoutRatio == 1 ? 2 : layoutRatio,
    measuredAt: layoutRatio,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: layoutRatio),
        // A sheet a query opens (the builder, a field's picker) answers the phone's back through this.
        child: BackScope(
          child: ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: screen, child: SingleChildScrollView(child: EditorColumn(view: view))),
            ),
          ),
        ),
      ),
    ),
  );
  if (!shadows) debugDisableShadows = true;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  await tester.pump();
  await tester.pump();
  return view;
}

/// The lines drawn, in document order.
List<RenderEditorLine> drawnLines(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

/// The note's own lines that are drawn as lines, their words.
String shownLines(WidgetTester tester, EditorView view) => drawnLines(tester).map((line) => view.state.doc.lineAt(line.from).text).join('\n');

/// A widget's box on the screen.
Rect boxOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Every piece named `name` ([Part]) under `under`, in the order they are drawn.
Finder parts(String name, [Finder? under]) {
  final named = find.byWidgetPredicate((widget) => widget is Part && widget.name == name);
  return under == null ? named : find.descendant(of: under, matching: named);
}

/// A control by what a screen reader hears.
Finder said(Pattern label) => find.bySemanticsLabel(label);

/// The drawn queries.
Finder get drawn => find.byType(DrawnQuery);

/// Everything a drawn query says, its words in order.
String wordsOf(WidgetTester tester, Finder under) {
  final words = StringBuffer();
  for (final element in find.descendant(of: under, matching: find.byType(RichText)).evaluate()) {
    words.write((element.widget as RichText).text.toPlainText());
    words.write('\n');
  }
  return words.toString();
}

/// A finger pressed on `at` and held until the thing under it lifts.
Future<TestGesture> holdAt(WidgetTester tester, Offset at) async {
  final finger = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 230));
  await tester.pump();
  return finger;
}
