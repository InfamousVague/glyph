/// Each applied cleanup, recorded so it can be taken back later (docs/CLEANUP.md, "Undo and the record"; Matt,
/// 2026-11-02): when, which folder, which AI, and every change with what it was before. Kept in the plugin's storage
/// ([cleanupRunsKey], this device's), the last [CleanupRecords.most] runs.
library;

import 'package:flutter/foundation.dart';

import '../types.dart' show PluginStorage;

/// The storage key the records are kept under.
const String cleanupRunsKey = 'glyph-cleanup-runs';

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
  const CleanupRecord({required this.id, required this.at, required this.folderId, required this.folderPath, required this.aiName, required this.changes, this.misplaced = const [], this.undone = false});

  final String id;
  final DateTime at;
  final String folderId;
  final String folderPath;
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

  CleanupRecord asUndone() => CleanupRecord(id: id, at: at, folderId: folderId, folderPath: folderPath, aiName: aiName, changes: changes, misplaced: misplaced, undone: true);

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'folder': folderId,
        'path': folderPath,
        'ai': aiName,
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
      changes: [if (changes is List) for (final c in changes) ?CleanupChange.fromJson(c)],
      misplaced: [if (misplaced is List) for (final m in misplaced) if (m is String) m],
      undone: json['undone'] == true,
    );
  }
}

/// The records, newest first, over a plugin's storage or a test's memory.
class CleanupRecords extends ChangeNotifier {
  CleanupRecords({PluginStorage? storage}) : _storage = storage;

  final PluginStorage? _storage;
  List<CleanupRecord>? _memory;

  /// The most runs kept.
  static const int most = 20;

  List<CleanupRecord> get all {
    final storage = _storage;
    if (storage == null) return _memory ?? const [];
    final raw = storage.get<Object?>(cleanupRunsKey, null);
    return [if (raw is List) for (final r in raw) ?CleanupRecord.fromJson(r)];
  }

  void _write(List<CleanupRecord> records) {
    final kept = records.take(most).toList();
    final storage = _storage;
    if (storage == null) {
      _memory = kept;
    } else {
      storage.set(cleanupRunsKey, [for (final r in kept) r.toJson()]);
    }
    notifyListeners();
  }

  /// [record] kept, first.
  void add(CleanupRecord record) => _write([record, ...all.where((r) => r.id != record.id)]);

  /// [id] marked as taken back.
  void markUndone(String id) => _write([for (final r in all) r.id == id ? r.asUndone() : r]);

  CleanupRecord? byId(String id) => all.where((r) => r.id == id).firstOrNull;
}
