/// Version 2 of the header toolbar, **Grouped** (lib/shell/header_toolbar.dart): the controls in clusters, each
/// cluster a pill of its own, so the row reads as three things rather than ten.
///
/// - **The way around**, at the start: Home and the notes' sidebar, a hairline, then Back and Forward, as one
///   segmented pill on the page's second paper.
/// - **The note's own**, at the end: the view switch and the two most used of its actions (three on a wide window),
///   then ••• with the rest and More for this note, in a second pill. With nothing else to show, ••• is the note's
///   More itself.
/// - **You**: one round button for the app's own - the bell, the organizations, Settings - whose menu has them with
///   their badges, and which wears the bell's dot while something is new. The aside's toggle ends the row, a pill of
///   one.
///
/// Iconography: the chosen pack in its **Solid** style, a little smaller than today's, so the glyphs read as one set
/// inside their pills. A control that is on (Home the page, the sidebar showing, the bookmark set) is a segment of
/// ink with the glyph in paper, where today's rings wore a ring.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../header_toolbar.dart';
import 'header_kit.dart';

HeaderRow groupedRow(BuildContext context, HeaderParts parts) {
  Widget solid(Widget child) => styled(context, IconStyle.solid, child);
  final way = parts.way;
  return HeaderRow(
    lead: [
      if (way.isNotEmpty)
        solid(
          GroupedPill(
            children: [
              for (final act in way) ...[
                // A hairline between where you are and where you have been.
                if (act.id == 'back' && way.any((each) => each.id == 'home' || each.id == 'sidebar')) const GroupedRule(),
                GroupedSegment(act: act, fine: parts.fine),
              ],
            ],
          ),
        ),
    ],
    trail: [
      ?parts.presence,
      if (parts.onNote) solid(_NotePill(parts: parts)) else ...fallbackTools(parts),
      if (parts.you.isNotEmpty) solid(GroupedYou(parts: parts)),
      if (parts.aside case final aside?) solid(GroupedPill(children: [GroupedSegment(act: aside, fine: parts.fine)])),
    ],
  );
}

/// A screen's own controls handed as widgets alone, drawn as they come, scrolling where they would run out of room.
List<Widget> fallbackTools(HeaderParts parts) => [
      if (parts.tools case final tools?)
        ConstrainedBox(constraints: BoxConstraints(maxWidth: parts.room / 2), child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: tools)),
      ?parts.tail,
    ];

/// The note's pill: the view, the most used, and ••• for the rest.
class _NotePill extends StatelessWidget {
  const _NotePill({required this.parts});
  final HeaderParts parts;

  @override
  Widget build(BuildContext context) {
    final shown = parts.actions.take(parts.wide ? 3 : 2).toList();
    final rest = notShown(parts.actions, shown);
    final more = parts.more;
    return GroupedPill(
      children: [
        if (parts.view case final view?) GroupedSegment(act: view, fine: parts.fine),
        for (final act in shown) GroupedSegment(act: act, fine: parts.fine),
        if (rest.isEmpty && more != null)
          GroupedSegment(act: more, fine: parts.fine)
        else if (rest.isNotEmpty)
          HeaderMenuButton(
            act: moreAct(label: 'More for this note: the rest of its tools'),
            fine: parts.fine,
            radius: 999,
            entries: [
              for (final act in rest) HeaderMenuAct(act),
              if (more != null) ...[const HeaderMenuRule(), HeaderMenuAct(more)],
            ],
            face: (context, state, open) => GroupedSegmentFace(act: moreAct(), state: state, on: open),
          ),
      ],
    );
  }
}

/// The round button for you, with the bell's dot.
class GroupedYou extends StatelessWidget {
  const GroupedYou({super.key, required this.parts});
  final HeaderParts parts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final act = youAct(parts);
    return HeaderMenuButton(
      act: act,
      fine: parts.fine,
      radius: 999,
      entries: youEntries(parts),
      menuLabel: 'Notifications, organizations and Settings',
      face: (context, state, open) {
        final lit = state.hovered || state.pressed || open;
        final ink = t.color('glacier-text');
        return withMarks(
          act,
          Container(
            width: ring,
            height: ring,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? t.color('app-paper-2') : null,
              border: Border.all(color: lit ? ink : t.color('glacier-border-subtle'), width: 1.5),
            ),
            child: Center(child: HeaderGlyph(act, size: 17, color: lit ? ink : t.color('glacier-text-muted'))),
          ),
          rim: t.color('glacier-bg'),
          ink: ink,
          paper: t.color('app-paper'),
        );
      },
    );
  }
}

/// A pill of segments on the page's second paper, a ring high, with a hairline round it.
class GroupedPill extends StatelessWidget {
  const GroupedPill({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    return Container(
      height: t.len('app-bar-ring'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.color('glacier-border-subtle'), width: hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 1, children: children),
    );
  }
}

/// The hairline between a pill's two halves.
class GroupedRule extends StatelessWidget {
  const GroupedRule({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(width: t.len('glacier-hairline'), height: t.len('app-bar-ring') * 0.45, color: t.color('glacier-border')),
    );
  }
}

/// One segment of a pill: a round inside it.
class GroupedSegment extends StatelessWidget {
  const GroupedSegment({super.key, required this.act, required this.fine});
  final HeaderAct act;
  final bool fine;

  @override
  Widget build(BuildContext context) => HeaderPress(act: act, fine: fine, radius: 999, face: (context, state) => GroupedSegmentFace(act: act, state: state, on: act.on));
}

class GroupedSegmentFace extends StatelessWidget {
  const GroupedSegmentFace({super.key, required this.act, required this.state, required this.on});
  final HeaderAct act;
  final PressState state;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.len('app-bar-ring') - 4 - 2 * t.len('glacier-hairline');
    final lit = (state.hovered || state.pressed) && !state.disabled;
    final ink = t.color('glacier-text'), paper = t.color('glacier-bg');
    final color = on ? paper : (lit ? ink : t.color('glacier-text-muted'));
    return withMarks(
      act,
      Container(
        width: size + 4,
        height: size,
        decoration: BoxDecoration(color: on ? ink : (lit ? paper : null), borderRadius: BorderRadius.circular(999)),
        child: Center(child: HeaderGlyph(act, size: 16, color: color, strokeWidth: 2)),
      ),
      rim: t.color('app-paper-2'),
      ink: ink,
      paper: t.color('app-paper'),
    );
  }
}
