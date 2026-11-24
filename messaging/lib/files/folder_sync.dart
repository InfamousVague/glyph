/// A folder on a computer kept in step with My files (GMFB-38: "Sync a folder on your computer with a drive").
///
/// What a pass does, and what it never does. This touches people's own folders, so the rules are few and one-way safe:
///
/// - **Adds and changes only.** A file new or changed in the folder goes up to the drive under the same path; a file
///   new or changed in the drive comes down into the folder. Which side changed is told from a small state file kept
///   in the app's own folder ([SyncState]): for each path, the local size and modified time and the drive's file id
///   and SHA-256 when the two were last in step.
/// - **Nothing is deleted, on either side.** A file removed on one side is still on the other, so the next pass brings
///   it back. The drive has no "replace": a changed file goes up as a newer file of the same name and the older one
///   stays in the drive; the newest of a name is the one the folder follows.
/// - **A local file is replaced only where its content is one the sync itself recorded**: its size and time are as
///   recorded AND its SHA-256 is the recorded one. Anything else (both sides changed, or no record) keeps both: the
///   drive's is written beside it as "name (from My files).ext" and the local one goes up.
/// - **What comes down is written under a temporary name in the same folder** (".ghost-sync-….part") and renamed when
///   whole and checked, so a half-written file never has the real name.
/// - **Left out**: hidden files and folders (a dot first, desktop.ini, Thumbs.db), links (never followed), files
///   changed in the last few seconds (still being written), files over the drive's limit or its room, and names
///   another system can't hold. A pass never walks or writes outside the folder: a path from the drive is refused
///   where it has a name of dots, a slash, or goes through a link.
/// - **Never synced**: the home folder itself or anything above it, a disk's top, and the app's own folders.
///
/// The folder chosen is this computer's alone: a file in the app's folder, never the account's synced preferences.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../desktop/store.dart' show DeskStore;
import '../net/file_seal.dart';
import '../platform_info.dart';
import '../voice/voice.dart' show VoiceChannel;
import 'drive.dart';
import 'files_store.dart';

/// A file in the drive, as a pass sees it: its path from the drive's top ("Papers/lease.pdf").
class DriveFile {
  const DriveFile({required this.id, required this.path, required this.size, required this.sha, required this.at});
  final String id, path, sha;
  final int size, at;
}

/// One file can't go this pass, for a reason said in a few words ("too big"); the rest carry on.
class SyncSkip implements Exception {
  const SyncSkip(this.why);
  final String why;
}

/// The pass can't go on (the drive is out of reach); said in the state line, tried again next time.
class SyncStop implements Exception {
  const SyncStop(this.why);
  final String why;
}

/// The drive, as much of it as a pass needs. [StoreDrive] is the app's; a test gives its own.
abstract class SyncDrive {
  /// Which drive this is, for the state file's name (never its seed).
  String get id;

  /// Every file in the drive; null where it can't be reached now.
  Future<List<DriveFile>?> list();

  /// The most one file may be, and the room left; 0 and null where not known.
  int get maxFile;
  int? get free;

  /// Adds the file at [local] as [name] in [folder] (null for the top): the drive's file, or null where it went up but
  /// can't be told which it is. Throws [SyncSkip] or [SyncStop].
  Future<DriveFile?> upload(String local, String? folder, String name);

  /// [f] whole and checked, at a path on this device the pass copies from. Throws [SyncSkip] or [SyncStop].
  Future<String> fetch(DriveFile f);
}

/// What one path was when the folder and the drive were last in step.
class SyncEntry {
  SyncEntry({this.size = -1, this.modified = -1, this.id = '', this.sha = '', this.kept});

  /// The local file's size and modified time (ms), and the drive's file id and SHA-256 of that content.
  int size, modified;
  String id, sha;

  /// A drive file already written beside this path as a second copy, so it is not written again.
  String? kept;

  Map<String, Object?> toJson() => {'z': size, 'm': modified, 'id': id, 'h': sha, 'k': ?kept};
  static SyncEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    return SyncEntry(size: (j['z'] as num?)?.toInt() ?? -1, modified: (j['m'] as num?)?.toInt() ?? -1, id: '${j['id'] ?? ''}', sha: '${j['h'] ?? ''}', kept: j['k'] as String?);
  }
}

/// The state file of one synced folder, in the app's own folder (never inside the synced one).
class SyncState {
  SyncState(this.file);
  final File file;
  final Map<String, SyncEntry> entries = {};

