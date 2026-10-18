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

/// Each permission in the catalogue's plain words (lib/settings/panes/plugins_pane.dart): the rows of a plugin's
/// detail page, where [permissionWords] are the web's card's. "Built-in app commands" was the page's way of saying
/// that something is kept or read inside the app on this device (a sign-in, the contacts, where the phone is), and
/// that is the phone. The port's own.
const Map<Permission, String> plainPermissionWords = {
  Permission.notes: 'Your notes',
  Permission.network: 'The internet',
  Permission.ai: 'The model on your phone',
  Permission.voice: 'Voice commands',
  Permission.native: 'Your phone',
};

/// What a plugin uses, as its card in the catalogue says it: "Uses your notes, the internet and your phone", or
/// "Uses nothing past the note you are in" for one that asks for nothing (Marks).
String usesLine(PluginManifest manifest) {
  final kinds = <Permission>{for (final p in manifest.permissions) p.kind};
  if (kinds.isEmpty) return 'Uses nothing past the note you are in';
  return 'Uses ${joinAnd([for (final kind in kinds) _lowered(plainPermissionWords[kind]!)])}';
}

String _lowered(String words) => words[0].toLowerCase() + words.substring(1);

/// "a", "a and b", "a, b and c".
String joinAnd(List<String> words) => switch (words.length) {
      0 => '',
      1 => words.single,
      _ => '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}',
    };
