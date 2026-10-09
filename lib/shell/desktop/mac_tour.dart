/// A DEBUG BUILD'S ONLY: the Mac app walked from inside, so it can be looked at and driven without a click or a key
/// ever being sent to the person's screen or to another app.
///
/// The app is started from a terminal with a script in its environment, does what the script says, and ends:
///
/// ```sh
/// GHOST_TOUR='wait:1500;shot:home;key:cmd+k;wait:400;shot:palette;key:escape;quit' \
///   "build/macos/Build/Products/Debug/Ghost Flutter.app/Contents/MacOS/Ghost Flutter"
/// ```
///
/// Pictures and the log are the app's own files, in its container's temporary folder
/// (`~/Library/Containers/com.mattssoftware.glyph.flutter/Data/tmp/tour/`): the window as the Mac draws it, lights
/// and all (macos/Runner/MainFlutterWindow.swift `snapshot`).
///
/// The steps, `;` between them:
///
/// - `wait:<ms>`; `shot:<name>`; `size:<w>,<h>`; `quit`
/// - `key:<chord>`: a key pressed in this window alone, through AppKit as the keyboard's would be, so the menu's
///   shortcuts are walked too: `cmd+n`, `cmd+shift+z`, `escape`, `return`, `left`… `keys:<letters>` types them.
/// - `tap:<x>,<y>`, `dtap:` (double), `ttap:` (triple), `rtap:` (the right button), `hover:`,
///   `drag:<x1>,<y1>,<x2>,<y2>`, `scroll:<x>,<y>,<dy>`: a mouse's, given to Flutter's own gesture binding.
/// - `taptext:<words>` / `rtaptext:` / `hovertext:`: the same at the middle of the first text drawn that holds the
///   words. `where:<words>` only logs where it is.
/// - `hit:<x>,<y>`: logs what is under a point (the widgets' render objects, top first).
/// - `cursor:<x>,<y>`: logs the pointer shape there.
///
/// In a release build none of this is compiled in: [runMacTour] returns at once, and the Swift half answers
/// "not implemented".
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/mac_app.dart';
import 'mac_window.dart';

/// Runs the script in `GHOST_TOUR`, if this is a debug build of the Mac app started with one.
Future<void> runMacTour() async {
  if (!kDebugMode || !runsAsMacApp) return;
  final script = Platform.environment['GHOST_TOUR'];
  if (script == null || script.trim().isEmpty) return;
  final tour = _Tour();
  await tour.run(script);
}

class _Tour {
  final Directory _dir = Directory('${Directory.systemTemp.path}/tour');
  late final File _log = File('${_dir.path}/log.txt');
  int _pointer = 9000;
  Offset _mouse = Offset.zero;

