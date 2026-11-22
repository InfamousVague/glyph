import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/hangout_screen.dart';
import 'package:ghost_messaging/ui/space_thread.dart';

import 'support/space_call_harness.dart';

/// Threads in a space's chat (GMFB-36, from the Uplink gap review): a thread's replies stay off the chat, a line under
/// the message says how many and who wrote last, and pressing it opens the thread with its replies and a box.
void main() {
  testWidgets('the chat shows a thread\'s line, not its replies; the line opens the thread', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final room = h.room(threaded: true);
    expect(room.timeline.length, 4);
    await h.shoot(tester, HangoutChat(room: room), 'thread-chat', size: SpaceHarness.phone);
    expect(tester.takeException(), isNull);
    expect(find.text('Which movie?'), findsNothing, reason: 'a thread\'s reply is not in the chat');
    expect(find.text('2 replies'), findsOneWidget);
    await tester.tap(find.text('2 replies'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(SpaceThreadScreen), findsOneWidget);
    expect(find.text('Starting the movie in 10, hop in'), findsWidgets);
    expect(find.text('Which movie?'), findsOneWidget);
    expect(find.text('The new one with the robots'), findsOneWidget);
    expect(find.text('Reply in thread'), findsOneWidget, reason: 'the box');
    await tester.pumpWidget(const SizedBox());
  });

  test('how long ago, shortly', () {
    final now = DateTime(2026, 11, 22, 12);
    expect(ago(now.subtract(const Duration(seconds: 20)), now), 'now');
    expect(ago(now.subtract(const Duration(minutes: 5)), now), '5m');
    expect(ago(now.subtract(const Duration(hours: 3)), now), '3h');
    expect(ago(now.subtract(const Duration(days: 2)), now), '2d');
  });
}
