import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/root/desktop_wiring.dart';
import 'package:ghost_md/shell/desktop/desktop_commands.dart';
import 'package:ghost_md/shell/desktop/mac_drag_strip.dart';
import 'package:ghost_md/shell/desktop/mac_lights.dart';

/// A desktop's keys and the Mac's menu bar (App.tsx's own `keydown` listener, docs/DESIGN.md §144 and §210 of
/// ../glyph), the drag strip (`.app-dragBar`) and the row the Mac's window buttons are set into.
void main() {
  group('the commands', () {
    test('are named as the Mac’s menu names them', () {
      expect([for (final name in ['newNote', 'sync', 'palette', 'find', 'settings', 'quit']) desktopCommandNamed(name)],
          [DesktopCommand.newNote, DesktopCommand.sync, DesktopCommand.palette, DesktopCommand.find, DesktopCommand.settings, null]);
      expect(desktopCommandFor(LogicalKeyboardKey.keyN), DesktopCommand.newNote);
      expect(desktopCommandFor(LogicalKeyboardKey.keyR), DesktopCommand.sync);
      expect(desktopCommandFor(LogicalKeyboardKey.keyF), DesktopCommand.find);
      expect(desktopCommandFor(LogicalKeyboardKey.comma), DesktopCommand.settings);
      // Command-K is the kit's own, bound where the palette is.
      expect(desktopCommandFor(LogicalKeyboardKey.keyK), isNull);
    });

    test('ask the newest handler first, and a note under something modal does not answer Find', () {
      final commands = DesktopCommands();
      final said = <String>[];
      final under = commands.on(DesktopCommand.find, () {
        said.add('under');
        return true;
      });
      var answers = false;
      final over = commands.on(DesktopCommand.find, () {
        said.add('over');
        return answers;
      });
      expect(commands.run(DesktopCommand.find), isTrue);
      expect(said, ['over', 'under']);
      answers = true;
      said.clear();
      expect(commands.run(DesktopCommand.find), isTrue);
      expect(said, ['over']);
      commands.covered = () => true;
      expect(commands.run(DesktopCommand.find), isFalse);
      commands.covered = null;
      over();
      under();
      expect(commands.run(DesktopCommand.find), isFalse);
      expect(commands.run(DesktopCommand.newNote), isFalse);
    });

    testWidgets('are asked by Command on a Mac and Control elsewhere, alone and not held', (tester) async {
      final commands = DesktopCommands();
      final ran = <DesktopCommand>[];
      for (final command in DesktopCommand.values) {
        commands.on(command, () {
          ran.add(command);
          return true;
        });
      }
      final mac = DesktopKeys.attach(platform: TargetPlatform.macOS, commands: commands)!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      // Another modifier with it is another chord (Command-Shift-N), and a letter with no command is nothing.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      // Control is not Command on a Mac.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ran, [DesktopCommand.newNote, DesktopCommand.sync, DesktopCommand.settings, DesktopCommand.find]);
      mac.dispose();

      ran.clear();
      final windows = DesktopKeys.attach(platform: TargetPlatform.windows, commands: commands)!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ran, [DesktopCommand.newNote]);
      windows.dispose();
      // A phone's keyboard keeps its chords.
      expect(DesktopKeys.attach(platform: TargetPlatform.android, commands: commands), isNull);
    });
  });

  group('the root’s answers', () {
    test('a new note only on a place with nothing over it; Settings not over something else', () {
      final commands = DesktopCommands();
      var place = true, covered = false;
      final did = <String>[];
      final stop = wireDesktopCommands(
        commands: commands,
        onPlace: () => place,
        covered: () => covered,
        newNote: () => did.add('new'),
        refresh: () async {},
        status: () => (phase: 'idle', message: null),
        say: did.add,
        palette: () => did.add('palette'),
        settings: () => did.add('settings'),
      );
      expect(commands.run(DesktopCommand.newNote), isTrue);
      place = false;
      expect(commands.run(DesktopCommand.newNote), isFalse);
      place = true;
      covered = true;
      expect(commands.run(DesktopCommand.newNote), isFalse);
      expect(commands.run(DesktopCommand.settings), isFalse);
      expect(commands.covered!(), isTrue);
      covered = false;
      expect(commands.run(DesktopCommand.settings), isTrue);
      expect(commands.run(DesktopCommand.palette), isTrue);
      expect(did, ['new', 'settings', 'palette']);
      stop();
      expect(commands.covered, isNull);
      expect(commands.run(DesktopCommand.newNote), isFalse);
    });

    testWidgets('Command-R refreshes once and says Synced, Still syncing past five seconds, or why not', (tester) async {
      expect(syncToast((phase: 'idle', message: null)), 'Synced');
      expect(syncToast((phase: 'off', message: null)), 'Synced');
      expect(syncToast((phase: 'syncing', message: null)), 'Still syncing');
      expect(syncToast((phase: 'error', message: 'The service did not answer.')), 'The service did not answer.');
      expect(syncToast((phase: 'error', message: null)), 'Could not sync.');
      final commands = DesktopCommands();
      final said = <String>[];
      var refreshes = 0;
      var phase = 'syncing';
      var wait = const Duration(seconds: 1);
      wireDesktopCommands(
        commands: commands,
        onPlace: () => true,
        covered: () => false,
        newNote: () {},
        refresh: () {
          refreshes += 1;
          return Future<void>.delayed(wait, () => phase = 'idle');
        },
        status: () => (phase: phase, message: null),
        say: said.add,
        palette: () {},
        settings: () {},
      );
      expect(commands.run(DesktopCommand.sync), isTrue);
      // Pressed again while it runs: the one refresh.
      expect(commands.run(DesktopCommand.sync), isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(refreshes, 1);
      expect(said, ['Synced']);
      // A sync that outlasts the wait.
      phase = 'syncing';
      wait = const Duration(seconds: 30);
      commands.run(DesktopCommand.sync);
      await tester.pump(const Duration(seconds: 6));
      expect(said, ['Synced', 'Still syncing']);
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('the drag strip', () {
    Widget strip(List<String> said, {Widget? over}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 50,
              child: Stack(children: [
                Positioned.fill(child: MacDragStrip(onDrag: () => said.add('drag'), onZoom: () => said.add('zoom'))),
                if (over != null) Positioned(left: 100, top: 10, width: 30, height: 30, child: over),
              ]),
            ),
          ),
        );

    testWidgets('drags the window once a press moves, and zooms it on a double click', (tester) async {
      final said = <String>[];
      await tester.pumpWidget(strip(said));
      final press = await tester.startGesture(const Offset(200, 20), kind: PointerDeviceKind.mouse);
      await press.moveBy(const Offset(0.5, 0));
      expect(said, isEmpty);
      await press.moveBy(const Offset(12, 3));
      await press.moveBy(const Offset(12, 3));
      await press.up();
      // Once: the window itself follows the pointer from there.
      expect(said, ['drag']);
      said.clear();
      await tester.tapAt(const Offset(200, 20), kind: PointerDeviceKind.mouse);
      expect(said, isEmpty);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(201, 20), kind: PointerDeviceKind.mouse);
      expect(said, ['zoom']);
      // Two clicks in two places are two clicks.
      said.clear();
      await tester.tapAt(const Offset(40, 20), kind: PointerDeviceKind.mouse);
      await tester.tapAt(const Offset(300, 20), kind: PointerDeviceKind.mouse);
      expect(said, isEmpty);
      await tester.tapAt(const Offset(20, 40), kind: PointerDeviceKind.mouse);
      // The right button is not a drag.
      final right = await tester.startGesture(const Offset(200, 20), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await right.moveBy(const Offset(40, 0));
      await right.up();
      expect(said, isEmpty);
    });

    testWidgets('is behind the bar’s controls, which take their own presses', (tester) async {
      final said = <String>[];
      await tester.pumpWidget(strip(said, over: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => said.add('button'))));
      await tester.tapAt(const Offset(115, 25), kind: PointerDeviceKind.mouse);
      final press = await tester.startGesture(const Offset(115, 25), kind: PointerDeviceKind.mouse);
      await press.moveBy(const Offset(30, 0));
      await press.up();
      expect(said, ['button']);
    });
  });

  testWidgets('the lights’ row says where its centre is, and again only when it moves', (tester) async {
    final placed = <double>[];
    Widget row(double top) => Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [Positioned(left: 0, right: 0, top: top, height: 36, child: MacLightsRow(onPlaced: placed.add, child: const ColoredBox(color: Color(0xFF000000))))]),
        );
    await tester.pumpWidget(row(9));
    await tester.pump();
    expect(placed, [27.0]);
    await tester.pumpWidget(row(9));
    await tester.pump();
    expect(placed, [27.0]);
    await tester.pumpWidget(row(20));
    await tester.pump();
    expect(placed, [27.0, 38.0]);
    expect(trafficLightsStart, 16);
  });
}
