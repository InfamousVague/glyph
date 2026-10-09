/// Where the library is, and the calls that move it (native/src/kept/library_commands.rs; docs/DESIGN.md §187 of
/// ../glyph), for Settings › Library folder (lib/settings/panes/library_folder_pane.dart). A port of
/// `src/app/core/libraryFolder.ts`.
///
/// A folder is only ever chosen in the system's own picker (Android, android/…/glyph/files/LibraryTree.kt): the app
/// never sends a path. It is looked into first - how many Markdown files it holds, whether Obsidian keeps it - and
/// the page says what will happen before anything does. Then [LibraryFolder.move] moves the notes in, and the list
/// is read again.
///
/// What differs:
/// - The page's imports (`invoke`, `window.GlyphHost.chooseLibraryFolder` with its `libraryFolder` answer,
///   `announceNotesChanged`, the platform) are one value, [LibraryFolder], which the app's root makes from the core
///   it already holds and a test makes from fakes.
/// - **The picker is one call.** The activity answered "started" and said the rest as an event on its page; here
///   `chooseLibraryFolder` on `ghost_md/files` (android/…/ghost_md/FilesBridge.kt) answers the picker's JSON when the
///   picker does, so [pickTreeOnPhone] is a function that answers what `readFolderAnswer` reads.
/// - **No generation to wait for** (`FOLDER_GENERATION`, 25): the Dart and the core are one build. `update` is what
///   [LibraryFolder.way] answers where this build has no way to choose: an Android run with no picker behind
///   the channel, and a desktop run that is not the Mac app.
/// - **The Mac's `library_choose_folder` is two calls**: the folder panel is Swift's
///   (macos/Runner/FilesChannel.swift, the same `chooseLibraryFolder` on the channel, answering `{path, name}`),
///   and the core's `library_inspect {path}` looks into the folder and holds it. The Mac app is sandboxed, so
///   the panel's grant is also what lets the core read the folder, now and (kept as a bookmark) at later launches.
/// - `browser` is never answered: there is no build of this app whose notes are a browser's.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mac_app.dart';
import 'native/core.dart';

/// The channel FilesBridge.kt answers on: the system's pickers, each call answered with the picker's own JSON.
const MethodChannel filesChannel = MethodChannel('ghost_md/files');

/// The binary with `library_root`, the folder picker, the move and the way back (`FOLDER_GENERATION`), kept for the
/// record: nothing here waits for it.
const int folderGeneration = 25;

/// Where a folder can be chosen from here: the Mac's panel, Android's picker, or nowhere yet, and why (`FolderWay`).
enum FolderWay { mac, android, browser, update, none }

/// Where the library is now (library_commands.rs `Status`).
@immutable
class LibraryStatus {
  const LibraryStatus({required this.kind, this.path, this.name, this.reachable = true, this.notes = 0, this.own});

  factory LibraryStatus.fromJson(Map<String, Object?> json) => LibraryStatus(
        kind: json['kind'] is String ? json['kind']! as String : 'app',
        path: json['path'] as String?,
        name: json['name'] as String?,
        reachable: json['reachable'] != false,
        notes: (json['notes'] as num?)?.toInt() ?? 0,
        own: json['own'] as String?,
      );

  /// `app`, `folder` or `tree`.
  final String kind;
  final String? path;
  final String? name;

  /// False while a chosen folder cannot be reached, and Ghost.md's own folder is open instead.
  final bool reachable;
  final int notes;
  final String? own;
}

/// A folder picked and looked into, nothing written there yet (`Candidate`).
@immutable
class Candidate {
  const Candidate({required this.kind, this.path, required this.name, this.markdown = 0, this.obsidian = false, this.notes = 0});

  factory Candidate.fromJson(Map<String, Object?> json) => Candidate(
        kind: json['kind'] is String ? json['kind']! as String : 'tree',
        path: json['path'] as String?,
        name: json['name'] is String ? json['name']! as String : '',
        markdown: (json['markdown'] as num?)?.toInt() ?? 0,
        obsidian: json['obsidian'] == true,
        notes: (json['notes'] as num?)?.toInt() ?? 0,
      );

  /// `folder` or `tree`.
  final String kind;
  final String? path;
  final String name;
  final int markdown;
  final bool obsidian;

