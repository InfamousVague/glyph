/// The selection's handles and the magnifier over a finger that is moving one: Flutter's `SelectionOverlay` on the
/// view's layer links, with the kit's handles (`GlacierTextSelectionControls`). Never the system's toolbar: the
/// note's own menu is another piece, and is asked for through `Editor.onHold`.
///
/// On the web these are the browser's own (glyphTheme.ts: "real browser selections with real grab handles and a
/// real magnifier"), so what is kept is Android's behaviour rather than a look measured off the page: a handle at
/// each end of a selection, one under a caret after a tap, which goes after a few seconds or at the next key; a
/// handle dragged moves its end of the selection, the other end staying put, with the loupe above the finger and
/// the page scrolling when the finger nears its edge.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../state/selection.dart';
import '../state/state.dart';
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'motion.dart';

/// What the handles ask of the editor's widget.
abstract class EditorHandlesHost {
  BuildContext get context;
  EditorView get view;
  LayerLink get caretLink;

  /// The scroll view's rectangle on screen, or null.
  Rect? get viewportRect;

  /// Scrolls when `global` is near the scroll view's edge; `again` is called after each step with the page moved.
  void autoScroll(Offset global, VoidCallback again);
  void stopAutoScroll();
}

class EditorHandles {
  EditorHandles(this.host);

  final EditorHandlesHost host;

  /// How long the handle under a caret stays: about Android's own.
  static const Duration caretHandleFor = Duration(seconds: 4);

  SelectionOverlay? _overlay;
  bool _collapsed = false;
  bool _wanted = false;
  Timer? _fade;
  final LayerLink _toolbar = LayerLink();
  final ValueNotifier<bool> _startVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _endVisible = ValueNotifier<bool>(true);

  EditorView get _view => host.view;

  /// Whether handles are up.
  bool get showing => _overlay != null;

  /// Whether a handle is being dragged.
  bool get dragging => _dragAnchor != null;

  /// Shows handles for the selection as it is: one under a caret, two round a range.
  void show() {
    _wanted = true;
    update();
  }

  /// Takes the handles away until they are asked for again.
  void hide() {
    _wanted = false;
    _fade?.cancel();
    _fade = null;
    _drop();
  }

  void _drop() {
    _overlay?.dispose();
    _overlay = null;
  }

  void dispose() {
    hide();
    _startVisible.dispose();
    _endVisible.dispose();
  }

  Rect? _coords(int pos, int side) => _view.coordsAtPos(pos, side);

  /// Brings the handles in line with the selection: called after every update of the view and every frame the page
  /// scrolled.
  void update() {
    if (!_wanted || !_view.hasFocus || Overlay.maybeOf(host.context, rootOverlay: true) == null) {
      _drop();
      return;
    }
    final sel = _view.state.selection.main;
    final collapsed = sel.empty;
    if (collapsed && _view.state.doc.length == 0 || collapsed && !_view.state.facet(EditorViewLike.editable)) {
      _drop();
      return;
    }
    // An iPhone draws nothing under a caret (the kit's handles there are the phone's own), and a handle that is
    // not drawn must not be left to take the touches round the caret either.
    if (collapsed && !dragging && defaultTargetPlatform == TargetPlatform.iOS) {
      _drop();
      return;
    }
    if (_overlay != null && collapsed != _collapsed && !dragging) _drop();
    final start = _coords(sel.from, 1), end = _coords(sel.to, collapsed ? 1 : -1);
    final startHeight = start?.height ?? _view.heights.lineHeight, endHeight = end?.height ?? _view.heights.lineHeight;
    final points = <TextSelectionPoint>[
      TextSelectionPoint(start?.bottomLeft ?? Offset.zero, TextDirection.ltr),
      TextSelectionPoint(end?.bottomLeft ?? Offset.zero, TextDirection.ltr),
    ];
    final bounds = host.viewportRect;
    bool inView(Rect? at) => at != null && (bounds == null || (at.bottom > bounds.top && at.top < bounds.bottom));
    _startVisible.value = inView(start);
    _endVisible.value = inView(end);
    var overlay = _overlay;
    if (overlay == null) {
      _collapsed = collapsed && !dragging;
      final theme = _view.theme;
      overlay = _overlay = SelectionOverlay(
        context: host.context,
        startHandleType: _collapsed ? TextSelectionHandleType.collapsed : TextSelectionHandleType.left,
        lineHeightAtStart: startHeight,
        startHandlesVisible: _startVisible,
        onStartHandleDragStart: (details) => _dragStart(details.globalPosition, start: true),
        onStartHandleDragUpdate: (details) => _dragUpdate(details.globalPosition),
        onStartHandleDragEnd: (_) => _dragEnd(),
        endHandleType: _collapsed ? TextSelectionHandleType.collapsed : TextSelectionHandleType.right,
        lineHeightAtEnd: endHeight,
        endHandlesVisible: _endVisible,
        onEndHandleDragStart: (details) => _dragStart(details.globalPosition, start: false),
        onEndHandleDragUpdate: (details) => _dragUpdate(details.globalPosition),
        onEndHandleDragEnd: (_) => _dragEnd(),
        selectionEndpoints: points,
        selectionControls: GlacierTextSelectionControls(color: theme?.caret ?? const Color(0xFF000000)),
        selectionDelegate: null,
        clipboardStatus: null,
        startHandleLayerLink: _collapsed ? host.caretLink : _view.startHandleLink,
        endHandleLayerLink: _view.endHandleLink,
        toolbarLayerLink: _toolbar,
        magnifierConfiguration: TextMagnifierConfiguration(magnifierBuilder: (context, controller, info) => EditorMagnifier(info: info)),
      );
      overlay.showHandles();
    } else {
      overlay
        ..lineHeightAtStart = startHeight
        ..lineHeightAtEnd = endHeight
        ..selectionEndpoints = points;
    }
    if (_collapsed && !dragging) {
      _fade ??= Timer(caretHandleFor, () {
        _fade = null;
        if (_collapsed) hide();
      });
    } else {
      _fade?.cancel();
      _fade = null;
    }
  }

