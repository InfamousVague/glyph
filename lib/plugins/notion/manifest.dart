/// The Notion plugin's manifest and its host. A port of `src/app/plugins/notion/manifest.ts`.
///
/// What differs:
/// - `secrets` is new: the sign-in the page gave to Rust (`notion_save_account`, kept in `notion.json` in the app's
///   own folder) is kept here in the device's secure store, under [accountSecret]. Nothing of it is ever in
///   `storage`.
/// - `native` is kept word for word, since Settings' card reads the permission and its reason from it; none of the
///   four commands exists here (lib/plugins/types.dart), and client.dart does their work.
library;

import '../host.dart';
import '../types.dart';

/// The name the Notion sign-in is kept under in the secure store: the claim's JSON, as `notion.json` held it.
const String accountSecret = 'glyph-notion-account';

const PluginManifest manifest = PluginManifest(
  id: 'notion',
  name: 'Notion',
  description: 'Turns list items into tasks on your Notion boards: swipe an item, or send a whole list.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Turns a sent item’s words into a link to its task, in the note it came from.'),
    PluginPermission(Permission.network, 'Signs in through ghostmarkdown.com and sends tasks to Notion. Only the items you send go.'),
    PluginPermission(Permission.native, 'Keeps your Notion sign-in inside the app, where no page can read it.'),
  ],
  hosts: ['api.notion.com', 'ghostmarkdown.com'],
  native: PluginNative(generation: 12, commands: ['notion_save_account', 'notion_account', 'notion_disconnect', 'notion_request']),
  storage: ['glyph-notion-links', 'glyph-notion-signin', 'glyph-notion-tasks'],
  secrets: [accountSecret],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);
