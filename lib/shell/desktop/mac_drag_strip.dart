/// The Mac app's drag strip: `.app-dragBar` of the web app's app.css, the top row's empty ground, which drags the
/// window as a title bar does and zooms it on a double click (`data-tauri-drag-region` in the Tauri app).
///
/// It sits behind the bar's controls (lib/shell/app_tab_bar.dart), so the sidebar button, the arrows and the tabs
/// still take their presses and only the ground between them reaches it. A press that moves is handed to the
/// window itself (`NSWindow.performDrag`, lib/shell/desktop/mac_window.dart), which follows the pointer from
/// there; nothing is drawn.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'mac_window.dart';

class MacDragStrip extends StatefulWidget {
  const MacDragStrip({super.key, this.onDrag, this.onZoom});

  /// The window's, unless a test hands its own.
  final VoidCallback? onDrag;
  final VoidCallback? onZoom;

  @override
  State<MacDragStrip> createState() => _MacDragStripState();
}

class _MacDragStripState extends State<MacDragStrip> {
  Offset? _down;
  int? _pointer;
  Duration? _lastUp;
  Offset? _lastUpAt;

  void _pressed(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    _down = event.position;
    _pointer = event.pointer;
  }

  void _moved(PointerMoveEvent event) {
    final down = _down;
    if (down == null || event.pointer != _pointer) return;
    // Past a click's own slop: a drag of the window, which the window takes from here.
    if ((event.position - down).distance < kPrecisePointerHitSlop) return;
    _down = null;
    _lastUp = null;
    (widget.onDrag ?? MacWindow.instance.drag)();
  }

  void _released(PointerUpEvent event) {
    if (_down == null || event.pointer != _pointer) return;
    _down = null;
    final last = _lastUp, at = _lastUpAt;
    if (last != null && at != null && event.timeStamp - last <= kDoubleTapTimeout && (event.position - at).distance <= kDoubleTapSlop) {
      _lastUp = null;
      (widget.onZoom ?? MacWindow.instance.zoom)();
      return;
    }
    _lastUp = event.timeStamp;
    _lastUpAt = event.position;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pressed,
      onPointerMove: _moved,
      onPointerUp: _released,
      onPointerCancel: (_) => _down = null,
      child: const SizedBox.expand(),
    );
  }
}
