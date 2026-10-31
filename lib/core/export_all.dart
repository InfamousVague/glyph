/// Everything the app keeps, as one zip on a USB drive or wherever a person chooses (Matt: "Please add a feature that
/// allows me to plug in a USB drive and export the entire app onto a folder or zip file with
/// `ghostmarkdown_<datetime>.7z` or something"; docs/DESIGN.md §167 of tauri/). A port of `src/app/core/exportAll.ts`.
///
/// A zip rather than a 7z, since every computer and phone opens a zip with nothing installed, named
/// `ghostmarkdown_2026-10-01_21-42-05.zip` on the device's own clock, with one folder of that name inside it. On
/// Android the system's picker makes the file, a drive plugged in by USB among its places
/// (android/…/glyph/files/ExportTarget.kt), and Rust writes the archive straight into it (`export_fd`,
/// native/src/kept/export_commands.rs over the Tauri app's export.rs).
///
/// What differs:
/// - The page's imports (`invoke`, `listenTo`, `window.GlyphHost.chooseExport` with its `exportTarget` answer,
///   `exportDone` and `discardExport`, `localStorage`, the platform) are one value, [ExportAll], which the app's root
///   makes from the core it already holds ([ExportAll.overCore]) and a test makes from fakes.
/// - **The picker is one call**, as the library folder's is (lib/core/library_folder.dart).
/// - **The export is a job**, as the backup is (lib/core/backup.dart): `export_fd` answers an id at once and the
///   core says the rest as events.
/// - **No generation to wait for** (`EXPORT_GENERATION`, 22): `update` is only an Android run with no picker
///   behind the channel.
/// - **No browser's export**: there is no build of this app whose notes are a browser's (`browserFiles`,
///   `noteFileName` and the browser's save stay on the page).
/// - **The Mac exports as Android does.** The Tauri app's `export_save` opened the save panel in Rust; here the
///   panel is Swift's (macos/Runner/FilesChannel.swift), which makes the file and answers a descriptor it opened
///   on it, so the Mac app goes through `chooseExport` and `export_fd` exactly as the phone does. Outside the Mac
///   app (a test, another desktop) [ExportAll.way] answers `update`.
/// - **The manifest's `page`** is what this build calls itself ([ExportAll.page]), where the page said the bundle
///   it was loaded from.
/// - **The README's date is written in English**, in the phone's own order and clock, as lib/core/backup.dart's is.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backup.dart' show isoInstant, sizeSaid;
import 'library_folder.dart' show filesChannel;
import 'locale_dates.dart';
import 'mac_app.dart';
import 'native/core.dart';
import 'native/events.dart';
import 'preferences.dart' show PreferencesStore;
import 'stored.dart';

export 'backup.dart' show sizeSaid;

/// The binary generation with `export_fd`, `export_cancel` and the activity's `chooseExport` (`EXPORT_GENERATION`),
/// kept for the record.
const int exportGeneration = 22;

/// Where an export can go from here: the Mac's panel, Android's picker, a browser's save, or nowhere yet
/// (`ExportWay`).
enum ExportWay { mac, android, browser, update, none }

String _two(int n) => n.toString().padLeft(2, '0');

/// `ghostmarkdown_2026-10-01_21-42-05.zip`, on the device's clock: no colon, which a USB drive's FAT will not hold
/// (`exportName`).
String exportName(DateTime at) => 'ghostmarkdown_${at.year}-${_two(at.month)}-${_two(at.day)}_${_two(at.hour)}-${_two(at.minute)}-${_two(at.second)}.zip';

/// The settings carried: how the app looks and behaves, its plugins and the workspaces, and nothing that opens an
/// account or a service. No session, no sync key, no Notion or GitHub token: a drive is easily lost
/// (`SETTINGS_KEYS`).
const List<String> settingsKeys = ['glyph-preferences', 'glyph-plugins', 'glyph-workspace-current', 'glyph-note-bookmarks', 'glyph-book-spots'];

/// The preference keys that are secrets or hold them, left out of `settings.json` (docs/MARKDOWN_FIRST.md §5, gap 3;
/// the critic, 2026-10-31): `shares` is every read-only link's id AND key, `calendars` holds Google's refresh token
/// and the iCal URLs, `webhooks` the outgoing hooks' secrets, and `sealedKeys` every API key and connection, sealed
/// but still a key. Until this they went out in the clear under a README that said "No account, password or key".
/// The web's preferences carry unknown keys at the top level (`Preferences.more`), so these are top-level keys of the
/// `glyph-preferences` value.
const Set<String> secretPreferenceKeys = {'shares', 'calendars', 'webhooks', 'sealedKeys'};

