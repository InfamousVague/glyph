/// The smoke bench's plain parts (lib/diag/wisp_bench.dart): what it can draw, the limits of a run, the floor that
/// licenses a table, and how it says what it found. A port of `src/app/diag/wispBenchRun.ts`.
///
/// What differs:
/// - [wearingOf] read the element's attributes and its computed `filter`. Here a view's smoke is the strips it is
///   drawn through (lib/art/wisp_strips.dart `RenderWispStrips.strips`), so that is what is read: still what the
///   surface wears, not what was asked for. A strip names its drawing by its kind, so nothing is put in brackets
///   after it, where the page added the filter's own text.
/// - [whereItRuns] is given what the page read from its globals: the version, the platform, what draws, the window.
/// - [BenchRow] is the page's `Row`, a name Flutter's widgets have.
/// - The app-wide override is the same key, `glyph-wisp-draw` ([wispDrawKey]), read by [wispDrawAsked] and applied
///   to lib/art/wisp_settings.dart by [useWispDrawAsked], which whoever starts the app calls once after the device's
///   memory is in place; the page's art/wispMask.ts read the key itself as it loaded.
library;

import '../art/art.dart';
import '../core/stored.dart';
import 'frame_clock.dart';

/// What a surface can be told to wear (`Draw`): the filter, the mask, or no smoke.
enum BenchDraw {
  filter('filter', 'Filter'),
  mask('mask', 'Mask'),
  none('none', 'No smoke');

  const BenchDraw(this.value, this.label);
  final String value, label;

  /// The app's own name for it; null for no smoke, which is not a thing the app can be told to draw.
  WispDraw? get wisp => switch (this) { BenchDraw.filter => WispDraw.filter, BenchDraw.mask => WispDraw.mask, BenchDraw.none => null };
}

/// The choices, in the control's order (`DRAWS`).
const List<BenchDraw> benchDraws = BenchDraw.values;

/// How a cell drives its surface (`Condition`).
enum BenchCondition {
  idle('idle', 'At rest'),
  repaint('repaint', 'One repaint a frame'),
  scroll('scroll', 'Scrolling');

  const BenchCondition(this.value, this.label);
  final String value, label;
}

/// `CONDITIONS`, in the order a surface is driven.
const List<BenchCondition> benchConditions = BenchCondition.values;

/// The default run (`QUICK_LIMITS`): enough frames for a median at 60Hz, and a wall that ends a cell whose frames
/// are seconds.
const CellLimits quickLimits = CellLimits(frames: 180, wallMs: 8000);

/// A long run (`LONG_LIMITS`), for cells whose frames are seconds, so they get more than a couple.
const CellLimits longLimits = CellLimits(frames: 180, wallMs: 30000);

/// The floor (`FLOOR_MS`): what a frame of the page WITHOUT smoke may take before the whole table is thrown away. A
/// display draws at 60Hz (16.7ms) or 120Hz (8.3ms); a page with nothing on it that cannot hold a frame under this is
/// on a machine that is busy, and nothing measured beside it is a measurement of the smoke.
const double floorMs = 25;

/// Where the surface sits while it is measured (`SCROLLED_TO`): off its top, so both bands are on.
const double scrolledTo = 400;

/// One cell of the table (`Row`).
class BenchRow {
  const BenchRow({required this.draw, required this.condition, required this.wearing, required this.reading});
  final BenchDraw draw;
  final BenchCondition condition;

  /// What the surface was wearing when the cell ran, read from the view, not assumed from the choice.
  final String wearing;
  final Reading reading;
}

/// Whether the table can be read at all, from its no-smoke rows; and the words for it either way (`floorVerdict`).
({bool ok, String words})? floorVerdict(List<BenchRow> rows) {
  final bare = rows.where((row) => row.draw == BenchDraw.none && row.condition != BenchCondition.repaint);
  if (bare.isEmpty) return null;
  final worst = bare.map((row) => row.reading.median).reduce((a, b) => a > b ? a : b);
  if (worst > floorMs) {
    return (
      ok: false,
      words: 'The page without smoke could not hold a frame (median ${ms(worst)}ms): this machine was busy, and nothing here is a measurement of the smoke. Run it again when the machine is quiet.',
    );
  }
  return (ok: true, words: 'The page without smoke held its frames (median ${ms(worst)}ms), so the rest can be read against it.');
}

String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// What is being measured on, for the top of the table (`whereItRuns`).
String whereItRuns({required String version, required String platform, required String engine, required double width, required double height, required double ratio}) =>
    'Ghost.md $version · $platform · $engine · ${_n(width)}x${_n(height)} @${_n(ratio)}';

/// What a view is wearing right now, in the page's words (`wearingOf`): `nothing`, or the drawing and its ends,
/// `filter: top + foot`. [strips] are the view's own (see the header); a plain fade, which is what reduced motion
/// leaves of the filter, reads as `fade`.
String wearingOf(Iterable<WispStrip> strips) {
  var top = false, foot = false;
  String? drawn;
  for (final strip in strips) {
    final String kind;
    final bool atFoot;
    switch (strip) {
      case WispSmokeStrip():
        kind = 'filter';
        atFoot = strip.smoke.lipA == null;
      case WispMaskStrip():
        kind = 'mask';
        atFoot = strip.rect.top > 0;
      case WispFadeStrip():
        kind = 'fade';
        atFoot = strip.rect.top > 0;
      default:
        continue;
    }
    drawn ??= kind;
    if (atFoot) {
      foot = true;
    } else {
      top = true;
    }
  }
  if (drawn == null) return 'nothing';
  return '$drawn: ${[if (top) 'top', if (foot) 'foot'].join(' + ')}';
}

/// The table as text, for pasting to whoever is not looking at the screen (`reportText`).
String reportText(String where, List<BenchRow> rows) {
  final head = ['draw', 'condition', 'wearing', 'n', 'median', 'p90', 'worst'].join('\t');
  final lines = [
    for (final row in rows) [row.draw.value, row.condition.value, row.wearing, '${row.reading.n}', ms(row.reading.median), ms(row.reading.p90), ms(row.reading.worst)].join('\t'),
  ];
  final verdict = floorVerdict(rows);
  return [where, if (verdict != null) verdict.words, head, ...lines].join('\n');
}

/// The key the whole app's drawing is asked for under (art/wispMask.ts `WISP_DRAW_KEY`). A reset spares it.
const String wispDrawKey = 'glyph-wisp-draw';

/// What the whole app is told to draw from its next start, if anything.
WispDraw? wispDrawAsked([Stored? kept]) => switch ((kept ?? stored).readText(wispDrawKey)) { 'filter' => WispDraw.filter, 'mask' => WispDraw.mask, _ => null };

/// Tells the whole app which to draw from its next start; null puts back its default.
void askWispDraw(WispDraw? which, [Stored? kept]) => (kept ?? stored).writeText(wispDrawKey, which?.name);

/// Puts what was asked for in place (lib/art/wisp_settings.dart): once, as the app starts.
void useWispDrawAsked([Stored? kept]) => WispSettings.instance.draw = wispDrawAsked(kept);
