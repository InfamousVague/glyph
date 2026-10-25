import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The strips a view's soft edges are drawn with under [of], whichever way this platform draws them
/// (lib/art/edge_strips.dart [edgeLook]): through pictures of the view ([EdgeStrips]), as the page's ground laid
/// over it or over a backdrop's bands ([EdgeShade]), or as a box's masks ([EdgeMasked]). Their places are the same
/// in every look; only how they are drawn differs. The first view found under [of], or none.
List<EdgeStrip> edgeStripsUnder(WidgetTester tester, Finder of) {
  // By what draws them: a box whose height is its own makes them as it is laid out, by a widget of blur_box.dart's own.
  final pictures = _drawnBy<RenderEdgeStrips>(of);
  if (pictures.isNotEmpty) return pictures.first.strips;
  final masked = _drawnBy<RenderEdgeMasked>(of);
  if (masked.isNotEmpty) return masked.first.strips;
  for (final paint in tester.widgetList<CustomPaint>(find.descendant(of: of, matching: find.byType(CustomPaint)))) {
    // Over the view where the edges fade; over a backdrop's bands where they are blurred so.
    if (paint.foregroundPainter case EdgeShade(:final strips)) return strips;
    if (paint.painter case EdgeShade(:final strips)) return strips;
  }
  return const [];
}

/// Whether anything under [of] takes pictures of a view to draw its edges.
bool takesEdgePictures(WidgetTester tester, Finder of) => _drawnBy<RenderEdgeStrips>(of).any((view) => view.strips.isNotEmpty);

/// The render objects of type [T] under [of], in the tree's order.
List<T> _drawnBy<T extends RenderObject>(Finder of) => [
      for (final element in find.descendant(of: of, matching: find.byElementPredicate((e) => e is RenderObjectElement && e.renderObject is T)).evaluate())
        (element as RenderObjectElement).renderObject as T,
    ];
