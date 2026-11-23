import 'package:flutter/widgets.dart';

/// The shape of a person's video tile on a wide screen, width over height (Matt, 2026-11-23: "please make the video
/// chats more square right now they're too wide and narrow make them like 4:3"). A camera's picture is cropped to fill
/// it; a shared screen keeps its own shape inside.
const double tileAspect = 4 / 3;

/// [n] tiles of [aspect] in a grid as large as fits in [room], [gap] between them: every number across is tried and
/// the one giving the biggest tiles kept. The size is the same for every tile; a short last row is the caller's to
/// centre.
({int cols, int rows, Size size}) fitTiles(Size room, int n, {double gap = 0, double aspect = tileAspect}) {
  var best = (cols: 1, rows: n < 1 ? 0 : 1, size: Size.zero);
  for (var cols = 1; cols <= n; cols++) {
    final rows = (n / cols).ceil();
    var w = (room.width - gap * (cols - 1)) / cols;
    var h = (room.height - gap * (rows - 1)) / rows;
    if (w <= 0 || h <= 0) continue;
    if (w / h > aspect) {
      w = h * aspect;
    } else {
      h = w / aspect;
    }
    if (w * h > best.size.width * best.size.height) best = (cols: cols, rows: rows, size: Size(w, h));
  }
  return best;
}

/// [count] tiles from [tile], 4:3 and as large as fit in the room given, the grid centred and a short last row centred
/// under the rest.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.count, required this.tile, this.gap = 8});
  final int count;
  final Widget Function(int i) tile;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final fit = fitTiles(box.biggest, count, gap: gap);
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
            for (var r = 0; r < fit.rows; r++)
              Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
                for (var i = r * fit.cols; i < count && i < (r + 1) * fit.cols; i++) SizedBox(width: fit.size.width, height: fit.size.height, child: tile(i)),
              ]),
          ]),
        );
      });
}
