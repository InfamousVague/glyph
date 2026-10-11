/// The map card: where a note was written, or a place in its words, drawn. Ports `src/app/editor/MapCard.tsx` and
/// `src/app/editor/MapCard.module.css`. Matt: "show a map card embedded on the note". A dumb component: it draws
/// the tag it is given, never reads the note, never asks for a name and never writes.
///
/// Two layers, always both. Under, the quiet card: paper, a faint dot grid (a map without a map, in the dotwork
/// family of the ghost) and the pin, or a ring for a rough tag, since an area is not a point. The pin is the same
/// drawing in the same place on both layers, so a map arriving only deepens its ink. It sits a little below the
/// middle of the box (the map is centred to match), clear of the place's chip above it and the chips at the foot.
/// Over it, in `map` mode, the map's tiles, fading in once they have loaded: loading, offline and every tile
/// failed are one state, the quiet card. No spinner, no error copy. The tile layer is greyed and washed with the
/// page's paper so every tile sits between the fourth and third inks and the pin is the only full-ink mark,
/// inverted on a dark page from the app's own theme.
///
/// In `ask` mode (the reader) the quiet card carries "Show the map" and a tap fetches nothing until then.
/// Otherwise a tap opens the place in the device's maps app, with the place or the coordinates and never the
/// note's title.
///
/// Two sizes: the card, and the header a note made from A map at the top wears, 10rem tall on a phone and 16rem
/// from 600px, as wide as the note's column up to 48rem. And [MapPicture]: the same box with the quiet layer
/// alone.
///
/// What differs:
/// - THE TILES ARE A SEAM. The page draws OpenStreetMap's tiles through Leaflet, fetched over the network; this
///   stage has neither. [MapTilesBuilder] is given the tag, the zoom and the box and draws the tiles, centred on
///   the tag, calling `onLoaded` once at least one tile is in; the card does everything round it (the map's box 20
///   pixels past the foot so its middle is where the pin is, the grey and the wash, the fade, the full-ink pin over
///   it, the credit). With no builder a card in `map` mode is the quiet card, which is the page offline.
/// - The grey of the tile layer is one colour matrix, the product of the stylesheet's
///   `grayscale(1) contrast(0.92) brightness(1.04)`, and `grayscale(1) invert(1) brightness(1.1)` on a dark page.
///   Leaflet's seams between tiles (`mix-blend-mode`, 256.5px) are the builder's own business.
/// - `dark` is read from the theme the card is drawn in unless said: the page was told it because its theme is a
///   React prop there.
/// - A tap is `onOpen` (core/placeLink.ts `openPlace` on the page): the caller has the opener.
/// - `--map-scale` is `scale`. `className` has no counterpart.
/// - The focus ring of the page's `<button>` is not drawn: nothing here takes the keyboard's focus yet.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/icons.dart' show placePath;
import '../../art/svg_path.dart';
import '../../core/place_refs.dart';
import '../looks/look.dart' show layoutUnit;
import 'inline_box.dart';

/// The ordinary card, or the header across a map note's column (`look: map`).
enum MapSize { card, header }

/// Tiles from the map's builder; the quiet card (coordinates and a drawn pin); or the quiet card with "Show the
/// map" on it, one tap from tiles (the reader).
enum MapCardMode { map, quiet, ask }

/// Why the card is quiet, said in a chip (`'local-only' | 'off'`).
enum QuietWhy { localOnly, off }

/// Draws the map's tiles in the box it is given, centred on `tag` at `zoom`, as a still picture: nothing on it
/// moves or answers a press. Calls `onLoaded` once the tiles are in (at least one of them: a failed tile is the
/// map's paper).
typedef MapTilesBuilder = Widget Function(BuildContext context, {required GeoTag tag, required int zoom, required VoidCallback onLoaded});

/// How long the card takes to leave, as the arrival's beat (`mapLeave`).
const Duration _leave = Duration(milliseconds: 300);
const Duration _arrive = Duration(milliseconds: 360);

