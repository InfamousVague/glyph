/// Voice and AI alone on a phone, to be proved there before the recorder and the model's screens are ported:
/// `flutter build apk --debug --no-pub --target-platform android-arm64 -t lib/main_voice.dart`. A column of
/// buttons over a log, each one of stage 8's native pieces end to end (docs/STAGES_5_6_8_9.md, 8C to 8F):
///
/// - **Get voice model**: `capture_fetch_model` from [_mirror] (a server on the Mac, `10.0.2.2` from the emulator),
///   never a real mirror, with its progress.
/// - **Dictate**: the phone's microphone (DictationMic.kt) through Dart into the app's own `CaptureEngine`, as the
///   recorder will; **Dictate direct** has Kotlin push straight into the core over JNI; **Dictate fixture** plays
///   `<dataDir>/fixture.wav` in place of the device (a debug build's hook, for an emulator started without audio).
///   **Stop** keeps the tape under a note made for it.
/// - **Generate**: the smallest model of the catalogue writes, its words streamed.
/// - **Start meeting / Stop meeting**: the foreground service records; Stop hands over to the write-up.
/// - **Write up last tape**: the last kept dictation is written up by WorkManager, which carries on with the app
///   swiped away. The jobs' state is read every two seconds and a finished one is taken and shown.
/// - **Use long tape**: a recorder's WAV pushed to `<dataDir>/long.wav` becomes the last tape, so its write-up lasts
///   long enough to swipe the app away under it.
/// - **Allow notifications**, **Assistant?**: the notification prompt, and whether this build has the phone
///   assistant at all (off unless built with GHOST_ASSISTANT=1).
///
/// No always-on microphone: one is opened by a Dictate button or a meeting's start, and by nothing else here.
/// Every line of the log is also printed as `[voice] …`, for `adb logcat -s flutter`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'ai/backend.dart';
import 'ai/native_backend.dart';
import 'capture/audio.dart';
import 'capture/device_mic.dart';
import 'capture/engine.dart';
import 'capture/meeting.dart' show meetingTitle;
import 'capture/meeting_host.dart';
import 'capture/meeting_live.dart';
import 'capture/native_backend.dart';
import 'core/native/device_paths.dart';
import 'core/native/ghost_core.dart';
import 'core/preferences.dart';

/// Where the models are fetched from: a server run on the Mac for this build, and nothing else.
const String _mirror = String.fromEnvironment('VOICE_MODELS', defaultValue: 'http://10.0.2.2:8765');

/// The smallest model of the catalogue.
const String _model = 'qwen3.5-2b';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // So each button has a name `uiautomator` can find.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const _VoiceApp());
}

class _VoiceApp extends StatefulWidget {
  const _VoiceApp();

  @override
  State<_VoiceApp> createState() => _VoiceState();
}

class _VoiceState extends State<_VoiceApp> {
  final List<String> _log = [];
  String _status = 'Opening the core…';
  String _live = '';

  late GhostCore _core;
  late DevicePaths _paths;
  late NativeCaptureBackend _capture;
  late NativeAiBackend _ai;
  late DeviceMeetingHost _host;
  late MeetingLive _meeting;
  bool _ready = false;

  // A dictation under way.
  CaptureSession? _session;
  Microphone? _microphone;
  DeviceMic? _direct;
  String? _noteForTake;
  String? _lastTape;
  final Stopwatch _since = Stopwatch();
  int _partials = 0, _segments = 0;

