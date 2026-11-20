import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/keys.dart';

/// The keyboard's commands (lib/keys.dart; Matt, 2026-11-20: "add push to talk and full keyboard commands with a
/// keyboard shortcuts setting in settings").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null));

  // What the frame is handed as a key comes down, with what is held held (simulated).
  Future<KeyCommand?> press(WidgetTester tester, Keys keys, LogicalKeyboardKey key, {List<LogicalKeyboardKey> held = const [], bool typing = false}) async {
    KeyCommand? got;
    bool handler(KeyEvent e) {
      if (e is KeyDownEvent && e.logicalKey == key) got = keys.commandFor(e, typing: typing);
      return false;
    }

    HardwareKeyboard.instance.addHandler(handler);
    for (final h in held) {
      await tester.sendKeyDownEvent(h);
    }
    await tester.sendKeyEvent(key);
    for (final h in held.reversed) {
      await tester.sendKeyUpEvent(h);
    }
    HardwareKeyboard.instance.removeHandler(handler);
    return got;
  }

  final primary = Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  testWidgets('every command has its own keys, and the keys pressed find it: Shift and the rest must match', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final keys = Keys.forTest()..start(AppState());
    final used = {for (final c in KeyCommand.values) Keys.defaults[c]};
    expect(used.length, KeyCommand.values.length, reason: 'no two on the same keys');
    expect(await press(tester, keys, LogicalKeyboardKey.keyN, held: [primary]), KeyCommand.newChat);
    expect(await press(tester, keys, LogicalKeyboardKey.keyM, held: [primary, LogicalKeyboardKey.shiftLeft]), KeyCommand.toggleMute);
    expect(await press(tester, keys, LogicalKeyboardKey.keyM, held: [primary]), isNull, reason: 'without Shift it is not Mute');
    expect(await press(tester, keys, LogicalKeyboardKey.backquote), KeyCommand.pushToTalk);
  });

  testWidgets('a command on a key alone waits while typing; one with Cmd or Ctrl does not', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final keys = Keys.forTest()..start(AppState());
    expect(await press(tester, keys, LogicalKeyboardKey.backquote, typing: true), isNull);
    expect(await press(tester, keys, LogicalKeyboardKey.keyK, held: [primary], typing: true), KeyCommand.search);
  });

  testWidgets('keys changed are kept; keys taken from another leave it on none; each can be put back', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final app = AppState();
    final keys = Keys.forTest()..start(app);
    const f2 = KeyBinding(LogicalKeyboardKey.f2);
    keys.set(KeyCommand.pushToTalk, f2);
    expect(keys.of(KeyCommand.pushToTalk), f2);
    expect(keys.changed(KeyCommand.pushToTalk), isTrue);
    // Kept with the app's choices: a new start reads them back.
    final again = Keys.forTest()..start(app);
    expect(again.of(KeyCommand.pushToTalk), f2);
    expect(await press(tester, again, LogicalKeyboardKey.f2), KeyCommand.pushToTalk);
    // New chat's keys given to Search: New chat is on none.
    again.set(KeyCommand.search, Keys.defaults[KeyCommand.newChat]);
    expect(again.of(KeyCommand.newChat), isNull);
    expect(await press(tester, again, LogicalKeyboardKey.keyN, held: [primary]), KeyCommand.search);
    again.reset(KeyCommand.newChat);
    expect(again.of(KeyCommand.newChat), Keys.defaults[KeyCommand.newChat]);
    expect(again.of(KeyCommand.search), isNull, reason: 'putting New chat back takes its keys back');
    again.resetAll();
    expect(KeyCommand.values.where(again.changed), isEmpty);
    expect(again.pushToTalk, isFalse, reason: 'push to talk is off unless switched on');
    again.setPushToTalk(true);
    expect((Keys.forTest()..start(app)).pushToTalk, isTrue);
  });

  test('keys are written as each computer writes them', () {
    const b = KeyBinding(LogicalKeyboardKey.keyM, primary: true, shift: true);
    expect(b.label, Platform.isMacOS ? 'Cmd+Shift+M' : 'Ctrl+Shift+M');
    expect(const KeyBinding(LogicalKeyboardKey.backquote).label, '`');
    expect(KeyBinding.fromJson(b.toJson()), b);
  });
}
