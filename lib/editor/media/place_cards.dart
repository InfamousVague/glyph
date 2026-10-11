/// A place in the words, drawn (lib/core/place_refs.dart): the map card under a line that is only a link to a
/// `geo:` address, and the line folded to its name away from the caret. Ports `src/app/editor/placeCards.ts`.
///
///     [Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
///
/// The line keeps its Markdown, as a picture's line does (images.dart), and the card is a block widget under it,
/// so the caret and the saved note are exactly as written. Off the caret's line the `[` and the `](geo:…)` fold
/// away and only the name reads, as a long address reads short (links.dart); on the caret's line, in a note being
/// written, it is all there to edit. The card is the note's own map card (map_card.dart) with no place chip, since
/// the line above says the name, and a tap on it opens the maps app.
///
/// Where it may fetch is the caller's to say, read once: `live` on the note screen, which draws the map's tiles
/// where the map switch is on and Local only is off, and the quiet card with the reason otherwise; `ask` on a
/// shared page, which fetches nothing until the reader taps "Show the map"; and `off` everywhere else, a notebook
/// read straight through and a note drawn small included, whose promise is that nothing on it fetches. There the
/// line still reads as its name.
///
/// A place at the very top of a note, its first line or the one under its title (`topPlaceLine`), is drawn as the
/// note's header instead: the map across the column at a map note's height, since a place put first is what the
/// note is about (GLY-3).
///
/// What differs:
/// - What the page reached for itself is told through [placeCards]: the two switches (`switches`:
///   `preferences()`), what says they changed (`changed`: `onPreferences`), how a place is opened on a map
///   (`onOpen`: `openPlace`) and what draws the tiles (`tiles`: Leaflet on the page; see map_card.dart). `dark` is
///   read from the theme the card is drawn in unless said.
/// - The card's component was fetched lazily (`lazy`, `Suspense`) to keep Leaflet out of a shared page's chunk;
///   there are no chunks here.
/// - The theme's rules are drawn by the widget, each cited where it is drawn. Its `font-family`, `font-size` and
///   `line-height` (the app's own hand for the chips) are the chips' own in map_card.dart.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/place_refs.dart';
import '../editor.dart';
import '../view/blocks.dart' show ClassedBlockWidget;
import '../view/drawn_block.dart';
import '../view/line_facts.dart';
import '../view/lines.dart';
import 'images.dart' show gutterOf;
import 'map_card.dart';

/// Where a card may fetch: the note screen, a shared page, or nowhere (`'live' | 'ask' | 'off'`).
enum PlaceMode { live, ask, off }

/// How a card draws: MapCard's `mode`, and why it is quiet.
typedef PlaceLook = ({MapCardMode mode, QuietWhy? quietWhy});

/// How a card draws, from where it is and the switches.
PlaceLook placeLook(PlaceMode mode, {required bool localOnly, required bool mapTiles}) {
  if (mode == PlaceMode.ask) return (mode: MapCardMode.ask, quietWhy: null);
  if (localOnly) return (mode: MapCardMode.quiet, quietWhy: QuietWhy.localOnly);
  if (!mapTiles) return (mode: MapCardMode.quiet, quietWhy: QuietWhy.off);
  return (mode: MapCardMode.map, quietWhy: null);
}

/// The two switches a card reads: Local only, and the map.
typedef PlaceSwitches = ({bool localOnly, bool mapTiles});

/// What the cards are told by whoever makes the editor.
class PlaceSeams {
  const PlaceSeams({this.dark, this.switches, this.changed, this.onOpen, this.tiles});

  final bool Function()? dark;
  final PlaceSwitches Function()? switches;
  final Listenable? changed;
  final void Function(GeoTag tag)? onOpen;
  final MapTilesBuilder? tiles;
}

final Facet<PlaceSeams, PlaceSeams> _seams = Facet.define<PlaceSeams, PlaceSeams>(combine: (values) => values.isEmpty ? const PlaceSeams() : values.first);

/// The card, and the reader's "Show the map" turning it into a map: the only state a place card keeps.
class _PlaceMap extends StatefulWidget {
  const _PlaceMap({required this.tag, required this.look, required this.dark, required this.size, required this.seams});

  final GeoTag tag;
  final PlaceLook look;
  final bool? dark;
  final MapSize size;
  final PlaceSeams seams;

