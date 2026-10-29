/// The GitHub plugin's manifest and its host. A port of `src/app/plugins/github/manifest.ts`.
///
/// What differs:
/// - `secrets` is new: the token the page kept in localStorage under `glyph-github-token` is kept here in the
///   device's secure store, under [tokenSecret]. The storage key of the same name stays in `storage` so a reset
///   clears a value an older build left there; nothing writes it.
library;

import '../host.dart';
import '../types.dart';

/// The name the token is kept under in the secure store.
const String tokenSecret = 'glyph-github-token';

const PluginManifest manifest = PluginManifest(
  id: 'github',
  name: 'GitHub',
  description:
      'Links a note to a repo: its list items become issues you can tick off from either side, and the repo is read on the phone into a short briefing so names and terms come out right when the note is formatted.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Notes linked to repos, their items issues',
  adds: [
    'A GitHub repo to link a note to, on its settings',
    'Swipe a list item left, or tap the quiet “GitHub” after it, to make it an issue',
    'Send list to GitHub, once the note is linked',
    'A briefing of the repo for the model as the note is formatted',
  ],
  standard: true,
  permissions: [
    PluginPermission(Permission.notes, 'Sends a note’s list items to the repo as issues, and writes each one’s link back into the note.'),
    PluginPermission(Permission.network, 'Reads the repo’s README, docs and file list from GitHub, and makes and closes the issues you send. Nothing else of your notes goes there.'),
    PluginPermission(Permission.ai, 'The model on your phone writes the briefing from what it read.'),
  ],
  hosts: ['api.github.com'],
  storage: ['glyph-github-projects', 'glyph-project-links', 'glyph-github-token', 'glyph-github-issues'],
  secrets: [tokenSecret],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);

/// What GitHub or the plugin refuses, in a sentence a person can act on (the page threw an `Error` with it).
class GithubFailure implements Exception {
  const GithubFailure(this.message, {this.status});
  final String message;

  /// GitHub's status, where it refused: 401 for a token it does not know.
  final int? status;

  @override
  String toString() => message;
}
