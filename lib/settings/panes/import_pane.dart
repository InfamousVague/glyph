import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../export/ghostex_calls.dart' show Ghostex;
import '../../importer/import_report.dart';
import '../../importer/importer.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'ghostex_cards.dart';
import 'settings_host.dart';

/// What Settings' search finds on Import.
const List<SettingsFindable> importFindable = [
  SettingsFindable('Obsidian vault', 'import obsidian vault folder markdown canvas move from'),
  SettingsFindable('Evernote export (.enex)', 'import evernote enex export notebook move from'),
  ghostexImportFindable,
];

/// Where an import is: not begun, choosing, bringing things in, done, or stopped by a failure.
sealed class _State {
  const _State();
}

class _Idle extends _State {
  const _Idle();
}

class _Running extends _State {
  const _Running(this.from, this.progress);
  final String from;
  final ImportProgress? progress;
}

class _Done extends _State {
  const _Done(this.report, {this.removed = false});
  final ImportReport report;
  final bool removed;
}

class _Failed extends _State {
  const _Failed(this.why);
  final String why;
}

/// Settings › Import, beside Export: notes from another app, brought into one workspace of their own
/// (lib/importer/). Two rows, an Obsidian vault and Evernote's exports; while one runs, how far it has got and a
/// word to stop it; after, what it brought, what it renamed, what it left out, and the way to take it all back.
///
/// The calls are the [Importer] it is handed, or the one Settings was given (`SettingsFeatures.importer`). With
/// none, as in a picture of the page, the rows are drawn and cannot be pressed. Not on an iPhone, whose section is
/// not listed (settings_sections.dart).
///
/// Below them, A .ghostex file (ghostex_cards.dart): an export of Ghost.md's own read back, over the [Ghostex] it is
/// handed (`SettingsFeatures.ghostex`).
class ImportPane extends StatefulWidget {
  const ImportPane({super.key, this.importer, this.ghostex});

  final Importer? importer;
  final Ghostex? ghostex;

  static Widget hosted(BuildContext context) {
    final features = SettingsHost.maybeOf(context)?.features;
    return ImportPane(importer: features?.importer, ghostex: features?.ghostex);
  }

  @override
  State<ImportPane> createState() => _ImportPaneState();
}

class _ImportPaneState extends State<ImportPane> {
  _State _state = const _Idle();
  bool _stop = false;

  void _run(String from, Future<ImportReport?> Function(Importer importer) start) {
    final importer = widget.importer;
    if (importer == null) return;
    _stop = false;
    setState(() => _state = _Running(from, null));
    unawaited(start(importer).then<void>(
      (report) {
        if (mounted) setState(() => _state = report == null ? const _Idle() : _Done(report));
      },
      onError: (Object failure) {
        if (mounted) setState(() => _state = _Failed(failure is StateError ? failure.message : 'The import could not finish.'));
      },
    ));
  }

  void _progress(String from, ImportProgress progress) {
    if (mounted && _state is _Running) setState(() => _state = _Running(from, progress));
  }

  void _obsidian() => _run('Obsidian', (importer) => importer.obsidian(progress: (p) => _progress('Obsidian', p), stopped: () => _stop));

  void _evernote() => _run('Evernote', (importer) => importer.evernote(progress: (p) => _progress('Evernote', p), stopped: () => _stop));

  void _remove(ImportReport report) {
    widget.importer?.remove(report);
    setState(() => _state = _Done(report, removed: true));
  }

  /// How far it has got, in words.
  static String _saying(_Running state) {
    final progress = state.progress;
    if (progress == null) return 'Choose what to import.';
    if (progress.total > 0) return 'Importing from ${state.from}, ${progress.done} of ${progress.total}. Keep Ghost.md open.';
    return 'Importing from ${state.from}, ${progress.done} ${progress.done == 1 ? 'note' : 'notes'} so far. Keep Ghost.md open.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _state;
    final can = widget.importer != null && state is! _Running;
    final progress = state is _Running ? state.progress : null;
    return PaneBody(
      children: [
        if (state is _Running)
          SettingsCallout(
            icon: const AppIcon(Lucide.folderInput, size: 20),
            action: progress == null ? null : RowAction(onPress: () => _stop = true, child: const Text('Stop')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_saying(state)),
                if (progress != null && progress.total > 0) ...[
                  SizedBox(height: t.space(2)),
                  GlacierProgressBar(ariaLabel: 'Importing', value: progress.done.toDouble(), max: progress.total.toDouble(), size: GlacierProgressBarSize.sm),
                ],
              ],
            ),
          ),
        if (state is _Done) ..._done(context, state),
        if (state is _Failed) SettingsCallout(child: Text(state.why)),
        PaneSection(
          description: const Text('Notes from another app come into a workspace of their own, named for the day, so they can be taken out again in one go. Nothing you have is changed.'),
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.folderInput, size: 20),
              label: 'Obsidian vault',
              hint: const Text('Choose the vault’s folder. Its notes, folders, pictures, files and canvases come in as they are.'),
              onPress: can ? _obsidian : null,
              disabled: !can,
            ),
            SettingRow(
              icon: const AppIcon(Lucide.bookOpen, size: 20),
              label: 'Evernote export (.enex)',
              hint: const Text('Choose one or more .enex files. Each becomes a notebook, with its tags, dates, pictures and files.'),
              onPress: can ? _evernote : null,
              disabled: !can,
            ),
          ],
        ),
        GhostexImportCard(ghostex: widget.ghostex),
      ],
    );
  }

  List<Widget> _done(BuildContext context, _Done state) {
    final report = state.report;
    final renamed = importRenamedSaid(report);
    final skipped = importSkippedSaid(report);
    if (state.removed) {
      return [SettingsCallout(icon: const AppIcon(Lucide.trash2, size: 20), child: Text('The import is in the trash, and its workspace is gone. Restore its notes from the trash, or empty it to remove them for good.'))];
    }
    return [
      SettingsCallout(
        icon: const AppIcon(Lucide.folderInput, size: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: context.tokens.space(2),
          children: [
            Text(importDoneSaid(report)),
            if (renamed != null) Text(renamed),
            if (skipped != null) Text(skipped),
          ],
        ),
      ),
      if (report.groupId != null)
        PaneSection(
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.trash2, size: 20),
              label: 'Remove this import',
              hint: Text('Puts everything it brought into the trash and takes ${report.groupName} away.'),
              onPress: () => _remove(report),
            ),
          ],
        ),
    ];
  }
}
