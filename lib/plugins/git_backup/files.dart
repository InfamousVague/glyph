/// What the plugin writes into the repository beside the notes, and what it maps in from the app's data: the
/// generated `.gitignore` and `README.txt`, the attachments (pictures, files, recordings) brought to the names the
/// notes link them by, and the sizes the setup shows before the first commit.
///
/// **The README is `README.txt`, never `README.md`**: a `.md` at the Library's root would be indexed as a note and
/// synced to the account (the critic's finding, docs/MARKDOWN_FIRST.md §12); export_commands.rs writes `README.txt`
/// for the same reason. `.git/` and `.trash/` are never notes: the vault's walk skips every dot folder
/// (tauri/src-tauri/src/library/vault.rs `markdown()`), which test/plugins/git_backup/files_test.dart confirms.
///
/// **Attachments.** Until the attachments slice lands on main (pictures and files under the Library at `image/` and
/// `file/`), they live at `<app data>/images/` and `<app data>/images/files/`, and recordings at `<app data>/recordings/`.
/// [AttachmentMap] copies each into the repository at the name the notes link ([attachmentFolders]), only what changed
/// by size or time, and takes out of the repository what the app no longer has. When a source folder IS the
/// repository's folder (the slice has landed and the Library holds `image/` itself) the copy is a no-op, so the swap
/// to the real folders is a change of paths, not of code.
library;

import 'dart:io';

import 'settings.dart';

/// The folders an attachment kind is committed under, and where the app keeps it until it lives in the Library.
const List<({String repoName, String appFolder})> attachmentFolders = [
  (repoName: 'image', appFolder: 'images'),
  (repoName: 'file', appFolder: 'images/files'),
  (repoName: 'recordings', appFolder: 'recordings'),
];

/// The `.gitignore` the plugin writes: the index and its journals, backup scratch, temp files, the Mac's clutter,
/// films always; recordings while the switch is off; each organization not included. `.glyph/notes/` is KEPT (the
/// recordings' lengths and phrases, until they move into the notes).
String gitignoreText(GitBackupSettings settings, {required Iterable<String> orgs}) {
  final lines = <String>[
    '# Ghost.md: rebuilt from the files',
    '.glyph/index.sqlite',
    '.glyph/index.sqlite-wal',
    '.glyph/index.sqlite-shm',
    '.glyph/index.sqlite-journal',
    '.ghostmd-backup.json',
    '*.ghostmd.tmp',
    '**/.*.part',
    '**/*.tmp',
    '.orphans.json',
    '.DS_Store',
    '# never backed up',
    'video/',
  ];
  if (!settings.recordings) lines.add('recordings/');
  final excluded = [for (final org in orgs) if (!settings.orgsIncluded.contains(org)) org]..sort();
  if (excluded.isNotEmpty) {
    lines.add('# organizations not included (each has a switch on the plugin’s page)');
    for (final org in excluded) {
      lines.add('orgs/${_escaped(org)}/');
    }
  }
  return '${lines.join('\n')}\n';
}

/// A folder name as a `.gitignore` line takes it: the characters it reads as a pattern escaped.
String _escaped(String name) => name.replaceAllMapped(RegExp(r'[\[\]*?#!\\ ]'), (m) => '\\${m[0]}');

/// The `README.txt` at the repository's root: what the repository is, and how to open it again.
String readmeText({required String madeBy}) => '''
This is a Ghost.md library, backed up to git by the Back up to git plugin.

Every note is a Markdown file, in a folder for its workspace (Inbox/, workspaces/<Name>/, orgs/<Organization>/).
Beside each note a .versions file holds its history as plain text, image/ and file/ hold the pictures and files
the notes link, and .glyph/ holds the library's own records (its config, and a small JSON a recording). Nothing in
this repository is encrypted: anyone who can read the repository can read the notes. Keep it private.

To open it again in Ghost.md: Settings > Library > Open library from git, or "I have a backup" on a fresh device,
and paste this repository's address and a token that may read it. On a Mac you can also clone it by hand and
choose the folder in Settings > Library folder (Import from a repo folder).

Any other Markdown app opens the folder as it is. Ghost.md's own marks are plain text that reads fine elsewhere.

Made by $madeBy with Ghost.md (https://ghostmarkdown.com).
''';

