import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/backup.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/backup_pane.dart';
import 'package:ghost_md/settings/panes/backup_tree.dart';
import 'package:glacier/glacier.dart';

import 'stage9_support.dart';

/// Settings › Backup (lib/settings/panes/backup_pane.dart; docs/DESIGN.md §204 and §213 of ../glyph): the page with
/// no drive in, a drive found by looking again, the allow, the backup from a drive's row with its progress and Stop,
/// what it says after, and the drive's Ghost.md folder as a tree. A port of `src/app/settings/BackupPane.test.tsx`,
/// on Android's road where the web's cases were the Mac's: the drives, the picker and the core are stood in for.
class Device {
  BackupWay way = BackupWay.android;
  List<BackupDrive> drives = [];
  List<HeldFile> files = [];
  final List<String> runs = [], listed = [], ejected = [], allowed = [];
  int cancels = 0;
  DriveAnswer allow = const DriveAllowed('content://tree/usb');
  Backed backed = const Backed(notes: 312, files: 340, written: 14, unchanged: 326);

  /// Held open by a test that wants to see the backup under way.
  Completer<void>? gate;
  void Function(BackupProgress)? tell;
}

/// The backup's calls over [device]: the page's own logic, with what it stands on answered by the test.
class FakeBackups extends Backups {
  FakeBackups(this.device)
      : super(
          invoke: (command, [args = const {}]) async => throw const CoreError('not asked in this test'),
          run: (request, onProgress) async => const Backed(),
          platform: TargetPlatform.android,
        );

  final Device device;

  @override
  Future<BackupWay> way() async => device.way;

  @override
  Future<List<BackupDrive>> listDrives(BackupWay way) async => device.drives;

  @override
  Future<DriveAnswer> allowDrive(String id) async {
    device.allowed.add(id);
    return device.allow;
  }

  @override
  Future<Backed> runBackup(BackupWay way, BackupDrive drive, void Function(BackupProgress progress) onProgress, {DateTime? at}) async {
    device.runs.add('${drive.name} ${drive.tree}');
    device.tell = onProgress;
    await device.gate?.future;
    return device.backed;
  }

  @override
  Future<List<HeldFile>?> listBackupFiles(BackupWay way, BackupDrive drive) async {
    device.listed.add(drive.name);
    return device.files;
  }

  @override
  void cancelBackup() => device.cancels += 1;

  @override
  Future<void> ejectDrive(BackupDrive drive) async => device.ejected.add(drive.name);
}

