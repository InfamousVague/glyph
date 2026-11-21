import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Windows lowers every other sound on the computer while the app is in a call (Matt, 2026-11-21: "When on
/// windows in a call it's making my background audio on my PC quieter is this a setting we can turn off?"). Windows
/// does that to any app talking through a microphone unless the app says it does not want it; the app says so unless
/// "Lower other sounds in calls" is switched on in Settings › Voice and video (VoiceSettings.duckOthers).
///
/// The native half is windows/runner/ducking.cpp, on "ghost/ducking". Elsewhere nothing is asked: the Mac and the
/// phone do not lower other apps for a call this way.
class Ducking {
  Ducking._();
  static const _channel = MethodChannel('ghost/ducking');

  /// Said before a call opens the microphone and again once it is open (VoiceFx.apply), and when the switch changes.
  static Future<void> apply({required bool duckOthers}) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await _channel.invokeMethod<int>('set', {'leaveOthers': !duckOthers});
    } on MissingPluginException {
      // An older Windows build: Windows does as it does.
    } on PlatformException {
      // Likewise.
    }
  }
}
