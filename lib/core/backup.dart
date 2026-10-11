/// Backup: every note, onto a removable drive, as plain files under a `Ghost.md` folder on its root (docs/DESIGN.md
/// §204 and §213 of tauri/; Matt: "add a section to the settings called "Backup" it should prompt the user to
/// plugin a removable drive to backup all the notes in the app to workspace folders and such under a Ghost.md folder
/// on the root of the drive"). A port of `src/app/core/backup.ts`.
///
/// The drives are Android's removable volumes (android/…/glyph/files/BackupDrives.kt), asked again every two seconds
/// while Settings › Backup is open, so a drive plugged in shows up by itself. A drive is allowed once, through the
/// system's own picker opened on its root, and is remembered. The writing is Rust's (the Tauri app's backup.rs, included
/// whole in native/): the notes by their workspace folders, each note's versions file beside it, the pictures, films
/// and recordings under Attachments/, and a second backup to the same drive writes only what changed.
///
/// What differs:
/// - The page's imports (`invoke`, `listenTo`, `window.GlyphHost.backupDrives` and `chooseBackupDrive` with its
///   `backupDrive` answer, the platform) are one value, [Backups], which the app's root makes from the core it
///   already holds ([Backups.overCore]) and a test makes from fakes.
/// - **The picker is one call**, as the library folder's is (lib/core/library_folder.dart): `chooseBackupDrive` on
///   `ghost_md/files` answers the picker's JSON when the picker does.
/// - **The backup is a job** (native/src/kept/backup_commands.rs): `backup_run` answers an id at once and the core
///   says the rest as events, where the page's `invoke` waited. [CoreBackupRun] is that pair as the one future
///   the page had; `backup://progress` is heard as the page heard it.
/// - **No generation to wait for** (`BACKUP_GENERATION` 26, `BACKUP_FILES_GENERATION` 27): the Dart and the core
///   are one build, so `update` is only an Android run with no drives behind the channel.
/// - **The Mac app's drives are the core's**, as the Tauri app's are (`backup_drives`, `backup_eject`,
///   native/src/kept/backup_commands.rs): the removable mounts under `/Volumes`, each written by its path with
///   nothing to allow first, and put away by Eject. Windows' drives are not ported, and outside the Mac app (a
///   test, a desktop run) [Backups.way] answers `none`; [BackupWay.windows] is kept for the day they are.
/// - **Dates are written in English**, in the phone's own order and clock once it has said which
///   (lib/core/locale_dates.dart, the page's own answers for en-US and en-GB), and until then as a browser set to
///   English (United States) writes them (lib/notes/when.dart says the same of its days).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library_folder.dart' show filesChannel;
import 'locale_dates.dart';
import 'mac_app.dart';
import 'native/core.dart';
import 'native/events.dart';

/// The native generation with the backup's commands and Android's drives (`BACKUP_GENERATION`), and the one with
/// `backup_files` (`BACKUP_FILES_GENERATION`): kept for the record, nothing here waits for either.
const int backupGeneration = 26;
const int backupFilesGeneration = 27;

/// Where a backup can go from here: the Mac's drives, Windows', Android's, an app to update first, or nowhere
/// (`BackupWay`).
enum BackupWay { mac, windows, android, update, none }

/// The last backup a drive holds (`LastBackup`).
@immutable
class LastBackup {
  const LastBackup({required this.backedUpAt, required this.notes});
  final String backedUpAt;
  final int notes;

  @override
  bool operator ==(Object other) => other is LastBackup && other.backedUpAt == backedUpAt && other.notes == notes;

  @override
  int get hashCode => Object.hash(backedUpAt, notes);

  @override
  String toString() => 'LastBackup($backedUpAt, $notes)';
}

/// A drive plugged in now (`BackupDrive`).
@immutable
class BackupDrive {
  const BackupDrive({required this.id, required this.name, this.free, this.total, this.tree, this.last});

