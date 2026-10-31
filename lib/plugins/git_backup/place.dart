/// Where the repository is: the Library folder itself, with `.git` inside it (Matt's decision 3, 2026-10-31,
/// docs/MARKDOWN_FIRST.md §11), or, where that cannot be, a mirror of the Library under the app's data that the plugin
/// keeps in step with it.
///
/// Two places refuse `.git` in the Library:
/// - **A syncing folder.** A chosen Library on iCloud Drive, Dropbox, OneDrive or Google Drive would sync `.git`
///   object by object and corrupt it (the index is refused in such folders for the same reason). Told by the path on
///   the Mac ([syncingFolder]); the plugin refuses to init there in a plain sentence, and says what to do instead
///   (choose a folder outside it, or use Ghost.md's own).
/// - **An Android SAF tree.** A folder picked in Android's picker has no filesystem path for git to live at, so the
///   repository is a mirror at `<app data>/git/library/`, written from the library's notes before each commit
///   ([mirrorPath]), and the page says so.
library;

import '../../core/library_folder.dart' show LibraryStatus;

/// What kind of place the repository is at.
enum RepoKind {
  /// `.git` inside the Library folder: the Mac's own folder or a chosen one, and a phone's own folder.
  library,

  /// A mirror under the app's data, kept in step with a Library that cannot hold `.git` (an Android SAF tree).
  mirror,
}

/// The repository's place: its folder on disk, and whether that is the Library or a mirror of it.
class RepoPlace {
  const RepoPlace({required this.kind, required this.path, this.libraryPath});

  final RepoKind kind;

  /// The folder with `.git` in it.
  final String path;

  /// The Library's own folder, where the repository is it; null for a mirror of a tree with no path.
  final String? libraryPath;

  bool get isMirror => kind == RepoKind.mirror;

  @override
  String toString() => '${kind.name} at $path';
}

/// The syncing service [path] is inside, by its folders, or null for a plain folder: `~/Library/Mobile Documents/…`
/// is iCloud Drive, `~/Dropbox/…` Dropbox, `~/Library/CloudStorage/OneDrive-…` OneDrive, `~/Library/CloudStorage/
/// GoogleDrive-…` Google Drive, and so on. Matched on the folder names alone, which is how the Mac lays them out; a
/// folder a person named "Dropbox" themselves is refused too, which is the safe side. On Android a picked folder is
/// a tree with no path and takes the mirror (placeFor); the app's own folder is never inside a syncing one.
String? syncingFolder(String path) {
  final parts = path.split(RegExp(r'[\\/]+'));
  for (final part in parts) {
    if (part == 'Mobile Documents' || part == 'com~apple~CloudDocs' || part == 'iCloud Drive') return 'iCloud Drive';
    if (part == 'Dropbox') return 'Dropbox';
    if (part.startsWith('OneDrive')) return 'OneDrive';
    if (part == 'Google Drive' || part.startsWith('GoogleDrive')) return 'Google Drive';
  }
  // The Mac's folder for every file provider, when the provider's own folder was not one of the above.
  return parts.contains('CloudStorage') ? 'a cloud drive' : null;
}

/// Why the Library cannot be the repository, in a sentence, or null where it can: the folder it is in syncs by
/// itself, which would tear `.git` apart.
String? libraryRefusal(String libraryPath) {
  final service = syncingFolder(libraryPath);
  if (service == null) return null;
  return 'Your Library is inside $service, which syncs every file by itself and would corrupt a git repository kept there. Choose a Library folder outside $service in Settings › Library folder, or use Ghost.md’s own folder, then set this up again.';
}

/// Where the repository goes for a library at [status]: `.git` in the Library for the app's own folder or a chosen
/// one on disk; a mirror at [mirrorRoot] for an Android tree; a refusal, as a sentence, for a syncing folder.
({RepoPlace? place, String? refusal}) placeFor(LibraryStatus status, {required String mirrorRoot}) {
  switch (status.kind) {
    case 'tree':
      return (place: RepoPlace(kind: RepoKind.mirror, path: mirrorRoot), refusal: null);
    case 'folder':
      final path = status.reachable ? status.path : null;
      if (path == null) return (place: null, refusal: 'Your Library folder can’t be reached just now. Plug the drive back in, or choose the folder again, then set this up again.');
      final refusal = libraryRefusal(path);
      if (refusal != null) return (place: null, refusal: refusal);
      return (place: RepoPlace(kind: RepoKind.library, path: path, libraryPath: path), refusal: null);
    default:
      final own = status.own;
      if (own == null) return (place: null, refusal: 'Ghost.md’s own folder could not be found.');
      return (place: RepoPlace(kind: RepoKind.library, path: own, libraryPath: own), refusal: null);
  }
}

/// What the page says of a mirror, so the person knows the repository is not the folder they picked.
const String mirrorExplained =
    'Your Library is a folder picked in Android’s picker, where git can’t keep its files, so the repository is a copy of it kept inside Ghost.md and brought up to date before each backup. Your folder itself is untouched.';