/// A street for a fine tag; for a rough one a district, a step wider than the name is asked at, so its ring fits
/// the box.
int zoomOf(bool rough) => rough ? 11 : 15;

/// How wide a rough tag's ring is drawn, in pixels at its zoom (11): the half diagonal of the cell its two
/// decimals round to. A hundredth of a degree of longitude is 14.6 px at that zoom anywhere; of latitude, that
/// over the latitude's cosine (Web Mercator's stretch), so the ring's radius is 14 px in London, 10 at the equator
/// and more towards the poles.
int ringRadius(double lat) {
  final half = (0.01 / 360) * 256 * math.pow(2, zoomOf(true)) * 0.5;
  final cos = math.max(0.2, math.cos(lat * math.pi / 180));
  final across = math.sqrt(half * half + (half / cos) * (half / cos));
  return math.min(18, math.max(10, across)).round();
}

const Map<QuietWhy, String> _why = <QuietWhy, String>{QuietWhy.localOnly: 'Local only is on.', QuietWhy.off: 'Map off in Settings.'};

/// The map's mark for "Show the map", in the page's own strokes.
const String _mapMark = 'M3 6.5l6-2.5 6 2.5 6-2.5v13.5l-6 2.5-6-2.5-6 2.5zM9 4v13.5M15 6.5v13.5';

/// The mark, on both layers: the app's pin, its body filled with the paper so it reads over tiles, its tip on the
/// place; or, for a rough tag, a ring the size of the area its decimals leave open.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.rough, required this.radius, required this.ink, required this.paper});

  final bool rough;
  final int radius;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    if (rough) {
      final centre = size.center(Offset.zero);
      // fill="color-mix(in srgb, currentColor 10%, transparent)"
      canvas
        ..drawCircle(centre, radius.toDouble(), Paint()..color = ink.withValues(alpha: ink.a * 0.1))
        ..drawCircle(centre, radius.toDouble(), stroke);
      return;
    }
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(svgPath(placePath), Paint()..color = paper)
      ..drawPath(svgPath(placePath), stroke)
      ..drawCircle(const Offset(12, 10.5), 2.2, Paint()..color = ink)
      ..restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.rough != rough || old.radius != radius || old.ink != ink || old.paper != paper;
}

