// The graph of the notes (lib/links/graph_layout.dart, lib/links/graph_view.dart): the layout, the same each time and
// quick for a thousand notes; a pinch that only draws the picture it has; a tap that opens a note and a hold that
// lights its neighbours; and pictures of the sample library's graph and of a thousand notes
// (build/feature-shots/links/, with --update-goldens).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/link_index.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/links/graph_layout.dart';
import 'package:ghost_md/links/graph_view.dart';

import '../core/make_note.dart';
import '../support/render.dart';

/// A library of [n] notes, each linking to a few others, a tenth with no links, in three workspaces.
List<Note> thousand(int n) {
  final random = math.Random(7);
  return [
    for (var i = 0; i < n; i += 1)
      makeNote('n$i', body: '# Note $i\n\n${i % 10 == 0 ? 'Alone.' : [for (var j = 0; j < 1 + random.nextInt(3); j += 1) '[[Note ${(i ~/ 25) * 25 + random.nextInt(25)}]] and [[Note ${random.nextInt(n)}]]'].join('\n')}'),
  ];
}

LinkIndexer indexerOf(List<Note> notes) => LinkIndexer(notes: () => notes, inlineUpTo: 1 << 20);

void main() {
  setUpAll(loadAppFonts);

  group('the layout', () {
    test('is the same each time, every link near its length, and a thousand notes in a fraction of a second', () {
      final indexer = indexerOf(thousand(1000));
      final graph = indexer.index.graph();
      final input = (ids: graph.ids, from: graph.from, to: graph.to);
      final watch = Stopwatch()..start();
      final at = layOutGraph(input);
      watch.stop();
      // ignore: avoid_print
      print('1,000 notes and ${graph.from.length} links laid out in ${watch.elapsedMilliseconds} ms');
      // On a Mac at rest about 300 ms; the bound leaves room for a machine busy with other tests.
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(layOutGraph(input), at);
      expect(at.every((value) => value.isFinite), isTrue);
      // Two notes never on one spot.
      final seen = <String>{for (var i = 0; i < at.length; i += 2) '${at[i].round()},${at[i + 1].round()}'};
      expect(seen.length, greaterThan(990));
    });

    test('a small graph: linked notes nearer each other than to a note with no links', () {
      final at = layOutGraph((ids: const ['a', 'b', 'c', 'alone'], from: const [0, 1], to: const [1, 2]));
      double d(int x, int y) => math.sqrt(math.pow(at[2 * x] - at[2 * y], 2) + math.pow(at[2 * x + 1] - at[2 * y + 1], 2));
      expect(d(0, 1), lessThan(linkLength * 2));
      expect(d(1, 2), lessThan(linkLength * 2));
    });
  });

  group('the view', () {
    Future<List<String>> show(WidgetTester tester, LinkIndexer indexer, {String? focus, Size size = const Size(430, 932), String theme = 'dark', WorkspaceStore? spaces}) async {
      final opened = <String>[];
      await pumpApp(
        tester,
        size: size,
        ratio: 3,
        prefs: AppPreferences(theme: theme),
        home: GraphScreen(indexer: indexer, focus: focus, focusTitle: focus == null ? null : indexer.index.factsOf(focus)?.title, hueOf: (id) => spaces?.workspaceOf(id)?.hue, onOpen: opened.add, onClose: () => opened.add('closed')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return opened;
    }

    testWidgets('a pinch and a drag draw the picture it has, and record none', (tester) async {
      final indexer = indexerOf(SampleLibrary.seeded().value);
      await show(tester, indexer);
      final recorded = GraphPainter.debugRecorded;
      final view = find.byType(GraphView);
      final centre = tester.getCenter(view);
      final one = await tester.startGesture(centre - const Offset(40, 0));
      final two = await tester.startGesture(centre + const Offset(40, 0), pointer: 2);
      for (var i = 1; i <= 10; i += 1) {
        await one.moveTo(centre - Offset(40.0 + 8 * i, 0));
        await two.moveTo(centre + Offset(40.0 + 8 * i, 4.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await one.up();
      await two.up();
      await tester.pump();
      expect(GraphPainter.debugRecorded, recorded, reason: 'the frames of a pinch draw the one picture again');
      expect(tester.state<GraphViewState>(view).transform.scale, greaterThan(0));
      debugDisableShadows = true;
    });

    testWidgets('a tap on a note opens it, a hold lights it and its neighbours, a tap on nothing puts the light out', (tester) async {
      final indexer = indexerOf(SampleLibrary.seeded().value);
      final opened = await show(tester, indexer, focus: 'portugal');
      final state = tester.state<GraphViewState>(find.byType(GraphView));
      final graph = tester.widget<GraphView>(find.byType(GraphView)).graph;
      Offset where(String id) {
        final i = graph.ids.indexOf(id);
        final t = state.transform;
        return tester.getTopLeft(find.byType(GraphView)) + Offset(state.positions![2 * i] * t.scale + t.shift.dx, state.positions![2 * i + 1] * t.scale + t.shift.dy);
      }

      expect(graph.ids, unorderedEquals(['portugal', 'packing', 'lisbon', 'coast']));
      await tester.longPressAt(where('portugal'));
      await tester.pump();
      expect(state.lit, graph.ids.indexOf('portugal'));
      await tester.tapAt(tester.getTopLeft(find.byType(GraphView)) + const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.lit, -1);
      await tester.tapAt(where('coast'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, ['coast']);
      debugDisableShadows = true;
    });

    for (final (name, size) in const [('phone', Size(430, 932)), ('fold', Size(900, 1000))]) {
      testWidgets('pictures: the sample library and a thousand notes, $name', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        Directory('build/feature-shots/links').createSync(recursive: true);
        final library = SampleLibrary.seeded();
        final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()));
        await show(tester, indexerOf(library.value), size: size, spaces: spaces);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/links/graph-sample-$name.png'));
        await show(tester, indexerOf(thousand(1000)), size: size);
        // A thousand notes are laid out by a worker: real time for it, then the frame it lands in.
        expect(find.text('Laying out 1000 notes'), findsOneWidget);
        for (var i = 0; i < 40 && tester.state<GraphViewState>(find.byType(GraphView)).positions == null; i += 1) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump();
        }
        await tester.pump();
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/links/graph-thousand-$name.png'));
        // Held: a note and its neighbours lit, their names drawn.
        final state = tester.state<GraphViewState>(find.byType(GraphView));
        final t = state.transform;
        await tester.longPressAt(tester.getTopLeft(find.byType(GraphView)) + Offset(state.positions![2 * 51] * t.scale + t.shift.dx, state.positions![2 * 51 + 1] * t.scale + t.shift.dy));
        await tester.pump();
        await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/links/graph-thousand-lit-$name.png'));
        debugDisableShadows = true;
      });
    }
  });
}
