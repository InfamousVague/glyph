/// The Things plugin, built in and off until switched on: Things 3's areas, projects and to-dos brought in as
/// notebooks and notes (lib/importer/things.dart, things_database.dart, things_paste.dart; docs/INTEGRATIONS.md,
/// "Imports"), from its own data on a Mac or from a list it copied. Matt, 2026-10-17: "Ask Claude and other
/// integrations should be shipped as plugins".
///
/// Its page holds the import ([ImportPane] with Things' card alone), and while it is on Settings › Import offers it
/// beside Obsidian and Evernote (lib/settings/settings_sections.dart asks [thingsOn]). Switched off, neither does;
/// what an import brought stays where it came. It keeps nothing, and reaches nothing past the device.
library;

import '../../settings/panes/import_pane.dart' show ImportKind, ImportPane, importFindableOf;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../registry.dart' show pluginOn;
import '../types.dart';

const PluginManifest thingsManifest = PluginManifest(
  id: 'things',
  name: 'Things',
  description: 'Brings Things 3 in: its areas as notebooks and its projects as their pages, from Things on this Mac or a list it copied.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.imports,
  tagline: 'Bring Things 3 in',
  adds: [
    'Things 3 on Settings › Import: from Things on this Mac, or a list it copied',
  ],
  // Off until switched on: an import is a thing done once, by someone moving from Things.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Makes a notebook of each area and a note of each project, in a workspace of the import’s own. Nothing you have is changed.'),
    PluginPermission(Permission.native, 'Reads a copy of Things’ own data on this Mac, when you ask, or what Things copied. Nothing leaves the device.'),
  ],
  storage: [],
);

/// Whether Things' import is offered: the plugin's switch.
bool thingsOn() => pluginOn(thingsManifest);

/// What the search finds on its page.
final List<SettingsFindable> _findable = importFindableOf(const [ImportKind.things]);

final GlyphPlugin thingsPlugin = GlyphPlugin(
  manifest: thingsManifest,
  icon: 'square-check-big',
  settings: PluginSettings(
    pane: (context) => ImportPane.hosted(context, kinds: const [ImportKind.things]),
    summary: () => 'Import from Things 3',
    hue: 'graphite',
    settings: _findable,
  ),
);