/// A faint dot grid: `radial-gradient(currentColor 0.6px, transparent 0.7px)` every 12px, at 0.45.
class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink.withValues(alpha: ink.a * 0.45);
    for (var y = 6.0; y < size.height + 1; y += 12) {
      for (var x = 6.0; x < size.width + 1; x += 12) {
        canvas.drawCircle(Offset(x, y), 0.65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.ink != ink;
}

class _MapMarkIcon extends CustomPainter {
  const _MapMarkIcon(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(
        svgPath(_mapMark),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_MapMarkIcon old) => old.ink != ink;
}

/// A CSS filter list as one colour matrix: `grayscale(1)`, then each step in turn.
List<double> _tileFilter(bool dark) {
  // grayscale(1): the luminance in every channel.
  const r = 0.2126, g = 0.7152, b = 0.0722;
  // Then a slope and an offset on each channel: contrast(c) is `c x + (0.5 - 0.5 c)`, brightness(k) is `k x`,
  // invert(1) is `1 - x`.
  double slope, offset;
  if (dark) {
    // invert(1) brightness(1.1)
    slope = -1.1;
    offset = 1.1;
  } else {
    // contrast(0.92) brightness(1.04)
    slope = 0.92 * 1.04;
    offset = (0.5 - 0.5 * 0.92) * 1.04;
  }
  final o = offset * 255;
  return <double>[r * slope, g * slope, b * slope, 0, o, r * slope, g * slope, b * slope, 0, o, r * slope, g * slope, b * slope, 0, o, 0, 0, 0, 1, 0];
}

class MapCard extends StatefulWidget {
  const MapCard({
    super.key,
    required this.tag,
    this.size = MapSize.card,
    required this.mode,
    this.quietWhy,
    this.dark,
    this.onShow,
    this.onOpen,
    this.arrive = false,
    this.leave = false,
    this.onLeft,
    this.where = true,
    this.tiles,
    this.scale = 1,
  });

  final GeoTag tag;

  /// The card, or a map note's header.
  final MapSize size;
  final MapCardMode mode;

  /// Why the card is quiet, said in a chip, or nothing (offline, a failed tile, a tile switch).
  final QuietWhy? quietWhy;

  /// The page's side, where the caller knows better than the theme the card is drawn in.
  final bool? dark;

  /// `ask` pressed: the caller switches mode to `map`.
  final VoidCallback? onShow;

  /// The card pressed, in any other mode: the caller opens the place on a map.
  final void Function(GeoTag tag)? onOpen;

  /// The card just appeared on an open note: it arrives on the kit's beat rather than popping in at full height.
  final bool arrive;

  /// The tag was just taken off: the card leaves on the same beat, then `onLeft` lets it go.
  final bool leave;
  final VoidCallback? onLeft;

  /// The place's chip at the top of the card: on by default. A card under a place line in the words leaves it
  /// off, because the line above it already says the name.
  final bool where;

  /// What draws the map, in `map` mode; the quiet card without it.
  final MapTilesBuilder? tiles;

  /// `--map-scale`: a template's card draws the box smaller.
  final double scale;

  @override
  State<MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<MapCard> with SingleTickerProviderStateMixin {
  bool _loaded = false;
  Timer? _leaving;
  late final AnimationController _beat = AnimationController(vsync: this, duration: _arrive, value: 1);

  @override
  void initState() {
    super.initState();
    if (widget.arrive && !widget.leave) _beat.forward(from: 0);
    if (widget.leave) _startLeaving();
  }

  @override
  void didUpdateWidget(MapCard old) {
    super.didUpdateWidget(old);
    // The map is made again for another place, another zoom or another mode, and has not loaded.
    if (old.mode != widget.mode || old.tag.lat != widget.tag.lat || old.tag.lon != widget.tag.lon || old.tag.rough != widget.tag.rough) _loaded = false;
    if (widget.leave && !old.leave) _startLeaving();
    if (!widget.leave && old.leave) {
      _leaving?.cancel();
      _beat.value = 1;
    }
  }

  /// Leaving: the card goes on its beat, and then is let go (at once, for a phone that asks for less motion).
  void _startLeaving() {
    final still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _leaving?.cancel();
    _leaving = Timer(still ? Duration.zero : _leave, () => widget.onLeft?.call());
    if (!still) _beat.animateBack(0, duration: _leave);
  }

  @override
  void dispose() {
    _leaving?.cancel();
    _beat.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.mode == MapCardMode.ask) {
      widget.onShow?.call();
    } else {
      widget.onOpen?.call(widget.tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tag = widget.tag;
    final dark = widget.dark ?? t.isDark;
    final mode = widget.mode;
    final label = tagLabel(tag);
    final mapped = mode == MapCardMode.map && widget.tiles != null;
    // OSM's data is credited where it is shown: the tiles, or the name it gave. The coordinates are the phone's.
    final credit = (mode == MapCardMode.map && _loaded) || tag.place != null;
    final asks = mode == MapCardMode.ask;
    final quietWhy = widget.quietWhy;
    final paper2 = t.color('app-paper-2');
    final space2 = t.space(2);
    final fade = t.duration('glacier-duration-normal');
    final ease = t.curve('glacier-ease-out');

    Widget mark({required bool over}) {
      // '.mark': { position: absolute; inset-block-start: var(--place-y); inset-inline-start: 50%;
      //   translate: -14px -27px; color: var(--app-ink-2) }   '.over': { color: var(--app-ink) }
      final r = ringRadius(tag.lat);
      final box = tag.rough ? 2.0 * r + 4 : 28.0;
      return _Placed(
        // '.card': { --place-y: calc(50% + 10px) }   '.card[data-rough]': { --place-y: 50% }
        down: tag.rough ? 0 : 10,
        shift: tag.rough ? Offset(-box / 2, -box / 2) : const Offset(-14, -27),
        child: CustomPaint(
          key: ValueKey<String>(over ? 'mark-over' : 'mark'),
          size: Size.square(box),
          painter: _MarkPainter(rough: tag.rough, radius: r, ink: t.color(over ? 'app-ink' : 'app-ink-2'), paper: t.color('app-paper')),
        ),
      );
    }

    final layers = <Widget>[
      // '.quiet': { position: absolute; inset: 0; color: var(--app-ink-3) }
      Positioned.fill(
        key: const ValueKey<String>('quiet'),
        child: ExcludeSemantics(
          child: CustomPaint(painter: _DotsPainter(t.color('app-ink-3'))),
        ),
      ),
      mark(over: false),
      if (mapped)
        // '.map': { position: absolute; inset: 0 0 -20px; opacity: 0; transition: opacity
        //   var(--glacier-duration-normal) var(--glacier-ease-out); background: var(--app-paper-2) }
        // '.card[data-rough] .map': { inset: 0 }   '.card[data-loaded] .map': { opacity: 1 }
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: tag.rough ? 0 : -20,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _loaded ? 1 : 0,
                duration: fade,
                curve: ease,
                child: ColoredBox(
                  color: paper2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      // '.map .leaflet-tile-pane': { filter: grayscale(1) contrast(0.92) brightness(1.04) }
                      // '.card[data-dark] .map .leaflet-tile-pane': { filter: grayscale(1) invert(1) brightness(1.1) }
                      ColorFiltered(
                        colorFilter: ColorFilter.matrix(_tileFilter(dark)),
                        child: widget.tiles!(
                          context,
                          tag: tag,
                          zoom: zoomOf(tag.rough),
                          onLoaded: () {
                            if (mounted && !_loaded) setState(() => _loaded = true);
                          },
                        ),
                      ),
                      // '.map::after': { content: ''; position: absolute; inset: 0; background: var(--app-paper-2);
                      //   opacity: 0.45 }
                      ColoredBox(color: paper2.withValues(alpha: paper2.a * 0.45)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      if (mode == MapCardMode.map)
        // '.over': { opacity: 0; transition: opacity ... }   '.card[data-loaded] .over': { opacity: 1 }
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(opacity: _loaded ? 1 : 0, duration: fade, curve: ease, child: Stack(children: <Widget>[mark(over: true)])),
          ),
        ),
      // '.where': { inset-block-start: var(--glacier-space-2); inset-inline-start: var(--glacier-space-2);
      //   color: var(--app-ink-2); font-variant-numeric: tabular-nums }
      if (widget.where)
        PositionedDirectional(
          top: space2,
          start: space2,
          end: space2,
          child: Align(alignment: AlignmentDirectional.topStart, heightFactor: 1, child: _Chip(label, name: 'chip-where', ink: t.color('app-ink-2'), tabular: true)),
        ),
      // '.why': { inset-block-end: var(--glacier-space-2); inset-inline-start: var(--glacier-space-2);
      //   color: var(--app-ink-3) }
      // '.credit': { inset-block-end: var(--glacier-space-2); inset-inline-end: var(--glacier-space-2);
      //   color: var(--app-ink-3) }   '.why + .credit, .show + .credit': { max-inline-size: 60% }
      Positioned(
        left: space2,
        right: space2,
        bottom: space2,
        child: _Foot(
          start: asks
              ? _Chip('Show the map', name: 'chip-show', ink: t.color('app-ink'), show: true)
              : (quietWhy != null && mode == MapCardMode.quiet ? _Chip(_why[quietWhy]!, name: 'chip-why', ink: t.color('app-ink-3')) : null),
          end: credit ? _Chip('© OpenStreetMap contributors', name: 'chip-credit', ink: t.color('app-ink-3')) : null,
        ),
      ),
    ];

    // '.card': { position: relative; isolation: isolate; overflow: hidden;
    //   block-size: calc(7.2rem * var(--map-scale, 1)); max-inline-size: 32rem;
    //   border-radius: var(--glacier-radius-lg); border: var(--glacier-hairline) solid var(--app-rule);
    //   background: var(--app-paper-2); color: var(--app-ink) }
    // '.tap': the whole card, over everything.
    final hairline = t.len('glacier-hairline');
    final radius = t.radius('lg');
    Widget card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: mapMaxWidth(context, widget.size)),
      child: SizedBox(
        key: const ValueKey<String>('card'),
        height: mapHeight(context, widget.size) * widget.scale,
        child: Semantics(
          button: true,
          label: asks ? 'Show the map' : 'Open $label on a map',
          onTap: widget.leave ? null : _press,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.leave ? null : _press,
            child: DecoratedBox(
              decoration: BoxDecoration(color: paper2, borderRadius: BorderRadius.circular(radius), border: Border.all(color: t.color('app-rule'), width: hairline)),
              child: Padding(
                padding: EdgeInsets.all(hairline),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(math.max(0, radius - hairline)),
                  child: DefaultTextStyle.merge(style: TextStyle(color: t.color('app-ink')), child: Stack(clipBehavior: Clip.hardEdge, children: layers)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // '.card[data-arrive]': { animation: mapArrive 360ms var(--glacier-ease-out) both }
    // '.card[data-leave]': { pointer-events: none; animation: mapLeave 300ms var(--glacier-ease-out) both }
    // '@keyframes mapArrive': { from: { block-size: 0; opacity: 0; transform: translateY(6px) } }
    // '@keyframes mapLeave': { to: { block-size: 0; margin-block: 0; border-block-width: 0; opacity: 0;
    //   transform: translateY(-6px) } }
    if (widget.arrive || widget.leave) {
      final curved = CurvedAnimation(parent: _beat, curve: ease);
      card = AnimatedBuilder(
        animation: curved,
        child: card,
        builder: (context, child) => IgnorePointer(
          ignoring: widget.leave,
          child: Opacity(
            opacity: curved.value.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, (1 - curved.value) * (widget.leave ? -6 : 6)),
              child: ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: curved.value.clamp(0, 1), child: child)),
            ),
          ),
        ),
      );
    }
    return card;
  }
}

/// How tall the map's box is: the card (7.2rem, 9.6rem from 600px wide) or the header (10rem, 16rem).
double mapHeight(BuildContext context, MapSize size) {
  final wide = MediaQuery.sizeOf(context).width >= 600;
  final rem = switch (size) {
    MapSize.header => wide ? 16.0 : 10.0,
    MapSize.card => wide ? 9.6 : 7.2,
  };
  return layoutUnit(context.tokens.lenOf('${rem}rem'));
}

/// The most the box is wide: a link card's width, or a reader's column for the header.
double mapMaxWidth(BuildContext context, MapSize size) => context.tokens.lenOf(size == MapSize.header ? '48rem' : '32rem');

/// A child set at the middle of the box across and `down` pixels below the middle of it, then moved by `shift`.
class _Placed extends StatelessWidget {
  const _Placed({required this.down, required this.shift, required this.child});

  final double down;
  final Offset shift;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: CustomSingleChildLayout(delegate: _PlacedDelegate(down, shift), child: child),
    ),
  );
}

class _PlacedDelegate extends SingleChildLayoutDelegate {
  const _PlacedDelegate(this.down, this.shift);

  final double down;
  final Offset shift;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(size.width / 2, size.height / 2 + down) + shift;

  @override
  bool shouldRelayout(_PlacedDelegate old) => old.down != down || old.shift != shift;
}

/// The chips at the foot: the left one at the start, the credit at the end, which is held to 60% of the card
/// when it shares the foot. The left one gives way when the card is narrow.
class _Foot extends StatelessWidget {
  const _Foot({this.start, this.end});

  final Widget? start;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    final space2 = context.tokens.space(2);
    final start = this.start, end = this.end;
    if (start == null) return end == null ? const SizedBox.shrink() : Align(alignment: AlignmentDirectional.bottomEnd, heightFactor: 1, child: end);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Percentages are of the card's padding box, which is this row and a space either side.
        final card = constraints.maxWidth + 2 * space2;
        // Each chip is set against its own corner: they may overlap on a narrow card, as on the page.
        return Stack(
          children: <Widget>[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[Flexible(child: start)]),
            if (end != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: card * 0.6), child: end),
              ),
          ],
        );
      },
    );
  }
}

