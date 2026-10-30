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
/// - **Under •••**, first, on every screen (Matt, 2026-10-29: "Put the all files folder icon under the more menu as
///   well as the + button in the header"): every note by folder and a new note.
///
/// **On a narrow window** (the Fold folded, a phone) the title wants the room: the way around is Home and the sidebar,
/// then Back (Home always shows, Matt, 2026-10-28: "Also always show the home button on the top bar"), the note's
/// pill is the view and •••, and Forward and every action are one press away under •••. At
/// home, with no note's pill, ••• is a pill of its own for what the way around has put away. The aside's toggle is
/// under ••• at any width: the ends are kept to two pills and a button.
///
/// Iconography: Grouped's - the chosen pack's **Solid** in the pills, an "on" segment of ink with its glyph in paper -
/// and the title pill as Command centre draws it; all of it the size of the home page's dock while the page scrolls
/// ([dockGlyph]), the bar with it.
///
/// **The home page has no search field of its own** while this version draws the bar (Matt, 2026-10-28: "remove the
/// search bar from the home page since it's redundant"): the title pill is the search, the palette finding notes by
/// name as the field did, and ⌘K / Ctrl K still opens it (lib/home/home_filters.dart `searchField`). **Nor its filters'
/// button** (Matt, 2026-10-29: "also remove this filter button on the home page, when on the homepage add it next to
/// the command search bar in the top bar"): the home page hands it to the bar (lib/shell/top_bar_tools.dart
/// `TopBarFill.filters`), and it is a circle of the bar's right after the title pill, the page's own button and panel
/// (Show and Workspace, the counts and the tick), ink while a filter is on. Off the home page there is none. The chips
/// of what is chosen stay on the page.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../../art/lucide.g.dart';
import '../header_toolbar.dart';
import '../page_dock.dart' show dockScrolledScale;
import '../top_bar_tools.dart' show BarButton;
import 'command_row.dart' show CommandField, menuHueGlyph;
import 'grouped_row.dart';
import 'header_kit.dart';

/// The glyphs the home page's dock draws (lib/shell/page_dock.dart: `1.15rem`) at the size the dock is while the page
/// scrolls ([dockScrolledScale]), the rings the same: the shell stamps `data-header='large'` while this version draws
/// the bar, which makes `--app-bar-ring` the dock's `--app-ring` at that scale (assets/css/app.css), and every pill,
/// circle and the bar's height are built from that (Matt, 2026-10-29: "make the header icons and searchbar just a touch
/// smaller to match the size of the buttons in the dock when smaller"). About 14.7, where they were 20 (21 on you)
/// after 2026-10-28's "a size larger" and "very slightly" more.
double dockGlyph(Tokens t) => t.lenOf('1.15rem') * dockScrolledScale;

/// [dockGlyph], and on a phone's width a small step larger (Matt, 2026-10-29: "Make the header icons and search bar
/// slightly larger on mobile"; the rings with it, app.css `[data-header='phone']`).
double groupedCommandGlyph(BuildContext context) => dockGlyph(context.tokens) + (headerOnPhone(context) ? phoneGlyphStep : 0);

HeaderRow groupedCommandRow(BuildContext context, HeaderParts parts) {
  final glyph = groupedCommandGlyph(context);
  Widget solid(Widget child) => styled(context, IconStyle.solid, child);
  final wide = parts.wide;
  // The way around: all four on a wide window; Home, the sidebar and Back on a narrow one, Forward put away. Home is
  // never put away (Matt, 2026-10-28: "Also always show the home button on the top bar").
  // At home on a narrow window the Filters' circle wants a place beside the pill too, so Back, which at home has
  // seldom anywhere to go, is put away with Forward before the pill is squeezed; Filters and Home never are.
  final squeezed = !wide && parts.filters != null;
  final way = [for (final act in parts.way) if (wide || (act.id != 'forward' && !(squeezed && act.id == 'back'))) act];
  final putAway = [...notShown(parts.way, way), ?parts.aside];
  final shown = parts.actions.take(wide ? 2 : 0).toList();
  final rest = notShown(parts.actions, shown);
  final more = parts.more;
  // Each row's glyph in its own hue, as Command centre's menu has them.
  Widget hue(HeaderAct act) => menuHueGlyph(context, act);
  final entries = <HeaderMenuEntry>[
    // What the bar keeps under ••• first (Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as the + button in the header").
    ...keptEntries(parts, more: rest.isNotEmpty || more != null || putAway.isNotEmpty, icon: hue),
    for (final act in rest) HeaderMenuAct(act, icon: hue(act)),
    if (more != null) HeaderMenuAct(more, icon: hue(more)),
    if (putAway.isNotEmpty) ...[
      if (rest.isNotEmpty || more != null) const HeaderMenuRule(),
      const HeaderMenuLabel('Go'),
      for (final act in putAway) HeaderMenuAct(act, icon: hue(act)),
    ],
  ];
  final overflow = entries.isEmpty
      ? null
      : HeaderMenuButton(
          act: moreAct(label: parts.onNote ? 'More for this note: the rest of its tools' : 'More'),
          fine: parts.fine,
          radius: 999,
          entries: entries,
          face: (context, state, open) => GroupedSegmentFace(act: moreAct(), state: state, on: open, glyph: glyph),
        );
  return HeaderRow(
    lead: [
      if (way.isNotEmpty) solid(GroupedWay(way: way, fine: parts.fine, glyph: glyph)),
    ],
    // The pill opens ••• itself where there is no palette.
    centre: styled(context, IconStyle.outline, CommandField(parts: parts, entries: entries, large: true)),
    trail: [
      // The home page's Filters beside the pill (Matt, 2026-10-29: "when on the homepage add it next to the command
      // search bar in the top bar"): the page's own button and panel, a circle of the bar's.
      if (parts.filters case final filters?) solid(KeyedSubtree(key: HeaderAct.keyOf('filters'), child: _FiltersCircle(filters: filters))),
      ?parts.presence,
      if (parts.onNote)
        solid(
          GroupedPill(
            children: [
              if (parts.view case final view?) GroupedSegment(act: view, fine: parts.fine, glyph: glyph),
              for (final act in shown) GroupedSegment(act: act, fine: parts.fine, glyph: glyph),
              ?overflow,
            ],
          ),
        )
      else ...[
        ...fallbackTools(parts),
        if (overflow != null) solid(GroupedPill(children: [overflow])),
      ],
      ?parts.activity,
      if (parts.you.isNotEmpty) solid(GroupedYou(parts: parts, glyph: glyph)),
    ],
  );
}

/// The home page's Filters as one of the bar's circles: the page's button (lib/home/home_filters.dart
/// `HomeFiltersButton`) drawn as a Grouped segment in a pill of one, ink while a filter is on, as the page's own was.
class _FiltersCircle extends StatelessWidget {
  const _FiltersCircle({required this.filters});
  final BarButton filters;

  static const HeaderAct _act = HeaderAct(id: 'filters', label: 'Filters', word: 'Filters', hue: 'indigo', icon: Lucide.slidersHorizontal, onPress: null);

  @override
  Widget build(BuildContext context) => filters(
        (context, state, {required open, required on}) {
          final lit = PressState(hovered: state.hovered || open, pressed: state.pressed, focused: state.focused);
          return GlacierFocusRing(
            visible: state.focused,
            radius: 999,
            child: GroupedPill(children: [GroupedSegmentFace(act: _act, state: lit, on: on, glyph: groupedCommandGlyph(context))]),
          );
        },
      );
}
