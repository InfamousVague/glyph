/// Keys: CodeMirror's `keymap` facet and the way it runs a key (@codemirror/view, keymap.ts), bound through
/// Flutter's `ShortcutManager` and `Actions`.
///
/// [editorKeymap] is `keymap.of(bindings)`: a list of [KeyBinding]s (commands.dart) at the precedence it is given.
/// A key runs every binding it matches, highest precedence first, until one says it handled it; a binding with
/// `preventDefault` swallows the key even then. A binding with no `run` but a `viewCommand` is one of the commands
/// only a layout can answer (motion.dart).
///
/// How a key gets here: the editor's focus node hands every key event to a `ShortcutManager` whose shortcuts are
/// made from the bindings in force ([shortcutsFor]): one `SingleActivator` for each key the keymaps name, each to
/// an [EditorKeyIntent] that carries CodeMirror's name for the key. The editor's `Actions` answer that intent with
/// [runKey]. So a hardware keyboard and the screen keyboard's Backspace (which Android sends as a key, docs/STAGE4.md
/// rule 2) take the same road, and what no binding takes goes on to the app's own shortcuts and then to the
/// keyboard's text.
///
/// What differs from CodeMirror:
/// - a key is named from Flutter's logical key, not from the character it would type, so a binding for `Mod-/`
///   is the key that types `/` unshifted on the keyboard in use;
/// - multi-stroke bindings (`Ctrl-x Ctrl-s`) and `scope` are not read: no keymap of the app's has either;
/// - `any` handlers are not here: a plugin's `keyDown` handler (plugin.dart) sees every key first.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../commands/commands.dart';
import '../commands/markdown_commands.dart';
import '../state/history.dart';
import '../state/state.dart';
import '../state/undo_slot.dart';
import '../view/editor_view.dart';
import 'motion.dart';

/// CodeMirror's `keymap` facet: `keymap.of(bindings)` is `editorKeymap.of(bindings)`.
final Facet<List<KeyBinding>, List<List<KeyBinding>>> editorKeymap = Facet.define<List<KeyBinding>, List<List<KeyBinding>>>();

/// CodeMirror's `historyKeymap` (@codemirror/commands, history.ts): Mod-z undoes, Mod-y (Mod-Shift-z on a Mac,
/// and Ctrl-Shift-z on Linux, which is what Android is to CodeMirror) redoes, Mod-u and Alt-u (Mod-Shift-u) undo
/// and redo a selection.
final List<KeyBinding> historyKeymap = List<KeyBinding>.unmodifiable(<KeyBinding>[
  KeyBinding(key: 'Mod-z', run: undo, preventDefault: true),
  KeyBinding(key: 'Mod-y', mac: 'Mod-Shift-z', run: redo, preventDefault: true),
  KeyBinding(linux: 'Ctrl-Shift-z', run: redo, preventDefault: true),
  KeyBinding(key: 'Mod-u', run: undoSelection, preventDefault: true),
  KeyBinding(key: 'Alt-u', mac: 'Mod-Shift-u', run: redoSelection, preventDefault: true),
]);

/// y-codemirror's `yUndoManagerKeymap` (y-undomanager.js), which liveBinding.ts puts in the undo slot with the
/// live document's undo: Mod-z, Mod-y (Mod-Shift-z on a Mac) and Mod-Shift-z everywhere. No undo of a selection:
/// Yjs has none.
final List<KeyBinding> liveUndoKeymap = List<KeyBinding>.unmodifiable(<KeyBinding>[
  KeyBinding(key: 'Mod-z', run: undoLive, preventDefault: true),
  KeyBinding(key: 'Mod-y', mac: 'Mod-Shift-z', run: redoLive, preventDefault: true),
  KeyBinding(key: 'Mod-Shift-z', run: redoLive, preventDefault: true),
]);

/// lang-markdown's `markdownKeymap` as bindings: Enter continues a list or a quote, Backspace takes a marker whole.
final List<KeyBinding> markdownBindings = List<KeyBinding>.unmodifiable(<KeyBinding>[
  for (final binding in markdownKeymap) KeyBinding(key: binding.key, run: binding.run),
]);

/// Which of a binding's keys is this platform's: CodeMirror's `mac`, `win` and `linux`, where an iPhone is a Mac
/// and Android is Linux.
enum KeyPlatform {
  mac,
  win,
  linux;

  static KeyPlatform get current => switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => KeyPlatform.mac,
    TargetPlatform.windows => KeyPlatform.win,
    _ => KeyPlatform.linux,
  };
}

