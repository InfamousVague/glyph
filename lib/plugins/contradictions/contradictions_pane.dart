/// The contradiction finder's page in Settings (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder: spots
/// when a newer note disagrees with an older one"): who checks, Check now (with the cost asked first where it is a big
/// run, lib/activity/activity_cost.dart `askJobCost`) or Stop while it runs, when it checks on its own, and what may be
/// out of date, each with Open, Mark superseded and Not a conflict.
///
/// In Simple (`Preferences.simple`) how sure a finding must be, Within each folder only and Organization notes wait
/// behind More, which opens in place.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../activity/activity_cost.dart' show askJobCost;
import '../../ai/contradictions/ai.dart';
import '../../ai/contradictions/findings.dart';
import '../../ai/contradictions/runner.dart';
import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../settings/kit/settings_kit.dart';
import 'contradictions.dart' show contradictionOpenNote, contradictionRunner;

class ContradictionsPane extends StatefulWidget {
  const ContradictionsPane({super.key, this.runner, this.aiName});

  /// The finder: a test's own, else the app's ([contradictionRunner]).
  final ContradictionRunner? runner;

  /// Who would check, for the page's line: a test's own, else ai.dart's [appContradictionAiName].
  final String Function()? aiName;

  @override
  State<ContradictionsPane> createState() => _ContradictionsPaneState();
}

class _ContradictionsPaneState extends State<ContradictionsPane> {
  bool _more = false;
  String? _problem;
  String? _said;

  /// Before the app has made its finder (and in a test that draws the page alone), one with no notes and nobody to
  /// ask, so the page is drawn whole and Settings' search finds what it lists.
  late final ContradictionRunner _idle = ContradictionRunner(notes: () => const [], pickAi: () async => null);

  ContradictionRunner get _runner => widget.runner ?? contradictionRunner.value ?? _idle;

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  Future<void> _checkNow() async {
    final runner = _runner;
    if (runner.running) return;
    setState(() {
      _problem = null;
      _said = null;
    });
    final ai = await runner.pickAi();
    if (!mounted) return;
    if (ai == null) {
      setState(() => _problem = noAiWords(localOnly: preferences.value.localOnly));
      return;
    }
    final pairs = await runner.plan();
    if (!mounted) return;
    if (pairs.isEmpty) {
      runner.setSettings(runner.settings.copyWith(ranOnce: true));
      setState(() => _said = 'Nothing new to compare: no two notes share enough names, dates or numbers since the last check.');
      return;
    }
    final estimate = runner.estimate(pairs.length, ai);
    if (!await askJobCost(context, estimate, title: 'Check ${pairs.length} note pairs with ${ai.name}?')) return;
    final end = await runner.run(personStarted: true, pairs: pairs);
    if (!mounted) return;
    if (end == RunEnd.failed) setState(() => _problem = runner.problem);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ContradictionRunner?>(
      valueListenable: contradictionRunner,
      builder: (context, _, _) {
        final runner = _runner;
        return ListenableBuilder(listenable: Listenable.merge([preferences, runner]), builder: (context, _) => _page(context, runner));
      },
    );
  }

