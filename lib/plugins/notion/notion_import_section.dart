/// Import from Notion, on the Notion plugin's page (Matt, 2026-11-04: "Add functionality in the notion plugin to
/// import a whole notion into ghost since we should have 1 to 1 functionality"; docs/NOTION_IMPORT.md).
///
/// Shown once Ghost.md is signed in to Notion. It says what Notion lets Ghost.md see ("142 pages and 6 databases"),
/// that a whole Notion needs the top-level pages picked on Notion's page, with Choose more pages there (the sign-in
/// again, whose page is where pages are picked); then Import everything, or Sync again once it has run, into a new
/// workspace called Notion or the one the person picks. While it runs, how far it has got and Stop (the activity
/// tray has the same); after, what came in and what was left out.
///
/// In Simple (GHST-103) the import itself stays, since it is how someone moves from Notion; where it goes waits
/// behind More, which opens in place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/workspaces.dart' show Workspace, WorkspaceStore, isOrgWorkspace, workspacePathName;
import '../../importer/import_report.dart';
import '../../importer/import_target.dart';
import '../../importer/notion/notion_import.dart' show NotionShared, notionWorkspaceName;
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/settings_host.dart';
import '../details_cache.dart' show failureWords;
import 'client.dart' show startNotionSignIn;
import 'notion_import_job.dart';

class NotionImportSection extends StatefulWidget {
  const NotionImportSection({super.key, this.job, this.target, this.workspaces, this.simple});

  /// The import; the app's own ([notionImport]) unless a test hands one.
  final NotionImportJob? job;

  /// Where it writes, and the workspaces to choose from: Settings' importer's (`SettingsFeatures.importer`) unless
  /// handed. With neither, as in a picture of the page, the rows are drawn and cannot be pressed.
  final ImportTarget Function()? target;
  final WorkspaceStore? workspaces;

  /// Simple mode; the preferences' unless handed.
  final bool? simple;

  @override
  State<NotionImportSection> createState() => _NotionImportSectionState();
}

class _NotionImportSectionState extends State<NotionImportSection> {
  late final NotionImportJob _job = widget.job ?? notionImport;
  NotionShared? _shared;
  String? _trouble;
  bool _more = false;

  /// The workspace picked to import into, by id; null for a new workspace (or, once one ran, the last one).
  String? _into;
  bool _chosen = false;

  @override
  void initState() {
    super.initState();
    _job.addListener(_changed);
    unawaited(_look());
  }

