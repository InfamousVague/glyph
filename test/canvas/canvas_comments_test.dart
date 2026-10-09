// A canvas's comments in the view (lib/canvas/canvas_comments.dart over canvas_view.dart): the cases of
// `src/app/canvas/CanvasView.comments.test.tsx`, in its order. A round on a card's corner for its threads, in the
// colour of who started the first open one, with how many are open; the round opens the thread's card, where a
// reply, Resolve and Delete thread change the canvas; Comment on the picked card's bar starts a thread; and a canvas
// that cannot change draws no rounds.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart' show SealKey;
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/canvas_comments.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/back.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

const String withThreads = '''{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" }
  ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "sam", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [] },
    { "id": "c2", "node": "book", "by": "lee", "at": "2026-10-05T14:01:00Z", "text": "And where?", "replies": [], "resolved": { "by": "matt", "at": "2026-10-05T14:02:00Z" } }
  ]
}''';

/// An account signed in as matt, and nothing else of one.
class _Matt extends ChangeNotifier implements AccountSource {
  @override
  Session? get session => const Session(token: 't', handle: 'matt', accountId: 7);

  @override
  Future<SealKey?> accountKey() async => null;
}

/// A canvas on the screen with its comments, and every canvas it handed on.
class Shown {
  Shown(this.tester);
  final WidgetTester tester;
  final GlobalKey<CanvasViewState> view = GlobalKey<CanvasViewState>();
  final List<Canvas> changes = [];
  late String body;
  Canvas get last => changes.last;

  /// Draws the canvas again from [body], as the note does when it changes.
  late StateSetter redraw;

  Future<void> show(Canvas canvas, {bool editable = true, CommentColours? colours, String theme = 'light'}) async {
    body = canvasNoteBody('Test', canvas);
    final account = _Matt();
    Widget drawn(StateSetter setState, CanvasThreads? threads, String Function(String)? hue) => CanvasView(
      key: view,
      body: body,
      threads: threads,
      threadHue: hue,
      onChange: !editable
          ? null
          : (next) {
              changes.add(canvasOf(next)!);
              setState(() => body = next);
            },
    );
    await pumpApp(
      tester,
      size: const Size(800, 600),
      prefs: AppPreferences(theme: theme, canvasSnap: false),
      home: BackScope(
        child: StatefulBuilder(
          builder: (context, setState) {
            redraw = setState;
            return !editable
                ? drawn(setState, null, null)
                : CanvasComments(body: body, colours: () => colours ?? commentColours(orgId: null), account: account, now: () => DateTime.utc(2026, 10, 5, 15), builder: (context, threads, hue) => drawn(setState, threads, hue));
          },
        ),
      ),
    );
    await tester.pump();
    addTearDown(() => debugDisableShadows = true);
  }

  Future<void> settle([int ms = 400]) async {
    for (var left = ms; left > 0; left -= 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> done() async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder get sheet => find.byType(CommentSheet);
  List<String> get said => [for (final element in find.descendant(of: sheet, matching: find.byType(RichText)).evaluate()) (element.widget as RichText).text.toPlainText()];

  Future<void> write(String words, String send) async {
    await tester.enterText(find.descendant(of: sheet, matching: find.byType(EditableText)), words);
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == send));
    await tester.pump();
    await tester.pump();
  }

  Future<void> row(String words) async {
    final found = find.descendant(of: sheet, matching: find.text(words));
    await tester.ensureVisible(found);
    await tester.tap(found);
    await tester.pump();
    await tester.pump();
  }
}

