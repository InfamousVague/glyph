import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/boards/boards.dart';
import 'package:ghost_md/editor/items/task_fields.dart' show fieldsLocale, fieldsToday;
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// One case test/editor/boards/fixtures/reference.mjs measured on the web page.
class BoardFixture {
  BoardFixture(this.name, this.json);

  factory BoardFixture.read(String name) => BoardFixture(name, jsonDecode(File('test/editor/boards/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

  final String name;
  final Map<String, dynamic> json;

  String get doc => json['doc'] as String;
  NoteView get display => json['display'] == 'formatted' ? NoteView.formatted : NoteView.mixed;
  String get theme => json['theme'] as String;
  String get noteFace => json['noteFace'] as String;
  String get textSize => json['textSize'] as String;
  bool get readOnly => json['readOnly'] as bool;
  int? get caret => json['caret'] as int?;
  String get today => json['today'] as String;
  String get locale => json['locale'] as String;

  /// How far the page's board was scrolled along, and its first lane down.
  double? get scroll => (json['scroll'] as num?) == null ? null : (boards.first['scrollLeft'] as num).toDouble();
  bool get laneAtFoot => json['lane'] != null;

  /// The column whose + was pressed, and what was typed.
  int? get compose => json['compose'] as int?;
  String? get typed => json['typed'] as String?;

  /// The card held, and where the finger is.
  String? get hold => json['hold'] as String?;
  Offset? get held => json['held'] == null ? null : Offset(((json['held'] as Map)['x'] as num).toDouble(), ((json['held'] as Map)['y'] as num).toDouble());

  List<Map<String, dynamic>> get lines => (json['lines'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get boards => (json['boards'] as List).cast<Map<String, dynamic>>();

  static Rect rect(Object? r) {
    final m = r! as Map<String, dynamic>;
    return Rect.fromLTRB((m['left'] as num).toDouble(), (m['top'] as num).toDouble(), (m['right'] as num).toDouble(), (m['bottom'] as num).toDouble());
  }

  /// Every case, and after them those drawn in a phone's own pixels (`phone/<name>`).
  static List<String> names() => <String>[
    for (final under in const <String>['', 'phone/'])
      if (Directory('test/editor/boards/fixtures/$under').existsSync())
        ...(Directory('test/editor/boards/fixtures/$under').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => '$under${f.uri.pathSegments.last.replaceAll('.json', '')}').toList()..sort()),
  ];

  /// The screen the page was drawn on, and the device pixels to a CSS one it was LAID OUT in: 390 and 1 for a
  /// browser told a scale to paint at, the phone's own for a case in `phone/` (Chromium launched at the scale).
  double get screen => ((json['screen'] ?? 390) as num).toDouble();
  double get ratio => ((json['ratio'] ?? 1) as num).toDouble();
}

/// The note the web's boards.test.ts opens.
const String boardNote = '# Launch week\n\n```board\nTo do: ship-page\nDone: pick-date\n```\n\n- [ ] Ship the pricing page ^ship-page\n- [x] Pick a launch date ^pick-date\n';

/// A note with its boards drawn, as the page drew it: a screen 390 x 844 at two device pixels, the editor's box at
/// the screen's corner (test/editor/tables/support.dart's `pumpTables`, with `drawnBoards()` among the
/// extensions). Pumped twice more, for the frame a board measures its lanes in and the frame it is pinned in.
Future<EditorView> pumpBoards(
  WidgetTester tester,
  String doc, {
  String theme = 'light',
  String noteFace = 'maple',
  String textSize = 'large',
  NoteView display = NoteView.mixed,
  bool readOnly = false,
  int? caret,
  String today = '2026-10-08',
  String locale = 'en-US',
  CardActions? actions,
  List<Extension> more = const <Extension>[],
  ScrollController? scroll,
  double? height,
  bool shadows = false,
  double screen = 390,
  double layoutRatio = 1,
}) async {
  // Nothing is remembered between tests, and no write is left waiting when one ends.
  rememberBoardHeights = false;
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(
        display: display,
        readOnly: readOnly,
        more: <Extension>[drawnBoards(actions: actions), fieldsToday.of(() => today), fieldsLocale.of(locale), ...more],
      ),
    ),
  );
  addTearDown(view.destroy);
  // The input layer's part: asked for focus, the view has it.
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    size: Size(screen, layoutRatio == 1 ? 844 : 2300),
    prefs: AppPreferences(theme: theme, noteFace: noteFace, textSize: textSize),
    ratio: layoutRatio == 1 ? 2 : layoutRatio,
    measuredAt: layoutRatio,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: layoutRatio),
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: screen, height: height, child: SingleChildScrollView(controller: scroll, child: EditorColumn(view: view))),
          ),
        ),
      ),
    ),
  );
  // A test that takes no picture has no use for real shadows, and must not leave the switch thrown.
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

Future<EditorView> pumpBoardFixture(WidgetTester tester, BoardFixture fixture) => pumpBoards(
  tester,
  fixture.doc,
  theme: fixture.theme,
  noteFace: fixture.noteFace,
  textSize: fixture.textSize,
  display: fixture.display,
  readOnly: fixture.readOnly,
  caret: fixture.caret,
  today: fixture.today,
  locale: fixture.locale,
  shadows: true,
  screen: fixture.screen,
  layoutRatio: fixture.ratio,
);

/// The lines drawn, in document order.
List<RenderEditorLine> drawnLines(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

/// A widget's box on the screen.
Rect boxOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

Finder keyed(String key) => find.byKey(ValueKey<String>(key));

/// Something inside column `index` of the first board.
Finder inColumn(int index, Finder matching) => find.descendant(of: keyed('column$index'), matching: matching);

/// The card with anchor `id`, on the board (not its copy in the air).
Finder cardOf(String id) => find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((widget) => widget is BoardCard && widget.card.id == id));

/// A part of a card, by the key it is built with.
Finder inCard(String id, String key) => find.descendant(of: cardOf(id), matching: keyed(key));

/// A control by what a screen reader hears.
Finder said(String label) => find.bySemanticsLabel(label);

/// The words a [BoardWords] under `finder` set, line by line, on the screen.
List<Rect> wordLines(WidgetTester tester, Finder finder) => tester.renderObject<RenderBoardWords>(finder).wordBoxes;

/// A finger pressed on `at` and held until the thing under it lifts.
Future<TestGesture> holdAt(WidgetTester tester, Offset at) async {
  final finger = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 230));
  await tester.pump();
  return finger;
}
