import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/backup.dart';
import '../../core/library_folder.dart' show failureOf;
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'backup_tree.dart';
import 'settings_host.dart';

/// What Settings' search finds on Backup (`findable`, src/app/settings/BackupPane.findable.ts): nothing by name. The
/// page's rows are the drives plugged in, which no search can name ahead of time, so the section is found by its own
/// name and words.
const List<SettingsFindable> backupFindable = [];

/// How often the drives are looked for while the page is open (`LOOK_EVERY_MS`).
const Duration lookEvery = Duration(seconds: 2);

sealed class _State {
  const _State();
}

class _Idle extends _State {
  const _Idle();
}

class _Allowing extends _State {
  const _Allowing(this.drive);
  final BackupDrive drive;
}

class _Running extends _State {
  const _Running(this.drive, this.progress);
  final BackupDrive drive;
  final BackupProgress? progress;
}

class _Done extends _State {
  const _Done(this.drive, this.backed);
  final BackupDrive drive;
  final Backed backed;
}

class _Ejected extends _State {
  const _Ejected(this.name);
  final String name;
}

class _Failed extends _State {
  const _Failed(this.why);
  final String why;
}

/// A failure as the page says it: the core answers with a sentence, a page throw with an error (`failureOf`).
String _failureOf(Object error) {
  final said = failureOf(error);
  return said == 'That didn’t work.' ? 'The backup could not be written.' : said;
}

/// What a drive's files were read for: the drive, the way in to it, and the backup it held then (`heldKey`).
String _heldKey(BackupDrive drive) => '${drive.id}|${drive.tree ?? ''}|${drive.last?.backedUpAt ?? ''}';

/// A drive's row's hint: its room, and the last backup it holds (`hintOf`).
String driveHint(BackupDrive drive, {DateTime? now}) => [if (drive.free != null) '${sizeSaid(drive.free!)} free', lastSaid(drive.last, now: now)].join(' · ');

/// Port of `BackupPane` (src/app/settings/BackupPane.tsx; docs/DESIGN.md §204 and §213 of ../glyph; Matt: "add a
/// section to the settings called "Backup" it should prompt the user to plugin a removable drive to backup all the
/// notes in the app to workspace folders and such under a Ghost.md folder on the root of the drive").
///
/// With no drive in, the page asks for one, and looks again every two seconds while it is open, so a drive plugged in
/// shows up by itself. Each drive is a row: its name, its room, and the last backup it holds; Back up writes every
/// note into `Ghost.md/` on its root (lib/core/backup.dart). The first backup to a drive opens the system's picker on
/// its root to allow it, once. While a backup runs, how far it has got and Stop; after, what it wrote. Under the
/// drives, each one that holds a backup has its Ghost.md folder as a tree ([BackupTree]): read once for a drive and
/// again when its last backup's time changes, not at every look.
///
/// What differs from the web original:
/// - The backup's calls are the [Backups] it is handed (lib/core/backup.dart), or the one Settings was given
///   (`SettingsFeatures.backup`). With none, backups need the app.
/// - There is no app from before the tree to say "Update Ghost.md to see the files a drive holds here": the Dart and
///   the core are one build.
/// - A folder of the tree stays as it was left, open or closed, while the page is up, whatever is drawn over it
///   (the page kept that in each row; here the page keeps it for its rows, [BackupTree.toggled]).
/// - **The seam.** Settings' `backup` row opens this page (`BackupPane.hosted`); what is left is for the root to
///   hand Settings
///   `SettingsFeatures(backup: Backups.overCore(invoke: core.invoke, startJob: core.startJob, events: core.events))`.
class BackupPane extends StatefulWidget {
  const BackupPane({super.key, this.backups, this.now});

  final Backups? backups;

  /// The moment "today" is told from; now when null. A test gives its own.
  final DateTime? now;

  static Widget hosted(BuildContext context) => BackupPane(backups: SettingsHost.maybeOf(context)?.features.backup);

  @override
  State<BackupPane> createState() => _BackupPaneState();
}

class _BackupPaneState extends State<BackupPane> {
  BackupWay? _way;
  List<BackupDrive>? _drives;
  _State _state = const _Idle();
  Timer? _timer;

  /// The files each drive's Ghost.md folder holds, by [_heldKey]: asked once for a drive and the backup on it.
  final Map<String, List<HeldFile>?> _held = {};
  final Set<String> _asked = {};

  /// The folders of each drive's tree that were tapped, by the drive's id.
  final Map<String, Set<String>> _toggled = {};

  /// Read by the look for drives, which must not change the page under a backup that is running.
  bool get _busy => _state is _Running || _state is _Allowing;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _find() async {
    final found = await widget.backups?.way() ?? BackupWay.none;
    if (!mounted) return;
    setState(() => _way = found);
    if (found != BackupWay.mac && found != BackupWay.windows && found != BackupWay.android) return;
    _look();
    _timer = Timer.periodic(lookEvery, (_) => _look());
  }

  void _look() {
    if (_busy) return;
    unawaited(widget.backups!.listDrives(_way!).then(_found, onError: (Object _) => _found(const [])));
  }

  void _found(List<BackupDrive> drives) {
    if (!mounted) return;
    setState(() => _drives = drives);
    final way = _way!;
    for (final drive in drives) {
      if (drive.last == null) continue;
      final key = _heldKey(drive);
      if (!_asked.add(key)) continue;
      unawaited(widget.backups!.listBackupFiles(way, drive).then<void>(
        (files) {
          if (mounted) setState(() => _held[key] = files);
        },
        onError: (Object _) {
          if (mounted) setState(() => _held[key] = null);
        },
      ));
    }
  }