  /// The handles go when the note changes under them: something was typed, or typed over the selection.
  void typed() {
    if (_wanted && !dragging) hide();
  }

  // -- dragging -----------------------------------------------------------------------------------------------------

  /// The end of the selection that stays put while a handle is dragged; null when none is.
  int? _dragAnchor;

  /// From the finger to the middle of the text the handle hangs under: a handle is held below its line.
  Offset _grip = Offset.zero;
  Offset _finger = Offset.zero;

  void _dragStart(Offset global, {required bool start}) {
    final sel = _view.state.selection.main;
    final at = _coords(start ? sel.from : sel.to, start || sel.empty ? 1 : -1);
    _dragAnchor = sel.empty ? -1 : (start ? sel.to : sel.from);
    _grip = at == null ? Offset.zero : at.center - global;
    _finger = global;
    _fade?.cancel();
    _fade = null;
    final info = _magnifier(global);
    if (info != null) _overlay?.showMagnifier(info);
  }

  void _dragUpdate(Offset global) {
    if (_dragAnchor == null) return;
    _finger = global;
    _dragTo();
    host.autoScroll(global, _dragTo);
  }

  void _dragTo() {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final found = _view.posAtCoords(_finger + _grip, precise: false);
    if (found == null) return;
    final pos = skipAtoms(_view, found);
    final sel = _view.state.selection.main;
    if (anchor < 0) {
      if (pos != sel.head) _view.dispatch(TransactionSpec(selection: EditorSelection.single(pos), userEvent: 'select.pointer'));
    } else if (pos != anchor && pos != sel.head) {
      // A handle cannot close the selection: it stops a place short of the other.
      _view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, pos), userEvent: 'select.pointer'));
    }
    final info = _magnifier(_finger);
    if (info != null) _overlay?.updateMagnifier(info);
  }

  void _dragEnd() {
    _dragAnchor = null;
    host.stopAutoScroll();
    _overlay?.hideMagnifier();
    update();
  }

  /// Shows the loupe for a finger that is selecting without a handle (a press held and dragged).
  void showMagnifierAt(Offset global) {
    final info = _magnifier(global);
    final overlay = _overlay;
    if (info == null || overlay == null) return;
    if (overlay.magnifierExists) {
      overlay.updateMagnifier(info);
    } else {
      overlay.showMagnifier(info);
    }
  }

  void hideMagnifier() => _overlay?.hideMagnifier();

  MagnifierInfo? _magnifier(Offset global) {
    final sel = _view.state.selection.main;
    final caret = _coords(sel.head, sel.assoc == 0 ? 1 : sel.assoc);
    final line = _view.lineAt(sel.head);
    if (caret == null || line == null) return null;
    final box = MatrixUtils.transformRect(line.getTransformTo(null), Offset.zero & line.size);
    return MagnifierInfo(
      globalGesturePosition: global,
      caretRect: caret,
      fieldBounds: host.viewportRect ?? box,
      currentLineBoundaries: Rect.fromLTRB(box.left, caret.top, box.right, caret.bottom),
    );
  }
}

/// The loupe: Android's, a rounded lens a little over the line being touched, showing it a quarter larger.
class EditorMagnifier extends StatelessWidget {
  const EditorMagnifier({super.key, required this.info});

  final ValueNotifier<MagnifierInfo> info;

  static const Size size = Size(77.37, 37.9);
  static const double _lift = 22;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MagnifierInfo>(
    valueListenable: info,
    builder: (context, info, _) {
      final screen = MediaQuery.sizeOf(context);
      final line = info.currentLineBoundaries;
      // Over the finger along the line, on the caret's line whatever the finger's height.
      final focus = Offset(info.globalGesturePosition.dx.clamp(line.left, math.max(line.left, line.right)), info.caretRect.center.dy);
      final left = (focus.dx - size.width / 2).clamp(0.0, math.max(0.0, screen.width - size.width)).toDouble();
      final top = math.max(0.0, focus.dy - size.height / 2 - _lift - size.height / 2);
      final centre = Offset(left + size.width / 2, top + size.height / 2);
      return Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: RawMagnifier(
            size: size,
            magnificationScale: 1.25,
            focalPointOffset: focus - centre,
            decoration: const MagnifierDecoration(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(40))),
              shadows: <BoxShadow>[BoxShadow(blurRadius: 1.5, offset: Offset(0, 2), spreadRadius: 0.75, color: Color(0x1F000000))],
            ),
          ),
        ),
      );
    },
  );
}
