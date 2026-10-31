/// The "Back up to git" plugin's manifest and its host (Matt, 2026-10-31: "add a plugin to backup on git"). The app's
/// own: neither the web app nor the Tauri one had it. docs/GIT_BACKUP.md says how it works; docs/MARKDOWN_FIRST.md
/// §10 and §11 are the design and the decisions it follows.
///
/// The one secret is the token the git host takes as a password ([tokenSecret]), kept in the device's secure store
/// and sealed to the account's other devices as GitHub's is (lib/sync/connections.dart). The storage key holds the
/// plugin's settings and what it last saw of the repository ([stateKey]: settings.dart), never a secret.
///
/// `hosts` names api.github.com alone: the plugin asks GitHub's API what a token may do and to make a repository.
/// The git traffic itself (fetch, push, clone) goes through the core's own HTTPS (native/src/git.rs) to whichever
/// host the remote names, which is why the network permission's reason says so in words.
library;

import '../host.dart';
import '../types.dart';

/// The name the git token is kept under in the secure store.
const String tokenSecret = 'glyph-git-token';

/// The storage key the plugin's settings and last-seen state are kept under (settings.dart).
const String stateKey = 'glyph-git-backup';

const PluginManifest manifest = PluginManifest(
  id: 'git-backup',
  name: 'Back up to git',
  description:
      'Commits your Library folder to a git repository you own and pushes it after each quiet spell, so your notes are backed up as plain files with their history, on GitHub, GitLab, Codeberg or any git host. A fresh device opens the library again by cloning it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Your notes, pushed to a repo you own',
  adds: [
    'A commit two minutes after your last change, and a push when you are online',
    'Back up now, on the page and in the command palette',
    'Open library from git, on a fresh device',
    'Switches for recordings and each organization, off until you say',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads every note and file of your Library to commit them, and writes the notes a merge brings back from the repository.'),
    PluginPermission(Permission.network, 'Pushes to and fetches from the git host you add, and nothing else; asks GitHub’s API what your token may do and, if you ask, to make the repository.'),
  ],
  hosts: ['api.github.com'],
  storage: [stateKey],
  secrets: [tokenSecret],
);

/// The plugin's one way onto the phone. It reads the ground when it is used (lib/plugins/host.dart), so a test that
/// puts its own ground in place needs no host of its own.
final PluginHost host = createHost(manifest);
