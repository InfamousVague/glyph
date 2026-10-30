/// A ticket's lock and its sub-tickets' progress where a board or a query lists it (Matt, 2026-10-30, of a list of
/// plain-Markdown features: "add all 12"; lib/book/ticket_links.dart). Under its name on a card, after it on a row: a
/// lock in amber with what blocks it while something does, and a thin bar of how many of its sub-tickets are done.
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../tickets/ticket_panel.dart' show TicketProgressBar;
import 'queries.dart' show TicketMarks;
import 'query_layout.dart';
import 'query_look.dart';

class QueryTicketMarks extends StatelessWidget {
  const QueryTicketMarks({super.key, required this.look, required this.marks, this.bar = true});

  final QueryLook look;
  final TicketMarks marks;

  /// Whether the progress has its bar (a card), or its words alone (a row).
  final bool bar;

  /// Whether [marks] draws anything.
  static bool has(TicketMarks marks) => marks != null && (marks.blockers.isNotEmpty || (marks.progress != null && !marks.progress!.isEmpty));

  @override
  Widget build(BuildContext context) {
    final marks = this.marks;
    if (marks == null) return const SizedBox.shrink();
    final amber = look.t.color('glacier-amber-11');
    final progress = marks.progress;
    final blockers = marks.blockers;
    final parts = <Widget>[
      if (blockers.isNotEmpty)
        Semantics(
          container: true,
          label: 'Waiting on ${blockers.join(', ')}',
          excludeSemantics: true,
          child: Part(
            'cardLock',
            child: CssRow(
              gap: look.space(1),
              shrinkWrap: true,
              children: <Widget>[
                CssItem(shrink: 0, child: AppIcon(Lucide.lock, size: 12, strokeWidth: 2.2, color: amber)),
                CssItem(least: 0, child: PageWords(blockers.join(', '), look.sans(look.xs, color: amber), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      if (progress != null && !progress.isEmpty)
        Semantics(
          container: true,
          label: 'Sub-tickets, ${progress.words}',
          excludeSemantics: true,
          child: Part(
            'cardProgress',
            child: bar
                ? Row(
                    children: <Widget>[
                      Expanded(child: TicketProgressBar(look: look, fraction: progress.fraction, height: 3)),
                      SizedBox(width: look.space(2)),
                      PageWords('${progress.done}/${progress.total}', look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false),
                    ],
                  )
                : PageWords('${progress.done}/${progress.total} done', look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false),
          ),
        ),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    if (!bar) return Wrap(spacing: look.space(2), crossAxisAlignment: WrapCrossAlignment.center, children: parts);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, part) in parts.indexed) ...<Widget>[if (index > 0) SizedBox(height: look.space(1)), part],
      ],
    );
  }
}
