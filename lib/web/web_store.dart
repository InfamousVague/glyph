/// The notes in a browser: the library commands the phone's Rust core answers (native/src/dispatch.rs), answered by
/// the page over its own storage (shelf.dart, IndexedDB), with the same arguments and the same JSON back, so every
/// screen, the sync and the history above `CoreInvoke` are the phone's own and do not know where they are.
///
/// Matt, 2026-10-26: "update the web version of the app it's very behind". A page has no folder of Markdown files
/// and no SQLite file to index them in, so it cannot run the library's Rust (tauri/src-tauri/src/library); this is
/// that library's rules, port by port, over one JSON object a note. What a note's file would hold is held whole:
/// its words, its times, its pin and archive, its recording's phrases and its formatted version.
///
/// The library's rules kept here, each where its Rust says it:
///
/// - **A draft has no file** (`save_note`, `draft`): a new note with no words is held in memory and is not in the
///   list, and goes back to being a draft when its words are all taken out again, with nothing else set on it.
/// - **A revision is a compare-and-swap** (`update_note`): a save from a revision that is not the note's is
///   refused, and a deleted note is never written back.
/// - **A pin, an archive, a recording and a formatted version are not edits**: the note keeps its time.
/// - **A note synced in keeps its own times, revision and folder** (`apply_note`).
/// - **A command's write is kept for its undo** (library/mutations.rs), and undone only while the note is what the
///   command left.
/// - **The list is newest first, ties by id** (index.rs `rows_newest_first`), without the phrases and the formatted
///   text, which only a note asked for by id carries (`note_of`).
/// - **A note's path is the phone's**: where its file would be is asked of the browser's core (`note_path`,
///   native/web/src/paths.rs, over names.rs itself), so a note made here syncs to the file the Mac would have made.
///
/// What differs: nothing outside the page writes the notes, so nothing is scanned; a note's time is the moment the
/// page wrote it, where the phone's is its file's; and there is no folder the person chose (`library_root` is the
/// app's own, always).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/bytes.dart';
import '../core/native/core.dart';
import '../core/note.dart' show isTrashedPath, livePathOf, trashedPathOf;
import 'shelf.dart';

/// The commands [WebStore] answers. Every other one is the worker's (crypto, documents, ids) or not in a browser.
const Set<String> webStoreCommands = {
  'init',
  'list_notes',
  'get_note',
  'create_note',
  'update_note',
  'delete_note',
  'set_note_starred',
  'set_note_archived',
  'trash_note',
  'restore_note',
  'set_note_recording',
  'store_apply',
  'apply_command_mutation',
  'undo_command_mutation',
  'latest_command_mutation',
  'versions_read',
  'versions_write',
  'library_root',
  'reset_local_data',
  'sync_put_file',
  'read_file',
  'file_path',
  'file_digest',
  'file_exists',
};

/// The phone's limits on a recording (note.rs `Recording::new`).
const int _maxRecordingMs = 24 * 60 * 60 * 1000;
const int _maxSegments = 20000;
const int _maxSegmentChars = 10000;

/// A name that may become a file: 1 to 128 ASCII letters, digits, `-` and `_` (fsx.rs `plain_id`).
bool plainId(String id) => id.isNotEmpty && id.length <= 128 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

/// A picture's name as the phone keeps one (kept/images.rs `valid_name`).
bool validPictureName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  final stem = name.substring(0, dot), extension = name.substring(dot + 1);
  return stem.length <= 64 && plainId(stem) && const ['jpg', 'jpeg', 'png', 'webp'].contains(extension);
}

/// The pictures a body shows, as `![alt](image/<name>)`, in order and once each (kept/images.rs `referenced`).
List<String> picturesIn(String body) {
  final names = <String>[];
  for (final match in RegExp(r'!\[([^\]]*)\]\(image/([^)]*)\)').allMatches(body)) {
    final name = match.group(2)!;
    if (validPictureName(name) && !names.contains(name)) names.add(name);
  }
  return names;
}

class WebStore {
  WebStore._(this._shelf, this._ask, this._notes, this._now);

