/// Version 6 of the header toolbar, **Grouped command** (lib/shell/header_toolbar.dart; Matt, 2026-10-28, after the
/// contact sheet on 2.3.61: "Make a version that combines the command center and grouped sections"): Grouped's
/// pills at either end and Command centre's pill in the middle.
///
/// - **The way around**, at the start: Grouped's two pills - Home and the sidebar, then Back and Forward, a gap
///   between them - each button a circle (Matt, 2026-10-28: "make the buttons circular instead of pill shaped").
/// - **The note's name**, between: Command centre's pill, a search glyph and the title, which opens the command
///   palette (⌘K or Ctrl K said on it under a mouse), taking whatever room the two ends leave.
/// - **The note's own**, at the end: Grouped's second pill, the view switch and the two most used of its actions, with
///   ••• for the rest of them, More for this note, and what the row has no room for. Then the round button for you
///   (the bell, the organizations, Settings), wearing the bell's dot.
///
/// **On a narrow window** (the Fold folded, a phone) the title wants the room: the way around is Home and the sidebar,
/// then Back (Home always shows, Matt, 2026-10-28: "Also always show the home button on the top bar"), the note's
/// pill is the view and •••, and Forward and every action are one press away under •••. At
/// home, with no note's pill, ••• is a pill of its own for what the way around has put away. The aside's toggle is
/// under ••• at any width: the ends are kept to two pills and a button.
///
/// Iconography: Grouped's - the chosen pack's **Solid** in the pills, an "on" segment of ink with its glyph in paper -
/// and the title pill as Command centre draws it; all of it **a size larger** than the other versions, the bar with
/// it ([_glyph]).
///
/// **The home page has no search field of its own** while this version draws the bar (Matt, 2026-10-28: "remove the
/// search bar from the home page since it's redundant"): the title pill is the search, the palette finding notes by
/// name as the field did, and ⌘K / Ctrl K still opens it. The filters' button stays, at the head of the list, at its
/// end (lib/home/home_filters.dart `searchField`).
library;

import 'package:flutter/widgets.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../header_toolbar.dart';
import 'command_row.dart' show CommandField;
import 'grouped_row.dart';
import 'header_kit.dart';

/// A size up from Grouped's 16 (Matt, 2026-10-28: "make the elements a size larger"), and a notch more that evening
/// ("make the top bar items slightly larger very slightly": 19 became 20), in rings a size up too: the shell stamps
/// `data-header='large'` while this version draws the bar, which makes `--app-bar-ring` 34-42px (assets/css/app.css),
/// and every pill, circle and the bar's height are built from that.
const double _glyph = 20;

HeaderRow groupedCommandRow(BuildContext context, HeaderParts parts) {
  Widget solid(Widget child) => styled(context, IconStyle.solid, child);
  final wide = parts.wide;
  // The way around: all four on a wide window; Home, the sidebar and Back on a narrow one, Forward put away. Home is
  // never put away (Matt, 2026-10-28: "Also always show the home button on the top bar").
  final way = [for (final act in parts.way) if (wide || act.id != 'forward') act];
  final putAway = [...notShown(parts.way, way), ?parts.aside];
  final shown = parts.actions.take(wide ? 2 : 0).toList();
  final rest = notShown(parts.actions, shown);
  final more = parts.more;
  final entries = <HeaderMenuEntry>[
    for (final act in rest) HeaderMenuAct(act),
    if (more != null) HeaderMenuAct(more),
    if (putAway.isNotEmpty) ...[
      if (rest.isNotEmpty || more != null) const HeaderMenuRule(),
      const HeaderMenuLabel('Go'),
      for (final act in putAway) HeaderMenuAct(act),
    ],
  ];
  final overflow = entries.isEmpty
      ? null
      : HeaderMenuButton(
          act: moreAct(label: parts.onNote ? 'More for this note: the rest of its tools' : 'More'),
          fine: parts.fine,
          radius: 999,
          entries: entries,
          face: (context, state, open) => GroupedSegmentFace(act: moreAct(), state: state, on: open, glyph: _glyph),
        );
  return HeaderRow(
    lead: [
      if (way.isNotEmpty) solid(GroupedWay(way: way, fine: parts.fine, glyph: _glyph)),
    ],
    // The pill opens ••• itself where there is no palette.
    centre: styled(context, IconStyle.outline, CommandField(parts: parts, entries: entries, large: true)),
    trail: [
      ?parts.presence,
      if (parts.onNote)
        solid(
          GroupedPill(
            children: [
              if (parts.view case final view?) GroupedSegment(act: view, fine: parts.fine, glyph: _glyph),
              for (final act in shown) GroupedSegment(act: act, fine: parts.fine, glyph: _glyph),
              ?overflow,
            ],
          ),
        )
      else ...[
        ...fallbackTools(parts),
        if (overflow != null) solid(GroupedPill(children: [overflow])),
      ],
      if (parts.you.isNotEmpty) solid(GroupedYou(parts: parts, glyph: _glyph + 1)),
    ],
  );
}
