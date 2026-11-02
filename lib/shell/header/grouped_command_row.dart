/// The header toolbar's line of controls, **Grouped command** (lib/shell/header_toolbar.dart; Matt, 2026-10-28, after
/// the contact sheet on 2.3.61: "Make a version that combines the command center and grouped sections"): Grouped's
/// pills at either end and Command centre's pill in the middle. The sixth of six versions, and since 2026-11-01 the
/// only one: the contact sheet ended here (Matt: "we currently have too many appearance settings for different title
/// bar layouts and stuff"), and the pieces it took from Grouped and Command centre are at the foot of this file.
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

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../../art/lucide.g.dart';
import '../../notes/tabs/bar_parts.dart' show controlGlass, controlGlassBox;
import '../header_toolbar.dart';
import '../page_dock.dart' show dockScrolledScale;
import '../top_bar_tools.dart' show BarButton;
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

/// How wide the row must be for the Academy's circle to stand in it: the opened Fold, the Mac and a phone 412 points
/// across, where the title pill keeps its word. On a narrower phone (390, and the Fold 8's cover screen at about 344)
/// the circle would cut the pill to "Se…", so the Academy is under ••• there, one press away.
const double academyRowRoom = 370;

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
  // The Academy's circle, just before the button for you, where the row has room for one more ([academyRowRoom]); a
  // narrower phone gives the title pill its room and keeps the Academy under •••.
  final academy = parts.academy != null && parts.room >= academyRowRoom ? parts.academy : null;
  final putAway = [...notShown(parts.way, way), ?parts.aside, if (academy == null) ?parts.academy];
  final shown = parts.actions.take(wide ? 2 : 0).toList();
  final rest = notShown(parts.actions, shown);
  final more = parts.more;
  // Each row's glyph in its own hue, as Command centre's menu has them.
  Widget hue(HeaderAct act) => menuHueGlyph(context, act);
  final menu = parts.menu;
  final noted = menu != null && more != null;
  final go = <HeaderMenuEntry>[const HeaderMenuLabel('Go'), for (final act in putAway) HeaderMenuAct(act, icon: hue(act))];
  final entries = <HeaderMenuEntry>[
    // What the bar keeps under ••• first (Matt, 2026-10-29: "Put the all files folder icon under the more menu as well as the + button in the header").
    ...keptEntries(parts, more: rest.isNotEmpty || more != null || putAway.isNotEmpty, icon: hue),
    // A note's More sheet, row by row, made as the menu opens (Matt, 2026-11-02: "Show more items in the more dropdown
    // we should be able to scroll on it instead of needing to open a new modal"): the way around first, then the
    // actions the sheet has no row for (Share), its groups, All settings… for the sheet itself, and Move to Trash. A
    // row the bar has an action for (Links with its count, History, Pin…) is that action, under its key; what the pill
    // shows is not listed again.
    if (noted) ...[
      if (putAway.isNotEmpty) ...[...go, const HeaderMenuRule()],
      HeaderMenuLater((context) {
        final groups = menu();
        final ids = {for (final group in groups) for (final item in group.items) item.id};
        final own = <String, HeaderAct>{};
        final extra = <HeaderAct>[];
        for (final act in rest) {
          if (ids.contains(act.id)) {
            own[act.id] = act;
          } else if (act.id == 'history' && ids.contains('keep-history')) {
            // History where the note keeps none yet: the sheet's Keep version history is its row.
            own['keep-history'] = act;
          } else {
            extra.add(act);
          }
        }
        return [
          for (final act in extra) HeaderMenuAct(act, icon: hue(act)),
          if (extra.isNotEmpty) const HeaderMenuRule(),
          ...noteMenuEntries(context, groups, more: allSettingsAct(more.onPress ?? () {}), leave: {for (final act in shown) act.id}, own: own, hued: true),
        ];
      }),
    ] else ...[
      for (final act in rest) HeaderMenuAct(act, icon: hue(act)),
      if (more != null) HeaderMenuAct(more, icon: hue(more)),
      if (putAway.isNotEmpty) ...[
        if (rest.isNotEmpty || more != null) const HeaderMenuRule(),
        ...go,
      ],
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
      // Ghost Academy, immediately left of the button for you (Matt, 2026-11-02): a pill of one, the bar's glass.
      if (academy != null) solid(GroupedPill(children: [GroupedSegment(act: academy, fine: parts.fine, glyph: glyph)])),
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

// ---- the pieces, from the versions the contact sheet let go (Grouped, Command centre) -------------------------------

/// A screen's own controls handed as widgets alone, drawn as they come, scrolling where they would run out of room.
List<Widget> fallbackTools(HeaderParts parts) => [
      if (parts.tools case final tools?)
        ConstrainedBox(constraints: BoxConstraints(maxWidth: parts.room / 2), child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: tools)),
      ?parts.tail,
    ];

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
            // The header's control glass, as the pills are, where it was the bar showing through a ring (Matt,
            // 2026-11-01: "make sure all components in the header support glass").
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: controlGlass(t, lit: lit),
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

/// A pill of segments on the header's control glass, a ring high, with a hairline round it: translucent over the bar's
/// own glass and blur, where it was the page's second paper, solid (Matt, 2026-11-01: "the header is a mix of glass and
/// not glass elements").
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
      decoration: controlGlassBox(t, border: hairline),
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
        // Lit, the control glass once more over the pill's, so the two together are its lit step and the segment stays
        // glass (it was the page's paper); on, ink, a state rather than a surface.
        decoration: BoxDecoration(color: on ? ink : (lit ? controlGlass(t) : null), shape: BoxShape.circle),
        child: Center(child: HeaderGlyph(act, size: glyph, color: color, strokeWidth: 2)),
      ),
      rim: paper,
      ink: ink,
      paper: t.color('app-paper'),
    );
  }
}

