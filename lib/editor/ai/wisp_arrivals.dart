/// Words arriving in the editor from smoke, and leaving into it: the Wisp treatment (`lib/art/wisp_text.dart`) for
/// text the recorder writes into a note as it is understood and rewritten. Ports `src/app/editor/wispArrivals.ts`.
///
/// Matt: text should "appear and disappear with the Wisp effect as it's understood and rewritten". The recorder
/// dispatches its changes as ordinary transactions with the [wisp] annotation; this extension does the rest:
///
/// - Every letter a `heard` change inserts arrives out of smoke, one after another at a hand's pace even when a
///   whole phrase lands at once.
/// - A `rewrite` change is diffed against the text it replaces, so a pending phrase firming up ("buy mil" to "buy
///   milk") moves one letter, and the letters that really went are shown leaving, bending and thinning where they
///   were.
/// - Only the newest letters are in motion, capped at a pool of filters, so a long note costs nothing but its last
///   few words.
/// - With `typing` on, what the person deletes leaves into smoke too (Matt: "I want the text to fade in and delete
///   away with the wisp effect as I type"). What they type or paste appears at once, since a letter drawn out of
///   smoke is not yet there under the finger that typed it (Matt: "Don't ghostly fade the text in I want text input
///   to be instantaious").
///
/// WispText owns its letters; a note's are the view's, so here the motion is all in the filter and none in the
/// lines: each moving letter is a mark decoration carrying `filter: url(#one-of-the-pool)`, and the filter itself,
/// with the bend, the blur, the lift and the fade, is what a frame moves, kept beside the editor
/// (`wisp_filters.dart`). The view may lay a mark's run out again whenever its neighbours change; nothing is lost
/// when it does. With reduced motion asked for, nothing here happens at all.
///
/// What is in motion, and when, is decided in `lib/editor/marks/wisp_motion.dart`; this module is the drawing - the
/// pool of filters, the frame loop - and the extension that puts the two together.
///
/// What differs:
/// - The page moved an SVG filter per word, which the browser drew the word's `<span>` through. Here a filter is a
///   [Smoke] of numbers, and a moving word is drawn letter by letter through the wisp's shader by the letters' own
///   painter (`wisp_filters.dart` [WispLetter], on `lib/editor/marks/run_paint.dart`'s `LetterLayer`): the same
///   shader the departures and the recorder's page use, set with this file's numbers each frame. So the mark that
///   wears a filter (`cm-wispCh`) is laid on each letter of the word, spaces aside, and not once on the word, and
///   each says its letter (`data-text`): a painter is told a run's rectangles and nothing else, and a run is cut
///   wherever another mark begins. A waiting word's mark (`cm-wispWait`) is still the word's. Both are given at the
///   highest precedence, inside every other mark, so the run's painter is theirs.
/// - `fit` is not ported: the filter's region is the wisp's own for a letter (`wisp_filters.dart`), which is the
///   page's region for a single letter, and there is no wide region round a long piece to save.
/// - The ghosts of what left (`Ghost`, `.cm-wispGonePlace`, `.cm-wispGone`, `lookAt`, `pinGhosts`) are drawn by
///   `wispDepartures` (`lib/editor/marks/wisp_motion.dart`), which this extension brings: a ghost there is a widget
///   with its own clock that settles itself. So a ghost takes no filter of this pool, and the pool's eviction (a
///   deletion's ghost taking the oldest letter's filter, `evicted`) has nothing to do and is not ported: with the
///   pool full an arriving word waits, as on the page. The ghosts are given at the highest precedence, which is
///   what sets one in the look its text had (`lookAt`'s classes): a widget inside the marks round it.
/// - A settled word's filter is freed before the pass that draws the marks asks for any, where the page freed it
///   after. On the page a word waiting on a filter took one a settling later; if a hitch settled every word of a
///   full pool in one frame there was no later settling, and the words still waiting never started. Here a waiting
///   word takes the freed filter in the same pass.
/// - A frame in which a waiting word's turn has come goes on to move and settle the others, where the page's
///   returned after drawing the marks again. With frames further apart than the words' turns (a word comes every
///   24 to 62 ms) the page's loop only ever drew marks until the whole phrase had started, and its letters stood
///   clear until then.
/// - `requestAnimationFrame` is a `Ticker`, and `performance.now()` is [wispNow], which a test holds.
/// - Setting a filter's attribute repaints nothing by itself: each frame asks the lines that hold a marked letter to
///   paint again ([repaintWearing]).
/// - Reduced motion and the chosen pace are the facets `wispStill` and `wispPace` of `wisp_motion.dart`, which
///   whoever makes the editor fills; this extension sets neither.
/// - A word the view draws as something else (a to-do's box, a link folded to its label) has no run of letters to
///   paint, so it simply appears; its turn and its settling are counted all the same.
/// - A letter inside a mark that paints (a highlight's wash, an underline) is drawn without that paint until it
///   settles: a run has one painter, its innermost mark's.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../../art/wisp_text.dart' show wispLetterFrequency, wispSlotSeed;
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart' show baseTheme;
import '../marks/run_paint.dart';
import '../marks/wisp_motion.dart';
import 'wisp_filters.dart';

