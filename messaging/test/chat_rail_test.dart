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

    // Matt, 2026-11-25: "i'd like to be able to press and hold to drag through the chat map and have it magnify out where
    // my thumb is like the mac dock does when hovering".
    test('the lines swell under the finger, most right under it, and are as they were a little way off', () {
      expect(ChatRail.magnifyAt(0), ChatRail.magnifyMost);
      expect(ChatRail.magnifyAt(10), lessThan(ChatRail.magnifyMost));
      expect(ChatRail.magnifyAt(10), greaterThan(ChatRail.magnifyAt(30)));
      expect(ChatRail.magnifyAt(-30), ChatRail.magnifyAt(30));
      expect(ChatRail.magnifyAt(120), closeTo(1, 0.01));
    });

    testWidgets('a finger held on the map and drawn along it takes the chat with it, swollen under it, and lets go', (tester) async {
      final c = await open(tester, _chat());
      final rail = find.byKey(const ValueKey('chat-rail'));
      final box = tester.getRect(rail);
      final touch = await tester.startGesture(box.bottomCenter - const Offset(0, 6));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing, reason: 'a hold is not a press: no list');
      for (var i = 1; i <= 10; i++) {
        await touch.moveTo(Offset(box.center.dx, box.bottom - 6 - (box.height - 12) * i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester);
      expect(c.offset, greaterThan(c.position.maxScrollExtent - 60), reason: 'drawn to the top, the chat is at its oldest');
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/held.png'));
      await touch.moveTo(box.center);
      await tester.pump(const Duration(milliseconds: 16));
      await settle(tester);
      expect(c.offset, lessThan(c.position.maxScrollExtent - 60), reason: 'and back down with it');
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/held-middle.png'));
      await touch.up();
      await settle(tester);
      expect(tester.takeException(), isNull);
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

    testWidgets('a press on a stretch goes to where it begins, exactly, however far and however tall the rows between', (tester) async {
      // Rows of very different heights, so a guess by the scroll's share of its length lands somewhere else.
      final marks = _chat();
      final sheet = await loadSheet(tester);
      final c = ScrollController();
      addTearDown(c.dispose);
      await pumpScreen(
        tester,
        sheet,
        ChatRail(
          controller: c,
          marks: marks,
          chat: 'tall-rows',
          child: ListView.builder(controller: c, reverse: true, itemCount: marks.length, itemBuilder: (context, i) => SizedBox(key: ValueKey('row-$i'), height: i < 20 ? 30 : (i < 40 ? 140 : 60), child: Text(marks[i].text))),
        ),
        AppState(),
        size: const Size(700, 600),
        platform: 'desktop',
      );
      await tester.pump();
      await tester.pump();
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await tester.pump();
      await tester.pump();
      // The middle stretch: messages 20 to 39, the oldest of them 39.
      final middle = find.byKey(const ValueKey('chat-rail-stretch-39'));
      await mouse.moveTo(tester.getCenter(middle));
      await mouse.down(tester.getCenter(middle));
      await mouse.up();
      await settle(tester);
      expect(find.byKey(const ValueKey('row-39')), findsOneWidget, reason: 'the stretch\'s first message is on the screen');
      expect(tester.getRect(find.byKey(const ValueKey('row-39'))).top, closeTo(12, 1), reason: 'at the top, to read on from');
      // And the oldest, at the very top of the chat.
      final oldest = find.byKey(const ValueKey('chat-rail-stretch-59'));
      await mouse.moveTo(tester.getCenter(oldest));
      await mouse.down(tester.getCenter(oldest));
      await mouse.up();
      await settle(tester);
      expect(c.offset, c.position.maxScrollExtent);
      expect(tester.getRect(find.byKey(const ValueKey('row-59'))).top, closeTo(0, 1));
      // A press on the map itself: the message under it, in the middle of the screen.
      await mouse.moveTo(tester.getRect(rail).bottomCenter - const Offset(0, 2));
      await mouse.down(tester.getRect(rail).bottomCenter - const Offset(0, 2));
      await mouse.up();
      await settle(tester);
      expect(c.offset, 0, reason: 'the newest');
    });

    testWidgets('on a phone a press opens the list, a press on its first row goes there, and a press outside puts it away', (tester) async {
      final c = await open(tester, _chat());
      final rail = find.byKey(const ValueKey('chat-rail'));
      await tester.tap(rail);
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsOneWidget);
      // Outside: away, and the chat does not take the press.
      await tester.tapAt(const Offset(80, 300));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
      expect(c.offset, 0);
      // Again, and the first row: the oldest stretch.
      await tester.tap(rail);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat-rail-stretch-59')));
      await settle(tester);
      expect(c.offset, c.position.maxScrollExtent, reason: 'at the oldest');
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing, reason: 'put away once somewhere is chosen');
    });

    testWidgets('the list keeps the stretch on the screen in its middle as the chat is scrolled', (tester) async {
      // Many stretches, more than the list shows at once.
      final marks = [
        for (var s = 0; s < 12; s++)
          for (var i = 0; i < 6; i++) RailMark(at: _now - s * 5 * 60 * _minute - i * _minute, who: 'maya', mine: false, name: 'Maya', text: 'stretch $s line $i'),
      ];
      final c = await open(tester, marks);
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      final list = tester.getRect(find.byKey(const ValueKey('chat-rail-list')));
      c.jumpTo(c.position.maxScrollExtent);
      await settle(tester);
      final oldest = tester.getRect(find.byKey(const ValueKey('chat-rail-stretch-71')));
      expect(oldest.top, greaterThanOrEqualTo(list.top), reason: 'the oldest stretch, now on the screen, is in the list\'s view');
      expect(oldest.bottom, lessThanOrEqualTo(list.bottom));
      c.jumpTo(0);
      await settle(tester);
      final newest = tester.getRect(find.byKey(const ValueKey('chat-rail-stretch-5')));
      expect(newest.top, greaterThanOrEqualTo(list.top));
      expect(newest.bottom, lessThanOrEqualTo(list.bottom));
    });

    // Matt, 2026-11-25: "using the chat map is still pretty laggy and i can't scroll up and down in the popup menu to
    // scroll up and down either".
    testWidgets('a wheel turned over the list of stretches, or over the map, scrolls the chat', (tester) async {
      final c = await open(tester, _week());
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      final list = find.byKey(const ValueKey('chat-rail-list'));
      expect(list, findsOneWidget);
      expect(c.offset, 0);
      // Up the page, toward what is older: the chat is drawn bottom up, so its scroll grows.
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(list), kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, -300)));
      await settle(tester);
      expect(c.offset, closeTo(300, 1));
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(rail), kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, -200)));
      await settle(tester);
      expect(c.offset, closeTo(500, 1));
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(list), kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, 500)));
      await settle(tester);
      expect(c.offset, closeTo(0, 1));
      expect(list, findsOneWidget, reason: 'still open under the mouse');
    });

    testWidgets('two fingers on a trackpad over the list scroll the chat too', (tester) async {
      final c = await open(tester, _week());
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      final at = tester.getCenter(find.byKey(const ValueKey('chat-rail-list')));
      final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pad.panZoomStart(at);
      await pad.panZoomUpdate(at, pan: const Offset(0, 60));
      await pad.panZoomUpdate(at, pan: const Offset(0, 260));
      await pad.panZoomEnd();
      await settle(tester);
      expect(c.offset, greaterThan(150));
    });

    testWidgets('scrolling the chat builds the list of stretches again only when another stretch comes onto the screen', (tester) async {
      var faces = 0;
      final marks = _week();
      final sheet = await loadSheet(tester);
      final c = ScrollController();
      addTearDown(c.dispose);
      await pumpScreen(
        tester,
        sheet,
        ChatRail(
          controller: c,
          marks: marks,
          chat: 'builds',
          face: (who, name, mine, size) {
            faces++;
            return SizedBox.square(dimension: size);
          },
          child: ListView.builder(controller: c, reverse: true, itemCount: marks.length, itemBuilder: (context, i) => SizedBox(height: 48, child: Text(marks[i].text))),
        ),
        AppState(),
        size: const Size(700, 600),
        platform: 'desktop',
      );
      await tester.pump();
      await tester.pump();
      final rail = find.byKey(const ValueKey('chat-rail'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      final before = faces;
      expect(before, greaterThan(0));
      // A little way, inside the newest stretch: nothing of the list is built again.
      for (var i = 1; i <= 10; i++) {
        c.jumpTo(i * 4.0);
        await tester.pump();
      }
      expect(faces, before);
      // To the oldest end: another stretch is the one on the screen, and the list says so.
      c.jumpTo(c.position.maxScrollExtent);
      await settle(tester);
      expect(faces, greaterThan(before));
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
