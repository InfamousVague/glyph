import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../net/crypto.dart';
import 'file_kinds.dart';

/// One file in a Files space, as its description says (sealed in the space's log with the space's files key): what it
/// is called, how big, its type and the plain file's SHA-256, the key it is sealed with and the relay's name for its
/// blob, who added it and when, the folder it is in, and a small picture of it where it is a picture.
@immutable
class SpaceFile {
  const SpaceFile({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.sha,
    required this.key,
    required this.prefix,
    required this.by,
    required this.byName,
    required this.at,
    this.chunk = 256 * 1024,
    this.folder,
    this.thumb,
    this.width = 0,
    this.height = 0,
  });

  /// The blob's id on the relay (32 hex digits): also what each sealed chunk is bound to.
  final String id;
  final String name;

  /// The plain file's size in bytes.
  final int size;
  final String mime;

  /// The plain file's SHA-256 in hex: a download is checked against it.
  final String sha;

  /// The file's own key (32 bytes) and its chunks' nonce prefix (8 bytes).
  final Uint8List key;
  final Uint8List prefix;
  final int chunk;

  /// Who added it: their hub id (as the relay signed it, not as they said), and the name they gave.
  final String by;
  final String byName;

  /// When it was added, ms since 1970.
  final int at;

  /// The folder it is in; null for the space's top.
  final String? folder;

  /// A small PNG of it, for a picture; null for anything else.
  final Uint8List? thumb;
  final int width, height;

  FileKind get kind => FileKind.of(name, mime);
  DateTime get when => DateTime.fromMillisecondsSinceEpoch(at);

  SpaceFile copyWith({String? name, String? folder, bool clearFolder = false}) => SpaceFile(
        id: id,
        name: name ?? this.name,
        size: size,
        mime: mime,
        sha: sha,
        key: key,
        prefix: prefix,
        by: by,
        byName: byName,
        at: at,
        chunk: chunk,
        folder: clearFolder ? null : (folder ?? this.folder),
        thumb: thumb,
        width: width,
        height: height,
      );

  /// What the log's `add` carries (the [by] is the relay's, so it is not in here).
  Map<String, Object?> toJson() => {
        'id': id,
        'n': name,
        'z': size,
        'm': mime,
        'h': sha,
        'k': base64Encode(key),
        'p': base64Encode(prefix),
        if (chunk != 256 * 1024) 'c': chunk,
        'u': byName,
        'at': at,
        if (folder != null) 'd': folder,
        if (thumb != null) 'th': base64Encode(thumb!),
        if (width > 0) 'w': width,
        if (height > 0) 'ht': height,
      };

