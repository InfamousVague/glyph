/// The walkthrough's voice, played (Matt, 2026-10-27: "a friendly elevenlabs v4 voice explaining each section"): each
/// page's words, said as the page shows, stopped as it goes.
///
/// The files were made at build time (tool/onboarding_voice.py; the words in narration.dart) and ship in the app's
/// assets, so the voice needs no key and no network. They are played over the app's own sounds channel,
/// `ghost_md/sounds` (lib/sounds/sounds.dart), with two more methods of its own there: `narrate`, which plays a long
/// clip on the device's media player rather than the pool the short sounds are kept in, and `hush`, which stops it.
/// No new package: the app plays everything over channels of its own.
///
/// When it plays: as soon as a page shows. The app is not a web page, so nothing asks for a tap first; a person who
/// would rather read switches the voice off with the speaker in the guide's bar, and that is remembered on this
/// device (it is the device's sound, not a preference to sync). The native half keeps quiet where the device asks
/// for quiet: on Android the ringer on silent or vibrate, Do Not Disturb, or a call, the same rules the app's
/// sounds keep. Where there is no native half (an iPhone for now, the web, a test) nothing plays, and the words are on
/// the page all the same.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/stored.dart';
import 'narration.dart';
import 'pages.dart';

/// The key that says the voice was switched off on this device.
const String guideMutedKey = 'glyph-guide-voice-off';

/// The device's player of a long clip, as [Narrator] asks it.
abstract class NarrationOutput {
  /// Plays [bytes], kept under [key], from the start, in place of whatever it was playing. Answers whether it plays:
  /// false where the device asks for quiet.
  Future<bool> narrate(String key, Uint8List bytes);

  /// Stops whatever it is playing.
  Future<void> hush();
}

/// [NarrationOutput] over the app's `ghost_md/sounds` channel.
class ChannelNarrationOutput implements NarrationOutput {
  const ChannelNarrationOutput([this.channel = const MethodChannel('ghost_md/sounds')]);
  final MethodChannel channel;

  @override
  Future<bool> narrate(String key, Uint8List bytes) async => await channel.invokeMethod<bool>('narrate', {'key': key, 'bytes': bytes}) ?? false;

  @override
  Future<void> hush() => channel.invokeMethod<void>('hush');
}

/// The device's player where this build has one: Android and the Mac, as for the app's sounds.
NarrationOutput? defaultNarrationOutput() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.macOS => const ChannelNarrationOutput(),
    _ => null,
  };
}

/// Says each page as it shows. One is made by the guide and let go with it, which hushes it.
class Narrator extends ChangeNotifier {
  Narrator({NarrationOutput? output, bool useDefaultOutput = true, Future<ByteData> Function(String asset)? load})
      : output = output ?? (useDefaultOutput ? defaultNarrationOutput() : null),
        _load = load ?? rootBundle.load;

  /// The player; null where there is none, and nothing is said.
  final NarrationOutput? output;
  final Future<ByteData> Function(String asset) _load;

  GuidePage? _page;
  GuidePage? _saying;

  /// Each turn of the pages counts one, so a load that comes back after the page has turned is not played.
  int _turn = 0;

  /// Whether the voice is off on this device.
  bool get muted => stored.readText(guideMutedKey) == '1';

  /// The page being said now, as far as this side knows: null when hushed, muted or never begun. The clip's own end
  /// is the player's, and not reported back: the words on the page are what is read once it stops.
  GuidePage? get saying => _saying;

  /// [page] is on screen: say it, unless the voice is off. The page that was being said stops first.
  void show(GuidePage page) {
    if (_page == page && _saying == page) return;
    _page = page;
    unawaited(_say(page));
  }

  /// The voice on or off, remembered on this device. Off stops it at once; on says the page showing from the start.
  void setMuted(bool off) {
    stored.writeText(guideMutedKey, off ? '1' : null);
    notifyListeners();
    final page = _page;
    if (off) {
      unawaited(hush());
    } else if (page != null) {
      unawaited(_say(page));
    }
  }

  /// Stops the voice: the guide has gone, the app has left the screen, or a recording has begun.
  Future<void> hush() async {
    _turn++;
    final was = _saying;
    _saying = null;
    if (was != null) notifyListeners();
    try {
      await output?.hush();
    } catch (_) {
      // A binary from before the channel had `hush`: there was nothing playing to stop.
    }
  }

  Future<void> _say(GuidePage page) async {
    await hush();
    final output = this.output;
    if (output == null || muted) return;
    final turn = _turn;
    final asset = narrationAsset(page);
    try {
      final data = await _load(asset);
      if (turn != _turn) return;
      final played = await output.narrate(asset, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      if (turn != _turn || !played) return;
      _saying = page;
      notifyListeners();
    } catch (_) {
      // No file for the page (its voice not made yet) or no player: the page's words are there to read.
    }
  }

  @override
  void dispose() {
    // Hushed without telling anyone: nobody is listening now.
    _turn++;
    _saying = null;
    final output = this.output;
    if (output != null) unawaited(output.hush().catchError((Object _) {}));
    super.dispose();
  }
}
