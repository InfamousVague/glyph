/// The Cleanup plugin's page in Settings (docs/CLEANUP.md, "The page"; Matt, 2026-11-02: "spawn a task making a
/// 'cleanup' plugin that allows us to use whatever AI we choose that's connected to clean up and sort the notes in a
/// given folder"): the folder, the AI, what to do, exactly what is sent, Look for changes, then the review, then what
/// was applied with Undo, and the past runs with theirs. In Simple the passes past the basic three, Deeper folders and
/// Rewrite for clarity wait behind More, which opens in place (GHST-103).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/workspaces.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/settings_search.dart' show SettingsFindable;
import 'plan.dart';
import 'prompts.dart' show sentWords;
import 'records.dart';
import 'review.dart';
import 'service.dart';

/// What Settings' search finds on the page.
const List<SettingsFindable> cleanupFindable = [
  SettingsFindable('Folder', 'cleanup clean up tidy sort folder notes'),
  SettingsFindable('AI', 'cleanup ai model claude openai gemini aster local device'),
  SettingsFindable('What to do', 'sort titles duplicates merge tidy markdown tags links stale archive undo past runs'),
];

/// The page (see the library doc). [service] is a test's; the app's [CleanupService.current] where null.
class CleanupPane extends StatefulWidget {
  const CleanupPane({super.key, this.service});

  final CleanupService? service;

  @override
  State<CleanupPane> createState() => _CleanupPaneState();
}

class _CleanupPaneState extends State<CleanupPane> {
  bool _more = false;
  bool _picking = false;
  String? _said;
  CleanupService? _heard;

  CleanupService? get _service => widget.service ?? CleanupService.current;

  /// Local only as the AIs were last read under: a change reads them again.
  bool? _readUnder;

  @override
  void initState() {
    super.initState();
    preferences.addListener(_prefs);
    _listen();
  }

  void _prefs() {
    final service = _service;
    if (service != null && _readUnder != null && _readUnder != service.localOnly) {
      _readUnder = service.localOnly;
      unawaited(service.readAis());
    }
    _redraw();
  }

  @override
  void didUpdateWidget(CleanupPane old) {
    super.didUpdateWidget(old);
    _listen();
  }

  void _listen() {
    final service = _service;
    if (identical(service, _heard)) return;
    _heard?.removeListener(_redraw);
    _heard?.workspaces.removeListener(_redraw);
    _heard = service;
    if (service != null) {
      service.addListener(_redraw);
      service.workspaces.addListener(_redraw);
      _readUnder = service.localOnly;
      unawaited(service.readAis());
    }
  }