  /// The notes that would be moved in from where the library is now.
  final int notes;
}

/// What a move did (`Moved`).
@immutable
class Moved {
  const Moved({this.notes = 0, this.adopted = 0, this.renamed = 0, this.same = 0, this.removed = 0, required this.status});

  factory Moved.fromJson(Map<String, Object?> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    final status = json['status'];
    return Moved(
      notes: count('notes'),
      adopted: count('adopted'),
      renamed: count('renamed'),
      same: count('same'),
      removed: count('removed'),
      status: LibraryStatus.fromJson(status is Map ? status.cast<String, Object?>() : const {}),
    );
  }

  final int notes;
  final int adopted;
  final int renamed;
  final int same;
  final int removed;
  final LibraryStatus status;
}

/// A failure as the page says it: the core answers with a sentence, a thrown string is its own words, and an error
/// its message (`failureOf`).
String failureOf(Object? error) {
  if (error is String) return error;
  if (error is CoreError) return error.message;
  if (error is PlatformException) return error.message ?? 'That didn’t work.';
  if (error is StateError) return error.message;
  if (error is Exception || error is Error) {
    final text = error.toString();
    for (final lead in const ['Exception: ', 'Error: ']) {
      if (text.startsWith(lead)) return text.substring(lead.length);
    }
    return text;
  }
  return 'That didn’t work.';
}

/// What Android's picker answered (files/LibraryTree.kt), as the page reads it (`FolderAnswer`).
sealed class FolderAnswer {
  const FolderAnswer();
}

class FolderGranted extends FolderAnswer {
  const FolderGranted(this.uri, this.name);
  final String uri;
  final String name;

  @override
  bool operator ==(Object other) => other is FolderGranted && other.uri == uri && other.name == name;

  @override
  int get hashCode => Object.hash(uri, name);
}

class FolderCancelled extends FolderAnswer {
  const FolderCancelled();

  @override
  bool operator ==(Object other) => other is FolderCancelled;

  @override
  int get hashCode => (FolderCancelled).hashCode;
}

class FolderRefused extends FolderAnswer {
  const FolderRefused(this.error);
  final String error;

  @override
  bool operator ==(Object other) => other is FolderRefused && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// The picker's answer read (`readFolderAnswer`): anything that is not one of the three is a folder that cannot be
/// used.
FolderAnswer readFolderAnswer(String json) {
  const unread = FolderRefused('That folder can’t be used.');
  Object? said;
  try {
    said = jsonDecode(json);
  } catch (_) {
    return unread;
  }
  if (said is! Map) return unread;
  if (said['cancelled'] == true) return const FolderCancelled();
  final error = said['error'], uri = said['uri'], name = said['name'];
  if (error is String) return FolderRefused(error);
  if (uri is String && uri.startsWith('content://')) return FolderGranted(uri, name is String ? name : '');
  // The Mac's panel: a folder by its whole path.
  final path = said['path'];
  if (path is String && path.startsWith('/') && path.length > 1) return FolderGranted(path, name is String ? name : '');
  return unread;
}

/// Android's folder picker through the activity, answering its JSON once the picker does; with no phone half, the
/// words the page had for a shell without one.
Future<String> pickTreeOnPhone() async {
  try {
    return await filesChannel.invokeMethod<String>('chooseLibraryFolder') ?? jsonEncode({'error': 'This phone has no way to choose a folder.'});
  } on MissingPluginException {
    return jsonEncode({'error': 'This phone has no way to choose a folder.'});
  } on PlatformException catch (failure) {
    return jsonEncode({'error': failure.message ?? 'This phone has no way to choose a folder.'});
  }
}

/// The library's folder as the app reaches it: the page's imports, as one value (see the header).
class LibraryFolder {
  LibraryFolder({required CoreInvoke invoke, Future<String> Function()? pickTree, this.onNotesChanged, TargetPlatform? platform, bool? macApp})
      : _invoke = invoke,
        _platform = platform,
        _macApp = macApp ?? runsAsMacApp,
        _pickTree = pickTree;

  final CoreInvoke _invoke;
  final TargetPlatform? _platform;
  final Future<String> Function()? _pickTree;

  /// Whether the Mac's own panel is behind the channel (lib/core/mac_app.dart): never in a test on a Mac.
  final bool _macApp;

