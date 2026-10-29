/// Where the Keyboard modes plugin meets the note's editor (keymaps.dart): one extension, [keyboardModes], that the
/// note's desk gives every editor it makes, whatever is chosen. It hears a hardware keyboard's keys before anything
/// else of the editor's (`Prec.highest`, ahead of the `/` palette), names each the way the chosen engine reads keys,
/// and hands it on: Vim's (vim.dart) or Emacs's (emacs.dart), each over the editor as a [KeyText] ([EditorKeyText]).
/// A key the engine does not take goes on to the editor's keymaps, the app's shortcuts and the keyboard's text, as
/// it did before there was a plugin; with Off, every key does.
///
/// - **Hardware keys only.** The engines are handed key events, never the screen keyboard's text, which arrives as
///   edits. The screen keyboard sends a few keys too (Android's Backspace, sometimes Enter), so on a phone or a
///   tablet nothing is taken until a key that only a hardware keyboard sends has been pressed: a letter, Esc, or a
///   letter with Control or Alt ([hardwareKeyboardSeen]). A Mac, Windows and Linux have one from the start.
/// - **The app's own keys.** Anything with Cmd (Meta) held is never taken. In Vim's Insert every key is left as it
///   is but Esc, Ctrl-[ and the `k` of `jk`; while the `+`'s list is open ([KeymapHooks.holding]) its keys are its
///   own in Insert and in Emacs. In Normal and Visual a plain letter is Vim's.
/// - **Undo is the note's**: its history, or its live document's while it is bound to one (undo_slot.dart
///   `undoNote`); each engine's change is one step of it, kept from joining the typing before it (`isolateHistory`).
/// - **The caret** is a block over the character in Vim's Normal: the view's `selectionPainter`, put back as it was
///   in every other mode.
/// - **Saving and closing** are the desk's ([KeymapHooks.save], [KeymapHooks.close]); the close waits for the frame,
///   the key that asked for it being handled inside the editor it closes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../../editor/commands/commands.dart' as commands show indentUnit;
import '../../editor/editor.dart';
import '../../editor/input/keymap.dart' show runCommand;
import '../../editor/input/motion.dart' show cursorByLine, selectByLine;
import '../../editor/view/editor_view.dart';
import '../../editor/view/line.dart' show EditorSelectionPainter;
import '../host.dart' show onPluginStorage;
import '../registry.dart' show plugins;
import 'emacs.dart';
import 'keymaps.dart' show KeyboardMode;
import 'text.dart';
import 'vim.dart';

/// Whether a hardware keyboard has been used in this run: on a Mac, Windows or Linux from the start; on a phone or
/// a tablet from the first key only a hardware keyboard sends. Until then the engines take nothing and draw nothing.
final ValueNotifier<bool> hardwareKeyboardSeen = ValueNotifier<bool>(
  !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux),
);

/// What the desk tells the extension, each asked as it is used.
class KeymapHooks {
  const KeymapHooks({required this.mode, this.startNormal, this.jk, this.save, this.close, this.holding});

  /// The way of typing chosen now (keymaps.dart `keyboardMode`).
  final KeyboardMode Function() mode;

  /// Vim's two switches; on and off where not given.
  final bool Function()? startNormal;
  final bool Function()? jk;

  /// Saves the note now; closes it.
  final VoidCallback? save;
  final VoidCallback? close;

  /// Whether something of the editor's own has the keys now: the `+`'s list, open.
  final bool Function(EditorViewLike view)? holding;
}

final Expando<KeymapSession> _sessions = Expando<KeymapSession>('keymaps');

/// The session of [view]'s editor, where it has the extension.
KeymapSession? keymapSessionOf(EditorView view) => _sessions[view];

/// The extension: see the header.
Extension keyboardModes(KeymapHooks hooks) {
  final plugin = ViewPlugin.define<_KeymapPlugin>((view) => _KeymapPlugin(view as EditorView, hooks));
  return Extension.list(<Extension>[
    plugin,
    Prec.highest(EditorViewLike.eventHandlers(EditorEventHandlers(keyDown: (event, view) => view is EditorView && (_sessions[view]?.key(event) ?? false)))),
  ]);
}

