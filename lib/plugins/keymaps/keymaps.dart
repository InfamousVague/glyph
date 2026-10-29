/// The Keyboard modes plugin, built in and off until added: a note typed from a hardware keyboard the way Vim or
/// Emacs types (Matt, 2026-10-29: "add vim controls to the app via a plugin as well", then "add a vim / emac
/// controls via a plugin"). Its page chooses Off, Vim or Emacs; Vim then has Start notes in Normal mode and jk to
/// leave Insert.
///
/// The engines are their own files and know nothing of the editor: vim.dart and emacs.dart, over text.dart's
/// [KeyText]. The editor reaches them through one extension the note's desk always gives its editor
/// (editor_keys.dart `keyboardModes`), which asks [keyboardMode] at every key, so a choice made on the page is in
/// the note already open; and the badge at the editor's foot (mode_badge.dart) says the mode, or the mark or the
/// search while Emacs holds one.
///
/// Only a hardware keyboard's keys are taken: the screen's keyboard types as it always has, and on a phone nothing
/// shows until a key that only a hardware keyboard sends has been pressed (editor_keys.dart [hardwareKeyboardSeen]).
/// It keeps three switches on this device and reaches nothing past it.
library;

import '../../settings/settings_search.dart' show SettingsFindable;
import '../host.dart';
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'keymaps_pane.dart';

export 'editor_keys.dart' show KeymapHooks, hardwareKeyboardSeen, keyboardModes, keymapSessionOf;
export 'keymaps_pane.dart' show KeymapsPane;
export 'mode_badge.dart' show KeymapBadge;

/// The plugin's id: its switch, and its page's (`plugin:keyboard-modes`).
const String keymapsId = 'keyboard-modes';

/// Which way of typing: `off`, `vim` or `emacs`.
const String keymapModeKey = 'glyph-keymaps-mode';

/// Vim's two: whether a note opens in Normal, and whether `jk` leaves Insert.
const String vimNormalStartKey = 'glyph-keymaps-vim-normal';
const String vimJkKey = 'glyph-keymaps-vim-jk';

const PluginManifest keymapsManifest = PluginManifest(
  id: keymapsId,
  name: 'Keyboard modes',
  description: 'Type in your notes from a hardware keyboard the way Vim or Emacs does: Vim’s Normal, Insert and Visual modes and its command line, or Emacs’s Control and Meta keys, its kills and its search.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.editor,
  tagline: 'Vim or Emacs keys in your notes',
  adds: [
    'Vim’s modes in a note: Normal, Insert, Visual and a command line, with :w and :q',
    'Or Emacs’s keys: C-a and C-e, C-k and C-y, the mark and C-s',
    'A small badge at the note’s foot with the mode you are in',
  ],
  // Off until added: it changes what the letters do.
  standard: false,
  permissions: [],
  storage: [keymapModeKey, vimNormalStartKey, vimJkKey],
);

/// The plugin's host: its storage alone.
final PluginHost keymapsHost = createHost(keymapsManifest);

/// The ways of typing its page chooses between.
enum KeyboardMode {
  off('Off'),
  vim('Vim'),
  emacs('Emacs');

  const KeyboardMode(this.label);

  final String label;
}

/// The way of typing chosen, as the plugin is: [KeyboardMode.off] while it is switched off. Vim until one is chosen.
KeyboardMode keyboardMode([PluginHost? via]) {
  if (!pluginOn(keymapsManifest)) return KeyboardMode.off;
  return keyboardModeChosen(via);
}

/// The way chosen on its page, whether the plugin is on or not.
KeyboardMode keyboardModeChosen([PluginHost? via]) {
  final kept = (via ?? keymapsHost).storage.get<Object?>(keymapModeKey, null);
  return KeyboardMode.values.firstWhere((mode) => mode.name == kept, orElse: () => KeyboardMode.vim);
}

void setKeyboardMode(KeyboardMode mode, [PluginHost? via]) => (via ?? keymapsHost).storage.set(keymapModeKey, mode.name);

/// Whether a note opens in Vim's Normal mode; on until switched off.
bool vimStartsNormal([PluginHost? via]) => (via ?? keymapsHost).storage.get<Object?>(vimNormalStartKey, true) != false;
void setVimStartsNormal(bool on, [PluginHost? via]) => (via ?? keymapsHost).storage.set(vimNormalStartKey, on);

/// Whether `jk` typed quickly leaves Insert; off until switched on.
bool vimJk([PluginHost? via]) => (via ?? keymapsHost).storage.get<Object?>(vimJkKey, false) == true;
void setVimJk(bool on, [PluginHost? via]) => (via ?? keymapsHost).storage.set(vimJkKey, on);

/// What the search finds on its page.
const List<SettingsFindable> keymapsFindable = [
  SettingsFindable('Keys', 'vim emacs keyboard modes normal insert visual off'),
  SettingsFindable('Start notes in Normal mode', 'vim normal mode start'),
  SettingsFindable('jk to leave Insert', 'vim jk escape insert'),
];

String _summary() => switch (keyboardModeChosen()) {
      KeyboardMode.off => 'Off',
      KeyboardMode.vim => 'Vim keys',
      KeyboardMode.emacs => 'Emacs keys',
    };

/// See the header.
final GlyphPlugin keymapsPlugin = GlyphPlugin(
  manifest: keymapsManifest,
  icon: 'terminal',
  settings: PluginSettings(
    pane: (context) => const KeymapsPane(),
    summary: _summary,
    hue: 'mint',
    settings: keymapsFindable,
  ),
);

