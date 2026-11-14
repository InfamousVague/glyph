import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'link/link.dart';

/// What the Mac app asks of macOS (macos/Runner/DeskChannels.swift): the Mac's name, the Keychain, and Bonjour.
class MacPlatform {
  MacPlatform._();
  static const _system = MethodChannel('ghost_desktop/system');

  /// "Matt's MacBook Pro", or the host's name where macOS will not say.
  static Future<String> computerName() async {
    try {
      final name = await _system.invokeMethod<String>('name');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return Platform.localHostname.replaceAll(RegExp(r'\.local\.?$'), '').replaceAll('-', ' ');
  }

  static Future<String?> keyRead(String account) async {
    try {
      return await _system.invokeMethod<String>('keyRead', {'account': account});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> keyWrite(String account, String value) async {
    try {
      return await _system.invokeMethod<bool>('keyWrite', {'account': account, 'value': value}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// A picture of where a video starts and how long it runs (macos/Runner/DeskVideo.swift), from its bytes.
  static Future<Map?> videoPreview(int id, Uint8List bytes, String ending) async {
    try {
      return await _system.invokeMapMethod<Object?, Object?>('videoPreview', {'id': id, 'bytes': bytes, 'ext': ending});
    } catch (_) {
      return null;
    }
  }

  /// Opens a window that plays the video. Null when it is playing, or why it is not.
  static Future<String?> videoPlay(int id, Uint8List bytes, String ending, String title) async {
    try {
      return await _system.invokeMethod<String>('videoPlay', {'id': id, 'bytes': bytes, 'ext': ending, 'title': title});
    } on MissingPluginException {
      return 'this copy of the app has no player';
    }
  }

  static Future<void> keyDelete(String account) async {
    try {
      await _system.invokeMethod<bool>('keyDelete', {'account': account});
    } catch (_) {}
  }
}

/// Phones announcing `_ghostmsg._tcp` on this network, as Bonjour finds them. macOS asks the person once whether the
/// app may look on the local network; refused, nothing is found, and an address can be given by hand.
class BonjourFinder implements PeerFinder {
  static const _system = MethodChannel('ghost_desktop/system');
  static const _found = EventChannel('ghost_desktop/bonjour');

  List<Peer> _current = const [];
  StreamSubscription<dynamic>? _sub;
  void Function()? _onChange;

  @override
  List<Peer> get current => _current;

  @override
  set onChange(void Function()? listener) => _onChange = listener;

  @override
  void start() {
    _sub ??= _found.receiveBroadcastStream().listen((list) {
      final next = <Peer>[];
      for (final s in (list as List? ?? const [])) {
        final port = ((s as Map)['port'] as num?)?.toInt() ?? 0;
        // A numeric IPv4 address first: it needs no name looked up, and no interface named.
        final addresses = [for (final a in (s['addresses'] as List? ?? const [])) '$a']..sort((a, b) => (a.contains(':') ? 1 : 0) - (b.contains(':') ? 1 : 0));
        for (final a in addresses) {
          if (port > 0 && !a.startsWith('fe80')) next.add(Peer(a, port));
        }
      }
      _current = next;
      _onChange?.call();
    }, onError: (_) {});
    _system.invokeMethod('browse').catchError((_) {});
  }

  @override
  void stop() {
    _sub?.cancel();
    _sub = null;
    _system.invokeMethod('stopBrowsing').catchError((_) {});
  }
}