class _KeymapPlugin extends PluginValue {
  _KeymapPlugin(EditorView view, KeymapHooks hooks) : session = KeymapSession._(view, hooks) {
    _sessions[view] = session;
  }

  final KeymapSession session;

  @override
  void update(ViewUpdate update) => session._viewUpdated(update);

  @override
  void destroy() => session._close();
}

/// One editor's keyboard modes: the engines made for it, as each is first chosen, and what the badge reads.
class KeymapSession extends ChangeNotifier {
  KeymapSession._(this.view, this.hooks) : _focused = view.hasFocus {
    _stopStorage = onPluginStorage(_choiceChanged);
    plugins.addListener(_choiceChanged);
    hardwareKeyboardSeen.addListener(_choiceChanged);
    _sync(hooks.mode());
  }

  final EditorView view;
  final KeymapHooks hooks;
  late final VoidCallback _stopStorage;
  bool _closed = false;

  late final EditorKeyText _text = EditorKeyText(view, hooks);

  KeyboardMode _mode = KeyboardMode.off;

  /// The way of typing in force in this editor.
  KeyboardMode get mode => _mode;

  /// Vim and Emacs, once each has been chosen in this editor.
  VimEngine? get vim => _vim;
  EmacsEngine? get emacs => _emacs;
  VimEngine? _vim;
  EmacsEngine? _emacs;

  /// Whether the editor has the keyboard's focus.
  bool get focused => _focused;
  bool _focused;

  /// Whether the badge is drawn at all: a way of typing on, and a hardware keyboard about.
  bool get showing => _mode != KeyboardMode.off && hardwareKeyboardSeen.value;

  void _choiceChanged() {
    if (_closed) return;
    _sync(hooks.mode());
    _caret();
    notifyListeners();
  }

  void _sync(KeyboardMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    switch (mode) {
      case KeyboardMode.vim:
        _vim ??= VimEngine(_text, start: (hooks.startNormal?.call() ?? true) ? VimMode.normal : VimMode.insert, jk: () => hooks.jk?.call() ?? false)..addListener(_engineChanged);
      case KeyboardMode.emacs:
        _emacs ??= EmacsEngine(_text)..addListener(_engineChanged);
      case KeyboardMode.off:
        break;
    }
    _caret();
  }

  void _engineChanged() {
    if (_closed) return;
    _caret();
    notifyListeners();
  }

  /// A key from the editor's focus: true where the chosen engine took it.
  bool key(KeyEvent event) {
    if (event is KeyUpEvent || _closed) return false;
    final mode = hooks.mode();
    _sync(mode);
    if (mode == KeyboardMode.off || view.composing) return false;
    if (!hardwareKeyboardSeen.value) {
      if (!onlyHardwareSends(event)) return false;
      hardwareKeyboardSeen.value = true;
    }
    final holding = hooks.holding?.call(view) ?? false;
    switch (mode) {
      case KeyboardMode.vim:
        final name = vimKeyName(event);
        final vim = _vim!;
        if (name == null) return false;
        if (holding && vim.mode == VimMode.insert && vim.commandLine == null) return false;
        return vim.handle(name);
      case KeyboardMode.emacs:
        final name = emacsKeyName(event);
        if (name == null || holding) return false;
        return _emacs!.handle(name);
      case KeyboardMode.off:
        return false;
    }
  }

  void _viewUpdated(ViewUpdate update) {
    if (update.focusChanged && _focused != view.hasFocus) {
      _focused = view.hasFocus;
      _later(notifyListeners);
    }
    if (_mode == KeyboardMode.off) return;
    if (!update.selectionSet && !update.docChanged) return;
    final main = update.state.selection.main;
    if (_mode == KeyboardMode.vim) {
      final vim = _vim;
      if (vim != null && !vim.busy && update.selectionSet) _later(() => vim.moved(main.anchor, main.head));
    } else {
      final emacs = _emacs;
      if (emacs != null && !emacs.busy) _later(() => emacs.moved(main.anchor, main.head, docChanged: update.docChanged));
    }
  }

