/// What Wrapped keeps (docs/WRAPPED.md, "What is kept"), Markdown-first (docs/MARKDOWN_FIRST.md: new features keep
/// their state in the files): one file in the Library's dot folder, `.glyph/wrapped.json`, beside Cleanup's runs, so a
/// backup to git, a folder shared between two Macs and a restore all carry it. Where the Library has no file Dart can
/// reach (an Android folder picked in the system's picker) it is the plugin's storage on this device instead.
///
/// What is in it:
/// - **Each note's read** ([WrappedRead]): the hash of the words it was read from, its one-line gist, its themes, and
///   whether the AI took it for stale or a gem worth finding again. A note whose words still hash the same is never
///   sent again: that is what makes a second Wrapped cheap.
/// - **The library's read**: the themes of the period, and the tidying suggested ([WrappedSuggestion]).
/// - **The run**: which period, whether a run was asked for and has not finished ([WrappedState.wanted], so it goes on
///   after the app is opened again), when it began and ended, and when the story was last seen.
/// - **What the person said**: each Keep and Dismiss, remembered by key; each Later, until when; and each change a press
///   made, as Cleanup's record, so it can be taken back ([WrappedState.records]).
///
/// It never holds a note's words, only the one-line gists and the before and after of a change pressed, which Undo
/// needs. An organization's notes are never read, so none of theirs is here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/library_config.dart' show ConfigFile, FileConfigFile;
import '../../core/library_folder.dart' show LibraryStatus;
import '../cleanup/records.dart' show CleanupRecord;
import '../types.dart' show PluginStorage;
import 'manifest.dart';
import 'stats.dart';

/// The file's name inside the Library's dot folder, and its version.
const String wrappedFileName = 'wrapped.json';
const int wrappedVersion = 1;

/// The Library's Wrapped file, by Cleanup's rule (lib/plugins/cleanup/records.dart `cleanupRunsFileFor`).
ConfigFile? wrappedFileFor(LibraryStatus status) {
  if (status.kind == 'tree') return null;
  final root = status.kind == 'folder' && status.reachable && status.path != null ? status.path : status.own;
  if (root == null || root.isEmpty) return null;
  return FileConfigFile('$root/.glyph/$wrappedFileName');
}

/// The plugin's storage as a file: where there is no Library file.
class StorageWrappedFile implements ConfigFile {
  const StorageWrappedFile(this.storage);
  final PluginStorage storage;

  @override
  Future<String?> read() async {
    final held = storage.get<Object?>(wrappedStateKey, null);
    return held is String ? held : null;
  }

  @override
  Future<void> write(String text) async => storage.set(wrappedStateKey, text);
}

/// One note as the pass read it.
@immutable
class WrappedRead {
  const WrappedRead({required this.hash, this.gist = '', this.themes = const [], this.stale = false, this.staleWhy = '', this.gem = false, this.at = 0});

  /// The hash of the words it was read from (note_decay/ai.dart `stableHash`).
  final String hash;
  final String gist;
  final List<String> themes;
  final bool stale;
  final String staleWhy;

  /// Worth finding again: the story's "the one you forgot".
  final bool gem;

  /// When it was read, in milliseconds.
  final int at;

  Map<String, Object?> toJson() => {'hash': hash, 'gist': gist, if (themes.isNotEmpty) 'themes': themes, if (stale) 'stale': true, if (staleWhy.isNotEmpty) 'staleWhy': staleWhy, if (gem) 'gem': true, 'at': at};

  static WrappedRead? fromJson(Object? json) {
    if (json is! Map || json['hash'] is! String) return null;
    final themes = json['themes'];
    return WrappedRead(
      hash: json['hash'] as String,
      gist: json['gist'] is String ? json['gist'] as String : '',
      themes: [if (themes is List) for (final t in themes) if (t is String) t],
      stale: json['stale'] == true,
      staleWhy: json['staleWhy'] is String ? json['staleWhy'] as String : '',
      gem: json['gem'] == true,
      at: json['at'] is int ? json['at'] as int : 0,
    );
  }
}

/// What a suggestion would do.
enum SuggestionKind {
  /// A note into a folder there is: [WrappedSuggestion.folderId].
  move,

