/// Stage 9's native pieces alone on a phone (docs/STAGES_5_6_8_9.md, 9A to 9C, and the three small channels), to be
/// proved there before the root wires them: `flutter build apk --debug --no-pub --target-platform android-arm64
/// -t lib/main_files.dart`. A column of buttons over a log:
///
/// - **Open web / mail / map / refused**: an address handed to the phone (`ghost_md/open`, OpenLink.kt): the
///   browser, the mail app, the maps app, and a `javascript:` address, which goes nowhere.
/// - **Links**: every `ghostmd://` link that opened the app is logged as it is taken and sorted
///   (`ghost_md/links`, AppLinks.kt): `adb shell am start -a android.intent.action.VIEW -d "ghostmd://note/abc"
///   com.mattssoftware.glyph.flutter`, cold and with the app up.
/// - **Recording?**, **Reset (keep models)**: the phone's half of starting over (`ghost.md/reset`,
///   ResetChannel.kt) with the core's `reset_local_data`; **Seed** writes a note and a secret first, and **Count**
///   says what is there.
/// - **Pages**: Settings' own pages for the library's folder (9A), the backup (9B) and the export (9C), as
///   Settings draws them, over the real core and the phone's pickers and drives. The head's way
///   out comes back to the log. An emulator has no drive until it is given one: `adb shell sm set-virtual-disk true`,
///   then `adb shell sm partition <the disk `sm list-disks` names> public`.
/// - **Back up into a folder**: the same backup, written through the same tree calls, into a folder picked in the
///   phone's picker. For an emulator, whose one drive is an SD card: Android 11 and later let no app be granted the
///   top of an SD card ("Can't use this folder"), only of a USB drive, so the page's own road cannot be walked to
///   its end there. Run it twice to see the second write only what changed.
///
/// Every line of the log is also printed as `[files] …`, for `adb logcat -s flutter`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'account/device_keys.dart';
import 'app/ghost_app.dart';
import 'core/back.dart';
import 'core/backup.dart';
import 'core/export_all.dart' hide sizeSaid;
import 'core/library_folder.dart';
import 'core/native/device_paths.dart';
import 'core/native/ghost_core.dart';
import 'core/open_link.dart';
import 'core/phone_links.dart';
import 'core/preferences.dart';
import 'core/reset_native.dart';
import 'main.dart' show appStyleSheets;
import 'settings/kit/settings_icons.dart';
import 'settings/panes/backup_pane.dart';
import 'settings/panes/export_pane.dart';
import 'settings/panes/library_folder_pane.dart';
import 'settings/settings_screen.dart';
import 'share/app_links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // So each button has a name `uiautomator` can find.
  SemanticsBinding.instance.ensureSemantics();
  // The page's theme, for Settings' pages: the log itself is drawn without it.
  final sheet = await loadTokenSheet(more: appStyleSheets);
  try {
    await preferences.load().timeout(const Duration(seconds: 2));
  } catch (_) {
    // A device that cannot remember: the defaults.
  }
  runApp(GhostApp(sheet: sheet, home: const _FilesApp()));
}

class _FilesApp extends StatefulWidget {
  const _FilesApp();

  @override
  State<_FilesApp> createState() => _FilesState();
}

class _FilesState extends State<_FilesApp> {
  final List<String> _log = [];
  late GhostCore _core;
  late DevicePaths _paths;
  late PhoneReset _reset;
  final PhoneLinks _links = PhoneLinks();
  final SecureStore _secrets = deviceSecureStore();
  void Function()? _stopLinks;
  bool _ready = false;