/// The GitHub Pages workflow the Publish switch commits, where the publisher's template is not yet in the tree
/// (publish/templates/github-pages.yml): it builds nothing yet, and says so. TODO(docs/GIT_BACKUP.md): swap for the
/// publisher's template when it lands.
const String placeholderPagesWorkflow = '''
# Ghost.md: publishes this library as a website with GitHub Pages. Written by the Back up to git plugin.
# This is a placeholder until Ghost.md's publisher ships its template; it only checks the repository out.
name: ghost-pages
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Ghost.md's publisher is not in this build yet; the site is built once it is."
''';

/// The path the workflow is committed at.
const String pagesWorkflowPath = '.github/workflows/ghost-pages.yml';

/// What a folder weighs: every file's bytes, and how many there are.
class FolderSize {
  const FolderSize(this.bytes, this.files);
  final int bytes;
  final int files;

  static const FolderSize none = FolderSize(0, 0);

  FolderSize operator +(FolderSize other) => FolderSize(bytes + other.bytes, files + other.files);
}

/// The bytes and files under [dir], dot folders skipped when [skipDot] (so `.git` is not counted among the notes),
/// and nothing where it is not there.
FolderSize folderSize(String dir, {bool skipDot = true, bool Function(String relative)? where}) {
  final root = Directory(dir);
  if (!root.existsSync()) return FolderSize.none;
  var bytes = 0;
  var files = 0;
  void walk(Directory at) {
    for (final entry in at.listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (skipDot && name.startsWith('.')) continue;
      final relative = entry.path.substring(dir.length).replaceFirst(RegExp(r'^[\\/]+'), '');
      if (entry is Directory) {
        walk(entry);
      } else if (entry is File) {
        if (where != null && !where(relative)) continue;
        bytes += entry.lengthSync();
        files += 1;
      }
    }
  }

  walk(root);
  return FolderSize(bytes, files);
}

/// The sizes the setup and the page show: what a commit takes, and what is left out by the switches.
class RepoSizes {
  const RepoSizes({required this.committed, required this.recordings, required this.orgsExcluded, required this.video, required this.git});

  /// Notes, versions, pictures, files, and whatever the switches include.
  final FolderSize committed;

  /// Recordings, whether or not the switch includes them (the switch's row says what it would add).
  final FolderSize recordings;

  /// The organizations' notes not included.
  final FolderSize orgsExcluded;

  /// Films, never committed.
  final FolderSize video;

  /// The `.git` folder itself.
  final FolderSize git;
}

/// [sizes] of the repository at [repoPath], with the attachments still at [appData] counted where they are.
RepoSizes repoSizes({required String repoPath, String? appData, required GitBackupSettings settings, required Iterable<String> orgs}) {
  final excludedOrgs = {for (final org in orgs) if (!settings.orgsIncluded.contains(org)) org};
  bool committed(String relative) {
    final parts = relative.split(RegExp(r'[\\/]+'));
    if (parts.first == 'video') return false;
    if (parts.first == 'recordings') return settings.recordings;
    if (parts.first == 'orgs' && parts.length > 1 && excludedOrgs.contains(parts[1])) return false;
    return true;
  }

  var size = folderSize(repoPath, where: committed);
  var recordings = folderSize('$repoPath/recordings');
  var video = folderSize('$repoPath/video');
  if (appData != null && appData != repoPath) {
    for (final folder in attachmentFolders) {
      final source = '$appData/${folder.appFolder}';
      if ('$repoPath/${folder.repoName}' == source) continue;
      final here = folderSize(source, where: (relative) => folder.repoName != 'image' || !relative.startsWith('files/'));
      if (folder.repoName == 'recordings') {
        recordings = recordings + here;
        if (settings.recordings) size = size + here;
      } else {
        size = size + here;
      }
    }
    video = video + folderSize('$appData/video');
  }
  var orgsExcluded = FolderSize.none;
  for (final org in excludedOrgs) {
    orgsExcluded = orgsExcluded + folderSize('$repoPath/orgs/$org');
  }
  return RepoSizes(committed: size, recordings: recordings, orgsExcluded: orgsExcluded, video: video, git: folderSize('$repoPath/.git', skipDot: false));
}