/// A chip: glass at a corner, one line, never in the way of a tap.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.name, required this.ink, this.tabular = false, this.show = false});

  final String text;
  final String name;
  final Color ink;
  final bool tabular;

  /// The one thing to press on the reader's card, so it is drawn as the kit's small button is, with the map's
  /// mark.
  final bool show;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // '.chip': { position: absolute; max-inline-size: calc(100% - 2 * var(--glacier-space-2));
    //   padding: 2px var(--glacier-space-2); border-radius: var(--glacier-radius-sm);
    //   background: color-mix(in srgb, var(--app-paper) 82%, transparent); font-size: var(--glacier-font-size-xs);
    //   line-height: 1.4; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; pointer-events: none }
    final size = t.fontSize('xs');
    final base = t.textAt(size, color: ink);
    final style = tabular ? base.copyWith(fontFeatures: <FontFeature>[...?base.fontFeatures, const FontFeature.tabularFigures()]) : base;
    final words = InlineWords(text, style: style, lineHeight: size * 1.4, ellipsis: true);
    // '.show': { display: inline-flex; align-items: center; gap: var(--glacier-space-1);
    //   border: var(--glacier-hairline) solid var(--app-rule); background: var(--app-paper); color: var(--app-ink) }
    final hairline = show ? t.len('glacier-hairline') : 0.0;
    return IgnorePointer(
      child: DecoratedBox(
        key: ValueKey<String>(name),
        decoration: BoxDecoration(
          color: show ? t.color('app-paper') : t.colorOf('color-mix(in srgb, var(--app-paper) 82%, transparent)'),
          borderRadius: BorderRadius.circular(t.radius('sm')),
          border: show ? Border.all(color: t.color('app-rule'), width: hairline) : null,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2 + hairline, horizontal: t.space(2) + hairline),
          child: show
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CustomPaint(size: const Size.square(12), painter: _MapMarkIcon(ink)),
                    SizedBox(width: t.space(1)),
                    Flexible(child: words),
                  ],
                )
              : words,
        ),
      ),
    );
  }
}

