/// What the plugin writes into the repository beside the notes, and what it maps in from the app's data: the
/// generated `.gitignore` and `README.txt`, the attachments (pictures, files, recordings) brought to the names the
/// notes link them by, and the sizes the setup shows before the first commit.
///
/// **The README is `README.txt`, never `README.md`**: a `.md` at the Library's root would be indexed as a note and
/// synced to the account (the critic's finding, docs/MARKDOWN_FIRST.md §12); export_commands.rs writes `README.txt`
/// for the same reason. `.git/` is never notes: the vault's walk skips every dot folder but `.trash/`, which it reads as the Trash
/// (tauri/src-tauri/src/library/vault.rs `markdown()`), which test/plugins/git_backup/files_test.dart confirms.
///
/// **Attachments.** The attachments slice (2026-10-31, tauri/src-tauri/src/library/attachments.rs) moves them under
/// the Library at the paths the notes link, a kind at a time: pictures live at `Library/image/` now; files, films and
/// recordings are read from `Library/file/`, `video/`, `recordings/` but still written beside the app's data until
/// the Dart store and the players read both. The core says where each kind is read from, the first folder the one
/// written to (lib/files/attachment_places.dart `AttachmentPlaces`). [AttachmentMap] copies each kind from every
/// folder it is read from that is not the repository's own folder into the repository at the name the notes link
/// ([attachmentFolders]), only what changed by size or time; a repository file is taken out only where no folder of
/// its kind has it and the repository's folder is not itself one the app reads. When a kind is settled under the
/// Library the copy is a no-op, so the swap to the real folders is a change of places, not of code.
library;

import 'dart:io';

import '../../files/attachment_places.dart';
import 'settings.dart';

/// The folders an attachment kind is committed under, and the kind's folders as [AttachmentPlaces] lists them.
const List<({String repoName, List<String> Function(AttachmentPlaces) read})> attachmentFolders = [
  (repoName: 'image', read: _image),
  (repoName: 'file', read: _file),
  (repoName: 'recordings', read: _recording),
];

List<String> _image(AttachmentPlaces p) => p.image;
List<String> _file(AttachmentPlaces p) => p.file;
List<String> _recording(AttachmentPlaces p) => p.recording;

String _normal(String path) => path.replaceAll(RegExp(r'[\\/]+$'), '');

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

/// [sizes] of the repository at [repoPath], with the attachments still beside the app's data ([places]) counted where
/// they are.
RepoSizes repoSizes({required String repoPath, AttachmentPlaces? places, required GitBackupSettings settings, required Iterable<String> orgs}) {
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
  if (places != null) {
    for (final folder in attachmentFolders) {
      for (final source in folder.read(places)) {
        if (_normal(source) == _normal('$repoPath/${folder.repoName}')) continue;
        final here = folderSize(source, where: (relative) => !relative.contains('/'));
        if (folder.repoName == 'recordings') {
          recordings = recordings + here;
          if (settings.recordings) size = size + here;
        } else {
          size = size + here;
        }
      }
    }
    for (final source in places.video) {
      if (_normal(source) != _normal('$repoPath/video')) video = video + folderSize(source);
    }
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

/// The attachments brought into the repository at the names the notes link (see the header). [places] is where the
/// app reads each kind; where a kind already lives in the repository nothing is copied.
class AttachmentMap {
  const AttachmentMap({required this.repoPath, required this.places});
  final String repoPath;
  final AttachmentPlaces? places;

  /// Copies what changed and takes out what is gone from every folder of its kind (never where the repository's own
  /// folder is one the app reads); answers the paths of files refused for size, so the commit can name them.
  /// Recordings are copied only when [settings] includes them and each is under the cap (the cap holds for a
  /// recording already in the repository's folder too: over it, it is left out of the commit by being taken out).
  List<String> bring(GitBackupSettings settings) {
    final places = this.places;
    if (places == null) return const [];
    final refused = <String>[];
    for (final folder in attachmentFolders) {
      final target = Directory('$repoPath/${folder.repoName}');
      if (folder.repoName == 'recordings' && !settings.recordings) continue;
      final sources = [for (final s in folder.read(places)) if (_normal(s) != _normal(target.path)) Directory(s)];
      final targetIsRead = folder.read(places).any((s) => _normal(s) == _normal(target.path));
      final wanted = <String>{};
      for (final source in sources) {
        if (!source.existsSync()) continue;
        for (final entry in source.listSync(followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.')) continue;
          final length = entry.lengthSync();
          if (folder.repoName == 'recordings' && length > settings.recordingsMaxBytes) {
            refused.add('${folder.repoName}/$name');
            continue;
          }
          if (!wanted.add(name)) continue;
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
          if (folder.repoName == 'recordings' && entry.lengthSync() > settings.recordingsMaxBytes) {
            if (!refused.contains('${folder.repoName}/$name')) refused.add('${folder.repoName}/$name');
            if (!targetIsRead) entry.deleteSync();
            continue;
          }
          if (!targetIsRead && !wanted.contains(name)) entry.deleteSync();
        }
      }
    }
    return refused;
  }

  /// The other way, after a clone: what the repository holds at `image/`, `file/` and `recordings/` copied to where
  /// the app writes each kind (the first of its folders), so the notes' pictures show. Nothing where that is the
  /// repository's own folder.
  int restore() {
    final places = this.places;
    if (places == null) return 0;
    var copied = 0;
    for (final folder in attachmentFolders) {
      final source = Directory('$repoPath/${folder.repoName}');
      final written = folder.read(places).firstOrNull;
      if (written == null || _normal(written) == _normal(source.path) || !source.existsSync()) continue;
      final target = Directory(written);
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