  void load() {
    entries.clear();
    try {
      if (!file.existsSync()) return;
      final j = jsonDecode(file.readAsStringSync());
      final files = j is Map ? j['files'] : null;
      if (files is! Map) return;
      for (final e in files.entries) {
        final v = SyncEntry.fromJson(e.value);
        if (v != null) entries['${e.key}'] = v;
      }
    } catch (_) {
      // Unreadable: as a folder never synced, where nothing is replaced and what differs is kept twice.
      entries.clear();
    }
  }

  void save(String root) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsStringSync(jsonEncode({'v': 1, 'root': root, 'files': {for (final e in entries.entries) e.key: e.value.toJson()}}), flush: true);
    tmp.renameSync(file.path);
  }
}

/// What a pass came to.
class SyncReport {
  int up = 0, down = 0, both = 0;

  /// Why files were left out, and how many of each.
  final Map<String, int> skipped = {};

  /// More to move than one pass takes, or more files than one pass walks.
  bool capped = false;

  /// Why the pass did not finish; null where it did.
  String? stopped;

  int get moved => up + down;
  void skip(String why) => skipped[why] = (skipped[why] ?? 0) + 1;

  /// The state line once a pass is done.
  String get line {
    if (stopped != null) return 'Stopped: $stopped';
    final left = [for (final e in skipped.entries) '${e.value} ${e.key}'].join(', ');
    final more = capped ? ' More next time.' : '';
    if (left.isEmpty) return 'In step.$more';
    final n = skipped.values.fold(0, (a, b) => a + b);
    return 'In step, but for $n left out ($left).$more';
  }
}

/// One pass over one folder ([run]); and what may be synced at all ([whyNot]).
class FolderSyncEngine {
  FolderSyncEngine({required this.root, required this.drive, required this.state, DateTime Function()? now, this.most = 2000, this.walkMost = 20000, this.quiet = const Duration(seconds: 5), this.stopped, this.progress}) : now = now ?? DateTime.now;

  /// The folder, as [resolve] gave it.
  final String root;
  final SyncDrive drive;
  final SyncState state;
  final DateTime Function() now;

  /// The most files one pass moves, and the most it looks at.
  final int most, walkMost;

  /// A file changed more recently than this is taken to be still being written.
  final Duration quiet;

  /// Asked between files: true stops the pass (Stop syncing, signed out).
  final bool Function()? stopped;

  /// Told as it goes: how many files are still to move.
  final void Function(int left)? progress;

  static final String _sep = PlatformInfo.pathSeparator;

  /// What a second copy's name is given.
  static const fromDrive = ' (from My files)';

  /// The start of a temporary file's name: hidden, so no pass takes one for a file.
  static const partStart = '.ghost-sync-';

  static const _hiddenNames = {'desktop.ini', 'thumbs.db', 'ehthumbs.db', r'$recycle.bin', 'system volume information', 'icon\r'};

  /// Whether a file or folder of this name is left out as hidden.
  static bool hidden(String name) => name.startsWith('.') || name.startsWith('~\$') || _hiddenNames.contains(name.toLowerCase());

  /// Whether every system can hold this name as it is, and the drive keeps it unchanged.
  static bool holdable(String name) => name.isNotEmpty && SpaceFile.cleanName(name) == name && name.length <= 200;

  /// Whether the drive keeps this folder path unchanged (no more than its depth, each name holdable and short).
  static bool holdableFolder(String? folder) => folder == null || SpaceFile.cleanFolder(folder) == folder;