  Widget _page(BuildContext context, ContradictionRunner runner) {
    final prefs = preferences.value;
    final settings = runner.settings;
    if (!_more && settingsSought(context, const ['How sure', 'Organization notes'])) _more = true;
    final full = !prefs.simple || _more;
    final who = (widget.aiName ?? appContradictionAiName)();
    final open = runner.open;
    void set(ContradictionSettings next) => runner.setSettings(next);
    return PaneBody(
      children: [
        if (_problem != null) SettingsCallout(icon: const AppIcon(Lucide.triangleAlert, size: 18), child: Text(_problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        PaneSection(
          title: 'Check for contradictions',
          description: Text(
            'Finds where a newer note changes what an older one says, like a release day or a price, and marks the older line “Out of date?”. ${prefs.localOnly ? 'Local only is on, so only the model on this device checks.' : 'Checked by $who.'}',
          ),
          children: [
            SettingRow(
              key: const ValueKey('contradictions-check'),
              icon: const AppIcon(Lucide.textSearch, size: 18),
              label: runner.running ? 'Checking ${runner.done} of ${runner.total} note pairs' : 'Check now',
              hint: Text(runner.running ? 'You can leave this page; it goes on in the background.' : (settings.lastRun == null ? 'Never checked yet. Nothing runs on its own until you check once.' : 'Last checked ${_when(settings.lastRun!)}.')),
              value: runner.running ? RowAction(key: const ValueKey('contradictions-stop'), onPress: runner.stop, child: const Text('Stop')) : RowAction(key: const ValueKey('contradictions-run'), onPress: () => unawaited(_checkNow()), child: const Text('Check')),
            ),
          ],
        ),
        PaneSection(
          title: 'When it checks',
          footer: settings.ranOnce ? null : const Text('On its own only after you have checked once by hand.'),
          children: [
            for (final schedule in ContradictionSchedule.values)
              SettingRow(
                key: ValueKey('contradictions-when-${schedule.name}'),
                label: schedule.label,
                hint: Text(switch (schedule) {
                  ContradictionSchedule.off => 'Only when you press Check.',
                  ContradictionSchedule.saved => 'A couple of minutes after you stop editing, the notes you saved.',
                  ContradictionSchedule.nightly => 'Once a day, early in the morning or when you next open the app.',
                }),
                control: Pick(checked: settings.schedule == schedule, label: 'Check ${schedule.label.toLowerCase()}', onPress: () => set(settings.copyWith(schedule: schedule))),
              ),
          ],
        ),
        PaneSection(
          title: 'May be out of date',
          children: [
            if (open.isEmpty)
              const SettingRow(key: ValueKey('contradictions-none'), label: 'Nothing out of date', hint: Text('What a check finds shows here and on the note’s line.'))
            else
              for (final finding in open) _FindingRow(key: ValueKey('contradiction-${finding.key}'), finding: finding, runner: runner),
          ],
        ),
        if (full) ...[
          PaneSection(
            title: 'How sure',
            description: const Text('How sure the AI must be before a line is marked. Surer means fewer marks, and fewer wrong ones.'),
            children: [
              for (final (value, label) in const [(0.7, 'Fairly sure'), (0.8, 'Sure'), (0.9, 'Very sure')])
                SettingRow(
                  key: ValueKey('contradictions-sure-$value'),
                  label: label,
                  control: Pick(checked: (settings.threshold - value).abs() < 0.001, label: 'Mark when $label'.toLowerCase(), onPress: () => set(settings.copyWith(threshold: value))),
                ),
            ],
          ),
          PaneSection(
            title: 'Which notes',
            children: [
              SettingRow(
                key: const ValueKey('contradictions-by-folder'),
                label: 'Within each folder only',
                hint: const Text('Compare your notes only with others in the same folder.'),
                control: GlacierSwitch(ariaLabel: 'Within each folder only', checked: settings.byFolder, onCheckedChange: (on) => set(settings.copyWith(byFolder: on))),
              ),
              SettingRow(
                key: const ValueKey('contradictions-orgs'),
                label: 'Organization notes',
                hint: const Text('Compare each organization’s notes with the same organization’s, never with yours. Its notes go to the AI that checks.'),
                control: GlacierSwitch(ariaLabel: 'Organization notes', checked: settings.orgs, onCheckedChange: (on) => set(settings.copyWith(orgs: on))),
              ),
            ],
          ),
          const SettingsFootnote(
            child: Text(
              'Only lines with dates, numbers and names two notes share are sent, a few pairs at a time. What was found and what you said was not a conflict are kept in your Library’s .glyph folder (an organization’s in its own folder), so a backup keeps them.',
            ),
          ),
        ] else
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('contradictions-more'),
                label: 'More',
                hint: const Text('How sure, and which notes are compared.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ],
          ),
      ],
    );
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'today at $time';
    if (today.difference(day).inDays == 1) return 'yesterday at $time';
    return 'on ${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

/// One finding on the page: the older note and its words, what the newer one says, and what to do.
class _FindingRow extends StatelessWidget {
  const _FindingRow({super.key, required this.finding, required this.runner});

  final Finding finding;
  final ContradictionRunner runner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final open = contradictionOpenNote;
    return SettingRow(
      icon: const AppIcon(Lucide.replace, size: 18),
      label: finding.olderTitle.isEmpty ? 'A note' : finding.olderTitle,
      layout: SettingRowLayout.stacked,
      hint: Text('“${finding.olderQuote}”. ${finding.newerTitle.isEmpty ? 'A newer note' : finding.newerTitle} says “${finding.newerQuote}”.'),
      control: Wrap(
        alignment: WrapAlignment.end,
        spacing: t.space(2),
        runSpacing: t.space(1),
        children: [
          if (open != null) RowAction(key: const ValueKey('finding-open'), onPress: () => open(finding.olderId), child: const Text('Open')),
          RowAction(key: const ValueKey('finding-superseded'), onPress: () => unawaited(runner.markSuperseded(finding)), child: const Text('Mark superseded')),
          RowAction(key: const ValueKey('finding-dismiss'), onPress: () => unawaited(runner.dismiss(finding)), child: const Text('Not a conflict')),
        ],
      ),
    );
  }
}
