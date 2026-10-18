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
/// none its one mirror is [noMirror], an address on the phone itself where nothing listens, so Get says it could
/// not and the models already on the phone are used as they are. **Never an empty list**: the core reads a list
/// with no address in it as none given, and falls back to the web app's own two (native/src/models.rs `mirrors`).
///
/// The summaries and the review are lib/ai's ([Summaries], `reviewAvailable`, `keepJobConfigCurrent`): the queue is
/// made here over the same store, the phone's write-up and the better words' queue, the recorder asks it for a
/// take's summary and whether its review can run, a meeting's write-up is given its configuration, and
/// `MeetingLive.writeUpRunningNow` is the last look at the phone's jobs.
///
/// What is not here yet, each a seam:
/// - **The account's part of a summary**: `syncNow`, `syncSettled` and the feed's `record` are what [Voice.make] is
///   given, and nothing where the build has no account.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../ai/backend.dart' as ai;
import '../ai/job_config.dart' show keepJobConfigCurrent, sendJobConfig;
import '../ai/native_backend.dart';
import '../ai/review.dart' show reviewAvailable;
import '../ai/summaries.dart';
import '../ai/summary_keep.dart' show keptText, summaryUnchanged;
import '../capture/audio.dart';
import '../capture/device_mic.dart';
import '../capture/engine.dart';
import '../capture/instruction_intent.dart' show inferInstruction;
import '../capture/meeting.dart' show canRecordMeeting;
import '../capture/meeting_host.dart';
import '../capture/meeting_live.dart';
import '../capture/native_backend.dart';
import '../capture/ui/meeting_screen.dart' show NotificationsAnswer;
import '../capture/recorder.dart';
import '../capture/refine.dart';
import '../capture/spoken/inline.dart' show SpokenFormat;
import '../capture/tips.dart' show Tip;
import '../capture/core_system_sound.dart';
import '../capture/system_sound.dart' show SoundSupport, SystemSound;
import '../capture/voice_model.dart' show VoiceModel;
import '../core/mac_app.dart';
import '../core/library.dart';
import '../core/note.dart';
import '../core/native/ghost_core.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../editor/media/clip_refs.dart' show TapeIds;
import '../plugins/registry.dart' show plugins;
import '../tapes/player.dart' show markAudioRemoved;

/// `--dart-define=GHOST_MODELS=http://…`: where this build fetches a voice or language model from. Empty in every
/// build that was not given one.
const String ghostModelsDefine = String.fromEnvironment('GHOST_MODELS');

/// `--dart-define=GHOST_MIC_FIXTURE=true`, a debug build's only: a take plays `<dataDir>/fixture.wav` in place of the
/// device's microphone where that file is there, for an emulator started without audio (lib/capture/device_mic.dart
/// `testWav`).
const bool ghostMicFixtureDefine = bool.fromEnvironment('GHOST_MIC_FIXTURE');

/// The mirror of a build that may fetch from nowhere: the discard port on the phone itself, where nothing listens,
/// so a fetch fails at once and nothing leaves the device. The core's own tests use the same address for "nothing
/// there".
const String noMirror = 'http://127.0.0.1:9';