// A key's name in its parts, and each modifier's spellings: made once, not for every name read.
final RegExp _keyParts = RegExp(r'-(?!$)');
final RegExp _isMeta = RegExp(r'^(cmd|meta|m)$', caseSensitive: false);
final RegExp _isAlt = RegExp(r'^a(lt)?$', caseSensitive: false);
final RegExp _isCtrl = RegExp(r'^(c|ctrl|control)$', caseSensitive: false);
final RegExp _isShift = RegExp(r'^s(hift)?$', caseSensitive: false);
final RegExp _isMod = RegExp(r'^mod$', caseSensitive: false);
final RegExp _functionKey = RegExp(r'^F(\d\d?)$');

/// CodeMirror's `normalizeKeyName`: `Mod-Shift-z` as `Ctrl-Shift-z` (or `Meta-Shift-z`), modifiers in the order
/// Alt, Ctrl, Meta, Shift. A capital letter is its key with Shift (`Alt-A` is `Alt-Shift-a`).
String normalizeKeyName(String name, KeyPlatform platform) {
  final parts = name.split(_keyParts);
  var result = parts.last;
  if (result == 'Space') result = ' ';
  var alt = false, ctrl = false, shift = false, meta = false;
  for (var i = 0; i < parts.length - 1; i++) {
    final mod = parts[i];
    if (_isMeta.hasMatch(mod)) {
      meta = true;
    } else if (_isAlt.hasMatch(mod)) {
      alt = true;
    } else if (_isCtrl.hasMatch(mod)) {
      ctrl = true;
    } else if (_isShift.hasMatch(mod)) {
      shift = true;
    } else if (_isMod.hasMatch(mod)) {
      if (platform == KeyPlatform.mac) {
        meta = true;
      } else {
        ctrl = true;
      }
    } else {
      throw ArgumentError('Unrecognized modifier name: $mod');
    }
  }
  if (result.length == 1 && result.toLowerCase() != result) {
    shift = true;
    result = result.toLowerCase();
  }
  if (alt) result = 'Alt-$result';
  if (ctrl) result = 'Ctrl-$result';
  if (meta) result = 'Meta-$result';
  if (shift) result = 'Shift-$result';
  return result;
}

const Map<String, LogicalKeyboardKey> _named = <String, LogicalKeyboardKey>{
  'ArrowLeft': LogicalKeyboardKey.arrowLeft,
  'ArrowRight': LogicalKeyboardKey.arrowRight,
  'ArrowUp': LogicalKeyboardKey.arrowUp,
  'ArrowDown': LogicalKeyboardKey.arrowDown,
  'Home': LogicalKeyboardKey.home,
  'End': LogicalKeyboardKey.end,
  'PageUp': LogicalKeyboardKey.pageUp,
  'PageDown': LogicalKeyboardKey.pageDown,
  'Enter': LogicalKeyboardKey.enter,
  'Backspace': LogicalKeyboardKey.backspace,
  'Delete': LogicalKeyboardKey.delete,
  'Escape': LogicalKeyboardKey.escape,
  'Tab': LogicalKeyboardKey.tab,
  ' ': LogicalKeyboardKey.space,
};

/// The logical key CodeMirror's `name` (the last part of a binding's key) stands for, or null.
LogicalKeyboardKey? keyNamed(String name) {
  final named = _named[name];
  if (named != null) return named;
  if (name.length == 1) return LogicalKeyboardKey.findKeyByKeyId(name.codeUnitAt(0)) ?? LogicalKeyboardKey(name.codeUnitAt(0));
  final f = _functionKey.firstMatch(name);
  if (f != null) return LogicalKeyboardKey.findKeyByKeyId(LogicalKeyboardKey.f1.keyId + int.parse(f.group(1)!) - 1);
  return null;
}

/// One command a key runs: a binding's `run` or its `shift`, with what the view has to supply.
class BoundCommand {
  const BoundCommand(this.run, this.viewCommand, this.preventDefault);

  final StateCommand? run;
  final String? viewCommand;
  final bool preventDefault;
}

/// The bindings in force, by normalized key: CodeMirror's `buildKeymap`.
class Keymap {
  Keymap._(this.byKey);

  /// Builds the map from the keymaps of a state, highest precedence first.
  factory Keymap.of(List<List<KeyBinding>> keymaps, [KeyPlatform? platform]) {
    final on = platform ?? KeyPlatform.current;
    final byKey = <String, List<BoundCommand>>{};
    void add(String key, StateCommand? run, String? viewCommand, bool preventDefault) {
      if (run == null && viewCommand == null) return;
      byKey.putIfAbsent(normalizeKeyName(key, on), () => <BoundCommand>[]).add(BoundCommand(run, viewCommand, preventDefault));
    }

    for (final bindings in keymaps) {
      for (final b in bindings) {
        final name = switch (on) {
          KeyPlatform.mac => b.mac,
          KeyPlatform.win => b.win,
          KeyPlatform.linux => b.linux,
        } ?? b.key;
        if (name == null) continue;
        add(name, b.run, b.viewCommand, b.preventDefault);
        if (b.shift != null || b.shiftViewCommand != null) add('Shift-$name', b.shift, b.shiftViewCommand, b.preventDefault);
      }
    }
    return Keymap._(byKey);
  }

