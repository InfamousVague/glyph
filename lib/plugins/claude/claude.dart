/// The Claude plugin, standard in Ghost.md: Claude on your notes, through the MCP server (the web app's
/// docs/MCP.md). A port of `src/app/plugins/claude/index.tsx`.
///
/// Unlike the others it runs nothing inside the app - Claude reaches the account from outside, through the sync
/// service - so what the plugin is here is its page ([ClaudePane]): the address, the instructions drawer, what
/// Claude can do and where the key lives. Its switch shows or hides that page; it does not connect or disconnect
/// Claude, which is done in Claude, and the page says so. It declares `notes` and `network` because that is what
/// Claude is given once a person signs it in, and Settings' card says what a plugin may reach; nothing here asks
/// the network, and it keeps nothing (no storage, no secrets).
///
/// What differs: the handle the page read from the account's own hook (`useAccount().session?.handle`) is asked of
/// [claudeHandle], which the app's root sets once it has an account; until then the page reads as signed out.
library;

import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'claude_pane.dart';

export 'claude_guide.dart' show ClaudeGuide, cssLine, wrapCode;
export 'claude_pane.dart' show ClaudePane;
export 'steps.dart';

const PluginManifest claudeManifest = PluginManifest(
  id: 'claude',
  name: 'Claude',
  description: 'Read, add to and change your notes from Claude, through Ghost.md’s MCP server.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Claude reads and writes the notes of your account once you sign it in: from outside the phone, through the sync service, never through this app.'),
    PluginPermission(Permission.network, 'Claude talks to Ghost.md’s sync service and nothing else. This page only carries the instructions.'),
  ],
  hosts: ['ghostmarkdown.com'],
  storage: [],
);

/// The handle this device is signed in with, or null when it is not. The app's root sets it; null asks nobody.
String? Function()? claudeHandle;

/// See the header (`claudePlugin`).
final GlyphPlugin claudePlugin = GlyphPlugin(
  manifest: claudeManifest,
  icon: 'bot',
  settings: PluginSettings(
    pane: (context) => ClaudePane(handle: claudeHandle?.call()),
    summary: () => 'Read and write your notes from Claude',
    hue: 'coral',
    // What Settings' search finds on the page (docs/DESIGN.md §138): its cards, by their titles.
    settings: const [
      SettingsFindable('Connect', 'mcp server address hosted computer'),
      SettingsFindable('What Claude can do', 'tools'),
      SettingsFindable('Your key', 'secret connections'),
    ],
  ),
);