final RegExp _secretName = RegExp(r'token|secret|password|webhook|sealed|refresh', caseSensitive: false);

/// [value] with every secret taken out, all the way down: the keys of [secretPreferenceKeys] at the top of the
/// preferences, and anywhere a key naming a token, a secret, a password, a webhook or a sealed value. What is left
/// is the look and the behaviour, the plugins, the workspaces, the trash, the meetings: nothing that opens a link
/// or a service (`secretFree`).
Object? secretFree(Object? value, {bool top = false}) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!(top && secretPreferenceKeys.contains(entry.key)) && !_secretName.hasMatch('${entry.key}')) entry.key: secretFree(entry.value),
    };
  }
  if (value is List) return [for (final each in value) secretFree(each)];
  return value;
}

/// The settings as `settings.json`: each key's stored value, read as JSON where it is JSON, the secrets taken out
/// of the preferences ([secretFree]) (`settingsFile`). [read] is the device's memory, the app's own ([stored])
/// unless given. Nothing reads the file back into the app, so leaving the secrets out costs no compatibility.
String settingsFile([String? Function(String key)? read]) {
  final settings = <String, Object?>{};
  for (final key in settingsKeys) {
    String? raw;
    try {
      raw = (read ?? stored.readText)(key);
    } catch (_) {
      raw = null;
    }
    if (raw == null) continue;
    try {
      final Object? value = jsonDecode(raw);
      settings[key] = key == PreferencesStore.storageKey ? secretFree(value, top: true) : secretFree(value);
    } catch (_) {
      settings[key] = raw;
    }
  }
  return '${const JsonEncoder.withIndent('  ').convert(settings)}\n';
}

/// What the archive is, in its own README (`readme`).
String readme(String name, DateTime at) {
  final root = name.replaceFirst(RegExp(r'\.zip$'), '');
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  // `toLocaleString()`, in English: "10/1/2026, 9:42:05 PM", and "01/10/2026, 21:42:05" once a British phone has
  // said it is one (core/locale_dates.dart).
  final when = toldDate(at, DateForm.whole) ?? '${at.month}/${at.day}/${at.year}, $hour:${_two(at.minute)}:${_two(at.second)} ${at.hour < 12 ? 'AM' : 'PM'}';
  return [
    'Ghost.md, exported $when',
    '',
    'Everything in $root/ is what Ghost.md kept on the device it was exported from.',
    '',
    'Library/      Every note, as a Markdown (.md) file, in its folders. Open the folder in Obsidian or any',
    '              text editor. Library/.glyph/ holds what a note has that is not text: a recording\'s',
    '              phrases and their times.',
    'images/       The pictures notes show. A note links one as image/<name>.',
    'video/        The films notes play. A note links one as video/<name>.',
    'recordings/   The recordings voice notes and meetings kept, as WAV, named by the note\'s id.',
    'settings.json How the app looked and behaved, its plugins, workspaces, trash and meetings. The account,',
    '              its keys, share links, calendars and webhooks are left out: nothing in here opens anything.',
    'manifest.json When it was exported, from which version, and how many notes and files.',
    '',
    'Not here: the AI and voice models (downloaded again in Settings), the search index (rebuilt from',
    'the files), and anything that signs in to an account.',
    '',
  ].join('\n');
}

/// How far an export has got (export.rs `Progress`): bytes read of all, files of all.
@immutable
class ExportProgress {
  const ExportProgress({this.done = 0, this.total = 0, this.files = 0, this.of = 0});

  factory ExportProgress.fromJson(Map<String, Object?> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ExportProgress(done: count('done'), total: count('total'), files: count('files'), of: count('of'));
  }

  final int done;
  final int total;
  final int files;
  final int of;
}

/// What an export wrote (export.rs `Exported`).
@immutable
class Exported {
  const Exported({required this.name, this.notes = 0, this.files = 0, this.bytes = 0, this.written = 0});

