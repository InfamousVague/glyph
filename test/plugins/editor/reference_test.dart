// The editor's side of the plugins held to the web page: fixtures/reference.mjs drew a note of linked lines with the
// web app's whole `Editor` in Chromium, a stand-in mark-details provider registered in the page, and measured the
// rows of pills, the quiet words at the ends of lines, the swipe's tile and the drawer. Here the same note is drawn
// with this piece's extensions over the base editor and the same stand-in, and every rectangle is compared to half
// a pixel. Pictures are written to shots/, to be looked at beside the page's (fixtures/*.png).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/media/linked_rows.dart';
import 'package:ghost_md/editor/media/links.dart';
import 'package:ghost_md/plugins/mark_details.dart';

import '../../support/render.dart';
import 'support.dart';

Map<String, dynamic> fixture(String name) => jsonDecode(File('test/plugins/editor/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

String t(int n) => 'https://www.notion.so/Task-${'$n' * 32}';

/// What reference.mjs's provider knew in the page.
final StandIn notion = StandIn(
  readsUrl: (url) => url.contains('notion.so/'),
  actionsFor: (url, words) => notion.known[url] is! MarkReady
      ? const <MarkAction>[]
      : <MarkAction>[
          MarkAction(id: 'done', label: 'Mark done in Notion', icon: MarkActionIcon.done, busyLabel: 'Marking done…', run: () async => null),
          MarkAction(id: 'rename', label: 'Use these words as its title', icon: MarkActionIcon.rename, busyLabel: 'Renaming…', run: () async => null),
        ],
);

void know() {
  MarkEntry ready(int n, String title, MarkStatus? status, List<String> brief, {bool gone = false}) => MarkReady(
    MarkDetails(
      url: t(n),
      title: title,
      status: status,
      brief: brief,
      fields: <MarkField>[MarkField('Status', status?.label ?? ''), const MarkField('Priority', 'P1'), const MarkField('Due', 'Sep 20'), const MarkField('Owner', 'Sam')],
      readAt: DateTime.now().millisecondsSinceEpoch,
      gone: gone,
    ),
  );
  notion.known
    ..clear()
    ..[t(1)] = ready(1, 'Buy oat milk', const MarkStatus('In progress', Stage.doing), const <String>['P1', 'Overdue by 2 days'])
    ..[t(2)] = ready(2, 'Call Sam', const MarkStatus('Done', Stage.done), const <String>['Due Sep 20'])
    ..[t(3)] = ready(3, 'Nested one', const MarkStatus('', Stage.todo), const <String>[])
    ..[t(4)] = ready(4, 'In the bin', null, const <String>['P1'], gone: true)
    ..[t(5)] = const MarkLoading()
    ..[t(6)] = const MarkFailed('Notion said no.');
}

final RegExp _todo = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s\[ \]\s');

/// The page's `suggest` and `swipeAction`, which never finish.
List<LineSuggestion> suggest(String body) => <LineSuggestion>[
  for (final (index, text) in body.split('\n').indexed)
    if (_todo.hasMatch(text) && !text.contains('](')) LineSuggestion(line: index + 1, label: 'Notion', busyLabel: 'Sending', run: () => Completer<void>().future),
];

List<Extension> extensions() => <Extension>[
  itemExtensions(suggest: suggest, swipe: () => SwipeAction(label: 'Send to Notion', busyLabel: 'Sending…', run: (_) => Completer<void>().future)),
  shortLinks(),
  linkedRows(LinkMenus(say: (_) {})),
];

Rect rectOf(Object r) => MediaFixture.rect((r as Map).cast<String, dynamic>());

/// Holds the lines' boxes, the rows, their pills and stage dots, and the words after lines to the page's.
({List<String> problems, double worst}) held(WidgetTester tester, Map<String, dynamic> page, {Set<int> movedLines = const <int>{}}) {
  final problems = <String>[];
  var worst = 0.0;
  void hold(String what, Rect drawn, Rect want) {
    final d = off(drawn, want);
    if (d > worst) worst = d;
    if (d > tolerance) problems.add('$what: $drawn, the page $want');
  }

  final lines = drawnLines(tester), wantLines = (page['lines'] as List).cast<Map<String, dynamic>>();
  expect(lines.length, wantLines.length);
  for (var i = 0; i < lines.length; i++) {
    if (movedLines.contains(wantLines[i]['from'])) continue;
    hold('line ${wantLines[i]['from']}', borderBox(lines[i]), rectOf(wantLines[i]['rect'] as Object));
  }
  final rows = (page['rows'] as List).cast<Map<String, dynamic>>();
  void all(String key, List<Rect> want) {
    final drawn = partRects(tester, key);
    if (drawn.length != want.length) {
      problems.add('$key: ${drawn.length} drawn, the page ${want.length}');
      return;
    }
    for (var i = 0; i < want.length; i++) {
      hold('$key $i', drawn[i], want[i]);
    }
  }

  all('cm-linkRow', <Rect>[for (final row in rows) rectOf(row['rect'] as Object)]);
  all('cm-linkPill', <Rect>[
    for (final row in rows)
      for (final pill in row['pills'] as List) rectOf((pill as Map)['rect'] as Object),
  ]);
  all('cm-linkStage', <Rect>[
    for (final row in rows)
      for (final stage in row['stages'] as List) rectOf((stage as Map)['rect'] as Object),
  ]);
  all('cm-suggest', <Rect>[for (final word in page['suggests'] as List) rectOf((word as Map)['rect'] as Object)]);
  // What the pills say, in the page's order.
  final said = tester.widgetList<LinkPill>(find.byType(LinkPill)).map((pill) => pill.text).toList();
  final wantSaid = <String>[
    for (final row in rows)
      for (final pill in row['pills'] as List) (pill as Map)['text'] as String,
  ];
  if (said.join('|') != wantSaid.join('|')) problems.add('pills say $said, the page $wantSaid');
  return (problems: problems, worst: worst);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    provideMarkDetails('notion', () => notion);
  });
  setUp(know);

  for (final name in const <String>['rows', 'rows-dark']) {
    testWidgets('$name: the rows under linked lines, their pills, and the words after lines, where the page has them', (tester) async {
      final page = fixture(name);
      final view = await pumpNote(tester, page['doc'] as String, more: extensions(), theme: page['theme'] as String);
      await tester.pump(const Duration(milliseconds: 300));
      final result = held(tester, page);
      // ignore: avoid_print
      print('$name: worst ${result.worst.toStringAsFixed(3)}');
      expect(result.problems, isEmpty, reason: result.problems.join('\n'));
      await shot(tester, name);
      view.destroy();
    });
  }

  for (final name in const <String>['open', 'open-dark']) {
    testWidgets('$name: a tap on a pill rings the name and brings the drawer up over the note', (tester) async {
      final page = fixture(name);
      final view = await pumpNote(tester, page['doc'] as String, more: extensions(), theme: page['theme'] as String);
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final result = held(tester, page);
      final panel = tester.getRect(find.byKey(const ValueKey<String>('sheet-panel')));
      final want = rectOf((page['dialog'] as Map)['rect'] as Object);
      // ignore: avoid_print
      print('$name: worst ${result.worst.toStringAsFixed(3)}, the drawer ${off(panel, want).toStringAsFixed(3)}');
      expect(result.problems, isEmpty, reason: result.problems.join('\n'));
      expect(off(panel, want), lessThanOrEqualTo(tolerance), reason: 'the drawer $panel, the page $want');
      expect(tester.widgetList<LinkPill>(find.byType(LinkPill)).first.open, isTrue);
      await shot(tester, name);
      view.destroy();
    });
  }

  for (final name in const <String>['menu', 'menu-dark', 'menu-unread']) {
    testWidgets('$name: the drawer, part by part, where the page has it', (tester) async {
      final page = fixture(name);
      if (page['menu'] == 'unread') notion.known.clear();
      await pumpApp(
        tester,
        prefs: AppPreferences(theme: page['theme'] as String),
        ratio: 2,
        home: BackScope(
          child: Builder(
            // One device pixel to the logical one for layout, as the page was measured (test/editor/view/support.dart).
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
              child: Stack(children: <Widget>[MarkMenu(props: MarkMenuProps(name: 'notion', url: t(1), words: 'Buy milk', say: (_) {}, close: () {}, unlink: () {}))]),
            ),
          ),
        ),
      );
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final parts = (page['parts'] as List).cast<Map<String, dynamic>>();
      final problems = <String>[];
      var worst = 0.0;
      // The page's parts of a class, or of a tag inside a class, against the boxes wearing a key here. A block the
      // page stretches across the sheet is held by its start, top and foot where the box here hugs its words.
      void hold(String what, bool Function(Map<String, dynamic> part) which, Finder drawn, {bool right = true}) {
        final want = parts.where(which).map((part) => rectOf(part['rect'] as Object)).toList();
        final got = <Rect>[for (final box in tester.renderObjectList<RenderBox>(drawn)) box.localToGlobal(Offset.zero) & box.size];
        if (want.length != got.length) {
          problems.add('$what: ${got.length} drawn, the page ${want.length}');
          return;
        }
        for (var i = 0; i < want.length; i++) {
          final a = got[i], b = right ? want[i] : Rect.fromLTRB(want[i].left, want[i].top, a.right, want[i].bottom);
          final d = off(a, b);
          if (d > worst) worst = d;
          if (d > tolerance) problems.add('$what $i: $a, the page ${want[i]}');
        }
      }

      bool Function(Map<String, dynamic>) cls(String name) => (part) => (part['classes'] as List).contains(name);
      Finder key(String name) => find.byKey(ValueKey<String>(name));
      hold('sheet', cls('sheet'), key('sheet-panel'));
      hold('head', cls('head'), key('markMenu-head'));
      hold('eyebrow', cls('eyebrow'), key('markMenu-eyebrow'), right: false);
      hold('name', (part) => part['tag'] == 'span' && (part['classes'] as List).isEmpty, key('markMenu-name'));
      hold('status', cls('status'), key('markMenu-status'));
      hold('stage', cls('stage'), key('markMenu-stage'));
      hold('fact', cls('fact'), find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('markMenu-fact-')));
      hold('title', cls('title'), key('markMenu-title'), right: false);
      hold('dt', (part) => part['tag'] == 'dt', key('markMenu-dt'), right: false);
      hold('dd', (part) => part['tag'] == 'dd', key('markMenu-dd'), right: false);
      hold('quiet', cls('quiet'), key('markMenu-quiet'), right: false);
      hold('options', cls('options'), key('markMenu-options'));
      hold('option', cls('option'), find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('markMenu-option-')));
      hold('icon', cls('icon'), key('markMenu-icon'));
      hold('label', cls('label'), key('markMenu-label'));
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(page['label'] as String))), findsWidgets);
      handle.dispose();
      // ignore: avoid_print
      print('$name: worst ${worst.toStringAsFixed(3)}');
      expect(problems, isEmpty, reason: problems.join('\n'));
      await shot(tester, name);
    });
  }

  for (final name in const <String>['swipe', 'swipe-armed', 'swipe-armed-dark', 'swipe-busy']) {
    testWidgets('$name: the line under the finger and the tile behind it, where the page has them', (tester) async {
      final page = fixture(name);
      final view = await pumpNote(tester, page['doc'] as String, more: extensions(), theme: page['theme'] as String);
      final swiped = (page['swiped'] as Map).cast<String, dynamic>();
      final from = swiped['lineFrom'] as int;
      final wantLine = rectOf(swiped['lineRect'] as Object), wantTile = (page['tile'] as Map).cast<String, dynamic>();
      // The page's own gesture: down at 320, across the intent, then to where it was measured.
      final y = (wantLine.top + wantLine.bottom) / 2;
      final end = name == 'swipe' ? 260.0 : 170.0;
      sendPointer(view, PointerDownEvent(pointer: 7, position: Offset(320, y)));
      sendPointer(view, PointerMoveEvent(pointer: 7, position: Offset(300, y), timeStamp: const Duration(milliseconds: 10)));
      sendPointer(view, PointerMoveEvent(pointer: 7, position: Offset(end, y), timeStamp: const Duration(milliseconds: 20)));
      if (name == 'swipe-busy') sendPointer(view, PointerUpEvent(pointer: 7, position: Offset(end, y)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final result = held(tester, page, movedLines: <int>{from});
      final problems = <String>[...result.problems];
      final line = borderBox(drawnLines(tester).firstWhere((line) => line.from == from));
      if (off(line, wantLine) > tolerance) problems.add('the line $line, the page $wantLine');
      final tile = tester.renderObject<RenderSwipeTile>(find.byType(SwipeTile));
      final box = tile.globalTileRect!;
      if (off(box, rectOf(wantTile['rect'] as Object)) > tolerance) problems.add('the tile $box, the page ${wantTile['rect']}');
      // `text-transform: uppercase` is the page's drawing; its text is the action's own word.
      expect(tile.tile.word, (wantTile['text'] as String).toUpperCase());
      expect(swipeOf(view.state)!.armed, (wantTile['attrs'] as Map).containsKey('data-armed'));
      expect(tile.tile.opacity, closeTo(double.parse(wantTile['opacity'] as String), 0.001));
      expect(tile.wordWidth, closeTo((wantTile['textWidth'] as num).toDouble(), tolerance), reason: 'how wide the tile’s word is set');
      // ignore: avoid_print
      print('$name: worst ${result.worst.toStringAsFixed(3)}, line ${off(line, wantLine).toStringAsFixed(3)}, tile ${off(box, rectOf(wantTile['rect'] as Object)).toStringAsFixed(3)}');
      expect(problems, isEmpty, reason: problems.join('\n'));
      await shot(tester, name);
      view.destroy();
    });
  }
}
