import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../core/library_folder.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'files_pane.dart';
import 'settings_host.dart';

/// What Settings' search finds on Library folder (`findable`, src/app/settings/LibraryFolderPane.findable.ts), by its
/// cards' titles.
const List<SettingsFindable> libraryFolderFindable = [
  SettingsFindable('Where your notes are', 'library folder choose move obsidian vault icloud dropbox syncthing backup drive'),
  SettingsFindable('Good to know', 'sync google drive index pictures recordings'),
  // Files and scans, a group of its own on this page (files_pane.dart).
  ...filesFindable,
];

/// Why the page cannot choose a folder here, when it cannot (`UNAVAILABLE`).
const Map<FolderWay, (String, String)> _unavailable = {
  FolderWay.browser: ('Only in the app', 'In a browser the notes are kept by the browser itself. The Mac and Android apps keep them as Markdown files, in a folder you can choose here.'),
  FolderWay.update: ('Needs the app’s next update', 'This version of Ghost.md keeps the notes in its own folder only. Update it to choose another.'),
  FolderWay.none: ('Not on iPhone yet', 'On an iPhone the notes stay in Ghost.md’s own folder for now.'),
};

/// What the page is doing: nothing, a folder looked into and waiting for a yes, the way home being asked, or a move
/// under way (`Step`).
sealed class _Step {
  const _Step();
}

class _Idle extends _Step {
  const _Idle();
}

class _Confirm extends _Step {
  const _Confirm(this.candidate);
  final Candidate candidate;
}

class _Home extends _Step {
  const _Home();
}

class _Moving extends _Step {
  const _Moving();
}

/// Where the notes are, as the first row says it (`whereSaid`): its label and its hint.
(String, String) whereSaid(LibraryStatus status) {
  final count = status.notes == 1 ? '1 note' : '${status.notes} notes';
  if (status.kind == 'app') return ('Ghost.md’s own folder', '$count. ${status.own ?? 'Inside the app’s storage.'}');
  if (status.kind == 'folder') return (status.name ?? 'A folder of yours', '$count. ${status.path ?? ''}'.trim());
  return ((status.name ?? '').isEmpty ? 'A folder of yours' : status.name!, '$count. Chosen on this phone.');
}

/// Port of `LibraryFolderPane` (src/app/settings/LibraryFolderPane.tsx; docs/DESIGN.md §187 of tauri/, a setting
/// of its own since §205): where the notes are now; Choose a folder…, which opens the system's own picker and then
/// says, before anything moves, what is in the folder and what will happen to the notes; Use Ghost.md's own folder,
/// with a copy of the notes or none; and what is good to know, by device. Nothing here deletes a file in a folder of
/// the person's, and the page says so where it matters.
///
/// What differs from the web original:
/// - The folder's calls are the [LibraryFolder] it is handed (lib/core/library_folder.dart), or the one Settings was
///   given (`SettingsFeatures.libraryFolder`). With none, it is the page on a build that cannot choose: "Needs the
///   app's next update".
/// - **The seam.** Settings' `library` row opens this page (`LibraryFolderPane.hosted`); what is left is for the
///   root to hand Settings `SettingsFeatures(libraryFolder: LibraryFolder(invoke: core.invoke, onNotesChanged: …))`.
class LibraryFolderPane extends StatefulWidget {
  const LibraryFolderPane({super.key, this.folder});

  final LibraryFolder? folder;

  static Widget hosted(BuildContext context) => LibraryFolderPane(folder: SettingsHost.maybeOf(context)?.features.libraryFolder);

  @override
  State<LibraryFolderPane> createState() => _LibraryFolderPaneState();
}

class _LibraryFolderPaneState extends State<LibraryFolderPane> {
  FolderWay? _way;
  LibraryStatus? _status;
  _Step _step = const _Idle();
  ({String text, bool failed})? _said;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void didUpdateWidget(LibraryFolderPane old) {
    super.didUpdateWidget(old);
    if (!identical(old.folder, widget.folder)) unawaited(_find());
  }

  Future<void> _find() async {
    final folder = widget.folder;
    final found = folder == null ? FolderWay.update : await folder.way();
    if (!mounted || !identical(folder, widget.folder)) return;
    setState(() => _way = found);
    if (found == FolderWay.mac || found == FolderWay.android) await _read();
  }

