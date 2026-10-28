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
/// device (it is the device's sound, not a preference to sync). The native half keeps quiet only in a call or while
/// something records: it is media the person opened the walkthrough to hear, which silent and Do Not Disturb let play
/// (2026-10-28, on the Fold, whose Sleep mode had turned Do Not Disturb on: "The welcome audio isn't playing now").
/// Where there is no native half (an iPhone for now, the web, a test) nothing plays, and the words are on
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

/// One clip to say: where it is in the app's assets, and how long it runs, so a clip after it waits its turn.
typedef VoiceClip = ({String asset, Duration? length});

/// Says clips one after another over the device's player, and stops them as asked: the walkthrough's [Narrator], and
/// the Academy's voice (lib/academy/academy_screen.dart; Matt, 2026-10-28: "Add the voiceover to the academy
/// sections"). One switch keeps both quiet, [guideMutedKey], remembered on the device: a person who would rather read
/// the tour would rather read the lessons too, and the speaker in either bar turns it back on for both.
///
/// The player has one clip at a time and says nothing of its end, so a clip after another waits the first one's
/// [VoiceClip.length] and a breath before it starts; a clip with no length is the last said.
class VoiceOver extends ChangeNotifier {
  VoiceOver({NarrationOutput? output, bool useDefaultOutput = true, Future<ByteData> Function(String asset)? load})
      : output = output ?? (useDefaultOutput ? defaultNarrationOutput() : null),
        _load = load ?? rootBundle.load;

  /// The player; null where there is none, and nothing is said.
  final NarrationOutput? output;
  final Future<ByteData> Function(String asset) _load;

  /// The pause between one clip and the next.
  static const Duration breath = Duration(milliseconds: 450);

  /// What was asked for last, said again from its start when the voice is switched back on.
  List<VoiceClip>? _asked;
  String? _saying;
  Timer? _waiting;

  /// Each hush counts one, so a load or a wait that comes back after it is not played.
  int _turn = 0;

  /// Whether the voice is off on this device.
  bool get muted => stored.readText(guideMutedKey) == '1';

  /// The asset being said now, as far as this side knows: null when hushed, muted or never begun. The clip's own end
  /// is the player's, and not reported back.
  String? get sayingAsset => _saying;

  /// Says [clips], one after another, in place of whatever was being said; nothing while the voice is off.
  void say(List<VoiceClip> clips) {
    _asked = clips;
    unawaited(_play(clips));
  }

  /// The voice on or off, remembered on this device. Off stops it at once; on says what was asked for last, from its
  /// start.
  void setMuted(bool off) {
    stored.writeText(guideMutedKey, off ? '1' : null);
    notifyListeners();
    final asked = _asked;
    if (off) {
      unawaited(hush());
    } else if (asked != null) {
      unawaited(_play(asked));
    }
  }

  /// Stops the voice, and any clip waiting its turn: the page has gone, the app has left the screen, or a recording
  /// has begun.
  Future<void> hush() async {
    _turn++;
    _waiting?.cancel();
    _waiting = null;
    final was = _saying;
    _saying = null;
    if (was != null) notifyListeners();
    try {
      await output?.hush();
    } catch (_) {
      // A binary from before the channel had `hush`: there was nothing playing to stop.
    }
  }

  Future<void> _play(List<VoiceClip> clips) async {
    await hush();
    final output = this.output;
    if (output == null || muted) return;
    final turn = _turn;
    for (final (index, clip) in clips.indexed) {
      if (index > 0) {
        final before = clips[index - 1].length;
        if (before == null) return;
        // Cancelled by a hush, the wait never ends, and nothing after it is said.
        final waited = Completer<void>();
        _waiting = Timer(before + breath, waited.complete);
        await waited.future;
        if (turn != _turn) return;
      }
      try {
        final data = await _load(clip.asset);
        if (turn != _turn) return;
        final played = await output.narrate(clip.asset, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        if (turn != _turn) return;
        if (!played) {
          // The device asks for quiet: what comes after is not said either.
          if (_saying != null) {
            _saying = null;
            notifyListeners();
          }
          return;
        }
        _saying = clip.asset;
        notifyListeners();
      } catch (_) {
        // No file for the clip (its voice not made yet) or no player: the page's words are there to read.
        return;
      }
    }
  }

  @override
  void dispose() {
    // Hushed without telling anyone: nobody is listening now.
    _turn++;
    _waiting?.cancel();
    _saying = null;
    final output = this.output;
    if (output != null) unawaited(output.hush().catchError((Object _) {}));
    super.dispose();
  }
}

/// Says each walkthrough page as it shows. One is made by the guide and let go with it, which hushes it.
class Narrator extends VoiceOver {
  Narrator({super.output, super.useDefaultOutput, super.load});

  GuidePage? _page;

  /// The page being said now, as far as this side knows: null when hushed, muted or never begun. The words on the
  /// page are what is read once it stops.
  GuidePage? get saying {
    final asset = sayingAsset;
    return asset == null ? null : GuidePage.values.where((page) => narrationAsset(page) == asset).firstOrNull;
  }

  /// [page] is on screen: say it, unless the voice is off. The page that was being said stops first.
  void show(GuidePage page) {
    if (_page == page && saying == page) return;
    _page = page;
    say([(asset: narrationAsset(page), length: null)]);
  }
}
