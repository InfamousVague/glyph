/// A fixed note, spoken on a clock, for exercising the recorder without a microphone. A port of
/// `src/app/capture/simulated.ts`: the third engine behind capture/engine.dart's one interface, chosen by `simulate`
/// in the query the engine is given. Each phrase arrives first as growing partials and then as a committed segment,
/// which is the rhythm the Whisper engine produces. It "keeps" audio in the sense that stop answers with a length, so
/// a note's tape can be built against it. Development and test tooling: nothing on the phone reaches it without the
/// query.
///
/// `simulate` speaks a note; `simulate=route` speaks one that moves itself to another note partway ("hey Ghost, move
/// this to shopping list") and then pauses, so routing and the tips in a pause can be watched without a microphone;
/// `simulate=leave` leaves a note in AttackFM, said in one phrase and then in two; `simulate=item` speaks "hey Ghost,
/// new item for attack FM" and items for its list; `simulate=command` is Matt's case, "add a list item to" with the
/// item after a pause, then a one-shot, then a sentence that opens with the app's name; `simulate=ask` stops with
/// the item said; `simulate=giveback` says the keyword and names no note; `simulate=takeback` says a sentence,
/// changes a word in it, corrects one, scratches one and sends it after a breath, and sends one in one breath, to
/// shopping list; `simulate=say` with `say=a|b` speaks the phrases given, bar-separated; `simulate=review` says a
/// note with a misheard word, for the review after a recording.
///
/// Each command in them is read as the recorder reads one: the live reader (live_route.dart) carries out "hey Ghost,
/// add … to a note" as it is said, and anything else is read once, from the whole transcript, at Done. Nothing asks
/// for a yes.
///
/// What differs:
/// - The web reads `window.location.search` and `performance.now()`; here the query and the clock are given
///   ([simulated]'s `search` and `now`), and the 40 ms interval is a `Timer`.
/// - [SimulatedBackend] is not on the web. It is the same script played as a [CaptureBackend], the test backend for
///   everything written over the native capture until the real one exists (engine.dart says what that one must do):
///   the Whisper engine's own path - events, pushes in order, the kept recording's length - with the script's
///   phrases coming out of it. It speaks only between `start` and `stop` or `cancel`.
library;

import 'dart:async';

import 'engine.dart';
import 'markdown.dart' show Segment;

/// The scripts, by the word after `simulate=` (`SCRIPTS`).
const Map<String, List<String>> _scripts = {
  'note': [
    'Weekend trip.',
    'We need to book the cabin by Friday and the deposit is 200 dollars.',
    'For the drive we want snacks, water, a charger and the good playlist.',
    'Remember to ask Sam about the dog.',
    'Separately the car needs an oil change before we leave.',
  ],
  'route': ['Oat milk, eggs and the good coffee.', 'Hey Ghost, move this to shopping list.', 'And bin bags.'],
  'leave': [
    'Quick thought before I forget.',
    'Hey Ghost, leave a note on the page for attack FM that says the seek bar drifts on two devices.',
    'Hey Ghost, leave a note for attack FM.',
    'Ship the APK on Friday.',
  ],
  'item': [
    'Quick thought before I forget.',
    'Hey Ghost, new item for attack FM.',
    'Fix the login bug on Android.',
    'Hey Ghost, new tasks for attack FM.',
    'Update the readme, ship the APK and tell Sam.',
  ],
  'giveback': ['Pick up the parcel.', 'Hey Ghost, that was a long day.'],
  'takeback': [
    'Weekend trip.',
    'The meeting is at three.',
    'No wait, four.',
    'We need snacks and water.',
    'Actually, we need snacks and a charger.',
    'Bin bags and oat milk.',
    'Scratch that.',
    'Add it to shopping list instead.',
    'Call Sam about the dog.',
    'Scratch that, add it to shopping list instead.',
  ],
  'review': ['Bug bash on Friday.', 'Fix the seat bar on two devices.', 'Downloads get stuck on the discover list.'],
  'ask': ['Quick thought before I forget.', 'Hey Ghost, add a list item to the attack FM.', 'Fix the seek bar.'],
  'command': [
    'Quick thought before I forget.',
    'Hey Ghost, add a list item to the attack FM.',
    'Fix the seek bar.',
    'Hey Ghost add ship the APK to attack FM.',
    'Ghost is going to need a plugin store.',
  ],
};

typedef _Cue = ({int at, void Function() run});

/// The phrases a query asks for: `say`'s, a phrase per bar, so any command can be tried without a microphone, or
/// the script `simulate` names, or the note.
List<String> _script(Map<String, String> search) {
  final said = search['say'];
  if (said != null && said.isNotEmpty) return said.split('|').map((phrase) => phrase.trim()).where((phrase) => phrase.isNotEmpty).toList();
  return _scripts[search['simulate'] ?? ''] ?? _scripts['note']!;
}

/// The script as cues on a clock: each word a longer partial, 180 ms apart, then the phrase committed 350 ms on.
List<_Cue> _cues(List<String> script, void Function(String text) onPartial, void Function(Segment segment) onSegment) {
  final cues = <_Cue>[];
  var at = 0;
  for (var index = 0; index < script.length; index += 1) {
    final phrase = script[index];
    final words = phrase.split(' ');
    final startMs = at;
    for (var w = 0; w < words.length; w += 1) {
      at += 180;
      final guess = words.sublist(0, w + 1).join(' ');
      cues.add((at: at, run: () => onPartial(guess)));
    }
    at += 350;
    final endMs = at;
    cues.add((
      at: endMs,
      run: () {
        onPartial('');
        onSegment(Segment(text: phrase, startMs: startMs, endMs: endMs));
      },
    ));
    at += index == 3 ? 2600 : 300; // one long pause, to show a paragraph break
  }
  return cues;
}

