/// The plugins in this build, which are switched on, and everything they offer. A port of
/// `src/app/plugins/registry.ts`.
///
/// The app asks here and never names a plugin: the note's cog asks for `noteLinks()`, the recorder for `tips()` and
/// `formats()`, the formatter for `contextFor(noteId)`, Settings for the registry itself, which is a [Listenable].
/// A switched-off plugin offers nothing anywhere, at once; its data stays where it was, so switching it on again
/// brings it back as it was.
///
/// Switches are `glyph-plugins` in the device's memory (id to on/off), and a plugin with no switch yet is on if it
/// is standard.
///
/// What differs:
/// - The page made one registry of its built-in plugins as the module loaded. Here [createRegistry] is the same
///   function, and the app's registry is [plugins], which starts empty and is put in place by
///   `installBuiltInPlugins` (built_in.dart) once the root has its storage and preferences; a test makes its own
///   and may [usePlugins] it.
/// - Local only is read from the `localOnly` it is given (the root's preferences), and [Registry.preferencesChanged]
///   is what the root calls when they change, where the page's registry listened by itself.
/// - `subscribe` is [Listenable.addListener]; `usePlugins()` (hooks.ts) is a `ListenableBuilder` on the registry.
library;

import 'package:flutter/foundation.dart';

import '../core/item_links.dart' show registerMarkName;
import '../core/notifications.dart' show FeedNotification;
import '../core/stored.dart';
import 'host.dart';
import 'reach.dart';
import 'types.dart';

/// `SWITCHES_KEY`.
const String pluginSwitchesKey = 'glyph-plugins';

/// A note's link to something outside it, with that thing's name (`NoteLinked`).
class NoteLinked {
  const NoteLinked(this.link, this.name);
  final NoteLink link;
  final String name;
}

/// Where the switches are kept (`SwitchStore`).
abstract interface class SwitchStore {
  Map<String, bool> read();
  void write(Map<String, bool> switches);
}

/// The switches in the app's own memory, under [pluginSwitchesKey] (`localSwitches`).
class StoredSwitches implements SwitchStore {
  const StoredSwitches([this._stored]);
  final Stored? _stored;

  @override
  Map<String, bool> read() => (_stored ?? stored).read<Map<String, bool>>(pluginSwitchesKey, const {}, (raw) => raw is Map ? {for (final MapEntry(:key, :value) in raw.entries) if (key is String && value is bool) key: value} : const {});

  // Without storage a switch lasts as long as the app.
  @override
  void write(Map<String, bool> switches) => (_stored ?? stored).write(pluginSwitchesKey, switches);
}

/// The switches for this run only: a test's.
class MemorySwitches implements SwitchStore {
  MemorySwitches([Map<String, bool>? held]) : held = {...?held};
  Map<String, bool> held;

  @override
  Map<String, bool> read() => held;

  @override
  void write(Map<String, bool> switches) => held = switches;
}

/// A node name the parser can carry, and a delimiter: a run of one character Markdown itself doesn't use, or an
/// emoji twice, which is how an effect is written.
final RegExp _formatName = RegExp(r'^[A-Z][A-Za-z0-9]*$');
final RegExp _formatDelimiter = RegExp(r'^([^\w\s*_~`[\]<>#!()\\])\1{0,2}$');
final RegExp _effectDelimiter = RegExp(r'^(\p{Extended_Pictographic}\u{FE0F}?)\1$', unicode: true);

/// The extension points a plugin uses must match what its manifest asks for: anything that changes a note (an
/// action, the swipe, the words it offers on a note's lines) needs `notes`. Its formattings must be ones the parser
/// can carry. Checked when the registry is made, so a plugin that overreaches never loads.
void _checkExtensions(GlyphPlugin plugin) {
  final id = plugin.manifest.id;
  for (final format in plugin.formats) {
    if (!_formatName.hasMatch(format.name)) throw ArgumentError('The “$id” plugin\'s formatting “${format.name}” needs a capitalised name of letters and digits.');
    if (!_formatDelimiter.hasMatch(format.delimiter) && !_effectDelimiter.hasMatch(format.delimiter)) {
      throw ArgumentError('The “$id” plugin\'s “${format.name}” formatting needs a delimiter of one to three of the same character that Markdown doesn\'t already use, or an emoji twice, not “${format.delimiter}”.');
    }
  }
  if ((plugin.noteActions.isNotEmpty || plugin.itemAction != null || plugin.suggest != null) && !plugin.manifest.declares(Permission.notes)) {
    throw PluginPermissionError(plugin.manifest, 'the “notes” permission its note actions need');
  }
}