/// The mirrors a model is fetched from in this build (see the library's header): null is the web app's own two, for
/// a release; a list is the whole list, and is never empty. A mirror that names the real hosts is refused in a
/// build that is not a release, as the account's service is (lib/root/account_wiring.dart `accountBase`).
List<String>? voiceMirrors(String define, {bool debug = !kReleaseMode}) {
  const none = <String>[noMirror];
  final given = define.trim().replaceFirst(RegExp(r'/+$'), '');
  if (given.isEmpty) return debug ? none : null;
  final uri = Uri.tryParse(given);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return debug ? none : null;
  final host = uri.host.toLowerCase();
  final real = host == 'attack.fm' || host.endsWith('.attack.fm') || host == 'ghostmarkdown.com' || host.endsWith('.ghostmarkdown.com') || host == 'huggingface.co' || host.endsWith('.huggingface.co');
  if (debug && real) return none;
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

/// Asks the phone to let Ghost.md notify, and answers what it said (`core/host.ts` `requestNotifications`): allowed
/// where it already may; asked, where Android's prompt is now up (its answer arrives as the `notified` event,
/// [MeetingLive.notified]); blocked where no prompt can change it (refused twice, or turned off in the phone's
/// settings), which is also the answer of a phone with no service to ask and of one that would not say. The one
/// way the app asks: the meeting screen's Allow and Settings › Recording's, over [MeetingService.requestNotifications]
/// (android/…/ghost_md/MeetingBridge.kt). Whether it may notify is read again after, as the page reads it.
Future<NotificationsAnswer> askToNotify(MeetingService? service, MeetingLive live) async {
  if (live.canNotifyNow()) return NotificationsAnswer.allowed;
  if (service == null) return NotificationsAnswer.blocked;
  NotificationsAnswer answer;
  try {
    answer = switch (await service.requestNotifications()) {
      'allowed' => NotificationsAnswer.allowed,
      'asked' => NotificationsAnswer.asked,
      _ => NotificationsAnswer.blocked,
    };
  } catch (_) {
    answer = NotificationsAnswer.blocked;
  }
  live.canNotifyNow();
  return answer;
}

/// What `main` hands the root to make a [Voice] from: the core, and the phone's halves it attached before the first
/// frame.
/// What is being made, waited for [within] and no longer: the app's first frame does not wait on a phone that is
/// slow to attach its half of voice. `now` is it where it came in time. Where it did not, `later` is it when it does
/// come (null if it never does), so the run still has its recorder and its AI from then, where it had neither until
/// the app was started again. One that fails, in time or after, is said by [failed] and is null: never an error
/// nobody catches.
Future<({T? now, Future<T?>? later})> inTime<T extends Object>(Future<T> making, {Duration within = const Duration(seconds: 3), void Function(Object failure)? failed}) async {
  final made = making.then<T?>((made) => made, onError: (Object failure) {
    failed?.call(failure);
    return null;
  });
  var late = false;
  final now = await made.timeout(within, onTimeout: () {
    late = true;
    return null;
  });
  return (now: now, later: late ? made : null);
}

class VoiceMaking {
  const VoiceMaking({required this.core, required this.host, required this.dataDir, this.mirrors, this.assistant = false, this.launch = ''});

  final GhostCore core;
  final DeviceMeetingHost host;
  final String dataDir;

  /// Where a model is fetched from ([voiceMirrors]).
  final List<String>? mirrors;

  /// Whether the phone assistant and the side key are there at all: off, unless the build was made with
  /// GHOST_ASSISTANT=1 or a developer switched them on for this phone (lib/core/wip.dart).
  final bool assistant;

  /// What this launch was for, read once: "assist", "capture", "meeting" or "" (`takeCaptureLaunch`).
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
  Voice({required this.recorder, this.service, this.models, this.assistant = false, this.launch = '', this.captureKey, this.assistKey, this.canMeet = false, this.sound, this.removeAudio, this.summaries, this.cancelWriteUp, this.dispose_});

  /// Everything the recorder's screens reach (lib/capture/recorder.dart).
  final Recorder recorder;

  /// The phone's meeting service, or null where there is none (a Mac, a test without one).
  final MeetingService? service;

  /// The catalogue with what is on this phone, for Settings' AI page; null where there is no engine.
  final ai.ModelsController? models;

  /// Whether the phone assistant and the side key are there (a build made with `GHOST_ASSISTANT=1`, or a phone
  /// a developer switched them on for): only then is a launch or a key press ever a recording. Never an always-on microphone
  /// either way.
  final bool assistant;

  /// What this launch was for: "assist" (the phone's assistant), "capture" (Record note), "meeting" or "".
  final String launch;

  /// Told each time the launcher's Record note asks for a capture while the app is open (`answerHost('capture',
  /// …)`); null where nothing can say.
  final Stream<void>? captureKey;

  /// Told each time the phone's assistant (the side key held, the assistant gesture) asks while the app is open:
  /// Claude is talked to where it can answer, else it is a capture as [captureKey]'s (lib/root/capture_route.dart).
  final Stream<void>? assistKey;

  /// Whether a meeting can be recorded here (capture/meeting.dart `canRecordMeeting`), asked once by [start].
  bool canMeet;

  /// Whether this phone can put other apps' sound in a meeting, read by [start].
  SoundSupport? sound;

  /// The summary queue (lib/ai/summaries.dart), or null where there is no engine to summarise with.
  final Summaries? summaries;

  /// The notes were said to have changed: told to whoever follows it for the queue ([Summaries.onNotesChanged]).
  final Set<VoidCallback> _notesListeners = <VoidCallback>{};
  void notesChanged() {
    recorder.notesChanged();
    for (final listener in _notesListeners.toList()) {
      listener();
    }
  }

  VoidCallback? _stopSummaries;
  VoidCallback? _stopJobConfig;

  /// Removes the audio of these notes' tapes from this device, their words and phrases kept, and answers which
  /// went (`core/recordings.ts` `deleteRecordings`); null where nothing can.
  final Future<List<String>> Function(List<String> ids)? removeAudio;

  /// Stops a note's write-up on the phone, as its note goes into the trash (`core/host.ts` `cancelWriteUpOnHost`);
  /// null where the phone has no service to ask.
  final Future<void> Function(String noteId)? cancelWriteUp;

  /// Whether the phone is locked, as last asked ([readLocked]): the recorder's screens ask at once and cannot wait.
  /// Asked before a recorder is put up, and again when the phone says the answer changed under one ([phoneSaid]),
  /// so each use reads what is true then, as the page's `isLocked()` did by asking the phone each time.
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

  /// What the phone said without being asked, where it is about the lock: `unlocked` is a person unlocking the
  /// phone while a take runs (MeetingBridge.kt), the one moment [locked] goes stale under a recorder. A take begun
  /// over the lock screen and unlocked before Done then ends on its note, not behind the lock.
  Future<void> phoneSaid(String name) async {
    if (name == 'unlocked') await readLocked();
  }

  /// As the app opens: the voice model's file is looked for (and fetched where this build has a mirror), the better
  /// words' queue is wired to the notes, the models on the phone are read, and whether a meeting can be recorded
  /// here. Opens no microphone.
  ///
  /// [summarized] is told once a summary has landed in a note with the app on screen.
  Future<void> start({VoidCallback? notesChanged, void Function(({String id, String title}) done)? summarized}) async {
    recorder.start(notesChanged: notesChanged);
    // The summary queue, wired to the notes, and the write-up's configuration kept current for the phone's service.
    _stopSummaries = summaries?.startSummaries(notesChanged ?? () {}, summarized ?? (_) {});
    if (summaries != null) _stopJobConfig = keepJobConfigCurrent();
    unawaited(models?.refresh());
    final service = this.service;
    if (service == null) {
      // The Mac: whether it can tap its own sound, for the + sheet's switch. Asked, never opened, here.
      try {
        sound = await recorder.systemSound?.meetingSoundSupport();
      } catch (_) {
        sound = null;
      }
      return;
    }
    try {
      sound = await service.meetingSound();
    } catch (_) {
      sound = null;
    }
    await readLocked();
  }

  void dispose() {
    _stopSummaries?.call();
    _stopJobConfig?.call();
    _notesListeners.clear();
    recorder.dispose();
    models?.dispose();
    dispose_?.call();
  }

  /// A [Voice] over the core and the phone ([making]), writing into [library]. [published] says whether a note has
  /// a shared link, which a recording over the lock screen never writes to.
  ///
  /// The summary queue's part of the app is given too: [isTrashed] (a note in the trash is not summarised), and the
  /// account's [syncNow], [syncSettled] and [record] (a row in the feed), each nothing in a build with no account.
  static Future<Voice> make(
    VoiceMaking making, {
    required NoteLibrary library,
    required Stored kept,
    bool Function(String id)? published,
    bool Function(String id)? isTrashed,
    Future<void> Function()? syncNow,
    Future<void> Function()? syncSettled,
    Future<void> Function(String kind, Map<String, Object?> details)? record,
  }) async {
    final core = making.core;
    final host = making.host;
    final capture = NativeCaptureBackend(core, mirrors: making.mirrors);
    final engine = NativeAiBackend(core, mirrors: making.mirrors);
    ai.useAiBackend(engine);

    final store = LibraryRecorderStore(library);
    late final Voice voice;
    // Whether a write-up was listening or summarising at the last look at the phone's jobs.
    var writingUp = false;
    final live = host.hasMeetings ? MeetingLive(host: host, writeUpRunningNow: () => writingUp) : null;
    final unbind = live == null ? null : host.bind(live);

    // Whoever asked to hear of the app coming back to the screen (the document's `visibilitychange`): the voice
    // model's fetch, which is then tried again where it failed, the better words' queue and the summaries', which
    // then look again. Told by the recorder, which the root feeds the app's lifecycle.
    final visibleListeners = <VoidCallback>{};
    VoidCallback onVisible(VoidCallback listener) {
      visibleListeners.add(listener);
      return () => visibleListeners.remove(listener);
    }

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
      onVisible: onVisible,
    );

    final summaries = Summaries(
      isTauri: () => ai.aiBackend.available,
      preferences: () => preferences.value,
      stored: kept,
      refineHeld: refining.refineHeld,
      refinePending: refining.refinePending,
      onRefineHold: refining.onRefineHold,
      canNotifyNow: () => live?.canNotifyNow() ?? false,
      recordingJobState: () async {
        if (!host.hasMeetings) return const <RecordingJobState>[];
        final states = [for (final job in await engine.recordingJobState()) RecordingJobState.fromJson(job)];
        writingUp = states.any((job) => job.phase == RecordingJobPhase.listening || job.phase == RecordingJobPhase.summarizing);
        return states;
      },
      takeRecordingResult: (id) async {
        if (!host.hasMeetings) return null;
        final result = await engine.recordingResultTake(id);
        return result == null ? null : RecordingResult.fromJson(result);
      },
      writeUpOnHost: (noteId, now) {
        if (!host.hasMeetings) return false;
        unawaited(host.writeUp(noteId, now: now).then<void>((_) {}, onError: (Object _) {}));
        return true;
      },
      answerHost: (name, handler) {
        final answering = host.events.listen((event) {
          if (event.name == name) handler(event.argument ?? '');
        });
        return () => unawaited(answering.cancel());
      },
      getNote: store.getNote,
      // A write another writer won says so in the queue's own words.
      updateNote: (id, body, expectedRevision) async {
        final Note? now = await store.getNote(id);
        if (now == null) throw StateError('The note was deleted.');
        if (now.revision != expectedRevision) throw StateError('The note changed.');
        try {
          return await store.updateNote(id, body, expectedRevision);
        } catch (_) {
          throw StateError('The note changed.');
        }
      },
      isTrashed: isTrashed ?? (_) => false,
      syncNow: syncNow ?? () async {},
      syncSettled: syncSettled ?? () async {},
      record: record ?? (_, _) async {},
      visible: () => host.visible,
      onVisible: onVisible,
      onNotesChanged: (listener) {
        voice._notesListeners.add(listener);
        return () => voice._notesListeners.remove(listener);
      },
      sendJobConfig: sendJobConfig,
    );

    // The scripted WAV in place of the device, in a debug build that asked for it and has the file.
    final fixture = kDebugMode && ghostMicFixtureDefine ? File('${making.dataDir}/fixture.wav') : null;
    final keys = StreamController<void>.broadcast();
    final assists = StreamController<void>.broadcast();
    final screenOff = <VoidCallback>{};
    var made = false;
    final heard = host.events.listen((event) {
      switch (event.name) {
        // Only a build with the assistant is ever asked for a capture by the phone (off unless the build or the phone's developer switch turned it on).
        case 'capture':
          if (making.assistant) (event.argument == 'assist' ? assists : keys).add(null);
        case 'screenOff':
          for (final listener in screenOff.toList()) {
            listener();
          }
        default:
          // Nothing of the lock is said before there is a recorder to have asked about it.
          if (made) unawaited(voice.phoneSaid(event.name));
      }
    });

    final transcriber = CaptureEngine(backend: capture, hasNativeGeneration: ai.hasNativeGeneration);
    final recorder = Recorder(
      engine: transcriber,
      // The recorder's own, told of the app's return too: a download that failed is tried again each time
      // (capture/useVoiceModel.ts).
      voiceModel: VoiceModel(native: true, ensureModel: transcriber.ensureModel, onVisible: onVisible),
      store: store,
      host: RecorderHost(
        isLocked: () => voice.locked,
        // The screen is kept on while a take runs, and its going off stops it, with or without the assistant: so
        // "Press the side key to stop" is said wherever the phone can tell, as the page says it wherever its host
        // has `setCapturing` (core/host.ts). It said "Tap Done to stop." beside the page's line on the same phone.
        setCapturing: (on) {
          if (!host.hasMeetings) return false;
          unawaited(host.setCapturing(on).then<void>((_) {}, onError: (Object _) {}));
          return true;
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
      // The switched-on plugins' formattings that can be said like bold, and their tips for a pause.
      spokenFormats: () => [
        for (final format in plugins.formats())
          if (format.cue case final String cue when cue.isNotEmpty) SpokenFormat(word: cue, delimiter: format.delimiter),
      ],
      pluginTips: (recent) => [for (final tip in plugins.tips(recent)) Tip(say: tip.say, does: tip.does)],
      // A command the rules could not place, read by the model on this phone; a long job in the core.
      startInference: (words) => inferInstruction(
        words,
        invoke: (command, args) async => command == 'ai_infer_command' ? (await core.startJob(command, args)).done : core.invoke(command, args),
        preferredModel: preferences.value.formatModel,
      ),
      // The review after a recording, where this binary and the switch allow it, and a take's summary.
      reviewAvailable: reviewAvailable,
      enqueueSummary: (id, kind) => summaries.enqueueSummary(id, SummaryKind.of(kind)),
      // The Mac's own sound for a meeting: a Core Audio tap in the core, opened only by a meeting with its switch on.
      systemSound: runsAsMacApp
          ? SystemSound(backend: CoreSystemSound(core), isAndroid: false, isMacApp: true, hasNativeGeneration: ai.hasNativeGeneration, meetingSoundOnHost: () => null)
          : null,
      // On the Mac the recorder itself records a meeting, with no service behind it (capture/meeting.ts).
      canRecordMeeting: (host.hasMeetings || runsAsMacApp) &&
          await canRecordMeeting(native: true, isIOS: Platform.isIOS, isAndroid: Platform.isAndroid, isMobile: Platform.isAndroid || Platform.isIOS, hasNativeGeneration: ai.hasNativeGeneration),
      warn: debugPrint,
    );

    // Back on screen, whoever asked to hear of it for the queue is told.
    final offVisible = recorder.onVisible(() {
      for (final listener in visibleListeners.toList()) {
        listener();
      }
    });
    voice = Voice(
      recorder: recorder,
      service: host.hasMeetings ? DeviceMeetingService(host) : null,
      models: ai.ModelsController(),
      summaries: summaries,
      assistant: making.assistant,
      launch: making.launch,
      captureKey: keys.stream,
      assistKey: assists.stream,
      canMeet: recorder.canRecordMeeting,
      removeAudio: (ids) async {
        if (ids.isEmpty) return const <String>[];
        final done = await engine.recordingDelete(ids);
        markAudioRemoved(done.removed);
        return done.removed;
      },
      cancelWriteUp: host.hasMeetings ? host.cancelWriteUp : null,
      dispose_: () {
        offVisible();
        unbind?.call();
        unawaited(heard.cancel());
        unawaited(keys.close());
        unawaited(assists.close());
      },
    );
    made = true;
    return voice;
  }
}