  factory Exported.fromJson(Map<String, Object?> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return Exported(name: json['name'] is String ? json['name']! as String : '', notes: count('notes'), files: count('files'), bytes: count('bytes'), written: count('written'));
  }

  final String name;
  final int notes;
  final int files;
  final int bytes;
  final int written;

  Exported named(String name) => Exported(name: name, notes: notes, files: files, bytes: bytes, written: written);

  @override
  bool operator ==(Object other) => other is Exported && other.name == name && other.notes == notes && other.files == files && other.bytes == bytes && other.written == written;

  @override
  int get hashCode => Object.hash(name, notes, files, bytes, written);
}

/// What the picker answered (files/ExportTarget.kt), as the page reads it (`TargetAnswer`).
sealed class TargetAnswer {
  const TargetAnswer();
}

class TargetMade extends TargetAnswer {
  const TargetMade(this.fd, this.name);
  final int fd;
  final String name;

  @override
  bool operator ==(Object other) => other is TargetMade && other.fd == fd && other.name == name;

  @override
  int get hashCode => Object.hash(fd, name);
}

class TargetCancelled extends TargetAnswer {
  const TargetCancelled();

  @override
  bool operator ==(Object other) => other is TargetCancelled;

  @override
  int get hashCode => (TargetCancelled).hashCode;
}

class TargetRefused extends TargetAnswer {
  const TargetRefused(this.error);
  final String error;

  @override
  bool operator ==(Object other) => other is TargetRefused && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// The picker's answer read (`readTargetAnswer`): a descriptor is a whole number past the three every process
/// starts with.
TargetAnswer readTargetAnswer(String json) {
  const unread = TargetRefused('That place can’t be written to.');
  Object? said;
  try {
    said = jsonDecode(json);
  } catch (_) {
    return unread;
  }
  if (said is! Map) return unread;
  if (said['cancelled'] == true) return const TargetCancelled();
  final error = said['error'], fd = said['fd'], name = said['name'];
  if (error is String) return TargetRefused(error);
  if (fd is int && fd > 2) return TargetMade(fd, name is String ? name : '');
  return unread;
}

/// The phone's half of an export (`GlyphHost.chooseExport`, `exportDone`, `discardExport`).
class ExportPicker {
  const ExportPicker({required this.choose, required this.done, required this.discard});

  /// The activity's, on `ghost_md/files`.
  static const ExportPicker phone = ExportPicker(choose: _chooseOnPhone, done: _doneOnPhone, discard: _discardOnPhone);

  /// Opens the picker to make a zip called `name`, and answers its JSON once the picker does.
  final Future<String> Function(String name) choose;

  /// The export is whole: the file stays.
  final void Function() done;

  /// The export failed or was stopped: the half-written file goes.
  final void Function() discard;

  static const String _none = 'This phone has no way to choose where to save.';

  static Future<String> _chooseOnPhone(String name) async {
    try {
      return await filesChannel.invokeMethod<String>('chooseExport', {'name': name}) ?? jsonEncode({'error': _none});
    } on MissingPluginException {
      return jsonEncode({'error': _none});
    } on PlatformException catch (failure) {
      return jsonEncode({'error': failure.message ?? _none});
    }
  }

  static void _doneOnPhone() => unawaited(filesChannel.invokeMethod<void>('exportDone').then<void>((_) {}, onError: (Object _) {}));
  static void _discardOnPhone() => unawaited(filesChannel.invokeMethod<void>('discardExport').then<void>((_) {}, onError: (Object _) {}));
}

/// `export_fd` under way: how it ends, and what it says meanwhile. The page had `invoke('export_fd')` and a listener.
typedef ExportRun = Future<Exported> Function(Map<String, Object?> args, void Function(ExportProgress progress) onProgress);

/// `export_fd` over the core: the job started, `export://progress` heard until it ends, and its end as the answer
/// or the core's own sentence.
ExportRun coreExportRun({required Future<CoreJob> Function(String command, [Map<String, Object?> args]) startJob, required Stream<CoreEvent> events}) {
  return (args, onProgress) async {
    final heard = events.where((event) => event.event == 'export://progress').listen((event) => onProgress(ExportProgress.fromJson(event.map)));
    try {
      final job = await startJob('export_fd', args);
      final said = await job.done;
      return Exported.fromJson(said is Map ? said.cast<String, Object?>() : const {});
    } finally {
      await heard.cancel();
    }
  };
}

/// The export as the app reaches it: the page's imports, as one value (see the header).
class ExportAll {
  ExportAll({required CoreInvoke invoke, required ExportRun run, ExportPicker? picker, String? Function(String key)? kept, this.page = 'flutter', TargetPlatform? platform})
      : _invoke = invoke,
        _run = run,
        _picker = picker,
        _kept = kept,
        _platform = platform;