/// The registry (`Registry`). It tells its listeners when who is enabled changes.
class Registry extends ChangeNotifier {
  Registry._(this._plugins, this._store, this._localOnly) : _switches = _store.read();

  final List<GlyphPlugin> _plugins;
  final SwitchStore _store;
  final bool Function() _localOnly;
  Map<String, bool> _switches;

  /// A stable list between changes, so a listener that compares sees no change when there is none.
  List<GlyphPlugin>? _enabled;

  List<GlyphPlugin> all() => _plugins;

  List<GlyphPlugin> enabled() => _enabled ??= List.unmodifiable(_plugins.where((p) => isEnabled(p.manifest.id)));

  GlyphPlugin? byId(String id) {
    for (final plugin in _plugins) {
      if (plugin.manifest.id == id) return plugin;
    }
    return null;
  }

  /// Whether [id]'s switch has ever been moved on this device (it then has one of its own, kept).
  bool hasSwitch(String id) => _switches.containsKey(id);

  /// Switches on, once, a plugin that ships off but whose feature this device was already using before it was a
  /// plugin (a calendar added, the contacts turned on): [inUse] says so. A plugin whose switch has been moved, either
  /// way, is left as it was set.
  void adopt(String id, {required bool inUse}) {
    if (!inUse || hasSwitch(id) || byId(id) == null) return;
    _switches = {..._switches, id: true};
    _store.write(_switches);
    _told();
  }

  bool isEnabled(String id) {
    final plugin = byId(id);
    if (plugin == null) return false;
    // Local only holds off whatever reaches outside the phone (lib/core/preferences.dart).
    if (_localOnly() && usesNetwork(plugin.manifest)) return false;
    return _switches[id] ?? plugin.manifest.standard;
  }

  /// Whether [id] is added, as its switch is set, whatever Local only says: a plugin held off by it is still on the
  /// catalogue's Added shelf (lib/settings/panes/plugins_pane.dart), saying why it does nothing. Not on the page.
  bool switchedOn(String id) {
    final plugin = byId(id);
    return plugin != null && (_switches[id] ?? plugin.manifest.standard);
  }

  void setEnabled(String id, bool on) {
    if (byId(id) == null || isEnabled(id) == on) return;
    _switches = {..._switches, id: on};
    _store.write(_switches);
    _told();
  }

  /// Local only turning on or off changes who is enabled without a switch moving (`onPreferences`): the root calls
  /// this when the preferences change.
  void preferencesChanged() => _told();

  void _told() {
    _enabled = null;
    notifyListeners();
    markDetailsChanged();
  }

  /// `subscribe`: hears every change; answers the way to stop.
  VoidCallback subscribe(VoidCallback listener) {
    addListener(listener);
    return () => removeListener(listener);
  }

  List<NoteLink> noteLinks() => [for (final p in enabled()) ...p.noteLinks];

  /// What a note is linked to, by every switched-on plugin that says so: its link, and the name of the thing.
  List<NoteLinked> linksOf(String noteId) => [
        for (final link in noteLinks())
          if (link.linked?.call(noteId) case final String name when name.isNotEmpty) NoteLinked(link, name),
      ];

  List<NoteAction> noteActions() => [for (final p in enabled()) ...p.noteActions];

  ItemAction? itemAction(String noteId) {
    for (final p in enabled()) {
      final action = p.itemAction;
      if (action != null && action.available(noteId)) return action;
    }
    return null;
  }

  List<Tip> tips(String? recentTitle) => [for (final p in enabled()) ...?p.tips?.call(recentTitle)];

