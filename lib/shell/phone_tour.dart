/// A DEBUG BUILD'S ONLY: the iPhone app walked from inside, in its simulator, so it can be looked at and driven
/// without a click or a key ever being sent to the person's screen or to another app. What
/// lib/shell/desktop/mac_tour.dart is to the Mac app, for a phone: a finger where that has a mouse, and the
/// keyboard's own words where that has keys.
///
/// The app finds a script waiting in its own cache folder as it starts, does what it says, and takes the file
/// away. tool/ios-tour.sh is the other half, on the Mac: it leaves the script there, starts the app, takes the
/// pictures the script asks for (`xcrun simctl io … screenshot`, the whole screen as the phone draws it, status
/// bar, keyboard and home indicator included) and reads the log back.
///
/// ```sh
/// tool/ios-tour.sh <udid> <folder for the pictures> 'wait:6000;shot:home;taplabel:Write a note;wait:900;type:Hello;shot:note'
/// ```
///
/// A file and not the environment, where the Mac's script is: `Platform.environment` is empty on an iPhone,
/// whatever the process was started with. The script, the log and what is asked of the Mac are the app's own
/// files, in `<container>/Library/Caches/com.mattssoftware.glyph.flutter/tour/` (`script.txt`, `log.txt`,
/// `ask.txt`).
///
/// The steps, `;` between them:
///
/// - `wait:<ms>`; `shot:<name>` (asks the Mac for a picture and waits until it is taken); `host:<words>` (asks the
///   Mac for anything else it does: `appearance dark`, `appearance light`).
/// - `tap:<x>,<y>`, `hold:<x>,<y>` (a press held), `swipe:<x1>,<y1>,<x2>,<y2>[,<ms>]`: a finger's, given to
///   Flutter's own gesture binding. `flick:` is a swipe let go while still moving.
/// - `taptext:<words>` / `holdtext:<words>`: the same at the middle of the first text drawn that holds the words;
///   `taplabel:<words>` / `holdlabel:` at the first control whose spoken name holds them (an icon's button has no
///   words drawn). `where:<words>` only logs where it is.
/// - `type:<words>`: typed into whatever holds the keyboard, as the keyboard would say it: one letter at a time
///   to the note's editor (its own text client, lib/editor/input/ime.dart) or to a field. `enter`; `backspace:<n>`.
///   No key is pressed on the simulator's keyboard, which nothing here can reach.
/// - `texts` / `labels`: logs every text, or every named control, on screen with where it is. `hit:<x>,<y>`: what
///   is under a point. `insets`: the phone's safe areas and the keyboard's height as the app is told them.
/// - `channels`: asks each of the iPhone's method channels something harmless and logs what it answered.
/// - `unfocus`: gives the keyboard up.
///
/// In a release build none of this is compiled in: [runPhoneTour] returns at once.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/iphone_app.dart';
import '../core/native/device_paths.dart';
import '../editor/editor_widget.dart';
import '../editor/input/ime.dart';
import '../editor/view/line.dart' show RenderEditorLine;

/// Runs the script waiting in the app's cache folder, if this is a debug build of the iPhone app and there is
/// one (tool/ios-tour.sh leaves it). The file is taken away as it is read, so the next start is an ordinary one.
Future<void> runPhoneTour() async {
  if (!kDebugMode || !runsAsIPhoneApp) return;
  final Directory dir;
  final String script;
  try {
    dir = Directory('${(await DevicePaths.find()).cacheDir}/tour');
    final waiting = File('${dir.path}/script.txt');
    if (!waiting.existsSync()) return;
    script = waiting.readAsStringSync();
    waiting.deleteSync();
  } catch (_) {
    return;
  }
  if (script.trim().isEmpty) return;
  await PhoneTour(dir: dir).run(script);
}

/// The steps of a script, as they are split: `name` and what follows its colon. For a test.
List<({String name, String arg})> tourSteps(String script) => [
      for (final raw in script.split(';'))
        if (raw.trim().isNotEmpty)
          () {
            final step = raw.trim();
            final colon = step.indexOf(':');
            return (name: colon < 0 ? step : step.substring(0, colon), arg: colon < 0 ? '' : step.substring(colon + 1));
          }(),
    ];