  @override
  void dispose() {
    preferences.removeListener(_prefs);
    _heard?.removeListener(_redraw);
    _heard?.workspaces.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _apply(CleanupService service, {bool all = false}) async {
    final done = await service.apply(all: all);
    if (!mounted || done == null) return;
    final record = done.record;
    final words = done.applied == 0 ? 'Nothing was changed.' : 'Applied ${done.applied} ${done.applied == 1 ? 'change' : 'changes'} to ${record.folderPath}.';
    _toast(words, undo: record.changes.isEmpty ? null : () => unawaited(_undo(service, record.id)));
  }

  Future<void> _undo(CleanupService service, String id) async {
    final undone = await service.undo(id);
    if (!mounted || undone == null) return;
    setState(() => _said = undone.left.isEmpty ? 'Taken back: ${undone.undone} ${undone.undone == 1 ? 'change' : 'changes'}.' : 'Taken back ${undone.undone}; left as they are: ${undone.left.join('; ')}.');
  }

  void _toast(String message, {VoidCallback? undo}) {
    try {
      GlacierToast.of(context).toast(message: Text(message), action: undo == null ? null : GlacierToastAction(label: 'Undo', onPress: undo));
    } on FlutterError {
      // A page drawn under no toasts (a test of its own) says it on the page alone.
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      // The page's cards all the same, with nothing to choose: what the search finds is on it.
      return PaneBody(children: [
        const SettingsCallout(child: Text('Cleanup needs your notes, which this build has not opened yet.')),
        const PaneSection(title: 'Folder', children: [SettingRow(icon: AppIcon(Lucide.folder, size: 16), label: 'Choose a folder', disabled: true)]),
        const PaneSection(title: 'AI', children: [SettingRow(icon: AppIcon(Lucide.info, size: 16), label: 'No AI connected', disabled: true)]),
        PaneSection(title: 'What to do', children: [
          for (final pass in CleanupPass.values) SettingRow(icon: AppIcon(passIcon(pass), size: 16), label: pass.label, hint: Text(pass.about), disabled: true),
        ]),
      ]);
    }
    if (!_more && settingsSought(context, const ['What to do'])) _more = true;
    final simple = preferences.value.simple;
    final full = !simple || _more;
    final stage = service.stage;
    final busy = stage == CleanupStage.running || stage == CleanupStage.applying;
    final plan = service.plan;
    return PaneBody(
      children: [
        if (service.problem != null) SettingsCallout(icon: const AppIcon(Lucide.triangleAlert, size: 18), child: Text(service.problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        if (stage == CleanupStage.review && plan != null)
          CleanupReview(
            plan: plan,
            ticked: service.ticked,
            aiName: service.ai?.name ?? 'The AI',
            onTick: service.tick,
            onTickPass: service.tickPass,
            onApply: () => unawaited(_apply(service)),
            onApplyAll: () => unawaited(_apply(service, all: true)),
            onDiscard: service.discard,
          )
        else if (stage == CleanupStage.applying)
          const SettingsCallout(icon: AppIcon(Lucide.loaderCircle, size: 18), child: Text('Applying…'))
        else ...[
          if (stage == CleanupStage.applied && service.last != null) _applied(service),
          ..._chooser(service, full: full, busy: busy),
        ],
        _pastRuns(service),
        if (service.ai != null) SettingsFootnote(key: const ValueKey('cleanup-sent'), child: Text(sentWords(service.ai!.name, service.ai!.sizes, local: service.ai!.local, options: service.options))),
      ],
    );
  }

  Widget _applied(CleanupService service) {
    final done = service.last!;
    final record = done.record;
    final undone = service.records.byId(record.id)?.undone ?? false;
    return PaneSection(
      title: 'Applied',
      children: [
        SettingRow(
          key: const ValueKey('cleanup-applied'),
          icon: const AppIcon(Lucide.check, size: 16),
          label: record.changes.isEmpty ? 'Nothing was changed' : record.summary,
          hint: Text('${record.folderPath}${done.skipped.isEmpty ? '' : ' · ${done.skipped.length} left as they were'}'),
          value: record.changes.isEmpty ? null : RowAction(key: const ValueKey('cleanup-undo'), onPress: () => unawaited(_undo(service, record.id)), disabled: undone, child: Text(undone ? 'Undone' : 'Undo')),
        ),
        if (done.misplaced.isNotEmpty)
          SettingRow(
            key: const ValueKey('cleanup-misplaced'),
            icon: const AppIcon(Lucide.triangleAlert, size: 16),
            label: 'Not where it should be: ${done.misplaced.length}',
            hint: Text(done.misplaced.join('\n')),
          ),
        if (done.skipped.isNotEmpty)
          SettingRow(
            key: const ValueKey('cleanup-skipped'),
            icon: const AppIcon(Lucide.info, size: 16),
            label: 'Left as they were: ${done.skipped.length}',
            hint: Text(done.skipped.take(6).join('\n')),
          ),
        SettingRow(key: const ValueKey('cleanup-again'), label: 'Clean up another folder', value: RowAction(onPress: service.again, child: const Text('Start'))),
      ],
    );
  }

  List<Widget> _chooser(CleanupService service, {required bool full, required bool busy}) {
    final folder = service.folder;
    final spaces = service.workspaces.value;
    final ai = service.ai;
    final options = service.options;
    final passes = [for (final pass in CleanupPass.values) if (full || pass.basic) pass];
    return [
      PaneSection(
        title: 'Folder',
        children: [
          SettingRow(
            key: const ValueKey('cleanup-folder'),
            icon: const AppIcon(Lucide.folder, size: 16),
            label: folder == null ? 'Choose a folder' : workspacePathName(spaces.list, folder.id),
            hint: Text(folder == null ? 'Its notes, and the notes in the folders inside it.' : '${service.noteCount} ${service.noteCount == 1 ? 'note' : 'notes'}, the folders inside it included${service.workspaces.orgOf(folder.id) != null ? ' · an organization’s: its notes stay in it' : ''}'),
            value: RowAction(onPress: () => setState(() => _picking = !_picking), disabled: busy, child: Text(_picking ? 'Done' : (folder == null ? 'Choose' : 'Change'))),
          ),
          if (_picking)
            for (final w in spaces.list)
              SettingRow(
                key: ValueKey('cleanup-folder-${w.id}'),
                label: workspacePathName(spaces.list, w.id),
                hint: Text('${service.workspaces.notesUnder(w.id).length} notes'),
                control: Pick(
                  checked: w.id == service.folderId,
                  label: 'Clean up ${w.name}',
                  onPress: () {
                    service.choose(w.id);
                    setState(() => _picking = false);
                  },
                ),
              ),
        ],
      ),
      PaneSection(
        title: 'AI',
        description: Text(service.localOnly ? 'Local only is on, so only the model on this device is used.' : 'The AI you have connected that reads the notes. Only it is sent anything.'),
        children: [
          if (service.aisRead && service.ais.isEmpty)
            SettingRow(
              key: const ValueKey('cleanup-no-ai'),
              icon: const AppIcon(Lucide.info, size: 16),
              label: service.localOnly ? 'No model on this device' : 'No AI connected',
              hint: Text(service.localOnly ? 'Download one in Settings › AI, or turn Local only off.' : 'Add Claude, OpenAI, Gemini, Aster or your own endpoint from the Market, or download a model in Settings › AI.'),
            ),
          for (final each in service.ais)
            SettingRow(
              key: ValueKey('cleanup-ai-${each.id}'),
              label: each.name,
              hint: Text([if (each.model != null && each.model!.isNotEmpty) each.model!, each.local ? 'Nothing leaves this device' : 'With your key'].join(' · ')),
              control: Pick(checked: ai?.id == each.id, label: 'Use ${each.name}', disabled: busy, onPress: () => service.chooseAi(each.id)),
            ),
        ],
      ),
      PaneSection(
        title: 'What to do',
        children: [
          for (final pass in passes)
            SettingRow(
              key: ValueKey('cleanup-pass-switch-${pass.name}'),
              icon: AppIcon(passIcon(pass), size: 16),
              label: pass.label,
              hint: Text(pass.about),
              control: GlacierSwitch(ariaLabel: pass.label, checked: options.has(pass), disabled: busy, onCheckedChange: (on) => service.setPass(pass, on)),
            ),
          if (full) ...[
            SettingRow(
              key: const ValueKey('cleanup-deeper'),
              label: 'Deeper folders',
              hint: const Text('New folders may go inside its folders too, not only directly inside it.'),
              control: GlacierSwitch(ariaLabel: 'Deeper folders', checked: options.deeper, disabled: busy || !options.has(CleanupPass.sort), onCheckedChange: service.setDeeper),
            ),
            SettingRow(
              key: const ValueKey('cleanup-rewrite'),
              label: 'Rewrite for clarity',
              hint: const Text('Tidy may change your words, not only their formatting. Off unless you say.'),
              control: GlacierSwitch(ariaLabel: 'Rewrite for clarity', checked: options.rewrite, disabled: busy || !options.has(CleanupPass.tidy), onCheckedChange: service.setRewrite),
            ),
          ] else
            SettingRow(
              key: const ValueKey('cleanup-more'),
              label: 'More',
              hint: const Text('Tidy, tags and links, stale notes, deeper folders and rewriting.'),
              control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
            ),
        ],
      ),
      PaneSection(
        children: [
          if (service.stage == CleanupStage.running)
            SettingRow(
              key: const ValueKey('cleanup-running'),
              icon: const AppIcon(Lucide.loaderCircle, size: 16),
              label: service.progress ?? 'Reading',
              hint: Text(service.estimate?.words ?? ''),
              value: RowAction(key: const ValueKey('cleanup-stop'), onPress: service.stop, child: const Text('Stop')),
            )
          else
            SettingRow(
              key: const ValueKey('cleanup-look'),
              icon: const AppIcon(Lucide.sparkles, size: 16),
              label: 'Look for changes',
              hint: Text(service.cannotLook ?? (ai == null ? '' : 'Asks ${ai.name}; nothing changes until you review and apply.')),
              value: RowAction(onPress: () => unawaited(service.look(context)), disabled: service.cannotLook != null, child: const Text('Look')),
            ),
        ],
      ),
    ];
  }

  Widget _pastRuns(CleanupService service) {
    final runs = service.records.all;
    if (runs.isEmpty) return const SizedBox.shrink();
    String when(DateTime at) {
      final local = at.toLocal();
      return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return PaneSection(
      title: 'Past runs',
      children: [
        for (final CleanupRecord run in runs.take(6))
          SettingRow(
            key: ValueKey('cleanup-run-${run.id}'),
            icon: const AppIcon(Lucide.history, size: 16),
            label: run.folderPath.isEmpty ? 'A folder' : run.folderPath,
            hint: Text('${when(run.at)} · ${run.aiName.isEmpty ? '' : '${run.aiName} · '}${run.summary}${run.misplaced.isEmpty ? '' : ' · ${run.misplaced.length} not where they should be'}'),
            value: RowAction(onPress: () => unawaited(_undo(service, run.id)), disabled: run.undone, child: Text(run.undone ? 'Undone' : 'Undo')),
          ),
      ],
    );
  }
}