  /// The Mac's path under /Volumes, or Android's volume id.
  final String id;
  final String name;
  final int? free;
  final int? total;

  /// Android: the drive's tree Ghost.md may write, once the person has allowed it; never on the Mac.
  final String? tree;
  final LastBackup? last;

  BackupDrive withTree(String tree) => BackupDrive(id: id, name: name, free: free, total: total, tree: tree, last: last);
  BackupDrive withLast(LastBackup? last) => BackupDrive(id: id, name: name, free: free, total: total, tree: tree, last: last);

  @override
  bool operator ==(Object other) => other is BackupDrive && other.id == id && other.name == name && other.free == free && other.total == total && other.tree == tree && other.last == last;

  @override
  int get hashCode => Object.hash(id, name, free, total, tree, last);

  @override
  String toString() => 'BackupDrive($id, $name, free $free, total $total, tree $tree, $last)';
}

/// How far a backup has got: bytes and files (`BackupProgress`).
@immutable
class BackupProgress {
  const BackupProgress({this.done = 0, this.total = 0, this.files = 0, this.of = 0});

  factory BackupProgress.fromJson(Map<String, Object?> json) => BackupProgress(done: _int(json['done']) ?? 0, total: _int(json['total']) ?? 0, files: _int(json['files']) ?? 0, of: _int(json['of']) ?? 0);

  final int done;
  final int total;
  final int files;
  final int of;
}

/// What a backup did (`Backed`).
@immutable
class Backed {
  const Backed({this.notes = 0, this.files = 0, this.written = 0, this.unchanged = 0, this.removed = 0, this.bytes = 0});

  factory Backed.fromJson(Map<String, Object?> json) => Backed(
        notes: _int(json['notes']) ?? 0,
        files: _int(json['files']) ?? 0,
        written: _int(json['written']) ?? 0,
        unchanged: _int(json['unchanged']) ?? 0,
        removed: _int(json['removed']) ?? 0,
        bytes: _int(json['bytes']) ?? 0,
      );

  final int notes;
  final int files;
  final int written;
  final int unchanged;
  final int removed;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is Backed && other.notes == notes && other.files == files && other.written == written && other.unchanged == unchanged && other.removed == removed && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(notes, files, written, unchanged, removed, bytes);
}

/// A finite number as a whole one, or null (`num`).
int? _int(Object? value) => value is num && value.isFinite ? value.toInt() : null;

LastBackup? _lastOf(Object? value) {
  if (value is! Map) return null;
  final at = value['backedUpAt'];
  return at is String && at.isNotEmpty ? LastBackup(backedUpAt: at, notes: _int(value['notes']) ?? 0) : null;
}

/// Android's drives as the activity says them (BackupDrives.kt `drives`): nothing readable is no drives
/// (`readAndroidDrives`).
List<BackupDrive> readAndroidDrives(String json) {
  Object? said;
  try {
    said = jsonDecode(json);
  } catch (_) {
    return const [];
  }
  if (said is! List) return const [];
  return [
    for (final drive in said)
      if (drive is Map && drive['id'] is String && (drive['id'] as String).isNotEmpty)
        BackupDrive(
          id: drive['id'] as String,
          name: drive['name'] is String && (drive['name'] as String).isNotEmpty ? drive['name'] as String : drive['id'] as String,
          free: _int(drive['free']),
          total: _int(drive['total']),
          tree: drive['tree'] is String && (drive['tree'] as String).isNotEmpty ? drive['tree'] as String : null,
        ),
  ];
}

/// What the drive's picker answered (`DriveAnswer`).
sealed class DriveAnswer {
  const DriveAnswer();
}

class DriveAllowed extends DriveAnswer {
  const DriveAllowed(this.tree);
  final String tree;

  @override
  bool operator ==(Object other) => other is DriveAllowed && other.tree == tree;

  @override
  int get hashCode => tree.hashCode;
}

