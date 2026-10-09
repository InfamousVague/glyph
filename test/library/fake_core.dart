import 'dart:convert';

import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

/// The Rust core, as far as stage 3 asks it anything, in memory: what `CoreInvoke` answers when the real one is
/// `ghost_core` over `src-tauri/src/library/mod.rs` and the commands of `commands.rs` (docs/STAGE3.md).
///
/// What it holds to, each read from the Rust:
/// - **Ids are made once** (`create_note`: "the note id already exists"), and a save is over exactly the revision
///   read (`update_note`: "the note was deleted or changed", for a note that is gone as for one that moved on).
/// - **A blank new note is a draft with no file**: it answers to `get_note`, has no `path`, and is not in
///   `list_notes`. Its first words write `Inbox/<Title>.md`; a note this run started as a draft, with nothing else
///   set on it, goes back to being one when its words are all taken out. A draft pinned, archived, given a
///   recording or a versions file becomes a file, `Untitled.md`.
/// - **`revision`** starts at 1, goes up by one at each `update_note` (a draft's too), and is whatever
///   `store_apply` was handed.
/// - **`updatedAt` is the file's modified time**: moved by a save that changes the text, kept by a pin, an archive
///   and a recording, and the note's own under `store_apply`.
/// - **`list_notes`** is newest modified first, ties by id, with `segments` and `formatted` null; `get_note` fills
///   them from what is kept beside the note.
/// - **A title change renames the file** in its folder (`Stem.md`, then `Stem 2.md`); `store_apply` with a `path`
///   moves it there when that path is a library path and free, and writes what is kept beside the note from the
///   note it was handed, so a note from the list wipes its phrases (the trap).
/// - **`delete_note`** answers whether there was one; a draft counts.
/// - **`versions_read` / `versions_write`** keep `<path less .md>.versions`, moved and deleted with the note; a
///   write for an id nothing answers to is `false`.
/// - **`apply_command_mutation` / `undo_command_mutation`** (`library/mutations.rs`) are checked whole first
///   (`ApplyCommandRequest::into_mutation`: plain ids, a source of `editor` or `capture`, `append` with what it
///   read or `create` with nothing), apply only while the note's revision and body are what was previewed, keep
///   the change, and undo it only while the note is what the command left; anything else is a `conflict` with the
///   note as it now is.
///
/// What it does not do: read a title as `names.rs` `title_of` does in every case (it uses the app's own
/// `noteTitle`, which the two are held to by `core/titles.fixture.json` on the web), front matter in the file, a
/// folder the person chose, `latest_command_mutation`.
///
/// Answers go through JSON and back, so what a caller is handed is what crossing FFI would hand it.
class FakeCore {
  FakeCore({this.now = 1000});

  /// The clock: milliseconds. A test moves it between writes, as the Rust tests space theirs.
  int now;

  int get _now => now;

  final Map<String, _Row> _rows = {};
  final Map<String, _Row> _drafts = {};
  final Set<String> _drafted = {};
  final Map<String, String> _versions = {};

  /// The index's `command_mutations`: each applied command by its id.
  final Map<String, _Command> _commands = {};

  /// Every command asked, in order.
  final List<({String command, Map<String, Object?> args})> sent = [];

  /// Commands that fail, by name: how many more times, and with what.
  final Map<String, ({int times, String message})> _failing = {};

  /// The next [times] asks of [command] fail with [message].
  void fail(String command, {int times = 1, String message = 'database is locked'}) => _failing[command] = (times: times, message: message);

  /// How many times [command] has been asked.
  int asked(String command) => sent.where((each) => each.command == command).length;

  /// The paths of every file in the library, sorted.
  List<String> get files => [for (final row in _rows.values) row.path!]..sort();

  /// The versions files, by path.
  Map<String, String> get versionsFiles => Map.unmodifiable(_versions);

