import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../importer/import_report.dart';
import '../../importer/importer.dart';
import '../account_forms.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// Where an import comes from. Obsidian's and Evernote's are the app's own; Todoist's and Things' are each a
/// plugin's (lib/plugins/todoist, lib/plugins/things), on their pages and on Import only while they are on.
enum ImportKind { obsidian, evernote, todoist, things }

/// What Settings' search finds of each import, by the card or row that names it.
const Map<ImportKind, SettingsFindable> _findable = {
  ImportKind.obsidian: SettingsFindable('Obsidian vault', 'import obsidian vault folder markdown canvas move from'),
  ImportKind.evernote: SettingsFindable('Evernote export (.enex)', 'import evernote enex export notebook move from'),
  ImportKind.todoist: SettingsFindable('Todoist', 'import todoist tasks to-dos projects api token csv export move from'),
  ImportKind.things: SettingsFindable('Things 3', 'import things cultured code to-dos areas projects paste copy move from'),
};

/// What Settings' search finds on a page offering [kinds].
List<SettingsFindable> importFindableOf(Iterable<ImportKind> kinds) => [for (final kind in ImportKind.values) if (kinds.contains(kind)) _findable[kind]!];

/// Where an import goes, said over the app's own imports, or under a plugin's.
const String _where = 'Notes from another app come into a workspace of their own, named for the day, so they can be taken out again in one go. Nothing you have is changed.';

/// What Settings' search finds on Import with every import offered.
final List<SettingsFindable> importFindable = importFindableOf(ImportKind.values);

/// Where an import is: not begun, choosing, bringing things in, done, or stopped by a failure.
sealed class _State {
  const _State();
}

class _Idle extends _State {
  const _Idle();
}

class _Running extends _State {
  const _Running(this.from, this.progress, {this.waiting = 'Choose what to import.'});
  final String from;
  final ImportProgress? progress;

  /// What it says before the first note: the picker is open, or an account is being read.
  final String waiting;
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
/// (lib/importer/). Two rows, an Obsidian vault and Evernote's exports; then Todoist, by a token pasted for the one
/// import or a project's CSV export, and Things 3, from its database on a Mac or from what it copied (each with
/// a switch for what is done); while one runs, how far it has got and a word to stop it; after, what it brought,
/// what it renamed, what it left out, and the way to take it all back.
///
/// The token is held in the field while it is typed and nowhere else: pressing Import takes it out of the field,
/// hands it to the import and lets it go.
///
/// The calls are the [Importer] it is handed, or the one Settings was given (`SettingsFeatures.importer`). With
/// none, as in a picture of the page, the rows are drawn and cannot be pressed. Not on an iPhone, whose section is
/// not listed (settings_sections.dart).
///
/// [kinds] are the imports it offers: Settings › Import's are Obsidian's and Evernote's, and Todoist's and Things'
/// while their plugins are on (settings_sections.dart); each of those plugins' pages is this page with its own alone,
/// where the words on where an import goes stand under it.
class ImportPane extends StatefulWidget {
  const ImportPane({super.key, this.importer, this.kinds = ImportKind.values});

  final Importer? importer;
  final List<ImportKind> kinds;

  static Widget hosted(BuildContext context, {List<ImportKind> kinds = ImportKind.values}) => ImportPane(importer: SettingsHost.maybeOf(context)?.features.importer, kinds: kinds);

  @override
  State<ImportPane> createState() => _ImportPaneState();
}

class _ImportPaneState extends State<ImportPane> {
  _State _state = const _Idle();
  bool _stop = false;
  String _token = '';
  bool _todoistDone = false;
  bool _thingsDone = false;

  void _run(String from, Future<ImportReport?> Function(Importer importer) start, {String? waiting}) {
    final importer = widget.importer;
    if (importer == null) return;
    _stop = false;
    setState(() => _state = waiting == null ? _Running(from, null) : _Running(from, null, waiting: waiting));
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
    if (mounted && _state is _Running) setState(() => _state = _Running(from, progress, waiting: (_state as _Running).waiting));
  }

  void _obsidian() => _run('Obsidian', (importer) => importer.obsidian(progress: (p) => _progress('Obsidian', p), stopped: () => _stop));

  void _evernote() => _run('Evernote', (importer) => importer.evernote(progress: (p) => _progress('Evernote', p), stopped: () => _stop));

  void _todoist() {
    final token = _token.trim();
    if (token.isEmpty) return;
    setState(() => _token = '');
    final done = _todoistDone;
    _run('Todoist', (importer) => importer.todoist(token, done: done, progress: (p) => _progress('Todoist', p), stopped: () => _stop), waiting: 'Reading your Todoist account…');
  }

  void _todoistCsv() => _run('Todoist', (importer) => importer.todoistCsv(progress: (p) => _progress('Todoist', p), stopped: () => _stop));

  void _thingsOnMac() {
    final done = _thingsDone;
    _run('Things', (importer) => importer.thingsOnMac(done: done, progress: (p) => _progress('Things', p), stopped: () => _stop), waiting: 'Reading Things…');
  }