/// The cues played on a 40 ms tick against a clock, as the web's interval plays them.
class _Player {
  _Player(this.cues, this.now) : last = now() {
    timer = Timer.periodic(const Duration(milliseconds: 40), (_) => tick());
  }

  final List<_Cue> cues;
  final double Function() now;
  double clock = 0;
  int next = 0;
  double last;
  final Completer<void> finished = Completer<void>();
  late final Timer timer;

  void tick() {
    final at = now();
    clock += at - last;
    last = at;
    while (next < cues.length && cues[next].at <= clock) {
      cues[next++].run();
    }
    if (next >= cues.length && !finished.isCompleted) finished.complete();
  }

  /// The script's end, or 50 ms, whichever comes first: then the clock stops.
  Future<void> stop() async {
    await Future.any<void>([finished.future, Future<void>.delayed(const Duration(milliseconds: 50))]);
    timer.cancel();
  }
}

final Stopwatch _sinceLoad = Stopwatch()..start();
double _performanceNow() => _sinceLoad.elapsedMicroseconds / 1000;

/// The scripted voice as a session: [search] is the page's query by name, [now] its clock in milliseconds.
CaptureSession simulated(CaptureHandlers handlers, {Map<String, String> search = const {}, double Function()? now}) {
  final player = _Player(_cues(_script(search), handlers.onPartial, handlers.onSegment), now ?? _performanceNow);
  return CaptureSession(
    kind: EngineKind.simulated,
    wantsSamples: false,
    keepsAudio: true,
    push: (_) {},
    positionMs: () => player.clock,
    stop: ([options]) async {
      await player.stop();
      return Stopped(recordedMs: player.clock.round(), transcript: null);
    },
    cancel: () => player.timer.cancel(),
  );
}

/// The scripted voice as the native capture: what a [CaptureEngine] is given in a test, in place of the Rust core.
///
/// `start` begins the script, whose guesses and phrases come out of [events] as the core's would; `push` counts what
/// it is handed and keeps the order it came in ([pushed]); `stop` answers the phrases said so far as its final
/// transcript and the length it spoke as the kept recording; `cancel` stops the clock. The voice model is always
/// there, and the larger one's pass answers the phrases said in the stretch asked for, as they were said.
class SimulatedBackend implements CaptureBackend {
  SimulatedBackend({this.search = const {}, double Function()? now}) : now = now ?? _performanceNow;

  /// The page's query by name: which script, or `say`'s phrases.
  final Map<String, String> search;

  /// The clock, in milliseconds.
  final double Function() now;

  final StreamController<CaptureEvent> _events = StreamController<CaptureEvent>.broadcast(sync: true);
  _Player? _player;

  /// Every chunk pushed since the last start, as it arrived.
  final List<String> pushed = <String>[];

  /// Every phrase committed since the last start.
  final List<Segment> said = <Segment>[];

  /// Every note a recording was kept for, with its length.
  final Map<String, int> kept = <String, int>{};

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    _player?.timer.cancel();
    pushed.clear();
    said.clear();
    _player = _Player(
      _cues(_script(search), (text) => _events.add(CaptureEventPartial(text)), (segment) {
        said.add(segment);
        _events.add(CaptureEventSegment(segment));
      }),
      now,
    );
  }

  @override
  Future<void> push(String pcm) async {
    if (_player == null) throw Exception('no capture is running');
    pushed.add(pcm);
  }

  @override
  Future<void> rewind(int toMs) async {
    said.removeWhere((segment) => segment.endMs > toMs);
    _events.add(CaptureEventRewound(toMs: toMs, segments: List<Segment>.of(said)));
  }

  @override
  Future<CaptureStopped?> stop([StopOptions? options]) async {
    final player = _player;
    if (player == null) throw Exception('no capture is running');
    await player.stop();
    _player = null;
    if (options == null) return null;
    final recordedMs = player.clock.round();
    final recordAs = options.recordAs;
    if (recordAs != null) kept[recordAs] = (options.append == true ? (kept[recordAs] ?? 0) : 0) + recordedMs;
    return CaptureStopped(transcript: said.map((segment) => segment.text).join(' '), recordedMs: recordAs == null ? null : kept[recordAs]);
  }

  @override
  Future<void> cancel() async {
    _player?.timer.cancel();
    _player = null;
  }

  @override
  Future<ModelStatus> modelStatus() async => const ModelStatus(present: true, name: 'simulated', path: '', bytes: 0);

  @override
  Future<ModelStatus> fetchModel() => modelStatus();

  @override
  Future<int?> reassignRecording({required String fromId, required String toId, required bool append}) async {
    final length = kept.remove(fromId);
    if (length == null) return null;
    return kept[toId] = (append ? (kept[toId] ?? 0) : 0) + length;
  }

  @override
  Future<void> discardRecording({required String id}) async {
    kept.remove(id);
  }

  @override
  Future<({bool present, int bytes})> refineModelStatus() async => (present: true, bytes: 0);

  @override
  Future<({bool present, int bytes})> fetchRefineModel() => refineModelStatus();

  @override
  Future<List<Segment>> refine({required String id, required int fromMs, required String promptTail}) async =>
      said.where((segment) => segment.startMs >= fromMs).toList();
}