const Map<String, String> _hues = {'folders': 'amber', 'home': 'blue', 'sidebar': 'indigo', 'back': 'cyan', 'forward': 'cyan', 'bell': 'amber', 'organizations': 'magenta', 'settings': 'lime', 'academy': 'purple', 'aside': 'mint', 'search': 'blue', 'new': 'green', 'all': 'indigo', 'more': 'indigo'};

String _hueOf(HeaderAct act) => _hues[act.id] ?? act.hue;

/// A row's glyph in a menu of •••, in its own hue as Command centre draws them: Grouped command's menu wears the same
/// (Matt, 2026-10-30: "The colors for the dropdown more menu are missing on general deployments though I see the
/// colored icons on my end": he was on Command centre, everyone else on the default, whose menu was grey).
Widget menuHueGlyph(BuildContext context, HeaderAct act) => HeaderGlyph(act, size: 16, color: hueInk(context.tokens, _hueOf(act)), strokeWidth: 2);

/// The pill in the middle: a search glyph, the note's name (or what the palette is for), and ⌘K under a mouse.
class CommandField extends StatelessWidget {
  const CommandField({super.key, required this.parts, required this.entries, this.large = false});
  final HeaderParts parts;

  /// A size up: the title's words in the page's own size, the glyph with them (Grouped command's).
  /// Grouped command's pill (version 6): the bar's larger ring, and "Search" alone where it is narrow. Its words
  /// are the small size as the other pill's are (Matt, 2026-10-29: "the text in the top searchbar is a bit too large").
  final bool large;

  /// The menu of •••, which the pill opens where there is no palette.
  final List<HeaderMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final search = parts.search;
    final title = parts.title;
    // On a phone the words are a size up (Matt, 2026-10-29: "Make the header icons and search bar slightly larger on
    // mobile"), which leaves the long words no room there: the one word.
    final phone = headerOnPhone(context);
    final words = title == null || title.isEmpty ? (phone || (large && !parts.wide) ? 'Search' : 'Search or run a command') : title;
    final act = search ?? HeaderAct(id: 'search', label: 'Everything else', word: 'Search', hue: 'blue', icon: Lucide.search, onPress: () {});
    final named = HeaderAct(id: act.id, label: title == null || title.isEmpty ? act.label : '${act.label}: $title', word: act.word, hue: act.hue, icon: act.icon, onPress: act.onPress);
    final double glyphSize = (large ? 16 : 15) + (phone ? phoneGlyphStep : 0);
    final hint = parts.fine && search != null;
    Widget face(BuildContext context, PressState state, bool open) {
            final lit = state.hovered || state.pressed || open;
            final muted = t.color('glacier-text-muted');
            return Container(
              height: t.len('app-bar-ring'),
              padding: EdgeInsets.symmetric(horizontal: t.space(3)),
              // The header's control glass, the bar's blur under it, where it was the second paper and the third lit
              // (Matt, 2026-11-01: "make sure all components in the header support glass").
              decoration: controlGlassBox(t, lit: lit),
              // Squeezed below its glass, the gap after it and the key's hint (a Mac's window at its floor of 360 in the
              // Islands, whose window buttons take the bar's start; or the one frame a screen's own controls stay in the
              // row after it goes, before they are handed back), the line keeps that much and is cut at the pill's edge.
              child: ConstraintsTransformBox(
                alignment: AlignmentDirectional.centerStart,
                clipBehavior: Clip.hardEdge,
                constraintsTransform: (box) {
                  final least = glyphSize + t.space(2) + (hint ? t.space(2) + 48 : 0);
                  return box.maxWidth >= least ? box : box.copyWith(minWidth: least, maxWidth: least);
                },
                child: Row(
                  spacing: t.space(2),
                  children: [
                    HeaderGlyph(act, size: glyphSize, color: muted, strokeWidth: 1.9, wash: false),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text(phone ? 'md' : 'sm', weight: title == null || title.isEmpty ? 'regular' : 'medium', color: title == null || title.isEmpty ? muted : t.color('glacier-text'))),
                      ),
                    ),
                    if (hint)
                      ExcludeSemantics(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: t.color('glacier-border'), width: 1)),
                          // The Mac's ⌘ is drawn, not typed: the app's faces have no glyph for it. Ctrl elsewhere.
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 2,
                            children: [
                              if (defaultTargetPlatform == TargetPlatform.macOS)
                                CustomPaint(size: Size.square(t.fontSize('xs') * 0.85), painter: _CommandKey(muted))
                              else
                                Text('Ctrl', style: t.text('xs', weight: 'medium', color: muted)),
                              Text('K', style: t.text('xs', weight: 'medium', color: muted)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
    }

    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: search != null || entries.isEmpty
            ? HeaderPress(act: named, fine: parts.fine, radius: 999, face: (context, state) => face(context, state, false))
            : HeaderMenuButton(act: named, fine: parts.fine, radius: 999, entries: entries, menuLabel: 'Everything else', face: face),
      ),
    );
  }
}

/// ⌘, the Mac's command key: a square with a loop at each corner.
class _CommandKey extends CustomPainter {
  const _CommandKey(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final loop = side * 0.2;
    final inner = Rect.fromLTWH(loop * 2, loop * 2, side - loop * 4, side - loop * 4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.1;
    canvas.drawRect(inner, paint);
    for (final corner in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
      canvas.drawCircle(Offset(corner.dx + (corner.dx < side / 2 ? -loop : loop), corner.dy + (corner.dy < side / 2 ? -loop : loop)), loop, paint);
    }
  }

  @override
  bool shouldRepaint(_CommandKey old) => old.color != color;
}
