/// A ticket's planning in its panel (ticket_panel.dart; Matt, 2026-10-31; lib/core/query/planning.dart): the sheets
/// its cycle and its milestone are picked from, and the words its cycle's chip says. Each pick is one write into its
/// front matter, `cycle: 2026-C47` or `milestone: "[[v2 launch]]"`, as every other value the panel picks is.
library;

import 'package:flutter/widgets.dart';

import '../../core/planning/cycles.dart';
import '../../core/query/planning.dart' show TicketPlanning;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';

/// What a cycle's chip says: its name, and `now` for today's; its days are its sheet's to say.
String cycleChipWords(Cycle cycle, Cycle? current) => CycleBook.same(cycle, current) ? '${cycle.name} · now' : cycle.name;

/// The sheet a ticket's cycle is picked from: the notebook's last two, today's and the next two, each with its days,
/// and No cycle.
class CycleSheet extends StatelessWidget {
  const CycleSheet({super.key, required this.planning, required this.onPick, required this.onClose});

  final TicketPlanning planning;

  /// Writes the cycle as a ticket names it, or null to take it off.
  final void Function(String? written) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final mine = planning.cycle;
    void choose(String? written) {
      final pick = onPick;
      onClose();
      pick(written);
    }

    final offered = [...planning.cycles];
    // A cycle of its own that the notebook's run of them does not show is offered too, where it is.
    if (mine != null && !offered.any((each) => CycleBook.same(each, mine))) offered.insert(0, mine);
    return Sheet(
      key: const ValueKey('cycle-sheet'),
      label: 'Cycle',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text('Cycle'),
        SheetGroup(
          children: <Widget>[
            for (final cycle in offered)
              SheetRow(
                key: ValueKey('cycle:${cycle.name}'),
                label: CycleBook.same(cycle, planning.current) ? '${cycle.name} (now)' : cycle.name,
                hint: cycleDaysWords(cycle).isEmpty ? null : cycleDaysWords(cycle),
                chosen: CycleBook.same(cycle, mine),
                onPress: () => choose(cycle.written),
              ),
            SheetRow(key: const ValueKey('cycle:none'), label: 'No cycle', chosen: mine == null, onPress: () => choose(null)),
          ],
        ),
      ],
    );
  }
}

/// The sheet a ticket's milestone is picked from: the milestone notes, the soonest first, and No milestone.
class MilestoneSheet extends StatelessWidget {
  const MilestoneSheet({super.key, required this.planning, required this.own, required this.onPick, required this.onClose});

  final TicketPlanning planning;

  /// The milestone its own front matter names (not its epic's).
  final String? own;

  /// Writes the milestone as a link, or null to take it off.
  final void Function(String? written) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    void choose(String? written) {
      final pick = onPick;
      onClose();
      pick(written);
    }

    final mine = own?.toLowerCase();
    return Sheet(
      key: const ValueKey('milestone-sheet'),
      label: 'Milestone',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text('Milestone'),
        if (planning.milestones.isEmpty) SheetNote('No milestones yet: a note with “type: milestone” and a “date:” is one.'),
        SheetGroup(
          children: <Widget>[
            for (final milestone in planning.milestones)
              SheetRow(
                key: ValueKey('milestone:${milestone.title}'),
                label: milestone.title,
                hint: milestone.day,
                chosen: mine != null && milestone.title.toLowerCase() == mine,
                onPress: () => choose('[[${milestone.title}]]'),
              ),
            SheetRow(key: const ValueKey('milestone:none'), label: 'No milestone', chosen: mine == null, onPress: () => choose(null)),
          ],
        ),
      ],
    );
  }
}
