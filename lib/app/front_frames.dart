import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's binding: Flutter's own, but nothing is drawn from the moment Android says the app is leaving the front
/// (the activity's onPause, sent over `ghost_md/front` by MainActivity.kt) until it is back (onResume).
///
/// Why: on Impeller over OpenGL ES a frame drawn while the window's surface is being taken away is drawn with no
/// context ("call to OpenGL ES API with no current context"), then a null read on the raster thread, and the app is
/// gone. Flutter itself stops making frames only once the app is hidden, which Android tells after the surface has
/// gone; anything that asks for a frame in between does it: a clock that never ends (the walkthrough's first page,
/// the update card's drift: three times of three each), and a caret's blink or a sheet still settling (the note's
/// More sheet, once). Stopping the clocks alone covered the first two and not the third.
///
/// Held, a frame is begun and its clocks tick, but nothing is built, laid out or sent to be drawn; what was dirty
/// stays dirty and is drawn by the first frame after the app is back. onPause is the activity leaving, not a window
/// losing focus: beside another window in split screen, under the notification shade or behind a permission prompt
/// the app goes on drawing.
class GhostBinding extends WidgetsFlutterBinding {
  static const MethodChannel _front = MethodChannel('ghost_md/front');

  static GhostBinding? _instance;

  /// The binding, made once: `main` calls this in place of `WidgetsFlutterBinding.ensureInitialized`.
  static WidgetsBinding ensureInitialized() {
    if (_instance == null) {
      final binding = GhostBinding();
      _instance = binding;
      if (defaultTargetPlatform == TargetPlatform.android) {
        _front.setMethodCallHandler((call) async {
          if (call.method == 'leaving') binding._hold(true);
          if (call.method == 'back') binding._hold(false);
        });
      }
    }
    return WidgetsBinding.instance;
  }

  bool _held = false;
  bool _missed = false;

  void _hold(bool held) {
    if (held == _held) return;
    _held = held;
    if (!held && _missed) {
      _missed = false;
      scheduleFrame();
    }
  }

  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    // Back in front whatever the channel said: a hold must never outlive the app's return.
    if (state == AppLifecycleState.resumed) _hold(false);
    super.handleAppLifecycleStateChanged(state);
  }

  @override
  void drawFrame() {
    if (_held) {
      _missed = true;
      return;
    }
    super.drawFrame();
  }
}
