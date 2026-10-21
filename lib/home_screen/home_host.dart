/// The phone's half of the home screen, over the channel `ghost_md/home_screen` (android/…/ghost_md/home/HomeScreen.kt):
/// `put {kind, json}` keeps what a widget draws or the icon's shortcuts name, and has them drawn again.
///
/// - `todos`: the To-dos widget's open to-dos, dated and not (home_data.dart `todosJson`); the Calendar widget's
///   dated ones too.
/// - `notes`: the Recent notes widget's notes (`notesJson`).
/// - `voice`: the Voice note widget's last recordings (`notesJson`).
/// - `calendar`: the Calendar widget's events, or that the Calendar plugin is off (`calendarJson`).
/// - `look`: the app theme's side (`dark`, `light`, `system`), which the widgets are drawn in (`lookJson`).
/// - `recent`: the notes opened last, the icon's shortcuts after its own four (`namedJson`).
/// - `today`, `pinned`: what the Today and Pinned widgets drew before the four replaced them (docs/WIDGETS_ANDROID.md). No
///   longer handed over; the phone takes them and keeps nothing.
///
/// Where there is no phone half (a desktop, an iPhone, a test without one) nothing is kept and nothing asks.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// What the home screen is handed.
enum HomeKind { today, pinned, recent, todos, notes, voice, calendar, look }

abstract interface class HomeScreenHost {
  /// Keeps [json] as what [kind] draws. False where it could not be kept.
  Future<bool> put(HomeKind kind, String json);
}

const MethodChannel homeScreenChannel = MethodChannel('ghost_md/home_screen');

class PhoneHomeScreenHost implements HomeScreenHost {
  const PhoneHomeScreenHost({MethodChannel channel = homeScreenChannel, bool? android}) : _channel = channel, _android = android;

  final MethodChannel _channel;
  final bool? _android;

  @override
  Future<bool> put(HomeKind kind, String json) async {
    if (!(_android ?? defaultTargetPlatform == TargetPlatform.android)) return false;
    try {
      return await _channel.invokeMethod<Object?>('put', {'kind': kind.name, 'json': json}) == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
