/// The keyboard comes back with the app. The web app's page keeps its focus while another app is in front, and the
/// WebView raises the keyboard again as it returns; Android takes Flutter's keyboard down as the app leaves and
/// nothing asks for it again, so a note being written came back with its caret and no keys, and Back went a step
/// back in the app where the page's Back put the keyboard away (seen beside the web app on the emulator).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Remembers whether the keyboard was up while the app was in front, and asks for it again on the way back while
/// something still holds the focus. It asks the text input channel itself, so it is the same for the editor's own
/// client and for a kit field.
class KeepKeyboard with WidgetsBindingObserver {
  KeepKeyboard._();

  static KeepKeyboard? _one;

  /// Starts watching, once.
  static void install() {
    if (_one != null) return;
    WidgetsBinding.instance.addObserver(_one = KeepKeyboard._());
  }

  /// Stops watching (a test's).
  static void remove() {
    final one = _one;
    if (one != null) WidgetsBinding.instance.removeObserver(one);
    _one = null;
  }

  /// How long after the app is back the keyboard is asked for a second time: the first ask can come before the
  /// window has the focus, and Android drops it.
  static const Duration again = Duration(milliseconds: 300);

  bool _front = true;
  bool _up = false;
  bool _wasUp = false;

  @override
  void didChangeMetrics() {
    if (!_front) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    _up = views.any((view) => view.viewInsets.bottom > 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _front = true;
      if (!_wasUp) return;
      _wasUp = false;
      _raise();
      Timer(again, _raise);
      return;
    }
    if (_front) {
      _front = false;
      _wasUp = _up;
      _up = false;
    }
  }

  void _raise() {
    if (!_front || FocusManager.instance.primaryFocus?.context == null) return;
    if (WidgetsBinding.instance.platformDispatcher.views.any((view) => view.viewInsets.bottom > 0)) return;
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }
}
