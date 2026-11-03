/// Each applied cleanup, recorded so it can be taken back later (docs/CLEANUP.md, "Undo and the record"; Matt,
/// 2026-11-02): when, which folder, which AI, and every change with what it was before.
///
/// **Where** (Matt, 2026-11-02, choosing "Library folder"): a personal folder's runs are kept in the Library itself,
/// `.glyph/cleanup.json` ([cleanupRunsFileFor]), beside the library's config, so they go wherever the folder goes (Back
/// up to git commits it, a folder shared between two Macs carries it, a restore brings it back) and a run can be undone
/// on another device that has the folder. An organization's runs stay in the plugin's storage on this device
/// ([cleanupRunsKey]): their before and after are a team's words, and a file in `.glyph/` is committed by Back up to
/// git whichever organizations are left out of it. So is every run where the Library has no file Dart can reach (an
/// Android folder picked in the system's picker). Each place keeps its last [CleanupRecords.most] runs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/library_config.dart' show ConfigFile, FileConfigFile;
import '../../core/library_folder.dart' show LibraryStatus;
import '../types.dart' show PluginStorage;

/// The storage key an organization's runs are kept under on this device.
const String cleanupRunsKey = 'glyph-cleanup-runs';

/// The file a personal folder's runs are kept in, inside the library's dot folder.
const String cleanupRunsFileName = 'cleanup.json';

/// The file's version.
const int cleanupRunsVersion = 1;

/// The Library's file of runs, by the library config's rules (lib/core/library_config.dart `configFileFor`): the
/// chosen folder while it can be reached, else Ghost.md's own; none for an Android folder picked in the system's
/// picker, which has no path Dart can reach.
ConfigFile? cleanupRunsFileFor(LibraryStatus status) {
  if (status.kind == 'tree') return null;
  final root = status.kind == 'folder' && status.reachable && status.path != null ? status.path : status.own;
  if (root == null || root.isEmpty) return null;
  return FileConfigFile('$root/.glyph/$cleanupRunsFileName');
}

/// What a change was.
enum CleanupChangeKind { folder, move, body, trash, archive }

/// One change a run made, with what it takes to put it back.
@immutable
class CleanupChange {
  const CleanupChange._(this.kind, {this.note, this.folder, this.path, this.from, this.to, this.before, this.after, this.revision});

  /// A folder made: [folder], at [path].
  const CleanupChange.folder(String id, String path) : this._(CleanupChangeKind.folder, folder: id, path: path);

  /// A note filed elsewhere: [from] to [to].
  const CleanupChange.move(String note, {required String? from, required String to}) : this._(CleanupChangeKind.move, note: note, from: from, to: to);

  /// A note's words: [before] and [after], [revision] the one the write left.
  const CleanupChange.body(String note, {required String before, required String after, required int revision}) : this._(CleanupChangeKind.body, note: note, before: before, after: after, revision: revision);

  /// A note put in the Trash.
  const CleanupChange.trash(String note) : this._(CleanupChangeKind.trash, note: note);

  /// A note put in the Archive.
  const CleanupChange.archive(String note) : this._(CleanupChangeKind.archive, note: note);

  final CleanupChangeKind kind;
  final String? note;
  final String? folder;
  final String? path;
  final String? from;
  final String? to;
  final String? before;
  final String? after;
  final int? revision;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'note': ?note,
        'folder': ?folder,
        'path': ?path,
        'from': ?from,
        'to': ?to,
        'before': ?before,
        'after': ?after,
        'revision': ?revision,
      };

  static CleanupChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = CleanupChangeKind.values.where((k) => k.name == json['kind']).firstOrNull;
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return switch (kind) {
      CleanupChangeKind.folder when s('folder') != null => CleanupChange.folder(s('folder')!, s('path') ?? ''),
      CleanupChangeKind.move when s('note') != null && s('to') != null => CleanupChange.move(s('note')!, from: s('from'), to: s('to')!),
      CleanupChangeKind.body when s('note') != null && s('before') != null && s('after') != null && json['revision'] is int =>
        CleanupChange.body(s('note')!, before: s('before')!, after: s('after')!, revision: json['revision'] as int),
      CleanupChangeKind.trash when s('note') != null => CleanupChange.trash(s('note')!),
      CleanupChangeKind.archive when s('note') != null => CleanupChange.archive(s('note')!),
      _ => null,
    };
  }
}

