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
import '../../account/ui_state.dart' show AccountScope;
import '../../core/library.dart' show NoteLibrary;
import '../../core/preferences.dart' show preferences;
import '../../orgs/types.dart' show Org;
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
  const NotionImportSection({super.key, this.job, this.target, this.workspaces, this.simple, this.makeOrg, this.library});

  /// The import; the app's own ([notionImport]) unless a test hands one.
  final NotionImportJob? job;

  /// Where it writes, and the workspaces to choose from: Settings' importer's (`SettingsFeatures.importer`) unless
  /// handed. With neither, as in a picture of the page, the rows are drawn and cannot be pressed.
  final ImportTarget Function()? target;
  final WorkspaceStore? workspaces;

  /// Simple mode; the preferences' unless handed.
  final bool? simple;

  /// How a new organization is made: the signed-in account's `Orgs.createOrg` (AccountScope) unless a test hands
  /// one. None signed in, and A new organization says so rather than importing elsewhere.
  final Future<Org> Function(String name)? makeOrg;

  /// The notes Remove what was imported reads; the target's library unless handed.
  final NoteLibrary? library;

  @override
  State<NotionImportSection> createState() => _NotionImportSectionState();
}

class _NotionImportSectionState extends State<NotionImportSection> {
  late final NotionImportJob _job = widget.job ?? notionImport;
  NotionShared? _shared;
  String? _trouble;
  bool _more = false;

  /// Where the person picked to import into: [_newOrg], [_newWorkspace] or a workspace's id; null for the default,
  /// the last import's workspace, else a new organization (Matt, 2026-11-04: "I want the import to start a new org").
  String? _into;
  static const String _newOrg = '<new organization>';
  static const String _newWorkspace = '<new workspace>';

  /// Remove what was imported, asked twice: armed by the first press for a few seconds.
  bool _armed = false;
  Timer? _disarm;
  String? _removed;

  @override
  void initState() {
    super.initState();
    _job.addListener(_changed);
    unawaited(_look());
  }

  @override
  void dispose() {
    _disarm?.cancel();
    _job.removeListener(_changed);
    super.dispose();
  }

  Future<Org> Function(String name)? get _makeOrg {
    if (widget.makeOrg != null) return widget.makeOrg;
    final services = AccountScope.maybeOf(context);
    final orgs = services?.orgs;
    if (orgs == null || !(services?.signedIn ?? false)) return null;
    return (name) => orgs.createOrg(name);
  }

