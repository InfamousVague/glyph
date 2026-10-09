import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Stops every clock under it the moment the app is no longer the one in front, and lets them go on when it is again.
///
/// Flutter stops making frames once the app is hidden, which on Android is told after the window's surface has gone.
/// In between (from `inactive`, Android's onPause) a clock that never ends still asks for a frame each tick, and on
/// Impeller over OpenGL ES a frame drawn as the surface goes is drawn with no context: "call to OpenGL ES API with no
/// current context", then a null read on the raster thread and the app is gone. Seen on an Android emulator every
/// time Home was pressed over the walkthrough's first page (its promises' clock) and over the update card (its
/// eleven-second drift), and never over a page at rest. With the clocks stopped at `inactive` no frame is on its way
/// when the surface is taken, and both survive.
///
/// Android only: the fault is that engine's. What it costs there: beside another window (split screen on a Fold) the
/// app that is not focused holds its animations still until it is touched again. A stopped clock keeps its time, so
/// nothing starts over.
class FrontTickers extends StatefulWidget {
  const FrontTickers({super.key, required this.child});
  final Widget child;

  @override
  State<FrontTickers> createState() => _FrontTickersState();
}

class _FrontTickersState extends State<FrontTickers> with WidgetsBindingObserver {
  bool _front = _isFront(WidgetsBinding.instance.lifecycleState);

  static bool _isFront(AppLifecycleState? state) => state == null || state == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = _isFront(state);
    if (front != _front) setState(() => _front = front);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(enabled: _front || defaultTargetPlatform != TargetPlatform.android, child: widget.child);
}
