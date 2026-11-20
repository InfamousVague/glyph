import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// The app's keyboard commands and push to talk (Matt, 2026-11-20: "add push to talk and full keyboard commands with a
/// keyboard shortcuts setting in settings"): what each does, the keys it is on unless changed, and the keys the person
/// chose, kept with the app's choices ('keys'). Settings › Keyboard shortcuts lists and changes them
/// (lib/ui/settings_panes.dart); the frame listens for them (lib/ui/shell.dart).
///
/// They are heard while the app is in front, on a computer and on a phone or tablet with a keyboard. A command with
/// Cmd (Ctrl on Windows and a phone), Ctrl or Alt in it works while typing; one on a key alone (push to talk's ` and
/// the like) does not fire while the cursor is in a text field, so it can still be typed.
enum KeyCommand {
  pushToTalk('Push to talk', 'Hold to talk in a call while push to talk is on', group: 'Calls'),
  toggleMute('Mute or unmute', 'In a call', group: 'Calls'),
  toggleDeafen('Deafen or undeafen', 'In a call', group: 'Calls'),
  leaveCall('Leave the call', 'In a call', group: 'Calls'),
  newChat('Start something new', 'A chat, a group, a space or a circle', group: 'Go to'),
  search('Search', 'The conversations\' search', group: 'Go to'),
  messages('Messages', 'The list of conversations', group: 'Go to'),
  contacts('Contacts', null, group: 'Go to'),
  archive('Archive', null, group: 'Go to'),
  voice('Spaces', 'Spaces and the call you are in', group: 'Go to'),
  settings('Settings', null, group: 'Go to'),
  marketplace('Marketplace', null, group: 'Go to'),
  closePage('Close the page', 'The conversation or page open beside the list', group: 'Go to'),
  shortcuts('Keyboard shortcuts', 'This list', group: 'Go to');

  const KeyCommand(this.label, this.hint, {required this.group});
  final String label;
  final String? hint;
  final String group;
}

/// A key and what is held with it. [primary] is Cmd on a Mac and Ctrl elsewhere, as an app's shortcuts are.
@immutable
class KeyBinding {
  const KeyBinding(this.key, {this.primary = false, this.shift = false, this.alt = false, this.control = false});

  final LogicalKeyboardKey key;
  final bool primary;
  final bool shift;
  final bool alt;

  /// Ctrl as itself on a Mac, where [primary] is Cmd; on the others it is [primary].
  final bool control;

  static bool get _mac => !kIsWeb && Platform.isMacOS;

  /// Whether it holds a key that is not typed: it works while the cursor is in a field.
  bool get chord => primary || alt || control;

  Map<String, Object> toJson() => {'k': key.keyId, if (primary) 'p': 1, if (shift) 's': 1, if (alt) 'a': 1, if (control) 'c': 1};

  static KeyBinding? fromJson(Object? j) {
    if (j is! Map || j['k'] is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(j['k'] as int);
    if (key == null) return null;
    return KeyBinding(key, primary: j['p'] == 1, shift: j['s'] == 1, alt: j['a'] == 1, control: j['c'] == 1);
  }

  /// The binding made by a key pressed now, with what is held: what a person sets in Settings.
  static KeyBinding? pressed(KeyEvent e) {
    final k = e.logicalKey;
    if (_modifier(k)) return null;
    final held = HardwareKeyboard.instance;
    final meta = held.isMetaPressed, ctrl = held.isControlPressed;
    return KeyBinding(
      k,
      primary: _mac ? meta : ctrl,
      control: _mac && ctrl,
      shift: held.isShiftPressed,
      alt: held.isAltPressed,
    );
  }

  static bool _modifier(LogicalKeyboardKey k) => {
        LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.shift,
        LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, LogicalKeyboardKey.control,
        LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight, LogicalKeyboardKey.alt,
        LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight, LogicalKeyboardKey.meta,
        LogicalKeyboardKey.fn, LogicalKeyboardKey.capsLock,
      }.contains(k);

  /// Whether [e] is this key with exactly what this holds held (Shift and the rest must match, so Cmd+Shift+M is not
  /// Cmd+M).
  bool matches(KeyEvent e) {
    if (!_same(e.logicalKey, key)) return false;
    final held = HardwareKeyboard.instance;
    final meta = held.isMetaPressed, ctrl = held.isControlPressed;
    final wantMeta = _mac && primary, wantCtrl = _mac ? control : primary;
    return meta == wantMeta && ctrl == wantCtrl && held.isShiftPressed == shift && held.isAltPressed == alt;
  }

  /// The same key, either side's for a modifier used alone and the number row's or the keypad's Enter.
  static bool _same(LogicalKeyboardKey a, LogicalKeyboardKey b) {
    if (a == b) return true;
    bool enter(LogicalKeyboardKey k) => k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;
    return enter(a) && enter(b);
  }

  /// How it is written: "Cmd+Shift+M" on a Mac, "Ctrl+Shift+M" elsewhere.
  String get label {
    final name = _keyName(key);
    // In words, not ⌘ and ⇧: the app's own font has no such signs.
    if (_mac) return [if (primary) 'Cmd', if (control) 'Ctrl', if (alt) 'Option', if (shift) 'Shift', name].join('+');
    return [if (primary || control) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', name].join('+');
  }

  static String _keyName(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.backquote) return '`';
    if (k == LogicalKeyboardKey.space) return 'Space';
    if (k == LogicalKeyboardKey.escape) return 'Esc';
    if (k == LogicalKeyboardKey.comma) return ',';
    if (k == LogicalKeyboardKey.slash) return '/';
    if (k == LogicalKeyboardKey.enter) return 'Enter';
    final label = k.keyLabel;
    return label.isEmpty ? (k.debugName ?? '?') : (label.length == 1 ? label.toUpperCase() : label);
  }

  @override
  bool operator ==(Object other) => other is KeyBinding && other.key == key && other.primary == primary && other.shift == shift && other.alt == alt && other.control == control;

  @override
  int get hashCode => Object.hash(key, primary, shift, alt, control);
}

class Keys extends ChangeNotifier {
  Keys._();
  static final Keys instance = Keys._();

