/// The Claude plugin, standard in Ghost.md: Claude on your notes, both ways. A port of
/// `src/app/plugins/claude/index.tsx`, and the app's own Claude besides (Matt, 2026-10-17: "Ask Claude and other
/// integrations should be shipped as plugins").
///
/// - **In the app** (docs/CLAUDE_APP.md): Claude asked from here with the person's own Anthropic API key, from the
///   dock at the head of every page, the command bar and an AI's Chat; the chat; Claude typing into the note it
///   writes in; and the "Ask Claude" note done as requests are written. Its code is lib/claude/; what the plugin
///   holds of it is its cards on the page ([ClaudeInApp]) and the one question the app asks, [claudeInApp]. Off, no
///   dock has Claude, the chat does not open, the command bar has no Ask Claude and the inbox asks nothing.
/// - **From Claude's own app** (the web app's docs/MCP.md): the MCP server's address, the instructions drawer, what
///   Claude can do and where the key lives ([ClaudePane]). That half runs nothing inside the app: Claude reaches the
///   account from outside, through the sync service, and switching the plugin off does not disconnect it, which is
///   done in Claude, as the page says.
///
/// It declares `notes` and `network` because that is what each half reaches: the app's Claude reads and writes the
/// notes here and talks to `api.anthropic.com`, and the connector is given the account's notes through
/// `ghostmarkdown.com` once a person signs it in. The key and its choices are kept by lib/claude/claude_settings.dart
/// in the device's secure store; the plugin keeps nothing of its own.
///
/// What differs: the handle the page read from the account's own hook (`useAccount().session?.handle`) is asked of
/// [claudeHandle], which the app's root sets once it has an account; until then the page reads as signed out. The
/// web's plugin is the connector's page alone; its manifest is still the card the web measured
/// (test/plugins/support.dart `webClaude`), and this one says the app's half too.
library;

import '../../settings/settings_search.dart' show SettingsFindable;
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'claude_in_app.dart';
import 'claude_pane.dart';

export 'claude_guide.dart' show ClaudeGuide, cssLine, wrapCode;
export 'claude_in_app.dart' show ClaudeInApp, PhoneAssistantSeam, claudeInAppFindable, claudeSummary;
export 'claude_pane.dart' show ClaudePane, ClaudePartHeading;
export 'steps.dart';

const PluginManifest claudeManifest = PluginManifest(
  id: 'claude',
  name: 'Claude',
  description: 'Ask Claude in the app with your own API key, and read, add to and change your notes from Claude, through Ghost.md’s MCP server.',
  version: '1.1.0',
  author: 'Ghost.md',
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Asked here, Claude reads, makes and changes your notes on this device as you watch. From Claude’s own app it reads and writes them through the sync service once you sign it in.'),
    PluginPermission(Permission.network, 'What you ask here, and the notes Claude reads to answer, go to Anthropic with your key. Claude’s own app talks to Ghost.md’s sync service and nothing else.'),
  ],
  hosts: ['api.anthropic.com', 'ghostmarkdown.com'],
  storage: [],
);

/// Whether the app's own Claude is on: the dock's Claude, the chat, Ask Claude in the command bar, the inbox
/// (docs/CLAUDE_APP.md). Asked as each is drawn or run.
bool claudeInApp() => pluginOn(claudeManifest);

/// The handle this device is signed in with, or null when it is not. The app's root sets it; null asks nobody.
String? Function()? claudeHandle;

/// See the header (`claudePlugin`).
final GlyphPlugin claudePlugin = GlyphPlugin(
  manifest: claudeManifest,
  icon: 'bot',
  settings: PluginSettings(
    pane: (context) => ClaudePane(handle: claudeHandle?.call(), inApp: const ClaudeInApp()),
    summary: claudeSummary,
    hue: 'coral',
    // What Settings' search finds on the page (docs/DESIGN.md §138): its cards, by their titles, the app's first.
    settings: const [
      ...claudeInAppFindable,
      SettingsFindable('Connect', 'mcp server address hosted computer'),
      SettingsFindable('What Claude can do', 'tools'),
      SettingsFindable('Your key', 'secret connections'),
    ],
  ),
);
