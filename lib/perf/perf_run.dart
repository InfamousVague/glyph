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
import 'dart:ui' as ui show channelBuffers;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../book/book_view.dart' show BookView;
import '../core/book.dart' show chaptersOf;
import '../core/native/device_paths.dart';
import '../core/note_text.dart' show noteTitle, sameTitle;
import '../core/sample_library.dart' show seedLibrary, starterNotes;
import '../launch/launch_screen.dart';
import '../shell/phone_tour.dart';
import '../shell/wide_screen.dart' show mousePointer, splitFits;
import 'frame_log.dart';
import 'perf_seed.dart' show perfBody;

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
/// `allnotes`, `sidebar`, `search`, `palette`, `settings`; `bench:note+settings` on the command line). What a part
/// opens is looked for first (`seek`, in a stretch that is not kept): a phone's home page has it a few screens down
/// where a wide window shows it at once.
///
/// Besides the tour's steps a walk has a few of its own ([_ownStep]): the system's `back`, a press or a drag on
/// what wears a key (`tapkey`, `dragkey`: a canvas's card and a note's lines are not words the tour can find), two
/// fingers (`pinch`), and `fixture:chapters`, which gives the notebook pages that are written.
String benchScript(Size size, {Set<String>? only}) {
  final x = (size.width / 2).round();
  final high = (size.height * 0.30).round(), low = (size.height * 0.72).round(), middle = (size.height * 0.5).round();
  String flings(int from, int to, int times) => [for (var i = 0; i < times; i += 1) 'flick:$x,$from,$x,$to,140;wait:1100'].join(';');
  // The notes' card hangs at the window's left, twenty rems wide: a finger down its middle.
  const card = 172;
  String cardFlings(int from, int to, int times) => [for (var i = 0; i < times; i += 1) 'flick:$card,$from,$card,$to,140;wait:1100'].join(';');
  // Settings in two panes, its sections always beside the page, or one page at a time (lib/settings/settings_screen.dart).
  final split = splitFits(size, mouse: mousePointer);
  // A canvas's zoom buttons are a wide window's (lib/canvas/canvas_view.dart `_tools`).
  final zooms = size.width > 600;
  // What is written into a canvas's card, and taken out again letter by letter.
  const more = ' and the cat, who has not been asked about either.';
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
      // The caret goes into the note's first paragraph, by its words: a tap at mid-screen took whatever was there
      // (a link once, and the stretch measured the page it opened).
      'mark:note-type', 'tapline:A note is plain Markdown', 'wait:900', 'type:$words', 'wait:600',
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
      'mark:_seek', 'reach:Bench canvas',
      'mark:canvas-open', 'taptext:Bench canvas', 'wait:2000',
      'mark:canvas-drag', 'swipe:$x,$low,$x,$high,900', 'swipe:$x,$high,$x,$low,900',
      // Two fingers apart and together again about the middle, then the buttons a wide window has, and the fit.
      'mark:canvas-zoom', 'pinch:$x,$middle,120,300,900', 'pinch:$x,$middle,300,120,900',
      if (zooms) 'taplabel:Zoom in;wait:300;taplabel:Zoom in;wait:300;taplabel:Zoom out;wait:300;taplabel:Zoom out;wait:300',
      'taplabel:Fit the whole canvas', 'wait:600',
      // A card picked, then carried by the finger that picked it, and back.
      'mark:canvas-card', 'tapkey:card sam', 'wait:400', 'dragkey:card sam,140,90,900', 'wait:300', 'dragkey:card sam,-140,-90,900', 'wait:400',
      // The picked card tapped again is open to be written in.
      'mark:canvas-write', 'tapkey:card sam', 'wait:900', 'type:$more', 'wait:600', 'backspace:${more.length}', 'wait:400',
      'mark:canvas-leave', 'unfocus', 'taplabel:Home', 'wait:1500',
    ],
    'notebook': [
      // The notebook's pages are given notes that are written, once (a library made for the walk has none that are).
      'mark:_seek', 'reach:Bench notebook', 'taptext:Bench notebook', 'wait:1500', 'fixture:chapters', 'taplabel:Home', 'wait:1200', 'reach:Bench notebook',
      'mark:notebook-open', 'taptext:Bench notebook', 'wait:2000',
      'mark:notebook-fling', flings(low, high, 2), flings(high, low, 2),
      // A page opened from the index, the next one from its bar, and back to the index by the bar.
      'mark:notebook-chapter', 'tapkey:book-chapter-4', 'wait:1800',
      'mark:notebook-next', 'tapkey:book-bar-next', 'wait:1800',
      'mark:notebook-back', 'tapkey:book-bar-book', 'wait:1800',
      'mark:_seek', 'reach:Read straight through',
      'mark:notebook-read-open', 'taptext:Read straight through', 'wait:1800',
      'mark:notebook-read', flings(low, high, 4), flings(high, low, 4),
      'mark:_seek', 'reach:Index',
      'mark:notebook-index', 'tapkey:book-index', 'wait:1200',
      'mark:notebook-leave', 'taplabel:Home', 'wait:1500',
    ],
    'allnotes': [
      // By the palette, as a person on any page gets there: the home page's own way is at its foot.
      'mark:_seek', 'taplabel:Search and commands', 'wait:900', 'type:All notes', 'wait:500',
      'mark:allnotes-open', 'enter', 'wait:2000',
      'mark:allnotes-fling', flings(low, high, 4), flings(high, low, 4),
      'mark:allnotes-search', 'taplabel:Search your notes', 'wait:600', 'type:fox', 'wait:900',
      'mark:allnotes-clear', 'taplabel:Clear the search', 'wait:900',
      'mark:allnotes-leave', 'unfocus', 'taplabel:Back to home', 'wait:1500',
    ],
    'sidebar': [
      'mark:sidebar-open', 'taplabel:All your notes', 'wait:1500',
      'mark:sidebar-fling', cardFlings(low, high, 3), cardFlings(high, low, 3),
      // Names only and back: every row made again, as a folder shut or opened makes them (the walk's library has
      // no workspace, so no folder).
      'mark:sidebar-names', 'taplabel:Show names only', 'wait:1200', cardFlings(low, high, 1), cardFlings(high, low, 1), 'taplabel:Show each note drawn small', 'wait:1200',
      'mark:sidebar-close', 'back', 'wait:1000',
    ],
    'search': [
      'mark:search-open', 'taplabel:Search and commands', 'wait:1200',
      // A note's name a letter at a time, the notes found under it at each.
      'mark:search-type', 'type:bench canvas', 'wait:600',
      'mark:search-pick', 'enter', 'wait:1800',
      'mark:search-leave', 'taplabel:Home', 'wait:1500',
    ],
    'palette': [
      'mark:palette-open', 'taplabel:Search and commands', 'wait:1200',
      // A command typed, taken back, and something nothing answers to.
      'mark:palette-type', 'type:theme', 'wait:500', 'backspace:5', 'wait:400', 'type:zzqq', 'wait:600',
      'mark:palette-close', 'back', 'wait:1000',
    ],
    'settings': [
      'mark:settings-open', 'taplabel:Settings', 'wait:1500',
      'mark:settings-fling', flings(low, high, 3), flings(high, low, 3),
      'mark:_seek', 'reach:Appearance',
      'mark:settings-page', 'taptext:Appearance', 'wait:1500', flings(low, high, 3), flings(high, low, 3),
      // Two pages more: About, and under it the cheat sheet, the page with the most rows. One page at a time, the
      // way to another is back through the list.
      // In two panes the sections are a column at the left, and About is under its foot: a finger down that column.
      'mark:_seek', if (split) 'swipe:160,$low,160,$high,400;wait:300;swipe:160,$low,160,$high,400;wait:300' else 'back;wait:700;reach:About',
      'mark:settings-about', 'taptext:About', 'wait:1500',
      'mark:_seek', 'reach:Cheat sheet',
      'mark:settings-cheatsheet', 'taptext:Cheat sheet', 'wait:1500', flings(low, high, 3), flings(high, low, 3),
      // Out the way a person came: the cheat sheet to About, (About to the list,) and out of Settings.
      'mark:settings-leave', 'back', 'wait:700', if (!split) 'back;wait:700', 'back', 'wait:1200',
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
    for (final old in ['report.json', 'done', 'vm.txt', 'read']) {
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

  // The CPU's samples are handed over between stretches (tool/perf_cpu.dart, a desktop's walk): a read stops this
  // isolate while the VM writes them out, and one that landed inside a stretch was that stretch's dropped frames
  // and the top of its profile. The reader takes the file away when it has read.
  final sampled = Platform.environment.containsKey('GHOST_PERF_HOLD');
  Future<void> handOver() async {
    if (!sampled) return;
    final ask = File('${dir.path}/read');
    try {
      ask.writeAsStringSync('now\n', flush: true);
    } catch (_) {
      return;
    }
    for (var waited = 0; waited < 100 && ask.existsSync(); waited += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      if (ask.existsSync()) ask.deleteSync();
    } catch (_) {}
  }

  for (final step in tourSteps(script)) {
    if (step.name == 'mark') {
      await walk();
      await log.mark(step.arg, between: handOver);
    } else if (_ownSteps.contains(step.name)) {
      await walk();
      await _ownStep(tour, step.name, step.arg);
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

// ---- the walk's own steps ----------------------------------------------------------------------------------------

/// The steps a walk has besides the tour's (lib/shell/phone_tour.dart).
const Set<String> _ownSteps = {'back', 'reach', 'tapkey', 'dragkey', 'pinch', 'fixture'};

/// One of the walk's own steps:
///
/// - `back`: the system's back, as Android's gesture sends it; a desktop's Escape walks the same stack
///   (lib/core/back.dart).
/// - `reach:<words>`: the tour's `seek`, unless the words are in the window already. A note that has been opened
///   has a tab in the bar, which is where `taptext` then finds its name, and `seek` took a name that high for one
///   to be scrolled down to: twenty-four pulls of the home page (each a pull to refresh) before every opening.
/// - `tapkey:<key>`: a tap in the middle of what wears that key; `dragkey:<key>,<dx>,<dy>[,<ms>]`: a finger put
///   down there and moved by that much.
/// - `pinch:<x>,<y>,<from>,<to>[,<ms>]`: two fingers either side of a point, from one distance apart to another.
/// - `fixture:chapters`: [_benchChapters].
Future<void> _ownStep(PhoneTour tour, String name, String arg) async {
  switch (name) {
    case 'back':
      ui.channelBuffers.push('flutter/navigation', const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
      await _frames();
    case 'reach':
      final at = _worded(arg);
      if (at == null || !_window().contains(at.center)) await tour.run('seek:$arg');
    case 'tapkey':
      await _tapKey(tour, arg);
    case 'dragkey':
      final parts = arg.split(',');
      final by = [for (final part in parts.skip(parts.length > 3 ? parts.length - 3 : 1)) double.parse(part.trim())];
      final key = parts.take(parts.length - by.length).join(',');
      final at = _keyed(key);
      debugPrint('[tour] dragkey "$key" -> ${at == null ? 'NOT FOUND' : '${at.center.dx.round()},${at.center.dy.round()}'}');
      if (at == null) return;
      final from = at.center;
      await tour.run('swipe:${from.dx.round()},${from.dy.round()},${(from.dx + by[0]).round()},${(from.dy + by[1]).round()},${by.length > 2 ? by[2].round() : 600}');
    case 'pinch':
      final n = [for (final part in arg.split(',')) double.parse(part.trim())];
      await _pinch(Offset(n[0], n[1]), n[2], n[3], ms: n.length > 4 ? n[4].round() : 600);
    case 'fixture':
      if (arg == 'chapters') await _benchChapters(tour);
  }
}

Future<void> _frames([int count = 2]) async {
  for (var i = 0; i < count; i += 1) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
}

Rect _window() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return Offset.zero & (view.physicalSize / view.devicePixelRatio);
}

/// Where the last text drawn that holds [words] is, as the tour's `taptext` finds it; null when none is drawn.
Rect? _worded(String words) {
  final window = _window();
  Rect? found;
  void visit(Element element) {
    final render = element.renderObject;
    if (element is RenderObjectElement && render is RenderOffstage && render.offstage) return;
    if (element is RenderObjectElement && render is RenderParagraph && render.attached && render.hasSize && render.text.toPlainText().contains(words)) {
      final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
      if (box.width > 0 && box.height > 0 && window.overlaps(box)) found = box;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Where what wears the key [key] (a `ValueKey` of that string) is in the window, if it is drawn there. What is
/// kept out of sight is not found, as the tour finds none of it.
Rect? _keyed(String key) {
  final window = _window();
  Rect? found;
  void visit(Element element) {
    if (found != null) return;
    final render = element.renderObject;
    if (element is RenderObjectElement && render is RenderOffstage && render.offstage) return;
    final worn = element.widget.key;
    if (worn is ValueKey<String> && worn.value == key && render is RenderBox && render.attached && render.hasSize) {
      final box = MatrixUtils.transformRect(render.getTransformTo(null), Offset.zero & render.size);
      if (box.width > 0 && box.height > 0 && window.overlaps(box)) {
        found = box;
        return;
      }
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<bool> _tapKey(PhoneTour tour, String key, {bool quiet = false}) async {
  final at = _keyed(key);
  if (at == null) {
    if (!quiet) debugPrint('[tour] tapkey "$key" -> NOT FOUND');
    return false;
  }
  await tour.run('tap:${at.center.dx.round()},${at.center.dy.round()}');
  return true;
}

int _finger = 9800;

/// Two fingers either side of [about], [from] apart, moved until they are [to] apart, and lifted.
Future<void> _pinch(Offset about, double from, double to, {required int ms}) async {
  final a = _finger += 1, b = _finger += 1;
  final clock = Stopwatch()..start();
  Offset left(double apart) => about - Offset(apart / 2, 0);
  Offset right(double apart) => about + Offset(apart / 2, 0);
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(PointerAddedEvent(pointer: a, position: left(from), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerDownEvent(pointer: a, position: left(from), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerAddedEvent(pointer: b, position: right(from), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerDownEvent(pointer: b, position: right(from), timeStamp: clock.elapsed));
  final steps = (ms / 16).ceil().clamp(4, 120);
  var was = from;
  for (var i = 1; i <= steps; i += 1) {
    final apart = from + (to - from) * i / steps;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    binding.handlePointerEvent(PointerMoveEvent(pointer: a, position: left(apart), delta: left(apart) - left(was), timeStamp: clock.elapsed));
    binding.handlePointerEvent(PointerMoveEvent(pointer: b, position: right(apart), delta: right(apart) - right(was), timeStamp: clock.elapsed));
    was = apart;
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));
  binding.handlePointerEvent(PointerUpEvent(pointer: a, position: left(to), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerRemovedEvent(pointer: a, position: left(to), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerUpEvent(pointer: b, position: right(to), timeStamp: clock.elapsed));
  binding.handlePointerEvent(PointerRemovedEvent(pointer: b, position: right(to), timeStamp: clock.elapsed));
  await _frames();
  debugPrint('[tour] pinch ${about.dx.round()},${about.dy.round()} ${from.round()} -> ${to.round()}');
}

/// How many written pages the walk's notebook is given.
const int _benchPages = 16;

/// The made-up notes the walk's notebook takes for its pages: notes of words (tickets first, half of them), among
/// the older ones, which stand far down the home page where no other part of the walk goes. By the seed's own rule
/// (lib/perf/perf_seed.dart), so they are the same notes in every library made for a walk.
List<String> _benchPageTitles() {
  final examples = [...seedLibrary(null), ...starterNotes(0)];
  final tickets = <String>[], others = <String>[];
  for (var i = 20; i < 150; i += 1) {
    final body = perfBody(examples[i % examples.length].body, i);
    // Not a canvas, a notebook or a journal, and not a journal's entry, which is named by the minute it was made.
    if (body.contains('"nodes"') || body.contains('book: true') || body.contains('\ndate: ')) continue;
    final title = noteTitle(body);
    // Plain letters only: the title is typed into the picker and taken out again a key at a time.
    if (title.isEmpty || title.contains(';') || title.codeUnits.any((unit) => unit > 126)) continue;
    (body.contains('type: ticket') ? tickets : others).add(title);
  }
  final some = tickets.take(_benchPages ~/ 2).toList();
  return [...some, ...others.take(_benchPages - some.length)];
}

/// Gives the notebook on screen pages that are written, through its own picker (Add a note you have), unless it
/// has them: a library made for the walk names every note with its number, so the pages its notebooks list are
/// notes nobody wrote, and an index of three rows that say so, with nothing to read straight through, is no
/// notebook to measure. Done once for a library; after that it finds the pages there and touches nothing.
Future<void> _benchChapters(PhoneTour tour) async {
  String? body;
  void visit(Element element) {
    if (body != null) return;
    final widget = element.widget;
    if (widget is BookView) {
      body = widget.body;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  final index = body;
  if (index == null) {
    debugPrint('[tour] fixture chapters: NOT FOUND, no notebook on screen');
    return;
  }
  final chapters = chaptersOf(index);
  final missing = [
    for (final title in _benchPageTitles())
      if (!chapters.any((chapter) => sameTitle(chapter.title, title))) title,
  ];
  if (missing.isEmpty) return;
  // A page at a time: the picker opened, the page's whole title typed into its field, its row ticked, and Add. (Not
  // every title into one opening of it: a field that has given up the keyboard to a row's press has no caret to
  // take the last title out from, and the next was typed after it.)
  var picked = 0;
  for (final title in missing) {
    await tour.run('seek:Add a note you have;taptext:Add a note you have;wait:400');
    if (!await _tapKey(tour, 'book-find')) break;
    await tour.run('wait:200;type:$title;wait:200');
    if (await _tapKey(tour, 'book-pick:$title', quiet: true) && await _tapKey(tour, 'book-add-picked')) {
      picked += 1;
    } else {
      await tour.run('taptext:Cancel');
    }
    await tour.run('unfocus;wait:400');
  }
  debugPrint('[tour] fixture chapters: $picked pages added to the notebook');
}