  /// A fresh one, for a test.
  @visibleForTesting
  factory Keys.forTest() => Keys._();

  AppState? _app;
  final Map<KeyCommand, KeyBinding?> _chosen = {};

  /// The conversation list's search field, while it is on the screen: what [KeyCommand.search] puts the cursor in.
  static final searchFocus = FocusNode(debugLabel: 'conversations search');

  static const defaults = {
    KeyCommand.pushToTalk: KeyBinding(LogicalKeyboardKey.backquote),
    KeyCommand.toggleMute: KeyBinding(LogicalKeyboardKey.keyM, primary: true, shift: true),
    KeyCommand.toggleDeafen: KeyBinding(LogicalKeyboardKey.keyD, primary: true, shift: true),
    KeyCommand.leaveCall: KeyBinding(LogicalKeyboardKey.keyE, primary: true, shift: true),
    KeyCommand.newChat: KeyBinding(LogicalKeyboardKey.keyN, primary: true),
    KeyCommand.search: KeyBinding(LogicalKeyboardKey.keyK, primary: true),
    KeyCommand.messages: KeyBinding(LogicalKeyboardKey.digit1, primary: true),
    KeyCommand.contacts: KeyBinding(LogicalKeyboardKey.digit2, primary: true),
    KeyCommand.archive: KeyBinding(LogicalKeyboardKey.digit3, primary: true),
    KeyCommand.voice: KeyBinding(LogicalKeyboardKey.digit4, primary: true),
    KeyCommand.settings: KeyBinding(LogicalKeyboardKey.comma, primary: true),
    KeyCommand.marketplace: KeyBinding(LogicalKeyboardKey.digit5, primary: true),
    KeyCommand.closePage: KeyBinding(LogicalKeyboardKey.keyW, primary: true),
    KeyCommand.shortcuts: KeyBinding(LogicalKeyboardKey.slash, primary: true),
  };

  void start(AppState app) {
    _app = app;
    _chosen.clear();
    try {
      final kept = jsonDecode(app.choice('keys', '{}')) as Map;
      for (final c in KeyCommand.values) {
        if (!kept.containsKey(c.name)) continue;
        // null kept: the person took the command off any key.
        _chosen[c] = KeyBinding.fromJson(kept[c.name]);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Push to talk: in a call the microphone is off unless its key is held. Off unless switched on.
  bool get pushToTalk => _app?.flag('push_to_talk', fallback: false) ?? false;
  void setPushToTalk(bool on) {
    _app?.setFlag('push_to_talk', on);
    notifyListeners();
  }

  /// The keys [c] is on: the person's, or its own; null where it is on none.
  KeyBinding? of(KeyCommand c) => _chosen.containsKey(c) ? _chosen[c] : defaults[c];

  bool changed(KeyCommand c) => _chosen.containsKey(c) && _chosen[c] != defaults[c];

  /// The command already on [b], other than [except]: what a new binding would take it from.
  KeyCommand? usedBy(KeyBinding b, {KeyCommand? except}) =>
      KeyCommand.values.where((c) => c != except && of(c) == b).firstOrNull;

  /// Puts [c] on [b] (null: on no key). Another command on the same keys is taken off them.
  void set(KeyCommand c, KeyBinding? b) {
    if (b != null) {
      final other = usedBy(b, except: c);
      if (other != null) _chosen[other] = null;
    }
    _chosen[c] = b;
    _save();
  }

  void reset(KeyCommand c) {
    _chosen.remove(c);
    final mine = defaults[c];
    if (mine != null) {
      final other = usedBy(mine, except: c);
      if (other != null) _chosen[other] = null;
    }
    _save();
  }

  void resetAll() {
    _chosen.clear();
    _save();
  }

  void _save() {
    _app?.set('keys', jsonEncode({for (final e in _chosen.entries) e.key.name: e.value?.toJson()}));
    notifyListeners();
  }

  /// The command [e] is, given whether the cursor is in a text field ([typing]): one on a key alone is not taken
  /// from someone typing.
  KeyCommand? commandFor(KeyEvent e, {required bool typing}) {
    for (final c in KeyCommand.values) {
      final b = of(c);
      if (b == null || !b.matches(e)) continue;
      if (typing && !b.chord) continue;
      return c;
    }
    return null;
  }

  /// Whether the cursor is in a text field now.
  static bool get typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
