/// The Todoist plugin, built in and off until switched on: Todoist's projects brought in as notes (lib/importer/
/// todoist.dart, todoist_csv.dart; docs/INTEGRATIONS.md, "Imports"), by an API token pasted for the one import or a
/// project's CSV export. Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins".
///
/// Its page holds the import ([ImportPane] with Todoist's card alone), and while it is on Settings › Import offers
/// it beside Obsidian and Evernote (lib/settings/settings_sections.dart asks [todoistOn]). Switched off, neither
/// does; what an import brought stays where it came, a workspace like any other. It keeps nothing: the token is used
/// for the one import and let go.
library;

import '../../settings/panes/import_pane.dart' show ImportKind, ImportPane, importFindableOf;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../registry.dart' show pluginOn;
import '../types.dart';

const PluginManifest todoistManifest = PluginManifest(
  id: 'todoist',
  name: 'Todoist',
  description: 'Brings your Todoist projects in as notes, their sections headings and their tasks to-dos, from your account or a project’s CSV export.',
  version: '1.0.0',
  author: 'Ghost.md',
  // Off until switched on: an import is a thing done once, by someone moving from Todoist.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Makes a note of each project, in a workspace of the import’s own. Nothing you have is changed.'),
    PluginPermission(Permission.network, 'Reads your Todoist account with the token you paste, for that one import; the token is not kept. An export is read on this device.'),
  ],
  hosts: ['api.todoist.com'],
  storage: [],
);

/// Whether Todoist's import is offered: the plugin's switch.
bool todoistOn() => pluginOn(todoistManifest);

/// What the search finds on its page.
final List<SettingsFindable> _findable = importFindableOf(const [ImportKind.todoist]);

final GlyphPlugin todoistPlugin = GlyphPlugin(
  manifest: todoistManifest,
  icon: 'list-checks',
  settings: PluginSettings(
    pane: (context) => ImportPane.hosted(context, kinds: const [ImportKind.todoist]),
    summary: () => 'Import from Todoist',
    hue: 'graphite',
    settings: _findable,
  ),
);
