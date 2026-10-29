/// Version 4 of the header toolbar, **Command centre** (lib/shell/header_toolbar.dart): a bar that is mostly a
/// place to type. At the start, Home and Back (the sidebar's toggle at home, where there is nowhere back to go;
/// Home always, Matt, 2026-10-28: "Also always show the home button on the top bar"); in the
/// middle a pill with the note's name and a search glyph, which opens the command palette, where every command the
/// app has is a word away (lib/commands/command_bar.dart; ⌘K said on it under a mouse); at the end one primary
/// action - the view switch on a note, a new note at home - and •••.
///
/// ••• holds everything else, in sections, each row's glyph in its own colour: **This note** (its actions and More
/// for this note), **Go** (Home, the sidebar, Back or Forward, the side panel, a new note), and **You** (the bell,
/// the organizations, Settings). Without a palette to open (a shell that was given none) the pill opens that menu.
///
/// Iconography: the chosen pack's **Outline** at a lighter stroke than today's (1.7), muted, so the pill and the one
/// primary action - paper glyph on an ink round - are what the eye finds; colour lives in the menu.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../../art/lucide.g.dart';
import '../header_toolbar.dart';
import '../top_bar_tools.dart' show BarButton;
import 'grouped_row.dart' show fallbackTools;
import 'header_kit.dart';

HeaderRow commandRow(BuildContext context, HeaderParts parts) {
  Widget outline(Widget child) => styled(context, IconStyle.outline, child);
  // A small step larger on a phone (Matt, 2026-10-29: "Make the header icons and search bar slightly larger on mobile").
  final step = headerOnPhone(context) ? phoneGlyphStep : 0.0;
  // Back where there is a note or a page to come back from; the sidebar's toggle at home.
  final start = parts.atHome ? (parts.sidebar ?? parts.back) : (parts.back ?? parts.sidebar);
  final primary = parts.onNote ? parts.view : parts.newNote;
  Widget colour(HeaderAct act) => HeaderGlyph(act, size: 16, color: hueInk(context.tokens, _hueOf(act)), strokeWidth: 2);
  final noteRows = <HeaderMenuEntry>[
    for (final act in notShown(parts.noteActs, [?primary])) HeaderMenuAct(act, icon: colour(act)),
    if (parts.more case final more?) HeaderMenuAct(more, icon: colour(more)),
  ];
  final goRows = <HeaderMenuEntry>[
    // A new note and every note at home; on a note they are the tabs' + and the sidebar's, and the menu is long enough.
    for (final act in notShown([...parts.way, ?parts.aside, if (!parts.onNote) ...[?parts.newNote, ?parts.allNotes]], [?parts.home, ?start, ?primary])) HeaderMenuAct(act, icon: colour(act)),
  ];
  final youRows = youEntries(parts, icon: colour);
  final entries = <HeaderMenuEntry>[
    if (noteRows.isNotEmpty) ...[const HeaderMenuLabel('This note'), ...noteRows],
    if (goRows.isNotEmpty) ...[if (noteRows.isNotEmpty) const HeaderMenuRule(), const HeaderMenuLabel('Go'), ...goRows],
    if (youRows.isNotEmpty) ...[if (noteRows.isNotEmpty || goRows.isNotEmpty) const HeaderMenuRule(), const HeaderMenuLabel('You'), ...youRows],
  ];
  return HeaderRow(
    lead: [
      // Home is always in the row, whatever the width (Matt, 2026-10-28: "Also always show the home button on the top bar").
      if (parts.home case final home?) outline(_Plain(act: home, fine: parts.fine, step: step)),
      if (start != null) outline(_Plain(act: start, fine: parts.fine, step: step)),
    ],
    centre: outline(CommandField(parts: parts, entries: entries)),
    trail: [
      // The home page's Filters right after the pill, as Grouped command has them (Matt, 2026-10-29, of this bar: "the
      // search bar and filters is still showing on the homepage on mobile when it shouldn't").
      if (parts.filters case final filters?) outline(KeyedSubtree(key: HeaderAct.keyOf('filters'), child: _Filters(filters: filters, step: step))),
      ?parts.presence,
      if (!parts.onNote) ...fallbackTools(parts),
      if (primary != null) outline(_Primary(act: primary, fine: parts.fine, step: step)),
      if (entries.isNotEmpty) outline(_CommandMenu(parts: parts, entries: entries, step: step)),
    ],
  );
}

const Map<String, String> _hues = {'home': 'blue', 'sidebar': 'indigo', 'back': 'cyan', 'forward': 'cyan', 'bell': 'amber', 'organizations': 'magenta', 'settings': 'lime', 'aside': 'mint', 'search': 'blue', 'new': 'green', 'all': 'indigo', 'more': 'indigo'};

