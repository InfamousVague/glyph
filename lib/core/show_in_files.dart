/// A note's file or a folder's directory shown where the computer shows files (Matt, 2026-11-01, after the note and
/// folder menus of 2.3.96: "also add an 'open in finder' option"). The row every note's and folder's menu has on a
/// desktop: the sidebar's, the page tree's …, the icon view's tiles and chips in All notes by folder.
///
/// - **A Mac:** Show in Finder, `open -R <path>`: a window on the folder it is in, with it selected. The app is not
///   sandboxed (macos/Runner/Release.entitlements), so a chosen folder's plain path is reached as the app's own is,
///   and nothing is asked for: no bookmark, no entitlement. The store's sandboxed build keeps everything in its own
///   container, which its `open` reaches too.
/// - **Windows:** Show in Explorer, `explorer /select, <path>`, the same window with it selected. Explorer answers 1
///   whether it opened or not, so its answer is not read.
/// - **Linux:** Show in Files, `xdg-open` on the folder it is in: a file manager opened there has nothing to select
///   with, so the folder is the most it can show.
/// - **Not on a phone or an iPhone, nor in a browser:** there the row is not there. The phone's Files app shows the
///   whole library (lib/core/library_files.dart, the sidebar's Browse files), never one file in it.
///
/// The path is the library's: its root as Settings › Library has it (a chosen folder, an Obsidian vault say, while it
/// can be reached, else Ghost.md's own; lib/core/folder_dirs.dart `libraryRootOf`), and under it a note's own
/// `path`, or a folder's directory as filing names it (lib/core/note_folders.dart `folderFor`). A note with no file
/// yet, a folder whose directory is not on the disk (one nothing was ever filed in), or a library Dart cannot reach
/// (an Android SAF tree): no row. The root is asked as the app starts and again each time a menu is drawn, and the
/// press asks it once more, so a library moved meanwhile shows the file where it is now.
///
/// What runs it is [ShowInFiles.new]'s `launch`, `Process.run` in the app and a fake in a test, which also says the
/// device and how a path is looked for: a test never opens Finder.
library;

import 'dart:async';
import 'dart:io' show Directory, File, Process;

import 'package:flutter/foundation.dart';

/// What a row runs: the program and its words.
@immutable
class ShowCommand {
  const ShowCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) => other is ShowCommand && other.executable == executable && listEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));

  @override
  String toString() => 'ShowCommand($executable ${arguments.join(' ')})';
}

/// The row's words on [platform], or null where it has none (a phone, an iPhone, Fuchsia).
String? showInFilesLabel(TargetPlatform platform) => switch (platform) {
      TargetPlatform.macOS => 'Show in Finder',
      TargetPlatform.windows => 'Show in Explorer',
      TargetPlatform.linux => 'Show in Files',
      _ => null,
    };

/// What shows [path] (whole, the device's own) on [platform]: selected in its folder on a Mac and Windows, its
/// folder opened on Linux. Null where there is no row.
ShowCommand? showCommandFor(TargetPlatform platform, String path) {
  switch (platform) {
    case TargetPlatform.macOS:
      return ShowCommand('open', ['-R', path]);
    case TargetPlatform.windows:
      return ShowCommand('explorer', ['/select,', path.replaceAll('/', r'\')]);
    case TargetPlatform.linux:
      final at = path.lastIndexOf('/');
      return ShowCommand('xdg-open', [at <= 0 ? '/' : path.substring(0, at)]);
    default:
      return null;
  }
}

/// [relative] (the library's, `/` between its parts) under [root], in the device's own way of writing a path.
String libraryPathOf(String root, String relative, {TargetPlatform? platform}) {
  final windows = (platform ?? defaultTargetPlatform) == TargetPlatform.windows;
  final sep = windows ? r'\' : '/';
  final base = root.endsWith('/') || root.endsWith(r'\') ? root.substring(0, root.length - 1) : root;
  final parts = relative.split('/').where((part) => part.isNotEmpty);
  return [base, ...parts].join(sep);
}

/// Runs a program and is done with it ([Process.run]'s, unless a test says).
typedef ShowLauncher = Future<void> Function(String executable, List<String> arguments);

/// Whether a path is on the disk, as a directory where [directory] says so.
typedef ShowExists = bool Function(String path, {required bool directory});

/// The menus' Show in Finder (see the header): whether a row is offered for a file, and what its press runs.
class ShowInFiles {
  ShowInFiles({required Future<String?> Function() root, ShowLauncher? launch, ShowExists? exists, TargetPlatform? platform, bool? web})
      : _rootOf = root,
        _launch = launch ?? _run,
        _exists = exists ?? _onDisk,
        _platform = platform,
        _web = web ?? kIsWeb {
    unawaited(refresh());
  }

  final Future<String?> Function() _rootOf;
  final ShowLauncher _launch;
  final ShowExists _exists;
  final TargetPlatform? _platform;
  final bool _web;

  TargetPlatform get _device => _platform ?? defaultTargetPlatform;

  /// The row's words here, or null where there is no row (a phone, an iPhone, a browser).
  String? get label => _web ? null : showInFilesLabel(_device);

  String? _root;
  Future<void>? _asking;

  /// The library's root as last asked, for a menu drawn now.
  String? get root => _root;

  /// Asks where the library is, once at a time; quiet when it cannot say, and nothing where there is no row.
  Future<void> refresh() => label == null ? Future<void>.value() : _asking ??= () async {
        try {
          _root = await _rootOf();
        } catch (_) {
          // Kept as it was: the next menu asks again.
        } finally {
          _asking = null;
        }
      }();

  /// The row's words for the library's [relative] path, a note's file or with [directory] a folder's, where it is on
  /// the disk; null for no row. The root is asked again meanwhile, for the next menu.
  String? offer(String? relative, {bool directory = false}) {
    final words = label;
    if (words == null || relative == null || relative.isEmpty) return null;
    unawaited(refresh());
    final root = _root;
    if (root == null) return null;
    return _exists(libraryPathOf(root, relative, platform: _device), directory: directory) ? words : null;
  }

  /// Shows [relative] (see [offer]) with the root asked once more; quiet about what it cannot do, said in the log.
  Future<void> show(String relative, {bool directory = false}) async {
    if (label == null) return;
    await refresh();
    final root = _root;
    if (root == null) return;
    final path = libraryPathOf(root, relative, platform: _device);
    final command = showCommandFor(_device, path);
    if (command == null) return;
    if (!_exists(path, directory: directory)) {
      debugPrint('[ghost] $path is not on the disk to show');
      return;
    }
    try {
      await _launch(command.executable, command.arguments);
    } catch (failure) {
      debugPrint('[ghost] could not show $path: $failure');
    }
  }

  static Future<void> _run(String executable, List<String> arguments) async {
    await Process.run(executable, arguments);
  }

  static bool _onDisk(String path, {required bool directory}) {
    try {
      return directory ? Directory(path).existsSync() : File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