void main() {
  setUpAll(loadAppFonts);

  late Device device;
  final now = DateTime(2026, 10, 6, 9);

  Future<void> open(WidgetTester tester) async {
    await showPane(tester, 'Backup', (context) => BackupPane(backups: FakeBackups(device), now: now), glyph: SettingsGlyph.hardDriveUpload);
    await letRun(tester);
  }

  /// Ends a test whose page keeps looking for drives.
  Future<void> close(WidgetTester tester) => endSettings(tester);

  String? hint(WidgetTester tester, String label) {
    final hint = tester.widget<SettingRow>(rowCalled(label)).hint;
    return hint is Text ? hint.data : null;
  }

  setUp(() => device = Device());

  testWidgets('asks for a drive with none in, and finds one plugged in by looking again', (tester) async {
    await open(tester);
    expect(find.text('Plug in a drive'), findsOneWidget);
    expect(find.text('Plug in a USB drive, or put in an SD card, to back up every note onto it. Ghost.md is looking for one now.'), findsOneWidget);
    device.drives = [const BackupDrive(id: '1A2B-3C4D', name: 'KINGSTON', free: 30000000000, total: 32000000000)];
    await tester.pump(lookEvery);
    await letRun(tester);
    expect(rowLabels(tester, 'Back up to'), ['KINGSTON']);
    expect(hint(tester, 'KINGSTON'), '30 GB free · No backup on it yet');
    expect(find.text('Plug in a drive'), findsNothing);
    await close(tester);
  });

  testWidgets('allows a drive once, backs up to it from its row, says how far it has got, and what it did', (tester) async {
    device.drives = [BackupDrive(id: 'usb', name: 'KINGSTON', last: LastBackup(backedUpAt: isoInstant(DateTime(2026, 10, 5, 18, 52)), notes: 300))];
    device.gate = Completer<void>();
    await open(tester);
    expect(hint(tester, 'KINGSTON'), 'Last backed up Oct 5, 06:52 PM · 300 notes');
    await tapOn(tester, actionSaying('Back up'));
    await letRun(tester);
    expect(device.allowed, ['usb']);
    expect(device.runs, ['KINGSTON content://tree/usb'], reason: 'the tree the picker granted is the one written');
    expect(find.text('Backing up to KINGSTON…'), findsOneWidget);
    expect(tester.widget<RowAction>(find.ancestor(of: find.text('Back up'), matching: find.byType(RowAction))).disabled, isTrue, reason: 'one backup at a time');

    device.tell!(const BackupProgress(done: 820000, total: 1400000000, files: 3, of: 40));
    await tester.pump();
    expect(find.text('Backing up to KINGSTON, 820 KB of 1.4 GB. Keep the drive plugged in.'), findsOneWidget);
    final bar = tester.widget<GlacierProgressBar>(find.byType(GlacierProgressBar));
    expect((bar.value, bar.max, bar.ariaLabel), (820000, 1400000000, 'Backing up'));
    // The look for drives does not change the page under a backup that is running.
    device.drives = [];
    await tester.pump(lookEvery);
    expect(rowLabels(tester, 'Back up to'), ['KINGSTON']);
    await tapOn(tester, actionSaying('Stop'));
    expect(device.cancels, 1);

    device.drives = [const BackupDrive(id: 'usb', name: 'KINGSTON', tree: 'content://tree/usb')];
    device.gate!.complete();
    await letRun(tester);
    expect(find.text('Backed up 312 notes to KINGSTON: 14 files written, 326 already there.'), findsOneWidget);
    expect(actionSaying('Eject'), findsNothing, reason: 'a phone has no Eject of the app’s own');
    expect(find.byType(GlacierProgressBar), findsNothing);
    await close(tester);
  });

  testWidgets('a drive already allowed is backed up to without the picker, and a refusal or a failure is said', (tester) async {
    device.drives = [const BackupDrive(id: 'usb', name: 'SD card', tree: 'content://tree/usb'), const BackupDrive(id: 'new', name: 'NEW')];
    await open(tester);
    await tapOn(tester, actionSaying('Back up').first);
    await letRun(tester);
    expect(device.allowed, isEmpty);
    expect(device.runs, ['SD card content://tree/usb']);

    device.allow = const DriveRefused('Choose the drive itself, not a folder on it, so the backup goes on its top level.');
    await tapOn(tester, actionSaying('Back up').last);
    await letRun(tester);
    expect(find.text('Choose the drive itself, not a folder on it, so the backup goes on its top level.'), findsOneWidget);
    device.allow = const DriveCancelled();
    await tapOn(tester, actionSaying('Back up').last);
    await letRun(tester);
    expect(find.textContaining('Choose the drive itself'), findsNothing, reason: 'a picker closed is nothing said');
    expect(device.runs.length, 1);
    await close(tester);
  });

  testWidgets('draws the drive’s Ghost.md folder as a tree, folders closed until tapped, read once for a backup', (tester) async {
    device.drives = [const BackupDrive(id: 'usb', name: 'KINGSTON', free: 5000000000, total: 8000000000, tree: 'content://tree/usb', last: LastBackup(backedUpAt: '2026-10-05T19:30:00Z', notes: 2))];
    device.files = const [HeldFile('Inbox/A.md', 1200), HeldFile('Workspaces/Work/Plan.md', 3400), HeldFile('Workspaces/Work/Plan.versions', 600), HeldFile('README.txt', 500)];
    await open(tester);
    expect(cardCalled('On KINGSTON'), findsOneWidget);
    final tree = find.byType(BackupTree);
    Finder inTree(String text) => find.descendant(of: tree, matching: find.text(text));
    // The folder itself is open: its folders and its own file, each with what is under it.
    expect(inTree('Ghost.md'), findsOneWidget);
    expect(inTree('4 files · 6 KB'), findsOneWidget);
    expect(inTree('Workspaces'), findsOneWidget);
    expect(inTree('2 files · 4 KB'), findsOneWidget);
    expect(inTree('README.txt'), findsOneWidget);
    expect(inTree('500 bytes'), findsOneWidget);
    expect(inTree('Plan.md'), findsNothing);
    await tapOn(tester, inTree('Workspaces'));
    await tapOn(tester, inTree('Work'));
    expect(inTree('Plan.md'), findsOneWidget);
    expect(inTree('3 KB'), findsOneWidget);
    await tapOn(tester, inTree('Workspaces'));
    expect(inTree('Plan.md'), findsNothing, reason: 'tapped again, it closes');
    // Looking again for drives does not read the files again.
    await tester.pump(lookEvery * 3);
    await letRun(tester);
    expect(device.listed, ['KINGSTON']);
    await close(tester);
  });

  testWidgets('draws no tree for a drive with no backup', (tester) async {
    device.drives = [const BackupDrive(id: 'new', name: 'NEW', free: 5000000000, total: 8000000000)];
    await open(tester);
    expect(cardCalled('On NEW'), findsNothing);
    expect(device.listed, isEmpty);
    expect(find.textContaining('Every note goes into a Ghost.md folder at the top of the drive'), findsOneWidget);
    await close(tester);
  });

  testWidgets('says to update an app too old to write a drive, and that a device without backups cannot', (tester) async {
    device.way = BackupWay.update;
    await open(tester);
    expect(find.text('Update Ghost.md to back up'), findsOneWidget);
    // Where a backup can go is found once, as the page is made: each of these is the page opened afresh.
    await tester.pumpWidget(const SizedBox.shrink());
    device.way = BackupWay.none;
    await open(tester);
    expect(find.text('Backups need the app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await showPane(tester, 'Backup', (context) => const BackupPane());
    await letRun(tester);
    expect(find.text('Backups need the app'), findsOneWidget, reason: 'and with no backups handed to it at all');
    await close(tester);
  });

  testWidgets('on the Mac’s road a backup done offers Eject', (tester) async {
    device.way = BackupWay.mac;
    device.drives = [const BackupDrive(id: '/Volumes/KINGSTON', name: 'KINGSTON')];
    await open(tester);
    expect(find.text('Plug in a drive'), findsNothing);
    await tapOn(tester, actionSaying('Back up'));
    await letRun(tester);
    expect(device.allowed, isEmpty);
    await tapOn(tester, actionSaying('Eject'));
    await letRun(tester);
    expect(device.ejected, ['KINGSTON']);
    expect(find.text('KINGSTON can be unplugged now.'), findsOneWidget);
    await close(tester);
  });
}