  @override
  void dispose() {
    _job.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _look() async {
    try {
      final shared = await _job.look();
      if (mounted) setState(() => _shared = shared);
    } catch (failure) {
      if (mounted) setState(() => _trouble = failureWords(failure));
    }
  }

  Future<void> _chooseMore() async {
    try {
      await startNotionSignIn();
    } catch (failure) {
      if (mounted) setState(() => _trouble = failureWords(failure));
    }
  }

  ImportTarget Function()? get _target => widget.target ?? SettingsHost.maybeOf(context)?.features.importer?.target;
  WorkspaceStore? get _workspaces => widget.workspaces ?? SettingsHost.maybeOf(context)?.features.importer?.workspaces;

  /// Where the import goes: the one picked, else the last import's workspace, else null for a new one.
  Workspace? _destination(WorkspaceStore? workspaces) {
    if (workspaces == null) return null;
    if (_chosen) return _into == null ? null : workspaces.value.list.where((w) => w.id == _into).firstOrNull;
    return _job.lastIn(workspaces);
  }

  void _run() {
    final target = _target;
    if (target == null) return;
    setState(() => _trouble = null);
    unawaited(_job.start(target(), into: _destination(_workspaces)));
  }

  static String _day(int at) {
    final when = DateTime.fromMillisecondsSinceEpoch(at);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${when.day} ${months[when.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _job.value;
    final workspaces = _workspaces;
    final target = _target;
    final into = _destination(workspaces);
    final last = _job.last;
    final again = into != null && last != null && into.id == last.workspaceId;
    final can = target != null && state is! NotionImportRunning;
    final simple = widget.simple ?? preferences.value.simple;
    final full = !simple || _more;
    final shared = _shared;
    final where = into == null ? 'a new workspace, $notionWorkspaceName' : (workspaces == null ? into.name : workspacePathName(workspaces.value.list, into.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state is NotionImportRunning)
          SettingsCallout(
            key: const ValueKey('notion-import-progress'),
            icon: const AppIcon(Lucide.folderInput, size: 20),
            action: RowAction(onPress: _job.stop, child: const Text('Stop')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.total == 0 ? 'Reading what Notion shares…' : 'Importing from Notion, ${state.done} of ${state.total} pages${state.on == null ? '' : ': ${state.on}'}. It goes on in the activity tray.'),
                if (state.total > 0) ...[
                  SizedBox(height: t.space(2)),
                  GlacierProgressBar(ariaLabel: 'Importing from Notion', value: state.done.toDouble(), max: state.total.toDouble(), size: GlacierProgressBarSize.sm),
                ],
              ],
            ),
          ),
        if (state is NotionImportDone) _done(context, state),
        if (state is NotionImportFailed) SettingsCallout(key: const ValueKey('notion-import-failed'), child: Text(state.why)),
        if (_trouble != null) SettingsCallout(child: Text(_trouble!)),
        PaneSection(
          title: 'Import from Notion',
          description: const Text('Brings every page and database Notion shares with Ghost.md into your notes as Markdown files: sub-pages as folders, databases as notebooks with a live table of their rows. For your whole Notion, pick your top-level pages on Notion’s page.'),
          children: [
            SettingRow(
              key: const ValueKey('notion-import-shared'),
              icon: const AppIcon(Lucide.squareKanban, size: 16),
              label: shared == null ? 'Counting what Notion shares…' : '${shared.pages} ${shared.pages == 1 ? 'page' : 'pages'} and ${shared.databases} ${shared.databases == 1 ? 'database' : 'databases'} shared',
              hint: Text(shared != null && shared.pages + shared.databases == 0
                  ? 'Notion shares nothing with Ghost.md yet. Choose your pages on Notion’s page, then come back.'
                  : 'Missing some? Choose more pages on Notion’s page (or every top-level page), then come back.'),
              control: RowAction(onPress: () => unawaited(_chooseMore()), child: const Text('Choose more pages')),
            ),
            SettingRow(
              key: const ValueKey('notion-import-run'),
              icon: AppIcon(again ? Lucide.refreshCw : Lucide.folderInput, size: 16),
              label: again ? 'Sync again' : 'Import everything',
              hint: Text(again
                  ? 'Brings what is new or changed since ${_day(last.at)} into $where. Nothing here is deleted.'
                  : 'Into $where. Running it again later brings only what changed.'),
              control: RowAction(onPress: _run, disabled: !can, child: Text(again ? 'Sync' : 'Import')),
            ),
            if (!full)
              SettingRow(
                key: const ValueKey('notion-import-more'),
                label: 'More',
                hint: const Text('Where it goes: a new workspace, or a folder or organization you have.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
          ],
        ),
        if (full && workspaces != null)
          PaneSection(
            key: const ValueKey('notion-import-where'),
            title: 'Where it goes',
            description: const Text('Pick a folder or an organization to bring Notion into it; an organization’s members see what comes in.'),
            children: [
              _choice(null, last == null || workspaces.value.list.every((w) => w.id != last.workspaceId) ? 'A new workspace, $notionWorkspaceName' : 'A new workspace', into == null, Lucide.folderPlus),
              for (final w in workspaces.value.list) _choice(w.id, workspacePathName(workspaces.value.list, w.id), into?.id == w.id, isOrgWorkspace(w.id) ? Lucide.users : Lucide.folder, hint: w.id == last?.workspaceId ? 'Where the last import went' : null),
            ],
          ),
      ],
    );
  }

  Widget _choice(String? id, String label, bool picked, LucideIcon icon, {String? hint}) => SettingRow(
        key: ValueKey('notion-import-into-${id ?? 'new'}'),
        icon: AppIcon(icon, size: 16),
        label: label,
        hint: hint == null ? null : Text(hint),
        control: picked ? const AppIcon(Lucide.check, size: 16) : null,
        onPress: _job.running
            ? null
            : () => setState(() {
                  _chosen = true;
                  _into = id;
                }),
      );

  Widget _done(BuildContext context, NotionImportDone state) {
    final report = state.report;
    final renamed = importRenamedSaid(report);
    final skipped = importSkippedSaid(report);
    return SettingsCallout(
      key: const ValueKey('notion-import-done'),
      icon: const AppIcon(Lucide.folderInput, size: 20),
      action: RowAction(onPress: _job.clear, child: const Text('Done')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: context.tokens.space(2),
        children: [
          Text('${state.stopped ? 'Stopped. ' : ''}${importDoneSaid(report)}${state.stopped ? ' Import again to bring the rest.' : ''}'),
          if (renamed != null) Text(renamed),
          if (skipped != null) Text(skipped),
        ],
      ),
    );
  }
}
