import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/chat_rail.dart';

import 'support/list_harness.dart';

// Matt, 2026-11-25: "in the right hand of the chat gutter add this same style of chat scrolling to show frequency of
// messages and who differently sent messages etc", then "hovering over it should show profile pictures and a brief
// summary of the messages if a local AI is enabled". lib/ui/chat_rail.dart. Run with --update-goldens, the pictures
// are build/chat-rail/*.png.

const _minute = 60 * 1000;
final _now = DateTime(2026, 11, 25, 15).millisecondsSinceEpoch;

/// A chat, newest first: three bursts, a day apart, between Maya and oneself.
List<RailMark> _chat({int each = 20}) => [
      for (var day = 0; day < 3; day++)
        for (var i = 0; i < each; i++)
          RailMark(
            at: _now - day * 24 * 60 * _minute - i * _minute ~/ 2,
            who: i.isEven ? 'maya' : 'me',
            mine: i.isOdd,
            name: i.isEven ? 'Maya Chen' : 'You',
            text: 'day $day line ${each - i}',
          ),
    ];

Future<void> _fonts() async {
  final loader = FontLoader('Inter Variable')..addFont(File('assets/fonts/InterVariable-latin.ttf').readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  await loader.load();
}

/// A group's chat over a week, for a picture: busy evenings, a quiet day, three people and oneself.
List<RailMark> _week() {
  const people = [('maya', 'Maya Chen'), ('sam', 'Sam Okafor'), ('me', 'You'), ('lee', 'Lee Park')];
  const said = [
    'are we still on for Friday?', 'yes! 7 at the usual place', 'I can bring the projector', 'who has the cable though',
    'me, it is in the car', 'perfect', 'running ten late', 'no rush, the table is ours till 9', 'ok ordering for everyone',
    'get the dumplings', 'photos from last night are up', 'that one of Sam is going on the wall',
  ];
  final out = <RailMark>[];
  var at = _now;
  var k = 0;
  for (var burst = 0; burst < 7; burst++) {
    final n = [34, 6, 22, 3, 41, 12, 18][burst];
    for (var i = 0; i < n; i++, k++) {
      final p = people[(k * 7 + burst + (i ~/ 3)) % people.length];
      out.add(RailMark(at: at, who: p.$1, mine: p.$1 == 'me', name: p.$2, text: said[(said.length - 1 - (k % said.length))]));
      at -= (i % 5 == 4 ? 9 : 1) * _minute ~/ (burst.isEven ? 2 : 1);
    }
    at -= [5, 19, 3, 26, 14, 40, 8][burst] * 60 * _minute;
  }
  return out;
}

void main() {
  group('the lines', () {
    test('one for each message while they fit, a long line in a burst and a short one alone', () {
      final marks = [
        for (var i = 0; i < 9; i++) RailMark(at: _now - i * 20 * 1000, who: 'maya', mine: false),
        RailMark(at: _now - 3 * 60 * _minute, who: 'me', mine: true),
      ];
      final ticks = ChatRail.ticksOf(marks, 40);
      expect(ticks, hasLength(10));
      expect(ticks.first.rate, 1, reason: 'nine within minutes');
      expect(ticks.last.rate, 0, reason: 'alone, hours before');
      expect(ticks.last.mine, isTrue);
      expect(ticks.first.who, 'maya');
    });

    test('more messages than lines: each line is several, and whoever wrote most of them', () {
      final marks = [
        for (var i = 0; i < 300; i++) RailMark(at: _now - i * _minute, who: i < 150 ? (i % 3 == 0 ? 'me' : 'maya') : 'me', mine: i < 150 ? i % 3 == 0 : true),
      ];
      final ticks = ChatRail.ticksOf(marks, 50);
      expect(ticks, hasLength(50));
      expect(ticks.first.who, 'maya');
      expect(ticks.first.mine, isFalse);
      expect(ticks.last.who, 'me');
      expect(ticks.last.mine, isTrue);
    });

    test('nothing for nothing', () {
      expect(ChatRail.ticksOf(const [], 10), isEmpty);
      expect(ChatRail.stretchesOf(const []), isEmpty);
    });
  });

  group('the stretches', () {
    test('cut where the chat paused, the newest first, each with who wrote in it and how it began', () {
      final s = ChatRail.stretchesOf(_chat());
      expect(s, hasLength(3));
      expect(s.first.newest, 0);
      expect(s.first.oldest, 19);
      expect(s.last.oldest, 59);
      expect(s.first.count, 20);
      expect(s.first.people.map((p) => p.who).toSet(), {'maya', 'me'});
      expect(s.first.opening, 'You: day 0 line 1', reason: 'its oldest words');
      expect(s.first.lines.split('\n').first, 'You: day 0 line 1');
      expect(s.first.lines.split('\n'), hasLength(20));
    });

    test('never more than a dozen, however often a chat paused', () {
      final marks = [for (var i = 0; i < 400; i++) RailMark(at: _now - i * 40 * 24 * 60 * _minute, who: 'maya', mine: false, text: 'hello $i')];
      final s = ChatRail.stretchesOf(marks);
      expect(s.length, lessThanOrEqualTo(ChatRail.mostStretches));
      expect(s.fold<int>(0, (n, x) => n + x.count), 400, reason: 'every message in one');
    });

    test('too little to sum up has no lines for a model, and something that happened is no part of one', () {
      final s = ChatRail.stretchesOf([
        RailMark(at: _now, who: 'maya', mine: false, name: 'Maya', text: 'ok'),
        RailMark(at: _now - 1000, who: '', mine: false, text: 'Maya joined', quiet: true),
      ]);
      expect(s.single.lines, isEmpty);
      expect(s.single.opening, 'Maya: ok');
      expect(s.single.people.map((p) => p.who), ['maya']);
    });
  });

  group('in a chat', () {
    Future<ScrollController> open(WidgetTester tester, List<RailMark> marks, {Future<String?> Function(String)? summarize}) async {
      final sheet = await loadSheet(tester);
      final c = ScrollController();
      addTearDown(c.dispose);
      await pumpScreen(
        tester,
        sheet,
        ChatRail(
          controller: c,
          marks: marks,
          chat: 'test-${marks.length}-${summarize.hashCode}',
          summarize: summarize,
          child: ListView.builder(controller: c, reverse: true, itemCount: marks.length, itemBuilder: (context, i) => SizedBox(height: 48, child: Text(marks[i].text))),
        ),
        AppState(),
        size: const Size(700, 600),
        platform: 'desktop',
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    setUpAll(_fonts);

    testWidgets('a picture of a week of a group', (tester) async {
      Future<String?> sum(String lines) async => switch (lines.split('\n').length) {
            > 30 => 'Dinner on Friday at 7: Sam brings the projector, Maya orders for the table.',
            > 15 => 'Who has the cable, and photos from last night going up.',
            _ => 'Running late; the table is held until 9.',
          };
      await open(tester, _week(), summarize: sum);
      final rail = find.byKey(const ValueKey('chat-rail'));
      expect(rail, findsOneWidget);
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/week.png'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsOneWidget);
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/week-list.png'));
    });

    testWidgets('a short chat has no map', (tester) async {
      await open(tester, _chat(each: 2));
      expect(find.byKey(const ValueKey('chat-rail')), findsNothing);
    });

    testWidgets('the map is at the right, and a press on it goes there', (tester) async {
      final c = await open(tester, _chat());
      final rail = find.byKey(const ValueKey('chat-rail'));
      expect(rail, findsOneWidget);
      expect(tester.getRect(rail).right, 700);
      expect(c.offset, 0);
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/rail.png'));
      // Its top is the oldest end.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getRect(rail).topCenter + const Offset(0, 2));
      addTearDown(mouse.removePointer);
      await mouse.down(tester.getRect(rail).topCenter + const Offset(0, 2));
      await mouse.up();
      await settle(tester);
      expect(c.offset, greaterThan(c.position.maxScrollExtent - 60), reason: 'at the oldest');
    });

    testWidgets('the mouse over it lists the stretches, with a face each and how each began; a press on one goes to it', (tester) async {
      final c = await open(tester, _chat());
      final rail = find.byKey(const ValueKey('chat-rail'));
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await tester.pump();
      await tester.pump();
      final list = find.byKey(const ValueKey('chat-rail-list'));
      expect(list, findsOneWidget);
      for (final day in [0, 1, 2]) {
        expect(find.descendant(of: list, matching: find.text('You: day $day line 1')), findsOneWidget);
      }
      expect(find.descendant(of: list, matching: find.textContaining('20 messages')), findsNWidgets(3));
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/list.png'));
      // The oldest stretch is the top row.
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('chat-rail-stretch-59'))));
      await tester.pump();
      expect(list, findsOneWidget, reason: 'still open with the mouse in the list');
      await mouse.down(tester.getCenter(find.byKey(const ValueKey('chat-rail-stretch-59'))));
      await mouse.up();
      await settle(tester);
      expect(c.offset, greaterThan(c.position.maxScrollExtent * 0.6));
      // And away from both, it closes.
      await mouse.moveTo(const Offset(100, 300));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
    });

    testWidgets('with a model to ask, each stretch is its summary, asked for once', (tester) async {
      final asked = <String>[];
      Future<String?> sum(String lines) async {
        asked.add(lines);
        return 'Plans for day ${asked.length}';
      }

      await open(tester, _chat(), summarize: sum);
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      expect(asked, hasLength(3));
      expect(asked.first.split('\n').first, 'You: day 0 line 1', reason: 'the newest stretch first, oldest words first');
      for (final n in [1, 2, 3]) {
        expect(find.text('Plans for day $n'), findsOneWidget);
      }
      // Away and back: nothing asked again.
      await mouse.moveTo(const Offset(100, 300));
      await settle(tester);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      expect(asked, hasLength(3));
      expect(find.text('Plans for day 1'), findsOneWidget);
    });
  });
}
