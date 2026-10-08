/// A meeting with the device's own sound in it, beside the microphone. A port of `src/app/capture/systemSound.ts`.
///
/// One switch, `meetingSound` (core/preferences.dart), off by default. On the Mac it is everything the Mac plays,
/// through a Core Audio process tap (macOS 14.2 and later; an older Mac records a meeting's microphone, and says
/// so): the other side of a call is in the tape and in the live words, because the core adds it into each microphone
/// chunk before the transcriber hears it. On Android it is other apps' sound through AudioPlaybackCapture (Android
/// 10 and later), which Android allows for media and games and never for calls. The words below say that plainly,
/// wherever the switch is.
///
/// Both arrived with native generation 25 ([meetingSoundGeneration]): an older binary offers neither, and records
/// the microphone as before.
///
/// What differs: the web reads its platform, its binary and its bridge from modules (`core/platform.ts`,
/// `core/nativeGeneration.ts`, `core/tauri.ts`, `core/host.ts`). Here they are what a [SystemSound] is made with,
/// and the module's functions are its methods, under the web's names. The Mac's four commands are a
/// [SystemSoundBackend]. The hook `useMeetingSoundSupport` is React's and is left for the widget that wants it:
/// it is [SystemSound.meetingSoundSupport], awaited once.
library;

/// The binary generation with the Mac's tap commands and Android's `startMeetingWith` and `meetingSound`
/// (`MEETING_SOUND_GENERATION`).
const int meetingSoundGeneration = 25;

class SoundSupport {
  const SoundSupport({required this.supported, required this.reason});

  final bool supported;

  /// Why not, in the app's words; null when it is supported.
  final String? reason;

  @override
  bool operator ==(Object other) => other is SoundSupport && other.supported == supported && other.reason == reason;

  @override
  int get hashCode => Object.hash(supported, reason);

  @override
  String toString() => 'SoundSupport(supported: $supported, reason: $reason)';
}

class SoundStarted {
  const SoundStarted({required this.capturing, required this.reason});

  final bool capturing;
  final String? reason;

  @override
  bool operator ==(Object other) => other is SoundStarted && other.capturing == capturing && other.reason == reason;

  @override
  int get hashCode => Object.hash(capturing, reason);

  @override
  String toString() => 'SoundStarted(capturing: $capturing, reason: $reason)';
}

/// Said in the recorder when the tap is open and nothing has come through it for a while (`NOTHING_FROM_THE_MAC`).
const String nothingFromTheMac =
    "Nothing from this Mac's sound yet. If it asked, allow Ghost.md in System Settings › Privacy & Security › Screen & System Audio Recording.";

/// The Mac's tap, as the core answers for it: the web's four `invoke` commands, each of which may reject.
abstract class SystemSoundBackend {
  /// `system_audio_available`.
  Future<SoundSupport> available();

  /// `system_audio_start`.
  Future<SoundStarted> start();

  /// `system_audio_stop`.
  Future<void> stop();

  /// `system_audio_status`.
  Future<({bool capturing, bool heard})> status();
}

/// A meeting's own sound on this device: where it can be had, what it is called, and the Mac's tap.
class SystemSound {
  const SystemSound({
    required this.backend,
    required this.isAndroid,
    required this.isMacApp,
    required this.hasNativeGeneration,
    required this.meetingSoundOnHost,
  });

  /// The core's commands, or null where there is no native core to ask (the web's `!isTauri()`).
  final SystemSoundBackend? backend;

  /// `core/platform.ts` `isAndroid` and `isMacApp`.
  final bool isAndroid;
  final bool isMacApp;

  /// `core/nativeGeneration.ts` `hasNativeGeneration`.
  final Future<bool> Function(int wanted) hasNativeGeneration;

  /// Whether this phone can put other apps' sound in a meeting, as the activity said; null where it cannot be asked
  /// (`core/host.ts` `meetingSoundOnHost`).
  final SoundSupport? Function() meetingSoundOnHost;

  /// What the switch is called, and what it says under it, on this platform.
  ({String label, String hint}) meetingSoundWords() {
    if (isAndroid) {
      return (
        label: 'Include sound from other apps',
        hint: 'Android lets Ghost.md hear media and games, never calls. It asks to share your screen each time; only the sound is kept.',
      );
    }
    return (
      label: "Record the computer's sound too",
      hint: 'Both sides of a call: what this Mac plays goes into the recording with the microphone. macOS asks the first time.',
    );
  }

  /// Whether this device can put its own sound in a meeting: null where the question does not arise (no native core,
  /// iOS, an older binary).
  Future<SoundSupport?> meetingSoundSupport() async {
    final backend = this.backend;
    if (backend == null || !(isAndroid || isMacApp)) return null;
    if (!(await hasNativeGeneration(meetingSoundGeneration))) return null;
    if (isAndroid) return meetingSoundOnHost();
    try {
      return await backend.available();
    } catch (_) {
      return null;
    }
  }

  /// Whether a phone's meeting should ask for other apps' sound: the switch on, and a binary and an Android that
  /// have it.
  Future<bool> wantsOtherApps(bool on) async {
    if (!on || !isAndroid) return false;
    return (await meetingSoundSupport())?.supported == true;
  }

  // ---- the Mac's tap, for the recorder in meeting mode ------------------------------------------------------------

  /// Opens the tap for the running capture: after the capture's start has resolved, since a start closes any tap a
  /// reloaded page left behind. The first one on a Mac raises the "System Audio Recording Only" consent.
  Future<SoundStarted> startComputerSound() async {
    try {
      return await _commands.start();
    } catch (failure) {
      return SoundStarted(capturing: false, reason: _thrown(failure));
    }
  }

  /// Closes it; the capture's stop and cancel close it too, so this is for the switch turned off mid-meeting.
  Future<void> stopComputerSound() async {
    try {
      await _commands.stop();
    } catch (_) {
      // Nothing was open, or nothing answers: closed either way.
    }
  }

  /// Whether it is open, and whether anything but silence has come through it (a refused consent delivers zeros).
  Future<({bool capturing, bool heard})?> computerSoundStatus() async {
    try {
      return await _commands.status();
    } catch (_) {
      return null;
    }
  }

  /// The commands, or the rejection the web's `invoke` makes where there is nothing to invoke.
  SystemSoundBackend get _commands => backend ?? (throw StateError('no native core for system audio'));
}

/// A thrown thing as JavaScript's `String(failure)` says it: an error is "Error: " and its message.
String _thrown(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return 'Error: ${text.substring(lead.length)}';
  }
  return text;
}
