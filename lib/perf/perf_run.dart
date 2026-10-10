/// The measured walk: a build made to be measured (`--dart-define=GHOST_PERF=true`) walks itself through what a
/// person does all day (the home page flung up and down, a long note opened, read and typed in, a board, a canvas,
/// Settings) and says what every stretch of it cost in frames (lib/perf/frame_log.dart).
///
/// The same walk, by the same fingers (lib/shell/phone_tour.dart gives each touch to Flutter's own gesture
/// binding, and each letter to the editor's own keyboard client), on the same library (lib/perf/perf_seed.dart),
/// so two builds can be told apart by their numbers and a change that was meant to help can be seen not to.
///
/// The walk is `--dart-define=GHOST_PERF_TOUR=<script>`, or `GHOST_PERF_TOUR` in the environment of a desktop
/// build; `bench` is the standard one ([benchScript]). A script is the tour's own steps with one more,
/// `mark:<name>`, which ends one stretch and begins the next. The report is the log's `[perf]` lines and
/// `<cache>/perf/report.json`; it carries the VM's own address in a profile build, where tool/perf_cpu.dart reads
/// the CPU's samples for each stretch.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Service;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/native/device_paths.dart';
import '../launch/launch_screen.dart';
import '../shell/phone_tour.dart';
import 'frame_log.dart';

/// The walk this build takes by itself, if any.
const String ghostPerfTour = String.fromEnvironment('GHOST_PERF_TOUR');

/// What `main` tells of its own start, in milliseconds since its first line: when the app was handed to Flutter
/// ([ranApp]), and whatever it timed on the way there.
abstract final class PerfLaunch {
  static final Stopwatch sinceMain = Stopwatch();
  static final Map<String, int> at = {};

  /// Called on `main`'s first line.
  static void begin() {
    if (!ghostPerf) return;
    sinceMain.start();
    FrameLog.instance.install();
  }

  /// One step of the start is done.
  static void step(String name) {
    if (ghostPerf) at[name] = sinceMain.elapsedMilliseconds;
  }

  /// The folders a measured DESKTOP build keeps everything in, when its environment names one
  /// (`GHOST_PERF_DIR=/some/scratch/folder`): its library of made-up notes and its report stay out of the folder
  /// the app keeps a person's notes in. Null anywhere else, and the app's own folders stand.
  static DevicePaths? dirs() {
    if (!ghostPerf) return null;
    final root = Platform.environment['GHOST_PERF_DIR'];
    if (root == null || root.trim().isEmpty) return null;
    return DevicePaths.own(dataDir: '$root/data', cacheDir: '$root/cache');
  }
}

/// The standard walk for a window [size] logical pixels: every touch is placed by the window, so the same walk
/// runs on the Fold shut, the Fold open and a Mac's window. It is made of parts, each of which begins and ends on
/// the home page, so one part can be walked alone ([only]: `home`, `note`, `board`, `canvas`, `notebook`,
/// `settings`; `bench:note+settings` on the command line). What a part opens is looked for first (`seek`, in a
/// stretch that is not kept): a phone's home page has it a few screens down where a wide window shows it at once.
String benchScript(Size size, {Set<String>? only}) {
  final x = (size.width / 2).round();
  final high = (size.height * 0.30).round(), low = (size.height * 0.72).round(), middle = (size.height * 0.5).round();
  String flings(int from, int to, int times) => [for (var i = 0; i < times; i += 1) 'flick:$x,$from,$x,$to,140;wait:1100'].join(';');
  const words = 'The quick brown fox jumps over the lazy dog, and then the dog, who was not as lazy as all that, gets up and has a word with the fox. ';
  final parts = <String, List<String>>{
    'home': [
      'mark:home-still', 'wait:2000',
      'mark:home-fling-down', flings(low, high, 5),
      'mark:home-fling-up', flings(high, low, 5),
      // A finger kept on the glass: every frame of it is a frame of scrolling.
      'mark:home-drag', 'swipe:$x,$low,$x,$high,1400', 'swipe:$x,$high,$x,$low,1400',
    ],
    'note': [
      'mark:_seek', 'seek:Bench long',
      'mark:note-open', 'taptext:Bench long', 'wait:2000',
      'mark:note-fling-down', flings(low, high, 4),
      'mark:note-fling-up', flings(high, low, 4),
      'mark:note-type', 'tap:$x,$middle', 'wait:900', 'type:$words', 'wait:600',
      'mark:note-type-lines', 'enter', 'type:- one', 'enter', 'type:two', 'enter', 'type:three', 'enter', 'enter', 'type:$words', 'wait:1500',
      'mark:note-leave', 'unfocus', 'wait:400', 'taplabel:Home', 'wait:1500',
    ],
    'board': [
      'mark:_seek', 'seek:Bench board',
      'mark:board-open', 'taptext:Bench board', 'wait:2000',
      'mark:board-fling', flings(low, high, 2), flings(high, low, 2),
      'mark:board-leave', 'taplabel:Home', 'wait:1500',
    ],
    'canvas': [
      'mark:_seek', 'seek:Bench canvas',
      'mark:canvas-open', 'taptext:Bench canvas', 'wait:2000',
      'mark:canvas-drag', 'swipe:$x,$low,$x,$high,900', 'swipe:$x,$high,$x,$low,900',
      'mark:canvas-leave', 'taplabel:Home', 'wait:1500',
    ],
    'notebook': [
      'mark:_seek', 'seek:Bench notebook',
      'mark:notebook-open', 'taptext:Bench notebook', 'wait:2000',
      'mark:notebook-fling', flings(low, high, 2), flings(high, low, 2),
      'mark:notebook-leave', 'taplabel:Home', 'wait:1500',
    ],
    'settings': [
      'mark:settings-open', 'taplabel:Settings', 'wait:1500',
      'mark:settings-fling', flings(low, high, 3), flings(high, low, 3),
      'mark:_seek', 'seek:Appearance',
      'mark:settings-page', 'taptext:Appearance', 'wait:1500', flings(low, high, 3), flings(high, low, 3),
    ],
  };
  return [
    // A first run on a phone opens on the welcome, over the app: skipped, or every touch of the walk lands on it.
    'mark:_start', 'tapif:Skip', 'wait:1500',
    for (final part in parts.entries)
      if (only == null || only.contains(part.key)) ...part.value,
    'mark:end',
  ].join(';');
}

