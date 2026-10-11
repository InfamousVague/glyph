/// The Mac's own sound for a meeting, asked of the core: the [SystemSoundBackend] system_sound.dart is written
/// against, over native/src/kept/system_audio.rs. What `invoke('system_audio_available')` and its three friends
/// were to the web app's `capture/systemSound.ts`.
///
/// What differs: `system_audio_start` is a job here (it answers an id at once and its end is the answer), since
/// opening the tap is a round trip to the Mac's audio server and the app's worker isolate is serial.
///
/// Opening the tap listens to everything the Mac plays, and the first time raises macOS's "System Audio Recording
/// Only" consent. Nothing here opens it but [start], which the recorder calls only in a meeting with the switch on.
library;

import '../core/native/ghost_core.dart';
import 'system_sound.dart';

class CoreSystemSound implements SystemSoundBackend {
  const CoreSystemSound(this.core);

  final GhostCore core;

  static Map<String, Object?> _map(Object? said) => said is Map ? said.cast<String, Object?>() : const {};

  @override
  Future<SoundSupport> available() async {
    final said = _map(await core.invoke('system_audio_available'));
    return SoundSupport(supported: said['supported'] == true, reason: said['reason'] as String?);
  }

  @override
  Future<SoundStarted> start() async {
    final said = _map(await (await core.startJob('system_audio_start')).done);
    return SoundStarted(capturing: said['capturing'] == true, reason: said['reason'] as String?);
  }

  @override
  Future<void> stop() async {
    await core.invoke('system_audio_stop');
  }

  @override
  Future<({bool capturing, bool heard})> status() async {
    final said = _map(await core.invoke('system_audio_status'));
    return (capturing: said['capturing'] == true, heard: said['heard'] == true);
  }
}