/// A size in words: "1.2 MB", "840 kB", "12 B".
String sizeWords(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(bytes < 10000 ? 1 : 0)} kB';
  if (bytes < 1000 * 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(bytes < 10 * 1000 * 1000 ? 1 : 0)} MB';
  return '${(bytes / 1e9).toStringAsFixed(1)} GB';
}

/// The organizations' folders under `orgs/` at [repoPath], by name.
List<String> orgFoldersAt(String repoPath) {
  final dir = Directory('$repoPath/orgs');
  if (!dir.existsSync()) return const [];
  return [for (final entry in dir.listSync(followLinks: false)) if (entry is Directory) entry.uri.pathSegments.where((s) => s.isNotEmpty).last]..sort();
}

/// The attachments brought into the repository at the names the notes link (see the header). [appData] is the
/// app's data folder; where the attachments already live in the repository nothing is copied.
class AttachmentMap {
  const AttachmentMap({required this.repoPath, required this.appData});
  final String repoPath;
  final String? appData;

  /// Copies what changed and removes what is gone; answers the paths of files refused for size, so the commit can
  /// name them. Recordings are copied only when [settings] includes them and each is under the cap.
  List<String> bring(GitBackupSettings settings) {
    final appData = this.appData;
    if (appData == null) return const [];
    final refused = <String>[];
    for (final folder in attachmentFolders) {
      final source = Directory('$appData/${folder.appFolder}');
      final target = Directory('$repoPath/${folder.repoName}');
      if (source.path == target.path) continue;
      if (folder.repoName == 'recordings' && !settings.recordings) continue;
      final wanted = <String>{};
      if (source.existsSync()) {
        for (final entry in source.listSync(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.')) continue;
          final length = entry.lengthSync();
          if (folder.repoName == 'recordings' && length > settings.recordingsMaxBytes) {
            refused.add('${folder.repoName}/$name');
            continue;
          }
          wanted.add(name);
          final to = File('${target.path}/$name');
          if (to.existsSync() && to.lengthSync() == length && !to.lastModifiedSync().isBefore(entry.lastModifiedSync())) continue;
          target.createSync(recursive: true);
          entry.copySync(to.path);
        }
      }
      if (target.existsSync()) {
        for (final entry in target.listSync(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (!wanted.contains(name)) entry.deleteSync();
        }
      }
    }
    return refused;
  }

  /// The other way, after a clone: what the repository holds at `image/`, `file/` and `recordings/` copied to where
  /// the app reads them, so the notes' pictures show. Nothing where they are one folder.
  int restore() {
    final appData = this.appData;
    if (appData == null) return 0;
    var copied = 0;
    for (final folder in attachmentFolders) {
      final source = Directory('$repoPath/${folder.repoName}');
      final target = Directory('$appData/${folder.appFolder}');
      if (source.path == target.path || !source.existsSync()) continue;
      for (final entry in source.listSync(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final to = File('${target.path}/$name');
        if (to.existsSync() && to.lengthSync() == entry.lengthSync()) continue;
        target.createSync(recursive: true);
        entry.copySync(to.path);
        copied += 1;
      }
    }
    return copied;
  }
}
