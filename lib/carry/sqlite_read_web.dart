/// sqlite_read.dart's names in the web build, which has no `dart:ffi` and no system SQLite: nothing a browser
/// carries or imports is read with it (the Mac's carry and the Things import are the apps', docs/WEB.md), and a
/// read that is asked for anyway is the refusal a device with no such library gives.
library;

/// As sqlite_read.dart's.
class SqliteFailure implements Exception {
  const SqliteFailure(this.said);
  final String said;

  @override
  String toString() => 'SQLite: $said';
}

/// As sqlite_read.dart's, with no SQLite to read with.
class SqliteRead {
  SqliteRead._();

  static List<List<Object?>> rows(String file, String sql, {bool ownCopy = false}) => throw const SqliteFailure('there is no SQLite in a browser');
}
