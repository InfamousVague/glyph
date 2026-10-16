/// The keyboard up for a note opened from outside the app (a widget's pen, the icon's New note, the tile). The note
/// takes the focus as it opens, as one made from the + does, but the app is still coming to the front then, and
/// Android drops a keyboard asked for before the window has the focus: so it is asked again once the app is in
/// front, and once more a moment later, as lib/core/keep_keyboard.dart asks for one on the way back.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How long after the app is in front the keyboard is asked for, the first time and the second.
const List<Duration> raiseAfter = [Duration(milliseconds: 350), Duration(milliseconds: 900)];

/// Asks for the keyboard while something holds the focus and no keyboard is up: once the app is in front.
void raiseKeyboardSoon() {
  void raise() {
    if (FocusManager.instance.primaryFocus?.context == null) return;
    if (WidgetsBinding.instance.platformDispatcher.views.any((view) => view.viewInsets.bottom > 0)) return;
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void soon() {
    for (final wait in raiseAfter) {
      Timer(wait, raise);
    }
  }

  if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return soon();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      listener.dispose();
      soon();
    },
  );
}