  /// Whether Settings' pages are up in place of the log.
  bool _pages = false;
  final BackStack _back = BackStack();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _stopLinks?.call();
    _links.dispose();
    super.dispose();
  }

  void _say(String line) {
    debugPrint('[files] $line');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _guard(String what, Future<void> Function() work) async {
    try {
      await work();
    } catch (failure) {
      _say('$what FAILED: $failure');
    }
  }

  Future<void> _open() => _guard('open', () async {
        _core = await GhostCore.open();
        _paths = await DevicePaths.find();
        await _core.init(dataDir: _paths.dataDir, cacheDir: _paths.cacheDir);
        _reset = PhoneReset(invoke: _core.invoke);
        _say('core open on ${_paths.dataDir}');
        setState(() => _ready = true);
        // Once the notes can be read, as the root will: every link that opened the app, sorted.
        _stopLinks = followAppLinks((link) => _say('link $link -> ${_sorted(link)}'), _links);
      });

  String _sorted(String link) => switch (readAppLink(link)) {
        JoinAppLink(:final code) => 'join $code',
        NoteAppLink(:final noteId) => 'note $noteId',
        PlaceAppLink(:final place) => place is OrganizationPlace ? 'organization ${place.orgId}' : 'notifications',
        ShareAppLink(:final id) => 'share $id',
        null => 'none of the app\'s',
      };

  Future<void> _openAddress(String url) => _guard('open', () async {
        _say('open $url: may be handed over ${canOpenLink(url)}');
        await openLink(url);
        // The channel's own answer, which `openLink` drops as the page's callers do.
        if (canOpenLink(url)) _say('the phone took it: ${await openLinkChannel.invokeMethod<bool>('open', {'url': url})}');
      });

  Future<void> _seed() => _guard('seed', () async {
        final id = await _core.newId();
        await _core.invoke('create_note', {'id': id, 'body': '# Kept until the reset\n\nA line.\n', 'source': 'editor'});
        await File('${_paths.dataDir}/recordings/$id.wav').create(recursive: true);
        await _secrets.write('walk-secret', 'kept');
        await _count();
      });

  Future<void> _count() => _guard('count', () async {
        final notes = await _core.invoke('list_notes') as List<Object?>;
        final recordings = Directory('${_paths.dataDir}/recordings');
        _say('${notes.length} notes; recordings folder ${recordings.existsSync() ? 'holds ${recordings.listSync().length}' : 'is not there'}; secret ${await _secrets.read('walk-secret')}');
      });

  Future<void> _backUpIntoFolder() => _guard('backup', () async {
        final answer = readFolderAnswer(await pickTreeOnPhone());
        if (answer is! FolderGranted) {
          _say('no folder to back up into: ${answer is FolderRefused ? answer.error : 'the picker was closed'}');
          return;
        }
        final backups = Backups.overCore(invoke: _core.invoke, startJob: _core.startJob, events: _core.events);
        final drive = BackupDrive(id: 'picked', name: answer.name, tree: answer.uri);
        final backed = await backups.runBackup(BackupWay.android, drive, (progress) => _say('backup ${sizeSaid(progress.done)} of ${sizeSaid(progress.total)}, ${progress.files} of ${progress.of} files'));
        _say(backedSaid(backed, answer.name));
        final held = await backups.listBackupFiles(BackupWay.android, drive) ?? const [];
        _say('${held.length} files held: ${held.map((file) => '${file.path} (${sizeSaid(file.size)})').join(', ')}');
        _say('last: ${await _core.invoke('backup_last', {'tree': answer.uri})}');
      });

  Future<void> _resetNow() => _guard('reset', () async {
        _reset.cancelWriteUps();
        await _reset.resetLocalData(models: false);
        _say('reset done');
        await _count();
      });

  Widget _settings() {
    final folder = LibraryFolder(invoke: _core.invoke, onNotesChanged: () => _say('the notes changed: the list would be read again'));
    final backups = Backups.overCore(invoke: _core.invoke, startJob: _core.startJob, events: _core.events);
    final export = ExportAll.overCore(invoke: _core.invoke, startJob: _core.startJob, events: _core.events);
    return BackScope(
      stack: _back,
      child: SettingsScreen(
        open: true,
        onClose: () => setState(() => _pages = false),
        title: 'Files',
        search: false,
        sections: [
          SettingsSection(
            id: 'library-folder',
            label: 'Library folder',
            icon: const SettingsIcon(SettingsGlyph.folder, size: 16),
            content: (context) => LibraryFolderPane(folder: folder),
            summary: 'Where your notes are kept',
            group: 1,
          ),
          SettingsSection(
            id: 'backup',
            label: 'Backup',
            icon: const SettingsIcon(SettingsGlyph.hardDriveUpload, size: 16),
            content: (context) => BackupPane(backups: backups),
            summary: 'To a USB drive or SD card',
            group: 1,
          ),
          SettingsSection(
            id: 'export',
            label: 'Export',
            icon: const SettingsIcon(SettingsGlyph.hardDriveDownload, size: 16),
            content: (context) => ExportPane(export: export),
            summary: 'Everything as one zip',
            group: 1,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pages && _ready) return _settings();
    final buttons = <(String, VoidCallback)>[
      ('Open web', () => _openAddress('https://example.com/')),
      ('Open mail', () => _openAddress('mailto:someone@example.com')),
      ('Open map', () => _openAddress('geo:51.5,-0.12')),
      ('Open refused', () => _openAddress('javascript:alert(1)')),
      ('Seed', _seed),
      ('Count', _count),
      ('Recording?', () => _guard('recording', () async => _say('recording: ${await resetChannel.invokeMethod<bool>('recording')}'))),
      ('Reset (keep models)', _resetNow),
      ('Pages', () => setState(() => _pages = true)),
      ('Back up into a folder', _backUpIntoFolder),
    ];
    const ink = Color(0xFFEDEDED), paper = Color(0xFF111111), line = Color(0xFF3A3A3A);
    const text = TextStyle(color: ink, fontSize: 13, height: 1.3, decoration: TextDecoration.none);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: paper,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ghost Flutter · files', style: text.copyWith(fontSize: 15), maxLines: 1),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, action) in buttons)
                      Semantics(
                        button: true,
                        label: label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _ready ? action : null,
                          child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: _ready ? ink : line), borderRadius: BorderRadius.circular(8)),
                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(label, style: text)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_log[index], style: text)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