  /// [then], once the update that asked for it is over: what it tells its listeners is drawn, and a listener may
  /// not be told in the middle of a build.
  void _later(VoidCallback then) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      then();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_closed) then();
    });
  }

  late final _BlockCaret _block = _BlockCaret(view);

  /// The block caret in Vim's Normal, the view's own everywhere else.
  void _caret() {
    final want = !_closed && _mode == KeyboardMode.vim && hardwareKeyboardSeen.value && _vim != null && !_vim!.mode.isVisual && _vim!.mode != VimMode.insert;
    final has = identical(view.selectionPainter, _block);
    if (want == has) return;
    view.selectionPainter = want ? _block : const EditorSelectionPainter();
    // The line the caret is on paints again: it hears the blink.
    final blink = view.caretOpacity, was = blink.value;
    blink.value = was == 0 ? 1 : 0;
    blink.value = was;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stopStorage();
    plugins.removeListener(_choiceChanged);
    hardwareKeyboardSeen.removeListener(_choiceChanged);
    _vim?.removeListener(_engineChanged);
    _emacs?.removeListener(_engineChanged);
    if (identical(view.selectionPainter, _block)) view.selectionPainter = const EditorSelectionPainter();
    _sessions[view] = null;
    dispose();
  }
}

/// The editor as a [KeyText].
class EditorKeyText implements KeyText {
  EditorKeyText(this.view, this.hooks);

  final EditorView view;
  final KeymapHooks hooks;

  @override
  String get text => view.state.doc.toString();

  @override
  int get anchor => view.state.selection.main.anchor;

  @override
  int get head => view.state.selection.main.head;

  @override
  bool get readOnly => view.state.readOnly;

  @override
  String get indentUnit => view.state.facet(commands.indentUnit);

  @override
  void select(int anchor, int head) => view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), userEvent: 'select.keymap', scrollIntoView: true));

  @override
  void change(List<KeyEdit> edits, int caret) => view.dispatch(TransactionSpec(
        changes: <ChangeSpec>[for (final edit in edits) ChangeSpec(from: edit.from, to: edit.to, insert: edit.insert)],
        selection: EditorSelection.single(caret),
        userEvent: edits.every((edit) => edit.insert.isEmpty) ? 'delete.keymap' : 'input.keymap',
        annotations: isolateHistory.of('before'),
        scrollIntoView: true,
      ));

  @override
  bool undo() {
    final before = view.state.doc;
    runCommand(view, undoNote);
    return !identical(before, view.state.doc);
  }

  @override
  bool redo() {
    final before = view.state.doc;
    runCommand(view, redoNote);
    return !identical(before, view.state.doc);
  }

  @override
  void save() => hooks.save?.call();

  @override
  void close() {
    final close = hooks.close;
    if (close == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => close());
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  bool vertical(bool forward, {required bool extend}) {
    final before = view.state.selection.main.head;
    extend ? selectByLine(view, forward) : cursorByLine(view, forward);
    return view.state.selection.main.head != before;
  }
}

/// Vim's caret in Normal: a block the width of the character under it, in the caret's colour and see-through, so
/// the letter is read through it.
class _BlockCaret extends EditorSelectionPainter {
  _BlockCaret(this.view);

  final EditorView view;

  @override
  void paintCaret(Canvas canvas, Rect caret, Color color, double opacity) {
    if (opacity <= 0) return;
    var width = caret.height * 0.5;
    final head = view.state.selection.main.head, doc = view.state.doc;
    if (head < doc.length && doc.sliceString(head, head + 1) != '\n') {
      final here = view.coordsAtPos(head, 1), next = view.coordsAtPos(head + 1, -1);
      if (here != null && next != null && (next.top - here.top).abs() < 1 && next.left > here.left) width = next.left - here.left;
    }
    canvas.drawRect(Rect.fromLTWH(caret.left, caret.top, width, caret.height), Paint()..color = color.withValues(alpha: color.a * opacity * 0.45));
  }
}

