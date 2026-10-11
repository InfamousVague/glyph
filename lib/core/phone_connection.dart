/// Whether the phone has a connection, and the moment one comes back: what the page asked its WebView
/// (`navigator.onLine`, and the window's `online` event). The fills' queue is its one reader (lib/ai/fills/queue.dart
/// `startFills`'s `onLine` and `onOnline`): a blank left "Waiting for a connection" goes on when one is back, where
/// it waited for the queue's one-minute look.
///
/// [Connection] is what the app is handed, so a test brings its own. [PhoneConnection] is the phone's
/// (`ghost_md/connection`, android/…/ghost_md/Connection.kt): the answer is read once as it starts, and kept as the
/// phone says `online` and `offline`, so [Connection.onLine] answers at once, as the page's property did. Where
/// nothing answers the channel (a Mac, an iPhone, a test) it is online and never says otherwise, which is what the
/// queue takes when it is given no connection at all.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// The connection as the app reads it.
abstract class Connection {
  /// Whether there is a connection now, as far as the phone can tell (`navigator.onLine`).
  bool get onLine;

  /// Calls [listener] each time a connection comes back (the window's `online` event); answers the way to stop.
  VoidCallback onOnline(VoidCallback listener);
}

const MethodChannel connectionChannel = MethodChannel('ghost_md/connection');

/// The phone's own answer.
class PhoneConnection implements Connection {
  PhoneConnection({MethodChannel channel = connectionChannel}) : _channel = channel;

  final MethodChannel _channel;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  bool _onLine = true;

  @override
  bool get onLine => _onLine;

  @override
  VoidCallback onOnline(VoidCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Hears the phone from here on, and asks it once how things stand now. Answers itself, for whoever makes it.
  PhoneConnection start() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'online':
          final was = _onLine;
          _onLine = true;
          if (!was) _tell();
        case 'offline':
          _onLine = false;
      }
      return null;
    });
    unawaited(_channel.invokeMethod<bool>('online').then<void>((now) {
      if (now != null) _onLine = now;
    }, onError: (Object _) {
      // No phone half behind the channel: online, as far as anyone here can tell.
    }));
    return this;
  }

  void _tell() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }
}
