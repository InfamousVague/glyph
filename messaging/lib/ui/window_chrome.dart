import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The Mac window's top bar is the app's own (Matt, 2026-11-17: "move the toolbar top bar into our own topbar
/// component so it can match themes on mac make it fold the traffic lights down and shift over the chat list on the
/// sidebar and make the top bars draggable areas"): the window draws edge to edge with no title strip of the Mac's
/// (macos/Runner/MainFlutterWindow.swift), each page's header ([GhostPage]) is drawn in the theme's colours where the
/// strip was, the three buttons sit centred in the header of the page at the window's left, that page's header starts
/// after them ([TopBarLights]), and every header moves the window when dragged and zooms it on a double click
/// ([WindowDragArea]).
class MacChrome {
  MacChrome._();

  static const _channel = MethodChannel('ghost_desktop/window');

  /// Only in the Mac app, and not under `flutter test` (which runs on a Mac but draws no window).
  static bool enabled = Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Where the first of the three buttons is, from the window's left.
  static const double lightsX = 20;

  /// What the page at the window's left leaves before its header's first word: the three buttons and a gap.
  static const double lightsRoom = 84;

  static ({double height, bool dark})? _said;

  /// Tells the window how tall the header is (the buttons are centred in it) and whether the look is dark (the
  /// buttons are drawn for it). Said again only when either changes.
  static void say({required double height, required bool dark}) {
    if (!enabled) return;
    final now = (height: height, dark: dark);
    if (_said == now) return;
    _said = now;
    _channel.invokeMethod('chrome', {'height': height, 'x': lightsX, 'dark': dark}).catchError((_) => null);
  }

  static void drag() => _channel.invokeMethod('drag').catchError((_) => null);
  static void zoom() => _channel.invokeMethod('zoom').catchError((_) => null);
}

/// A top bar's ground: a press that moves on it drags the window, a double click zooms it (or does what the Mac is set
/// to). It listens without taking part in the gestures, so the bar's own buttons answer as before.
class WindowDragArea extends StatefulWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  State<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends State<WindowDragArea> {
  Offset? _down;
  bool _dragged = false;
  Duration? _lastUp;
  Offset? _lastUpAt;

  @override
  Widget build(BuildContext context) {
    if (!MacChrome.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) return;
        _down = e.position;
        _dragged = false;
      },
      onPointerMove: (e) {
        final down = _down;
        if (down == null || _dragged) return;
        if ((e.position - down).distance > 3) {
          _dragged = true;
          MacChrome.drag();
        }
      },
      onPointerUp: (e) {
        final down = _down;
        _down = null;
        if (down == null || _dragged) return;
        final last = _lastUp;
        final at = _lastUpAt;
        if (last != null && at != null && e.timeStamp - last < const Duration(milliseconds: 450) && (e.position - at).distance < 6) {
          _lastUp = null;
          // Not on one of the bar's buttons: a double click there is two presses of the button.
          if (!_onButton(e.position)) MacChrome.zoom();
          return;
        }
        _lastUp = e.timeStamp;
        _lastUpAt = e.position;
      },
      onPointerCancel: (_) => _down = null,
      child: widget.child,
    );
  }

  /// Whether [global] is over something in the bar that answers a press (a button, the title that opens settings).
  bool _onButton(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMouseRegion && target.cursor == SystemMouseCursors.click) return true;
    }
    return false;
  }
}

/// Said over the page at the window's left (the list, or a page over all of a narrow window): its header leaves the
/// three buttons room.
class TopBarLights extends InheritedWidget {
  const TopBarLights({super.key, required super.child});

  static double roomOf(BuildContext context) =>
      MacChrome.enabled && context.dependOnInheritedWidgetOfExactType<TopBarLights>() != null ? MacChrome.lightsRoom : 0;

  @override
  bool updateShouldNotify(TopBarLights oldWidget) => false;
}