  /// Notes into a new folder, [WrappedSuggestion.folderName], inside [WrappedSuggestion.parentId] (null: at the top).
  newFolder,

  /// Notes that are one note: the first kept, the others merged into it and put in the Trash.
  merge,

  /// Two notes that should link: the first given a Related line to the second.
  link,
}

/// One tidying suggestion, as the review shows it.
@immutable
class WrappedSuggestion {
  const WrappedSuggestion({required this.kind, required this.notes, this.folderId, this.folderName, this.parentId, this.why = '', this.found = false});

  final SuggestionKind kind;

  /// The notes it changes, by id: the one kept first for a merge, the one given the link first for a link.
  final List<String> notes;
  final String? folderId;
  final String? folderName;
  final String? parentId;
  final String why;

  /// Found by the app itself (the same words twice), not the AI.
  final bool found;

  /// Stable while the suggestion is the same: what Dismiss is remembered by.
  String get id => switch (kind) {
        SuggestionKind.move => 'move:${notes.join(',')}>$folderId',
        SuggestionKind.newFolder => 'folder:${parentId ?? ''}/${(folderName ?? '').toLowerCase()}:${notes.join(',')}',
        SuggestionKind.merge => 'merge:${notes.join(',')}',
        SuggestionKind.link => 'link:${notes.join('>')}',
      };

  Map<String, Object?> toJson() => {'kind': kind.name, 'notes': notes, 'folder': ?folderId, 'name': ?folderName, 'parent': ?parentId, if (why.isNotEmpty) 'why': why, if (found) 'found': true};

  static WrappedSuggestion? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = SuggestionKind.values.where((k) => k.name == json['kind']).firstOrNull;
    final notes = json['notes'];
    if (kind == null || notes is! List) return null;
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return WrappedSuggestion(kind: kind, notes: [for (final n in notes) if (n is String) n], folderId: s('folder'), folderName: s('name'), parentId: s('parent'), why: s('why') ?? '', found: json['found'] == true);
  }
}

/// Everything Wrapped keeps (see the library doc).
@immutable
class WrappedState {
  const WrappedState({
    this.period = WrappedPeriod.year,
    this.wanted = false,
    this.began,
    this.finished,
    this.seen,
    this.reads = const {},
    this.themes = const [],
    this.suggestions = const [],
    this.dismissed = const {},
    this.later = const {},
    this.records = const [],
    this.aiName,
  });

  final WrappedPeriod period;

  /// A run was asked for and has not finished: it goes on when the app is next open.
  final bool wanted;
  final DateTime? began;
  final DateTime? finished;

  /// When the story was last opened: a Wrapped finished since is fresh.
  final DateTime? seen;
  final Map<String, WrappedRead> reads;
  final List<String> themes;
  final List<WrappedSuggestion> suggestions;

  /// Keep and Dismiss, by the item's key.
  final Set<String> dismissed;

  /// Later, by note id, until when (milliseconds).
  final Map<String, int> later;

  /// Each change a press made, newest first, for Undo.
  final List<CleanupRecord> records;

  /// Who read the notes last.
  final String? aiName;

  /// The most records kept.
  static const int mostRecords = 30;

  /// Whether a Wrapped has been made.
  bool get made => finished != null;

  /// A Wrapped finished since the story was last opened.
  bool get fresh => finished != null && (seen == null || seen!.isBefore(finished!));

  WrappedState copyWith({
    WrappedPeriod? period,
    bool? wanted,
    DateTime? Function()? began,
    DateTime? Function()? finished,
    DateTime? seen,
    Map<String, WrappedRead>? reads,
    List<String>? themes,
    List<WrappedSuggestion>? suggestions,
    Set<String>? dismissed,
    Map<String, int>? later,
    List<CleanupRecord>? records,
    String? aiName,
  }) =>
      WrappedState(
        period: period ?? this.period,
        wanted: wanted ?? this.wanted,
        began: began == null ? this.began : began(),
        finished: finished == null ? this.finished : finished(),
        seen: seen ?? this.seen,
        reads: reads ?? this.reads,
        themes: themes ?? this.themes,
        suggestions: suggestions ?? this.suggestions,
        dismissed: dismissed ?? this.dismissed,
        later: later ?? this.later,
        records: records ?? this.records,
        aiName: aiName ?? this.aiName,
      );