// What the recorder and the AI write with (capture/ui/live_page.dart, ai/), kept here for them.
export '../marks/wisp_motion.dart' show commonEnds, wisp;

/// The filters in the pool: at most this many words in motion at once, the rest waiting their turn.
const int poolMax = 32;

/// How far a letter is bent, how soft it is and how far it lifts, at the far end of its arc.
const double _bend = 34;
const double _soft = 5;
const double _lift = 4;

/// How a tapped box's letter moves (`- [x]`, `- ( )`): a gentle throw, and no lift at all.
///
/// The full bend throws a glyph's pixels up to seventeen pixels either way, and an arriving letter starts four
/// pixels low and rises into place. Across a word both read as smoke; on the one letter between two brackets that
/// stay put, they are the whole letter moving - sideways out of its box (Matt: "the x button still slides to the
/// left"), then up into it (Matt: "x button shifts down slightly when changing the status of a Todo checkbox").
/// A box's letter simply thickens and fades where it stands. Typing keeps both: its letters arrive among others,
/// with nothing fixed beside them to move against.
const double _boxBend = 8;
const double _boxLift = 0;

/// A filter at `t` of its arc, 0 to 1: what `shape` writes into a slot.
///
/// Arriving: the bend is over by three quarters of the way and the blur a little later, so the last frames near
/// zero, where a half pixel of displacement shimmers on thin strokes, are not drawn; the letter fades in over the
/// first third and lifts into place. Leaving: the same curves backwards, thinning as it goes.
///
/// The numbers are rounded as the page writes them into its attributes.
({double scale, double stdDeviation, double dy, double slope}) shapeAt(double t, {bool leaving = false, bool box = false}) {
  final p = leaving ? 1 - t : t;
  final spread = math.max(0.0, 1 - p / 0.72);
  final soft = math.max(0.0, 1 - p / 0.9);
  final alpha = leaving ? 1 - t : math.min(1.0, t / 0.3);
  final bend = box ? _boxBend : _bend;
  final rise = box ? _boxLift : _lift;
  final lift = leaving ? -rise * 1.2 * t : rise * (1 - math.min(1.0, t / 0.5));
  double fixed(double value, int digits) => double.parse(value.toStringAsFixed(digits));
  return (scale: fixed(bend * spread * spread, 2), stdDeviation: fixed(_soft * soft * soft, 2), dy: fixed(lift, 2), slope: fixed(alpha, 3));
}

/// One filter of the pool, and whether a word is wearing it.
class _Slot {
  _Slot(this.smoke);

  final Smoke smoke;
  bool busy = true;

  String get id => smoke.id;
}

int _instances = 0;

/// The drawing: a filter for each word in motion, the marks that carry them, and the frame loop.
class WispArrivalsPlugin extends PluginValue {
  WispArrivalsPlugin(this.view) {
    _instances += 1;
    prefix = 'wispcm-$_instances';
    _redraw();
  }

  final EditorViewLike view;

  /// What the editor's filters are named by: `wispcm-<n>-<slot>`.
  late final String prefix;

  DecorationSet decorations = Decoration.none;
  final List<_Slot> _pool = <_Slot>[];
  final Map<int, _Slot> _slots = <int, _Slot>{};
  Ticker? _frame;
  bool _gone = false;

  /// The marks, kept: one for each letter a filter is worn by, and one for a word that waits.
  final Map<String, Decoration> _marks = <String, Decoration>{};
  static final Decoration _wait = Decoration.mark(className: 'cm-wispWait');

  @override
  void update(ViewUpdate update) {
    if (!update.docChanged && identical(moving(update.startState), moving(update.state))) return;
    _redraw();
  }