/// The map's box with no map in it: the quiet layer alone, the card's own box and dot grid, so a box held for a
/// fix and the card that arrives in it are the same box and nothing moves. A picture: no button, nothing to
/// press, nothing read out, and nothing fetched.
class MapPicture extends StatelessWidget {
  const MapPicture({super.key, this.size = MapSize.card, this.pin = false, this.why, this.scale = 1});

  final MapSize size;

  /// A stand-in pin, where the card would put one: on a template's card, which shows a map it has no place for
  /// yet.
  final bool pin;

  /// Why the box has no map, said in its chip, or nothing while a fix is on its way.
  final String? why;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    final radius = t.radius('lg');
    final space2 = t.space(2);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mapMaxWidth(context, size)),
          child: SizedBox(
            key: const ValueKey<String>('card'),
            height: mapHeight(context, size) * scale,
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(radius), border: Border.all(color: t.color('app-rule'), width: hairline)),
              child: Padding(
                padding: EdgeInsets.all(hairline),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(math.max(0, radius - hairline)),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        key: const ValueKey<String>('quiet'),
                        child: CustomPaint(painter: _DotsPainter(t.color('app-ink-3'))),
                      ),
                      if (pin)
                        _Placed(
                          down: 10,
                          shift: const Offset(-14, -27),
                          child: CustomPaint(
                            key: const ValueKey<String>('mark'),
                            size: const Size.square(28),
                            painter: _MarkPainter(rough: false, radius: 0, ink: t.color('app-ink-2'), paper: t.color('app-paper')),
                          ),
                        ),
                      if (why != null && why!.isNotEmpty) Positioned(left: space2, right: space2, bottom: space2, child: _Foot(start: _Chip(why!, name: 'chip-why', ink: t.color('app-ink-3')))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
