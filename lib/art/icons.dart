import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'icon_wash.dart';
import 'svg_path.dart';

/// One of the app's own icons (art/Icons.tsx `icon`): its line on the 24 grid, and under it the wash on its body
/// when it has one. The body is its own path, the closed part of the drawing alone, so the wash never lands on a
/// handle, a needle or a tick; where the body has a hole in it it is filled even-odd, and the hole stays clear.
@immutable
class DrawnIcon {
  const DrawnIcon(this.d, [this.body]);
  final String d;
  final String? body;
}

/// A cog: eight square-shouldered teeth round a ring, with the hole in the middle. Worked out once from its radii
/// rather than typed in, so the teeth are even.
final String _cog = () {
  const teeth = 8;
  const step = math.pi * 2 / teeth;
  const outer = 10.0, inner = 7.6;
  final points = <String>[];
  for (var i = 0; i < teeth; i++) {
    final a = i * step;
    for (final (offset, r) in const [(-0.27, inner), (-0.15, outer), (0.15, outer), (0.27, inner)]) {
      final angle = a + offset * step;
      points.add('${(12 + r * math.cos(angle)).toStringAsFixed(2)} ${(12 + r * math.sin(angle)).toStringAsFixed(2)}');
    }
  }
  return 'M${points.join('L')}ZM15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z';
}();

const String _cassette = 'M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM10.4 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM19.6 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z';
const String _bookPath = 'M4.5 19.5v-15A2.5 2.5 0 0 1 7 2h12.5v20H7a2.5 2.5 0 0 1 0-5h12.5';

/// The book's cover and pages as one closed shape, for its wash.
const String _bookBody = 'M4.5 19.5v-15A2.5 2.5 0 0 1 7 2h12.5v20H7a2.5 2.5 0 0 1-2.5-2.5z';
const String _grid = 'M4 4h6.5v6.5H4zM13.5 4H20v6.5h-6.5zM4 13.5h6.5V20H4zM13.5 13.5H20V20h-6.5z';
const String _workspace = 'M3.5 6.5a1 1 0 0 1 1-1h5l2 2.5h8a1 1 0 0 1 1 1v9.5a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z';

/// The pin's teardrop, on the 24 grid (`PLACE_PATH`): where a note was written. The map card draws it.
const String placePath = 'M12 21.5c-4.2-4.4-6.5-8-6.5-11a6.5 6.5 0 0 1 13 0c0 3-2.3 6.6-6.5 11z';

/// The app's few icons, drawn rather than typed (art/Icons.tsx): strokes on the text's colour, a line 2.4 of 24
/// wide with round ends, sized by the text they sit in. Each under the name the web app exports it by.
abstract final class AppIcons {
  static const arrowLeft = DrawnIcon('M20 12H5m6-7-7 7 7 7');
  static const arrowRight = DrawnIcon('M4 12h15m-6-7 7 7-7 7');
  static final cog = DrawnIcon(_cog, _cog);
  static const plus = DrawnIcon('M12 5v14M5 12h14');

  /// A magnifier: a ring, and its handle down to the right.
  static const magnifier = DrawnIcon('M10.5 18a7.5 7.5 0 1 1 0-15a7.5 7.5 0 1 1 0 15ZM21 21l-5.2-5.2', 'M10.5 18a7.5 7.5 0 1 1 0-15a7.5 7.5 0 1 1 0 15Z');

  /// A pushpin: a cap, a flared body, and the needle below it.
  static const pin = DrawnIcon('M8.5 3h7M10 3l-.9 5.6L6 12.4h12l-3.1-3.8L14 3M12 12.4V21', 'M10 3l-.9 5.6L6 12.4h12l-3.1-3.8L14 3z');

  /// A cassette: the shell of the tape with its two reels, the shell washed and the reels left clear through it.
  static const cassette = DrawnIcon(_cassette, _cassette);

  /// A to-do's box with its tick.
  static const tickBox = DrawnIcon('M4.5 4.5h15v15h-15zM8.3 12.3l2.6 2.6 4.9-5.3', 'M4.5 4.5h15v15h-15z');

  /// A book, closed, seen from its fore-edge: the spine's curve and the cover.
  static const book = DrawnIcon(_bookPath, _bookBody);

  /// A notebook: the book with three rings across its spine.
  static const notebook = DrawnIcon('${_bookPath}M2.5 6.5h4M2.5 10.5h4M2.5 14.5h4', _bookBody);

  /// A clock at twenty past two.
  static const clock = DrawnIcon('M12 21a9 9 0 1 1 0-18a9 9 0 0 1 0 18zM12 7.5V12l3 2', 'M12 21a9 9 0 1 1 0-18a9 9 0 0 1 0 18z');

  /// Four squares: the grid of every note.
  static const grid = DrawnIcon(_grid, _grid);

