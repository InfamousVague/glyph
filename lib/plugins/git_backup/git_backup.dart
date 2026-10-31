/// The "Back up to git" plugin (Matt, 2026-10-31: "add a plugin to backup on git"): the Library folder committed and
/// pushed to a repository the person owns, two minutes after the last change and once an hour at least, and opened
/// again on a fresh device by cloning it. docs/GIT_BACKUP.md says how it works; the design and the decisions it
/// follows are docs/MARKDOWN_FIRST.md §10 and §11.
///
/// Where it shows, once added in the Market (off until then):
/// - Its page in Settings (git_backup_pane.dart): the repository, the switches, Back up now, Open library from git,
///   Remove; and its setup at the head (git_backup_setup.dart), which the Market opens as it is added.
/// - "Back up now" in the command palette (lib/commands/palette.dart), and "Open library from git" on Settings ›
///   Library folder.
/// - A job on the activity record for each backup, with the plugin's git glyph: no brand's mark, since any host does.
///
/// The parts: repo.dart (the core's git from Dart), place.dart (where the repository is), files.dart (what goes in
/// beside the notes), messages.dart (the commit messages), claim.dart (one pusher), merge.dart (the remote's changes
/// put together with ours), backup.dart (the cadence, the commit and the push), restore.dart (a clone opened as the
/// library), github_api.dart (a token's scopes, a repository made), service.dart (the running parts the root makes).
library;

import '../types.dart';
import 'git_backup_pane.dart';
import 'git_backup_setup.dart';
import 'manifest.dart';
import 'settings.dart';

export 'backup.dart';
export 'claim.dart';
export 'files.dart';
export 'github_api.dart';
export 'git_backup_pane.dart';
export 'git_backup_setup.dart';
export 'manifest.dart' show stateKey, tokenSecret;
export 'merge.dart';
export 'messages.dart';
export 'place.dart';
export 'publish.dart';
export 'repo.dart';
export 'restore.dart';
export 'service.dart';
export 'settings.dart';

String _summary() {
  final settings = gitBackupSettings();
  if (!settings.configured) return 'Not set up';
  final where = remoteShort(settings.remote!);
  final failed = settings.lastFailure != null;
  if (failed) return '$where · last backup failed';
  return settings.lastPushAt == null ? '$where · not pushed yet' : '$where · pushed';
}

final GlyphPlugin gitBackupPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'git-branch',
  setup: gitBackupSetup,
  settings: PluginSettings(
    pane: (context) => const GitBackupPane(),
    hue: 'green',
    settings: gitBackupFindable,
    summary: _summary,
  ),
);
