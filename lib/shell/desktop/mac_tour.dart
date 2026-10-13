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
/// - `type:<words>` gives words to the note's editor or the focused field as the Mac's text input would, and
///   `enter` a new line: for a window that is not the key window (the app started behind another), which the Mac
///   routes no typing to.
/// - `tap:<x>,<y>`, `dtap:` (double), `ttap:` (triple), `rtap:` (the right button), `hover:`,
///   `drag:<x1>,<y1>,<x2>,<y2>`, `scroll:<x>,<y>,<dy>`: a mouse's, given to Flutter's own gesture binding.
/// - `taplabel:<name>`: the same for a control with no words on it, by the name it gives a screen reader.
/// - `taptext:<words>` / `rtaptext:` / `hovertext:`: the same at the middle of the first text drawn that holds the
///   words. `where:<words>` only logs where it is.
/// - `hit:<x>,<y>`: logs what is under a point (the widgets' render objects, top first).
/// - `channels`: asks each of the Mac's method channels something harmless and logs what it answered.
///   `ask:<channel>|<method>|<key>=<value>,…` asks one thing of one of them.
/// - `link:<ghostmd://…>`: a link handed to the app's own delegate, as macOS hands one (never through the system).
/// - `panels:folder=<path>,name=<name>,file=<path>,cancel`: how the next of the Mac's panels is answered with no
///   hand on it (macos/Runner/FilesChannel.swift `Panels`).
/// - `texts`: every text on screen and where it is. `forget`: clears this app's own remembered settings and flags.
///   `pref:<key>=<value>`: sets one of its preferences for the next launch.
/// - `cursor:<x>,<y>`: logs the pointer shape there. `keylog`: from here on, logs every key the framework hears
///   and what the editor's keyboard client is told.
///
/// In a release build none of this is compiled in: [runMacTour] returns at once, and the Swift half answers
/// "not implemented".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/mac_app.dart';
import '../../core/stored_device.dart';
import '../../editor/editor_widget.dart';
import '../../editor/input/ime.dart';
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
      case 'channels':
        // Each of the Mac's halves asked something that shows nothing and changes nothing a person made: where the
        // files are, a secret written, read back and removed under a name of the tour's own, whether a
        // recording is here, the microphone's permission (never the request), the links kept, a reset's question. Not the clipboard, which is the person's.
        Future<void> ask(String label, Future<Object?> Function() call) async {
          try {
            _say('channel $label -> ${await call()}');
          } catch (failure) {
            _say('channel $label FAILED $failure');
          }
        }
        const secrets = MethodChannel('ghost_md/secure_store');
        await ask('device_paths dirs', () => const MethodChannel('ghost_md/device_paths').invokeMethod<Object?>('dirs'));
        await ask('secure_store write', () => secrets.invokeMethod<Object?>('write', {'name': 'tour-probe', 'value': 'kept'}));
        await ask('secure_store read', () => secrets.invokeMethod<Object?>('read', {'name': 'tour-probe'}));
        await ask('secure_store delete', () => secrets.invokeMethod<Object?>('delete', {'name': 'tour-probe'}));
        await ask('secure_store read again', () => secrets.invokeMethod<Object?>('read', {'name': 'tour-probe'}));
        await ask('tape onDevice', () => const MethodChannel('ghost_md/tape').invokeMethod<Object?>('onDevice', {'noteId': 'no-such-note'}));
        await ask('mic permission', () => const MethodChannel('ghost_md/mic').invokeMethod<Object?>('permission'));
        await ask('links take', () => const MethodChannel('ghost_md/links').invokeMethod<Object?>('take'));
        await ask('reset recording', () => const MethodChannel('ghost.md/reset').invokeMethod<Object?>('recording'));
        await ask('window state', () => MacWindow.channel.invokeMethod<Object?>('state'));
      case 'link':
        // A link handed to the app's own delegate, as macOS hands one: never opened through the system, where
        // another app that claims the scheme could be the one to get it.
        _say('link $arg -> ${await MacWindow.channel.invokeMethod<Object?>('link', {'url': arg})}');
        await _frames();
      case 'panels':
        // How the next of the Mac's panels is answered with no hand on it: `folder=<path>`, `name=<file name>`,
        // `file=<path>`, `cancel`, `,` between them. The folder is one the tour made for itself.
        final answer = <String, Object?>{};
        for (final part in arg.split(',')) {
          final at = part.indexOf('=');
          if (at < 0) {
            if (part.trim() == 'cancel') answer['cancel'] = true;
          } else {
            answer[part.substring(0, at).trim()] = part.substring(at + 1).trim();
          }
        }
        await MacWindow.channel.invokeMethod<Object?>('panels', answer);
        _say('panels $answer');
      case 'ask':
        // One call on one of the app's channels, its answer logged: `ask:<channel>|<method>|<key>=<value>,…`.
        final parts = arg.split('|');
        final args = <String, Object?>{
          if (parts.length > 2)
            for (final pair in parts[2].split(','))
              if (pair.contains('=')) pair.substring(0, pair.indexOf('=')): pair.substring(pair.indexOf('=') + 1),
        };
        try {
          _say('ask ${parts[0]} ${parts[1]} -> ${await MethodChannel(parts[0]).invokeMethod<Object?>(parts[1], args.isEmpty ? null : args)}');
        } catch (failure) {
          _say('ask ${parts[0]} ${parts[1]} FAILED $failure');
        }
        await _frames();
      case 'attrs':
        // The page's attributes at the root, as the theme holds them, and the window's size.
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        _say('window ${view.physicalSize / view.devicePixelRatio} at ${view.devicePixelRatio}x');
      case 'texts':
        // Every text on screen with where it is, top to bottom: what a picture shows, as words.
        final found = <(Rect, String)>[];
        void visit(Element element) {
          final render = element.renderObject;
          if (render is RenderParagraph && render.attached && render.hasSize) {
            final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
            final words = render.text.toPlainText().trim();
            if (words.isNotEmpty && box.width > 0 && box.top < 2000 && box.bottom > 0) found.add((box, words));
          }
          element.visitChildren(visit);
        }
        WidgetsBinding.instance.rootElement?.visitChildren(visit);
        found.sort((a, b) => a.$1.top != b.$1.top ? a.$1.top.compareTo(b.$1.top) : a.$1.left.compareTo(b.$1.left));
        for (final (box, words) in found.take(int.tryParse(arg) ?? 80)) {
          _say('text ${box.left.toStringAsFixed(1)},${box.top.toStringAsFixed(1)} ${box.width.toStringAsFixed(1)}x${box.height.toStringAsFixed(1)} "${words.length > 60 ? '${words.substring(0, 60)}…' : words}"');
        }
      case 'forget':
        // Everything this app's own memory holds (its shared preferences), gone: for a walk that must start as a
        // first launch does. The library's files are not touched from here.
        // Through the app's one door to the device's storage (lib/core/stored_device.dart), as everything that
        // keeps or forgets a key goes: test/diag/reset_test.dart holds that nothing else opens it. A write there is
        // handed over and not waited for; the Mac takes them in the order they were sent, a `quit` after them too.
        final kept = await DeviceStored.open();
        final keys = kept.allKeys.toList();
        for (final key in keys) {
          kept.removeItem(key);
        }
        _say('forget ${keys.length} keys');
      case 'pref':
        // One of the app's own preferences set for the next launch (`pref:<key>=<value>`): the theme, the sidebar's
        // style. Written where the app keeps them; the running app is not told.
        final at = arg.indexOf('=');
        final kept = await DeviceStored.open();
        final now = jsonDecode(kept.getItem('glyph-preferences') ?? '{}');
        if (now is Map && at > 0) {
          final value = arg.substring(at + 1);
          now[arg.substring(0, at)] = value == 'true' ? true : value == 'false' ? false : (num.tryParse(value) ?? value);
          kept.setItem('glyph-preferences', jsonEncode(now));
          _say('pref $arg');
        }
      case 'keylog':
        // Every key the framework hears, and whether anything took it: where a chord went, when it went nowhere.
        HardwareKeyboard.instance.addHandler((event) {
          _say('heard ${event.runtimeType} ${event.logicalKey.keyLabel} meta ${HardwareKeyboard.instance.isMetaPressed}');
          return false;
        });
        EditorIme.log = (line) => _say('ime $line');
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
      case 'type':
        await _type(arg);
      case 'enter':
        await _type('\n');
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
      case 'taplabel' || 'wherelabel':
        // A control with no words on it, by the name it gives a screen reader.
        Rect? found;
        void visit(Element element) {
          if (found != null) return;
          final widget = element.widget;
          if (widget is Semantics && widget.properties.label == arg) {
            final render = element.renderObject;
            if (render is RenderBox && render.attached && render.hasSize) {
              final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
              final view = WidgetsBinding.instance.platformDispatcher.views.first;
              if ((Offset.zero & (view.physicalSize / view.devicePixelRatio)).overlaps(box)) {
                found = box;
                return;
              }
            }
          }
          element.visitChildren(visit);
        }
        WidgetsBinding.instance.rootElement?.visitChildren(visit);
        final box = found;
        _say('$name "$arg" -> ${box == null ? 'NOT FOUND' : '${box.center.dx.toStringAsFixed(1)},${box.center.dy.toStringAsFixed(1)} $box'}');
        if (box != null && name == 'taplabel') await _click(box.center);
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

  /// Words given to whatever holds the keyboard, one letter at a time, each as the change the Mac's text input
  /// would hand over for it (lib/shell/phone_tour.dart `_type`, which this is): for a window that is not the key
  /// window, where the Mac routes no typing at all and `keys:` reaches nothing. A note's editor first, else the
  /// focused field of Flutter's own.
  Future<void> _type(String words) async {
    EditorIme? editor;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Editor) {
        final ime = widget.controller?.ime;
        if (ime != null && ime.attached) editor = ime;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    EditableTextState? field;
    if (editor == null) {
      final context = FocusManager.instance.primaryFocus?.context;
      field = context?.findAncestorStateOfType<EditableTextState>();
      if (field == null && context != null) {
        void inside(Element element) {
          if (field != null) return;
          if (element is StatefulElement && element.state is EditableTextState) {
            field = element.state as EditableTextState;
            return;
          }
          element.visitChildren(inside);
        }

        context.visitChildElements(inside);
      }
    }
    final ime = editor, typed = field;
    if (ime == null && typed == null) {
      _say('type "$words" NOTHING HOLDS THE KEYBOARD');
      return;
    }
    for (final char in words.characters) {
      if (ime != null) {
        final held = ime.held;
        final at = held.selection.isValid ? held.selection : TextSelection.collapsed(offset: held.text.length);
        final after = TextSelection.collapsed(offset: at.start + char.length);
        ime.updateEditingValueWithDeltas([
          at.isCollapsed
              ? TextEditingDeltaInsertion(oldText: held.text, textInserted: char, insertionOffset: at.start, selection: after, composing: TextRange.empty)
              : TextEditingDeltaReplacement(oldText: held.text, replacementText: char, replacedRange: TextRange(start: at.start, end: at.end), selection: after, composing: TextRange.empty),
        ]);
      } else {
        final value = typed!.textEditingValue;
        final at = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
        if (char == '\n') {
          typed.performAction(typed.widget.textInputAction ?? TextInputAction.done);
        } else {
          typed.userUpdateTextEditingValue(value.replaced(TextRange(start: at.start, end: at.end), char), SelectionChangedCause.keyboard);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await _frames();
    _say('type "${words.replaceAll('\n', '⏎')}" into ${ime != null ? 'the editor' : 'a field'}');
  }

  final Stopwatch _clock = Stopwatch()..start();
  Duration _now() => _clock.elapsed;
}