class DriveCancelled extends DriveAnswer {
  const DriveCancelled();

  @override
  bool operator ==(Object other) => other is DriveCancelled;

  @override
  int get hashCode => (DriveCancelled).hashCode;
}

class DriveRefused extends DriveAnswer {
  const DriveRefused(this.error);
  final String error;

  @override
  bool operator ==(Object other) => other is DriveRefused && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// The picker's answer read (`readDriveAnswer`).
DriveAnswer readDriveAnswer(String json) {
  const unread = DriveRefused('That drive can’t be written to.');
  Object? said;
  try {
    said = jsonDecode(json);
  } catch (_) {
    return unread;
  }
  if (said is! Map) return unread;
  if (said['cancelled'] == true) return const DriveCancelled();
  final error = said['error'], tree = said['tree'];
  if (error is String) return DriveRefused(error);
  if (tree is String && tree.isNotEmpty) return DriveAllowed(tree);
  return unread;
}

String _two(int n) => n.toString().padLeft(2, '0');
int _hour12(DateTime at) => at.hour % 12 == 0 ? 12 : at.hour % 12;
const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A moment as the page's `toLocaleString()` says it in English: "10/5/2026, 8:00:00 PM", and "05/10/2026,
/// 20:00:00" once a British phone has said it is one.
String _localeString(DateTime at) =>
    toldDate(at, DateForm.whole) ?? '${at.month}/${at.day}/${at.year}, ${_hour12(at)}:${_two(at.minute)}:${_two(at.second)} ${at.hour < 12 ? 'AM' : 'PM'}';

/// What the README on the drive says (`backupReadme`).
String backupReadme(DateTime at) => [
      'Ghost.md, backed up ${_localeString(at.toLocal())}',
      '',
      'Every note Ghost.md keeps, as Markdown (.md) files you can open in any text editor or in Obsidian.',
      '',
      'Inbox/            Notes in no workspace.',
      'Workspaces/       A folder for each of your workspaces.',
      'Organizations/    A folder for each organization you are in, with its notes.',
      'Attachments/      The pictures, films and recordings the notes show and play.',
      '',
      'A .versions file beside a note is its version history. .ghostmd-backup.json is what the last backup',
      'wrote, so the next backup to this drive only writes what changed. A note deleted in the app is taken',
      'off at the next backup; nothing else in this folder is ever touched.',
      '',
    ].join('\n');

/// A moment as JavaScript's `toISOString` writes it: UTC, to the millisecond, with a `Z`.
String isoInstant(DateTime at) {
  final utc = at.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-${_two(utc.month)}-${_two(utc.day)}T${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}.${utc.millisecond.toString().padLeft(3, '0')}Z';
}

/// One file the drive's Ghost.md folder holds: its path under the folder, and its size (`HeldFile`).
@immutable
class HeldFile {
  const HeldFile(this.path, this.size);
  final String path;
  final int size;

  @override
  bool operator ==(Object other) => other is HeldFile && other.path == path && other.size == size;

  @override
  int get hashCode => Object.hash(path, size);

