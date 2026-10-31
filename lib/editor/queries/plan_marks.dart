/// A ticket's planning where a board or a query lists it, and where its panel shows it (Matt, 2026-10-31, of the
/// ticket features he chose; lib/core/query/planning.dart): its priority as a coloured chip, a subtle "stale · 9
/// days" once it has sat too long in its status, its estimate as a chip a tap changes, an epic's points, and the bar
/// that carries a cycle's unfinished tickets on in one action.
///
/// - **A priority's chip** wears its glacier hue (planning.dart `priorityHue`): Urgent filled red, High red, Medium
///   amber, Low blue, on a ground of the same hue's quietest step. Calm (Settings › Appearance) turns every hue to
///   the ink, as it does the activity's colours, and Urgent stays the one filled.
/// - **Stale** is the quietest thing on a card: the ink's third strength and an hourglass, never a colour, since a
///   ticket left alone is not an alarm.
/// - **An estimate** is a chip of its own on a card: `3 pts`, `4h`; a tap opens its sheet, the usual points and hours
///   a tap away and any other typed. A card in a cycle with none says "Estimate" quietly where the board can be
///   written, since a cycle is where tickets are estimated, and nothing in Simple mode.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../activity/job_mark.dart' show activityCalm;
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/planning/planning.dart';
import '../../core/preferences.dart' show preferences;
import '../../core/query/query.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'query_layout.dart';
import 'query_look.dart';
import 'query_parts.dart' show QueryActs;

/// A ticket's priority, by task_fields.dart's [name], as a coloured chip.
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.look, required this.name, this.size});

  final QueryLook look;
  final String name;

  /// The type it is set in; the query's small type where unsaid.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final calm = activityCalm(t);
    final hue = priorityHue(name);
    final strong = name == 'highest';
    // .priorityChip { padding: 0 var(--glacier-space-2); border-radius: var(--glacier-radius-full);
    //   background: var(--glacier-<hue>-3); color: var(--glacier-<hue>-11); font-weight: semibold }
    final ground = calm ? QueryLook.mix(look.ink, strong ? 0.86 : 0.09) : t.color(strong ? 'glacier-$hue-9' : 'glacier-$hue-3');
    final ink = calm ? (strong ? look.paper : look.ink2) : (strong ? const Color(0xFFFFFFFF) : t.color('glacier-$hue-11'));
    final px = size ?? look.xs;
    final label = ticketPriorityLabel(name);
    return Semantics(
      container: true,
      label: '$label priority',
      excludeSemantics: true,
      child: Part(
        'priorityChip',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: look.space(2)),
          decoration: ShapeDecoration(color: ground, shape: const StadiumBorder()),
          child: PageWords(label, look.sans(px, weight: 'semibold', color: ink), line: pageLine(px, 1.5), softWrap: false),
        ),
      ),
    );
  }
}

/// `stale · 9 days`, quiet, with an hourglass.
class StaleMark extends StatelessWidget {
  const StaleMark({super.key, required this.look, required this.days});

