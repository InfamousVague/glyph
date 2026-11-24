/// "Sync a folder" in My files on a computer (GMFB-38: "Sync a folder on your computer with a drive"): the folder
/// chosen with its path, what the sync is doing, and Stop syncing. The rules are lib/files/folder_sync.dart's; this
/// is the way in and the words.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../files/folder_sync.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../platform_info.dart';
import '../common.dart';

/// The computer's own "choose a folder", asked of the system with nothing new built into the app: the Mac's
/// (`choose folder` through osascript), Windows' folder dialog (through PowerShell), and GNOME's zenity or KDE's
/// kdialog on Linux. The path chosen; null where it was put away or there is no chooser.
Future<String?> pickSyncFolder() async {
  const words = 'Choose a folder to sync with My files';
  final tries = <(String, List<String>)>[
    if (PlatformInfo.isMacOS) ('osascript', ['-e', 'POSIX path of (choose folder with prompt "$words")']),
    if (PlatformInfo.isWindows)
      (
        'powershell',
        [
          '-NoProfile',
          '-STA',
          '-Command',
          "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Add-Type -AssemblyName System.Windows.Forms; \$d = New-Object System.Windows.Forms.FolderBrowserDialog; \$d.Description = '$words'; \$d.ShowNewFolderButton = \$true; if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Out.Write(\$d.SelectedPath) }",
        ]
      ),
    if (PlatformInfo.isLinux) ...[
      ('zenity', ['--file-selection', '--directory', '--title=$words']),
      ('kdialog', ['--getexistingdirectory', PlatformInfo.environment['HOME'] ?? '.', '--title', words]),
    ],
  ];
  for (final (tool, args) in tries) {
    try {
      final r = await Process.run(tool, args, stdoutEncoding: utf8);
      if (r.exitCode != 0) return null;
      final path = '${r.stdout}'.trim();
      return path.isEmpty ? null : path;
    } on ProcessException {
      // Not installed: the next.
      continue;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// The entry at the top of My files: "Sync a folder" where none is chosen; else its path, its state line and Stop
/// syncing.
class FolderSyncEntry extends StatefulWidget {
  const FolderSyncEntry({super.key, required this.sync, this.pick});
  final FolderSync sync;

  /// What chooses the folder, the system's where null (a test gives its own).
  final Future<String?> Function()? pick;

  @override
  State<FolderSyncEntry> createState() => _FolderSyncEntryState();
}

class _FolderSyncEntryState extends State<FolderSyncEntry> {
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    widget.sync.load();
    // My files opened: a pass, where a folder is chosen.
    unawaited(widget.sync.pass());
  }

  Future<void> _choose() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      final path = await (widget.pick ?? pickSyncFolder)();
      if (path == null || !mounted) return;
      final why = widget.sync.choose(path);
      if (why != null && mounted) toast(context, why);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        final root = widget.sync.root;
        final quiet = pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'));
        return Padding(
          key: const ValueKey('folder-sync'),
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(1), t.space(3), t.space(2)),
          child: SettingsCallout(
            icon: const AppIcon(Lucide.folderInput, size: 18),
            action: root == null
                ? RowAction(key: const ValueKey('folder-sync-choose'), onPress: _choose, disabled: _choosing, child: const Text('Sync a folder'))
                : RowAction(key: const ValueKey('folder-sync-stop'), onPress: widget.sync.stop, child: const Text('Stop syncing')),
            child: root == null
                ? const Text('Keep a folder on this computer in step with My files.', key: ValueKey('folder-sync-words'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(root, key: const ValueKey('folder-sync-path'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(widget.sync.line.isEmpty ? (widget.sync.running ? 'Looking for changes' : 'Waiting to sync') : widget.sync.line, key: const ValueKey('folder-sync-line'), style: quiet),
                    Text('New and changed files go both ways. Removing a file here doesn\'t remove it from My files yet, so it comes back.', style: quiet),
                  ]),
          ),
        );
      },
    );
  }
}
