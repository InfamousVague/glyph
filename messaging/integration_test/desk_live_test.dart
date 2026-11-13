import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/desktop/desk.dart';
import 'package:ghost_messaging/desktop/link/link.dart';
import 'package:ghost_messaging/desktop/main.dart';
import 'package:ghost_messaging/desktop/ui/wizard.dart';
import 'package:ghost_messaging/kit/settings_kit.dart';
import 'package:ghost_messaging/ui/common.dart';
import 'package:ghost_messaging/ui/computers.dart';
import 'package:integration_test/integration_test.dart';

/// The real Mac app, started and driven here, against the real phone app on an emulator (docs/desktop.md, "Trying
/// it"). It is half of a run: this presses the Mac's buttons and says what it sees, a line at a time, and whoever
/// runs it presses the phone's (adb) as the lines ask:
///
///     flutter test integration_test/desk_live_test.dart -d macos \
///       --dart-define=DESK_MODE=local --dart-define=DESK_PEER=127.0.0.1:47900
///
/// - `DESK-CODE <code>`: paste it on the phone (Settings › Computers › Pair a computer), then `adb forward` the port
///   the phone says it listens on to DESK_PEER's (local), or `adb reverse` the relay's port (relay).
/// - `DESK-DIGITS <six>`: the phone should show the same; press "They match" there.
/// - `DESK-WAITING-FOR-TEXT`: send the emulator a text from 5550100 with "Live from the emulator" in it.
/// - `DESK-SENT <words>`: the phone's own store should now hold those words as sent.
///
/// DESK_MODE is local, relay or both; DESK_RELAY is the relay's address; DESK_SHOTS is a port on this Mac that
/// pictures of the window are sent to, if one is listening.
const _mode = String.fromEnvironment('DESK_MODE', defaultValue: 'local');
const _peer = String.fromEnvironment('DESK_PEER', defaultValue: '127.0.0.1:47900');
const _relay = String.fromEnvironment('DESK_RELAY', defaultValue: 'ws://127.0.0.1:8787/relay');
const _shots = int.fromEnvironment('DESK_SHOTS', defaultValue: 47990);
const _unpair = bool.fromEnvironment('DESK_UNPAIR', defaultValue: true);

void say(String line) {
  // ignore: avoid_print
  print(line);
}

void main() {
  // Every frame is drawn, as when a person runs the app. A test's own way is to draw only when it asks for a frame,
  // which made the window jerk along at a few frames a second while this drove it (Matt, 2026-11-13: "the loading
  // indicator is at a few fps instead of smooth"; integration_test/desk_frames_test.dart counts them).
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('the Mac app pairs with the phone, lists, hears a new text and sends one ($_mode)', (tester) async {
    Future<void> until(bool Function() test, String what, {Duration max = const Duration(minutes: 4)}) async {
      final end = DateTime.now().add(max);
      while (!test()) {
        if (DateTime.now().isAfter(end)) fail('Never happened: $what');
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// A picture of the window, sent to whoever listens on DESK_SHOTS.
    Future<void> shot(String name) async {
      try {
        await tester.pump(const Duration(milliseconds: 400));
        final view = tester.binding.renderViews.first;
        // ignore: invalid_use_of_protected_member
        final layer = view.debugLayer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & (view.size * view.flutterView.devicePixelRatio), pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final socket = await Socket.connect('127.0.0.1', _shots, timeout: const Duration(seconds: 2));
        socket.add('$name\n'.codeUnits);
        socket.add(bytes.buffer.asUint8List());
        await socket.flush();
        await socket.close();
      } catch (e) {
        say('DESK-NOTE no picture of $name: $e');
      }
    }

    final dir = Directory.systemTemp.createTempSync('ghost-desk-live');
    await desktopMain(peers: _mode == 'relay' ? const [] : [Peer.parse(_peer)!], folder: dir.path, bonjour: false);
    await until(() => find.text('Your texts, on your Mac').evaluate().isNotEmpty, 'the wizard');
    final link = DeskScope.of(tester.element(find.byType(PairWizard))).link;
    say('DESK-NAME ${link.name}');

    // The wizard: the three ways to connect are all there, and the first is the one chosen to start with.
    for (final m in connectionModes) {
      expect(find.text(m.label), findsOneWidget);
    }
    expect(tester.widget<Pick>(find.byWidgetPredicate((w) => w is Pick && w.label == 'Use local network, then relay')).checked, isTrue);
    await shot('1-wizard');
    final label = connectionModes.firstWhere((m) => m.id == _mode).label;
    await tester.tap(find.byWidgetPredicate((w) => w is Pick && w.label == 'Use ${label.toLowerCase()}'));
    await tester.pump(const Duration(milliseconds: 300));
    // The relay's address is under the choices, out of a short window's view until it is scrolled to.
    await tester.scrollUntilVisible(find.byType(EditableText), 240, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(EditableText).first, _relay);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Show the pairing code'));
    await until(() => link.attempt != null, 'the pairing code');
    expect(link.attempt!.offer.mode, _mode);
    say('DESK-CODE ${link.attempt!.offer.text}');
    await shot('2-code');

    await until(() => link.attempt?.phase == 'code', 'the phone', max: const Duration(minutes: 8));
    say('DESK-DIGITS ${link.attempt!.code} via=${link.via} phone=${link.attempt!.phoneName}');
    await shot('3-digits');
    await tester.tap(find.text('They match'));
    await until(() => link.phone != null && link.online, 'being paired', max: const Duration(minutes: 5));
    say('DESK-PAIRED via=${link.via} mode=${link.phone!.mode} phone=${link.phone!.name}');
    if (_mode == 'local') expect(link.via, 'local');
    if (_mode == 'relay') expect(link.via, 'relay');

    // The conversations, read from the phone.
    await until(() => find.textContaining('5550100').evaluate().isNotEmpty, 'the conversations');
    say('DESK-LISTED');
    await shot('4-conversations');
    await tester.tap(find.textContaining('5550100').first);
    await until(() => find.text('See you at 7').evaluate().length >= 2, 'the conversation'); // in the list and as a bubble
    await shot('5-conversation');

    // A text arrives on the phone while the conversation is open here.
    say('DESK-WAITING-FOR-TEXT');
    await until(() => find.textContaining('Live from the emulator').evaluate().length >= 2, 'the new text', max: const Duration(minutes: 5));
    say('DESK-HEARD via=${link.via}');
    await shot('6-new-text');

    // And one is typed here: it goes through the phone.
    final words = 'Sent from the Mac by $_mode at ${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    await tester.enterText(find.byType(EditableText).last, words);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send'));
    await until(() => find.text(words).evaluate().isNotEmpty, 'the sent text as a bubble', max: const Duration(minutes: 1));
    say('DESK-SENT $words');
    await tester.pump(const Duration(seconds: 3));
    await shot('7-sent');

    if (_unpair) {
      // Unpaired from here: the wizard is back, and the phone is told.
      await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Settings'));
      await until(() => find.text('Unpair this phone').evaluate().isNotEmpty, 'Settings');
      await shot('8-settings');
      await tester.ensureVisible(find.text('Unpair this phone'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Unpair this phone'));
      await until(() => find.text('Unpair').evaluate().isNotEmpty, 'the question');
      await tester.tap(find.text('Unpair').last);
      await until(() => link.phone == null && find.text('Your texts, on your Mac').evaluate().isNotEmpty, 'the wizard again');
      say('DESK-UNPAIRED');
    }
    say('DESK-DONE');
    await tester.pump(const Duration(seconds: 2));
  }, timeout: const Timeout(Duration(minutes: 25)));
}
