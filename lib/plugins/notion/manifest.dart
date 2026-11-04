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
  category: PluginCategory.connections,
  tagline: 'List items as tasks on your Notion boards',
  adds: [
    'A Notion board to link a note to, on its settings',
    'Swipe a list item left, or tap the quiet “Notion” after it, to send it as a task',
    'Send list to Notion, once the note is linked',
    'Import from Notion on its page: every page and database you share, as folders of notes, and again for what changed',
  ],
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Turns a sent item’s words into a link to its task, in the note it came from, and writes the notes an import brings.'),
    PluginPermission(Permission.network, 'Signs in through ghostmarkdown.com, sends tasks to Notion, and reads the pages you share for an import, with their pictures and files. Only the items you send go.'),
    PluginPermission(Permission.native, 'Keeps your Notion sign-in inside the app, where no page can read it.'),
  ],
  // The last three for an import's files (Matt, 2026-11-04, a whole Notion brought in): Notion's own storage, which
  // its signed links name, its built-in covers, and Unsplash's, which its cover picker offers.
  hosts: ['api.notion.com', 'ghostmarkdown.com', 'notion.so', 's3.us-west-2.amazonaws.com', 'images.unsplash.com'],
  native: PluginNative(generation: 12, commands: ['notion_save_account', 'notion_account', 'notion_disconnect', 'notion_request']),
  storage: ['glyph-notion-links', 'glyph-notion-signin', 'glyph-notion-tasks', 'glyph-notion-import'],
  secrets: [accountSecret],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);
