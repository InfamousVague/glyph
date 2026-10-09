/// Voice for one running app: what `App.tsx` gets by importing the recorder's modules (`capture/engine.ts`,
/// `capture/refine.ts`, `capture/meetingLive.ts`, `capture/useVoiceModel.ts`, `core/host.ts`, `core/ai.ts`), made
/// once over the Rust core and the phone's own halves, and handed to the root as a [Voice].
///
/// What is made, each from its own piece:
/// - the transcriber ([CaptureEngine] over [NativeCaptureBackend]: Whisper in the core) and the better words' queue
///   ([Refining]), over the app's own library ([LibraryRecorderStore]);
/// - the phone's microphone for a take ([DeviceMic], through Dart, as the recorder as ported expects), opened by a
///   recorder screen that is on screen and by nothing else: **no always-on microphone**;
/// - the meeting service's store ([MeetingLive] over [DeviceMeetingHost]) and what the screens ask of the service
///   ([MeetingService]);
/// - the language model's engine ([NativeAiBackend], made the app's with `useAiBackend`) and the catalogue with what
///   is on this phone ([ModelsController]), for Settings' AI page.
///
/// **Where a model comes from.** A model's download is the one thing here that crosses a network, and a build that
/// is not a release never asks the real mirrors for one ([voiceMirrors]): it is given its own with
/// `--dart-define=GHOST_MODELS=http://10.0.2.2:8765` (a server on this Mac, as lib/main_voice.dart's), and with
/// none it has no mirror at all, so Get says it could not and the models already on the phone are used as they are.
///
/// What is not here yet, each a seam:
/// - **Summaries and the review after a recording** (`ai/summaries.ts`, `ai/review.ts`): lib/ai has neither yet, so
///   [Recorder.enqueueSummary] and [Recorder.reviewAvailable] are the recorder's own no-ops, a meeting's write-up is
///   handed no job configuration (`keepJobConfig`), and a finished write-up's result is not landed in its note.
/// - **A tape's player** (`tapes/useTape.ts`'s `<audio>`): lib/tapes/player.dart's `TapePlayer` has no phone half,
///   so the tape at the top of a spoken note is not drawn.
/// - **The plugins' spoken formattings and tips** ([Recorder.spokenFormats], [Recorder.pluginTips]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../ai/backend.dart' as ai;
import '../ai/native_backend.dart';
import '../ai/summary_keep.dart' show keptText, summaryUnchanged;
import '../capture/audio.dart';
import '../capture/device_mic.dart';
import '../capture/engine.dart';
import '../capture/instruction_intent.dart' show inferInstruction;
import '../capture/meeting.dart' show canRecordMeeting;
import '../capture/meeting_host.dart';
import '../capture/meeting_live.dart';
import '../capture/native_backend.dart';
import '../capture/recorder.dart';
import '../capture/refine.dart';
import '../capture/system_sound.dart' show SoundSupport;
import '../core/library.dart';
import '../core/native/ghost_core.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../editor/media/clip_refs.dart' show TapeIds;
import '../tapes/player.dart' show markAudioRemoved;

/// `--dart-define=GHOST_MODELS=http://…`: where this build fetches a voice or language model from. Empty in every
/// build that was not given one.
const String ghostModelsDefine = String.fromEnvironment('GHOST_MODELS');

/// `--dart-define=GHOST_MIC_FIXTURE=1`, a debug build's only: a take plays `<dataDir>/fixture.wav` in place of the
/// device's microphone where that file is there, for an emulator started without audio (lib/capture/device_mic.dart
/// `testWav`).
const bool ghostMicFixtureDefine = bool.fromEnvironment('GHOST_MIC_FIXTURE');

/// The mirrors a model is fetched from in this build (see the library's header): null is the web app's own two, for
/// a release; a list is the whole list. A mirror that names the real hosts is refused in a build that is not a
/// release, as the account's service is (lib/root/account_wiring.dart `accountBase`).
List<String>? voiceMirrors(String define, {bool debug = !kReleaseMode}) {
  final given = define.trim().replaceFirst(RegExp(r'/+$'), '');
  if (given.isEmpty) return debug ? const <String>[] : null;
  final uri = Uri.tryParse(given);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return debug ? const <String>[] : null;
  final host = uri.host.toLowerCase();
  final real = host == 'attack.fm' || host.endsWith('.attack.fm') || host == 'ghostmarkdown.com' || host.endsWith('.ghostmarkdown.com') || host == 'huggingface.co' || host.endsWith('.huggingface.co');
  if (debug && real) return const <String>[];
  return [given];
}

/// The phone's meeting service and its capture bridge, as the app asks them (`core/host.ts`'s meeting functions,
/// each with the bridge's own answer). [DeviceMeetingHost] behind [DeviceMeetingService] on a phone; a test's own.
abstract class MeetingService {
  /// "started", "permission", "recording", or a reason in the app's words (`startMeetingOnHost`).
  Future<String> startMeeting(String noteId, String title, {bool otherApps = false});
  Future<void> stopMeeting();
  Future<void> discardMeeting();

