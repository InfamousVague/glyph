/// Where the ledger the relay is checked by is kept (lib/net/ledger.dart): a folder of files of its own, out of any
/// backup (the review, 2026-11-23, D6). It held up to some 60 KB a friend, rewritten every twenty seconds through a
/// chat, in the app's choices, which Android's backup copies to the person's other phones. Now:
///
/// - Android: the app's `no_backup` folder, which Android's backup never takes (Context.getNoBackupFilesDir).
/// - An iPhone, a Mac: the app's folder under Library/Caches, which iCloud's and Time Machine's backups leave out.
/// - Windows: under the local, unroamed app data (LOCALAPPDATA); Linux: under the cache folder (XDG_CACHE_HOME).
/// - A browser: none, and so no ledger (it has no direct route to compare one over).
library;

export 'kept_files_io.dart' if (dart.library.js_interop) 'kept_files_web.dart';
export 'kept_paths.dart';