// ---- keys by name ------------------------------------------------------------------------------------------------

/// A letter key's letter, `a` to `z`, or null.
String? _letter(LogicalKeyboardKey key) {
  final id = key.keyId;
  return id >= 0x61 && id <= 0x7a ? String.fromCharCode(id) : null;
}

/// A character a key types that is drawn: not a control character, not a space.
bool _drawn(String? character) => character != null && character.isNotEmpty && character.runes.length == 1 && character.codeUnitAt(0) > 0x20 && character.codeUnitAt(0) != 0x7f;

/// Whether only a hardware keyboard sends [event]: a screen keyboard types its letters as text, and sends at most
/// Backspace and Enter as keys.
bool onlyHardwareSends(KeyEvent event) {
  final held = HardwareKeyboard.instance;
  if (event.logicalKey == LogicalKeyboardKey.escape) return true;
  if ((held.isControlPressed || held.isAltPressed) && _letter(event.logicalKey) != null) return true;
  return _drawn(event.character);
}

/// [event] as Vim's engine names keys (vim.dart), or null for a key Vim never takes: anything with Cmd, a Control
/// chord but Ctrl-[ and Ctrl-r, the arrows and the other keys that type nothing.
String? vimKeyName(KeyEvent event) {
  final held = HardwareKeyboard.instance;
  final key = event.logicalKey;
  if (held.isMetaPressed) return null;
  if (key == LogicalKeyboardKey.escape) return vimEscape;
  if (held.isControlPressed) {
    if (held.isAltPressed) return null;
    if (key == LogicalKeyboardKey.bracketLeft) return vimEscape;
    if (key == LogicalKeyboardKey.keyR) return vimRedo;
    return null;
  }
  if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return vimEnter;
  if (key == LogicalKeyboardKey.backspace) return vimBackspace;
  if (key == LogicalKeyboardKey.tab) return vimTab;
  if (key == LogicalKeyboardKey.space) return ' ';
  final character = event.character;
  return _drawn(character) ? character : null;
}

/// [event] as Emacs's engine names keys (emacs.dart): `C-f`, `M-f`, `C-SPC`, `M-<`, `M-DEL`, `DEL`, `RET`, `ESC`,
/// or a character as itself; null for a key Emacs never takes (anything with Cmd, Control with Alt, a Control or
/// Meta chord with Shift but `C-_`, `C-@`, `M-<` and `M->`).
String? emacsKeyName(KeyEvent event) {
  final held = HardwareKeyboard.instance;
  final key = event.logicalKey;
  final ctrl = held.isControlPressed, alt = held.isAltPressed, shift = held.isShiftPressed;
  if (held.isMetaPressed || (ctrl && alt)) return null;
  if (key == LogicalKeyboardKey.escape) return 'ESC';
  if (key == LogicalKeyboardKey.backspace) return alt ? 'M-DEL' : (ctrl ? null : 'DEL');
  if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return ctrl || alt ? null : 'RET';
  if (ctrl) {
    if (key == LogicalKeyboardKey.space || (shift && key == LogicalKeyboardKey.digit2)) return 'C-SPC';
    if (key == LogicalKeyboardKey.slash && !shift) return 'C-/';
    if (key == LogicalKeyboardKey.minus && shift) return 'C-_';
    final letter = _letter(key);
    return letter != null && !shift ? 'C-$letter' : null;
  }
  if (alt) {
    if (shift && (key == LogicalKeyboardKey.comma || key == LogicalKeyboardKey.less)) return 'M-<';
    if (shift && (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.greater)) return 'M->';
    final letter = _letter(key);
    return letter != null && !shift ? 'M-$letter' : null;
  }
  final character = event.character;
  return _drawn(character) ? character : null;
}