  Future<void> _remove() async {
    _disarm?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      _disarm = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    final library = widget.library ?? _target?.call().library;
    final workspaces = _workspaces;
    if (library == null || workspaces == null) return;
    try {
      final moved = await _job.removeImported(library: library, workspaces: workspaces);
      if (mounted) {
        setState(() {
          _removed = moved == 1 ? '1 note moved to the trash.' : '$moved notes moved to the trash.';
          _into = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _trouble = failureWords(failure));
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      // Once an import has gone somewhere, that is where the next goes: Sync now, into the same place.
      if (_job.value is NotionImportDone) _into = null;
    });
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

  /// What is picked: the person's choice, else the last import's workspace, else a new organization.
  String _pick(WorkspaceStore? workspaces) {
    final chosen = _into;
    if (chosen != null && (chosen == _newOrg || chosen == _newWorkspace || (workspaces?.value.list.any((w) => w.id == chosen) ?? false))) return chosen;
    final last = workspaces == null ? null : _job.lastIn(workspaces);
    return last?.id ?? _newOrg;
  }

  /// The workspace the import goes into, where it is one already there.
  Workspace? _destination(WorkspaceStore? workspaces) {
    final pick = _pick(workspaces);
    return workspaces?.value.list.where((w) => w.id == pick).firstOrNull;
  }

  void _run() {
    final target = _target;
    final workspaces = _workspaces;
    if (target == null) return;
    setState(() {
      _trouble = null;
      _removed = null;
    });
    final pick = _pick(workspaces);
    if (pick == _newOrg && workspaces != null) {
      unawaited(_job.startInNewOrg(target(), makeOrg: _makeOrg, workspaces: workspaces));
    } else {
      unawaited(_job.start(target(), into: _destination(workspaces)));
    }
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
    final pick = _pick(workspaces);
    final where = into != null
        ? (workspaces == null ? into.name : workspacePathName(workspaces.value.list, into.id))
        : pick == _newWorkspace
            ? 'a new workspace, $notionWorkspaceName'
            : 'a new organization named for your Notion workspace${_makeOrg == null ? ' (sign in to Ghost.md first)' : ''}';

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
        if (_removed != null) SettingsCallout(key: const ValueKey('notion-import-removed'), icon: const AppIcon(Lucide.trash2, size: 20), child: Text(_removed!)),
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
            // Keep in sync (Matt, 2026-11-04: "we need a way to sync changes and update in real time"): once an import
            // has run into this place, on until switched off; how it went last, in words.
            if (again)
              SettingRow(
                key: const ValueKey('notion-import-live'),
                icon: const AppIcon(Lucide.refreshCw, size: 16),
                label: 'Keep in sync',
                hint: Text(_liveWords(last)),
                control: GlacierSwitch(ariaLabel: 'Keep in sync', checked: last.live, onCheckedChange: _job.setLive),
              ),
            SettingRow(
              key: const ValueKey('notion-import-run'),
              icon: AppIcon(again ? Lucide.refreshCw : Lucide.folderInput, size: 16),
              label: again ? 'Sync now' : 'Import everything',
              hint: Text(again
                  ? 'Reads all of what Notion shares and brings what is new or changed since ${_day(last.at)} into $where. Nothing here is deleted.'
                  : 'Into $where. Running it again later brings only what changed.'),
              control: RowAction(onPress: _run, disabled: !can || _job.syncing, child: Text(again ? 'Sync' : 'Import')),
            ),
            // Taking the last import away (Matt, 2026-11-04: "also delete the notes from my most recent notion import").
            if (last != null)
              SettingRow(
                key: const ValueKey('notion-import-remove'),
                icon: const AppIcon(Lucide.trash2, size: 16),
                label: 'Remove what was imported',
                hint: const Text('Moves the notes that came from Notion to the trash; they can be put back from there.'),
                control: RowAction(onPress: () => unawaited(_remove()), disabled: !can || _job.syncing, child: Text(_armed ? 'Tap again' : 'Remove')),
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
              _choice(_newOrg, 'A new organization', pick == _newOrg, Lucide.users, hint: 'Named for your Notion workspace, with you as its owner.'),
              _choice(_newWorkspace, 'A new workspace on this account', pick == _newWorkspace, Lucide.folderPlus),
              for (final w in workspaces.value.list) _choice(w.id, workspacePathName(workspaces.value.list, w.id), pick == w.id, isOrgWorkspace(w.id) ? Lucide.users : Lucide.folder, hint: w.id == last?.workspaceId ? 'Where the last import went' : null),
            ],
          ),
      ],
    );
  }

  /// What Keep in sync says: syncing now, or when it last checked, what changed on both sides, and what went wrong.
  String _liveWords(NotionImportPlace place) {
    if (!place.live) return 'Off. Sync now brings what changed when you ask.';
    final parts = <String>[
      if (_job.syncing) 'Syncing…' else if (place.checked != null) 'Synced ${_ago(place.checked!)}.' else 'Checks Notion every 2 minutes while Ghost.md is open.',
      if (place.both > 0) '${place.both == 1 ? '1 page' : '${place.both} pages'} changed in both; kept Ghost’s.',
      if (place.error != null && !_job.syncing) 'Last check: ${place.error}',
    ];
    return parts.join(' ');
  }

  static String _ago(int at) {
    final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    if (since.inMinutes < 1) return 'just now';
    if (since.inMinutes < 60) return since.inMinutes == 1 ? '1 minute ago' : '${since.inMinutes} minutes ago';
    if (since.inHours < 24) return since.inHours == 1 ? '1 hour ago' : '${since.inHours} hours ago';
    return 'on ${_day(at)}';
  }

  Widget _choice(String id, String label, bool picked, LucideIcon icon, {String? hint}) => SettingRow(
        key: ValueKey('notion-import-into-${id == _newOrg ? 'org' : id == _newWorkspace ? 'new' : id}'),
        icon: AppIcon(icon, size: 16),
        label: label,
        hint: hint == null ? null : Text(hint),
        control: picked ? const AppIcon(Lucide.check, size: 16) : null,
        onPress: _job.running
            ? null
            : () => setState(() => _into = id),
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