String _hueOf(HeaderAct act) => _hues[act.id] ?? act.hue;

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
    Widget face(BuildContext context, PressState state, bool open) {
            final lit = state.hovered || state.pressed || open;
            final muted = t.color('glacier-text-muted');
            return Container(
              height: t.len('app-bar-ring'),
              padding: EdgeInsets.symmetric(horizontal: t.space(3)),
              decoration: BoxDecoration(
                color: t.color(lit ? 'app-paper-3' : 'app-paper-2'),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.color(lit ? 'glacier-border' : 'glacier-border-subtle'), width: t.len('glacier-hairline')),
              ),
              child: Row(
                spacing: t.space(2),
                children: [
                  HeaderGlyph(act, size: (large ? 16 : 15) + (phone ? phoneGlyphStep : 0), color: muted, strokeWidth: 1.9, wash: false),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(words, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text(phone ? 'md' : 'sm', weight: title == null || title.isEmpty ? 'regular' : 'medium', color: title == null || title.isEmpty ? muted : t.color('glacier-text'))),
                    ),
                  ),
                  if (parts.fine && search != null)
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

/// A ring with no ground: Back, the sidebar's toggle.
class _Plain extends StatelessWidget {
  const _Plain({required this.act, required this.fine, this.step = 0});
  final HeaderAct act;
  final bool fine;

  /// A phone's step up.
  final double step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    return HeaderPress(
      act: act,
      fine: fine,
      radius: 999,
      face: (context, state) {
        final lit = state.hovered || state.pressed || act.on;
        return Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(shape: BoxShape.circle, color: lit ? t.color('app-paper-2') : null),
          child: Center(child: HeaderGlyph(act, size: 19 + step, color: lit ? t.color('glacier-text') : t.color('glacier-text-muted'), strokeWidth: 1.7)),
        );
      },
    );
  }
}

/// The home page's Filters (lib/home/home_filters.dart `HomeFiltersButton`) as one of this bar's rings: the page's
/// own button and panel in the bar's face, the round lit while its panel is open, ink while a filter is on.
class _Filters extends StatelessWidget {
  const _Filters({required this.filters, required this.step});
  final BarButton filters;
  final double step;

  static const HeaderAct _act = HeaderAct(id: 'filters', label: 'Filters', word: 'Filters', hue: 'indigo', icon: Lucide.slidersHorizontal, onPress: null);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    return filters((context, state, {required open, required on}) {
      final lit = state.hovered || state.pressed || open;
      final ink = on ? t.color('glacier-bg') : (lit ? t.color('glacier-text') : t.color('glacier-text-muted'));
      return GlacierFocusRing(
        visible: state.focused,
        radius: 999,
        child: Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? t.color('glacier-text') : (lit ? t.color('app-paper-2') : null)),
          child: Center(child: HeaderGlyph(_act, size: 18 + step, color: ink, strokeWidth: 1.7)),
        ),
      );
    });
  }
}

/// The one action that stands out: paper on an ink round.
class _Primary extends StatelessWidget {
  const _Primary({required this.act, required this.fine, this.step = 0});
  final HeaderAct act;
  final bool fine;
  final double step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    return HeaderPress(
      act: act,
      fine: fine,
      radius: 999,
      face: (context, state) => AnimatedScale(
        scale: state.pressed ? 0.92 : 1,
        duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
        child: Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('glacier-text')),
          child: Center(child: HeaderGlyph(act, size: 16 + step, color: t.color('glacier-bg'), strokeWidth: 2)),
        ),
      ),
    );
  }
}

/// ••• and its sections, with the bell's dot while something is new.
class _CommandMenu extends StatelessWidget {
  const _CommandMenu({required this.parts, required this.entries, this.step = 0});
  final HeaderParts parts;
  final List<HeaderMenuEntry> entries;
  final double step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final act = moreAct(label: 'Everything else');
    return HeaderMenuButton(
      act: HeaderAct(id: act.id, label: act.label, word: act.word, hue: act.hue, icon: act.icon, onPress: act.onPress, dot: parts.unread && parts.bell != null),
      fine: parts.fine,
      radius: 999,
      entries: entries,
      menuLabel: 'Everything else',
      face: (context, state, open) {
        final lit = state.hovered || state.pressed || open;
        final marked = HeaderAct(id: act.id, label: act.label, word: act.word, hue: act.hue, icon: act.icon, onPress: act.onPress, dot: parts.unread && parts.bell != null);
        return withMarks(
          marked,
          Container(
            width: ring,
            height: ring,
            decoration: BoxDecoration(shape: BoxShape.circle, color: lit ? t.color('app-paper-2') : null),
            child: Center(child: HeaderGlyph(act, size: 19 + step, color: lit ? t.color('glacier-text') : t.color('glacier-text-muted'), strokeWidth: 1.7)),
          ),
          rim: t.color('glacier-bg'),
          ink: t.color('glacier-text'),
          paper: t.color('app-paper'),
        );
      },
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