  /// An archive box: a lid, the box, and the handle slot.
  static const archiveBox = DrawnIcon('M3.5 4.5h17v4h-17zM5.5 8.5V19a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1V8.5M10 12.5h4', 'M3.5 4.5h17v4h-17zM5.5 8.5V19a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1V8.5z');

  /// A bin: lid, handle, can and two ribs.
  static const bin = DrawnIcon('M4 6.5h16M9.5 6.5V4h5v2.5M6.2 6.5 7.1 20h9.8l.9-13.5M10 10.5v6M14 10.5v6', 'M6.2 6.5 7.1 20h9.8l.9-13.5z');

  /// A folder: a tab at the top left, then the pocket. Where a note is filed.
  static const workspace = DrawnIcon(_workspace, _workspace);

  /// A board: three columns, the first two with a card in them.
  static const board = DrawnIcon('M4 5.5h4.5v13H4zM9.75 5.5h4.5v8.5h-4.5zM15.5 5.5H20v11h-4.5', 'M4 5.5h4.5v13H4zM9.75 5.5h4.5v8.5h-4.5zM15.5 5.5H20v11h-4.5z');

  /// My location: a ring with four short ticks.
  static const locate = DrawnIcon('M18.5 12a6.5 6.5 0 1 1-13 0a6.5 6.5 0 0 1 13 0zM12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3', 'M18.5 12a6.5 6.5 0 1 1-13 0a6.5 6.5 0 0 1 13 0z');

  /// Every one, by the name the web app exports it by: for a screen that draws them all.
  static final Map<String, DrawnIcon> all = {
    'ArrowLeft': arrowLeft,
    'ArrowRight': arrowRight,
    'Cog': cog,
    'Plus': plus,
    'Magnifier': magnifier,
    'Pin': pin,
    'Cassette': cassette,
    'TickBox': tickBox,
    'Book': book,
    'Notebook': notebook,
    'Clock': clock,
    'Grid': grid,
    'ArchiveBox': archiveBox,
    'Bin': bin,
    'Workspace': workspace,
    'Board': board,
    'Locate': locate,
  };
}

/// One of [AppIcons], drawn: `<Pin />` is `DrawnIconView(AppIcons.pin)`.
///
/// On the page it is 1em square and takes the text's colour; so here, unless [size] and [color] say otherwise. The
/// page also sinks it 0.12em below the baseline so it sits level with the words beside it; a row lays it out as a
/// box, and a line of text takes it with [span], which sinks it the same.
class DrawnIconView extends StatelessWidget {
  const DrawnIconView(this.icon, {super.key, this.size, this.color, this.wash = true});

  final DrawnIcon icon;
  final double? size;
  final Color? color;

  /// False draws the line alone.
  final bool wash;

  /// The icon in a line of text, sunk 0.12em as the page's `vertical-align` sinks it.
  static InlineSpan span(DrawnIcon icon, {required double em, Color? color}) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Transform.translate(offset: Offset(0, 0.12 * em), child: DrawnIconView(icon, size: em, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final em = size ?? context.dependOnInheritedWidgetOfExactType<IconTheme>()?.data.size ?? MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14);
    final ink = color ?? inkAt(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(em),
        painter: DrawnIconPainter(strokes: [icon.d], washed: [if (wash && icon.body != null) icon.body!], color: ink, strokeWidth: 2.4, evenOdd: true),
      ),
    );
  }
}

/// A modern house, for the button that goes home (art/Icons.tsx `House`): a single-pitch roof rising to the right
/// with its overhang drawn past the walls, and a door. The wash is on the house's body alone; the door and the
/// roof's line are strokes over it.
class HouseIcon extends StatelessWidget {
  const HouseIcon({super.key, this.size = 20, this.strokeWidth = 2.1, this.color});

  final double size;
  final double strokeWidth;
  final Color? color;

  static const _body = 'M4.5 10.6 19.5 6v13a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2z';
  static const _roof = 'M2.5 11.2 21.5 5.4';
  static const _door = 'M10 21v-5.5h4V21';

  @override
  Widget build(BuildContext context) {
    final ink = color ?? inkAt(context);
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: DrawnIconPainter(strokes: const [_body, _roof, _door], washed: const [_body], color: ink, strokeWidth: strokeWidth)),
    );
  }
}

/// The map card's pin (`PLACE_PATH`), filled or drawn as the card wants it.
class PlaceMark extends StatelessWidget {
  const PlaceMark({super.key, this.size = 24, required this.color, this.filled = true, this.strokeWidth = 2});

  final double size;
  final Color color;
  final bool filled;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: _PlacePainter(color, filled, strokeWidth)));
}

class _PlacePainter extends CustomPainter {
  const _PlacePainter(this.color, this.filled, this.strokeWidth);
  final Color color;
  final bool filled;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    if (!filled) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round;
    }
    canvas.drawPath(svgPath(placePath), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlacePainter old) => old.color != color || old.filled != filled || old.strokeWidth != strokeWidth;
}

/// How much of an icon's ink its wash is, for a drawing of the caller's own that wants the same.
const double appIconWash = iconWash;