  final Map<String, String> _jobs = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  void _say(String line) {
    debugPrint('[voice] $line');
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _guard(String what, Future<void> Function() work) async {
    try {
      await work();
    } catch (failure) {
      _say('$what FAILED: $failure');
    }
  }

  Future<void> _open() => _guard('open', () async {
        _core = await GhostCore.open();
        _paths = await DevicePaths.find();
        await _core.init(dataDir: _paths.dataDir, cacheDir: _paths.cacheDir);
        _capture = NativeCaptureBackend(_core, mirrors: const [_mirror]);
        _ai = NativeAiBackend(_core, mirrors: const [_mirror]);
        _host = await DeviceMeetingHost.attach();
        _meeting = MeetingLive(host: _host, writeUpRunningNow: () => _jobs.values.any((phase) => phase == 'listening' || phase == 'summarizing'));
        _host.bind(_meeting);
        _host.events.listen((event) => _say('host ${event.name}: ${event.argument ?? ''}'));
        _meeting.subscribe(() => _say('meeting state: ${_host.meetingStateJson()}'));
        final launch = await _host.takeLaunch();
        final voice = await _capture.modelStatus();
        final models = await _ai.models();
        final device = await _ai.device();
        _say('core open on ${_paths.dataDir}; launch "$launch"; generation ${await _ai.nativeGeneration()}; '
            '${device.cores} cores, ${((device.totalRamBytes ?? 0) / 1e9).toStringAsFixed(1)} GB; voice model ${voice.present ? 'here' : 'absent'}; '
            'models here: ${models.where((m) => m.present).map((m) => m.id).toList()}; meetings ${_host.hasMeetings}; may notify ${_host.canNotify()}');
        setState(() {
          _ready = true;
          _status = 'Ready';
        });
        _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_readJobs()));
        unawaited(_readJobs());
      });

  // ---- the voice model -------------------------------------------------------------------------------------------

  Future<void> _download() => _guard('download', () async {
        final before = await _capture.modelStatus();
        if (before.present) return _say('voice model already here: ${before.path} (${before.bytes} bytes)');
        final watch = Stopwatch()..start();
        var reports = 0;
        final heard = _capture.events.listen((event) {
          if (event is! CaptureEventModelProgress) return;
          reports += 1;
          setState(() => _status = 'Voice model ${(event.receivedBytes * 100 / event.totalBytes).toStringAsFixed(0)}%');
        });
        try {
          final status = await _capture.fetchModel();
          _say('voice model ${status.name}: present ${status.present}, ${status.bytes} bytes from $_mirror in ${watch.elapsedMilliseconds} ms, $reports reports');
        } finally {
          await heard.cancel();
          setState(() => _status = 'Ready');
        }
      });

  // ---- dictation -------------------------------------------------------------------------------------------------

  CaptureHandlers get _handlers => CaptureHandlers(
        onPartial: (text) {
          if (text.isNotEmpty) _partials += 1;
          setState(() => _live = text);
        },
        onSegment: (segment) {
          _segments += 1;
          _say('segment ${segment.startMs}-${segment.endMs}: ${segment.text}');
        },
        onError: (message) => _say('capture error: $message'),
      );

  Future<String> _noteForATake() async {
    final id = await _core.newId();
    final title = meetingTitle(DateTime.now().millisecondsSinceEpoch);
    await _core.invoke('create_note', {'id': id, 'body': '# $title\n', 'source': 'capture'});
    return id;
  }

  /// The recorder's own order: the microphone first, holding what it hears while the engine starts.
  Future<void> _dictate({String? testWav}) => _guard('dictate', () async {
        if (_session != null || _direct != null) return _say('a dictation is already running');
        _partials = _segments = 0;
        _since
          ..reset()
          ..start();
        final held = <Float32List>[];
        var level = 0.0;
        final microphone = await openMicrophone(
          MicrophoneHandlers(
            onChunk: (samples) {
              final running = _session;
              if (running != null) {
                running.push(samples);
              } else {
                held.add(samples);
              }
            },
            onLevel: (rms) {
              level = rms;
              setState(() => _status = 'Listening, level ${level.toStringAsFixed(3)}');
            },
          ),
          open: (constraints, {required sampleRate, required chunk}) => DeviceMic.openWith(constraints, testWav: testWav),
        );
        _microphone = microphone;
        _say('microphone open at ${microphone.deviceRate} Hz in ${_since.elapsedMilliseconds} ms${testWav == null ? '' : ' (the fixture, not the device)'}');
        final engine = CaptureEngine(backend: _capture, hasNativeGeneration: (wanted) async => wanted <= await _ai.nativeGeneration(), preferences: () => const Preferences());
        final session = await engine.startCapture(_handlers);
        _noteForTake = await _noteForATake();
        _session = session;
        for (final samples in held) {
          session.push(samples);
        }
        _say('capture started ${_since.elapsedMilliseconds} ms after the press, ${held.length} chunks held meanwhile');
      });

  /// Kotlin pushes into the core itself; Dart hears levels only.
  Future<void> _dictateDirect({String? testWav}) => _guard('dictate direct', () async {
        if (_session != null || _direct != null) return _say('a dictation is already running');
        _partials = _segments = 0;
        _since
          ..reset()
          ..start();
        final mic = await DeviceMic.openWith(const MicrophoneConstraints(), direct: true, testWav: testWav);
        _direct = mic;
        mic.levels.listen((heard) => setState(() => _status = 'Listening (direct), level ${heard.rms.toStringAsFixed(3)}, ${heard.samples} samples'));
        unawaited(mic.closed.then((reason) {
          if (reason != 'closed') _say('the microphone was let go: $reason');
        }));
        final listening = _capture.events.listen((event) {
          switch (event) {
            case CaptureEventPartial(:final text):
              _handlers.onPartial(text);
            case CaptureEventSegment(:final segment):
              _handlers.onSegment(segment);
            case CaptureEventError(:final message):
              _handlers.onError(message);
            default:
              break;
          }
        });
        unawaited(mic.closed.then((_) => listening.cancel()));
        await _capture.start();
        await mic.flow();
        _noteForTake = await _noteForATake();
        _say('capture started ${_since.elapsedMilliseconds} ms after the press; the microphone pushes into the core itself');
      });

  Future<void> _stopDictation() => _guard('stop', () async {
        final id = _noteForTake;
        final session = _session;
        final direct = _direct;
        if (session == null && direct == null) return _say('no dictation is running');
        _session = null;
        _direct = null;
        String? transcript;
        int? recordedMs;
        if (session != null) {
          _microphone?.stop();
          _microphone = null;
          final stopped = await session.stop(StopOptions(recordAs: id));
          transcript = stopped.transcript;
          recordedMs = stopped.recordedMs;
        } else if (direct != null) {
          direct.close();
          final totals = await direct.totals;
          _say('the microphone heard ${totals?.samples} samples: ${totals?.pushed} into the core, ${totals?.refused} refused');
          final stopped = await _capture.stop(StopOptions(recordAs: id));
          transcript = stopped?.transcript;
          recordedMs = stopped?.recordedMs;
        }
        _lastTape = recordedMs == null ? null : id;
        setState(() {
          _live = '';
          _status = 'Ready';
        });
        _say('dictation over after ${_since.elapsedMilliseconds} ms: $_partials partials, $_segments segments, tape $recordedMs ms kept as $id: "$transcript"');
      });

  // ---- the language model ----------------------------------------------------------------------------------------

  Future<void> _generate() => _guard('generate', () async {
        final here = (await _ai.models()).where((m) => m.id == _model && m.present);
        if (here.isEmpty) return _say('$_model is not in ${_paths.dataDir}/models (adb push it there)');
        final id = 'run-${DateTime.now().millisecondsSinceEpoch}';
        var reports = 0;
        int? firstWordMs;
        final watch = Stopwatch()..start();
        final unhear = _ai.listen(progressEvent, (payload) {
          final progress = Progress.fromJson((payload as Map).cast<String, Object?>());
          if (progress.id != id) return;
          reports += 1;
          if (progress.partial.isNotEmpty) firstWordMs ??= watch.elapsedMilliseconds;
          setState(() {
            _status = '${progress.phase.name} ${progress.outputTokens} tokens, ${progress.tokensPerSecond.toStringAsFixed(1)}/s';
            _live = progress.partial;
          });
        });
        try {
          final output = await _ai.generate(GenerateRequest(
            id: id,
            model: _model,
            system: 'You are a careful assistant inside a notes app. Answer briefly.',
            prompt: 'Write three short bullet points about why handwritten notes help memory.',
            maxTokens: 96,
            temperature: 0.3,
          ));
          _say('$_model: ${output.outputTokens} tokens at ${output.tokensPerSecond.toStringAsFixed(1)} a second, ${output.promptTokens} prompt tokens, load ${output.loadMs} ms, '
              'prefill ${output.prefillMs} ms, ${output.ms} ms in all, first word after $firstWordMs ms, $reports progress events: "${output.text.replaceAll('\n', ' / ')}"');
        } finally {
          unhear();
          setState(() {
            _status = 'Ready';
            _live = '';
          });
        }
      });

  // ---- meetings and the write-up ---------------------------------------------------------------------------------

  Future<void> _keepConfig() => _ai.keepJobConfig(const JobConfig(
        model: _model,
        prompts: JobPrompts(summary: '', notes: '', piece: '', parts: ''),
        onePassChars: 20000,
        pieceChars: 12000,
        temperature: 0.3,
        writeUp: 'now',
        summaries: 'meetings',
      ));

  Future<void> _startMeeting() => _guard('meeting', () async {
        await _keepConfig();
        final id = await _core.newId();
        final title = meetingTitle(DateTime.now().millisecondsSinceEpoch);
        await _core.invoke('create_note', {'id': id, 'body': '# $title\n', 'source': 'capture'});
        var answer = await _host.startMeeting(id, title);
        _say('startMeeting($id, "$title") -> $answer');
        if (answer == 'permission') {
          final granted = await _host.events.firstWhere((event) => event.name == 'meeting' && (event.argument ?? '').contains('"permission"'));
          if (!(granted.argument ?? '').contains('"granted":true')) return _say('the microphone was refused');
          answer = await _host.startMeeting(id, title);
          _say('startMeeting again -> $answer');
        }
      });

  Future<void> _stopMeeting() => _guard('stop meeting', () async {
        await _host.stopMeeting();
        _say('stopMeeting asked; state ${_host.meetingStateJson()}');
      });

  Future<void> _writeUpTape() => _guard('write up', () async {
        final id = _lastTape;
        if (id == null) return _say('no tape kept yet: dictate, then Stop');
        await _keepConfig();
        _say('writeUp($id, now) -> ${await _host.writeUp(id, now: true)}');
      });

  /// A debug walk's own: `<dataDir>/long.wav` (a recorder's WAV pushed there by adb) becomes a new note's tape, so a
  /// write-up lasts long enough to swipe the app away under it.
  Future<void> _useLongTape() => _guard('long tape', () async {
        final source = File('${_paths.dataDir}/long.wav');
        if (!source.existsSync()) return _say('no ${source.path}');
        final id = await _noteForATake();
        await Directory('${_paths.dataDir}/recordings').create(recursive: true);
        await source.copy('${_paths.dataDir}/recordings/$id.wav');
        _lastTape = id;
        _say('long tape of ${source.lengthSync()} bytes is now note $id\'s');
      });

  Future<void> _readJobs() async {
    if (!_ready) return;
    try {
      for (final job in await _ai.recordingJobState()) {
        final id = job['id'] as String;
        final said = '${job['phase']}${job['waitingFor'] == null ? '' : ' (${job['waitingFor']})'} ${job['percent']}%${job['error'] == null ? '' : ' ${job['error']}'}';
        if (_jobs[id] != said) {
          _jobs[id] = said;
          _say('write-up $id "${job['title']}": $said');
        }
        if (job['phase'] == 'done') {
          final result = await _ai.recordingResultTake(id);
          final note = await _core.invoke('get_note', {'id': id});
          final body = note is Map ? note['body'] as String? ?? '' : '';
          _say('WRITTEN UP $id with ${result?['model']}: ${result?['transcriptChars']} characters heard; summary: '
              '${(result?['summary'] as String?)?.replaceAll('\n', ' / ') ?? 'none'}; the note is now ${body.length} characters: ${body.replaceAll('\n', ' / ')}');
          _jobs.remove(id);
        }
      }
    } catch (failure) {
      _say('jobs FAILED: $failure');
    }
  }

  Future<void> _notifications() => _guard('notifications', () async => _say('requestNotifications -> ${await _host.requestNotifications()}'));

  Future<void> _assistant() => _guard('assistant', () async {
        _say('assistant in this build: ${await _host.assistantEnabled()}; is the assistant: ${await _host.isAssistant()}; maker ${await _host.deviceMaker()}; '
            'microphone ${await DeviceMic.permission()}');
      });

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixture = _ready ? '${_paths.dataDir}/fixture.wav' : '';
    final buttons = <(String, VoidCallback)>[
      ('Get voice model', _download),
      ('Dictate', _dictate),
      ('Dictate direct', _dictateDirect),
      ('Dictate fixture', () => _dictate(testWav: fixture)),
      ('Fixture direct', () => _dictateDirect(testWav: fixture)),
      ('Stop', _stopDictation),
      ('Generate', _generate),
      ('Start meeting', _startMeeting),
      ('Stop meeting', _stopMeeting),
      ('Write up last tape', _writeUpTape),
      ('Use long tape', _useLongTape),
      ('Allow notifications', _notifications),
      ('Assistant?', _assistant),
    ];
    const ink = Color(0xFFEDEDED), paper = Color(0xFF111111), line = Color(0xFF3A3A3A);
    const text = TextStyle(color: ink, fontSize: 13, height: 1.3, decoration: TextDecoration.none);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: paper,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One line, so the buttons under it never move.
                Text('Ghost Flutter · voice', style: text.copyWith(fontSize: 15), maxLines: 1),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, action) in buttons)
                      Semantics(
                        button: true,
                        label: label,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _ready ? action : null,
                          child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: _ready ? ink : line), borderRadius: BorderRadius.circular(8)),
                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text(label, style: text)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Semantics(label: 'status: $_status', excludeSemantics: true, child: Text(_status, style: text.copyWith(color: const Color(0xFFFFD27A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_live.isNotEmpty) Text(_live, style: text.copyWith(color: const Color(0xFF9AD0FF)), maxLines: 6, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_log[index], style: text)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