  @override
  void destroy() {
    _gone = true;
    _frame?.dispose();
    _frame = null;
    for (final slot in _pool) {
      removeFilter(slot.smoke);
    }
  }

  Decoration _letter(String id, String? ripple, String text) => _marks['$id|$ripple|$text'] ??= Decoration.mark(
    className: 'cm-wispCh',
    attributes: <String, String>{'style': 'filter:url(#$id)', 'data-text': text, 'data-ripple': ?ripple},
  );

  /// A filter for each thing in motion, kept while it moves; the marks that carry them. A letter whose turn hasn't
  /// come is only hidden, and takes no filter until it has: a long phrase then types across at its pace with the
  /// pool holding just the letters mid-arc, where it used to fill on the first line and settle the rest at once
  /// (Matt: "it still animates one line or so and then rapidly finishes").
  void _redraw() {
    final state = view.state;
    final current = moving(state);
    final now = wispNow();
    final alive = <int>{};
    final ranges = <Range<Decoration>>[];
    // The stretches the voice ripples through, each letter of which wears the ripple's filter over its own.
    final rippled = <({int from, int to, String id})>[for (final worn in state.facet(rippleWorn)) ...worn(state)];
    _nextDue = double.infinity;
    // The filters of what has settled are free again, before any is asked for: a word that was waiting on one takes
    // it in this same pass.
    for (final m in current) {
      if (m.gone.isEmpty) alive.add(m.id);
    }
    for (final id in _slots.keys.toList()) {
      if (!alive.contains(id)) {
        _slots.remove(id)!.busy = false;
        _starts.remove(id);
      }
    }
    var arriving = false;
    for (final m in current) {
      // What left is the departures' to draw (`wispDepartures`).
      if (m.gone.isNotEmpty) continue;
      arriving = true;
      if (m.at > now) {
        _nextDue = math.min(_nextDue, m.at);
        if (m.to > m.from) ranges.add(_wait.range(m.from, m.to));
        continue;
      }
      var slot = _slots[m.id];
      if (slot == null) {
        // A word never takes a filter from one still moving: with none free it waits its turn, unseen, and starts
        // when one settles. So a long phrase keeps arriving at the pace the phone can draw, instead of the rest
        // being set all at once to make room.
        final found = _slot();
        if (found == null) {
          // It waits, and nothing here asks for another look. When one settles, the `settle` it dispatches redraws
          // through the editor's own update, and this word takes the filter that was freed.
          //
          // It used to set `nextDue = now` to look again next frame, and that was a livelock: `tick` sees
          // `now >= nextDue` every frame, redraws and returns before the part of it that settles letters - and
          // settling is the only thing that frees a filter. So past 32 letters in motion none ever finished: 32
          // stayed mid-blur for good while the frame loop ran on at 60 a second. Measured typing at machine speed:
          // 20 and 40 letters settled, 60 and 90 froze at exactly 32. It only ever ran with the pool full, so
          // typing under 32 letters behaves exactly as it did. A paragraph arriving at once - pasted, or from
          // another device - is the case it broke.
          if (m.to > m.from) ranges.add(_wait.range(m.from, m.to));
          continue;
        }
        slot = found;
        _slots[m.id] = slot;
        _starts[m.id] = math.max(m.at, now);
        // Not yet on screen until its moment: fully bent, blurred and clear.
        _shape(slot, 0, m.box);
      }
      // The word's letters, spaces aside, each a character whole however many code units it is.
      var pos = m.from;
      for (final ch in state.doc.sliceString(m.from, m.to).characters) {
        if (ch.trim().isNotEmpty) {
          String? ripple;
          for (final stretch in rippled) {
            if (stretch.from <= pos && pos < stretch.to) ripple = stretch.id;
          }
          ranges.add(_letter(slot.id, ripple, ch).range(pos, pos + ch.length));
        }
        pos += ch.length;
      }
    }
    decorations = ranges.isEmpty ? Decoration.none : Decoration.set(ranges, true);
    if (arriving && !_gone) {
      _frame ??= Ticker(_tick);
      if (!_frame!.isActive) _frame!.start();
    }
  }

  /// When the next waiting letter's turn comes, and the marks are drawn again with it moving.
  double _nextDue = double.infinity;

  /// When each word with a filter really began: its turn, or later if it had to wait for a filter.
  final Map<int, double> _starts = <int, double>{};

