/// What a plugin may reach, as Settings says it (lib/settings/panes/plugins_pane.dart), and the one question about
/// it the registry asks: whether it reaches past the phone, which Local only holds off. A port of
/// `src/app/plugins/reach.ts`, word for word.
library;

import 'types.dart';

/// Each permission, in the words Settings uses for it (`PERMISSION_WORDS`).
const Map<Permission, String> permissionWords = {
  Permission.notes: 'Your notes',
  Permission.network: 'The internet',
  Permission.ai: 'The model on your phone',
  Permission.voice: 'Voice commands',
  Permission.native: 'Built-in app commands',
};

/// Whether a plugin reaches outside the phone, and so is held off while Local only is on.
bool usesNetwork(PluginManifest manifest) => manifest.declares(Permission.network);

/// What a plugin may reach, in one line: "Your notes · The internet (api.notion.com) · Built-in app commands".
String reachLine(PluginManifest manifest) => manifest.permissions
    .map((p) => p.kind == Permission.network && manifest.hosts.isNotEmpty ? '${permissionWords[Permission.network]} (${manifest.hosts.join(', ')})' : permissionWords[p.kind]!)
    .join(' · ');
