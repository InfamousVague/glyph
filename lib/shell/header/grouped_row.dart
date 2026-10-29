/// Version 2 of the header toolbar, **Grouped** (lib/shell/header_toolbar.dart): the controls in clusters, each
/// cluster a pill of its own, so the row reads as three things rather than ten.
///
/// - **The way around**, at the start: Home and the notes' sidebar in one pill on the page's second paper, then,
///   apart from it by the bar's own gap, Back and Forward in another ([GroupedWay]; Matt, 2026-10-28: "the grouped
///   ones need a bit of space between the home sidebar and navigation buttons"). Two pills read as two things on
///   the folded Fold, where a hairline inside one pill was lost; one pill with a hole in it read as a broken pill.
/// - **The note's own**, at the end: the view switch and the two most used of its actions (three on a wide window),
///   then ••• with the rest and More for this note, in a second pill. With nothing else to show, ••• is the note's
///   More itself.
/// - **Under •••**, first (Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as the +
///   button in the header"): every note by folder and a new note; at home, where there is no note's pill, ••• is a
///   circle of its own for them.
/// - **You**: one round button for the app's own - the bell, the organizations, Settings - whose menu has them with
///   their badges, and which wears the bell's dot while something is new. The aside's toggle ends the row, a round
///   of its own.
///
/// **Every button is a circle** (Matt, 2026-10-28: "make the buttons circular instead of pill shaped for each item
/// like the home item shows as a pill even though it's a single icon"): a segment is as wide as it is tall, and so
/// are its hover, its press, its "on" ground and its focus ring. Only a pill that holds several buttons is a pill;
/// one that holds a single button is that button's circle.
///
/// Iconography: the chosen pack in its **Solid** style, a little smaller than today's, so the glyphs read as one set
/// inside their pills. A control that is on (Home the page, the sidebar showing, the bookmark set) is a segment of
/// ink with the glyph in paper, where today's rings wore a ring.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../header_toolbar.dart';
import 'header_kit.dart';

