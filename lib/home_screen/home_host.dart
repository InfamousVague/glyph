/// The phone's half of the home screen, over the channel `ghost_md/home_screen` (android/…/ghost_md/home/HomeScreen.kt):
/// `put {kind, json}` keeps what a widget draws or the icon's shortcuts name, and has them drawn again.
///
/// - `today`: the Today widget's to-dos (home_data.dart `todayJson`).
/// - `pinned`: the Pinned widget's notes (`namedJson`).
/// - `recent`: the notes opened last, the icon's shortcuts after its own four (`namedJson`).
///
/// Where there is no phone half (a desktop, an iPhone, a test without one) nothing is kept and nothing asks.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// What the home screen is handed.
enum HomeKind { today, pinned, recent }

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