  @override
  State<_PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<_PlaceMap> {
  bool _asked = false;

  /// Another place in this card's place has not been asked for.
  @override
  void didUpdateWidget(_PlaceMap old) {
    super.didUpdateWidget(old);
    if (old.tag.lat != widget.tag.lat || old.tag.lon != widget.tag.lon || !identical(old.seams, widget.seams)) _asked = false;
  }

  @override
  Widget build(BuildContext context) => MapCard(
    tag: widget.tag,
    mode: widget.look.mode == MapCardMode.ask && _asked ? MapCardMode.map : widget.look.mode,
    quietWhy: widget.look.quietWhy,
    dark: widget.dark,
    size: widget.size,
    where: false,
    onShow: () => setState(() => _asked = true),
    onOpen: widget.seams.onOpen,
    tiles: widget.seams.tiles,
  );
}

/// The map card under a place's line.
class PlaceWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const PlaceWidget(this.tag, this.look, this.dark, [this.size = MapSize.card]);

  final GeoTag tag;
  final PlaceLook look;
  final bool? dark;

  /// The card, or the note's header for a place at its very top.
  final MapSize size;

  @override
  String get className => 'cm-placeCard';

  @override
  bool eq(PlaceWidget other) => other.tag == tag && other.look.mode == look.mode && other.look.quietWhy == look.quietWhy && other.dark == dark && other.size == size;

  /// The card's own height (7.2rem, 9.6rem from 600px wide), or the header's (10rem, 16rem), and the room around
  /// it, so the note does not jump as it draws.
  @override
  double get estimatedHeight {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return size == MapSize.header ? 170 : 110;
    const rem = 16.0;
    final wide = views.first.physicalSize.width / views.first.devicePixelRatio >= 600;
    return (size == MapSize.header ? (wide ? 16 : 10) : (wide ? 9.6 : 7.2)) * rem + 0.85 * rem;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final seams = EditorViewScope.maybeOf(context)?.state.facet(_seams) ?? const PlaceSeams();
    final gutter = gutterOf(context);
    final em = t.lenOf('1rem');
    // '.cm-placeCard': { fontFamily: 'var(--glacier-font-sans, system-ui)', fontSize: '1rem', lineHeight: '1.5',
    //   paddingBlock: '0.25em 0.6em', paddingInline: 'calc(var(--app-safe-left, 0px) + var(--app-gutter, 0px))
    //   calc(var(--app-safe-right, 0px) + var(--app-gutter, 0px))' }
    return Padding(
      key: const ValueKey<String>('cm-placeCard'),
      padding: EdgeInsets.only(top: em * 0.25, bottom: em * 0.6, left: t.lenOf('var(--app-safe-left, 0px)') + gutter, right: t.lenOf('var(--app-safe-right, 0px)') + gutter),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        // '.cm-placeCardBox': { minBlockSize: '7.2rem', maxInlineSize: '32rem' }
        // '.cm-placeCard[data-size="header"] .cm-placeCardBox': { minBlockSize: '10rem', maxInlineSize: '48rem' }
        // '@media (min-width: 600px)': the box's least heights are 9.6rem and 16rem.
        child: ConstrainedBox(
          key: const ValueKey<String>('cm-placeCardBox'),
          constraints: BoxConstraints(minHeight: mapHeight(context, size), maxWidth: mapMaxWidth(context, size)),
          child: _PlaceMap(tag: tag, look: look, dark: dark, size: size, seams: seams),
        ),
      ),
    );
  }
}

/// Local only, the map switch or the page's side changed: every card is drawn again as it now should be.
final StateEffectType<Null> refreshPlaceCards = StateEffect.define<Null>();

DecorationSet _cardsOf(EditorState state, PlaceMode mode) {
  final builder = RangeSetBuilder<Decoration>();
  // The lines that are places are the tree's own keeping: a keystroke reads the lines it changed, not the note.
  final places = placeFacts.of(state.doc);
  if (places.isEmpty) return builder.finish();
  final seams = state.facet(_seams);
  final switches = seams.switches?.call() ?? (localOnly: false, mapTiles: true);
  final look = placeLook(mode, localOnly: switches.localOnly, mapTiles: switches.mapTiles);
  final dark = seams.dark?.call();
  final fences = DocFences.of(state.doc);
  // The note's first lines, as far as a place at its top could be: front matter can run to 40. Read only where a
  // place is among them.
  final reach = state.doc.lines < 48 ? state.doc.lines : 48;
  int? top;
  var topRead = false;
  for (final line in places) {
    if (fences.covers(line.number)) continue;
    if (!topRead && line.number <= reach) {
      top = topPlaceLine(state.doc.sliceString(0, state.doc.line(reach).to).split('\n'));
      topRead = true;
    }
    builder.add(line.to, line.to, Decoration.widget(widget: PlaceWidget(line.fact.tag, look, dark, topRead && line.number == top ? MapSize.header : MapSize.card), block: true, side: 1));
  }
  return builder.finish();
}

