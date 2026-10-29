/// Version 3 of the header toolbar, **Vibrant tiles** (lib/shell/header_toolbar.dart): each control a small rounded
/// tile in a hue of its own, the Market's plugin tiles' colours (lib/market/market_items.dart `marketHues`, the same
/// wash from the deep shade to the bright and the same light from the top corner), with its glyph in white. Colour
/// says what a thing is before its shape does: the view amber, Share green, History purple, Home blue.
///
/// Fewer at once. On a phone the row holds Home, the sidebar and Back, then the view and the note's first action,
/// then a tile of ••• with everything else - Forward, the rest of the note's, More for this note, the bell, the
/// organizations, Settings, the aside - each row of its menu wearing its own small tile. On a wide window the bell
/// and Settings come out as tiles too, and the note's tiles say their word beside them, on a wash of their hue.
///
/// Differs from what was asked ("a subtle label under each on wide screens"): the word is beside its tile, not
/// under it. The row is a ring high, 28 to 34 points since the header was condensed (Matt, 2026-10-17: "make the
/// header of the app more condensed by default"), which leaves no line under a tile without the bar, and every
/// page under it, growing.
///
/// Iconography: the chosen pack in its **Filled** style, in white and with no wash, as the Market draws a plugin's
/// mark on its tile. A control that is on wears a white ring inside its tile.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icon_packs.dart' show IconStyle;
import '../../market/market_items.dart' show tileLight;
import '../../notes/tabs/bar_parts.dart' show InsetRing;
import '../header_toolbar.dart';
import 'grouped_row.dart' show fallbackTools;
import 'header_kit.dart';

const Color _white = Color(0xFFFFFFFF);

HeaderRow tilesRow(BuildContext context, HeaderParts parts) {
  Widget filled(Widget child) => styled(context, IconStyle.filled, child);
  final wide = parts.wide;
  final roomy = parts.room >= 1000;
  // The way around: all four on a wide window; Forward, seldom anywhere to go, under ••• on a phone.
  final way = [for (final act in parts.way) if (wide || act.id != 'forward') act];
  final shownActs = parts.actions.take(roomy ? 3 : (wide ? 2 : 1)).toList();
  final you = wide ? [?parts.bell, ?parts.settings] : const <HeaderAct>[];
  final hidden = <HeaderMenuEntry>[
    for (final act in notShown(parts.way, way)) HeaderMenuAct(act, icon: _MenuTile(act: act)),
    for (final act in notShown(parts.actions, shownActs)) HeaderMenuAct(act, icon: _MenuTile(act: act)),
    if (parts.more case final more?) HeaderMenuAct(more, icon: _MenuTile(act: more)),
  ];
  final yours = youEntries(
    HeaderParts(bell: wide ? null : parts.bell, organizations: parts.organizations, orgs: parts.orgs, onOrganization: parts.onOrganization, settings: wide ? null : parts.settings, unread: parts.unread, fine: parts.fine, room: parts.room),
    icon: (act) => _MenuTile(act: act),
  );
  final entries = <HeaderMenuEntry>[
    ...hidden,
    if (hidden.isNotEmpty && yours.isNotEmpty) const HeaderMenuRule(),
    ...yours,
    if (parts.aside case final aside? when !wide) ...[const HeaderMenuRule(), HeaderMenuAct(aside, icon: _MenuTile(act: aside))],
  ];
  return HeaderRow(
    lead: [
      filled(Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [for (final act in way) _Tile(act: act, fine: parts.fine)])),
    ],
    trail: [
      ?parts.presence,
      if (parts.onNote)
        filled(Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [for (final act in [?parts.view, ...shownActs]) _Tile(act: act, fine: parts.fine, word: wide)]))
      else
        ...fallbackTools(parts),
      if (you.isNotEmpty) filled(Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [for (final act in you) _Tile(act: act, fine: parts.fine)])),
      if (entries.isNotEmpty)
        filled(
          HeaderMenuButton(
            act: moreAct(label: 'Everything else'),
            fine: parts.fine,
            entries: entries,
            menuLabel: 'Everything else',
            face: (context, state, open) => _TileFace(act: moreAct(), state: state, on: open, ink: true, dot: !wide && parts.unread),
          ),
        ),
      if (parts.aside case final aside? when wide) filled(_Tile(act: aside, fine: parts.fine)),
    ],
  );
}

