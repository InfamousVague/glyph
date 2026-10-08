/// The sliver round the editor's own that the input layer hears pointers through, and that carries the caret's
/// layer link.
///
/// A sliver cannot be wrapped in a `Listener` or a `GestureDetector` (they are boxes), so this is the sliver's
/// twin of one: it puts itself in the hit test's path wherever the editor's sliver is, and passes every pointer
/// event to [onPointer]. With [fill] it also answers for the rest of the scroll view below a short note, which
/// is the web's `min-height: 100%` (Editor.tsx `GROW_THEME`): a tap on the empty paper under the last line puts
/// the caret at the end.
///
/// The view gives layer links for a selection's two ends; a caret has none, so the handle under a caret follows
/// [caretLink], whose leader is laid here at the foot of the caret each time the editor paints. (It would sit
/// better beside the other two, in the line that draws the caret: see the report.)
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../view/editor_view.dart';

class EditorInputSliver extends SingleChildRenderObjectWidget {
  const EditorInputSliver({super.key, required this.view, required this.caretLink, required this.onPointer, this.fill = true, super.child});

  final EditorView view;
  final LayerLink caretLink;
  final void Function(PointerEvent event) onPointer;
  final bool fill;

  @override
  RenderEditorInput createRenderObject(BuildContext context) => RenderEditorInput(view: view, caretLink: caretLink, onPointer: onPointer, fill: fill);

  @override
  void updateRenderObject(BuildContext context, RenderEditorInput renderObject) {
    renderObject
      ..view = view
      ..caretLink = caretLink
      ..onPointer = onPointer
      ..fill = fill;
  }
}

class RenderEditorInput extends RenderProxySliver {
  RenderEditorInput({required this.view, required LayerLink caretLink, required this.onPointer, bool fill = true}) : _caretLink = caretLink, _fill = fill;

  EditorView view;
  void Function(PointerEvent event) onPointer;

  LayerLink _caretLink;
  LayerLink get caretLink => _caretLink;
  set caretLink(LayerLink value) {
    if (identical(value, _caretLink)) return;
    _caretLink = value;
    markNeedsPaint();
  }

  bool _fill;
  bool get fill => _fill;
  set fill(bool value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final own = child.geometry!;
    geometry = _fill && own.scrollOffsetCorrection == null && constraints.remainingPaintExtent > own.hitTestExtent ? own.copyWith(hitTestExtent: constraints.remainingPaintExtent) : own;
  }

  @override
  bool hitTest(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    final geometry = this.geometry;
    if (geometry == null || mainAxisPosition < 0 || mainAxisPosition >= geometry.hitTestExtent || crossAxisPosition < 0 || crossAxisPosition >= constraints.crossAxisExtent) return false;
    final child = this.child;
    if (child != null && child.geometry!.visible) child.hitTest(result, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition);
    result.add(SliverHitTestEntry(this, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, SliverHitTestEntry entry) => onPointer(event);

  /// The scroll view's box this sliver is in: what the keyboard is told the editor's box is.
  RenderBox? get viewportBox {
    RenderObject? node = parent;
    while (node != null && node is! RenderBox) {
      node = node.parent;
    }
    return node as RenderBox?;
  }

  /// A global point in the sliver's own coordinates (down from where it starts, whatever is scrolled off).
  Offset globalToSliver(Offset global) {
    final inverse = Matrix4.tryInvert(getTransformTo(null));
    final local = inverse == null ? global : MatrixUtils.transformPoint(inverse, global);
    return local + Offset(0, constraints.scrollOffset);
  }

  final LayerHandle<LeaderLayer> _caret = LayerHandle<LeaderLayer>();

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final sel = view.state.selection.main;
    final at = view.hasFocus && sel.empty ? view.coordsAtPos(sel.head, sel.assoc == 0 ? 1 : sel.assoc) : null;
    final inverse = at == null ? null : Matrix4.tryInvert(getTransformTo(null));
    if (at == null || inverse == null) {
      _caret.layer = null;
      return;
    }
    final anchor = offset + MatrixUtils.transformPoint(inverse, at.bottomLeft);
    final layer = _caret.layer;
    if (layer == null) {
      _caret.layer = LeaderLayer(link: _caretLink, offset: anchor);
    } else {
      layer
        ..link = _caretLink
        ..offset = anchor;
    }
    context.pushLayer(_caret.layer!, (context, offset) {}, Offset.zero);
  }

  @override
  void dispose() {
    _caret.layer = null;
    super.dispose();
  }
}