/// One applied run.
@immutable
class CleanupRecord {
  const CleanupRecord({required this.id, required this.at, required this.folderId, required this.folderPath, required this.aiName, required this.changes, this.org, this.misplaced = const [], this.undone = false});

  final String id;
  final DateTime at;
  final String folderId;
  final String folderPath;

  /// The organization the folder is in, or null for a personal folder: where the record is kept follows it.
  final String? org;
  final String aiName;
  final List<CleanupChange> changes;

  /// What was not where it should be once applied, read back.
  final List<String> misplaced;

  /// Taken back already.
  final bool undone;

  int count(CleanupChangeKind kind) => changes.where((c) => c.kind == kind).length;

  /// "4 moved · 2 retitled or tidied · 1 to the Trash".
  String get summary {
    final parts = <String>[
      if (count(CleanupChangeKind.folder) > 0) '${count(CleanupChangeKind.folder)} new ${count(CleanupChangeKind.folder) == 1 ? 'folder' : 'folders'}',
      if (count(CleanupChangeKind.move) > 0) '${count(CleanupChangeKind.move)} moved',
      if (count(CleanupChangeKind.body) > 0) '${count(CleanupChangeKind.body)} edited',
      if (count(CleanupChangeKind.trash) > 0) '${count(CleanupChangeKind.trash)} to the Trash',
      if (count(CleanupChangeKind.archive) > 0) '${count(CleanupChangeKind.archive)} archived',
    ];
    return parts.isEmpty ? 'Nothing changed' : parts.join(' · ');
  }

  CleanupRecord asUndone() => CleanupRecord(id: id, at: at, folderId: folderId, folderPath: folderPath, aiName: aiName, changes: changes, org: org, misplaced: misplaced, undone: true);

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'folder': folderId,
        'path': folderPath,
        'ai': aiName,
        'org': ?org,
        'changes': [for (final c in changes) c.toJson()],
        if (misplaced.isNotEmpty) 'misplaced': misplaced,
        if (undone) 'undone': true,
      };

  static CleanupRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'] is String ? DateTime.tryParse(json['at'] as String) : null;
    if (json['id'] is! String || at == null || json['folder'] is! String) return null;
    final changes = json['changes'];
    final misplaced = json['misplaced'];
    return CleanupRecord(
      id: json['id'] as String,
      at: at,
      folderId: json['folder'] as String,
      folderPath: json['path'] is String ? json['path'] as String : '',
      aiName: json['ai'] is String ? json['ai'] as String : '',
      org: json['org'] is String ? json['org'] as String : null,
      changes: [if (changes is List) for (final c in changes) ?CleanupChange.fromJson(c)],
      misplaced: [if (misplaced is List) for (final m in misplaced) if (m is String) m],
      undone: json['undone'] == true,
    );
  }
}

/// The records, newest first (see the library doc): a personal folder's in the Library's file once [useFile] has
/// found it, an organization's (and every one while there is no file) in the plugin's storage, or a test's memory.
class CleanupRecords extends ChangeNotifier {
  CleanupRecords({PluginStorage? storage, ConfigFile? file}) : _storage = storage, _file = file;

  final PluginStorage? _storage;
  ConfigFile? _file;
  List<CleanupRecord>? _memory;
  List<CleanupRecord> _inFile = const [];
  Future<void> _writing = Future<void>.value();