/// A control by what a screen reader hears of it.
Finder said(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  setUpAll(loadAppFonts);

  final canvas = parseCanvas(withThreads)!;

  group('a canvas’s comments', () {
    testWidgets('marks a card with its open threads, in the first open one’s colour, and opens its threads from the round', (tester) async {
      final shown = Shown(tester);
      await shown.show(canvas);
      final mark = find.byKey(const ValueKey('round book'));
      expect(mark, findsOneWidget);
      expect(said('2 comments on this card, 1 open'), findsOneWidget);
      expect(find.descendant(of: mark, matching: find.text('1')), findsOneWidget);
      expect(find.byKey(const ValueKey('round site')), findsNothing);
      await tester.tap(mark);
      await shown.settle();
      // Two threads: the list first, open ones first; the thread's card from a row.
      expect(tester.widget<CommentSheet>(shown.sheet).page, const ListPage());
      expect(shown.said, containsAllInOrder(['Which Friday?', 'And where?']));
      await tester.tap(find.byKey(const ValueKey<String>('thread c1')));
      await shown.settle();
      expect(tester.widget<CommentSheet>(shown.sheet).page, const ThreadPage('c1'));
      // The words the thread is about: the card's first line.
      expect(shown.said, contains('# Book the cabin'));
      await shown.write('The 10th.', 'Send reply');
      final replies = shown.last.comments!.firstWhere((thread) => thread.id == 'c1').replies;
      expect([for (final reply in replies) '${reply.by}: ${reply.text}'], ['matt: The 10th.']);
      // The other thread is as it was, and the card under the sheet reads the reply at once.
      expect(shown.last.comments!.firstWhere((thread) => thread.id == 'c2').resolved?.by, 'matt');
      expect(shown.said, contains('The 10th.'));
      await shown.done();
    });

    testWidgets('resolves and deletes a thread from its card, and starts one from the picked card’s bar', (tester) async {
      final shown = Shown(tester);
      await shown.show(Canvas(nodes: canvas.nodes, edges: canvas.edges, comments: [canvas.comments!.first]));
      await tester.tap(find.byKey(const ValueKey('round book')));
      await shown.settle();
      expect(shown.said, contains('Which Friday?'));
      await shown.row('Resolve');
      expect(shown.last.comments!.single.resolved?.by, 'matt');
      // The canvas comes back changed, as the note hands it: the card shows the thread resolved, and Delete asks
      // twice.
      expect(said('A comment on this card, resolved'), findsOneWidget);
      expect(shown.said.join('\n'), contains('Resolved by You'));
      await shown.row('Delete thread');
      await shown.row('Delete it? Press again');
      expect(shown.last.comments, isNull);
      await shown.settle();
      expect(shown.sheet, findsNothing);
      expect(find.byKey(const ValueKey('round book')), findsNothing);
      // A tap picks the card, and Comment on its bar opens a new comment, which goes into the canvas on the card.
      final state = shown.view.currentState!;
      final site = state.live.nodeOf('site')!;
      final at = state.camera.view;
      final gesture = await tester.startGesture(Offset(at.x + (site.x + site.width / 2) * at.scale, at.y + (site.y + site.height / 2) * at.scale));
      await gesture.up();
      await tester.pump();
      await shown.settle();
      await tester.tap(said('Comment on this card'));
      await shown.settle();
      expect(tester.widget<CommentSheet>(shown.sheet).page, const NewPage('https://attack.fm/glyph'));
      await shown.write('Is this the right link?', 'Add comment');
      final added = shown.last.comments!;
      expect(added, hasLength(1));
      expect((added.single.node, added.single.by, added.single.text), ('site', 'matt', 'Is this the right link?'));
      expect(added.single.replies, isEmpty);
      expect(added.single.id, matches(RegExp(r'^c[0-9a-z]{4,}$')));
      expect(added.single.at, '2026-10-05T15:00:00Z');
      await shown.settle();
      expect(shown.sheet, findsNothing);
      await shown.done();
    });

    testWidgets('draws no rounds, and no Comment, on a canvas that cannot change', (tester) async {
      final shown = Shown(tester);
      await shown.show(canvas, editable: false);
      expect(find.byKey(const ValueKey('round book')), findsNothing);
      await shown.done();
    });

    testWidgets('reads the canvas again when the note changes under an open card: another member’s reply', (tester) async {
      final shown = Shown(tester);
      await shown.show(Canvas(nodes: canvas.nodes, edges: canvas.edges, comments: [canvas.comments!.first]));
      await tester.tap(find.byKey(const ValueKey('round book')));
      await shown.settle();
      // The note's body, handed in anew with a reply nobody here wrote.
      final theirs = parseCanvas(withThreads.replaceFirst('"text": "Which Friday?", "replies": []', '"text": "Which Friday?", "replies": [{ "by": "kit", "at": "2026-10-05T14:30:00Z", "text": "The 10th." }]'))!;
      shown.redraw(() => shown.body = canvasNoteBody('Test', Canvas(nodes: theirs.nodes, edges: theirs.edges, comments: [theirs.comments!.first])));
      await tester.pump();
      await tester.pump();
      expect(shown.said, containsAllInOrder(['Which Friday?', 'kit', 'The 10th.']));
      // And a reply written now is under theirs, not in place of it.
      await shown.write('Booked.', 'Send reply');
      expect([for (final reply in shown.last.comments!.single.replies) reply.text], ['The 10th.', 'Booked.']);
      await shown.done();
    });

    testWidgets('a round wears the colour of who started the first open thread', (tester) async {
      final shown = Shown(tester);
      await shown.show(
        canvas,
        colours: commentColours(orgId: 'o1', theirs: const {'sam': 'sea', 'lee': 'moss'}),
      );
      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/comments-rounds.png'));
      await tester.tap(find.byKey(const ValueKey('round book')));
      await shown.settle();
      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/comments-list.png'));
      await shown.done();
    });
  });
}