  /// The formatter's context for a note, from every plugin that gives one (`pluginContextFor`).
  String? contextFor(String noteId) {
    final parts = [
      for (final p in enabled())
        if (p.formatContext?.forNote(noteId) case final String part when part.trim().isNotEmpty) part,
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  /// `pluginContextVersion`.
  int contextVersion(String noteId) {
    // One context gives its own version, so a note formatted before plugins existed (with its project's version)
    // is not formatted again for it.
    final versions = [
      for (final p in enabled())
        if (p.formatContext?.version(noteId) case final int version when version != 0) version,
    ];
    if (versions.length <= 1) return versions.isEmpty ? 0 : versions.first;
    // `% 2 ** 52` on a double, as the page computes it: exact while the product stays under 2^53, which it does.
    const modulus = 4503599627370496; // 2^52
    return versions.fold<int>(7, (sum, version) => (sum * 31 + version) % modulus);
  }

  /// The words offered on a note's lines right now, from every switched-on plugin.
  List<Suggestion> suggestions(String noteId, String body) => [for (final p in enabled()) ...?p.suggest?.call(noteId, body)];

  /// Every key any plugin owns, switched on or not, for a reset.
  List<String> storageKeys() => [pluginSwitchesKey, for (final p in _plugins) ...p.manifest.storage];

  /// Every secret any plugin names, switched on or not, for a reset (lib/core/reset.dart); a name ending in `:` is
  /// the prefix of several. Not on the page (types.dart).
  List<String> secretNames() => [for (final p in _plugins) ...p.manifest.secrets];

  /// The inline formattings of every switched-on plugin (the editor's parser reads them).
  List<InlineFormat> formats() => [for (final p in enabled()) ...p.formats];

  /// A pass of the feed's rows, handed to every switched-on plugin that asks for them.
  Future<void> newRows(int before, List<FeedNotification> rows) async {
    // Each on its own: one plugin's failure is not another's.
    await Future.wait([
      for (final p in enabled())
        if (p.newRows case final told?) Future<void>.sync(() => told(before, rows)).catchError((Object _) {}),
    ]);
  }
}

/// Whether [plugin] can write an item's mark or read one back: a link, an action on a note, the swipe, a word after
/// a line, or its marks' details.
bool _linksItems(GlyphPlugin plugin) =>
    plugin.marks != null || plugin.itemAction != null || plugin.suggest != null || plugin.noteActions.isNotEmpty || plugin.noteLinks.isNotEmpty;

/// Makes a registry of [plugins] (`createRegistry`). [localOnly] is the preference, asked on every question.
Registry createRegistry(List<GlyphPlugin> plugins, {SwitchStore store = const StoredSwitches(), bool Function()? localOnly}) {
  final ids = <String>{};
  for (final plugin in plugins) {
    if (!ids.add(plugin.manifest.id)) throw ArgumentError('Two plugins are called “${plugin.manifest.id}”.');
    _checkExtensions(plugin);
    // Its id is the name its item marks carry (lib/core/item_links.dart), where it can mark an item at all: a plugin
    // that links nothing (Calendar, Contacts, Things) leaves "[calendar](…)" at the end of an item a link.
    if (_linksItems(plugin)) registerMarkName(plugin.manifest.id);
  }
  final registry = Registry._(List.unmodifiable(plugins), store, localOnly ?? () => false);
  // A switched-off plugin reads nothing back, so its marks draw plain.
  for (final plugin in plugins) {
    final marks = plugin.marks;
    if (marks != null) provideMarkDetails(plugin.manifest.id, () => registry.isEnabled(plugin.manifest.id) ? marks : null);
  }
  return registry;
}

Registry _plugins = createRegistry(const []);

/// The app's registry (`plugins`): empty until built_in.dart's `installBuiltInPlugins`, or a test's [usePlugins].
Registry get plugins => _plugins;

/// Makes [registry] the app's.
void usePlugins(Registry registry) => _plugins = registry;

/// Whether the plugin [manifest] names is on in the app's registry: for a built-in plugin's own code, which asks it
/// of itself as it is used. Before any plugin is put in place (a test that builds a screen without the app's
/// launch), whether it ships on, as [plugins] would say once it had them.
bool pluginOn(PluginManifest manifest) => _plugins.all().isEmpty ? manifest.standard : _plugins.isEnabled(manifest.id);