  static final Expando<Keymap> _made = Expando<Keymap>('keymap');

  /// The keymap of `state`, made once for each value of the facet.
  static Keymap forState(EditorState state) {
    final keymaps = state.facet(editorKeymap);
    return _made[keymaps] ??= Keymap.of(keymaps);
  }

  final Map<String, List<BoundCommand>> byKey;

  /// One activator for each bound key, to the intent that names it.
  late final Map<ShortcutActivator, Intent> shortcuts = () {
    final shortcuts = <ShortcutActivator, Intent>{};
    for (final name in byKey.keys) {
      final parts = name.split(_keyParts);
      final key = keyNamed(parts.last);
      if (key == null) continue;
      final mods = parts.sublist(0, parts.length - 1).toSet();
      shortcuts[SingleActivator(key, alt: mods.contains('Alt'), control: mods.contains('Ctrl'), meta: mods.contains('Meta'), shift: mods.contains('Shift'))] = EditorKeyIntent(name);
    }
    return shortcuts;
  }();
}

/// The editor's shortcuts: a `ShortcutManager` the editor's own focus node asks, where a `Shortcuts` widget would
/// ask it (that widget is a box, and the editor is a sliver).
class EditorShortcuts extends ShortcutManager {
  /// What the manager makes of a key event, from `context`'s place in the tree.
  KeyEventResult handle(BuildContext context, KeyEvent event) => handleKeypress(context, event);
}

/// A key the editor's keymaps bind, by CodeMirror's normalized name (`Ctrl-Shift-z`, `Backspace`).
class EditorKeyIntent extends Intent {
  const EditorKeyIntent(this.key);

  final String key;
}

/// Runs an [EditorKeyIntent] against a view: [runKey]. The key is handled when a binding took it, and goes on to
/// whoever is next when none did.
class EditorKeyAction extends Action<EditorKeyIntent> {
  EditorKeyAction(this.view);

  final EditorView Function() view;

  @override
  Object? invoke(EditorKeyIntent intent) => runKey(view(), intent.key);

  @override
  KeyEventResult toKeyEventResult(EditorKeyIntent intent, Object? invokeResult) => invokeResult == true ? KeyEventResult.handled : KeyEventResult.ignored;
}

/// The commands of commands.dart that stop at a document line's ends, and what stops at a wrapped line's instead.
final Map<StateCommand, bool Function(EditorView view)> _byLayout = Map<StateCommand, bool Function(EditorView view)>.identity()
  ..addAll(<StateCommand, bool Function(EditorView view)>{
    cursorLineBoundaryForward: (view) => cursorLineBoundary(view, true),
    cursorLineBoundaryBackward: (view) => cursorLineBoundary(view, false),
    cursorLineBoundaryLeft: (view) => cursorLineBoundary(view, false),
    cursorLineBoundaryRight: (view) => cursorLineBoundary(view, true),
    selectLineBoundaryForward: (view) => selectLineBoundary(view, true),
    selectLineBoundaryBackward: (view) => selectLineBoundary(view, false),
    selectLineBoundaryLeft: (view) => selectLineBoundary(view, false),
    selectLineBoundaryRight: (view) => selectLineBoundary(view, true),
    deleteLineBoundaryBackward: (view) => deleteLineBoundary(view, false),
    deleteLineBoundaryForward: (view) => deleteLineBoundary(view, true),
  });

/// Runs one command on the view: its layout twin where it has one.
bool runCommand(EditorView view, StateCommand command) => (_byLayout[command] ?? command)(view);

/// CodeMirror's `runHandlers` for one key, by its normalized name: every binding for it in turn until one handles
/// it. True when the key was handled or a binding asked for it to be swallowed.
bool runKey(EditorView view, String key) {
  final bound = Keymap.forState(view.state).byKey[key];
  if (bound == null) return false;
  var prevent = false;
  for (final command in bound) {
    if (command.run != null) {
      if (runCommand(view, command.run!)) return true;
    } else if (viewCommands[command.viewCommand]?.call(view) ?? false) {
      return true;
    }
    if (command.preventDefault) prevent = true;
  }
  return prevent;
}