  @override
  String toString() => 'HeldFile($path, $size)';
}

/// The files `backup_files` answered, read: nothing readable is left out.
List<HeldFile> readHeldFiles(Object? said) {
  if (said is! List) return const [];
  return [
    for (final file in said)
      if (file is Map && file['path'] is String && (file['path'] as String).isNotEmpty) HeldFile(file['path'] as String, _int(file['size']) ?? 0),
  ];
}

/// A backup under way: how it ends, and what it says meanwhile. The page had `invoke('backup_run')` and a listener.
typedef BackupRun = Future<Backed> Function(Map<String, Object?> request, void Function(BackupProgress progress) onProgress);

/// `backup_run` over the core: the job started, `backup://progress` heard until it ends, and its end as the
/// answer or the core's own sentence.
BackupRun coreBackupRun({required Future<CoreJob> Function(String command, [Map<String, Object?> args]) startJob, required Stream<CoreEvent> events}) {
  return (request, onProgress) async {
    final heard = events.where((event) => event.event == 'backup://progress').listen((event) => onProgress(BackupProgress.fromJson(event.map)));
    try {
      final job = await startJob('backup_run', {'request': request});
      final said = await job.done;
      return Backed.fromJson(said is Map ? said.cast<String, Object?>() : const {});
    } finally {
      await heard.cancel();
    }
  };
}

/// The backup as the app reaches it: the page's imports, as one value (see the header).
class Backups {
  Backups({required CoreInvoke invoke, required BackupRun run, Future<String> Function()? drives, Future<String> Function(String id)? chooseDrive, TargetPlatform? platform, bool? macApp})
      : _invoke = invoke,
        _run = run,
        _platform = platform,
        _drives = drives,
        _macApp = macApp ?? runsAsMacApp,
        _chooseDrive = chooseDrive;

  /// Over the app's own core and the phone's own drives.
  factory Backups.overCore({required CoreInvoke invoke, required Future<CoreJob> Function(String command, [Map<String, Object?> args]) startJob, required Stream<CoreEvent> events, TargetPlatform? platform}) =>
      Backups(
        invoke: invoke,
        run: coreBackupRun(startJob: startJob, events: events),
        platform: platform,
        drives: (platform ?? defaultTargetPlatform) == TargetPlatform.android ? drivesOnPhone : null,
        chooseDrive: chooseDriveOnPhone,
      );

  final CoreInvoke _invoke;
  final BackupRun _run;
  final TargetPlatform? _platform;

  /// `GlyphHost.backupDrives`: the drives plugged in now, as the activity's JSON. Null is a shell without them.
  final Future<String> Function()? _drives;

  /// Whether this is the Mac app, whose core lists a Mac's drives (lib/core/mac_app.dart): never in a test on a Mac.
  final bool _macApp;

  /// `GlyphHost.chooseBackupDrive`, answering what its `backupDrive` event said.
  final Future<String> Function(String id)? _chooseDrive;

  TargetPlatform get _device => _platform ?? defaultTargetPlatform;

  /// Where a backup can go from here (`backupWay`).
  Future<BackupWay> way() async {
    if (_device == TargetPlatform.iOS) return BackupWay.none;
    if (_device == TargetPlatform.android) return _drives != null ? BackupWay.android : BackupWay.update;
    // The Mac app's core lists the Mac's drives (see the header); no other desktop has them yet.
    if (_device == TargetPlatform.macOS && _macApp) return BackupWay.mac;
    return BackupWay.none;
  }

  /// The drives plugged in now, each with the last backup it holds where that can be read (`listDrives`).
  Future<List<BackupDrive>> listDrives(BackupWay way) async {
    if (way == BackupWay.mac || way == BackupWay.windows) {
      final drives = await _invoke('backup_drives');
      return [
        for (final drive in drives is List ? drives : const <Object?>[])
          if (drive is Map) BackupDrive(id: '${drive['id']}', name: '${drive['name']}', free: _int(drive['free']), total: _int(drive['total']), last: _lastOf(drive['last'])),
      ];
    }
    if (way != BackupWay.android) return const [];
    final drives = readAndroidDrives(await _drives?.call() ?? '[]');
    return Future.wait([
      for (final drive in drives)
        if (drive.tree == null)
          Future.value(drive)
        else
          _invoke('backup_last', {'tree': drive.tree}).then<Object?>((last) => last, onError: (Object _) => null).then((last) => drive.withLast(_lastOf(last))),
    ]);
  }

  /// Whether the person has yet to let Ghost.md write [drive]: an Android drive with no tree. A Mac's drive is
  /// written by its path, with nothing to allow.
  bool needsAllowing(BackupWay way, BackupDrive drive) => way == BackupWay.android && drive.tree == null;