  static SpaceFile? fromJson(Object? j, {required String by, int? at}) {
    if (j is! Map) return null;
    try {
      final id = j['id'] as String;
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return null;
      final key = base64Decode(j['k'] as String);
      final prefix = base64Decode(j['p'] as String);
      if (key.length != 32 || prefix.length != 8) return null;
      final name = cleanName(j['n'] as String);
      if (name.isEmpty) return null;
      // What any member writes is checked before it is believed: a chunk size of 0, a negative one or one of gigabytes
      // (which would have the whole file held in memory before anything opens), a size past what the relay keeps, a
      // picture claiming to be 30000 px across. One that fails is no file.
      final size = (j['z'] as num).toInt();
      final chunk = (j['c'] as num?)?.toInt() ?? 256 * 1024;
      if (size < 0 || size > maxSize) return null;
      if (chunk < 4096 || chunk > 4 << 20 || chunk & (chunk - 1) != 0) return null;
      final sha = j['h'] is String ? j['h'] as String : '';
      if (sha.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
      final w = (j['w'] as num?)?.toInt() ?? 0, h = (j['ht'] as num?)?.toInt() ?? 0;
      final thumb = j['th'] is String ? base64Decode(j['th'] as String) : null;
      return SpaceFile(
        id: id,
        name: name,
        size: size,
        mime: j['m'] is String ? j['m'] as String : FileKind.mimeOf(name),
        sha: sha,
        key: key,
        prefix: prefix,
        chunk: chunk,
        by: by,
        byName: j['u'] is String ? j['u'] as String : '',
        at: (j['at'] as num?)?.toInt() ?? at ?? 0,
        folder: cleanFolder(j['d']),
        // A small picture only: one bigger than a thumbnail is is left out (the file still lists, with its mark).
        thumb: thumb != null && thumb.length <= maxThumb ? thumb : null,
        width: w >= 0 && w <= 16384 ? w : 0,
        height: h >= 0 && h <= 16384 ? h : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// The largest file a space's list believes (the relay keeps up to about 2 GB); and the largest small picture.
  static const maxSize = 4 << 30;
  static const maxThumb = 18 * 1024;

  /// A name as a file may have it, on every system it may be saved to: no slashes, no characters Windows refuses
  /// (`: < > " | ? *`), no control characters and no invisible ones (direction marks that make "invoice\u202Efdp.exe"
  /// show as "invoiceexe.pdf", zero-width spaces), no trailing dots or spaces, not a name of only dots (which would
  /// be the folder itself or the one above it), not one of Windows' device names (CON, NUL, COM1...); at most 200
  /// characters. A name with nothing left is "file".
  static String cleanName(String name) {
    var n = name.replaceAll(RegExp(r'[\p{Cc}\p{Cf}]', unicode: true), '').replaceAll(RegExp(r'[/\\:<>"|?*]'), '_').trim();
    n = n.replaceAll(RegExp(r'[. ]+$'), '');
    if (n.isEmpty || RegExp(r'^\.+$').hasMatch(n)) return 'file';
    final base = (n.contains('.') ? n.substring(0, n.indexOf('.')) : n).toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$').hasMatch(base)) n = '_$n';
    return n.length > 200 ? n.substring(0, 200) : n;
  }

  /// A folder's name, or null for none: one level, so no slashes.
  static String? cleanFolder(Object? folder) {
    if (folder is! String) return null;
    final f = cleanName(folder);
    return f.isEmpty ? null : (f.length > 80 ? f.substring(0, 80) : f);
  }
}

/// One entry of a space's log as the relay keeps it: its number, who wrote it (the relay's word, from their signature),
/// when, and what it says once opened with the files key ([FileOp.open]); a sealed entry that does not open is kept as
/// null and skipped.
@immutable
class LoggedOp {
  const LoggedOp({required this.seq, required this.by, required this.at, required this.op});
  final int seq;
  final String by;
  final int at;
  final Map<String, Object?>? op;

  Map<String, Object?> toJson() => {'s': seq, 'by': by, 'at': at, 'op': op};
  static LoggedOp? fromJson(Object? j) {
    if (j is! Map || j['s'] is! int || j['by'] is! String) return null;
    return LoggedOp(seq: j['s'] as int, by: j['by'] as String, at: (j['at'] as num?)?.toInt() ?? 0, op: (j['op'] as Map?)?.cast<String, Object?>());
  }
}

/// The operations a space's log holds, each sealed with the files key: a file added (`add`), renamed (`ren`), moved to
/// a folder (`mv`), removed (`del`), and a folder made (`dir`) or let go (`rmdir`). An older build reading a newer
/// kind skips it.
class FileOp {
  FileOp._();

  static Map<String, Object?> add(SpaceFile f) => {'t': 'add', 'f': f.toJson()};
  static Map<String, Object?> rename(String id, String name) => {'t': 'ren', 'id': id, 'n': name};
  static Map<String, Object?> move(String id, String? folder) => {'t': 'mv', 'id': id, 'd': folder};
  static Map<String, Object?> delete(String id) => {'t': 'del', 'id': id};
  static Map<String, Object?> folder(String name) => {'t': 'dir', 'd': name};
  static Map<String, Object?> unfolder(String name) => {'t': 'rmdir', 'd': name};

  static Uint8List seal(Uint8List filesKey, Map<String, Object?> op) => NetCrypto.seal(filesKey, utf8.encode(jsonEncode(op)));

  static Map<String, Object?>? open(Uint8List filesKey, List<int> sealed) {
    final clear = NetCrypto.open(filesKey, sealed);
    if (clear == null) return null;
    try {
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }
}

/// Who may do what to a space's files, as its roles say (lib/voice/roles.dart), asked of each entry as the log is read:
/// every device reads the same log under the same roster and arrives at the same list.
abstract class FilesRules {
  /// Whether [by] may add files.
  bool mayAdd(String by);

  /// Whether [by] may rename, move or remove [file]: their own, or anyone's with Manage files and a higher role, or
  /// the owner.
  bool mayChange(String by, SpaceFile file);

  /// Whether [by] may make or remove folders.
  bool mayFolder(String by);
}

/// Everyone may add and change their own; the owner may change anything (a space whose roster has not come yet).
class OwnerRules implements FilesRules {
  const OwnerRules(this.ownerId);
  final String? ownerId;
  @override
  bool mayAdd(String by) => true;
  @override
  bool mayChange(String by, SpaceFile file) => by == file.by || (ownerId != null && by == ownerId);
  @override
  bool mayFolder(String by) => true;
}

/// A space's files as its log says, read in order under [rules].
class FilesList {
  FilesList._(this.files, this.folders);

  /// By id, in the order they were added.
  final Map<String, SpaceFile> files;

  /// Folders made, by name, with the files in them besides.
  final Set<String> folders;

  static FilesList read(Iterable<LoggedOp> log, FilesRules rules) {
    final files = <String, SpaceFile>{};
    final folders = <String>{};
    // Every id ever added: a file is added once. A deleted one can't be posted again (by anyone, with its key copied
    // from the first add) to bring back what was taken out.
    final seen = <String>{};
    for (final e in log) {
      final op = e.op;
      if (op == null) continue;
      switch (op['t']) {
        case 'add':
          final f = SpaceFile.fromJson(op['f'], by: e.by, at: e.at);
          if (f != null && seen.add(f.id) && rules.mayAdd(e.by)) {
            files[f.id] = f;
            if (f.folder != null) folders.add(f.folder!);
          }
        case 'ren':
          final f = files[op['id']];
          final name = op['n'] is String ? SpaceFile.cleanName(op['n'] as String) : '';
          if (f != null && name.isNotEmpty && rules.mayChange(e.by, f)) files[f.id] = f.copyWith(name: name);
        case 'mv':
          final f = files[op['id']];
          if (f != null && rules.mayChange(e.by, f)) {
            final d = SpaceFile.cleanFolder(op['d']);
            files[f.id] = f.copyWith(folder: d, clearFolder: d == null);
            if (d != null) folders.add(d);
          }
        case 'del':
          final f = files[op['id']];
          if (f != null && rules.mayChange(e.by, f)) files.remove(f.id);
        case 'dir':
          final d = SpaceFile.cleanFolder(op['d']);
          if (d != null && rules.mayFolder(e.by)) folders.add(d);
        case 'rmdir':
          final d = SpaceFile.cleanFolder(op['d']);
          // Only an empty folder goes: what is in it stays where it is.
          if (d != null && rules.mayFolder(e.by) && !files.values.any((f) => f.folder == d)) folders.remove(d);
      }
    }
    return FilesList._(files, folders);
  }

  int get bytes => files.values.fold(0, (n, f) => n + f.size);
}

/// How a space's files are listed.
enum FilesSort {
  newest('Newest'),
  oldest('Oldest'),
  name('Name'),
  size('Size'),
  type('Type');

  const FilesSort(this.label);
  final String label;

  static FilesSort of(String? name) => values.where((s) => s.name == name).firstOrNull ?? newest;

  List<SpaceFile> apply(Iterable<SpaceFile> files) {
    final list = files.toList();
    int byName(SpaceFile a, SpaceFile b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    switch (this) {
      case newest:
        list.sort((a, b) => b.at.compareTo(a.at));
      case oldest:
        list.sort((a, b) => a.at.compareTo(b.at));
      case name:
        list.sort(byName);
      case size:
        list.sort((a, b) => b.size != a.size ? b.size.compareTo(a.size) : byName(a, b));
      case type:
        list.sort((a, b) => a.kind.index != b.kind.index ? a.kind.index.compareTo(b.kind.index) : byName(a, b));
    }
    return list;
  }
}