  /// The most runs each place keeps.
  static const int most = 20;

  /// The Library's file, once the root knows where the library is (null: none to be had); read at once.
  Future<void> useFile(ConfigFile? file) async {
    _file = file;
    await reread();
  }

  /// Reads the Library's file again: as it is found, and before a write, so a run written by another device sharing
  /// the folder is kept.
  Future<void> reread() async {
    _inFile = await _readFile();
    notifyListeners();
  }

  /// What was last written, for a test to wait on.
  Future<void> get written => _writing;

  Future<List<CleanupRecord>> _readFile() async {
    final file = _file;
    if (file == null) return const [];
    try {
      final text = await file.read();
      if (text == null || text.trim().isEmpty) return const [];
      final json = jsonDecode(text);
      final runs = json is Map ? json['runs'] : null;
      return [if (runs is List) for (final r in runs) ?CleanupRecord.fromJson(r)];
    } catch (_) {
      // A file that cannot be read keeps nothing; it is written again whole with the next run.
      return const [];
    }
  }

  List<CleanupRecord> get _device {
    final storage = _storage;
    if (storage == null) return _memory ?? const [];
    final raw = storage.get<Object?>(cleanupRunsKey, null);
    return [if (raw is List) for (final r in raw) ?CleanupRecord.fromJson(r)];
  }

  void _writeDevice(List<CleanupRecord> records) {
    final kept = records.take(most).toList();
    final storage = _storage;
    if (storage == null) {
      _memory = kept;
    } else {
      storage.set(cleanupRunsKey, [for (final r in kept) r.toJson()]);
    }
  }

  /// [change] made to the Library's file: read first, so another device's runs are kept, then written whole.
  void _writeFile(List<CleanupRecord> Function(List<CleanupRecord> had) change) {
    final file = _file;
    if (file == null) return;
    _inFile = change(_inFile).take(most).toList();
    _writing = _writing.then((_) async {
      try {
        final had = await _readFile();
        final mine = {for (final r in _inFile) r.id: r};
        final merged = [..._inFile, for (final r in had) if (!mine.containsKey(r.id)) r]..sort((a, b) => b.at.compareTo(a.at));
        // Undone anywhere is undone.
        final undone = {for (final r in had) if (r.undone) r.id};
        final next = [for (final r in merged.take(most)) undone.contains(r.id) && !r.undone ? r.asUndone() : r];
        await file.write(const JsonEncoder.withIndent('  ').convert({'version': cleanupRunsVersion, 'runs': [for (final r in next) r.toJson()]}));
        _inFile = next;
      } catch (failure) {
        debugPrint('[ghost] the cleanup runs were not written to the Library: $failure');
      }
    });
  }

  /// Whether [record] is kept in the Library's file: a personal folder's, where there is a file.
  bool inLibrary(CleanupRecord record) => record.org == null && _file != null;

  List<CleanupRecord> get all {
    final seen = <String>{};
    final both = [..._inFile, ..._device]..sort((a, b) => b.at.compareTo(a.at));
    return [for (final r in both) if (seen.add(r.id)) r];
  }

  /// [record] kept, first, where it belongs.
  void add(CleanupRecord record) {
    if (inLibrary(record)) {
      _writeFile((had) => [record, for (final r in had) if (r.id != record.id) r]);
    } else {
      _writeDevice([record, for (final r in _device) if (r.id != record.id) r]);
    }
    notifyListeners();
  }

  /// [id] marked as taken back, wherever it is kept.
  void markUndone(String id) {
    if (_inFile.any((r) => r.id == id)) _writeFile((had) => [for (final r in had) r.id == id ? r.asUndone() : r]);
    if (_device.any((r) => r.id == id)) _writeDevice([for (final r in _device) r.id == id ? r.asUndone() : r]);
    notifyListeners();
  }

  CleanupRecord? byId(String id) => all.where((r) => r.id == id).firstOrNull;
}