  /// Android: the person asked, once, to let Ghost.md write the drive (`allowDrive`).
  Future<DriveAnswer> allowDrive(String id) async {
    final choose = _chooseDrive;
    if (choose == null) return const DriveRefused('This phone has no way to choose a drive.');
    return readDriveAnswer(await choose(id));
  }

  /// The backup onto [drive], telling how far it has got (`runBackup`).
  Future<Backed> runBackup(BackupWay way, BackupDrive drive, void Function(BackupProgress progress) onProgress, {DateTime? at}) async {
    if (way == BackupWay.none) throw StateError('Backing up isn’t on this device.');
    if (way == BackupWay.update) throw StateError('Update Ghost.md to back up to a drive.');
    final now = at ?? DateTime.now();
    final request = <String, Object?>{
      if (way == BackupWay.android) 'tree': drive.tree else 'drive': drive.id,
      'backedUpAt': isoInstant(now),
      'readme': backupReadme(now),
    };
    if (needsAllowing(way, drive)) throw StateError('Allow Ghost.md to use the drive first.');
    return _run(request, onProgress);
  }

  /// Every file the last backup left in the drive's Ghost.md folder (backup.rs `held`, from the backup's own
  /// manifest), for the tree under the drive. Null where it cannot be asked: an Android drive not yet allowed
  /// (`listBackupFiles`).
  Future<List<HeldFile>?> listBackupFiles(BackupWay way, BackupDrive drive) async {
    if (way != BackupWay.mac && way != BackupWay.windows && way != BackupWay.android) return null;
    if (needsAllowing(way, drive)) return null;
    return readHeldFiles(await _invoke('backup_files', way == BackupWay.android ? {'tree': drive.tree} : {'drive': drive.id}));
  }

  /// Stops the backup under way, between files (`cancelBackup`).
  void cancelBackup() => unawaited(_invoke('backup_cancel').then<void>((_) {}, onError: (Object _) {}));

  /// The Mac: the drive put away, so it can be pulled out (`ejectDrive`).
  Future<void> ejectDrive(BackupDrive drive) async => _invoke('backup_eject', {'drive': drive.id});
}

/// `GlyphHost.backupDrives` through the activity: `[]` with no phone half.
Future<String> drivesOnPhone() async {
  try {
    return await filesChannel.invokeMethod<String>('backupDrives') ?? '[]';
  } on MissingPluginException {
    return '[]';
  } on PlatformException {
    return '[]';
  }
}

/// `GlyphHost.chooseBackupDrive` through the activity, answering the picker's JSON once it does.
Future<String> chooseDriveOnPhone(String id) async {
  const none = 'This phone has no way to choose a drive.';
  try {
    return await filesChannel.invokeMethod<String>('chooseBackupDrive', {'id': id}) ?? jsonEncode({'error': none});
  } on MissingPluginException {
    return jsonEncode({'error': none});
  } on PlatformException catch (failure) {
    return jsonEncode({'error': failure.message ?? none});
  }
}

/// A file of the tree.
@immutable
class TreeLeaf {
  const TreeLeaf({required this.name, required this.path, required this.size});
  final String name;
  final String path;
  final int size;
}

/// A folder of the tree: its folders first, then its files, each by name; [files] and [size] count everything under
/// it (`TreeFolder`).
class TreeFolder {
  TreeFolder({required this.name, required this.path});
  final String name;

