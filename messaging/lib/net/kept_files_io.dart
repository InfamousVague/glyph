import 'dart:io';

import '../platform_info.dart';
import 'forward_secrecy.dart' show FsStore;
import 'kept_paths.dart';

/// Where there are files (kept_files.dart): the folder [name] is kept in on this device, out of any backup; null where
/// none can be named.
Directory? keptDir(String name) {
  try {
    final os = PlatformInfo.isAndroid
        ? 'android'
        : PlatformInfo.isIOS
            ? 'ios'
            : PlatformInfo.isMacOS
                ? 'macos'
                : PlatformInfo.isWindows
                    ? 'windows'
                    : PlatformInfo.isLinux
                        ? 'linux'
                        : '';
    final path = keptPathFor(name, os: os, data: Directory.systemTemp.parent.path, env: PlatformInfo.environment);
    return path == null ? null : Directory(path);
  } catch (_) {
    return null;
  }
}

/// The ledger's store on this device: a file for each name in [keptDir]; null where there is no such folder.
FsStore? ledgerFiles() {
  final dir = keptDir('ledger');
  return dir == null ? null : FilesFsStore(dir);
}

/// What is kept, a file for each name in [dir]: written whole each time (to a file beside it, then moved over it, so a
/// write cut short leaves the one before), and gone when written empty.
class FilesFsStore implements FsStore {
  FilesFsStore(this.dir);
  final Directory dir;

  /// The file [name] is kept in: only letters, digits, dots, dashes and underscores, and never a name of dots alone, so a
  /// name is never a path out of [dir].
  File _file(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${dir.path}${PlatformInfo.pathSeparator}${RegExp(r'^\.*$').hasMatch(safe) ? '_$safe' : safe}');
  }

  @override
  Future<String?> read(String name) async {
    final f = _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String name, String value) async {
    final f = _file(name);
    if (value.isEmpty) {
      if (await f.exists()) await f.delete();
      return;
    }
    await dir.create(recursive: true);
    final next = File('${f.path}.next');
    await next.writeAsString(value, flush: true);
    await next.rename(f.path);
  }
}