  final QueryLook look;
  final int days;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Stale: ${days == 1 ? 'a day' : '$days days'} in this status',
    excludeSemantics: true,
    child: Part(
      'stale',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIcon(Lucide.hourglass, size: 11, strokeWidth: 2.2, color: look.ink3),
          SizedBox(width: look.space(1)),
          Flexible(child: PageWords(staleWords(days), look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// An estimate as a chip says it: `3 pts`, `1 pt`, `4h`; the words as written for anything else.
String estimateChipWords(String written) {
  final estimate = estimateOf(written);
  if (estimate == null) return written;
  final amount = plainAmount(estimate.value);
  return estimate.unit == EstimateUnit.hours ? '${amount}h' : '$amount ${estimate.value == 1 ? 'pt' : 'pts'}';
}

/// A ticket's estimate on its card, a tap from its sheet where [onPick] writes it.
class EstimateChip extends StatefulWidget {
  const EstimateChip({super.key, required this.look, required this.value, this.onPick, this.record});

  final QueryLook look;

  /// As written; null for none.
  final String? value;

  /// Writes what is picked, null to take it off; absent, the chip is words.
  final void Function(String? value)? onPick;

  /// What the sheet names the ticket by.
  final String? record;

  @override
  State<EstimateChip> createState() => _EstimateChipState();
}

class _EstimateChipState extends State<EstimateChip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final value = widget.value;
    final pick = widget.onPick;
    final words = value == null ? 'Estimate' : estimateChipWords(value);
    // .estimate { padding: 0 var(--glacier-space-2); border: 1px solid var(--app-rule);
    //   border-radius: var(--glacier-radius-full); color: var(--app-ink-2) }  [data-empty] { color: var(--app-ink-4) }
    final chip = Part(
      'estimate',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: look.space(2)),
        decoration: ShapeDecoration(shape: StadiumBorder(side: BorderSide(color: look.rule, width: look.hair))),
        child: PageWords(words, look.sans(look.xs, color: value == null ? look.ink4 : look.ink2, tabular: true), line: pageLine(look.xs, 1.5), softWrap: false),
      ),
    );
    if (pick == null) return Semantics(label: value == null ? 'No estimate' : 'Estimate $words', excludeSemantics: true, child: chip);
    void open() {
      fireMotor(HapticKind.selection);
      setState(() => _open = true);
    }

    return Semantics(
      container: true,
      button: true,
      label: value == null ? 'Estimate: none. Set it' : 'Estimate: $words. Change it',
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            chip,
            if (_open)
              EstimateSheet(
                value: value,
                record: widget.record,
                onClose: () => setState(() => _open = false),
                onPick: (picked) {
                  fireMotor(HapticKind.selection);
                  pick(picked);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// The points a sheet offers, Fibonacci's as most teams estimate, and hours.
const List<String> estimatePoints = ['1', '2', '3', '5', '8', '13'];
const List<String> estimateHours = ['1h', '2h', '4h', '8h'];

/// An estimate's sheet: points and hours a tap away, any other typed, and None.
class EstimateSheet extends StatefulWidget {
  const EstimateSheet({super.key, required this.value, required this.onPick, required this.onClose, this.record});

  final String? value;
  final void Function(String? value) onPick;
  final VoidCallback onClose;
  final String? record;

  @override
  State<EstimateSheet> createState() => _EstimateSheetState();
}

class _EstimateSheetState extends State<EstimateSheet> {
  String _typed = '';

  void _choose(String? value) {
    final pick = widget.onPick;
    widget.onClose();
    if (value != widget.value) pick(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value?.trim().toLowerCase();
    final typed = _typed.trim();
    final readable = typed.isNotEmpty && estimateOf(typed) != null;
    return Sheet(
      key: const ValueKey('estimate-sheet'),
      label: 'Estimate',
      onClose: widget.onClose,
      children: <Widget>[
        SheetTitle.text(widget.record == null ? 'Estimate' : 'Estimate · ${widget.record}'),
        SheetGroup(
          children: <Widget>[
            for (final points in estimatePoints) SheetRow(key: ValueKey('estimate:$points'), label: estimateChipWords(points), chosen: value == points, onPress: () => _choose(points)),
          ],
        ),
        SheetGroup(
          children: <Widget>[
            for (final hours in estimateHours) SheetRow(key: ValueKey('estimate:$hours'), label: hours, chosen: value == hours, onPress: () => _choose(hours)),
          ],
        ),
        SheetGroup(
          children: <Widget>[
            SheetField(label: 'Another', value: _typed, placeholder: 'Like 21, or 3h', autoCorrect: false, onChange: (text) => setState(() => _typed = text), onSubmitted: (_) {
              if (readable) _choose(typed);
            }),
            if (typed.isNotEmpty) SheetRow(key: const ValueKey('estimate-typed'), label: readable ? 'Set it to ${estimateChipWords(typed)}' : 'An estimate is points, like 3, or hours, like 4h', disabled: !readable, onPress: () => _choose(typed)),
            SheetRow(key: const ValueKey('estimate-none'), label: 'None', chosen: value == null || value.isEmpty, onPress: () => _choose(null)),
          ],
        ),
      ],
    );
  }
}

/// A ticket's priority sheet, a ticket's four (planning.dart `ticketPriorities`) each as its chip: what a card's
/// priority and the panel's open. Lowest stays offered where a ticket has it.
class TicketPrioritySheet extends StatelessWidget {
  const TicketPrioritySheet({super.key, required this.look, required this.value, required this.onPick, required this.onClose, this.record});

  final QueryLook look;

  /// task_fields.dart's name, `highest` for urgent; null for none.
  final String? value;

  /// Writes the priority as a ticket writes it (`urgent`), or null to take it off.
  final void Function(String? written) onPick;
  final VoidCallback onClose;
  final String? record;

  @override
  Widget build(BuildContext context) {
    void choose(String? written) {
      final pick = onPick;
      onClose();
      pick(written);
    }

    return Sheet(
      key: const ValueKey('priority-sheet'),
      label: 'Priority',
      onClose: onClose,
      children: <Widget>[
        SheetTitle.text(record == null ? 'Priority' : 'Priority · $record'),
        SheetGroup(
          children: <Widget>[
            for (final each in ticketPriorities)
              SheetRow.rich(
                key: ValueKey('priority:${each.written}'),
                label: Align(alignment: Alignment.centerLeft, child: PriorityChip(look: look, name: each.name, size: look.em)),
                chosen: value == each.name,
                onPress: () => choose(each.written),
              ),
            if (value == 'lowest') SheetRow.rich(key: const ValueKey('priority:lowest'), label: Align(alignment: Alignment.centerLeft, child: PriorityChip(look: look, name: 'lowest', size: look.em)), chosen: true, onPress: () => choose('lowest')),
            SheetRow(key: const ValueKey('priority:none'), label: 'None', chosen: value == null, onPress: () => choose(null)),
          ],
        ),
      ],
    );
  }
}

/// A ticket's planning on its card or its row: stale, its estimate (a card's, a tap from its sheet), and an epic's
/// points. [card] draws the estimate; a row says stale alone, beside its name.
class QueryPlanMarks extends StatelessWidget {
  const QueryPlanMarks({super.key, required this.look, required this.row, required this.acts, this.card = true});

  final QueryLook look;
  final QueryRow row;
  final QueryActs acts;
  final bool card;

  /// Whether [row] has anything to draw here.
  static bool has(QueryRow row, {bool card = true}) {
    final plan = row.plan;
    if (plan == null) return false;
    if (plan.staleDays != null || plan.epic) return true;
    return card && (plan.estimate != null || (plan.cycle != null && !preferences.value.simple));
  }

  @override
  Widget build(BuildContext context) {
    final plan = row.plan;
    if (plan == null) return const SizedBox.shrink();
    final onSet = acts.editable ? acts.onSet : null;
    final progress = plan.progress;
    final parts = <Widget>[
      if (plan.epic)
        // .epic { color: var(--glacier-purple-11); font-weight: semibold; letter-spacing: 0.02em }
        Part('epic', child: PageWords('Epic', look.sans(look.xs, weight: 'semibold', color: activityCalm(look.t) ? look.ink2 : look.t.color('glacier-purple-11'), tracking: 0.02 * look.xs), line: look.lineXs, softWrap: false)),
      if (card && (plan.estimate != null || (onSet != null && plan.cycle != null && !preferences.value.simple)))
        EstimateChip(
          look: look,
          value: plan.estimate,
          record: row.id ?? row.name,
          onPick: onSet == null ? null : (value) => onSet(row, 'estimate', value),
        ),
      if (progress != null && progress.pointsTotal > 0)
        Part('epicPoints', child: PageWords('${plainAmount(progress.pointsDone)} of ${plainAmount(progress.pointsTotal)} pts', look.sans(look.xs, color: look.ink3, tabular: true), line: look.lineXs, softWrap: false)),
      if (plan.staleDays case final days?) StaleMark(look: look, days: days),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Part('plan', child: Wrap(spacing: look.space(2), runSpacing: look.space(1), crossAxisAlignment: WrapCrossAlignment.center, children: parts));
  }
}

/// The offer a query of a cycle makes once the cycle before has ended: "2026-C43 ended with 1 unfinished", and the
/// one button that moves them all to the next ([CarryOffer.words]).
class CarryBar extends StatelessWidget {
  const CarryBar({super.key, required this.look, required this.offer, required this.onCarry});

  final QueryLook look;
  final CarryOffer offer;
  final void Function(CarryOffer offer) onCarry;

  @override
  Widget build(BuildContext context) {
    final count = offer.noteIds.length;
    void carry() {
      fireMotor(HapticKind.selection);
      onCarry(offer);
    }

    // .carry { display: flex; flex-wrap: wrap; align-items: center; gap: var(--glacier-space-2);
    //   margin: var(--glacier-space-1) 0 var(--glacier-space-2); padding: var(--glacier-space-2) var(--glacier-space-3);
    //   border-radius: var(--glacier-radius-md); background: var(--app-paper) }
    return Padding(
      padding: EdgeInsets.only(top: look.space(1), bottom: look.space(2)),
      child: Part(
        'carry',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: look.space(3), vertical: look.space(2)),
          decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.t.radius('md')), border: Border.all(color: look.rule, width: look.hair)),
          child: Wrap(
            spacing: look.space(3),
            runSpacing: look.space(2),
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppIcon(Lucide.refreshCw, size: 13, strokeWidth: 2.2, color: look.ink3),
                  SizedBox(width: look.space(2)),
                  Flexible(child: PageWords('${offer.from.name} ended with $count unfinished', look.sans(look.em, color: look.ink2), line: look.line)),
                ],
              ),
              Semantics(
                container: true,
                button: true,
                label: offer.words,
                onTap: carry,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: carry,
                  // .carryButton { padding: var(--glacier-space-1) var(--glacier-space-3); border-radius: full;
                  //   background: var(--glacier-accent-solid); color: var(--glacier-accent-contrast) }
                  child: Part(
                    'carryButton',
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: look.space(3), vertical: look.space(1)),
                      decoration: ShapeDecoration(color: look.t.color('glacier-accent-solid'), shape: const StadiumBorder()),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(child: PageWords(offer.words, look.sans(look.em, weight: 'medium', color: look.t.color('glacier-accent-contrast')), line: look.line, maxLines: 2)),
                          SizedBox(width: look.space(1)),
                          AppIcon(Lucide.arrowRight, size: 13, strokeWidth: 2.2, color: look.t.color('glacier-accent-contrast')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
