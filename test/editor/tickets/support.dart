import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/items/tags.dart';
import 'package:ghost_md/editor/items/task_fields.dart' show fieldsLocale, fieldsToday;
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

export '../queries/support.dart' show PageFixture, boxOf, drawnLines, parts, said, shownLines, wordsOf;

const String ticketFixtures = 'test/editor/tickets/fixtures';

/// What a test's panel was asked to write and to open, in order.
class Asked {
  final List<(String key, Object? value)> written = <(String, Object?)>[];
  final List<String> opened = <String>[];
}

/// The options a test hands a ticket: the default workflow, two people, and the tickets `found`, looked up by key.
TicketOptions optionsWith(List<TicketChoice> found, {Asked? asked, List<String> statuses = defaultStatuses, List<String> people = const <String>['Sam', 'Priya Shah'], String? nextId, bool byTitle = false}) => TicketOptions(
  statuses: () => statuses,
  people: () => people,
  choices: () => found,
  find: (target) => found.where((choice) => choice.key == target.toUpperCase() || (byTitle && choice.title.toLowerCase() == target.toLowerCase())).firstOrNull,
  open: (target) => asked?.opened.add(target),
  nextId: nextId == null ? null : () => nextId,
);

/// A note with its ticket drawn, as the page drew it (test/editor/queries/support.dart's `pumpQueries`, with
/// `tickets()` among the extensions and the links between notes the page's editor has).
Future<EditorView> pumpTickets(
  WidgetTester tester,
  String doc, {
  TicketOptions? options,
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
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(
        readOnly: readOnly,
        more: <Extension>[
          tags(),
          wikiLinks(WikiOptions(known: (title) => options?.find(title) != null, open: (title, [anchor]) => options?.open(title))),
          tickets(() => options),
          fieldsToday.of(() => today),
          fieldsLocale.of(locale),
          ...more,
        ],
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

/// The drawn panels.
Finder get panel => find.byType(TicketPanel);