  Future<void> _read() async {
    try {
      final status = await widget.folder!.status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _said = (text: failureOf(error), failed: true));
    }
  }

  Future<void> _choose() async {
    setState(() => _said = null);
    try {
      final candidate = await widget.folder!.choose();
      if (mounted) setState(() => _step = candidate != null ? _Confirm(candidate) : const _Idle());
    } catch (error) {
      if (mounted) setState(() => _said = (text: failureOf(error), failed: true));
    }
  }

  Future<void> _run(Future<Moved> Function() move, String Function(String text) done) async {
    setState(() => _step = const _Moving());
    try {
      final moved = await move();
      if (!mounted) return;
      setState(() {
        _status = moved.status;
        _said = (text: done(movedSaid(moved)), failed: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _said = (text: failureOf(error), failed: true));
    }
    setState(() => _step = const _Idle());
  }

  static const Widget _hero = PaneSection(
    children: [
      PaneHero(
        glyph: AppIcon(Lucide.folder, size: 22),
        title: 'Library folder',
        meta: Text('Keep your notes in a folder of your own: an Obsidian vault, iCloud Drive or Dropbox, a Syncthing folder, a backup drive. They are Markdown files already.'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final way = _way;
    final why = _unavailable[way];
    if (why != null) {
      return PaneBody(
        children: [
          _hero,
          SettingsEmpty(icon: const AppIcon(Lucide.folder, size: 22), title: why.$1, body: Text(why.$2)),
          const FilesAndScans(),
        ],
      );
    }

    final folder = widget.folder;
    final status = _status;
    final where = status == null ? null : whereSaid(status);
    final own = status?.kind == 'app' || status?.reachable == false;
    final step = _step;
    final moving = step is _Moving;
    final said = _said;

    return PaneBody(
      children: [
        _hero,
        if (status != null && !status.reachable)
          SettingsCallout(
            icon: const AppIcon(Lucide.triangleAlert, size: 18),
            child: Text(
              '${status.name ?? 'Your folder'} can’t be reached: a drive unplugged, a folder moved, or the phone’s permission taken back. Ghost.md is using its own folder until it is back, and the notes in yours are untouched. Open Ghost.md again once it is back, or choose it again.',
            ),
          ),
        if (said != null) SettingsCallout(icon: AppIcon(said.failed ? Lucide.triangleAlert : Lucide.info, size: 18), child: Text(said.text)),
        PaneSection(
          title: 'Where your notes are',
          description: const Text('Each note is a Markdown file, in a folder for its workspace, so any app that opens a folder of Markdown opens these.'),
          children: [
            SettingRow(icon: const AppIcon(Lucide.folderOpen, size: 16), label: where?.$1 ?? 'Reading…', hint: where == null ? null : Text(where.$2)),
            SettingRow(
              icon: const AppIcon(Lucide.folder, size: 16),
              label: 'Choose a folder…',
              hint: Text(way == FolderWay.android ? 'In the phone’s folder picker.' : 'In the Mac’s folder panel.'),
              onPress: moving || folder == null ? null : () => unawaited(_choose()),
              disabled: moving,
            ),
            if (status != null && status.kind != 'app')
              SettingRow(
                icon: const AppIcon(Lucide.hardDrive, size: 16),
                label: 'Use Ghost.md’s own folder',
                hint: const Text('Your folder keeps every file.'),
                onPress: moving ? null : () => setState(() => _step = const _Home()),
                disabled: moving,
              ),
          ],
        ),
        if (step is _Confirm)
          PaneSection(
            title: 'Use ${step.candidate.name}?',
            description: Text(candidateSaid(step.candidate, own)),
            children: [
              SettingRow(
                label: 'Use this folder',
                hint: step.candidate.path == null ? null : Text(step.candidate.path!),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowAction(onPress: () => unawaited(_run(folder!.move, (text) => 'Your notes are in ${step.candidate.name} now. $text')), child: const Text('Use it')),
                    RowAction(onPress: () => setState(() => _step = const _Idle()), child: const Text('Cancel')),
                  ],
                ),
              ),
            ],
          ),
        if (step is _Home)
          PaneSection(
            title: 'Back to Ghost.md’s own folder?',
            description: Text('${where?.$1 ?? 'Your folder'} keeps every file either way: Ghost.md never deletes anything in a folder of yours.'),
            children: [
              SettingRow(
                label: 'Bring a copy back',
                hint: const Text('Every note in the folder, copied into Ghost.md’s own.'),
                control: RowAction(onPress: () => unawaited(_run(() => folder!.backToOwnFolder(true), (text) => 'Back in Ghost.md’s own folder. $text')), child: const Text('Copy')),
              ),
              SettingRow(
                label: 'Start empty',
                hint: const Text('Ghost.md’s own folder as it is, and nothing copied.'),
                control: RowAction(onPress: () => unawaited(_run(() => folder!.backToOwnFolder(false), (_) => 'Back in Ghost.md’s own folder.')), child: const Text('Start')),
              ),
              SettingRow(label: 'Stay in the folder', control: RowAction(onPress: () => setState(() => _step = const _Idle()), child: const Text('Cancel'))),
            ],
          ),
        if (moving) const SettingsCallout(icon: AppIcon(Lucide.folder, size: 18), child: Text('Moving your notes. Keep Ghost.md open.')),
        // Files in notes, scans and the words read in them (files_pane.dart).
        const FilesAndScans(),
        PaneSection(
          title: 'Good to know',
          children: [
            if (way == FolderWay.android) ...const [
              SettingRow(
                label: 'A folder on the phone is the reliable one',
                hint: Text('Syncthing keeps one in step with a computer. Dropbox and Google Drive reach Ghost.md through their own apps, which may keep a note online only and open it slowly.'),
              ),
              SettingRow(label: 'iCloud Drive', hint: Text('Has no Android app, so it isn’t in the picker. Choose it on the Mac.')),
            ] else ...const [
              SettingRow(label: 'iCloud Drive and Dropbox', hint: Text('With storage optimised, a note the Mac has taken off its disk stays in the list, and comes down when it is opened.')),
              SettingRow(label: 'Obsidian', hint: Text('Its notes keep their names and their properties when Ghost.md edits them, so links still find them. .obsidian and its trash are left alone.')),
            ],
            const SettingRow(label: 'Sync', hint: Text('The folder’s own Markdown files become notes, so with an account they go to your other devices too.')),
            const SettingRow(label: 'What stays in Ghost.md', hint: Text('Pictures, films and recordings, and the index that makes the list instant: never in your folder, so a sync service never copies half of it.')),
          ],
        ),
        const SettingsFootnote(
          child: Text('Ghost.md keeps a small .glyph folder in yours for what a note has that isn’t words (a recording’s phrases). A reset in Developer forgets the folder and leaves every file in it.'),
        ),
      ],
    );
  }
}