HeaderRow groupedRow(BuildContext context, HeaderParts parts) {
  Widget solid(Widget child) => styled(context, IconStyle.solid, child);
  // A cramped row (a Mac's window at a phone's width, its window buttons at the start) on a note puts Back and Forward
  // under the note's •••, with the activity ring always in the row (Matt, 2026-10-29: "Keep the activity indicator
  // always showing just have it gray put when nothing is happening").
  final putAway = parts.onNote && parts.cramped ? [?parts.back, ?parts.forward] : const <HeaderAct>[];
  final way = notShown(parts.way, putAway);
  return HeaderRow(
    lead: [
      if (way.isNotEmpty) solid(GroupedWay(way: way, fine: parts.fine)),
    ],
    trail: [
      ?parts.presence,
      if (parts.onNote) solid(_NotePill(parts: parts, putAway: putAway)) else ...[
        ...fallbackTools(parts),
        // At home there is no note's pill: ••• is a circle of its own, for what the bar keeps under it.
        if (parts.kept.isNotEmpty)
          solid(
            GroupedPill(
              children: [
                HeaderMenuButton(
                  act: moreAct(),
                  fine: parts.fine,
                  radius: 999,
                  entries: keptEntries(parts, more: false),
                  face: (context, state, open) => GroupedSegmentFace(act: moreAct(), state: state, on: open),
                ),
              ],
            ),
          ),
      ],
      ?parts.activity,
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

/// The note's pill: the view, the most used, and ••• for the rest, and for the way around a cramped row put away.
class _NotePill extends StatelessWidget {
  const _NotePill({required this.parts, this.putAway = const []});
  final HeaderParts parts;
  final List<HeaderAct> putAway;

  @override
  Widget build(BuildContext context) {
    // Three on a wide window, two on a phone, one where the row is cramped; on a narrow row the button for you takes a
    // circle's room from them, two on a 360 phone's (a phone reading a note has none; the one frame a note's tools stay
    // in the row as you leave it for All notes, and a Mac's narrowed window, have it), with the activity ring always
    // in the row (Matt, 2026-10-29: "Keep the activity indicator always showing").
    final crowd = parts.you.isNotEmpty && !parts.wide ? (parts.room < snugRoom ? 2 : 1) : 0;
    final shown = parts.actions.take(parts.wide ? 3 : math.max(0, (parts.cramped ? 1 : 2) - crowd)).toList();
    final rest = notShown(parts.actions, shown);
    final more = parts.more;
    return GroupedPill(
      children: [
        if (parts.view case final view?) GroupedSegment(act: view, fine: parts.fine),
        for (final act in shown) GroupedSegment(act: act, fine: parts.fine),
        if (rest.isEmpty && parts.kept.isEmpty && more != null)
          GroupedSegment(act: more, fine: parts.fine)
        else if (rest.isNotEmpty || parts.kept.isNotEmpty)
          HeaderMenuButton(
            act: moreAct(label: 'More for this note: the rest of its tools'),
            fine: parts.fine,
            radius: 999,
            entries: [
              // What the bar keeps under ••• first (Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as the + button in the header").
              ...keptEntries(parts, more: rest.isNotEmpty || more != null),
              for (final act in rest) HeaderMenuAct(act),
              if (more != null) ...[if (rest.isNotEmpty) const HeaderMenuRule(), HeaderMenuAct(more)],
              if (putAway.isNotEmpty) ...[const HeaderMenuRule(), const HeaderMenuLabel('Go'), for (final act in putAway) HeaderMenuAct(act)],
            ],
            face: (context, state, open) => GroupedSegmentFace(act: moreAct(), state: state, on: open),
          ),
      ],
    );
  }
}

/// The round button for you, with the bell's dot.
class GroupedYou extends StatelessWidget {
  const GroupedYou({super.key, required this.parts, this.glyph = 17});
  final HeaderParts parts;

  /// The glyph's size: Grouped command's is a size up.
  final double glyph;

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
            child: Center(child: HeaderGlyph(act, size: glyph, color: lit ? ink : t.color('glacier-text-muted'))),
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
      // A gap between the circles, so two buttons read as two (Matt, 2026-10-29, of Home and the sidebar: "too close
      // together it's missing the gap").
      child: Row(mainAxisSize: MainAxisSize.min, spacing: t.space(1), children: children),
    );
  }
}

/// The way around as two pills, the bar's gap between them: where you are (Home, the sidebar) and where you have
/// been (Back, Forward). A half with nothing in it is not drawn; a half with one button is that button's circle.
class GroupedWay extends StatelessWidget {
  const GroupedWay({super.key, required this.way, required this.fine, this.glyph = 16});
  final List<HeaderAct> way;
  final bool fine;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    final here = [for (final act in way) if (act.id == 'home' || act.id == 'sidebar') act];
    final been = notShown(way, here);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: context.tokens.space(2),
      children: [
        for (final half in [here, been])
          if (half.isNotEmpty) GroupedPill(children: [for (final act in half) GroupedSegment(act: act, fine: fine, glyph: glyph)]),
      ],
    );
  }
}

/// One segment of a pill: a circle inside it, as wide as it is tall.
class GroupedSegment extends StatelessWidget {
  const GroupedSegment({super.key, required this.act, required this.fine, this.glyph = 16});
  final HeaderAct act;
  final bool fine;

  /// The glyph's size: Grouped command's is a size up.
  final double glyph;

  @override
  Widget build(BuildContext context) => HeaderPress(act: act, fine: fine, radius: 999, face: (context, state) => GroupedSegmentFace(act: act, state: state, on: act.on, glyph: glyph));
}

class GroupedSegmentFace extends StatelessWidget {
  const GroupedSegmentFace({super.key, required this.act, required this.state, required this.on, this.glyph = 16});
  final HeaderAct act;
  final PressState state;
  final bool on;
  final double glyph;

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
        width: size,
        height: size,
        decoration: BoxDecoration(color: on ? ink : (lit ? paper : null), shape: BoxShape.circle),
        child: Center(child: HeaderGlyph(act, size: glyph, color: color, strokeWidth: 2)),
      ),
      rim: t.color('app-paper-2'),
      ink: ink,
      paper: t.color('app-paper'),
    );
  }
}
