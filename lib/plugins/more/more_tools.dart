/// More tools as plugins, and the one question every feature of theirs asks: is it on (docs/PM_PLUGINS.md §10; Matt,
/// 2026-11-01, after the project tools became plugins: "think about other things that can be plugins that might be
/// overwhelming for a new user as well"). Canvas, Meetings, Diagrams and math, Places, Email to a note and Publishing:
/// each off for a new person, and switched on once where it was already in use ([adoptMoreTools]).
///
/// **Where a switch is.** The person's alone: the plugin registry's (registry.dart, `glyph-plugins`), synced between
/// their devices (lib/sync/connections.dart `syncedSwitches`). No organization lists them, as one does the project
/// tools, so a note's space does not matter: [moreToolOn] is the whole question.
///
/// **What needs what.** Google Meet and Zoom stand on Meetings ([moreToolNeeds]): with Meetings off they do nothing,
/// and adding either in the Market adds Meetings.
///
/// **Once, where in use.** The registry's `adopt` turns a plugin on that ships off where its feature was in use before
/// it was a plugin, unless its switch was ever moved. Here each check is made once on a device, the first time the
/// library is read with this build (or, for the account's parts, the first time the service answers), and remembered
/// under [moreToolsAdoptedKey]; so a person who starts with none of them and writes a ```dart block next week is not
/// handed Diagrams and math for it, and finds the chip.
///
/// The features are the app's own, not the plugins': the registry's extension points have no fence, row or shelf, so
/// each feature asks here where it is drawn, as the project tools' do (lib/plugins/projects/suite.dart).
library;

import 'package:flutter/foundation.dart';

import '../../core/more_tools.dart';
import '../../core/stored.dart';
import '../canvas/canvas.dart' show canvasPlugin;
import '../diagrams/diagrams.dart' show diagramsPlugin;
import '../email/email.dart' show emailPlugin;
import '../meetings/meetings.dart' show meetingsPlugin;
import '../places/places_tool.dart' show placesToolPlugin;
import '../publishing/publishing.dart' show publishingPlugin;
import '../registry.dart' show Registry, plugins;
import '../types.dart';

export '../../core/more_tools.dart';

/// The six's plugins, in the Market's order (more_tools.dart [moreTools]).
final List<GlyphPlugin> morePlugins = [canvasPlugin, meetingsPlugin, diagramsPlugin, placesToolPlugin, emailPlugin, publishingPlugin];

/// One of the six's plugin by its id; null for an id that is none of theirs.
GlyphPlugin? moreToolPlugin(String id) {
  for (final plugin in morePlugins) {
    if (plugin.manifest.id == id) return plugin;
  }
  return null;
}

/// A tool's name as a chip says it: "Diagrams and math" is "Diagrams".
String moreToolShortName(String id) => switch (id) {
      diagramsTool => 'Diagrams',
      emailTool => 'Email to a note',
      _ => moreToolPlugin(id)?.manifest.name ?? id,
    };

/// The plugins that stand on one of the six: plugin id to the tool it needs.
const Map<String, String> moreToolNeeds = {'google-meet': meetingsTool, 'zoom': meetingsTool};

/// [id] with what it stands on, in the order to switch them on: Meetings before Google Meet.
List<String> withMoreNeeds(String id) => [?moreToolNeeds[id], id];

/// The plugins on that stand on [tool]: what removing it in the Market names.
List<String> moreDependentsOf(String tool, Registry registry) => [
      for (final MapEntry(:key, :value) in moreToolNeeds.entries)
        if (value == tool && registry.byId(key) != null && registry.switchedOn(key)) key,
    ];

/// The switches as every test that tests a feature finds it: each of the six on (test/flutter_test_config.dart sets it
/// for every test; a test of the off state sets it back to false).
abstract final class MoreTools {
  static bool debugAllOn = false;
}

/// Whether [id], one of the six, is on in [registry] (the app's where unsaid): its switch, Local only holding off the
/// ones that reach the service. Before any plugin is put in place (a screen built without the app's launch), off.
bool moreToolOn(String id, [Registry? registry]) {
  if (MoreTools.debugAllOn) return true;
  final reg = registry ?? plugins;
  return reg.byId(id) != null && reg.isEnabled(id);
}

/// Whether a plugin that stands on one of the six ([moreToolNeeds]) has what it needs; true for any other.
bool moreNeedsMet(String id, [Registry? registry]) {
  final need = moreToolNeeds[id];
  return need == null || moreToolOn(need, registry);
}

/// What moves as the six are switched: the app's registry, as it is when asked.
Listenable get moreToolsChanges => plugins;

// ---- adopting ------------------------------------------------------------------------------------------------------

/// Where a device keeps which of the checks it has made: their names, a list.
const String moreToolsAdoptedKey = 'glyph-more-tools-adopted';

/// The account's halves of the checks, made when the service first answers: an Email to a note address, a site.
const String emailAddressCheck = 'email:address';
const String publishedSitesCheck = 'publishing:sites';

Set<String> _made(Stored kept) => kept.read<Set<String>>(moreToolsAdoptedKey, const {}, (raw) => raw is List ? {for (final name in raw) if (name is String) name} : const {});

/// Whether the check [name] has been made on this device.
bool moreToolChecked(String name, {Stored? store}) => _made(store ?? stored).contains(name);

/// Makes each check of [inUse] not made on this device yet: the check's name to its tool and whether it is in use.
/// A tool in use is switched on where its switch was never moved ([Registry.adopt]); either way the check is made
/// and never asked again. Answers the tools switched on. Nothing while every test's switches are on.
List<String> adoptMoreTools(Registry registry, Map<String, (String, bool Function())> inUse, {Stored? store}) {
  if (MoreTools.debugAllOn) return const [];
  final kept = store ?? stored;
  final made = {..._made(kept)};
  final on = <String>[];
  var wrote = false;
  for (final MapEntry(key: name, value: (tool, used)) in inUse.entries) {
    if (made.contains(name)) continue;
    final had = registry.hasSwitch(tool);
    final now = registry.byId(tool) != null && used();
    registry.adopt(tool, inUse: now);
    if (now && !had && registry.hasSwitch(tool)) on.add(tool);
    made.add(name);
    wrote = true;
  }
  if (wrote) kept.write(moreToolsAdoptedKey, (made.toList()..sort()));
  if (on.isNotEmpty) debugPrint('[glyph] switched on, as they were in use before they were plugins: ${on.join(', ')}');
  return on;
}