/// Takes the walk this build was given, if it measures itself and was given one. Called once the app is running.
Future<void> runPerf() async {
  if (!ghostPerf) return;
  final asked = ghostPerfTour.isNotEmpty ? ghostPerfTour : (Platform.environment['GHOST_PERF_TOUR'] ?? '');
  final log = FrameLog.instance..install();
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  PerfLaunch.step('firstFrame');
  // The launch screen is the app opening: the walk begins when it has gone, and how long that took is the launch.
  for (var waited = 0; waited < 400 && _launching(); waited += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  PerfLaunch.step('open');
  debugPrint('[perf] launch ${jsonEncode(PerfLaunch.at)} ms since main');
  if (asked.trim().isEmpty) {
    // No walk: the frames of whatever the person does, a line each few seconds that had any.
    Timer.periodic(const Duration(seconds: 3), (_) => unawaited(log.mark('use', quiet: true)));
    return;
  }
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final window = view.physicalSize / view.devicePixelRatio;
  final String script;
  if (asked.trim() == 'bench') {
    script = benchScript(window);
  } else if (asked.trim().startsWith('bench:')) {
    script = benchScript(window, only: asked.trim().substring(6).split('+').map((part) => part.trim()).toSet());
  } else {
    script = asked;
  }
  final Directory dir;
  final String? vm;
  try {
    dir = Directory('${(PerfLaunch.dirs() ?? await DevicePaths.find()).cacheDir}/perf');
    dir.createSync(recursive: true);
    for (final old in ['report.json', 'done', 'vm.txt']) {
      final file = File('${dir.path}/$old');
      if (file.existsSync()) file.deleteSync();
    }
    // Where the VM answers, in a profile build: tool/perf_cpu.dart reads the CPU's samples there while the walk goes.
    vm = (await Service.getInfo()).serverUri?.toString();
    if (vm != null) File('${dir.path}/vm.txt').writeAsStringSync('$vm\n', flush: true);
  } catch (failure) {
    debugPrint('[perf] no folder for the walk: $failure');
    return;
  }
  // The tour asks its host for pictures and for leave to end, through a file; here nobody is asked, so every
  // question is answered at once by taking it away.
  final answers = Timer.periodic(const Duration(milliseconds: 40), (_) {
    final ask = File('${dir.path}/ask.txt');
    try {
      if (ask.existsSync()) ask.deleteSync();
    } catch (_) {}
  });
  final tour = PhoneTour(dir: dir);
  // Each stretch is the steps between two marks, walked as a script of its own.
  var steps = <String>[];
  Future<void> walk() async {
    if (steps.isEmpty) return;
    await tour.run(steps.join(';'));
    steps = <String>[];
  }

  for (final step in tourSteps(script)) {
    if (step.name == 'mark') {
      await walk();
      await log.mark(step.arg);
    } else {
      steps.add(step.arg.isEmpty ? step.name : '${step.name}:${step.arg}');
    }
  }
  await walk();
  answers.cancel();
  final report = {
    'launch': PerfLaunch.at,
    'window': {'width': view.physicalSize.width / view.devicePixelRatio, 'height': view.physicalSize.height / view.devicePixelRatio, 'ratio': view.devicePixelRatio, 'hz': view.display.refreshRate},
    'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    'vm': vm,
    'stretches': [for (final stats in log.stretches) stats.toJson()],
  };
  final said = jsonEncode(report);
  try {
    File('${dir.path}/report.json').writeAsStringSync(said, flush: true);
  } catch (_) {}
  // The log cuts a long line, so the report goes in pieces a reader joins.
  for (var from = 0; from < said.length; from += 800) {
    debugPrint('[perf] report ${said.substring(from, from + 800 > said.length ? said.length : from + 800)}');
  }
  debugPrint('[perf] report end');
  // A desktop's build waits to be read (its CPU samples, by tool/perf_cpu.dart) and then goes.
  if (Platform.environment.containsKey('GHOST_PERF_HOLD')) {
    final done = File('${dir.path}/done');
    for (var waited = 0; waited < 1200 && !done.existsSync(); waited += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      if (done.existsSync()) done.deleteSync();
    } catch (_) {}
    exit(0);
  }
}

/// Whether the launch screen is still up.
bool _launching() {
  var found = false;
  void visit(Element element) {
    if (found) return;
    if (element.widget is LaunchScreen) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}