  /// Over the app's own core and the phone's own picker.
  factory ExportAll.overCore({required CoreInvoke invoke, required Future<CoreJob> Function(String command, [Map<String, Object?> args]) startJob, required Stream<CoreEvent> events, String page = 'flutter', TargetPlatform? platform}) =>
      ExportAll(
        invoke: invoke,
        run: coreExportRun(startJob: startJob, events: events),
        // The activity's on Android; the Mac app's save panel (macos/Runner/FilesChannel.swift) by the same calls.
        picker: (platform ?? defaultTargetPlatform) == TargetPlatform.android || ((platform ?? defaultTargetPlatform) == TargetPlatform.macOS && runsAsMacApp) ? ExportPicker.phone : null,
        page: page,
        platform: platform,
      );

  final CoreInvoke _invoke;
  final ExportRun _run;
  final ExportPicker? _picker;
  final String? Function(String key)? _kept;
  final TargetPlatform? _platform;

  /// What this build calls itself in the archive's manifest.
  final String page;

  TargetPlatform get _device => _platform ?? defaultTargetPlatform;

  /// Where an export can go from here (`exportWay`).
  Future<ExportWay> way() async {
    if (_device == TargetPlatform.iOS) return ExportWay.none;
    if (_device == TargetPlatform.android) return _picker != null ? ExportWay.android : ExportWay.update;
    // The Mac app's save panel makes the file and hands over a descriptor, as Android's picker does.
    if (_device == TargetPlatform.macOS && _picker != null) return ExportWay.mac;
    return ExportWay.update;
  }

  /// The request Rust takes (export_commands.rs `ExportRequest`).
  Map<String, Object?> request(String name, DateTime at) => {
        'name': name,
        // A zip's times are the wall clock's.
        'offsetMinutes': at.timeZoneOffset.inMinutes,
        'page': page,
        'exportedAt': isoInstant(at),
        'files': [
          {'name': 'README.txt', 'text': readme(name, at)},
          {'name': 'settings.json', 'text': settingsFile(_kept)},
        ],
      };

  /// Stops the export under way (`cancelExport`).
  void cancel() => unawaited(_invoke('export_cancel').then<void>((_) {}, onError: (Object _) {}));

  /// Exports everything the way this device can: the archive written where the person chose, or null when they
  /// closed the picker without choosing. [onProgress] hears how far it has got (`exportEverything`).
  Future<Exported?> exportEverything(void Function(ExportProgress progress) onProgress, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final name = exportName(now);
    final way = await this.way();
    if (way == ExportWay.none) throw StateError('Exporting isn’t on iPhone yet.');
    if (way != ExportWay.android && way != ExportWay.mac) throw StateError('Update Ghost.md to export everything.');
    final picker = _picker!;
    switch (readTargetAnswer(await picker.choose(name))) {
      case TargetCancelled():
        return null;
      case TargetRefused(:final error):
        throw StateError(error);
      case TargetMade(:final fd, name: final made):
        try {
          final done = await _run({'request': request(name, now), 'fd': fd}, onProgress);
          picker.done();
          return made.isEmpty ? done : done.named(made);
        } catch (_) {
          // Half an archive is no archive: the picker's file goes, so the drive holds only what opens.
          picker.discard();
          rethrow;
        }
    }
  }
}

/// What an export wrote, as Settings' Export page says it: "Exported 312 notes and 48 other files, 1.2 GB, as
/// ghostmarkdown_….zip." (`doneSaid`).
String doneSaid(Exported exported) {
  String count(int n, String one, String many) => n == 1 ? 'one $one' : '$n $many';
  final others = exported.files - exported.notes < 0 ? 0 : exported.files - exported.notes;
  final what = others != 0 ? '${count(exported.notes, 'note', 'notes')} and ${count(others, 'other file', 'other files')}' : count(exported.notes, 'note', 'notes');
  return 'Exported $what, ${sizeSaid(exported.written)}, as ${exported.name}.';
}
