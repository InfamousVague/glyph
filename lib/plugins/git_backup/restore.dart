/// Opening a library from its repository (docs/GIT_BACKUP.md "Restore"): "Open library from git" on a fresh device
/// (Settings › Library, and the first-run screen's "I have a backup"), and "Import from a repo folder" on the Mac
/// for a clone made by hand.
///
/// **The clone** ([GitRestore.cloneInto]): shallow first, for speed, into a folder of its own under the app's data
/// (`<app data>/git/clone-<time>/`); its organizations' folders held aside (below); the attachments at `image/`,
/// `file/` and `recordings/` copied to where the app reads them until they live in the Library; `.glyph/config.json`'s
/// `git` key read for the remote and the switches. Then the app is pointed at the folder as Settings › Library folder
/// points it at any folder (lib/core/library_folder.dart `library_inspect` + `library_move`), which rebuilds the
/// index from the files; and the history is deepened in the background when the person wants it (`git_fetch` with
/// `deepen`).
///
/// **Team notes are the server's** (the critic's high finding): `orgs/<Org>/` folders are moved out of the working
/// tree to `<app data>/git/held/<Org>/` before the folder is opened, so a fresh device never files a teammate's
/// deleted note back into the organization after sign-in; the organizations' notes arrive from the team's channel
/// once the person signs in, and the folders stay in the repository as HEAD had them (`keep`) until the switch for
/// that organization is turned on again on this device.
///
/// **Import from a repo folder** ([GitRestore.importFolder]): a folder with `.git` and notes in it, chosen on the
/// Mac; the same holding aside and config read, then the folder opened as the Library.
///
/// On an iPhone there is no folder picker, so restore is the clone into app data alone.
library;

import 'dart:io';

import '../../core/native/core.dart' show CoreInvoke;
import 'files.dart';
import 'repo.dart';
import 'settings.dart';

class RestoreOutcome {
  const RestoreOutcome({required this.folder, required this.files, required this.notes, required this.orgsHeld, required this.attachments, this.settings, this.head});

  /// The folder the library now is (or is to be opened from).
  final String folder;
  final int files;
  final int notes;

  /// The organizations whose folders were held aside.
  final List<String> orgsHeld;

  /// Attachments copied to where the app reads them.
  final int attachments;

  /// The settings read from `.glyph/config.json`, with the organizations held aside left out of the switches.
  final GitBackupSettings? settings;
  final String? head;
}

class GitRestore {
  const GitRestore({required this.invoke, required this.appData});

  final CoreInvoke invoke;

  /// The app's data folder: the clone goes under it, and the attachments are copied into it.
  final String appData;

  String get _gitRoot => '$appData/git';

  /// Where a clone goes.
  String freshCloneFolder([DateTime? now]) => '$_gitRoot/clone-${(now ?? DateTime.now()).toUtc().millisecondsSinceEpoch}';

  /// The clone (see the header). [into] is a test's own folder; the app's is fresh under its data.
  Future<RestoreOutcome> cloneInto({required String url, GitAuth auth = GitAuth.none, bool shallow = true, String? into, void Function(String line)? progress}) async {
    final folder = into ?? freshCloneFolder();
    progress?.call('Cloning');
    final cloned = await GitRepo.clone(invoke, url: url, into: folder, auth: auth, shallow: shallow);
    final outcome = await _prepare(folder, remote: url, auth: auth, progress: progress);
    return RestoreOutcome(folder: folder, files: cloned.files, notes: outcome.notes, orgsHeld: outcome.orgsHeld, attachments: outcome.attachments, settings: outcome.settings, head: cloned.head);
  }

  /// A clone made by hand (see the header): refused in a sentence where [folder] is not a repository of notes.
  Future<RestoreOutcome> importFolder(String folder) async {
    final repo = GitRepo(invoke, folder);
    if (!await repo.exists()) throw GitFailure(GitTrouble.noRepo, 'No repository: $folder has no .git folder. Clone the repository first, then choose its folder.');
    final status = await repo.status();
    final outcome = await _prepare(folder, remote: await repo.remote(), auth: GitAuth.none);
    return RestoreOutcome(folder: folder, files: 0, notes: outcome.notes, orgsHeld: outcome.orgsHeld, attachments: outcome.attachments, settings: outcome.settings, head: status.head);
  }

  Future<({int notes, List<String> orgsHeld, int attachments, GitBackupSettings? settings})> _prepare(String folder, {String? remote, required GitAuth auth, void Function(String line)? progress}) async {
    progress?.call('Setting the library aside for the team');
    final held = holdOrgsAside(folder, heldRoot: '$_gitRoot/held');
    progress?.call('Linking pictures and files');
    final attachments = AttachmentMap(repoPath: folder, appData: appData).restore();
    var settings = readGitConfig(folder) ?? const GitBackupSettings();
    settings = settings.copyWith(remote: remote ?? settings.remote, repoPath: folder, orgsIncluded: settings.orgsIncluded.difference(held.toSet()), setUpAt: DateTime.now());
    final notes = folderSize(folder, where: (relative) => relative.toLowerCase().endsWith('.md')).files;
    return (notes: notes, orgsHeld: held, attachments: attachments, settings: settings);
  }

  /// The history brought whole, after a shallow clone, when the person wants it.
  Future<void> deepen(String folder, GitAuth auth) => GitRepo(invoke, folder).fetch(auth, deepen: true);
}

/// Moves every `orgs/<Org>/` folder at [folder] to `<heldRoot>/<Org>/` (see the header); answers their names.
List<String> holdOrgsAside(String folder, {required String heldRoot}) {
  final orgs = Directory('$folder/orgs');
  if (!orgs.existsSync()) return const [];
  final held = <String>[];
  for (final entry in orgs.listSync(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final into = Directory('$heldRoot/$name');
    if (into.existsSync()) into.deleteSync(recursive: true);
    into.parent.createSync(recursive: true);
    entry.renameSync(into.path);
    held.add(name);
  }
  held.sort();
  return held;
}
