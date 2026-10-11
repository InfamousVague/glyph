// editor/markReads.test.ts, case for case.
//
// What is asked differently: the page's visibility is the app's lifecycle, told through the binding; a frame is a
// pump; the minute is the test's own clock. The reader stands in for a plugin (support.dart `StandIn`).
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/mark_reads.dart';
import 'package:ghost_md/editor/media/linked_rows.dart';
import 'package:ghost_md/editor/media/links.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/mark_details.dart';

import '../../support/render.dart';
import 'support.dart';

final String task = 'https://app.notion.com/p/Buy-milk-${'a' * 32}';
final String doc = '- [ ] Buy milk [notion]($task)\n\nplain words\n';

/// What the plugin knows about the task now, and every read the note asked it for.
final StandIn reader = StandIn();

final MarkEntry ready = MarkReady(MarkDetails(url: task, title: 'Buy milk', status: const MarkStatus('In progress', Stage.doing), brief: const <String>['P1'], editedAt: 1, readAt: 1));

/// How many transactions have passed an answer on to the note.
int arrivals = 0;

Future<EditorView> open(WidgetTester tester, {bool still = false}) {
  arrivals = 0;
  final count = EditorViewLike.updateListener.of((update) {
    for (final tr in update.transactions) {
      if (tr.effects.any((effect) => effect.isOf(detailsArrived))) arrivals += 1;
    }
  });
  return pumpNote(tester, doc, more: <Extension>[shortLinks(still: still), linkedRows(null), count]);
}

/// The page's visibility as the reads see it.
void showPage(WidgetTester tester, {required bool visible}) => tester.binding.handleAppLifecycleStateChanged(visible ? AppLifecycleState.resumed : AppLifecycleState.paused);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    provideMarkDetails('notion', () => reader);
  });
  setUp(() {
    reader.known.clear();
    reader.wanted.clear();
  });

  group('asking what a note’s links are doing', () {
    testWidgets('asks for every linked thing in view on opening, and again each minute the note is open', (tester) async {
      final on = await open(tester);
      expect(reader.wanted, <(String, bool)>[(task, false)]);
      await tester.pump(const Duration(seconds: 59));
      expect(reader.wanted, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(reader.wanted, hasLength(2));
      on.destroy();
    });

    testWidgets('asks nothing while the app is in the background, and asks again when it comes back', (tester) async {
      final on = await open(tester);
      reader.wanted.clear();
      showPage(tester, visible: false);
      await tester.pump(const Duration(seconds: 60));
      expect(reader.wanted, isEmpty);
      showPage(tester, visible: true);
      expect(reader.wanted, <(String, bool)>[(task, false)]);
      on.destroy();
    });

    testWidgets('asks about a mark as soon as it is written', (tester) async {
      final on = await open(tester);
      reader.wanted.clear();
      final other = 'https://app.notion.com/p/Call-${'b' * 32}';
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: on.state.doc.length, insert: '- [ ] Call Sam [notion]($other)\n')));
      await tester.pump();
      expect(reader.wanted.map((asked) => asked.$1), contains(other));
      on.destroy();
    });

    testWidgets('stops asking when the note closes', (tester) async {
      (await open(tester)).destroy();
      reader.wanted.clear();
      await tester.pump(const Duration(seconds: 120));
      showPage(tester, visible: false);
      showPage(tester, visible: true);
      expect(reader.wanted, isEmpty);
    });

    testWidgets('asks nothing on a note drawn still, on a card', (tester) async {
      final on = await open(tester, still: true);
      await tester.pump(const Duration(seconds: 120));
      showPage(tester, visible: false);
      showPage(tester, visible: true);
      expect(reader.wanted, isEmpty);
      on.destroy();
    });
  });

  group('an answer arriving', () {
    List<String> row(WidgetTester tester) => tester.widgetList<LinkPill>(find.byType(LinkPill)).map((pill) => pill.text).toList();

    testWidgets('is drawn in the row under the line, however many answers came in the same frame', (tester) async {
      final on = await open(tester);
      expect(row(tester), <String>['Notion']);
      reader.known[task] = ready;
      markDetailsChanged();
      markDetailsChanged();
      markDetailsChanged();
      // Passed on at the next frame, once.
      expect(arrivals, 0);
      await tester.pump();
      expect(arrivals, 1);
      await tester.pump();
      expect(row(tester), <String>['Notion', 'In progress', 'P1']);
      on.destroy();
    });

    testWidgets('is drawn on a note drawn still too, which only never asks', (tester) async {
      final on = await open(tester, still: true);
      reader.known[task] = ready;
      markDetailsChanged();
      await tester.pump();
      await tester.pump();
      expect(row(tester), <String>['Notion', 'In progress', 'P1']);
      on.destroy();
    });
  });

  group('the minute’s clock (not on the page, which always keeps one)', () {
    testWidgets('runs only while something in view has a reader, and starts when one appears', (tester) async {
      forgetMarkProviders();
      addTearDown(() => provideMarkDetails('notion', () => reader));
      final on = await open(tester);
      await tester.pump(const Duration(seconds: 120));
      expect(reader.wanted, isEmpty);
      // The plugin is switched on: told as the registry tells it, and the marks in view are asked for at once.
      provideMarkDetails('notion', () => reader);
      markDetailsChanged();
      expect(reader.wanted, <(String, bool)>[(task, false)]);
      await tester.pump(const Duration(seconds: 60));
      expect(reader.wanted, hasLength(2));
      on.destroy();
    });
  });
}