  /// Reads every note off [shelf] once; [ask] is the browser's core, for a note's path, a digest and an id.
  static Future<WebStore> open(Shelf shelf, CoreInvoke ask, {int Function()? now}) async {
    final notes = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in (await shelf.texts(Shelves.notes)).entries) {
      try {
        final note = jsonDecode(value);
        if (note is Map<String, Object?> && note['id'] == key) notes[key] = note;
      } catch (_) {
        // A row that will not read is no note, as a file the library cannot parse is skipped.
      }
    }
    return WebStore._(shelf, ask, notes, now ?? () => DateTime.now().millisecondsSinceEpoch);
  }

  final Shelf _shelf;
  final CoreInvoke _ask;
  final int Function() _now;

  /// The written notes, whole, by id: what the files and the index are to the phone.
  final Map<String, Map<String, Object?>> _notes;

  /// New notes with no words yet (`Library.drafts`), and the ids this run began as drafts (`drafted`).
  final Map<String, Map<String, Object?>> _drafts = {};
  final Set<String> _drafted = {};

  /// How many notes are written: what Settings' library row counts.
  int get count => _notes.length;

  /// One command, by name, with the arguments the page sent: the decoded answer, or a [CoreError] with the
  /// library's own sentence.
  Future<Object?> call(String command, Map<String, Object?> args) async {
    switch (command) {
      case 'init':
        return null;
      case 'list_notes':
        return _list();
      case 'get_note':
        return _get(_string(args, 'id'));
      case 'create_note':
        final made = await _create(_string(args, 'id'), _string(args, 'body'), _string(args, 'source'));
        if (made == null) throw const CoreError('the note id already exists');
        return made;
      case 'update_note':
        final saved = await _update(_string(args, 'id'), _string(args, 'body'), _int(args, 'expectedRevision'));
        if (saved == null) throw const CoreError('the note was deleted or changed');
        return saved;
      case 'delete_note':
        return _delete(_string(args, 'id'));
      case 'set_note_starred':
        final starred = args['starred'] == true;
        return _front(_string(args, 'id'), (note) => note['starred'] = starred);
      case 'set_note_archived':
        final at = args['archived'] == true ? _now() : null;
        return _front(_string(args, 'id'), (note) => note['archivedAt'] = at);
      // The trash as a folder (library/trash.rs): the note's path moves under `.trash/` and back, numbered where the
      // name is taken, and nothing else about the note changes.
      case 'trash_note':
        return _front(_string(args, 'id'), (note) {
          final path = note['path'] as String?;
          if (path != null && !isTrashedPath(path)) note['path'] = _freeLike(trashedPathOf(path), note['id'] as String);
        });
      case 'restore_note':
        return _front(_string(args, 'id'), (note) {
          final path = note['path'] as String?;
          if (path != null && isTrashedPath(path)) note['path'] = _freeLike(livePathOf(path)!, note['id'] as String);
        });
      case 'set_note_recording':
        return _setRecording(_string(args, 'id'), args['recordingMs'], args['segments']);
      case 'store_apply':
        final note = args['note'];
        if (note is! Map) throw const CoreError('invalid args for command `store_apply`: missing field `note`');
        return _apply(note.cast<String, Object?>());
      case 'apply_command_mutation':
        return _applyCommand(args['request']);
      case 'undo_command_mutation':
        return _undoCommand(_string(args, 'mutationId'));
      case 'latest_command_mutation':
        return _latestUndo(10 * 60 * 1000);
      case 'versions_read':
        final id = _string(args, 'id');
        return _notes.containsKey(id) ? _shelf.text(Shelves.versions, id) : null;
      case 'versions_write':
        final id = _string(args, 'id');
        if (!await _written(id)) return false;
        await _shelf.putText(Shelves.versions, id, _string(args, 'text'));
        return true;
      case 'library_root':
        return {'kind': 'app', 'path': null, 'name': null, 'reachable': true, 'notes': _notes.length, 'own': null};
      case 'reset_local_data':
        await _reset();
        return null;
      case 'sync_put_file':
        await _putFile(_string(args, 'kind'), _string(args, 'name'), base64.decode(_string(args, 'base64')));
        return null;
      case 'read_file':
        final bytes = await _readFile(_string(args, 'kind'), _string(args, 'name'));
        return bytes == null ? null : toBase64(bytes);
      case 'file_path':
        // A page has no path to give: what is kept here is read and sealed as bytes (lib/sync/device.dart).
        return null;
      case 'file_digest':
        final bytes = await _readFile(_string(args, 'kind'), _string(args, 'name'));
        return bytes == null ? null : await _ask('sha256_16', {'data': toBase64Url(bytes)});
      case 'file_exists':
        return await _readFile(_string(args, 'kind'), _string(args, 'name')) != null;
    }
    throw CoreError('Ghost.md\'s core has no command named $command.');
  }

  // --- the notes ---------------------------------------------------------------------------------------------------

  /// A note as the library answers it: whole, or as the list has it (`note_of(row, full)`).
  Map<String, Object?> _answer(Map<String, Object?> note, {bool full = true}) => {
    'id': note['id'],
    'body': note['body'] ?? '',
    'createdAt': note['createdAt'],
    'updatedAt': note['updatedAt'],
    'source': note['source'] ?? 'editor',
    'starred': note['starred'] == true,
    'archivedAt': note['archivedAt'],
    'recordingMs': note['recordingMs'],
    'segments': full ? note['segments'] : null,
    'formatted': full ? note['formatted'] : null,
    'formattedFor': note['formattedFor'],
    'formattedModel': note['formattedModel'],
    if (note['path'] != null) 'path': note['path'],
    'revision': note['revision'] ?? 1,
  };

  List<Map<String, Object?>> _list() {
    final rows = _notes.values.toList()
      ..sort((a, b) {
        final by = (b['updatedAt'] as num? ?? 0).compareTo(a['updatedAt'] as num? ?? 0);
        return by != 0 ? by : (a['id'] as String).compareTo(b['id'] as String);
      });
    return [for (final row in rows) _answer(row, full: false)];
  }

  Map<String, Object?>? _get(String id) {
    final row = _notes[id];
    if (row != null) return _answer(row);
    final draft = _drafts[id];
    return draft == null ? null : _answer(draft);
  }

  Future<void> _keep(Map<String, Object?> note) async {
    final id = note['id'] as String;
    _notes[id] = note;
    await _shelf.putText(Shelves.notes, id, jsonEncode(note));
  }

  Future<void> _forget(String id) async {
    _notes.remove(id);
    await _shelf.putText(Shelves.notes, id, null);
    await _shelf.putText(Shelves.versions, id, null);
  }

  /// Where the note's file is to be, by the phone's own rules (native/web/src/paths.rs).
  Future<String> _pathFor(String id, String body, {String? path, String? wanted}) async {
    final taken = [
      for (final MapEntry(:key, :value) in _notes.entries)
        if (key != id && value['path'] is String) value['path'] as String,
    ];
    return await _ask('note_path', {'body': body, 'path': ?path, 'wanted': ?wanted, 'taken': taken}) as String;
  }

  /// A blank note with no file, held until it has words (`draft`).
  Map<String, Object?> _draft(String id, String body, String source) {
    final now = _now();
    final draft = _drafts.putIfAbsent(id, () => _blank(id, source, now));
    draft['body'] = body;
    draft['updatedAt'] = now;
    _drafted.add(id);
    return _answer(draft);
  }

  Map<String, Object?> _blank(String id, String source, int at) => {
    'id': id,
    'body': '',
    'createdAt': at,
    'updatedAt': at,
    'source': source,
    'starred': false,
    'archivedAt': null,
    'recordingMs': null,
    'segments': null,
    'formatted': null,
    'formattedFor': null,
    'formattedModel': null,
    'revision': 1,
  };

  /// Whether a written note holds nothing a person set, so it may be a draft again (`undraftable`).
  bool _undraftable(Map<String, Object?> row) =>
      row['starred'] != true && row['archivedAt'] == null && row['recordingMs'] == null && row['segments'] == null && row['formatted'] == null;

  /// Writes [body] as the note's words (`save_note`).
  Future<Map<String, Object?>> _save(String id, String body, String source) async {
    final row = _notes[id];
    if (body.trim().isEmpty) {
      if (row == null) return _draft(id, body, source);
      if (_drafted.contains(id) && _undraftable(row)) {
        final draft = {..._blank(id, row['source'] as String? ?? source, row['createdAt'] as int? ?? _now()), 'body': body, 'updatedAt': _now()};
        _drafts[id] = draft;
        await _forget(id);
        return _answer(draft);
      }
    }
    final draft = _drafts.remove(id);
    if (row == null) {
      final made = {
        ..._blank(id, draft?['source'] as String? ?? source, draft?['createdAt'] as int? ?? _now()),
        'body': body,
        'updatedAt': _now(),
        'path': await _pathFor(id, body),
        'revision': draft?['revision'] ?? 1,
      };
      await _keep(made);
      return _answer(made);
    }
    final path = await _pathFor(id, body, path: row['path'] as String?);
    // The same words in the same file are no write, and the file keeps its time.
    if (row['body'] == body && row['path'] == path) return _answer(row);
    await _keep({...row, 'body': body, 'path': path, 'updatedAt': _now()});
    return _answer(_notes[id]!);
  }

  Future<Map<String, Object?>?> _create(String id, String body, String source) async {
    if (_notes.containsKey(id) || _drafts.containsKey(id)) return null;
    return _save(id, body, source);
  }

  Future<Map<String, Object?>?> _update(String id, String body, int expected) async {
    final current = _get(id);
    if (current == null || current['revision'] != expected) return null;
    await _save(id, body, current['source'] as String);
    final revision = expected + 1;
    final row = _notes[id];
    if (row != null) {
      await _keep({...row, 'revision': revision});
      return _answer(_notes[id]!);
    }
    final draft = _drafts[id];
    if (draft == null) return null;
    draft['revision'] = revision;
    return _answer(draft);
  }

  /// A draft pinned, archived or given a recording becomes a written note, even without words (`written`).
  Future<bool> _written(String id) async {
    if (_notes.containsKey(id)) return true;
    final draft = _drafts.remove(id);
    if (draft == null) return false;
    _drafted.remove(id);
    await _keep({...draft, 'path': await _pathFor(id, draft['body'] as String? ?? '')});
    return true;
  }

  /// Changes what the front matter holds, and not the note's time (`set_front`).
  /// [wanted], or the first of `Stem 2.md`, `Stem 3.md` … in its folder that no other note than [id] holds
  /// (`unique_name`, for a move into or out of the trash).
  String _freeLike(String wanted, String id) {
    bool taken(String path) => _notes.entries.any((entry) => entry.key != id && entry.value['path'] == path);
    if (!taken(wanted)) return wanted;
    final at = wanted.lastIndexOf('/');
    final folder = at < 0 ? '' : wanted.substring(0, at + 1);
    final name = wanted.substring(at + 1);
    final stem = name.toLowerCase().endsWith('.md') ? name.substring(0, name.length - 3) : name;
    for (var n = 2; ; n += 1) {
      final next = '$folder$stem $n.md';
      if (!taken(next)) return next;
    }
  }

  Future<Map<String, Object?>?> _front(String id, void Function(Map<String, Object?> note) change) async {
    await _written(id);
    final row = _notes[id];
    if (row == null) return null;
    final changed = {...row};
    change(changed);
    await _keep(changed);
    return _answer(changed);
  }

  Future<Map<String, Object?>?> _setRecording(String id, Object? ms, Object? segments) async {
    final checked = ms == null ? null : _recording(ms, segments ?? const []);
    if (!await _written(id)) return null;
    final row = _notes[id]!;
    await _keep({...row, 'recordingMs': checked?.$1, 'segments': checked?.$2});
    return _answer(_notes[id]!);
  }

  /// A recording's length and phrases, checked as note.rs `Recording::new` checks them.
  (int, List<Object?>) _recording(Object? ms, Object? segments) {
    final length = ms is num ? ms.toInt() : throw const CoreError('a recording needs its length');
    if (length < 0 || length > _maxRecordingMs) throw CoreError('a recording of $length ms is not a length');
    final phrases = segments is List ? segments : const <Object?>[];
    if (phrases.length > _maxSegments) throw CoreError('${phrases.length} segments is more than a recording can have');
    for (var index = 0; index < phrases.length; index += 1) {
      final one = phrases[index];
      if (one is! Map) throw CoreError('segment $index is not a phrase');
      if ((one['startMs'] as num? ?? 0) > (one['endMs'] as num? ?? 0)) throw CoreError('segment $index ends before it starts');
      if ((one['text'] as String? ?? '').runes.length > _maxSegmentChars) throw CoreError('segment $index is too long to be one phrase');
    }
    return (length, phrases);
  }

  Future<bool> _delete(String id) async {
    _drafted.remove(id);
    final row = _notes[id];
    if (row == null) return _drafts.remove(id) != null;
    await _forget(id);
    // A picture only it showed goes with it; one another note also shows is kept (dispatch.rs `delete_with_files`).
    for (final name in picturesIn(row['body'] as String? ?? '')) {
      final shown = _notes.values.any((other) => (other['body'] as String? ?? '').contains('(image/$name)'));
      if (!shown) await _shelf.putBytes(Shelves.files, 'image/$name', null);
    }
    await _shelf.putBytes(Shelves.files, 'recording/$id', null);
    return true;
  }

  /// A note exactly as another device has it (`apply_note`).
  Future<Map<String, Object?>> _apply(Map<String, Object?> note) async {
    final id = note['id'];
    final body = note['body'];
    if (id is! String || body is! String) throw const CoreError('invalid args for command `store_apply`: a note needs its id and body');
    if (note['segments'] != null) _recording(note['recordingMs'] ?? 0, note['segments']);
    _drafts.remove(id);
    _drafted.remove(id);
    final row = _notes[id];
    final wanted = note['path'] as String?;
    final path = await _pathFor(id, body, path: row?['path'] as String?, wanted: wanted);
    final kept = {
      'id': id,
      'body': body,
      'createdAt': note['createdAt'] ?? row?['createdAt'] ?? _now(),
      'updatedAt': note['updatedAt'] ?? _now(),
      'source': note['source'] ?? 'editor',
      'starred': note['starred'] == true,
      'archivedAt': note['archivedAt'],
      'recordingMs': note['recordingMs'],
      'segments': note['segments'],
      'formatted': note['formatted'],
      'formattedFor': note['formattedFor'],
      'formattedModel': note['formattedModel'],
      'path': path,
      'revision': note['revision'] ?? 1,
    };
    await _keep(kept);
    return _answer(kept);
  }

  // --- a command's write, and its undo (library/mutations.rs) --------------------------------------------------

  Future<Map<String, Object?>> _applyCommand(Object? sent) async {
    if (sent is! Map) throw const CoreError('invalid args for command `apply_command_mutation`: missing field `request`');
    final request = sent.cast<String, Object?>();
    final mutationId = request['mutationId'], noteId = request['noteId'], kind = request['kind'], source = request['source'];
    final beforeRevision = request['beforeRevision'], beforeBody = request['beforeBody'], afterBody = request['afterBody'];
    if (mutationId is! String || noteId is! String || kind is! String || source is! String || afterBody is! String) {
      throw const CoreError('invalid args for command `apply_command_mutation`: a request needs its ids, kind, source and words');
    }
    if (!plainId(mutationId) || !plainId(noteId)) throw const CoreError('a command mutation needs plain bounded ids');
    if (source != 'editor' && source != 'capture') throw const CoreError('a command mutation has an unsupported source');
    if (kind != 'append' && kind != 'create') throw const CoreError('only append and create command mutations are supported');
    if (kind == 'create' && (beforeRevision != null || beforeBody != null)) throw const CoreError('a create command cannot replace an existing note');
    if (kind == 'append' && (beforeRevision == null || beforeBody == null)) throw const CoreError('an append command needs the previewed note revision');
    final current = _get(noteId);
    final matches = switch ((current, beforeRevision)) {
      (null, null) => true,
      (final note?, final num revision) => note['revision'] == revision.toInt() && note['body'] == beforeBody,
      _ => false,
    };
    if (!matches) return {'status': 'conflict', 'current': current};
    final Map<String, Object?> note;
    if (beforeRevision is num) {
      note = await _update(noteId, afterBody, beforeRevision.toInt()) ?? (throw const CoreError('the note changed during the command'));
    } else {
      note = await _create(noteId, afterBody, source) ?? (throw const CoreError('the note id already exists'));
    }
    await _shelf.putText(
      Shelves.mutations,
      mutationId,
      jsonEncode({
        'id': mutationId,
        'noteId': noteId,
        'kind': kind,
        'beforeBody': beforeBody,
        'afterBody': afterBody,
        'beforeRevision': beforeRevision,
        'afterRevision': note['revision'],
        'createdAt': _now(),
        'undoneAt': null,
      }),
    );
    return {'status': 'applied', 'mutationId': mutationId, 'note': note};
  }

  Future<Map<String, Object?>?> _mutation(String id) async {
    final text = await _shelf.text(Shelves.mutations, id);
    if (text == null) return null;
    final said = jsonDecode(text);
    return said is Map<String, Object?> ? said : null;
  }

  Future<Map<String, Object?>> _undoCommand(String mutationId) async {
    final record = await _mutation(mutationId);
    if (record == null) return {'status': 'not-found'};
    if (record['undoneAt'] != null) return {'status': 'already-undone'};
    final noteId = record['noteId'] as String;
    final current = _get(noteId);
    if (current == null || current['revision'] != record['afterRevision'] || current['body'] != record['afterBody']) {
      return {'status': 'conflict', 'current': current};
    }
    Map<String, Object?>? note;
    final before = record['beforeBody'];
    if (before is String && record['beforeRevision'] != null) {
      note = await _update(noteId, before, (record['afterRevision'] as num).toInt());
    } else {
      await _delete(noteId);
    }
    await _shelf.putText(Shelves.mutations, mutationId, jsonEncode({...record, 'undoneAt': _now()}));
    return {'status': 'undone', 'mutationId': mutationId, 'note': note};
  }

  Future<Map<String, Object?>?> _latestUndo(int maxAgeMs) async {
    final cutoff = _now() - maxAgeMs;
    final records = [
      for (final text in (await _shelf.texts(Shelves.mutations)).values)
        if (jsonDecode(text) case final Map<String, Object?> record when record['undoneAt'] == null && (record['createdAt'] as num? ?? 0) >= cutoff) record,
    ]..sort((a, b) {
      final by = (b['createdAt'] as num).compareTo(a['createdAt'] as num);
      return by != 0 ? by : (b['id'] as String).compareTo(a['id'] as String);
    });
    for (final record in records) {
      final note = _get(record['noteId'] as String);
      if (note != null && note['revision'] == record['afterRevision'] && note['body'] == record['afterBody']) {
        return {'mutationId': record['id'], 'noteId': record['noteId'], 'kind': record['kind'], 'createdAt': record['createdAt']};
      }
    }
    return null;
  }

  // --- pictures and recordings (native/src/files.rs) -------------------------------------------------------------

  String? _fileKey(String kind, String name) => switch (kind) {
    'image' => validPictureName(name) ? 'image/$name' : null,
    'recording' => plainId(name) ? 'recording/$name' : null,
    'versions' => null,
    _ => throw CoreError('Nothing is kept as $kind.'),
  };

  Future<Uint8List?> _readFile(String kind, String name) async {
    if (kind == 'versions') {
      if (!_notes.containsKey(name)) return null;
      final text = await _shelf.text(Shelves.versions, name);
      return text == null ? null : Uint8List.fromList(utf8.encode(text));
    }
    final key = _fileKey(kind, name);
    return key == null ? null : _shelf.bytes(Shelves.files, key);
  }

  Future<void> _putFile(String kind, String name, Uint8List bytes) async {
    if (kind == 'versions') throw const CoreError('Nothing is kept as versions.');
    final key = _fileKey(kind, name);
    if (key == null) throw CoreError(kind == 'image' ? 'That picture could not be kept.' : 'That is not a recording Glyph can keep.');
    if (kind == 'recording' && (bytes.length < 12 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF')) {
      throw const CoreError('That is not a recording Glyph can keep.');
    }
    await _shelf.putBytes(Shelves.files, key, bytes);
  }

  /// Starting over: every note, picture, recording, versions file and command, gone (`reset_local_data`).
  Future<void> _reset() async {
    _notes.clear();
    _drafts.clear();
    _drafted.clear();
    for (final shelf in const [Shelves.notes, Shelves.versions, Shelves.mutations, Shelves.files, Shelves.teamDocs]) {
      await _shelf.clear(shelf);
    }
  }

  // --- arguments ---------------------------------------------------------------------------------------------------

  static String _string(Map<String, Object?> args, String field) {
    final value = args[field];
    if (value is String) return value;
    throw CoreError('invalid args: missing field `$field`');
  }

  static int _int(Map<String, Object?> args, String field) {
    final value = args[field];
    if (value is num) return value.toInt();
    throw CoreError('invalid args: missing field `$field`');
  }
}