  /// Told once a move has changed which notes there are (`announceNotesChanged`): the list is read again.
  final void Function()? onNotesChanged;

  TargetPlatform get _device => _platform ?? defaultTargetPlatform;

  /// The picker: the one handed in, else the activity's on Android and the Mac app's panel on a Mac (the same
  /// call on the channel), else none.
  Future<String> Function()? get _picker => _pickTree ?? (_device == TargetPlatform.android || (_device == TargetPlatform.macOS && _macApp) ? pickTreeOnPhone : null);

  /// Where a folder can be chosen from here (`folderWay`).
  Future<FolderWay> way() async {
    if (_device == TargetPlatform.iOS) return FolderWay.none;
    if (_device == TargetPlatform.android) return _picker == null ? FolderWay.update : FolderWay.android;
    if (_device == TargetPlatform.macOS) return _picker == null ? FolderWay.update : FolderWay.mac;
    // No other desktop has a panel yet: this build keeps the notes in its own folder.
    return FolderWay.update;
  }

  /// Where the library is now (`libraryStatus`).
  Future<LibraryStatus> status() async => LibraryStatus.fromJson(_map(await _invoke('library_root')));

  /// A folder chosen in the system's own picker, and looked into; null when it was closed without one
  /// (`chooseFolder`). Throws the picker's or the core's own words.
  Future<Candidate?> choose() async {
    final picker = _picker;
    if (picker == null) throw StateError('This phone has no way to choose a folder.');
    switch (readFolderAnswer(await picker())) {
      case FolderCancelled():
        return null;
      case FolderRefused(:final error):
        throw StateError(error);
      case FolderGranted(:final uri):
        // Android's tree by its uri; the Mac's folder by its path (kept/library_commands.rs).
        return Candidate.fromJson(_map(await _invoke('library_inspect', uri.startsWith('/') ? {'path': uri} : {'uri': uri})));
    }
  }

  /// The folder looked into becomes the library; the list is read again from it (`moveLibrary`).
  Future<Moved> move() async {
    final moved = Moved.fromJson(_map(await _invoke('library_move')));
    onNotesChanged?.call();
    return moved;
  }

  /// Back to Ghost.md's own folder, with a copy of every note or none. The chosen folder keeps every file
  /// (`backToOwnFolder`).
  Future<Moved> backToOwnFolder(bool copy) async {
    final moved = Moved.fromJson(_map(await _invoke('library_use_app_folder', {'copy': copy})));
    onNotesChanged?.call();
    return moved;
  }

  static Map<String, Object?> _map(Object? said) => said is Map ? said.cast<String, Object?>() : const {};
}

String _notesSaid(int n) => n == 1 ? '1 note' : '$n notes';
String _filesSaid(int n) => n == 1 ? '1 Markdown file' : '$n Markdown files';

/// What will happen, said before it does. [fromOwn] is whether the notes are in Ghost.md's own folder now
/// (`candidateSaid`).
String candidateSaid(Candidate candidate, bool fromOwn) {
  final ours = candidate.notes != 0
      ? 'Your ${_notesSaid(candidate.notes)} ${fromOwn ? 'move' : 'are copied'} in${candidate.markdown != 0 ? ' beside them' : ''}, in the same folders, and a note whose name is taken there gets “2” after it.'
      : 'You have no notes to bring.';
  final after = candidate.notes != 0 ? (fromOwn ? ' Once they are in, they leave Ghost.md’s own folder.' : ' The folder they are in now keeps its copy.') : '';
  if (candidate.markdown == 0) return '${candidate.name} is empty of notes. $ours$after';
  final vault = candidate.obsidian ? ', and Obsidian keeps it' : '';
  return '${candidate.name} has ${_filesSaid(candidate.markdown)}$vault. Each becomes a note and stays where it is, as it is. $ours$after';
}

/// What a move did, in a sentence (`movedSaid`).
String movedSaid(Moved moved) {
  final parts = ['${_notesSaid(moved.notes)} moved in'];
  if (moved.adopted != 0) parts.add('${_notesSaid(moved.adopted)} that were there already');
  if (moved.renamed != 0) parts.add('${moved.renamed} renamed with a number');
  if (moved.same != 0) parts.add('${moved.same} already there word for word');
  return '${parts.join(', ')}.';
}