/// A block widget's height has to be known before layout, so the cards come from a field, as pictures do.
final Map<PlaceMode, StateField<DecorationSet>> _cardFields = <PlaceMode, StateField<DecorationSet>>{
  for (final mode in const <PlaceMode>[PlaceMode.live, PlaceMode.ask])
    mode: StateField.define<DecorationSet>(
      create: (state) => _cardsOf(state, mode),
      update: (value, tr) {
        if (tr.docChanged || tr.reconfigured || tr.effects.any((effect) => effect.isOf(refreshPlaceCards))) return _cardsOf(tr.state, mode);
        return value;
      },
      provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
    ),
};

/// A switch changed: the cards look again.
class _Listen extends PluginValue {
  _Listen(this.view) {
    _hear(view.state.facet(_seams).changed);
  }

  final EditorViewLike view;
  Listenable? _heard;
  bool _gone = false;

  void _hear(Listenable? changed) {
    if (identical(changed, _heard)) return;
    _heard?.removeListener(_onChanged);
    _heard = changed;
    changed?.addListener(_onChanged);
  }

  void _onChanged() => scheduleMicrotask(() {
    if (!_gone) view.dispatch(TransactionSpec(effects: refreshPlaceCards.of(null)));
  });

  @override
  void update(ViewUpdate update) => _hear(update.state.facet(_seams).changed);

  @override
  void destroy() {
    _gone = true;
    _heard?.removeListener(_onChanged);
  }
}

final ViewPlugin<_Listen> _listen = ViewPlugin.define<_Listen>(_Listen.new);

final RegExp _link = RegExp(r'\[([^\[\]\n]*)\]\(geo:[^)\s]*\)', caseSensitive: false);

/// The `[` and the `](geo:…)` of a place line, as ranges of the document.
List<({int from, int to})> _foldsOf(int from, String text, String words) {
  final link = _link.firstMatch(text);
  if (link == null || (link.group(1) ?? '').trim() != words) return const <({int from, int to})>[];
  final open = from + link.start;
  final close = open + 1 + (link.group(1)?.length ?? 0);
  return <({int from, int to})>[(from: open, to: open + 1), (from: close, to: open + link.group(0)!.length)];
}

final Decoration _hidden = Decoration.replace();

DecorationSet _foldAll(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  final state = view.state;
  final editable = state.facet(EditorViewLike.editable);
  // The lines the selection touches show their places whole, while the note is being written (links.dart).
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  final doc = state.doc;
  final fences = DocFences.of(doc);
  for (final range in view.visibleRanges) {
    // The places among the lines on screen, from what the tree keeps of them.
    for (final line in placeFacts.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      // A place's line in fenced code is the code's words, as the cards take it.
      if (active.contains(line.number) || fences.covers(line.number)) continue;
      for (final fold in _foldsOf(line.from, line.text, line.fact.words)) {
        builder.add(fold.from, fold.to, _hidden);
      }
    }
  }
  return builder.finish();
}

/// The place lines folded to their names off the caret, looked at again whenever what they show may have moved.
class _Folds extends PluginValue {
  _Folds(EditorViewLike view) : decorations = _foldAll(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    // While an IME composes, a line must not be replaced (glyph_lines.dart).
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) decorations = _foldAll(update.view);
  }
}

final ViewPlugin<_Folds> _folds = ViewPlugin.define<_Folds>(_Folds.new, decorations: (plugin) => plugin.decorations);

/// Places in the words: cards under their lines as `mode` says, and the lines folded to their names. Read once,
/// when the editor is made; `dark` and `switches` are asked whenever the cards are drawn.
Extension placeCards(
  PlaceMode mode, {
  bool Function()? dark,
  PlaceSwitches Function()? switches,
  Listenable? changed,
  void Function(GeoTag tag)? onOpen,
  MapTilesBuilder? tiles,
}) {
  if (mode == PlaceMode.off) return _folds;
  return Extension.list(<Extension>[_seams.of(PlaceSeams(dark: dark, switches: switches, changed: changed, onOpen: onOpen, tiles: tiles)), _cardFields[mode]!, _listen, _folds]);
}
