/// Your day: a card at the top of Messages saying what is waiting, each line opening its list (Matt, 2026-11-14, of
/// the ideas to streamline someone's day: "Morning digest: one card at the top of the list: 3 people need a reply, 2
/// deliveries today, a bill due Thursday, 1 appointment tomorrow", with "Bill and delivery timeline" and "Catch-up for
/// groups" grouped with it).
///
/// It counts what the other plugins sort: Needs a reply (Replies), Deliveries & tracking, Payment reminders and
/// Appointments (Kinds of text). A group's unread texts are summed up in its row by Summaries. Put away for the
/// rest of the day with its ×; back the next morning, and whenever something new is waiting.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_type.dart';
import 'plugin.dart';

/// One line of the card: what it counts, its section, and how it says it.
@immutable
class DayLine {
  const DayLine(this.section, this.icon, this.one, this.many);
  final String section;
  final LucideIcon icon;
  final String one;
  final String many;

  String say(int n) => n == 1 ? one : many.replaceAll('#', '$n');
}

const List<DayLine> dayLines = [
  DayLine('reply', LucideMore.reply, '1 person waiting on you', '# people waiting on you'),
  DayLine('deliveries', LucideMore.package, '1 delivery', '# deliveries'),
  DayLine('reminders', LucideMore.receipt, '1 bill or payment', '# bills and payments'),
  DayLine('appointments', LucideMore.calendarCheck, '1 appointment', '# appointments'),
];

class DayPlugin extends GhostPlugin {
  const DayPlugin({this.now});
  final DateTime Function()? now;

  @override
  String get id => 'day';

  @override
  String get name => 'Your day';

  @override
  String get description => 'A card at the top of Messages: who is waiting on you, deliveries, bills and appointments.';

  @override
  LucideIcon get icon => LucideMore.sunMedium;

  static String _today(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  List<SlotFill> get slots => [
        Slots.aboveList.fill((context, place, prefs) {
          if (place.section != null) return const [];
          final today = (now ?? DateTime.now)();
          final lines = [for (final l in dayLines) if ((place.counts[l.section] ?? 0) > 0) (line: l, n: place.counts[l.section]!)];
          if (lines.isEmpty) return const [];
          // Put away for today, unless something more is waiting than when it was.
          final total = lines.fold(0, (a, b) => a + b.n);
          final away = prefs.get('away');
          if (away == '${_today(today)}:$total') return const [];
          return [DayCard(today: today, lines: lines, show: place.show, close: () => prefs.set('away', '${_today(today)}:$total'))];
        }),
      ];

  @override
  PluginSettingsPage? get settingsPage => PluginSettingsPage(hue: 'yellow', intro: 'A card at the top of Messages, saying what is waiting.', summary: (prefs) => 'Replies, deliveries, bills, appointments');

  @override
  List<PluginSetting> get settings => const [
        PluginSetting.note(label: 'What it counts', hint: 'People waiting on a reply (Replies), and deliveries, bills and appointments (Kinds of text). A press on a line opens its list.', icon: Lucide.listFilter),
        PluginSetting.note(label: 'Put away', hint: 'Its × puts it away for the rest of the day; it comes back the next morning, or when something new is waiting.', icon: Lucide.x),
      ];
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The card.
class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.today, required this.lines, required this.close, this.show});
  final DateTime today;
  final List<({DayLine line, int n})> lines;
  final void Function(String? section)? show;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final greet = today.hour < 12 ? 'Good morning' : today.hour < 18 ? 'Good afternoon' : 'Good evening';
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(3)),
      child: Container(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(2), t.space(3)),
        decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('app-rule'))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greet, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                Text('${_weekdays[today.weekday - 1]}, ${_months[today.month - 1]} ${today.day}', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              ]),
            ),
            GlacierPressable(
              onPressed: close,
              semanticLabel: 'Put away for today',
              builder: (context, state) => Padding(padding: EdgeInsets.all(t.space(2)), child: AppIcon(Lucide.x, size: 16, color: t.color(state.pressed ? 'app-ink-4' : 'app-ink-3'))),
            ),
          ]),
          SizedBox(height: t.space(2)),
          for (final l in lines)
            GlacierPressable(
              onPressed: show == null ? null : () => show!(l.line.section),
              semanticLabel: l.line.say(l.n),
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(vertical: t.space(1) + 1),
                child: Row(children: [
                  AppIcon(l.line.icon, size: 16, strokeWidth: 2.2, wash: false, color: t.color('app-ink-2')),
                  SizedBox(width: t.space(2)),
                  Expanded(child: Text(l.line.say(l.n), style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.pressed ? 'app-ink-3' : 'app-ink')))),
                  if (show != null) Padding(padding: EdgeInsets.only(right: t.space(2)), child: AppIcon(Lucide.chevronRight, size: 14, color: t.color('app-ink-4'))),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