  /// One frame: every moving thing's filter set for its moment; the ones past the end handed back to settle.
  void _tick(Duration _) {
    if (_gone) return;
    final now = wispNow();
    if (now >= _nextDue) {
      // Its filter is set and its mark swapped in the same frame, so nothing shows plain in between; the empty
      // transaction is what makes the editor read the marks again.
      _redraw();
      view.dispatch(const TransactionSpec());
      if (_gone) return;
    }
    final done = <int>[];
    for (final m in moving(view.state)) {
      final slot = _slots[m.id];
      if (slot == null) continue;
      final t = (now - (_starts[m.id] ?? m.at)) / m.dur;
      if (t >= 1) {
        done.add(m.id);
        continue;
      }
      _shape(slot, math.max(0.0, t), m.box);
    }
    if (done.isNotEmpty) {
      view.dispatch(TransactionSpec(effects: settle.of(done)));
      return;
    }
    repaintWearing(view);
    if (_slots.isEmpty && _nextDue == double.infinity) _frame?.stop();
  }

  /// A slot's filter at `t` of an arriving word's arc ([shapeAt]).
  void _shape(_Slot slot, double t, bool box) {
    final shape = shapeAt(t, box: box);
    slot.smoke
      ..scale = shape.scale
      ..stdDeviation = shape.stdDeviation
      ..dy = shape.dy
      ..slope = shape.slope;
  }

  /// A free filter, or a new one while the pool has room.
  _Slot? _slot() {
    for (final free in _pool) {
      if (!free.busy) {
        free.busy = true;
        return free;
      }
    }
    if (_pool.length >= poolMax) return null;
    final i = _pool.length;
    final slot = _Slot(smokeFilter(id: '$prefix-$i', frequency: wispLetterFrequency, seed: wispSlotSeed(i), bend: 0, soft: 0, shown: 1));
    _pool.add(slot);
    return slot;
  }
}

/// The plugin, for whoever asks an editor what it is drawing (`view.plugin(wispPlugin)`).
final ViewPlugin<WispArrivalsPlugin> wispPlugin = ViewPlugin.define<WispArrivalsPlugin>(
  WispArrivalsPlugin.new,
  // The letters' marks inside every other, so a letter's painter is the one its run carries.
  provide: (plugin) => Prec.highest(EditorViewLike.decorations.of((EditorViewLike view) => view.plugin(plugin)?.decorations ?? Decoration.none)),
);

// Plain inline spans: a letter box of its own (inline-block, as WispText's letters are) would change the line's
// kerning and wrapping, and the text under the filter must sit exactly where it does without it.
final LookSheet _wispTheme = LookSheet('editor/wispArrivals.ts', <LookRule>[
  // '.cm-wispCh': {}, with its `filter: url(#id)`: the letter through its filter, in place of the paragraph's.
  LookRule(
    'cm-wispCh',
    null,
    classes: 2,
    box: (p, e) {
      final attrs = p.element?.attrs ?? const <String, String>{};
      p.painter = MarkPaint.add(p.painter, WispLetter(attrs['data-text'] ?? '', filterIdOf(attrs), attrs['data-ripple']));
    },
  ),
  // Not its turn yet: there, so the line doesn't move, but unseen.
  // '.cm-wispWait': { opacity: '0' }
  LookRule('cm-wispWait', null, classes: 2, box: (p, e) => p.painter = MarkPaint.add(p.painter, const WispUnseen())),
  // '.cm-wispGonePlace': { position: 'relative', display: 'inline' } and '.cm-wispGone': { position: 'absolute',
  //   left: '0', top: '0', textIndent: '0', whiteSpace: 'pre', pointerEvents: 'none', userSelect: 'none' } are the
  //   departures' ghost (`lib/editor/marks/wisp_motion.dart`): a widget of no size, drawn from the point the text
  //   left.
]);

final Extension _themed = baseTheme(_wispTheme);

/// Text arriving from and leaving into smoke: transactions carrying the [wisp] annotation, and with `typing`, the
/// person's own.
Extension wispArrivals({bool typing = false}) => Extension.list(<Extension>[
  // The field, the switch and the ghosts of what left. At the highest precedence, so a ghost stands inside every
  // mark round the point its text left and is set in their look (`lookAt`): at its own, a widget of the line, it
  // took the note's prose face and plain ink whatever the letters had been.
  Prec.highest(wispDepartures(typing_: typing)),
  wispPlugin,
  _themed,
]);
