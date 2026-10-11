/// The guide's table of marks: every way a note can be formatted, what to type, how it comes out, and how to say it
/// while recording. A port of `src/app/guide/MarksTable.tsx` with `MarksTable.module.css` (Matt: "create a guide
/// page, it should show every formatting mode we have in a table and show you an example of how it works").
///
/// A row is the mark with its icon, the line to type with its marks visible, and the same line drawn by the note's
/// own editor (mark_example.dart), so what is promised here is what the app does with those characters. The rows
/// come from marks.dart, which reads the switched-on plugins, so the app's own marks are listed with the plugins'
/// and a plugin switched off is never promised. Two columns, "you type" and "it reads".
///
/// No page of the app draws it since the marks page went (2026-10-02); the web keeps it for its test, and so does
/// this port.
///
/// What differs: the page makes its rows once (`useMemo`); here they are made as the table is, and again when the
/// plugins' switches change. The table is a column: put it in whatever scrolls.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../plugins/registry.dart';
import 'mark_example.dart';
import 'marks.dart';

class MarksTable extends StatefulWidget {
  const MarksTable({super.key, this.now});

  /// The day a due date's example counts from; the clock when null.
  final DateTime? now;

  @override
  State<MarksTable> createState() => _MarksTableState();
}

class _MarksTableState extends State<MarksTable> {
  late List<MarkGroup> _groups = markGroups(now: widget.now);
  Registry? _registry;

  @override
  void initState() {
    super.initState();
    _registry = plugins..addListener(_switched);
  }

  void _switched() {
    if (mounted) setState(() => _groups = markGroups(now: widget.now));
  }

  @override
  void dispose() {
    _registry?.removeListener(_switched);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final subtle = t.color('glacier-text-subtle');
    final muted = t.color('glacier-text-muted');
    final rule = BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'));
    final xs = t.fontSize('xs');
    final head = t.textAt(xs, color: subtle, tracking: t.len('app-tracking-caps-close', em: xs));

    Widget pair(Widget typed, Widget shown) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: typed), SizedBox(width: t.space(4)), Expanded(child: shown)],
    );

    Widget row(MarkRow row) {
      final icon = Lucide.all[row.icon];
      final typed = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The mark itself, with its icon, so the eye finds it before the line.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: t.lenOf('1.5rem'),
                  height: t.lenOf('1.5rem'),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.color('app-wash'), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: icon == null ? null : AppIcon(icon, size: 15, color: muted),
                ),
              ),
              SizedBox(width: t.space(2)),
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 0.1 * sm, horizontal: 0.4 * sm),
                  decoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-strong'), width: t.len('glacier-hairline')), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: Text(row.symbol, style: t.textAt(sm, weight: 'semibold', mono: true), maxLines: 1, softWrap: false),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space(1)),
          Text(row.typed, style: t.textAt(sm, mono: true, height: 1.5, color: muted)),
        ],
      );
      final shown = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(row.name, style: t.textAt(sm, weight: 'semibold')),
          SizedBox(height: t.space(1)),
          MarkExample(row: row),
          if (row.say != null) ...[SizedBox(height: t.space(1)), Text(row.say!, style: t.textAt(xs, color: subtle))],
        ],
      );
      return Container(
        padding: EdgeInsets.symmetric(vertical: t.space(4)),
        decoration: BoxDecoration(border: Border(bottom: rule)),
        // A board is a layout rather than a line: it takes the whole row, its example under what to type.
        child: row.looks == 'board'
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [typed, SizedBox(height: t.space(4)), shown])
            : pair(typed, shown),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: t.space(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, group) in _groups.indexed) ...[
            if (index > 0) SizedBox(height: t.space(8)),
            // A group of marks' name, as the cheat sheet sets the same groups' names (CheatSheet.module.css `.title`).
            Semantics(
              header: true,
              child: Text(group.title.toUpperCase(), style: t.textAt(sm, weight: 'semibold', color: subtle, tracking: t.len('app-tracking-caps', em: sm))),
            ),
            SizedBox(height: t.space(1)),
            Text(group.lead, style: t.textAt(t.fontSize('md'), height: t.len('glacier-leading-md'), color: muted)),
            SizedBox(height: t.space(3)),
            Container(
              padding: EdgeInsets.only(bottom: t.space(2)),
              decoration: BoxDecoration(border: Border(bottom: rule)),
              child: pair(Text('YOU TYPE', style: head), Text('IT READS', style: head)),
            ),
            for (final one in group.rows) KeyedSubtree(key: ValueKey('mark ${one.name}'), child: row(one)),
          ],
        ],
      ),
    );
  }
}
