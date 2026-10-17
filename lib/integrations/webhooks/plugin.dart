/// Webhooks, as a plugin (docs/INTEGRATIONS.md, §1; Matt, 2026-10-17: "Ask Claude and other integrations should be
/// shipped as plugins"): one of the plugins that ship with Ghost.md (lib/plugins/built_in.dart `builtIn`), off until
/// switched on in Settings › Plugins. Its page there is the outgoing and incoming hooks (webhooks_pane.dart).
///
/// While it is off, nothing of it runs: the outgoing hooks hear no save ([webhooksOn], asked by outgoing.dart's
/// sender on every save and before every send) and the sync pass does not read the incoming hooks' inbox
/// ([hooksWhileOn], the engine's `hooksIn`). Local only holds it off too, as it does every plugin that reaches past
/// the phone (lib/plugins/registry.dart `isEnabled`). The hooks themselves stay with the account's settings, so
/// switching it on again finds them.
///
/// The outgoing hooks go to whatever URL the person adds, so they are not asked through the plugin's host, which
/// reaches only the hosts a manifest lists; the manifest says so in its reason.
library;

import '../../core/preferences.dart';
import '../../plugins/registry.dart' show plugins;
import '../../plugins/types.dart';
import '../../settings/settings_search.dart' show SettingsFindable;
import 'incoming.dart' show HookPassContext, syncHooks;
import 'setup.dart' show webhooksId;
import 'webhooks_pane.dart';

const PluginManifest webhooksManifest = PluginManifest(
  id: webhooksId,
  name: 'Webhooks',
  description: 'Tells a URL of yours when a note changes, and gives you URLs that add to a note: for Zapier, Make, IFTTT or a line of curl.',
  version: '1.0.0',
  author: 'Ghost.md',
  // Off until switched on: it sends notes off the phone, to URLs the person adds.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads a note you change on this device to tell your URLs of it, and adds what is posted to your incoming hooks to the note it names.'),
    PluginPermission(Permission.network, 'Posts to the URLs you add, straight from this device, and collects what your incoming hooks took in from ghostmarkdown.com, sealed to your account.'),
  ],
  hosts: ['ghostmarkdown.com'],
  storage: ['glyph-webhooks-status', 'glyph-hooks-applied'],
);

/// Whether the plugin is on now: switched on, and Local only off.
bool webhooksOn() => plugins.isEnabled(webhooksId);

/// The sync pass's step for the incoming hooks, which reads nothing while the plugin is off.
Future<int> hooksWhileOn(HookPassContext ctx) => webhooksOn() ? syncHooks(ctx) : Future<int>.value(0);

final GlyphPlugin webhooksPlugin = GlyphPlugin(
  manifest: webhooksManifest,
  icon: 'link',
  settings: PluginSettings(
    pane: WebhooksPane.hosted,
    hue: 'graphite',
    summary: () => webhooksSummary(preferences.value),
    settings: <SettingsFindable>[...webhooksFindable()],
  ),
);
