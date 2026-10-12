/// An SQLite file's rows, read with the system's own SQLite: what the Mac carry reads WebKit's `localStorage` and
/// IndexedDB with (lib/carry/webkit_stores.dart). Nothing here writes a row, and the carry only ever hands it a
/// copy of a file, never the file a web view keeps (webkit_stores.dart `WebKitCopy`).
///
/// Over `dart:ffi` and `/usr/lib/libsqlite3.dylib`, which every Mac has: a dozen functions, no package. On a
/// device with no such library [SqliteRead.rows] throws, and the carry treats that as storage it could not read.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef _OpenC = Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>, Int32, Pointer<Uint8>);
typedef _OpenDart = int Function(Pointer<Uint8>, Pointer<Pointer<Void>>, int, Pointer<Uint8>);
typedef _PrepareC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Pointer<Void>>, Pointer<Pointer<Uint8>>);
typedef _PrepareDart = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<Void>>, Pointer<Pointer<Uint8>>);
typedef _HandleC = Int32 Function(Pointer<Void>);
typedef _HandleDart = int Function(Pointer<Void>);
typedef _ColumnIntC = Int32 Function(Pointer<Void>, Int32);
typedef _ColumnIntDart = int Function(Pointer<Void>, int);
typedef _ColumnInt64C = Int64 Function(Pointer<Void>, Int32);
typedef _ColumnDoubleC = Double Function(Pointer<Void>, Int32);
typedef _ColumnDoubleDart = double Function(Pointer<Void>, int);
typedef _ColumnBytesC = Pointer<Uint8> Function(Pointer<Void>, Int32);
typedef _ColumnBytesDart = Pointer<Uint8> Function(Pointer<Void>, int);
typedef _MessageC = Pointer<Uint8> Function(Pointer<Void>);
typedef _MallocC = Pointer<Uint8> Function(Int32);
typedef _MallocDart = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// A file SQLite would not read, with its own words for why.
class SqliteFailure implements Exception {
  const SqliteFailure(this.said);
  final String said;

  @override
  String toString() => 'SQLite: $said';
}

class SqliteRead {
  SqliteRead._();

  static DynamicLibrary? _opened;

  static DynamicLibrary get _library => _opened ??= DynamicLibrary.open(Platform.isMacOS || Platform.isIOS ? '/usr/lib/libsqlite3.dylib' : 'libsqlite3.so.0');

  /// Every row [sql] gives of the database at [file]: an `int`, a `double`, a `String`, a `Uint8List` or null to a
  /// column. The connection is opened read-only and closed before this returns.
  ///
  /// [ownCopy] says the file is a copy made to be read and thrown away: only then is it opened so that SQLite may
  /// fold a write-ahead log into it (a `-wal` copied without its `-shm` cannot be read otherwise). Never say it of
  /// a file anything else keeps.
  ///
  /// A column WebKit declared with its own collation (IndexedDB's `key`, `COLLATE IDBKEY`) can be read but not
  /// compared: ask for whole tables and choose rows in Dart.
  static List<List<Object?>> rows(String file, String sql, {bool ownCopy = false}) {
    final library = _library;
    final open = library.lookupFunction<_OpenC, _OpenDart>('sqlite3_open_v2');
    final prepare = library.lookupFunction<_PrepareC, _PrepareDart>('sqlite3_prepare_v2');
    final step = library.lookupFunction<_HandleC, _HandleDart>('sqlite3_step');
    final finalize = library.lookupFunction<_HandleC, _HandleDart>('sqlite3_finalize');
    final close = library.lookupFunction<_HandleC, _HandleDart>('sqlite3_close_v2');
    final columns = library.lookupFunction<_HandleC, _HandleDart>('sqlite3_column_count');
    final type = library.lookupFunction<_ColumnIntC, _ColumnIntDart>('sqlite3_column_type');
    final length = library.lookupFunction<_ColumnIntC, _ColumnIntDart>('sqlite3_column_bytes');
    final integer = library.lookupFunction<_ColumnInt64C, _ColumnIntDart>('sqlite3_column_int64');
    final real = library.lookupFunction<_ColumnDoubleC, _ColumnDoubleDart>('sqlite3_column_double');
    final blob = library.lookupFunction<_ColumnBytesC, _ColumnBytesDart>('sqlite3_column_blob');
    final text = library.lookupFunction<_ColumnBytesC, _ColumnBytesDart>('sqlite3_column_text');
    final message = library.lookupFunction<_MessageC, _MessageC>('sqlite3_errmsg');
    final malloc = library.lookupFunction<_MallocC, _MallocDart>('sqlite3_malloc');
    final free = library.lookupFunction<_FreeC, _FreeDart>('sqlite3_free');

    Pointer<Uint8> cString(String words) {
      final bytes = utf8.encode(words);
      final at = malloc(bytes.length + 1);
      if (at == nullptr) throw const SqliteFailure('no memory');
      at.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      return at;
    }

    String said(Pointer<Void> db) {
      final at = message(db);
      if (at == nullptr) return 'no words';
      var end = 0;
      while (at[end] != 0 && end < 4096) {
        end += 1;
      }
      return utf8.decode(at.asTypedList(end), allowMalformed: true);
    }

    final name = cString(file), query = cString(sql);
    final slot = malloc(16).cast<Pointer<Void>>();
    if (slot == nullptr) throw const SqliteFailure('no memory');
    slot.value = nullptr;
    (slot + 1).value = nullptr;
    Pointer<Void> db = nullptr, statement = nullptr;
    try {
      // 1: SQLITE_OPEN_READONLY, 2: SQLITE_OPEN_READWRITE (and never CREATE: a file that is not there is an error).
      final opened = open(name, slot, ownCopy ? 2 : 1, nullptr);
      db = slot.value;
      if (opened != 0) throw SqliteFailure(db == nullptr ? 'would not open ($opened)' : said(db));
      if (prepare(db, query, -1, slot + 1, nullptr) != 0) throw SqliteFailure(said(db));
      statement = (slot + 1).value;
      final out = <List<Object?>>[];
      final count = columns(statement);
      while (true) {
        final stepped = step(statement);
        if (stepped == 101) break; // SQLITE_DONE
        if (stepped != 100) throw SqliteFailure(said(db)); // not SQLITE_ROW
        out.add([
          for (var column = 0; column < count; column += 1)
            switch (type(statement, column)) {
              1 => integer(statement, column),
              2 => real(statement, column),
              3 => _text(text(statement, column), length(statement, column)),
              4 => _bytes(blob(statement, column), length(statement, column)),
              _ => null,
            },
        ]);
      }
      return out;
    } finally {
      if (statement != nullptr) finalize(statement);
      if (db != nullptr) close(db);
      free(name.cast());
      free(query.cast());
      free(slot.cast());
    }
  }

  static Uint8List _bytes(Pointer<Uint8> at, int length) => at == nullptr || length <= 0 ? Uint8List(0) : Uint8List.fromList(at.asTypedList(length));

  static String _text(Pointer<Uint8> at, int length) => utf8.decode(_bytes(at, length), allowMalformed: true);
}
