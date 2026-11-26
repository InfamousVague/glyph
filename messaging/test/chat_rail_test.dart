import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/chat_rail.dart';

import 'support/list_harness.dart';

// Matt, 2026-11-25: "in the right hand of the chat gutter add this same style of chat scrolling to show frequency of
// messages and who differently sent messages etc". Then, the same day: "Lets remove the popover for the summarized
// messages on the chat map for now and remove the tap and hold just allow scrolling normally it's a bit glitchy though
// when getting to the top or bottom dont change the main size of the chatmap scroll it up and down as we go back
// through history". lib/ui/chat_rail.dart. Run with --update-goldens, the pictures are build/chat-rail/*.png.

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
    /// A chat's list with its map, 700 by 600 with rows 48 tall unless [tall] says. [marks] can be given again, as
    /// when older messages are loaded.
    Future<ScrollController> openOn(WidgetTester tester, ValueNotifier<List<RailMark>> marks, {double Function(int i)? tall, ScrollPhysics? physics}) async {
      final sheet = await loadSheet(tester);
      final c = ScrollController();
      addTearDown(c.dispose);
      await pumpScreen(
        tester,
        sheet,
        ValueListenableBuilder<List<RailMark>>(
          valueListenable: marks,
          builder: (context, m, _) => ChatRail(
            controller: c,
            marks: m,
            chat: 'test',
            child: ListView.builder(
              controller: c,
              reverse: true,
              physics: physics,
              itemCount: m.length,
              itemBuilder: (context, i) => SizedBox(key: ValueKey('row-${m.length - i}'), height: tall?.call(i) ?? 48, child: Text(m[i].text)),
            ),
          ),
        ),
        AppState(),
        size: const Size(700, 600),
        platform: 'desktop',
      );
      await tester.pump();
      await tester.pump();
      return c;
    }

    Future<ScrollController> open(WidgetTester tester, List<RailMark> marks, {double Function(int i)? tall}) => openOn(tester, ValueNotifier(marks), tall: tall);

    final rail = find.byKey(const ValueKey('chat-rail'));
    RailPainter painter(WidgetTester tester) => tester.widget<CustomPaint>(find.descendant(of: rail, matching: find.byType(CustomPaint))).painter! as RailPainter;

    /// [n] messages a minute apart, newest first.
    List<RailMark> long(int n) => [for (var i = 0; i < n; i++) RailMark(at: _now - i * _minute, who: i.isEven ? 'maya' : 'me', mine: i.isOdd, name: i.isEven ? 'Maya Chen' : 'You', text: 'line ${n - i}')];

    setUpAll(_fonts);

    testWidgets('a picture of a week of a group', (tester) async {
      await open(tester, _week());
      expect(rail, findsOneWidget);
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/week.png'));
    });

    testWidgets('a short chat has no map', (tester) async {
      await open(tester, _chat(each: 2));
      expect(rail, findsNothing);
    });

    testWidgets('the map is at the right, and a press on it goes there', (tester) async {
      final c = await open(tester, _chat());
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
      // And a finger's press does the same: its foot is newer, and once the map is back there, the newest.
      for (var k = 0; k < 2; k++) {
        await tester.tapAt(tester.getRect(rail).bottomCenter - const Offset(0, 2));
        await settle(tester);
      }
      expect(c.offset, 0, reason: 'the newest');
    });

    testWidgets('a press goes to the message pressed, exactly, however tall the rows between', (tester) async {
      // Rows of very different heights, so a guess by the scroll's share of its length lands somewhere else.
      final marks = _chat();
      await open(tester, marks, tall: (i) => i < 20 ? 30 : (i < 40 ? 140 : 60));
      final box = tester.getRect(rail);
      // The 40th message from the newest (39, counted from 0), by where its line is.
      await tester.tapAt(Offset(box.center.dx, box.top + painter(tester).yOf(39)));
      await settle(tester);
      final row = find.byKey(ValueKey('row-${marks.length - 39}'));
      expect(row, findsOneWidget);
      expect(tester.getRect(row).center.dy, closeTo(300, 1), reason: 'in the middle of the screen');
    });

    // Matt, 2026-11-25: "Lets remove the popover for the summarized messages on the chat map for now and remove the tap
    // and hold".
    testWidgets('no list of stretches opens from it, under a mouse or a press, and a finger held on it moves nothing', (tester) async {
      final c = await open(tester, _chat());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(rail));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rail) + const Offset(0, 1));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
      expect(find.textContaining('20 messages'), findsNothing);
      await mouse.moveTo(const Offset(100, 300));
      await tester.pump();
      // Held at its foot, where the chat is already: nothing moves, nothing opens.
      final size = tester.getSize(rail);
      final touch = await tester.startGesture(tester.getRect(rail).bottomCenter - const Offset(0, 2));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
      expect(c.offset, 0);
      expect(tester.getSize(rail), size);
      await touch.up();
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-rail-list')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Matt, 2026-11-26: "Bring back the magnifying effect when scrolling through the chat map".
    testWidgets('the map swells under a mouse over it and under a finger scrolling over it, and settles once they go', (tester) async {
      final c = await open(tester, long(300));
      final box = tester.getRect(rail);
      final rest = [for (var i = 0; i < 80; i++) painter(tester).yOf(i)];
      expect([for (var i = 0; i < 80; i++) painter(tester).growOf(i)], everyElement(1.0));
      // A mouse over the middle: the line under it is the largest, those far off are as they were.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 300));
      addTearDown(mouse.removePointer);
      const under = 30;
      await mouse.moveTo(Offset(box.center.dx, box.top + rest[under]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final p = painter(tester);
      expect(p.growOf(under), closeTo(ChatRail.magnifyMost, 0.05));
      expect(p.yOf(under), closeTo(rest[under], 0.01), reason: 'the line under the pointer stays where it is');
      expect(p.growOf(under + 20), lessThan(p.growOf(under + 4)));
      expect(p.growOf(under + 40), closeTo(1, 0.01));
      expect(p.yOf(under) - p.yOf(under + 1), greaterThan(ChatRail.pitch * 1.8), reason: 'further apart under it');
      expect(p.yOf(under + 1) - p.yOf(under + 2), greaterThan(p.yOf(under + 15) - p.yOf(under + 16)));
      expect(c.offset, 0, reason: 'a mouse over it scrolls nothing');
      if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('../build/chat-rail/swell.png'));
      await mouse.moveTo(const Offset(100, 300));
      await settle(tester);
      expect(painter(tester).growOf(under), 1);
      // A finger drawn over it scrolls the chat, and the swell goes with the finger.
      final touch = await tester.startGesture(Offset(box.center.dx, box.top + 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter(tester).growOf(_nearest(painter(tester), 200)), greaterThan(2));
      for (var k = 0; k < 6; k++) {
        await touch.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(c.offset, greaterThan(60), reason: 'still scrolls the chat');
      await tester.pump(const Duration(milliseconds: 300));
      final q = painter(tester), at = _nearest(q, 320);
      expect(q.yOf(at), closeTo(320, ChatRail.pitch * ChatRail.magnifyMost), reason: 'under the finger where it is now');
      expect(q.growOf(at), greaterThan(2));
      await touch.up();
      await settle(tester);
      expect([for (var i = 0; i < 300; i += 9) painter(tester).growOf(i)], everyElement(1.0));
      expect(tester.takeException(), isNull);
    });

    // Matt, 2026-11-25: "just allow scrolling normally".
    testWidgets('a wheel turned over the map scrolls the chat', (tester) async {
      final c = await open(tester, _week());
      expect(c.offset, 0);
      // Up the page, toward what is older: the chat is drawn bottom up, so its scroll grows.
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(rail), kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, -300)));
      await settle(tester);
      expect(c.offset, closeTo(300, 1));
      await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(rail), kind: PointerDeviceKind.mouse, scrollDelta: const Offset(0, 500)));
      await settle(tester);
      expect(c.offset, closeTo(0, 1));
    });

    testWidgets('two fingers on a trackpad over the map scroll the chat too', (tester) async {
      final c = await open(tester, _week());
      final at = tester.getCenter(rail);
      final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pad.panZoomStart(at);
      await pad.panZoomUpdate(at, pan: const Offset(0, 60));
      await pad.panZoomUpdate(at, pan: const Offset(0, 260));
      await pad.panZoomEnd();
      await settle(tester);
      expect(c.offset, greaterThan(150));
    });

    testWidgets('a finger drawn over the map scrolls the chat as it does over the chat, with its glide after, and a finger put down stops the glide', (tester) async {
      final c = await open(tester, long(300));
      // Down the screen: toward what is older.
      await tester.drag(rail, const Offset(0, 200));
      await tester.pump();
      expect(c.offset, inInclusiveRange(170, 200), reason: 'the chat goes with the finger');
      await settle(tester);
      final rested = c.offset;
      await tester.fling(rail, const Offset(0, 200), 2500);
      final let = c.offset;
      expect(let, greaterThan(rested + 150));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.offset, greaterThan(let + 50), reason: 'it glides on once let go');
      final touch = await tester.startGesture(tester.getCenter(rail));
      await tester.pump(const Duration(milliseconds: 16));
      final stopped = c.offset;
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.offset, stopped, reason: 'held where the finger came down');
      await touch.moveBy(const Offset(0, -80));
      await touch.up();
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    // Matt, 2026-11-25: "it's a bit glitchy though when getting to the top or bottom dont change the main size of the
    // chatmap scroll it up and down as we go back through history". The map fitted every message into its height: 60
    // messages were 9 apart, 200 were 6 apart and several to a line, so a page of older ones drew it all again.
    testWidgets('older messages loaded in at the top leave the map its size and its lines as far apart, and it glides to them', (tester) async {
      final marks = ValueNotifier(long(50));
      final c = await openOn(tester, marks);
      expect(painter(tester).ticks, hasLength(50), reason: 'a line a message');
      expect(painter(tester).yOf(0) - painter(tester).yOf(1), ChatRail.pitch);
      c.jumpTo(c.position.maxScrollExtent);
      await settle(tester);
      final box = tester.getRect(rail);
      expect(painter(tester).yOf(0), painter(tester).tall - ChatRail.pitch / 2, reason: 'all of it fits: the newest at the map\'s foot');
      for (final n in [200, 500]) {
        final was = [for (final i in [0, 30, 49]) painter(tester).yOf(i)];
        marks.value = long(n);
        await tester.pump();
        expect([for (final i in [0, 30, 49]) painter(tester).yOf(i)], was, reason: 'no line jumps');
        await settle(tester);
        expect(tester.getRect(rail), box, reason: 'the map is where it was and as big, with $n');
        expect(painter(tester).ticks, hasLength(n), reason: 'still a line a message');
        expect(painter(tester).yOf(0) - painter(tester).yOf(1), ChatRail.pitch, reason: 'as far apart as they were');
        // Glided on to its frame: what is on the screen (the oldest dozen or so of the fifty) in its middle.
        expect(painter(tester).yOf(44), closeTo(painter(tester).tall / 2, ChatRail.pitch * 1.5));
      }
    });

    // Matt, 2026-11-26: "have it scroll up and down like there is a frame of chat history we're viewing".
    testWidgets('a chat longer than the map: the map is a frame on what is on the screen, moved with the chat, smoothly, and rests at each end', (tester) async {
      final marks = ValueNotifier(long(300));
      final c = await openOn(tester, marks);
      final size = tester.getSize(rail);
      final tall = painter(tester).tall;
      expect(tall, 540, reason: 'nine tenths of the chat\'s height, in whole lines');
      expect(painter(tester).yOf(0), tall - ChatRail.pitch / 2, reason: 'the newest at its foot');
      // Near the newest end the map rests at its foot.
      c.jumpTo(48.0 * 20);
      await settle(tester);
      expect(painter(tester).yOf(0), tall - ChatRail.pitch / 2);
      // Further back: what is on the screen (12.5 rows, from 120 up) is in the map's middle.
      c.jumpTo(48.0 * 120);
      await settle(tester);
      expect(painter(tester).yOf(126), closeTo(tall / 2, ChatRail.pitch));
      final was = painter(tester).yOf(100);
      c.jumpTo(48.0 * 120 + 20);
      await tester.pump();
      expect(painter(tester).yOf(100), closeTo(was + ChatRail.pitch * 20 / 48, 0.01), reason: 'by exactly as much as the chat was scrolled');
      final held = painter(tester).yOf(100);
      c.jumpTo(48.0 * 110);
      await settle(tester);
      expect(painter(tester).yOf(100), closeTo(held - ChatRail.pitch * (10 + 20 / 48), 0.01), reason: 'back down, and the map with it');
      // The oldest end: its line at the map's top, and no further.
      c.jumpTo(c.position.maxScrollExtent);
      await settle(tester);
      expect(painter(tester).yOf(299), ChatRail.pitch / 2);
      expect(tester.getSize(rail), size);
      // Older ones loaded there: nothing jumps, the map glides on to put what is on the screen in its middle, and
      // scrolling on up takes it up with it.
      marks.value = long(450);
      await tester.pump();
      expect(painter(tester).yOf(299), ChatRail.pitch / 2);
      await settle(tester);
      expect(painter(tester).yOf(294), closeTo(tall / 2, ChatRail.pitch));
      expect(tester.getSize(rail), size);
      final up = painter(tester).yOf(299);
      c.jumpTo(c.offset + 48);
      await settle(tester);
      expect(painter(tester).yOf(299), closeTo(up + ChatRail.pitch, 0.01));
      // And the newest end again.
      c.jumpTo(0);
      await settle(tester);
      expect(painter(tester).yOf(0), tall - ChatRail.pitch / 2);
      expect(tester.getSize(rail), size);
    });

    testWidgets('pulled past an end, as a phone\'s list can be, the map does not move or change its size', (tester) async {
      final c = await openOn(tester, ValueNotifier(long(300)), physics: const BouncingScrollPhysics());
      final size = tester.getSize(rail);
      c.jumpTo(c.position.maxScrollExtent);
      await settle(tester);
      final top = painter(tester).yOf(299);
      // A finger pulling the oldest end down past where it stops.
      final touch = await tester.startGesture(const Offset(200, 200));
      await touch.moveBy(const Offset(0, 30));
      await touch.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(c.offset, greaterThan(c.position.maxScrollExtent + 20), reason: 'pulled past the end');
      expect(painter(tester).yOf(299), top);
      expect(tester.getSize(rail), size);
      await touch.up();
      await settle(tester);
      // And the newest end.
      c.jumpTo(0);
      await settle(tester);
      final foot = painter(tester).yOf(0);
      final pull = await tester.startGesture(const Offset(200, 400));
      await pull.moveBy(const Offset(0, -30));
      await pull.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(c.offset, lessThan(-20));
      expect(painter(tester).yOf(0), foot);
      expect(tester.getSize(rail), size);
      await pull.up();
      await settle(tester);
    });
  });
}

/// The message whose line is drawn nearest [y] down the map.
int _nearest(RailPainter p, double y) {
  var best = 0;
  for (var i = 1; i < p.ticks.length; i++) {
    if ((p.yOf(i) - y).abs() < (p.yOf(best) - y).abs()) best = i;
  }
  return best;
}