  Future<void> _backUp(BackupDrive given) async {
    final way = _way, backups = widget.backups;
    if (way == null || backups == null) return;
    var drive = given;
    if (backups.needsAllowing(way, drive)) {
      setState(() => _state = _Allowing(drive));
      final answer = await backups.allowDrive(drive.id);
      if (!mounted) return;
      switch (answer) {
        case DriveCancelled():
          setState(() => _state = const _Idle());
          return;
        case DriveRefused(:final error):
          setState(() => _state = _Failed(error));
          return;
        case DriveAllowed(:final tree):
          drive = drive.withTree(tree);
      }
    }
    setState(() => _state = _Running(drive, null));
    try {
      final backed = await backups.runBackup(way, drive, (progress) {
        if (mounted && _state is _Running) setState(() => _state = _Running(drive, progress));
      });
      if (!mounted) return;
      setState(() => _state = _Done(drive, backed));
      unawaited(backups.listDrives(way).then(_found, onError: (Object _) {}));
    } catch (error) {
      if (mounted) setState(() => _state = _Failed(_failureOf(error)));
    }
  }

  void _eject(BackupDrive drive) {
    unawaited(widget.backups!.ejectDrive(drive).then<void>(
      (_) {
        if (mounted) setState(() => _state = _Ejected(drive.name));
      },
      onError: (Object error) {
        if (mounted) setState(() => _state = _Failed(_failureOf(error)));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final way = _way;
    if (way == BackupWay.none) {
      return const PaneBody(
        children: [SettingsEmpty(icon: AppIcon(Lucide.hardDrive, size: 28), title: 'Backups need the app', body: Text('Back up to a USB drive or an SD card from Ghost.md on a Mac or an Android phone.'))],
      );
    }
    if (way == BackupWay.update) {
      return const PaneBody(
        children: [SettingsEmpty(icon: AppIcon(Lucide.hardDrive, size: 28), title: 'Update Ghost.md to back up', body: Text('This version of the app can’t write to a drive yet. Settings › About has the update.'))],
      );
    }

    final state = _state;
    final progress = state is _Running ? state.progress : null;
    final working = _busy;
    final drives = _drives;

    return PaneBody(
      children: [
        if (state is _Running)
          SettingsCallout(
            icon: const AppIcon(Lucide.hardDriveUpload, size: 20),
            action: RowAction(onPress: () => widget.backups?.cancelBackup(), child: const Text('Stop')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  progress != null && progress.total > 0
                      ? 'Backing up to ${state.drive.name}, ${sizeSaid(progress.done)} of ${sizeSaid(progress.total)}. Keep the drive plugged in.'
                      : 'Backing up to ${state.drive.name}…',
                ),
                if (progress != null) ...[
                  SizedBox(height: t.space(2)),
                  GlacierProgressBar(ariaLabel: 'Backing up', value: progress.done.toDouble(), max: progress.total < 1 ? 1 : progress.total.toDouble(), size: GlacierProgressBarSize.sm),
                ],
              ],
            ),
          ),
        if (state is _Allowing) SettingsCallout(icon: const AppIcon(Lucide.usb, size: 20), child: Text('Allow Ghost.md to use ${state.drive.name}, at the top of the drive.')),
        if (state is _Done)
          SettingsCallout(
            icon: const AppIcon(Lucide.circleCheck, size: 20),
            action: way == BackupWay.mac ? RowAction(onPress: () => _eject(state.drive), child: const Text('Eject')) : null,
            child: Text(backedSaid(state.backed, state.drive.name)),
          ),
        if (state is _Ejected) SettingsCallout(icon: const AppIcon(Lucide.circleCheck, size: 20), child: Text('${state.name} can be unplugged now.')),
        if (state is _Failed) SettingsCallout(child: Text(state.why)),
        if (drives != null && drives.isEmpty)
          SettingsEmpty(
            icon: const AppIcon(Lucide.usb, size: 28),
            title: 'Plug in a drive',
            body: Text('Plug in a USB drive${way == BackupWay.android ? ', or put in an SD card,' : ' or an SD card'} to back up every note onto it. Ghost.md is looking for one now.'),
          ),
        if (drives != null && drives.isNotEmpty)
          PaneSection(
            title: 'Back up to',
            children: [
              for (final drive in drives)
                SettingRow(
                  key: ValueKey('drive ${drive.id}'),
                  icon: const AppIcon(Lucide.hardDrive, size: 20),
                  label: drive.name,
                  hint: Text(driveHint(drive, now: widget.now)),
                  control: RowAction(onPress: () => unawaited(_backUp(drive)), disabled: working, child: const Text('Back up')),
                ),
            ],
          ),
        for (final drive in drives ?? const <BackupDrive>[])
          if (drive.last != null && (_held[_heldKey(drive)]?.isNotEmpty ?? false))
            PaneSection(
              key: ValueKey('tree ${_heldKey(drive)}'),
              title: 'On ${drive.name}',
              children: [BackupTree(tree: backupTree(_held[_heldKey(drive)]!), toggled: _toggled.putIfAbsent(drive.id, () => {}))],
            ),
        const SettingsFootnote(
          child: Text(
            'Every note goes into a Ghost.md folder at the top of the drive, in your workspaces’ folders, with its version history and its pictures, films and recordings. The next backup to the same drive only writes what changed. Nothing leaves this device but onto the drive.',
          ),
        ),
      ],
    );
  }
}