/// The hue of the bar's own controls, by id; the note's wear theirs ([HeaderAct.hue]).
const Map<String, String> _hues = {'home': 'blue', 'sidebar': 'indigo', 'folders': 'amber', 'back': 'cyan', 'forward': 'cyan', 'bell': 'amber', 'organizations': 'magenta', 'settings': 'lime', 'aside': 'mint', 'more': 'indigo'};

String _hueOf(HeaderAct act) => _hues[act.id] ?? act.hue;

/// A tile, and with [word] its word beside it on a wash of its hue.
class _Tile extends StatelessWidget {
  const _Tile({required this.act, required this.fine, this.word = false});
  final HeaderAct act;
  final bool fine;
  final bool word;

  @override
  Widget build(BuildContext context) => HeaderPress(
        act: act,
        fine: fine,
        face: (context, state) {
          final face = _TileFace(act: act, state: state, on: act.on);
          if (!word) return face;
          final t = context.tokens;
          final ink = hueInk(t, _hueOf(act));
          final lit = state.hovered || state.pressed;
          return Container(
            height: t.len('app-bar-ring'),
            padding: const EdgeInsetsDirectional.only(start: 2, end: 10),
            decoration: BoxDecoration(color: ink.withValues(alpha: lit ? 0.2 : (t.isDark ? 0.16 : 0.1)), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [face, ExcludeSemantics(child: Text(act.word, style: t.text('sm', weight: 'semibold', color: ink)))],
            ),
          );
        },
      );
}

class _TileFace extends StatelessWidget {
  const _TileFace({required this.act, required this.state, required this.on, this.ink = false, this.dot = false});
  final HeaderAct act;
  final PressState state;
  final bool on;

  /// The tile of ••• is the page's ink, not a hue: it holds every colour.
  final bool ink;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.len('app-bar-ring') - 4;
    const radius = 8.0;
    final (deep, bright) = hueShades(_hueOf(act));
    final pressed = state.pressed && !state.disabled;
    final ground = ink
        ? BoxDecoration(color: t.color('glacier-text'), borderRadius: BorderRadius.circular(radius))
        : BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, Color.lerp(deep, bright, 0.55)!, bright]),
            boxShadow: state.hovered && !state.disabled ? [BoxShadow(color: deep.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))] : null,
          );
    final glyph = ink ? t.color('glacier-bg') : _white;
    Widget tile = AnimatedScale(
      scale: pressed ? 0.92 : 1,
      duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
      child: SizedBox(
        width: size,
        height: size,
        child: InsetRing(
          on: on,
          color: _white.withValues(alpha: 0.9),
          width: 2,
          radius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: ground,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!ink) tileLight(radius: radius),
                Center(child: HeaderGlyph(act, size: 15, color: glyph, strokeWidth: 2, wash: false)),
              ],
            ),
          ),
        ),
      ),
    );
    final marked = HeaderAct(id: act.id, label: act.label, word: act.word, hue: act.hue, onPress: act.onPress, dot: act.dot || dot, count: act.count);
    return withMarks(marked, tile, rim: t.color('glacier-bg'), ink: t.color('glacier-text'), paper: t.color('app-paper'));
  }
}

/// A row's small tile in a menu.
class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.act});
  final HeaderAct act;

  @override
  Widget build(BuildContext context) {
    final (deep, bright) = hueShades(_hueOf(act));
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, bright]),
      ),
      child: Center(child: HeaderGlyph(act, size: 12, color: _white, strokeWidth: 2.2, wash: false)),
    );
  }
}
