/// The weekly report on Wrapped's page and its Settings page (docs/WRAPPED.md, "The weekly report"; weekly.dart):
/// - **This week** ([WrappedWeekSection]): the last report's week and line, the AI's summary, View report, and its next
///   steps, each Apply (Wrapped's own press) with Undo, or Dismiss; where a cloud AI has not been said yes to, Add the
///   AI summary, which asks first as the main pass does. Shown in Simple too.
/// - **Which AI** ([WrappedWhichAi]): the AI Wrapped asks, its model, and the choice among those connected where there
///   are several (Cleanup's rows, cleanup_pane.dart).
/// - **Weekly reports** ([WrappedWeeklySettings]): on, the day, the time, Include AI summary with its cost a week, and
///   Notify me. Behind More in Simple (pane.dart).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../cleanup/ai.dart' show CleanupAi;
import 'actions.dart' show WrappedDone;
import 'service.dart';
import 'stats.dart' show dayNames;
import 'weekly.dart';

/// The hours a report may come at: six in the morning to ten at night.
const List<int> weeklyHours = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22];

class WrappedWeekSection extends StatefulWidget {
  const WrappedWeekSection({super.key, required this.service});

  final WrappedService service;

  @override
  State<WrappedWeekSection> createState() => _WrappedWeekSectionState();
}

class _WrappedWeekSectionState extends State<WrappedWeekSection> {
  String? _said;
  bool _busy = false;

  WrappedService get _service => widget.service;

  Future<void> _run(Future<String> Function() press) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final said = await press();
      if (mounted) setState(() => _said = said);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final report = _service.weeklyReport;
          if (report == null || !_service.weeklySettings.on) return const SizedBox.shrink();
          final start = weekOfKey(report.week);
          final ai = _service.weeklyAi;
          return PaneSection(
            key: const ValueKey('wrapped-week'),
            title: 'This week',
            description: Text([if (start != null) weekTitle(start), if (report.line.isNotEmpty) report.line].join(' · ')),
            children: [
              if (report.summary.isNotEmpty) SettingRow(key: const ValueKey('wrapped-week-summary'), label: report.summary),
              SettingRow(
                key: const ValueKey('wrapped-week-view'),
                icon: const AppIcon(Lucide.calendarDays, size: 18),
                label: 'View report',
                hint: const Text('Your week in notes, a note in your Weekly reports journal.'),
                onPress: _service.viewWeekly,
              ),
              if (!report.ai && ai != null && _service.weeklyAsks)
                SettingRow(
                  key: const ValueKey('wrapped-week-allow'),
                  icon: const AppIcon(Lucide.sparkles, size: 18),
                  label: 'Add the AI summary',
                  hint: Text('${ai.name} writes what the week was about and three next steps, from one-line gists, never whole notes. You’re asked first.'),
                  value: RowAction(disabled: _busy || _service.weeklyMaking, onPress: () => unawaited(_run(() async => await _service.allowWeeklyAi(context) ? 'Added.' : '')), child: const Text('Add')),
                ),
              for (final (i, step) in report.steps.indexed)
                if (!step.dismissed)
                  SettingRow(
                    key: ValueKey('wrapped-step-$i'),
                    icon: AppIcon(switch (step.kind) { WeeklyStepKind.checkOff => Lucide.squareCheckBig, WeeklyStepKind.archive => Lucide.archive, WeeklyStepKind.link => Lucide.link, WeeklyStepKind.look => Lucide.eye }, size: 18),
                    label: step.words,
                    layout: SettingRowLayout.stacked,
                    control: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        if (step.record != null)
                          RowAction(key: ValueKey('wrapped-step-undo-$i'), disabled: _busy, onPress: () => unawaited(_run(() => _service.undoStep(i))), child: const Text('Undo'))
                        else ...[
                          RowAction(
                            key: ValueKey('wrapped-step-apply-$i'),
                            disabled: _busy, onPress: () => unawaited(_run(() async => _doneWords(step, await _service.applyStep(i)))),
                            child: Text(switch (step.kind) { WeeklyStepKind.checkOff => 'Check off', WeeklyStepKind.archive => 'Archive', WeeklyStepKind.link => 'Link', WeeklyStepKind.look => 'Open' }),
                          ),
                          RowAction(key: ValueKey('wrapped-step-dismiss-$i'), disabled: _busy, onPress: () => _service.dismissStep(i), child: const Text('Dismiss')),
                        ],
                      ],
                    ),
                  ),
              if (_said != null && _said!.isNotEmpty) SettingRow(key: const ValueKey('wrapped-week-said'), label: _said!),
            ],
          );
        },
      );

  String _doneWords(WeeklyStep step, WrappedDone done) {
    final count = done.done;
    if (step.kind == WeeklyStepKind.look) return '';
    if (count == 0) return 'Nothing to change: it was done already.';
    return switch (step.kind) {
      WeeklyStepKind.checkOff => 'Checked off $count.',
      WeeklyStepKind.archive => 'Archived $count.',
      _ => 'Linked.',
    };
  }
}

/// "Which AI": the AI Wrapped asks and its model; the choice among those connected where there are several.
class WrappedWhichAi extends StatefulWidget {
  const WrappedWhichAi({super.key, required this.service});