  void _thingsPaste() => _run('Things', (importer) => importer.thingsPaste(), waiting: 'Reading what Things copied…');

  void _remove(ImportReport report) {
    widget.importer?.remove(report);
    setState(() => _state = _Done(report, removed: true));
  }

  /// How far it has got, in words.
  static String _saying(_Running state) {
    final progress = state.progress;
    if (progress == null) return state.waiting;
    if (progress.total > 0) return 'Importing from ${state.from}, ${progress.done} of ${progress.total}. Keep Ghost.md open.';
    return 'Importing from ${state.from}, ${progress.done} ${progress.done == 1 ? 'note' : 'notes'} so far. Keep Ghost.md open.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _state;
    final can = widget.importer != null && state is! _Running;
    final progress = state is _Running ? state.progress : null;
    final mac = widget.importer?.thingsOnMacOffered ?? false;
    final kinds = widget.kinds;
    final core = kinds.contains(ImportKind.obsidian) || kinds.contains(ImportKind.evernote);
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
        if (core)
          PaneSection(
            description: const Text(_where),
            children: [
              if (kinds.contains(ImportKind.obsidian))
                SettingRow(
                  icon: const AppIcon(Lucide.folderInput, size: 20),
                  label: 'Obsidian vault',
                  hint: const Text('Choose the vault’s folder. Its notes, folders, pictures, files and canvases come in as they are.'),
                  onPress: can ? _obsidian : null,
                  disabled: !can,
                ),
              if (kinds.contains(ImportKind.evernote))
                SettingRow(
                  icon: const AppIcon(Lucide.bookOpen, size: 20),
                  label: 'Evernote export (.enex)',
                  hint: const Text('Choose one or more .enex files. Each becomes a notebook, with its tags, dates, pictures and files.'),
                  onPress: can ? _evernote : null,
                  disabled: !can,
                ),
            ],
          ),
        if (kinds.contains(ImportKind.todoist))
          PaneSection(
            title: 'Todoist',
            description: const Text('Each project becomes a note, its sections headings and its tasks to-dos, with their dates, priorities, labels and sub-tasks. The token is in Todoist › Settings › Integrations › Developer; it is used for this import and not kept.'),
            children: [
              SettingRow(
                label: 'Completed tasks too',
                hint: const Text('Those done in the last year, ticked. With a token only: an export has none.'),
                control: GlacierSwitch(ariaLabel: 'Completed tasks too', checked: _todoistDone, disabled: !can, onCheckedChange: (on) => setState(() => _todoistDone = on)),
              ),
              SettingsForm(
                children: [
                  GlacierInput(
                    ariaLabel: 'Todoist API token',
                    placeholder: 'API token',
                    type: GlacierInputType.password,
                    autoCorrect: false,
                    spellCheck: false,
                    disabled: !can,
                    value: _token,
                    onChange: (text) => setState(() => _token = text),
                    onSubmitted: (_) => can ? _todoist() : null,
                  ),
                  FormSubmit(wordKey: const ValueKey('import-todoist'), 'Import from Todoist', onPressed: can && _token.trim().isNotEmpty ? _todoist : null),
                ],
              ),
              SettingRow(
                icon: const AppIcon(Lucide.table, size: 20),
                label: 'Todoist CSV export (.csv)',
                hint: const Text('Choose one or more projects’ exports (on a project’s menu, Manage data › Export as CSV). Each becomes a note.'),
                onPress: can ? _todoistCsv : null,
                disabled: !can,
              ),
            ],
          ),
        if (kinds.contains(ImportKind.things))
          PaneSection(
            title: 'Things 3',
            description: const Text('Areas become notebooks and projects their pages, with headings, to-dos, When dates, deadlines, tags, notes and checklists.'),
            children: [
              if (mac) ...[
                SettingRow(
                  icon: const AppIcon(Lucide.squareCheckBig, size: 20),
                  label: 'From Things on this Mac',
                  hint: const Text('Reads a copy of Things’ own data, every area and project. The Mac may ask first.'),
                  onPress: can ? _thingsOnMac : null,
                  disabled: !can,
                ),
                SettingRow(
                  label: 'The Logbook too',
                  hint: const Text('Done and cancelled to-dos, ticked.'),
                  control: GlacierSwitch(ariaLabel: 'The Logbook too', checked: _thingsDone, disabled: !can, onCheckedChange: (on) => setState(() => _thingsDone = on)),
                ),
              ],
              SettingRow(
                icon: const AppIcon(Lucide.clipboardPaste, size: 20),
                label: 'Paste from Things',
                hint: const Text('In Things, open a list and choose Share › Copy, then press here. The list becomes one note.'),
                onPress: can ? _thingsPaste : null,
                disabled: !can,
              ),
            ],
          ),
        // A plugin's page has no Obsidian card to say it over: said under its own.
        if (!core) const SettingsFootnote(child: Text(_where)),
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