  void _say(String line) {
    debugPrint('[tour] $line');
    try {
      _log.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> run(String script) async {
    try {
      _dir.createSync(recursive: true);
      if (_log.existsSync()) _log.deleteSync();
    } catch (_) {}
    FlutterError.onError = (details) => _say('ERROR ${details.exceptionAsString().split('\n').first}');
    for (final raw in script.split(';')) {
      final step = raw.trim();
      if (step.isEmpty) continue;
      final colon = step.indexOf(':');
      final name = colon < 0 ? step : step.substring(0, colon);
      final arg = colon < 0 ? '' : step.substring(colon + 1);
      try {
        await _step(name, arg);
      } catch (failure) {
        _say('FAILED $step: $failure');
      }
    }
  }

  List<double> _numbers(String arg) => [for (final part in arg.split(',')) double.parse(part.trim())];

  Future<void> _frames([int count = 2]) async {
    for (var i = 0; i < count; i += 1) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _step(String name, String arg) async {
    switch (name) {
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: int.parse(arg)));
      case 'shot':
        await _frames();
        _say('shot $arg -> ${await MacWindow.instance.snapshot(arg)}');
      case 'size':
        final n = _numbers(arg);
        await MacWindow.instance.resize(n[0], n[1]);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        _say('size ${view.physicalSize / view.devicePixelRatio} at ${view.devicePixelRatio}x');
      case 'quit':
        _say('quit');
        await MacWindow.instance.quit();
      case 'key':
        final parts = arg.toLowerCase().split('+');
        final ok = await MacWindow.instance.press(parts.last, command: parts.contains('cmd'), shift: parts.contains('shift'));
        _say('key $arg ${ok ? '' : 'NOT SENT'}');
        await _frames();
      case 'keys':
        for (final char in arg.split('')) {
          await MacWindow.instance.press(char.toLowerCase(), shift: char != char.toLowerCase() || char == '#' || char == '*');
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await _frames();
      case 'tap' || 'dtap' || 'ttap' || 'rtap':
        final n = _numbers(arg);
        await _click(Offset(n[0], n[1]), count: name == 'dtap' ? 2 : name == 'ttap' ? 3 : 1, right: name == 'rtap');
      case 'hover':
        final n = _numbers(arg);
        await _hover(Offset(n[0], n[1]));
      case 'drag':
        final n = _numbers(arg);
        await _drag(Offset(n[0], n[1]), Offset(n[2], n[3]));
      case 'scroll':
        final n = _numbers(arg);
        await _hover(Offset(n[0], n[1]));
        GestureBinding.instance.handlePointerEvent(PointerScrollEvent(position: Offset(n[0], n[1]), kind: PointerDeviceKind.mouse, scrollDelta: Offset(0, n[2])));
        await _frames();
      case 'taptext' || 'rtaptext' || 'hovertext' || 'where':
        final at = _textAt(arg);
        _say('$name "$arg" -> ${at == null ? 'NOT FOUND' : '${at.center.dx.toStringAsFixed(1)},${at.center.dy.toStringAsFixed(1)} $at'}');
        if (at == null) return;
        if (name == 'taptext') await _click(at.center);
        if (name == 'rtaptext') await _click(at.center, right: true);
        if (name == 'hovertext') await _hover(at.center);
      case 'hit':
        final n = _numbers(arg);
        final result = HitTestResult();
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        WidgetsBinding.instance.hitTestInView(result, Offset(n[0], n[1]), view.viewId);
        final names = <String>[];
        for (final entry in result.path) {
          final target = entry.target;
          if (target is RenderObject) {
            final creator = target.debugCreator;
            names.add(creator is DebugCreator ? creator.element.widget.runtimeType.toString() : target.runtimeType.toString());
          }
        }
        _say('hit $arg -> ${names.take(14).join(' < ')}');
      case 'cursor':
        final n = _numbers(arg);
        await _hover(Offset(n[0], n[1]));
        // ignore: invalid_use_of_visible_for_testing_member
        _say('cursor $arg -> ${RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)?.debugDescription}');
      default:
        _say('UNKNOWN $name');
    }
  }

  /// The first text on screen that holds [words], by the box it is drawn in.
  Rect? _textAt(String words) {
    Rect? found;
    void visit(Element element) {
      if (found != null) return;
      final render = element.renderObject;
      if (render is RenderParagraph && render.attached && render.hasSize && render.text.toPlainText().contains(words)) {
        final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final window = Offset.zero & (view.physicalSize / view.devicePixelRatio);
        if (window.overlaps(box) && box.width > 0) {
          found = box;
          return;
        }
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  Future<void> _hover(Offset to) async {
    GestureBinding.instance.handlePointerEvent(PointerHoverEvent(device: 1, position: to, delta: to - _mouse, kind: PointerDeviceKind.mouse));
    _mouse = to;
    await _frames();
  }

  Future<void> _click(Offset at, {int count = 1, bool right = false}) async {
    await _hover(at);
    final buttons = right ? kSecondaryMouseButton : kPrimaryMouseButton;
    for (var i = 0; i < count; i += 1) {
      final pointer = _pointer += 1;
      GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, device: 1, position: at, kind: PointerDeviceKind.mouse, buttons: buttons, timeStamp: _now()));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, device: 1, position: at, kind: PointerDeviceKind.mouse, timeStamp: _now()));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await _frames();
    _say('${right ? 'right ' : ''}click x$count at ${at.dx},${at.dy}');
  }

  Future<void> _drag(Offset from, Offset to) async {
    await _hover(from);
    final pointer = _pointer += 1;
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, device: 1, position: from, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, timeStamp: _now()));
    const steps = 12;
    var last = from;
    for (var i = 1; i <= steps; i += 1) {
      final next = Offset.lerp(from, to, i / steps)!;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(pointer: pointer, device: 1, position: next, delta: next - last, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, timeStamp: _now()));
      last = next;
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, device: 1, position: to, kind: PointerDeviceKind.mouse, timeStamp: _now()));
    _mouse = to;
    await _frames();
    _say('drag $from -> $to');
  }

  final Stopwatch _clock = Stopwatch()..start();
  Duration _now() => _clock.elapsed;
}
