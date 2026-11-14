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

  // --- the message field's own (macos/Runner/DeskChannels.swift, DeskSound.swift) --------------------------------

  /// The Mac's panel for choosing pictures: the paths chosen, none where it was put away.
  static Future<List<String>> pickPictures({int most = 5}) async {
    try {
      return [for (final p in (await _system.invokeMethod<List>('pickPictures', {'most': most})) ?? const []) '$p'];
    } catch (_) {
      return const [];
    }
  }

  /// Opens the Mac's own "Emoji & Symbols": what is chosen there is typed where the cursor is.
  static Future<void> emoji() async {
    try {
      await _system.invokeMethod('emoji');
    } catch (_) {}
  }

  /// Starts recording a voice message with the Mac's microphone, which stops itself at [bytes]: `ok`, or `denied`
  /// where macOS was told no, or an `error` in words.
  static Future<Map> voiceStart(int bytes) async {
    try {
      return (await _system.invokeMapMethod<Object?, Object?>('voiceStart', {'bytes': bytes})) ?? const {'ok': false};
    } on MissingPluginException {
      return const {'ok': false, 'error': 'This copy of the app has no recorder'};
    }
  }

  /// How loud it is now (`level`, 0 to 1) and whether the recording is as long as it may be (`full`).
  static Future<Map> voiceLevel() async {
    try {
      return (await _system.invokeMapMethod<Object?, Object?>('voiceLevel')) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> voiceCancel() async {
    try {
      await _system.invokeMethod('voiceCancel');
    } catch (_) {}
  }

  /// Ends the recording: its bytes (AAC in an `.m4a`), or null where there is nothing worth keeping.
  static Future<Uint8List?> voiceStop() async {
    try {
      return await _system.invokeMethod<Uint8List>('voiceStop');
    } catch (_) {
      return null;
    }
  }

  /// Plays a message's sound ([bytes] the first time; null goes on with the one paused). Null, or why it cannot.
  static Future<String?> voicePlay(int part, Uint8List? bytes) async {
    try {
      return await _system.invokeMethod<String>('voicePlay', {'part': part, 'bytes': bytes});
    } on MissingPluginException {
      return 'this copy of the app has no player';
    }
  }

  static Future<void> voicePause() async {
    try {
      await _system.invokeMethod('voicePause');
    } catch (_) {}
  }

  static Future<void> voiceHalt() async {
    try {
      await _system.invokeMethod('voiceHalt');
    } catch (_) {}
  }

  static Future<int> voiceLength(Uint8List bytes) async {
    try {
      return (await _system.invokeMethod<num>('voiceLength', {'bytes': bytes}))?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Where the sound being played has got to, as the Mac says it (DeskSound.swift `heard`): handed to [heard].
  static void listenToVoice(void Function(Map state) heard) {
    _system.setMethodCallHandler((call) async {
      if (call.method == 'voice' && call.arguments is Map) heard(call.arguments as Map);
      return null;
    });
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
