import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// The note the page's own test reads (`NOTE`, editor/comments.test.ts).
final String note = [
  '# Barn dance',
  '',
  'The ==venue==[^c1] is booked. Call the band[^c2]',
  '',
  '```comments',
  'c1 sam 2026-10-04T19:00:12Z',
  'The hall or the barn?',
  '  matt 2026-10-04T19:05:40Z',
  '  The hall.',
  'c2 matt 2026-10-04T19:10:00Z',
  'Which band?',
  '  resolved sam 2026-10-04T19:12:00Z',
  '```',
  '',
].join('\n');

/// What a test's screen was asked to open, and the colours it answers.
class Hooked {
  Hooked([Map<String, String>? colours]) : colours = colours ?? <String, String>{'sam': 'sea', 'matt': 'rose'};

  final Map<String, String> colours;
  final List<String> opened = <String>[];
  int changed = 0;

  late final CommentHooks hooks = CommentHooks(open: opened.add, colour: (handle) => colours[handle] ?? 'ink', me: () => 'matt', changed: () => changed += 1);
}

/// A note with its comments drawn, as the page drew it: a screen 390 x 844, the editor's box at the screen's corner
/// (test/editor/queries/support.dart's `pumpQueries`, with `noteComments()` among the extensions).
Future<EditorView> pumpComments(WidgetTester tester, String doc, CommentHooks? hooks, {int? selection, String theme = 'light', bool readOnly = false, List<Extension> more = const <Extension>[]}) async {
  // The page's test's own evening: two and a half hours after the first comment.
  commentsNow = () => DateTime.parse('2026-10-04T21:30:00Z').millisecondsSinceEpoch;
  addTearDown(() => commentsNow = () => DateTime.now().millisecondsSinceEpoch);
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      selection: selection == null ? null : EditorSelection.single(selection),
      extensions: noteExtensions(formats: marks, readOnly: readOnly, more: <Extension>[formatLooks(marks), noteComments(() => hooks), ...more]),
    ),
  );
  addTearDown(view.destroy);
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    prefs: AppPreferences(theme: theme),
    ratio: 2,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
        child: BackScope(
          child: ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view))),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  return view;
}

/// The rounds drawn, in the note's order.
List<RoundWidget> roundsOf(EditorView view) {
  final found = <(int, RoundWidget)>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final widget = value.spec.widget;
      if (widget is RoundWidget) found.add((from, widget));
      return null;
    });
  }
  found.sort((a, b) => a.$1 - b.$1);
  return [for (final (_, widget) in found) widget];
}

/// The washes drawn: where, and what each says of itself.
List<({int from, int to, Map<String, String> attrs})> washesOf(EditorView view) {
  final found = <({int from, int to, Map<String, String> attrs})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if ((value.spec.className ?? '').split(' ').contains('cm-commentWash')) found.add((from: from, to: to, attrs: value.spec.attributes ?? const <String, String>{}));
      return null;
    });
  }
  return found;
}

/// Everything under `under` says, its words in order.
String wordsOf(WidgetTester tester, Finder under) {
  final words = StringBuffer();
  for (final element in find.descendant(of: under, matching: find.byType(RichText)).evaluate()) {
    words.write((element.widget as RichText).text.toPlainText());
    words.write('\n');
  }
  return words.toString();
}