  /// "allowed", "asked" or "blocked" (`requestNotifications`).
  Future<String> requestNotifications();

  /// The app has deleted a note the notification's Discard threw away (`forgetDiscardedOnHost`).
  Future<void> forgetDiscarded(String noteId);

  /// Whether this phone can put other apps' sound in a meeting, and why not; null where it will not say.
  Future<SoundSupport?> meetingSound();
  Future<bool> isLocked();
  Future<void> endCapture({required bool leave});
}

/// [MeetingService] over the phone's own bridge.
class DeviceMeetingService implements MeetingService {
  const DeviceMeetingService(this.host);
  final DeviceMeetingHost host;

  @override
  Future<String> startMeeting(String noteId, String title, {bool otherApps = false}) => host.startMeeting(noteId, title, otherApps: otherApps);

  @override
  Future<void> stopMeeting() => host.stopMeeting();

  @override
  Future<void> discardMeeting() => host.discardMeeting();

  @override
  Future<String> requestNotifications() => host.requestNotifications();

  @override
  Future<void> forgetDiscarded(String noteId) => host.forgetDiscarded(noteId);

  @override
  Future<SoundSupport?> meetingSound() => host.meetingSound();

  @override
  Future<bool> isLocked() => host.isLocked();

  @override
  Future<void> endCapture({required bool leave}) => host.endCapture(leave: leave);
}

/// What `main` hands the root to make a [Voice] from: the core, and the phone's halves it attached before the first
/// frame.
class VoiceMaking {
  const VoiceMaking({required this.core, required this.host, required this.dataDir, this.mirrors, this.assistant = false, this.launch = ''});

  final GhostCore core;
  final DeviceMeetingHost host;
  final String dataDir;

  /// Where a model is fetched from ([voiceMirrors]).
  final List<String>? mirrors;

  /// Whether this build has the phone assistant and the side key at all (off unless built with GHOST_ASSISTANT=1).
  final bool assistant;

  /// What this launch was for, read once: "capture", "meeting" or "" (`takeCaptureLaunch`).
  final String launch;

  /// Attaches to the phone and reads what the launch was for. Off Android the host has no service and answers so.
  static Future<VoiceMaking> attach(GhostCore core, {required String dataDir, List<String>? mirrors}) async {
    final host = await DeviceMeetingHost.attach();
    var assistant = false;
    var launch = '';
    if (host.hasMeetings) {
      try {
        assistant = await host.assistantEnabled();
        launch = await host.takeLaunch();
      } catch (_) {
        // A phone half that will not say: no side key, and a launch for nothing.
      }
    }
    return VoiceMaking(core: core, host: host, dataDir: dataDir, mirrors: mirrors, assistant: assistant, launch: launch);
  }
}

/// Voice, as the root holds it: the recorder its screens are drawn over, and what the app asks of the phone about a
/// meeting. A test makes one over a scripted recorder and a service of its own.
class Voice {
  Voice({required this.recorder, this.service, this.models, this.assistant = false, this.launch = '', this.captureKey, this.canMeet = false, this.sound, this.removeAudio, this.dispose_});

  /// Everything the recorder's screens reach (lib/capture/recorder.dart).
  final Recorder recorder;

  /// The phone's meeting service, or null where there is none (a Mac, a test without one).
  final MeetingService? service;

  /// The catalogue with what is on this phone, for Settings' AI page; null where there is no engine.
  final ai.ModelsController? models;

  /// Whether this build has the phone assistant and the side key (`GHOST_ASSISTANT=1`): only then is a launch or a
  /// key press ever a recording. Never an always-on microphone either way.
  final bool assistant;

  /// What this launch was for: "capture", "meeting" or "".
  final String launch;

  /// Told each time the side key asks for a capture while the app is open (`answerHost('capture', …)`); null where
  /// nothing can say.
  final Stream<void>? captureKey;

  /// Whether a meeting can be recorded here (capture/meeting.dart `canRecordMeeting`), asked once by [start].
  bool canMeet;

  /// Whether this phone can put other apps' sound in a meeting, read by [start].
  SoundSupport? sound;

  /// Removes the audio of these notes' tapes from this device, their words and phrases kept, and answers which
  /// went (`core/recordings.ts` `deleteRecordings`); null where nothing can.
  final Future<List<String>> Function(List<String> ids)? removeAudio;

  /// Whether the phone is locked, as last asked ([readLocked]): the recorder's screens ask at once and cannot wait.
  bool locked = false;

  final void Function()? dispose_;

  MeetingLive? get live => recorder.meetingLive;

  /// Asks the phone whether it is locked, before a recorder's screen that reads it is put up.
  Future<void> readLocked() async {
    try {
      locked = await service?.isLocked() ?? false;
    } catch (_) {
      locked = false;
    }
  }