  /// Another writer in the same process (a meeting's write-up, `write_up.rs`): [body] over the note as it is, the
  /// revision moved on.
  void writeBehind(String id, String body) {
    final row = _rows[id] ?? _drafts[id];
    if (row == null) throw StateError('no note $id');
    _save(id, body, row.source);
    (_rows[id] ?? _drafts[id])!.revision += 1;
  }

  /// A file another app put in the folder, or a note from a launch ago.
  void seed(String id, String body, {String? path, int? at, String source = 'editor', bool starred = false, int? archivedAt, int revision = 1}) {
    final when = at ?? _now;
    _rows[id] = _Row(id: id, body: body, createdAt: when, modifiedAt: when, source: source)
      ..path = path ?? _free('Inbox', _stem(body))
      ..starred = starred
      ..archivedAt = archivedAt
      ..revision = revision;
  }

  /// The [CoreInvoke] a library is given.
  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) async {
    sent.add((command: command, args: args));
    // Crossing to the worker isolate and back is never the same turn.
    await Future<void>.delayed(Duration.zero);
    final failing = _failing[command];
    if (failing != null && failing.times > 0) {
      _failing[command] = (times: failing.times - 1, message: failing.message);
      throw CoreError(failing.message);
    }
    final Object? answer = _answer(command, jsonDecode(jsonEncode(args)) as Map<String, Object?>);
    return jsonDecode(jsonEncode(answer));
  }

  Object? _answer(String command, Map<String, Object?> args) {
    String text(String key) {
      final value = args[key];
      if (value is! String) throw CoreError('invalid args `$key` for command `$command`');
      return value;
    }

    switch (command) {
      case 'init':
        return null;
      case 'library_root':
        return {'own': true, 'folder': null};
      case 'list_notes':
        final rows = _rows.values.toList()..sort((a, b) => b.modifiedAt != a.modifiedAt ? b.modifiedAt.compareTo(a.modifiedAt) : a.id.compareTo(b.id));
        return [for (final row in rows) row.json(full: false)];
      case 'get_note':
        return (_rows[text('id')] ?? _drafts[text('id')])?.json(full: true);
      case 'create_note':
        final id = text('id');
        if (_rows.containsKey(id) || _drafts.containsKey(id)) throw const CoreError('the note id already exists');
        return _save(id, text('body'), text('source')).json(full: true);
      case 'update_note':
        final id = text('id');
        final current = _rows[id] ?? _drafts[id];
        final expected = args['expectedRevision'];
        if (expected is! int) throw CoreError('invalid args `expectedRevision` for command `$command`');
        if (current == null || current.revision != expected) throw const CoreError('the note was deleted or changed');
        final saved = _save(id, text('body'), current.source);
        saved.revision = expected + 1;
        return saved.json(full: true);
      case 'delete_note':
        return _delete(text('id'));
      case 'set_note_starred':
        return _front(text('id'), (row) => row.starred = args['starred'] == true);
      case 'set_note_archived':
        return _front(text('id'), (row) => row.archivedAt = args['archived'] == true ? _now : null);
      case 'set_note_recording':
        final id = text('id');
        if (!_written(id)) return null;
        final row = _rows[id]!;
        final ms = args['recordingMs'];
        row.recordingMs = ms is int ? ms : null;
        row.segments = ms is int ? ((args['segments'] as List?) ?? const []) : null;
        return row.json(full: true);
      case 'store_apply':
        return _apply(args['note']).json(full: true);
      case 'apply_command_mutation':
        return _applyCommand(args['request']);
      case 'undo_command_mutation':
        return _undoCommand(text('mutationId'));
      case 'versions_read':
        final row = _rows[text('id')];
        return row == null ? null : _versions[_versionsPath(row.path!)];
      case 'versions_write':
        final id = text('id');
        if (!_written(id)) return false;
        _versions[_versionsPath(_rows[id]!.path!)] = text('text');
        return true;
      default:
        throw CoreError('unknown command `$command`');
    }
  }

  // ---- library/mutations.rs -----------------------------------------------------------------------------------------

  /// `fsx::plain_id`: 1 to 128 ASCII letters, digits, `-` and `_`.
  static bool _plainId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);

  /// `ApplyCommandRequest::into_mutation`, then `apply_command`.
  Object? _applyCommand(Object? raw) {
    const fields = {'mutationId', 'noteId', 'kind', 'beforeRevision', 'beforeBody', 'afterBody', 'source'};
    if (raw is! Map) throw const CoreError('invalid args `request` for command `apply_command_mutation`');
    for (final key in raw.keys) {
      if (!fields.contains(key)) throw CoreError('invalid args `request` for command `apply_command_mutation`: unknown field `$key`');
    }
    final mutationId = raw['mutationId'], noteId = raw['noteId'], kind = raw['kind'], source = raw['source'], after = raw['afterBody'];
    final beforeRevision = raw['beforeRevision'], beforeBody = raw['beforeBody'];
    if (mutationId is! String || noteId is! String || kind is! String || source is! String || after is! String || beforeRevision is! int? || beforeBody is! String?) {
      throw const CoreError('invalid args `request` for command `apply_command_mutation`');
    }
    if (!_plainId(mutationId) || !_plainId(noteId)) throw const CoreError('a command mutation needs plain bounded ids');
    if (source != 'editor' && source != 'capture') throw const CoreError('a command mutation has an unsupported source');
    if (kind != 'append' && kind != 'create') throw const CoreError('only append and create command mutations are supported');
    if (kind == 'create' && (beforeRevision != null || beforeBody != null)) throw const CoreError('a create command cannot replace an existing note');
    if (kind == 'append' && (beforeRevision == null || beforeBody == null)) throw const CoreError('an append command needs the previewed note revision');

    final current = _rows[noteId] ?? _drafts[noteId];
    final matches = current == null ? beforeRevision == null : beforeRevision != null && current.revision == beforeRevision && current.body == beforeBody;
    if (!matches) return {'status': 'conflict', 'current': current?.json(full: true)};
    final saved = _save(noteId, after, current?.source ?? source);
    if (beforeRevision != null) saved.revision = beforeRevision + 1;
    _commands[mutationId] = _Command(noteId: noteId, beforeBody: beforeBody, afterBody: after, beforeRevision: beforeRevision, afterRevision: saved.revision);
    return {'status': 'applied', 'mutationId': mutationId, 'note': saved.json(full: true)};
  }

  /// `undo_command`: only while the command's exact result is still current.
  Object? _undoCommand(String mutationId) {
    final record = _commands[mutationId];
    if (record == null) return {'status': 'not-found'};
    if (record.undone) return {'status': 'already-undone'};
    final current = _rows[record.noteId] ?? _drafts[record.noteId];
    if (current == null || current.revision != record.afterRevision || current.body != record.afterBody) {
      return {'status': 'conflict', 'current': current?.json(full: true)};
    }
    Object? note;
    final before = record.beforeBody;
    if (before != null && record.beforeRevision != null) {
      final saved = _save(record.noteId, before, current.source);
      saved.revision = record.afterRevision + 1;
      note = saved.json(full: true);
    } else {
      _delete(record.noteId);
    }
    record.undone = true;
    return {'status': 'undone', 'mutationId': mutationId, 'note': note};
  }

  // ---- library/mod.rs ---------------------------------------------------------------------------------------------

  /// `delete_note`: whether there was one; a draft counts.
  bool _delete(String id) {
    _drafted.remove(id);
    final row = _rows.remove(id);
    if (row == null) return _drafts.remove(id) != null;
    _versions.remove(_versionsPath(row.path!));
    return true;
  }

  /// `save_note`: writes [body] as the note's text. A new id is a new file in `Inbox/`.
  _Row _save(String id, String body, String source) {
    final blank = body.trim().isEmpty;
    final row = _rows[id];
    if (blank) {
      if (row == null) return _draft(id, body, source);
      if (_drafted.contains(id) && row.undraftable) {
        _rows.remove(id);
        _versions.remove(_versionsPath(row.path!));
        final draft = _draft(id, body, source)
          ..source = row.source
          ..createdAt = row.createdAt;
        return draft;
      }
    }
    final draft = _drafts.remove(id);
    final stem = _stem(body);
    if (row == null) {
      final made = _Row(id: id, body: body, createdAt: draft?.createdAt ?? _now, modifiedAt: _now, source: draft?.source ?? source)
        ..path = _free('Inbox', stem)
        ..revision = draft?.revision ?? 1;
      return _rows[id] = made;
    }
    if (!_namedFor(row.path!, stem)) _rename(row, _free(_folderOf(row.path!), stem));
    if (row.body != body) {
      row.body = body;
      row.modifiedAt = _now;
    }
    return row;
  }

  /// `draft`: a blank note with no file, held until it has words.
  _Row _draft(String id, String body, String source) {
    final draft = _drafts.putIfAbsent(id, () => _Row(id: id, body: '', createdAt: _now, modifiedAt: _now, source: source));
    draft.body = body;
    draft.modifiedAt = _now;
    _drafted.add(id);
    return draft;
  }

  /// `written`: a draft pinned, archived or given a recording becomes a file, even without words.
  bool _written(String id) {
    if (_rows.containsKey(id)) return true;
    final draft = _drafts.remove(id);
    if (draft == null) return false;
    _drafted.remove(id);
    _rows[id] = draft
      ..path = _free('Inbox', _stem(draft.body))
      ..modifiedAt = _now;
    return true;
  }

  /// `set_front`: front matter only, the file's modified time kept.
  Object? _front(String id, void Function(_Row row) change) {
    _written(id);
    final row = _rows[id];
    if (row == null) return null;
    change(row);
    return row.json(full: true);
  }

  /// `apply_note`: a note exactly as another device has it.
  _Row _apply(Object? raw) {
    if (raw is! Map) throw const CoreError('invalid args `note` for command `store_apply`');
    for (final field in ['id', 'body', 'createdAt', 'updatedAt', 'source']) {
      if (raw[field] == null) throw CoreError('invalid args `note` for command `store_apply`: missing field `$field`');
    }
    final id = raw['id'] as String, body = raw['body'] as String;
    final segments = raw['segments'] as List?;
    if (segments != null) {
      for (final (index, segment) in segments.indexed) {
        if (((segment as Map)['startMs'] as int) > (segment['endMs'] as int)) throw CoreError('segment $index ends before it starts');
      }
    }
    _drafts.remove(id);
    _drafted.remove(id);
    final stem = _stem(body);
    final asked = raw['path'];
    final wanted = asked is String && _libraryPath(asked) ? asked : null;
    final row = _rows[id] ??= _Row(id: id, body: body, createdAt: 0, modifiedAt: 0, source: 'editor')..path = _free(wanted == null ? 'Inbox' : _folderOf(wanted), stem);
    if (wanted != null && wanted != row.path && !_exists(wanted)) {
      _rename(row, wanted);
    } else if (!_namedFor(row.path!, stem)) {
      _rename(row, _free(_folderOf(row.path!), stem));
    }
    row
      ..body = body
      ..createdAt = raw['createdAt'] as int
      ..modifiedAt = raw['updatedAt'] as int
      ..source = raw['source'] as String
      ..starred = raw['starred'] == true
      ..archivedAt = raw['archivedAt'] as int?
      // The sidecar is written from the note as it came: what the note does not carry is gone.
      ..recordingMs = raw['recordingMs'] as int?
      ..segments = segments
      ..formatted = raw['formatted'] as String?
      ..formattedFor = raw['formattedFor'] as int?
      ..formattedModel = raw['formattedModel'] as String?
      ..revision = raw['revision'] is int ? raw['revision'] as int : 1;
    return row;
  }

  void _rename(_Row row, String to) {
    final was = _versionsPath(row.path!), now = _versionsPath(to);
    final kept = _versions.remove(was);
    if (kept != null) _versions[now] = kept;
    row.path = to;
  }

  bool _exists(String path) => _rows.values.any((row) => row.path == path);

  /// `free_path`: `Stem.md`, or `Stem 2.md` and on while those are taken.
  String _free(String folder, String stem) {
    String at(String name) => folder.isEmpty ? name : '$folder/$name';
    if (!_exists(at('$stem.md'))) return at('$stem.md');
    for (var n = 2;; n += 1) {
      if (!_exists(at('$stem $n.md'))) return at('$stem $n.md');
    }
  }

  static String _folderOf(String path) {
    final at = path.lastIndexOf('/');
    return at < 0 ? '' : path.substring(0, at);
  }

  /// `library_path`: relative, `.md`, no dot folders or `..`.
  static bool _libraryPath(String path) => path.toLowerCase().endsWith('.md') && path.split('/').every((part) => part.isNotEmpty && !part.startsWith('.'));

  /// `named_for`: `Stem.md`, or `Stem 2.md` for a clash.
  static bool _namedFor(String path, String stem) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    if (!name.toLowerCase().endsWith('.md')) return false;
    final bare = name.substring(0, name.length - 3);
    if (bare == stem) return true;
    return bare.startsWith('$stem ') && RegExp(r'^\d+$').hasMatch(bare.substring(stem.length + 1));
  }

  static String _versionsPath(String path) => '${path.toLowerCase().endsWith('.md') ? path.substring(0, path.length - 3) : path}.versions';

  /// `file_stem(title_of(body))` (names.rs): the title as a file name without its extension.
  static String _stem(String body) {
    final cleaned = noteTitle(body).replaceAll(RegExp(r'[/\\:*?"<>|#^\[\]]|[\x00-\x1f\x7f]'), '').replaceAll('**', '').replaceAll('__', '');
    var stem = cleaned.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');
    if (stem.runes.length > 80) {
      final cut = String.fromCharCodes(stem.runes.take(80));
      final at = cut.lastIndexOf(' ');
      stem = at > 40 ? cut.substring(0, at) : cut;
    }
    stem = stem.replaceAll(RegExp(r'[. ]+$'), '').replaceAll(RegExp(r'^\.+'), '').trim();
    return stem.isEmpty ? 'Untitled' : stem;
  }
}