  /// [path] with links and dots worked out; null where it is no folder.
  static String? resolve(String path) {
    try {
      final d = Directory(path);
      if (!d.existsSync()) return null;
      var p = d.resolveSymbolicLinksSync();
      while (p.length > 1 && (p.endsWith('/') || p.endsWith(r'\')) && !RegExp(r'^[A-Za-z]:[\\/]$').hasMatch(p)) {
        p = p.substring(0, p.length - 1);
      }
      return p;
    } catch (_) {
      return null;
    }
  }

  static String _fold(String p) => (PlatformInfo.isWindows || PlatformInfo.isMacOS ? p.toLowerCase() : p).replaceAll(r'\', '/');
  static bool _within(String inner, String outer) {
    final a = _fold(inner), b = _fold(outer);
    return a == b || a.startsWith(b.endsWith('/') ? b : '$b/');
  }

  /// Why the folder at [path] (as [resolve] gave it) can't be synced, in words; null where it can. [home] is the
  /// person's home folder and [own] the app's own folders.
  static String? whyNot(String path, {String? home, List<String> own = const []}) {
    final parent = Directory(path).parent.path;
    if (parent == path || RegExp(r'^[A-Za-z]:[\\/]?$').hasMatch(path) || path == '/' || RegExp(r'^[\\/]{2}[^\\/]+[\\/][^\\/]+[\\/]?$').hasMatch(path)) {
      return 'A whole disk can\'t be synced. Choose a folder in it.';
    }
    // A Mac's other disks, and Linux's: /Volumes/Name, /media/me/Name, /mnt/name.
    if (RegExp(r'^/(Volumes|mnt|media)(/[^/]+)?$').hasMatch(path) || RegExp(r'^/media/[^/]+/[^/]+$').hasMatch(path)) {
      return 'A whole disk can\'t be synced. Choose a folder in it.';
    }
    final h = home == null ? null : (resolve(home) ?? home);
    if (h != null && _within(h, path)) return 'Your home folder can\'t be synced. Choose a folder in it.';
    for (final o in own) {
      final r = resolve(o) ?? o;
      if (_within(path, r) || _within(r, path)) return 'That is where Ghost Messaging keeps its own files. Choose another folder.';
    }
    if (hidden(path.split(RegExp(r'[\\/]')).last)) return 'A hidden folder can\'t be synced.';
    return null;
  }

  /// The local files, by path with forward slashes: size and modified time.
  Map<String, ({int size, int modified})> _walk(SyncReport r) {
    final out = <String, ({int size, int modified})>{};
    final soon = now().subtract(quiet).millisecondsSinceEpoch;
    void into(Directory d, String? rel, int depth) {
      List<FileSystemEntity> list;
      try {
        list = d.listSync(followLinks: false);
      } catch (_) {
        r.skip('can\'t be read');
        return;
      }
      list.sort((a, b) => a.path.compareTo(b.path));
      for (final e in list) {
        if (out.length >= walkMost) {
          r.capped = true;
          return;
        }
        final name = e.path.substring(e.path.lastIndexOf(_sep) + 1);
        if (hidden(name)) continue;
        // What it is, itself: a link is never followed, whatever it points at.
        final type = FileSystemEntity.typeSync(e.path, followLinks: false);
        if (type == FileSystemEntityType.link) {
          r.skip('a link');
          continue;
        }
        final path = rel == null ? name : '$rel/$name';
        if (type == FileSystemEntityType.directory) {
          if (!holdable(name) || name.length > 80 || depth >= SpaceFile.maxDepth) {
            r.skip(depth >= SpaceFile.maxDepth ? 'too deep in folders' : 'with a name My files can\'t hold');
            continue;
          }
          into(Directory(e.path), path, depth + 1);
        } else if (type == FileSystemEntityType.file) {
          if (!holdable(name)) {
            r.skip('with a name My files can\'t hold');
            continue;
          }
          try {
            final s = File(e.path).statSync();
            final m = s.modified.millisecondsSinceEpoch;
            if (m > soon) {
              r.skip('still being written');
              continue;
            }
            out[path] = (size: s.size, modified: m);
          } catch (_) {
            r.skip('can\'t be read');
          }
        }
      }
    }

    into(Directory(root), null, 0);
    return out;
  }

  String _local(String path) => '$root$_sep${path.replaceAll('/', _sep)}';

  /// Whether [path] from the drive may be written in the folder: every name holdable and not hidden, none of dots.
  static bool _safe(String path) {
    final names = path.split('/');
    if (names.isEmpty || names.length > SpaceFile.maxDepth + 1) return false;
    for (final n in names) {
      if (n.isEmpty || n == '.' || n == '..' || n.contains(r'\') || !holdable(n) || hidden(n)) return false;
    }
    return true;
  }

  /// Makes the folders [path] lies in, refusing where one of them is a link or a file: never written through a link.
  bool _makeParents(String path) {
    final names = path.split('/')..removeLast();
    var at = root;
    for (final n in names) {
      at = '$at$_sep$n';
      final type = FileSystemEntity.typeSync(at, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        Directory(at).createSync();
      } else if (type != FileSystemEntityType.directory) {
        return false;
      }
    }
    return true;
  }

  static Future<String> shaOf(String path) async => (await crypto.sha256.bind(File(path).openRead()).first).toString();

  ({int size, int modified})? _stat(String path) {
    try {
      if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.file) return null;
      final s = File(path).statSync();
      return (size: s.size, modified: s.modified.millisecondsSinceEpoch);
    } catch (_) {
      return null;
    }
  }

  int _n = 0;

  /// Brings [f] down to [to] (a full local path): copied to a temporary name beside it, checked, then renamed. Where
  /// [replacing] is given, the file there must still be exactly that, or nothing is written. Where it is null, there
  /// must be no file there.
  Future<({int size, int modified})> _bring(DriveFile f, String to, {({int size, int modified})? replacing}) async {
    final from = await drive.fetch(f);
    final part = File('${File(to).parent.path}$_sep$partStart${now().microsecondsSinceEpoch}-${_n++}.part');
    try {
      await File(from).copy(part.path);
      if (part.lengthSync() != f.size) throw const SyncSkip('didn\'t come down whole');
      if (f.sha.isNotEmpty && (await shaOf(part.path)) != f.sha.toLowerCase()) throw const SyncSkip('didn\'t come down whole');
      final there = _stat(to);
      final type = FileSystemEntity.typeSync(to, followLinks: false);
      if (replacing == null ? type != FileSystemEntityType.notFound : (there == null || there.size != replacing.size || there.modified != replacing.modified)) {
        throw const SyncSkip('changed while syncing');
      }
      try {
        part.renameSync(to);
      } on FileSystemException {
        throw const SyncSkip('in use');
      }
      return _stat(to)!;
    } finally {
      // Only ever the pass's own temporary file.
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
  }

  /// A name beside [path] not taken: "lease (from My files).pdf", then "(from My files 2)".
  String? _beside(String path) {
    final slash = path.lastIndexOf('/');
    final dir = slash < 0 ? '' : path.substring(0, slash + 1), name = path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name, end = dot > 0 ? name.substring(dot) : '';
    for (var n = 1; n <= 50; n++) {
      final mark = n == 1 ? fromDrive : '${fromDrive.substring(0, fromDrive.length - 1)} $n)';
      final p = '$dir$stem$mark$end';
      if (holdable('$stem$mark$end') && FileSystemEntity.typeSync(_local(p), followLinks: false) == FileSystemEntityType.notFound) return p;
    }
    return null;
  }

  /// One pass. Never throws.
  Future<SyncReport> run() async {
    final r = SyncReport();
    try {
      await _run(r);
    } on SyncStop catch (e) {
      r.stopped = e.why;
    } catch (e) {
      r.stopped = 'something went wrong ($e)';
    }
    return r;
  }

  Future<void> _run(SyncReport r) async {
    if (FileSystemEntity.typeSync(root, followLinks: false) != FileSystemEntityType.directory) throw const SyncStop('the folder isn\'t there any more.');
    final listed = await drive.list();
    if (listed == null) throw const SyncStop('My files can\'t be reached right now.');
    state.load();
    final local = _walk(r);
    final lower = {for (final p in local.keys) p.toLowerCase(): p};

    // The drive's newest file of each path; a path the folder can't hold, or that differs from another only by
    // capitals, is left out.
    final remote = <String, DriveFile>{};
    final refused = <String>{};
    for (final f in listed) {
      if (!_safe(f.path)) {
        if (refused.add(f.path)) r.skip('with a name this computer can\'t hold');
        continue;
      }
      final had = remote[f.path];
      if (had == null || f.at > had.at || (f.at == had.at && f.id.compareTo(had.id) > 0)) remote[f.path] = f;
    }
    final clash = <String>{};
    final seen = <String, String>{};
    for (final p in remote.keys.toList()..sort()) {
      final l = p.toLowerCase();
      final same = lower[l] ?? seen[l];
      if (same != null && same != p) {
        clash.add(p);
        r.skip('with a name that differs only by capitals');
      } else {
        seen[l] = p;
      }
    }

    // What to do with each path, before anything moves.
    final paths = {...local.keys, ...remote.keys}.toList()..sort();
    final todo = <(String, String)>[];
    for (final p in paths) {
      if (clash.contains(p)) continue;
      final l = local[p], d = remote[p], s = state.entries[p];
      if (l != null && d == null && remote.keys.any((k) => k != p && k.toLowerCase() == p.toLowerCase())) continue;
      final localChanged = l != null && (s == null || s.size != l.size || s.modified != l.modified);
      final driveChanged = d != null && (s == null || s.id != d.id);
      if (l != null && d == null) {
        // New here, or gone from the drive: it goes up (nothing is deleted here).
        todo.add((p, 'up'));
      } else if (l == null && d != null) {
        // New in the drive, or gone from here: it comes down. Never onto a folder of the same name.
        // Something there the walk left out (still being written, a folder, a link) is left alone.
        if (FileSystemEntity.typeSync(_local(p), followLinks: false) == FileSystemEntityType.notFound) todo.add((p, 'down'));
      } else if (l != null && d != null) {
        if (!localChanged && !driveChanged) continue;
        if (localChanged && !driveChanged) {
          todo.add((p, 'up'));
        } else if (!localChanged && driveChanged && s != null && s.sha.isNotEmpty) {
          todo.add((p, 'replace'));
        } else {
          todo.add((p, 'both'));
        }
      }
    }
    // Paths gone from both sides are forgotten.
    state.entries.removeWhere((p, _) => !local.containsKey(p) && !remote.containsKey(p) && FileSystemEntity.typeSync(_local(p), followLinks: false) == FileSystemEntityType.notFound);

    var free = drive.free;
    var left = todo.length;
    progress?.call(left);
    var moved = 0;

    Future<void> up(String p, ({int size, int modified}) l, {String? kept}) async {
      if (drive.maxFile > 0 && l.size > drive.maxFile) throw SyncSkip('too big (over ${fileSize(drive.maxFile)})');
      if (free != null && l.size > free!) throw const SyncSkip('with no room left in My files');
      final slash = p.lastIndexOf('/');
      final folder = slash < 0 ? null : p.substring(0, slash);
      if (!holdableFolder(folder)) throw const SyncSkip('with a name My files can\'t hold');
      final f = await drive.upload(_local(p), folder, p.substring(slash + 1));
      // The same file as when it was looked at, or it is not recorded and the next pass looks again.
      final after = _stat(_local(p));
      if (after == null || after.size != l.size || after.modified != l.modified) throw const SyncSkip('changed while syncing');
      if (free != null) free = free! - l.size;
      state.entries[p] = SyncEntry(size: l.size, modified: l.modified, id: f?.id ?? '', sha: (f != null && f.sha.isNotEmpty) ? f.sha.toLowerCase() : await shaOf(_local(p)), kept: kept);
      r.up++;
    }

    for (final (p, what) in todo) {
      if (stopped?.call() ?? false) throw const SyncStop('stopped.');
      if (moved >= most) {
        r.capped = true;
        break;
      }
      final l = local[p], d = remote[p], s = state.entries[p];
      try {
        switch (what) {
          case 'up':
            await up(p, l!);
            moved++;
          case 'down':
            if (!_makeParents(p)) throw const SyncSkip('under a link');
            final got = await _bring(d!, _local(p));
            state.entries[p] = SyncEntry(size: got.size, modified: got.modified, id: d.id, sha: d.sha.isNotEmpty ? d.sha.toLowerCase() : await shaOf(_local(p)));
            r.down++;
            moved++;
          case 'replace':
            // The local file is replaced only where its content is the one recorded; else both are kept.
            if ((await shaOf(_local(p))) != s!.sha) continue both;
            final got = await _bring(d!, _local(p), replacing: l);
            state.entries[p] = SyncEntry(size: got.size, modified: got.modified, id: d.id, sha: d.sha.isNotEmpty ? d.sha.toLowerCase() : await shaOf(_local(p)));
            r.down++;
            moved++;
          both:
          case 'both':
            // The same content on both sides is in step, with nothing moved.
            if (l!.size == d!.size && d.sha.isNotEmpty && (await shaOf(_local(p))) == d.sha.toLowerCase()) {
              state.entries[p] = SyncEntry(size: l.size, modified: l.modified, id: d.id, sha: d.sha.toLowerCase());
              break;
            }
            // Both are kept: the drive's beside the local one (once), and the local one goes up as the newest.
            if (s?.kept != d.id) {
              final beside = _beside(p);
              if (beside == null) throw const SyncSkip('with too many copies beside it');
              await _bring(d, _local(beside));
              state.entries[p] = (s ?? SyncEntry())..kept = d.id;
              state.save(root);
              r.both++;
              r.down++;
            }
            await up(p, l, kept: d.id);
            moved++;
        }
        state.save(root);
      } on SyncSkip catch (e) {
        r.skip(e.why);
      } on FileSystemException {
        r.skip('can\'t be read or written');
      }
      progress?.call(--left);
    }
    state.save(root);
  }
}

/// The app's drive behind [SyncDrive]: My files in the files store.
class StoreDrive implements SyncDrive {
  StoreDrive(this.store, this.channel, {this.tick = const Duration(milliseconds: 250)});
  final FilesStore store;
  final VoiceChannel channel;
  final Duration tick;
  final Map<String, SpaceFile> _files = {};

  @override
  String get id => FileSeal.filesRoom(channel.seed);

  static String _pathOf(SpaceFile f) => f.folder == null ? f.name : '${f.folder}/${f.name}';
  DriveFile _of(SpaceFile f) {
    _files[f.id] = f;
    return DriveFile(id: f.id, path: _pathOf(f), size: f.size, sha: f.sha.toLowerCase(), at: f.at);
  }

  @override
  Future<List<DriveFile>?> list() async {
    final s = store.of(channel);
    try {
      await s.refresh();
    } catch (_) {
      return null;
    }
    if (s.error != null) return null;
    return [for (final f in s.files.values) _of(f)];
  }

  @override
  int get maxFile {
    final i = store.of(channel).info;
    // What is sealed is a little more than the file: a margin for it.
    return i == null || i.maxFile <= 0 ? 0 : math.max(0, i.maxFile - (i.maxFile >> 10) - 4096);
  }

  @override
  int? get free {
    final i = store.of(channel).info;
    if (i == null || i.quota <= 0) return null;
    return math.max(0, i.quota - i.used - ((i.quota - i.used) >> 10) - 4096);
  }

  @override
  Future<DriveFile?> upload(String local, String? folder, String name) async {
    // One already going up from before (the store keeps its queue over a restart) is waited for, not sent twice.
    var t = store.transfers.where((t) => t.up && !t.chat && t.path == local && t.space.seed == channel.seed && (t.state == TransferState.queued || t.state == TransferState.running)).firstOrNull;
    if (t == null) {
      final before = store.transfers.length;
      store.upload(channel, [local], folder: folder);
      if (store.transfers.length == before) throw const SyncSkip('can\'t be read or written');
      t = store.transfers.last;
    }
    while (t.state == TransferState.queued || t.state == TransferState.running) {
      await Future<void>.delayed(tick);
    }
    if (t.state != TransferState.done) {
      final why = t.error ?? '';
      final waiting = t.state == TransferState.waiting;
      // Not left in the page's list as a failure to try again by hand: the next pass tries it.
      await store.cancel(t);
      if (waiting) throw const SyncStop('My files can\'t be reached right now.');
      if (why.startsWith('Too big')) throw const SyncSkip('too big');
      if (why.startsWith('Not enough room')) throw const SyncSkip('with no room left in My files');
      throw const SyncSkip('that didn\'t go up');
    }
    SpaceFile? find() {
      final same = [for (final f in store.of(channel).files.values) if (f.name == name && f.folder == folder && (t!.sha == null || f.sha.isEmpty || f.sha == t.sha)) f]..sort((a, b) => b.at.compareTo(a.at));
      return same.firstOrNull;
    }

    var f = find();
    if (f == null) {
      try {
        await store.of(channel).refresh();
      } catch (_) {}
      f = find();
    }
    return f == null ? null : _of(f);
  }

  @override
  Future<String> fetch(DriveFile f) async {
    final file = _files[f.id];
    if (file == null) throw const SyncSkip('that didn\'t come down');
    try {
      return await store.fetch(channel, file);
    } catch (_) {
      throw const SyncSkip('that didn\'t come down');
    }
  }
}

/// This computer's synced folder: which it is, what its state line says, and when a pass runs (on choosing, when My
/// files is opened, and every few minutes while the app is open).
class FolderSync extends ChangeNotifier {
  FolderSync({Directory Function()? data, Future<SyncDrive?> Function()? drive, String? Function()? home, List<String> Function()? own, this.every = const Duration(minutes: 4), this.quiet = const Duration(seconds: 5)})
      : _data = data ?? (() => Directory('${DeskStore.defaultDir().path}${PlatformInfo.pathSeparator}folder-sync')),
        _drive = drive ?? _appDrive,
        _home = home ?? (() => PlatformInfo.environment['USERPROFILE'] ?? PlatformInfo.environment['HOME']),
        _own = own;

  /// Off hides the entry and runs nothing (GMFB-38 shipped without a device test: one switch to take it out).
  static const enabled = true;

  /// Whether folders are synced here at all: a computer's app, never a phone or a browser.
  static bool get here => enabled && !kIsWeb && (PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux);

  static final FolderSync instance = FolderSync();

  static Future<SyncDrive?> _appDrive() async {
    final c = await Drive.mine();
    return c == null ? null : StoreDrive(FilesStore.instance, c);
  }

  final Directory Function() _data;
  final Future<SyncDrive?> Function() _drive;
  final String? Function() _home;
  final List<String> Function()? _own;
  final Duration every, quiet;

  /// The app's own folders: where it keeps things, and where it keeps what came down.
  List<String> _ownFolders() {
    final own = _own;
    if (own != null) return own();
    final home = PlatformInfo.environment['HOME'];
    return [DeskStore.defaultDir().path, _data().path, if (PlatformInfo.isMacOS && home != null) '$home/Library/Caches/Ghost Messaging'];
  }

  File get _choice => File('${_data().path}${PlatformInfo.pathSeparator}choice.json');

  /// The folder synced; null where none is.
  String? get root => _root;
  String? _root;

  /// The state line: "In step.", "Syncing 3 files", "Stopped: why".
  String get line => _line;
  String _line = '';

  bool get running => _running;
  bool _running = false;
  bool _loaded = false;
  Timer? _timer;
  int _gen = 0;

  /// The last pass's report, for a test.
  SyncReport? last;

  void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final j = jsonDecode(_choice.readAsStringSync());
      if (j is Map && j['root'] is String && (j['root'] as String).isNotEmpty) _root = j['root'] as String;
    } catch (_) {}
  }

  void _save() {
    try {
      _choice.parent.createSync(recursive: true);
      _choice.writeAsStringSync(jsonEncode({'root': _root ?? ''}), flush: true);
    } catch (_) {}
  }

  /// Reads the choice and runs a pass every few minutes while the app is open.
  void start() {
    if (!here) return;
    load();
    _timer ??= Timer.periodic(every, (_) => unawaited(pass()));
  }

  /// Syncs the folder at [path] from now on: why not, in words, or null where it is taken (and a pass begins).
  String? choose(String path) {
    load();
    final at = FolderSyncEngine.resolve(path);
    if (at == null) return 'That folder isn\'t there.';
    final why = FolderSyncEngine.whyNot(at, home: _home(), own: _ownFolders());
    if (why != null) return why;
    _gen++;
    _root = at;
    _line = '';
    _save();
    notifyListeners();
    unawaited(pass());
    return null;
  }

  /// Stops syncing. Nothing is removed from the folder or from My files.
  void stop() {
    _gen++;
    _root = null;
    _line = '';
    _save();
    notifyListeners();
  }

  void _say(String line) {
    if (_line == line) return;
    _line = line;
    notifyListeners();
  }

  /// One pass, where a folder is chosen and none is running. Quiet where no account is signed in.
  Future<void> pass() async {
    load();
    final root = _root;
    if (root == null || _running) return;
    final gen = _gen;
    _running = true;
    notifyListeners();
    try {
      // Looked at again each pass: what was fine to sync when chosen may have been moved or become the home folder.
      if (FolderSyncEngine.resolve(root) != root) return _say('Stopped: the folder isn\'t there any more.');
      if (FolderSyncEngine.whyNot(root, home: _home(), own: _ownFolders()) != null) return _say('Stopped: this folder can\'t be synced.');
      final SyncDrive? drive;
      try {
        drive = await _drive();
      } catch (_) {
        return _say('Stopped: My files can\'t be reached right now.');
      }
      if (drive == null) return _say('Stopped: sign in to your Ghost account on this computer.');
      final key = crypto.sha256.convert(utf8.encode('${drive.id}\n$root')).toString().substring(0, 32);
      final engine = FolderSyncEngine(
        root: root,
        drive: drive,
        state: SyncState(File('${_data().path}${PlatformInfo.pathSeparator}$key.json')),
        quiet: quiet,
        stopped: () => _gen != gen,
        progress: (left) {
          if (_gen == gen && left > 0) _say('Syncing $left ${left == 1 ? 'file' : 'files'}');
        },
      );
      final r = await engine.run();
      last = r;
      if (_gen == gen) _say(r.line);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