  /// As the app opens: the voice model's file is looked for (and fetched where this build has a mirror), the better
  /// words' queue is wired to the notes, the models on the phone are read, and whether a meeting can be recorded
  /// here. Opens no microphone.
  Future<void> start({VoidCallback? notesChanged}) async {
    recorder.start(notesChanged: notesChanged);
    unawaited(models?.refresh());
    final service = this.service;
    if (service == null) return;
    try {
      sound = await service.meetingSound();
    } catch (_) {
      sound = null;
    }
    await readLocked();
  }

  void dispose() {
    recorder.dispose();
    models?.dispose();
    dispose_?.call();
  }

  /// A [Voice] over the core and the phone ([making]), writing into [library]. [published] says whether a note has
  /// a shared link, which a recording over the lock screen never writes to.
  static Future<Voice> make(VoiceMaking making, {required NoteLibrary library, required Stored kept, bool Function(String id)? published}) async {
    final core = making.core;
    final host = making.host;
    final capture = NativeCaptureBackend(core, mirrors: making.mirrors);
    final engine = NativeAiBackend(core, mirrors: making.mirrors);
    ai.useAiBackend(engine);

    final store = LibraryRecorderStore(library);
    late final Voice voice;
    final live = host.hasMeetings ? MeetingLive(host: host, writeUpRunningNow: () => false) : null;
    final unbind = live == null ? null : host.bind(live);

    final refining = Refining(
      backend: capture,
      hasNativeGeneration: ai.hasNativeGeneration,
      preferences: () => preferences.value,
      stored: kept,
      getNote: store.getNote,
      updateNote: store.updateNote,
      setNoteRecording: store.setNoteRecording,
      keptText: keptText,
      summaryUnchanged: summaryUnchanged,
      writeUpRunning: () => live?.writeUpRunning() ?? false,
    );

    // The scripted WAV in place of the device, in a debug build that asked for it and has the file.
    final fixture = kDebugMode && ghostMicFixtureDefine ? File('${making.dataDir}/fixture.wav') : null;
    final keys = StreamController<void>.broadcast();
    final screenOff = <VoidCallback>{};
    final heard = host.events.listen((event) {
      switch (event.name) {
        // Only a build with the assistant is ever asked for a capture by the phone.
        case 'capture':
          if (making.assistant) keys.add(null);
        case 'screenOff':
          for (final listener in screenOff.toList()) {
            listener();
          }
      }
    });

    final recorder = Recorder(
      engine: CaptureEngine(backend: capture, hasNativeGeneration: ai.hasNativeGeneration),
      store: store,
      host: RecorderHost(
        isLocked: () => voice.locked,
        // The screen is kept on while a take runs, and its going off stops it; "Press the side key to stop" is
        // said only where this build has the side key.
        setCapturing: (on) {
          if (!host.hasMeetings) return false;
          unawaited(host.setCapturing(on).then<void>((_) {}, onError: (Object _) {}));
          return making.assistant;
        },
        endCapture: (locked) {
          if (host.hasMeetings) unawaited(host.endCapture(leave: locked).then<void>((_) {}, onError: (Object _) {}));
        },
        onScreenOff: (listener) {
          screenOff.add(listener);
          return () => screenOff.remove(listener);
        },
        haptic: (kind) => fireMotor(switch (kind) {
          'medium' => HapticKind.medium,
          'selection' => HapticKind.selection,
          'success' => HapticKind.success,
          'warning' => HapticKind.warning,
          'error' => HapticKind.error,
          _ => HapticKind.light,
        }),
        isAndroid: Platform.isAndroid,
      ),
      refining: refining,
      meetingLive: live,
      tapes: TapeIds(kept),
      openMicrophone: DeviceMic.supported
          ? (handlers) => openMicrophone(
                handlers,
                open: (constraints, {required sampleRate, required chunk}) =>
                    DeviceMic.openWith(constraints, testWav: fixture != null && fixture.existsSync() ? fixture.path : null),
              )
          : null,
      published: published ?? ((_) => false),
      // A command the rules could not place, read by the model on this phone; a long job in the core.
      startInference: (words) => inferInstruction(
        words,
        invoke: (command, args) async => command == 'ai_infer_command' ? (await core.startJob(command, args)).done : core.invoke(command, args),
        preferredModel: preferences.value.formatModel,
      ),
      canRecordMeeting: host.hasMeetings &&
          await canRecordMeeting(native: true, isIOS: Platform.isIOS, isAndroid: Platform.isAndroid, isMobile: Platform.isAndroid || Platform.isIOS, hasNativeGeneration: ai.hasNativeGeneration),
      warn: debugPrint,
    );

    voice = Voice(
      recorder: recorder,
      service: host.hasMeetings ? DeviceMeetingService(host) : null,
      models: ai.ModelsController(),
      assistant: making.assistant,
      launch: making.launch,
      captureKey: keys.stream,
      canMeet: recorder.canRecordMeeting,
      removeAudio: (ids) async {
        if (ids.isEmpty) return const <String>[];
        final done = await engine.recordingDelete(ids);
        markAudioRemoved(done.removed);
        return done.removed;
      },
      dispose_: () {
        unbind?.call();
        unawaited(heard.cancel());
        unawaited(keys.close());
      },
    );
    return voice;
  }
}