  /// The path under Ghost.md, with no slash at either end; '' for the folder itself.
  final String path;
  final List<TreeFolder> folders = [];
  final List<TreeLeaf> leaves = [];
  int files = 0;
  int size = 0;
}

final RegExp _digits = RegExp(r'\d+');

/// Two names as `localeCompare(…, { numeric: true, sensitivity: 'base' })` orders them in English: letters without
/// their case, and a run of digits by its number, so "Note 2" is before "Note 10".
int compareNames(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final dx = _digits.matchAsPrefix(x, i), dy = _digits.matchAsPrefix(y, j);
    if (dx != null && dy != null) {
      final nx = BigInt.parse(dx.group(0)!), ny = BigInt.parse(dy.group(0)!);
      if (nx != ny) return nx.compareTo(ny);
      i = dx.end;
      j = dy.end;
      continue;
    }
    final cx = x.codeUnitAt(i), cy = y.codeUnitAt(j);
    if (cx != cy) return cx.compareTo(cy);
    i += 1;
    j += 1;
  }
  return (x.length - i).compareTo(y.length - j);
}

/// The files as the folders they are in, under one root named for the folder on the drive (`backupTree`).
TreeFolder backupTree(Iterable<HeldFile> files, {String root = 'Ghost.md'}) {
  final top = TreeFolder(name: root, path: '');
  for (final file in files) {
    final parts = file.path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    final name = parts.removeLast();
    var folder = top;
    folder.files += 1;
    folder.size += file.size;
    for (final part in parts) {
      var next = folder.folders.where((each) => each.name == part).firstOrNull;
      if (next == null) {
        next = TreeFolder(name: part, path: folder.path.isEmpty ? part : '${folder.path}/$part');
        folder.folders.add(next);
      }
      next.files += 1;
      next.size += file.size;
      folder = next;
    }
    folder.leaves.add(TreeLeaf(name: name, path: file.path, size: file.size));
  }
  void sort(TreeFolder folder) {
    folder.folders.sort((a, b) => compareNames(a.name, b.name));
    folder.leaves.sort((a, b) => compareNames(a.name, b.name));
    folder.folders.forEach(sort);
  }

  sort(top);
  return top;
}

/// A size as a person reads it: "820 KB", "1.4 GB" (`sizeSaid`).
String sizeSaid(int bytes) {
  if (bytes < 1000) return '$bytes bytes';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit += 1;
  }
  return '${value >= 10 || unit == 0 ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
}

/// When a drive was last backed up to, as its row says: "Last backed up Oct 5, 06:52 PM · 312 notes" (`lastSaid`),
/// and "5 Oct, 18:52" once a British phone has said it is one.
String lastSaid(LastBackup? last, {DateTime? now}) {
  if (last == null) return 'No backup on it yet';
  final at = DateTime.tryParse(last.backedUpAt)?.toLocal();
  if (at == null) return 'Backed up before';
  final today = now ?? DateTime.now();
  final sameDay = at.year == today.year && at.month == today.month && at.day == today.day;
  // `toLocaleDateString(undefined, { day: 'numeric', month: 'short' })`, with the year when it is not this one.
  final day = sameDay
      ? 'today'
      : toldDate(at, at.year == today.year ? DateForm.MMMd : DateForm.yMMMd) ?? '${_months[at.month - 1]} ${at.day}${at.year == today.year ? '' : ', ${at.year}'}';
  // `toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })`.
  final time = toldDate(at, DateForm.hm2) ?? '${_two(_hour12(at))}:${_two(at.minute)} ${at.hour < 12 ? 'AM' : 'PM'}';
  final notes = last.notes == 1 ? 'one note' : '${last.notes} notes';
  return 'Last backed up $day, $time · $notes';
}

/// What a backup did, as Settings says it: "Backed up 312 notes to KINGSTON: 14 files written, 298 already there."
/// (`backedSaid`).
String backedSaid(Backed backed, String drive) {
  final notes = backed.notes == 1 ? 'one note' : '${backed.notes} notes';
  final parts = ['${backed.written == 1 ? 'one file' : '${backed.written} files'} written'];
  if (backed.unchanged != 0) parts.add('${backed.unchanged} already there');
  if (backed.removed != 0) parts.add('${backed.removed} taken off');
  return 'Backed up $notes to $drive: ${parts.join(', ')}.';
}
