/// What the plugin core's tests share: a manifest in a line, a ground of the test's own, a note in memory, and
/// stand-ins for the five plugins that ship, made from the web app's own manifests.
library;

import 'package:flutter/widgets.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/settings_search.dart';

/// `manifest(id, extra)` of registry.test.ts: nothing asked for unless said.
PluginManifest manifestOf(
  String id, {
  String? name,
  bool standard = true,
  List<Permission> permissions = const [],
  List<String> hosts = const [],
  PluginNative? native,
  List<String> storage = const [],
  List<String> secrets = const [],
}) =>
    PluginManifest(
      id: id,
      name: name ?? id,
      description: '',
      version: '1.0.0',
      author: 'test',
      standard: standard,
      permissions: [for (final kind in permissions) PluginPermission(kind, '')],
      hosts: hosts,
      native: native,
      storage: storage,
      secrets: secrets,
    );

/// A ground of the test's own: memory for storage and secrets, the requests it was asked, the pages it opened.
class TestGround {
  TestGround({Future<FetchResponse> Function(FetchRequest request)? answer, Future<bool> Function(int wanted)? hasNativeGeneration}) {
    ground = PluginGround(
      stored: () => kept,
      secrets: secrets,
      fetch: (request) {
        asked.add(request);
        return answer?.call(request) ?? Future.value(FetchResponse.json(200, const {}));
      },
      open: (url) async => opened.add(url),
      hasNativeGeneration: hasNativeGeneration,
    );
  }

  final MemoryStored kept = MemoryStored();
  final MemorySecureStore secrets = MemorySecureStore();
  final List<FetchRequest> asked = [];
  final List<String> opened = [];
  late final PluginGround ground;
}

/// A note in memory, as the editor would give it (`noteOf` of notion/send.test.ts).
class TestNote implements NoteEditing {
  TestNote(String body, {this.noteId = 'note-1'}) : lines = body.split('\n');

  @override
  final String noteId;
  List<String> lines;
  final List<String> said = [];

  @override
  String body() => lines.join('\n');

  @override
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next) {
    for (var n = 1; n <= lines.length; n++) {
      final text = lines[n - 1];
      if (find(text, n)) {
        // As the editor has it: what a line becomes may be several lines, each counted after.
        lines = [...lines.sublist(0, n - 1), ...next(text).split('\n'), ...lines.sublist(n)];
        return true;
      }
    }
    return false;
  }

  @override
  void say(String message) => said.add(message);
}

/// A link's mark that draws nothing but its box.
Widget noIcon(BuildContext context, double size) => SizedBox.square(dimension: size);

/// A link row as a test's plugin offers one.
NoteLink linkOf(String id, String label, String? Function(String noteId) linked, {PluginIcon icon = noIcon}) =>
    NoteLink(id: id, label: label, icon: icon, hint: (_) => '', picker: (context, noteId, onDone) => const SizedBox.shrink(), linked: linked);

// ---- the five that ship, as the web app's manifests say them ---------------------------------------------------------
//
// Copied word for word from src/app/plugins/{notion,github,slack}/manifest.ts, marks/index.tsx and claude/index.tsx
// (2026-10-08), so Settings > Plugins drawn over them is the page the web draws. Marks is the port's own
// (marks_plugin.dart). The pages behind the cards are stand-ins: each plugin's own is its worker's.

const PluginManifest webNotion = PluginManifest(
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
);

const PluginManifest webGithub = PluginManifest(
  id: 'github',
  name: 'GitHub',
  description:
      'Links a note to a repo: its list items become issues you can tick off from either side, and the repo is read on the phone into a short briefing so names and terms come out right when the note is formatted.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Sends a note’s list items to the repo as issues, and writes each one’s link back into the note.'),
    PluginPermission(Permission.network, 'Reads the repo’s README, docs and file list from GitHub, and makes and closes the issues you send. Nothing else of your notes goes there.'),
    PluginPermission(Permission.ai, 'The model on your phone writes the briefing from what it read.'),
  ],
  hosts: ['api.github.com'],
  storage: ['glyph-github-projects', 'glyph-project-links', 'glyph-github-token', 'glyph-github-issues'],
);

const PluginManifest webClaude = PluginManifest(
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

const PluginManifest webSlack = PluginManifest(
  id: 'slack',
  name: 'Slack',
  description: 'Posts a note, or a meeting’s summary, to a Slack channel when you say so, and an organization’s news to its channel.',
  version: '1.0.0',
  author: 'Ghost.md',
  // Off until switched on: it sends words off the phone, and only ever when the person has set a channel up for it.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the note you post, or its summary, to make the message. Nothing in the note changes.'),
    PluginPermission(Permission.network, 'Posts to the channels you add, straight from this device. Only what you choose to post goes, and an organization’s news where you set a channel for it.'),
    PluginPermission(Permission.native, 'Keeps each channel’s webhook inside the app, where no page can read it back, and posts with it.'),
  ],
  hosts: ['hooks.slack.com'],
  native: PluginNative(generation: 25, commands: ['slack_channels', 'slack_save_channel', 'slack_forget_channel', 'slack_post']),
  storage: ['glyph-slack-channels', 'glyph-slack-news', 'glyph-slack-posted'],
);

/// A stand-in for a plugin's own page: its name, where the page will be.
PluginSettings _page(String name, String summary, String hue, List<SettingsFindable> settings) =>
    PluginSettings(pane: (context) => Text('$name’s own page', key: ValueKey('page-of-$name')), summary: () => summary, hue: hue, settings: settings);

/// The web's `BUILT_IN`, in its order, each with the icon, the summary, the hue and the findable words its
/// `index.tsx` gives it with nothing linked or kept (a fresh install, which is what the page was measured on).
List<GlyphPlugin> webBuiltIn() => [
      GlyphPlugin(
        manifest: webNotion,
        icon: 'square-kanban',
        settings: _page('Notion', 'Boards for your lists', 'graphite', const [SettingsFindable('Account', 'sign in connect oauth workspace'), SettingsFindable('Boards', 'databases lists')]),
      ),
      GlyphPlugin(
        manifest: webGithub,
        icon: 'git-branch',
        settings: _page('GitHub', 'Repos, issues and context', 'graphite', const [SettingsFindable('Repos', 'repositories briefing context'), SettingsFindable('Token', 'private issues')]),
      ),
      marksPlugin,
      GlyphPlugin(
        manifest: webClaude,
        icon: 'bot',
        settings: _page('Claude', 'Read and write your notes from Claude', 'coral', const [
          SettingsFindable('Connect', 'mcp server address hosted computer'),
          SettingsFindable('What Claude can do', 'tools'),
          SettingsFindable('Your key', 'secret connections'),
        ]),
      ),
      GlyphPlugin(
        manifest: webSlack,
        icon: 'hash',
        settings: _page('Slack', 'Channels to post to', 'graphite', const [SettingsFindable('Channels', 'webhook test message organizations news'), SettingsFindable('Add a channel', 'incoming webhook hooks.slack.com')]),
      ),
    ];