  final WrappedService service;

  @override
  State<WrappedWhichAi> createState() => _WrappedWhichAiState();
}

class _WrappedWhichAiState extends State<WrappedWhichAi> {
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final ai = service.ai;
    final ais = service.ais;
    String said(CleanupAi each) => [if (each.model != null && each.model!.isNotEmpty) each.model!, each.local ? 'Nothing leaves this device' : 'With your key'].join(' · ');
    return PaneSection(
      title: 'Which AI',
      description: const Text('The AI that reads your notes for your Wrapped and writes your weekly report. Only it is sent anything.'),
      children: [
        SettingRow(
          key: const ValueKey('wrapped-which-ai'),
          icon: const AppIcon(Lucide.sparkles, size: 16),
          label: ai == null ? (service.aisRead ? 'No AI connected' : 'Looking…') : ai.name,
          hint: Text(ai == null ? 'Your Wrapped and weekly reports are the counts alone. Add Claude or another AI from the Market, or a model in Settings › AI.' : said(ai)),
          value: ais.length > 1 ? Text(_picking ? 'Choose' : 'Change') : null,
          onPress: ais.length > 1 ? () => setState(() => _picking = !_picking) : null,
        ),
        if (_picking && ais.length > 1)
          for (final each in ais)
            SettingRow(
              key: ValueKey('wrapped-ai-${each.id}'),
              label: each.name,
              hint: Text(said(each)),
              control: Pick(
                checked: ai?.id == each.id,
                label: 'Use ${each.name}',
                disabled: service.running || service.weeklyMaking,
                onPress: () {
                  service.chooseAi(each.id);
                  setState(() => _picking = false);
                },
              ),
            ),
      ],
    );
  }
}

/// The weekly report's choices.
class WrappedWeeklySettings extends StatefulWidget {
  const WrappedWeeklySettings({super.key, required this.service});

  final WrappedService service;

  @override
  State<WrappedWeeklySettings> createState() => _WrappedWeeklySettingsState();
}

class _WrappedWeeklySettingsState extends State<WrappedWeeklySettings> {
  bool _days = false, _hours = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final settings = service.weeklySettings;
    void set(WeeklySettings next) => service.setWeekly(next);
    final ai = service.ai;
    final cost = service.weeklyCostWords;
    return PaneSection(
      key: const ValueKey('wrapped-weekly-settings'),
      title: 'Weekly reports',
      description: Text('Your week in notes, a note in your Weekly reports journal, ${settings.words} for the week before. A week the app was not open for is made the next time it is.'),
      children: [
        SettingRow(
          key: const ValueKey('wrapped-weekly-on'),
          label: 'Weekly reports',
          control: GlacierSwitch(ariaLabel: 'Weekly reports', checked: settings.on, onCheckedChange: (on) => set(settings.copyWith(on: on))),
        ),
        if (settings.on) ...[
          SettingRow(
            key: const ValueKey('wrapped-weekly-day'),
            label: 'Day',
            value: Text(dayNames[settings.weekday - 1]),
            onPress: () => setState(() => _days = !_days),
          ),
          if (_days)
            for (var day = 1; day <= 7; day += 1)
              SettingRow(
                key: ValueKey('wrapped-weekly-day-$day'),
                label: dayNames[day - 1],
                control: Pick(
                  checked: settings.weekday == day,
                  label: 'On ${dayNames[day - 1]}s',
                  onPress: () {
                    set(settings.copyWith(weekday: day));
                    setState(() => _days = false);
                  },
                ),
              ),
          SettingRow(
            key: const ValueKey('wrapped-weekly-time'),
            label: 'Time',
            value: Text('${settings.hour}:${settings.minute.toString().padLeft(2, '0')}'),
            onPress: () => setState(() => _hours = !_hours),
          ),
          if (_hours)
            for (final hour in weeklyHours)
              SettingRow(
                key: ValueKey('wrapped-weekly-hour-$hour'),
                label: '$hour:00',
                control: Pick(
                  checked: settings.hour == hour && settings.minute == 0,
                  label: 'At $hour:00',
                  onPress: () {
                    set(settings.copyWith(hour: hour, minute: 0));
                    setState(() => _hours = false);
                  },
                ),
              ),
          SettingRow(
            key: const ValueKey('wrapped-weekly-ai'),
            label: 'Include AI summary',
            hint: Text(ai == null
                ? 'No AI is connected, so the report is the counts alone.'
                : '${ai.name} writes what the week was about and three next steps, from one-line gists and the counts, never whole notes.${cost == null ? '' : ' About $cost.'}'),
            control: GlacierSwitch(ariaLabel: 'Include AI summary', checked: settings.ai, onCheckedChange: (on) => set(settings.copyWith(ai: on))),
          ),
          SettingRow(
            key: const ValueKey('wrapped-weekly-notify'),
            label: 'Notify me',
            hint: const Text('“Your week in notes is ready”, where this device lets Ghost.md notify.'),
            control: GlacierSwitch(ariaLabel: 'Notify me', checked: settings.notify, onCheckedChange: (on) => set(settings.copyWith(notify: on))),
          ),
        ],
      ],
    );
  }
}
