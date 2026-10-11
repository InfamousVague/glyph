import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'ghost_mark.g.dart';
import 'svg_path.dart';

export 'ghost_mark.g.dart';

enum MarkPart { wisp, outline, body, fold, eye }

/// One shape of the mark: an ink shape is a line or an eye, drawn in the page's ink; the others are the note's
/// paper inside them, drawn in the page's paper.
class MarkShape {
  const MarkShape(this.part, this.ink, this.d);
  final MarkPart part;
  final bool ink;
  final String d;
}

/// Ghost.md's mark (art/ghostMark.ts): a note with a folded corner as a ghost, waving, a wisp rising from its head,
/// drawn from its shapes so it turns over with the theme rather than showing a white ghost on a dark page.
///
/// On the web the shapes are for a page that draws the mark inline (the connector's sign-in page); the app's icon
/// and the launch screen's ghost are pictures of the same drawing. [ink] and [paper] are the page's (`--app-ink`,
/// `--app-paper`) unless given.
class GhostMark extends StatelessWidget {
  const GhostMark({super.key, this.size = 96, this.ink, this.paper});

  final double size;
  final Color? ink;
  final Color? paper;

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTheme.maybeOf(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(ink ?? tokens?.color('app-ink') ?? const Color(0xFF000000), paper ?? tokens?.color('app-paper') ?? const Color(0xFFFFFFFF)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.ink, this.paper);
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / ghostMarkBox[2], size.height / ghostMarkBox[3]);
    canvas.translate(-ghostMarkBox[0], -ghostMarkBox[1]);
    for (final shape in ghostMarkShapes) {
      canvas.drawPath(svgPath(shape.d), Paint()..color = shape.ink ? ink : paper);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink || old.paper != paper;
}