/// A row of `command_mutations`: what a command changed, and whether it was taken back.
class _Command {
  _Command({required this.noteId, required this.beforeBody, required this.afterBody, required this.beforeRevision, required this.afterRevision});

  final String noteId;
  final String? beforeBody;
  final String afterBody;
  final int? beforeRevision;
  final int afterRevision;
  bool undone = false;
}

class _Row {
  _Row({required this.id, required this.body, required this.createdAt, required this.modifiedAt, required this.source});

  final String id;
  String body;
  int createdAt;
  int modifiedAt;
  String source;
  bool starred = false;
  int? archivedAt;
  int? recordingMs;
  List<Object?>? segments;
  String? formatted;
  int? formattedFor;
  String? formattedModel;

  /// Null for a draft.
  String? path;
  int revision = 1;

  /// `undraftable`: nothing a person set on it.
  bool get undraftable => !starred && archivedAt == null && recordingMs == null && segments == null && formatted == null;

  Map<String, Object?> json({required bool full}) => {
        'id': id,
        'body': body,
        'createdAt': createdAt,
        'updatedAt': modifiedAt,
        'source': source,
        'starred': starred,
        'archivedAt': archivedAt,
        'recordingMs': recordingMs,
        'segments': full ? segments : null,
        'formatted': full ? formatted : null,
        'formattedFor': formattedFor,
        'formattedModel': formattedModel,
        if (path != null) 'path': path,
        'revision': revision,
      };
}
