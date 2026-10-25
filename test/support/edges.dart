import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The strips a view's soft edges are drawn with under [of], whichever way this platform draws them
/// (lib/art/edge_strips.dart [edgeLook]): through pictures of the view ([EdgeStrips]), as the page's ground laid
/// over it or over a backdrop's bands ([EdgeShade]), or as a box's masks ([EdgeMasked]). Their places are the same
/// in every look; only how they are drawn differs. The first view found under [of], or none.
List<EdgeStrip> edgeStripsUnder(WidgetTester tester, Finder of) {
  final pictures = find.descendant(of: of, matching: find.byType(EdgeStrips));
  if (pictures.evaluate().isNotEmpty) return tester.renderObject<RenderEdgeStrips>(pictures.first).strips;
  final masked = find.descendant(of: of, matching: find.byType(EdgeMasked));
  if (masked.evaluate().isNotEmpty) return tester.renderObject<RenderEdgeMasked>(masked.first).strips;
  for (final paint in tester.widgetList<CustomPaint>(find.descendant(of: of, matching: find.byType(CustomPaint)))) {
    // Over the view where the edges fade; over a backdrop's bands where they are blurred so.
    if (paint.foregroundPainter case EdgeShade(:final strips)) return strips;
    if (paint.painter case EdgeShade(:final strips)) return strips;
  }
  return const [];
}

/// Whether anything under [of] takes pictures of a view to draw its edges.
bool takesEdgePictures(WidgetTester tester, Finder of) =>
    tester.renderObjectList<RenderEdgeStrips>(find.descendant(of: of, matching: find.byType(EdgeStrips))).any((view) => view.strips.isNotEmpty);