  Map<String, Object?> toJson() => {
        'version': wrappedVersion,
        'period': period.wire,
        'wanted': wanted,
        'began': ?began?.toUtc().toIso8601String(),
        'finished': ?finished?.toUtc().toIso8601String(),
        'seen': ?seen?.toUtc().toIso8601String(),
        'ai': ?aiName,
        'themes': themes,
        'suggestions': [for (final s in suggestions) s.toJson()],
        'dismissed': (dismissed.toList()..sort()),
        'later': later,
        'reads': reads.map((id, read) => MapEntry(id, read.toJson())),
        'records': [for (final r in records) r.toJson()],
      };

  static WrappedState fromJson(Object? json) {
    if (json is! Map) return const WrappedState();
    DateTime? at(String key) => json[key] is String ? DateTime.tryParse(json[key] as String) : null;
    final reads = json['reads'], themes = json['themes'], suggestions = json['suggestions'], dismissed = json['dismissed'], later = json['later'], records = json['records'];
    return WrappedState(
      period: WrappedPeriod.of(json['period']),
      wanted: json['wanted'] == true,
      began: at('began'),
      finished: at('finished'),
      seen: at('seen'),
      aiName: json['ai'] is String ? json['ai'] as String : null,
      themes: [if (themes is List) for (final t in themes) if (t is String) t],
      suggestions: [if (suggestions is List) for (final s in suggestions) ?WrappedSuggestion.fromJson(s)],
      dismissed: {if (dismissed is List) for (final d in dismissed) if (d is String) d},
      later: {if (later is Map) for (final MapEntry(:key, :value) in later.entries) if (key is String && value is int) key: value},
      reads: {
        if (reads is Map)
          for (final MapEntry(:key, :value) in reads.entries)
            if (key is String) key: ?WrappedRead.fromJson(value),
      },
      records: [if (records is List) for (final r in records) ?CleanupRecord.fromJson(r)],
    );
  }

  String encode() => '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  static WrappedState decode(String? text) {
    if (text == null || text.trim().isEmpty) return const WrappedState();
    try {
      return fromJson(jsonDecode(text));
    } catch (_) {
      // A file that cannot be read starts afresh; it is written again whole with the next change.
      return const WrappedState();
    }
  }
}

/// The state as the app holds it: read from its file, written back whole after every change, one write at a time.
class WrappedStore extends ChangeNotifier implements ValueListenable<WrappedState> {
  WrappedStore({ConfigFile? file}) : _file = file;

  ConfigFile? _file;
  WrappedState _value = const WrappedState();
  Future<void> _writing = Future<void>.value();
  bool _read = false;

  @override
  WrappedState get value => _value;

  /// Whether the file has been read once.
  bool get read => _read;

  /// What was last written, for a test to wait on.
  Future<void> get written => _writing;

  /// The file to keep it in, once the root knows where the Library is; read at once.
  /// What was kept before (the plugin's storage, until the Library's file was found) is carried into a file that has
  /// nothing yet.
  Future<void> useFile(ConfigFile? file) async {
    final had = _value;
    _file = file;
    final text = file == null ? null : await file.read().catchError((Object _) => null);
    if (file != null && (text == null || text.trim().isEmpty) && (had.made || had.reads.isNotEmpty)) {
      set(had);
      _read = true;
      return;
    }
    await reread();
  }

  Future<void> reread() async {
    final file = _file;
    _value = file == null ? _value : WrappedState.decode(await file.read().catchError((Object _) => null));
    _read = true;
    notifyListeners();
  }

  /// Sets [next] and writes it.
  void set(WrappedState next) {
    _value = next;
    notifyListeners();
    final file = _file;
    if (file == null) return;
    final text = next.encode();
    _writing = _writing.then((_) => file.write(text)).catchError((Object failure) => debugPrint('[glyph] Wrapped was not written: $failure'));
  }

  void change(WrappedState Function(WrappedState now) change) => set(change(_value));
}