class PhoneTour {
  PhoneTour({required Directory dir}) : _dir = dir;

  final Directory _dir;
  late final File _log = File('${_dir.path}/log.txt');
  late final File _ask = File('${_dir.path}/ask.txt');
  int _pointer = 9000;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _now() => _clock.elapsed;

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
      if (_ask.existsSync()) _ask.deleteSync();
    } catch (_) {}
    final before = FlutterError.onError;
    FlutterError.onError = (details) {
      _say('ERROR ${details.exceptionAsString().split('\n').take(3).join(' | ')}');
      before?.call(details);
    };
    for (final step in tourSteps(script)) {
      try {
        await _step(step.name, step.arg);
      } catch (failure) {
        _say('FAILED ${step.name}:${step.arg}: $failure');
      }
    }
    _say('end');
    await _host('end');
  }

  List<double> _numbers(String arg) => [for (final part in arg.split(',')) double.parse(part.trim())];

  Future<void> _frames([int count = 2]) async {
    for (var i = 0; i < count; i += 1) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Asks the Mac's half (tool/ios-tour.sh) for something and waits until it says it is done by taking the
  /// question away; not for ever, since a script run with nobody listening must still end.
  Future<void> _host(String words) async {
    try {
      _ask.writeAsStringSync('$words\n', flush: true);
    } catch (failure) {
      _say('host "$words" could not be asked: $failure');
      return;
    }
    for (var waited = 0; waited < 150; waited += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_ask.existsSync()) return;
    }
    _say('host "$words" was not answered');
    try {
      _ask.deleteSync();
    } catch (_) {}
  }

  Future<void> _step(String name, String arg) async {
    switch (name) {
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: int.parse(arg)));
      case 'shot':
        await _frames();
        await _host('shot $arg');
        _say('shot $arg');
      case 'host':
        await _host(arg);
        _say('host $arg');
        await _frames();
      case 'tap':
        final n = _numbers(arg);
        await _touch(Offset(n[0], n[1]));
      case 'hold':
        final n = _numbers(arg);
        await _touch(Offset(n[0], n[1]), held: const Duration(milliseconds: 700));
      case 'swipe' || 'flick':
        final n = _numbers(arg);
        await _swipe(Offset(n[0], n[1]), Offset(n[2], n[3]), ms: n.length > 4 ? n[4].round() : 220, settle: name == 'swipe');
      case 'taptext' || 'holdtext' || 'where' || 'tapif':
        final at = _textAt(arg);
        // `tapif` is for what may or may not be up (a first run's welcome and its Skip): not there is not a fault.
        if (name == 'tapif' && at == null) return;
        _say('$name "$arg" -> ${at == null ? 'NOT FOUND' : _spot(at)}');
        if (at == null) return;
        if (name == 'taptext' || name == 'tapif') await _touch(at.center);
        if (name == 'holdtext') await _touch(at.center, held: const Duration(milliseconds: 700));
      case 'tapline':
        // A line of the note's own words: the editor draws its lines itself, so they are no texts to find. The tap
        // lands a little way into the line's first row, among plain words.
        final at = _lineAt(arg);
        _say('tapline "$arg" -> ${at == null ? 'NOT FOUND' : _spot(at)}');
        if (at == null) return;
        await _touch(Offset(at.left + at.width * 0.3, at.top + (at.height < 36 ? at.height / 2 : 14)));
      case 'seek':
        // The words brought onto the screen by the finger, a part of a page at a time, until they are there to be
        // tapped: a phone's home page has the note a wide window shows at once a few screens down, and a list that
        // builds only what is near has not made it yet. Down first, then back up past where it began.
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final size = view.physicalSize / view.devicePixelRatio;
        final x = size.width / 2, high = size.height * 0.35, low = size.height * 0.70;
        Rect? at;
        for (var tries = 0; tries < 24; tries += 1) {
          at = _textAt(arg);
          if (at != null && at.center.dy > size.height * 0.18 && at.center.dy < size.height * 0.80) break;
          final down = at == null ? tries < 8 : at.center.dy >= size.height * 0.80;
          await _swipe(Offset(x, down ? low : high), Offset(x, down ? high : low), ms: 320, settle: true);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        _say('seek "$arg" -> ${at == null ? 'NOT FOUND' : _spot(at)}');
      case 'taplabel' || 'holdlabel':
        final at = _labelAt(arg);
        _say('$name "$arg" -> ${at == null ? 'NOT FOUND' : _spot(at)}');
        if (at == null) return;
        await _touch(at.center, held: name == 'holdlabel' ? const Duration(milliseconds: 700) : null);
      case 'type':
        await _type(arg);
      case 'enter':
        await _type('\n');
      case 'backspace':
        final count = arg.isEmpty ? 1 : int.parse(arg);
        for (var i = 0; i < count; i += 1) {
          _backspace();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await _frames();
      case 'unfocus':
        FocusManager.instance.primaryFocus?.unfocus();
        await _frames();
      case 'texts':
        for (final (words, box) in _texts()) {
          _say('text ${_spot(box)} "${words.replaceAll('\n', '⏎')}"');
        }
      case 'labels':
        for (final (words, box) in _labels()) {
          _say('label ${_spot(box)} "$words"');
        }
      case 'insets':
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final ratio = view.devicePixelRatio;
        _say('insets size ${view.physicalSize / ratio} at ${ratio}x, safe top ${view.viewPadding.top / ratio} bottom ${view.viewPadding.bottom / ratio} left ${view.viewPadding.left / ratio} right ${view.viewPadding.right / ratio}, keyboard ${view.viewInsets.bottom / ratio}, dark ${WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark}, text scale ${WidgetsBinding.instance.platformDispatcher.textScaleFactor}');
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
      case 'channels':
        await _channels();
      default:
        _say('UNKNOWN $name');
    }
  }

  /// Each of the iPhone's halves asked something that shows nothing and changes nothing a person made: where the
  /// files are, a secret written, read back and removed under a name of the tour's own, whether a recording is
  /// here, the links kept, a reset's question. Not the clipboard, which is the person's and which an iPhone asks
  /// about before it is read. And one of what an iPhone has no half of, to see that it says so.
  Future<void> _channels() async {
    Future<void> ask(String label, Future<Object?> Function() call) async {
      try {
        _say('channel $label -> ${await call()}');
      } catch (failure) {
        _say('channel $label FAILED $failure');
      }
    }

    const secrets = MethodChannel('ghost_md/secure_store');
    await ask('device_paths dirs', () => const MethodChannel('ghost_md/device_paths').invokeMethod<Object?>('dirs'));
    await ask('secure_store write', () => secrets.invokeMethod<Object?>('write', {'name': 'tour-probe:1', 'value': 'kept'}));
    await ask('secure_store read', () => secrets.invokeMethod<Object?>('read', {'name': 'tour-probe:1'}));
    await ask('secure_store delete', () => secrets.invokeMethod<Object?>('delete', {'name': 'tour-probe:1'}));
    await ask('secure_store read again', () => secrets.invokeMethod<Object?>('read', {'name': 'tour-probe:1'}));
    await ask('tape onDevice', () => const MethodChannel('ghost_md/tape').invokeMethod<Object?>('onDevice', {'noteId': 'no-such-note'}));
    await ask('links take', () => const MethodChannel('ghost_md/links').invokeMethod<Object?>('take'));
    await ask('reset recording', () => const MethodChannel('ghost.md/reset').invokeMethod<Object?>('recording'));
    await ask('open (refused scheme)', () => const MethodChannel('ghost_md/open').invokeMethod<Object?>('open', {'url': 'file:///etc/hosts'}));
    for (final absent in const ['ghost_md/mic', 'ghost_md/meeting', 'ghost_md/files', 'ghost_md/location', 'ghost_md/films', 'ghost_md/updates', 'ghost_md/hinge', 'ghost_md/front']) {
      await ask('$absent (none on an iPhone)', () => MethodChannel(absent).invokeMethod<Object?>('permission'));
    }
  }

  String _spot(Rect box) => '${box.center.dx.toStringAsFixed(0)},${box.center.dy.toStringAsFixed(0)} [${box.left.toStringAsFixed(0)},${box.top.toStringAsFixed(0)} ${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)}]';

  Rect get _window {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return Offset.zero & (view.physicalSize / view.devicePixelRatio);
  }

  Rect? _boxOf(RenderObject? render) {
    if (render is! RenderBox || !render.attached || !render.hasSize) return null;
    final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
    return box.width > 0 && box.height > 0 && _window.overlaps(box) ? box : null;
  }

  /// Whether what is under [element] is kept out of sight: built and laid out, and neither drawn nor pressed, as
  /// the shell keeps the home page under an open note (lib/shell/app_shell.dart). Its words and its controls are
  /// not there to be touched: found, a tap on "Home" landed on the kept page's own header, not on the bar's.
  bool _unseen(Element element) {
    final render = element.renderObject;
    return element is RenderObjectElement && render is RenderOffstage && render.offstage;
  }

  /// Every text drawn in the window, top to bottom.
  List<(String, Rect)> _texts() {
    final found = <(String, Rect)>[];
    void visit(Element element) {
      final render = element.renderObject;
      if (_unseen(element)) return;
      if (element is RenderObjectElement && render is RenderParagraph) {
        final box = _boxOf(render);
        final words = render.text.toPlainText();
        if (box != null && words.trim().isNotEmpty) found.add((words, box));
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    found.sort((a, b) => a.$2.top != b.$2.top ? a.$2.top.compareTo(b.$2.top) : a.$2.left.compareTo(b.$2.left));
    return found;
  }

  /// Every control with a spoken name: the kit's pressables, and anything else given a label.
  List<(String, Rect)> _labels() {
    final found = <(String, Rect)>[];
    void visit(Element element) {
      if (_unseen(element)) return;
      final widget = element.widget;
      String? label;
      if (widget is GlacierPressable) label = widget.semanticLabel;
      if (widget is Semantics) label = widget.properties.label ?? widget.properties.tooltip;
      if (label != null && label.isNotEmpty) {
        final box = _boxOf(element.renderObject);
        if (box != null) found.add((label, box));
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    found.sort((a, b) => a.$2.top != b.$2.top ? a.$2.top.compareTo(b.$2.top) : a.$2.left.compareTo(b.$2.left));
    return found;
  }

  /// The LAST drawn text that holds [words]: what is drawn later is drawn over, so a sheet's row is found before
  /// the page's under it.
  Rect? _textAt(String words) {
    Rect? found;
    void visit(Element element) {
      if (_unseen(element)) return;
      final render = element.renderObject;
      if (element is RenderObjectElement && render is RenderParagraph && render.text.toPlainText().contains(words)) {
        found = _boxOf(render) ?? found;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// The first of the editor's lines in sight whose words hold [words].
  Rect? _lineAt(String words) {
    Rect? found;
    void visit(Element element) {
      if (found != null || _unseen(element)) return;
      final render = element.renderObject;
      if (element is RenderObjectElement && render is RenderEditorLine && render.spec.projection.display.contains(words)) {
        found = _boxOf(render);
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  Rect? _labelAt(String words) {
    Rect? found;
    for (final (label, box) in _labels()) {
      if (label.contains(words)) found = box;
    }
    return found;
  }

  Future<void> _touch(Offset at, {Duration? held}) async {
    final pointer = _pointer += 1;
    GestureBinding.instance.handlePointerEvent(PointerAddedEvent(pointer: pointer, position: at, timeStamp: _now()));
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, position: at, timeStamp: _now()));
    await Future<void>.delayed(held ?? const Duration(milliseconds: 60));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, position: at, timeStamp: _now()));
    GestureBinding.instance.handlePointerEvent(PointerRemovedEvent(pointer: pointer, position: at, timeStamp: _now()));
    await _frames();
    _say('${held == null ? 'tap' : 'hold'} at ${at.dx.toStringAsFixed(0)},${at.dy.toStringAsFixed(0)}');
  }

  Future<void> _swipe(Offset from, Offset to, {required int ms, required bool settle}) async {
    final pointer = _pointer += 1;
    GestureBinding.instance.handlePointerEvent(PointerAddedEvent(pointer: pointer, position: from, timeStamp: _now()));
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: pointer, position: from, timeStamp: _now()));
    final steps = (ms / 16).ceil().clamp(4, 120);
    var last = from;
    for (var i = 1; i <= steps; i += 1) {
      final next = Offset.lerp(from, to, i / steps)!;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(pointer: pointer, position: next, delta: next - last, timeStamp: _now()));
      last = next;
    }
    // A swipe rests a moment before the finger lifts, so nothing is flung; a flick does not.
    if (settle) await Future<void>.delayed(const Duration(milliseconds: 120));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: pointer, position: to, timeStamp: _now()));
    GestureBinding.instance.handlePointerEvent(PointerRemovedEvent(pointer: pointer, position: to, timeStamp: _now()));
    await _frames();
    _say('${settle ? 'swipe' : 'flick'} ${from.dx.toStringAsFixed(0)},${from.dy.toStringAsFixed(0)} -> ${to.dx.toStringAsFixed(0)},${to.dy.toStringAsFixed(0)}');
  }

  /// The note's editor that holds the keyboard, by its text client.
  EditorIme? _editor() {
    EditorIme? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Editor) {
        final ime = widget.controller?.ime;
        if (ime != null && ime.attached) found = ime;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// The field that holds the keyboard, when it is one of Flutter's own.
  EditableTextState? _field() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    EditableTextState? found = context.findAncestorStateOfType<EditableTextState>();
    if (found != null) return found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  /// One letter at a time, each as the delta the keyboard sends for it.
  Future<void> _type(String words) async {
    final editor = _editor();
    final field = editor == null ? _field() : null;
    if (editor == null && field == null) {
      _say('type "$words" NOTHING HOLDS THE KEYBOARD');
      return;
    }
    for (final char in words.characters) {
      if (editor != null) {
        final held = editor.held;
        final at = held.selection.isValid ? held.selection : TextSelection.collapsed(offset: held.text.length);
        final after = TextSelection.collapsed(offset: at.start + char.length);
        editor.updateEditingValueWithDeltas([
          at.isCollapsed
              ? TextEditingDeltaInsertion(oldText: held.text, textInserted: char, insertionOffset: at.start, selection: after, composing: TextRange.empty)
              : TextEditingDeltaReplacement(oldText: held.text, replacementText: char, replacedRange: TextRange(start: at.start, end: at.end), selection: after, composing: TextRange.empty),
        ]);
      } else {
        final value = field!.textEditingValue;
        final at = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
        if (char == '\n') {
          field.performAction(field.widget.textInputAction ?? TextInputAction.done);
        } else {
          field.userUpdateTextEditingValue(value.replaced(TextRange(start: at.start, end: at.end), char), SelectionChangedCause.keyboard);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await _frames();
    _say('type "${words.replaceAll('\n', '⏎')}" into ${editor != null ? 'the editor' : 'a field'}');
  }

  void _backspace() {
    final editor = _editor();
    if (editor != null) {
      final held = editor.held;
      final at = held.selection;
      if (!at.isValid || (at.isCollapsed && at.start == 0)) {
        // The window's first character: a key, as an iPhone's keyboard sends it there too.
        editor.runKey('Backspace');
        return;
      }
      final range = at.isCollapsed ? TextRange(start: at.start - 1, end: at.start) : TextRange(start: at.start, end: at.end);
      editor.updateEditingValueWithDeltas([TextEditingDeltaDeletion(oldText: held.text, deletedRange: range, selection: TextSelection.collapsed(offset: range.start), composing: TextRange.empty)]);
      return;
    }
    final field = _field();
    if (field == null) return;
    final value = field.textEditingValue;
    final at = value.selection;
    if (!at.isValid || (at.isCollapsed && at.start == 0)) return;
    final range = at.isCollapsed ? TextRange(start: at.start - 1, end: at.start) : TextRange(start: at.start, end: at.end);
    field.userUpdateTextEditingValue(value.replaced(range, ''), SelectionChangedCause.keyboard);
  }
}
