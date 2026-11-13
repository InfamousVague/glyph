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
