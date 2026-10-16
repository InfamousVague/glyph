import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/backup.dart' show sizeSaid;
import '../../files/files_kit.dart';
import '../../files/read_pass.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds of Files and scans, on Library folder's page.
const List<SettingsFindable> filesFindable = [
  SettingsFindable('Read words in pictures', 'files and scans ocr text recognition scan search pictures photos receipts pdf'),
  SettingsFindable('Read what is already in notes', 'ocr existing pictures now scan'),
  SettingsFindable('Files in notes', 'attachments storage space pdf documents size files and scans'),
];

/// Files and scans (lib/files/): a short group of rows on Library folder's page, where the rest of what the app
/// keeps is said. Whether this device reads the words in pictures, scans and PDFs; reading what the notes already
/// show, now, with how far it has got; and how much the files in notes take here.
///
/// Over the app's [FilesKit] unless handed one. With none (a run that keeps no files) the rows are there and say so.
class FilesAndScans extends StatefulWidget {
  const FilesAndScans({super.key, this.kit});

  final FilesKit? kit;

  @override
  State<FilesAndScans> createState() => _FilesAndScansState();
}

/// What a run that keeps no files says.
const String noFilesHere = 'Files are not kept on this device yet.';

class _FilesAndScansState extends State<FilesAndScans> {
  FilesKit? get _kit => widget.kit ?? FilesKit.current;
  ({int files, int bytes})? _used;

  @override
  void initState() {
    super.initState();
    _kit?.pass.addListener(_changed);
    unawaited(_measure());
  }

  @override
  void dispose() {
    _kit?.pass.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _measure() async {
    final used = await _kit?.used();
    if (mounted && used != null) setState(() => _used = used);
  }

  /// What the reading of what is already in notes says under its name.
  static String progressWords(ReadPass? pass) {
    if (pass == null) return noFilesHere;
    final progress = pass.progress;
    if (!pass.on) return 'Turn on Read words in pictures first.';
    if (progress == null) return 'Every picture, scan and PDF your notes show that has not been read, one at a time, while you are not using the app.';
    if (progress.waiting != null) return '${progress.waiting} ${progress.done} of ${progress.total} read.';
    if (progress.total == 0) return 'Everything your notes show has been read.';
    if (progress.finished) return 'Read all ${progress.total}.';
    return 'Reading, ${progress.done} of ${progress.total}. It waits while you are using the app.';
  }

  @override
  Widget build(BuildContext context) {
    final kit = _kit;
    final pass = kit?.pass;
    final can = pass?.possible ?? false;
    final used = _used;
    final reading = pass != null && pass.busy && pass.progress?.finished == false;
    final why = kit == null ? noFilesHere : (can ? null : readsNoWords);
    return PaneSection(
      title: 'Files and scans',
      description: const Text('The words in pictures, scans and PDFs are read on this device, so a search finds the note they are in. Nothing is sent anywhere to be read.'),
      footer: const Text('Files up to 25 MB go to your other devices with their notes, sealed with your key. Larger ones stay on the device they were added on.'),
      children: [
        SettingRow(
          key: const ValueKey<String>('files-read'),
          label: 'Read words in pictures',
          hint: Text(why ??
              (defaultTargetPlatform == TargetPlatform.android
                  ? 'Each one is read as you add it. The reader comes from Google Play services the first time, and works with no connection after.'
                  : 'Each one is read as you add it, by the Mac’s own text recognition.')),
          control: can ? GlacierSwitch(ariaLabel: 'Read words in pictures', checked: pass!.on, onCheckedChange: (on) => pass.on = on) : null,
          disabledReason: why,
        ),
        SettingRow(
          key: const ValueKey<String>('files-read-existing'),
          label: 'Read what is already in notes',
          hint: Text(can ? progressWords(pass) : (why ?? '')),
          onPress: can && pass!.on && !reading ? () => unawaited(pass.readExisting()) : null,
          disabled: !can || !pass!.on || reading,
        ),
        SettingRow(
          key: const ValueKey<String>('files-used'),
          label: 'Files in notes',
          value: Text(kit == null ? 'None' : (used == null ? '…' : (used.files == 0 ? 'None yet' : '${used.files == 1 ? '1 file' : '${used.files} files'}, ${sizeSaid(used.bytes)}'))),
        ),
      ],
    );
  }
}
