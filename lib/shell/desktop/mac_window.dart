/// The Mac app's window, as the page reaches it: `ghost_md/window`, answered by macos/Runner/MainFlutterWindow.swift.
///
/// The Tauri Mac app's window was Tauri's (`tauri.conf.json` `titleBarStyle: Overlay`, src/platform.rs
/// `place_traffic_lights`, and `data-tauri-drag-region` on `.app-dragBar`). Here the window is Swift's and this is
/// the page's half of it:
///
/// - [MacWindow.lights] says where the page's top row is, so the three window buttons are set into it;
/// - [MacWindow.drag] and [MacWindow.zoom] are the drag strip's (lib/shell/desktop/mac_drag_strip.dart);
/// - a choice from the Mac's menu bar arrives as `menu` and is run as a [DesktopCommand]
///   (lib/shell/desktop/desktop_commands.dart).
///
/// Nothing here is called outside the Mac app ([runsAsMacApp]): in a test, or on a phone, every call is a no-op.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/mac_app.dart';
import 'desktop_commands.dart';

class MacWindow {
  MacWindow._();

  /// The one window the Mac app has.
  static final MacWindow instance = MacWindow._();

  static const MethodChannel channel = MethodChannel('ghost_md/window');

  bool _attached = false;
  ({double x, double centre})? _lights;

  /// Whether the window is full screen, where it has no buttons of its own to make room for.
  final ValueNotifier<bool> fullScreen = ValueNotifier<bool>(false);

  /// Begins to hear the window (its menu, its full screen). Once, from `main`; a no-op outside the Mac app.
  void attach({bool? macApp}) {
    if (_attached || !(macApp ?? runsAsMacApp)) return;
    _attached = true;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'menu':
          final command = desktopCommandNamed(call.arguments is String ? call.arguments as String : '');
          if (command != null) desktopCommands.run(command);
        case 'fullScreen':
          fullScreen.value = call.arguments == true;
      }
      return null;
    });
    unawaited(_ask<Map<Object?, Object?>>('state').then((state) => fullScreen.value = state?['fullScreen'] == true));
  }

  Future<T?> _ask<T>(String method, [Object? args]) async {
    if (!_attached) return null;
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Where the page's top row is: its start gutter and its centre from the window's top, in logical pixels. The
  /// window's three buttons are centred on it. Said again only when it moves.
  void lights({required double x, required double centre}) {
    if (_lights == (x: x, centre: centre)) return;
    _lights = (x: x, centre: centre);
    unawaited(_ask<void>('lights', {'x': x, 'centre': centre}));
  }

  /// The drag strip was pressed and moved: the window follows the pointer, as under a title bar.
  void drag() => unawaited(_ask<void>('drag'));

  /// The drag strip was double clicked: what the person chose for a title bar's double click (zoom, by default).
  void zoom() => unawaited(_ask<void>('zoom'));

  /// A debug build's only (lib/shell/desktop/mac_tour.dart): the window as drawn, saved as a PNG; the file's path.
  Future<String?> snapshot(String name) => _ask<String>('snapshot', {'name': name});

  /// A debug build's only: a key pressed in this window alone.
  Future<bool> press(String key, {bool command = false, bool shift = false}) async => await _ask<bool>('key', {'key': key, 'command': command, 'shift': shift}) ?? false;

  /// A debug build's only: the window at another size.
  Future<void> resize(double width, double height) => _ask<void>('resize', {'width': width, 'height': height});

  /// A debug build's only: the app ended.
  Future<void> quit() => _ask<void>('quit');
}
