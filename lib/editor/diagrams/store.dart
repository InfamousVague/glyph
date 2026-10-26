/// The diagrams that have been drawn, and the line the ones still to draw wait in. Ports the `drawn` map and the
/// `queue` of `src/app/editor/mermaid.ts`, with what a web view across a channel needs that a library in the page
/// did not.
///
/// - **Drawn once.** A picture is kept by what decides it ([DiagramAsk.key]): in memory, so scrolling past a
///   diagram draws nothing, and in the app's cache folder (`<cache>/diagrams`), so a note opened again has its
///   diagrams without a web view being asked. A diagram written wrong is kept too, as the page keeps it, by what
///   Mermaid said of it; one that could not be drawn for another reason is kept only while the app is open.
/// - **One at a time.** Mermaid keeps its settings in one place, and the web view is one page: a render waits for
///   the one before it.
/// - **Only what is still wanted.** Whoever asks says who they are (a `slot`: one drawn block). A block that asks
///   again, because its words changed again, lets go of what it asked before, and a render nobody waits for any
///   more is taken out of the line before its turn. So a diagram typed into while it is drawn (the Academy's page, a
///   note another member is writing) costs the render under way and one more, however fast the letters come: the
///   page has no pause before it draws, and this needs none.
///
/// What differs:
/// - The page's map is every diagram drawn since the app was opened, for ever; here memory is bounded
///   ([DiagramStore.memory] bytes of pictures, the least lately shown let go first) and so is the folder
///   ([DiagramStore.files]).
/// - The page kept the picture as an SVG, drawn by the browser at any size; here it is a bitmap at the device's
///   ratio, made for one width, and a note shown at another width asks again.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/iphone_app.dart';
import '../../core/mac_app.dart';
import '../../core/native/device_paths.dart';
import '../../format/body_hash.dart' show fnvOffsetBasis;
import 'bridge.dart';
import '../../core/host_platform.dart';

/// What a block shows of its diagram.
sealed class DiagramDrawing {
  const DiagramDrawing();
}

/// A diagram's picture, decoded, and where it sits in its block. Whoever is handed one owns it and lets it go
/// ([dispose]); the store's own stays in the store.
class DiagramPicture extends DiagramDrawing {
  DiagramPicture({required this.image, required this.block, required this.at, required this.scale});

  final ui.Image image;

  /// The block's size (`.cm-mermaid`, its padding included), in logical pixels.
  final ui.Size block;

  /// Where in the block the picture is.
  final ui.Rect at;

  /// Pixels of the picture to the logical one.
  final double scale;

  /// How much memory the picture takes.
  int get bytes => image.width * image.height * 4;

  /// The same picture for another holder.
  DiagramPicture share() => DiagramPicture(image: image.clone(), block: block, at: at, scale: scale);

  void dispose() => image.dispose();
}

/// A diagram that was not drawn: [said] is Mermaid's words for one written wrong, empty where the fault is not the
/// person's ([DiagramFailed]).
class DiagramMistake extends DiagramDrawing {
  const DiagramMistake(this.said);

  final String said;
}

/// A PNG's bytes as a picture.
typedef DiagramDecoder = Future<ui.Image> Function(Uint8List png);

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

class _Job {
  _Job(this.ask) : key = ask.key;

  final DiagramAsk ask;
  final String key;

  /// Who waits for it, each with the answer they are owed.
  final Map<Object, Completer<DiagramDrawing?>> waiting = <Object, Completer<DiagramDrawing?>>{};

  /// In the web view now: it cannot be called back.
  bool running = false;
}

class DiagramStore {
  DiagramStore({required this.bridge, Future<String?> Function()? folder, DiagramDecoder? decode, this.memory = 32 << 20, this.files = 240})
    : _findFolder = folder,
      _decodePng = decode ?? _decode;

  final DiagramBridge bridge;

  /// The most memory the kept pictures take, in bytes; the one just drawn is always kept.
  final int memory;

  /// The most pictures kept in the folder.
  final int files;

  final Future<String?> Function()? _findFolder;
  final DiagramDecoder _decodePng;

  /// Drawn, by key, the least lately shown first.
  final LinkedHashMap<String, DiagramDrawing> _held = LinkedHashMap<String, DiagramDrawing>();
  int _bytes = 0;

  /// Asked for and not yet answered, by key; [_line] is the ones waiting for the web view, in order.
  final Map<String, _Job> _jobs = <String, _Job>{};
  final Queue<_Job> _line = Queue<_Job>();
  bool _drawing = false;

  /// How many times the web view was asked, and how many pictures came from the folder: for tests.
  int renders = 0;
  int reads = 0;

  Future<Directory?>? _folder;
  bool _pruned = false;

  Future<Directory?> _dir() => _folder ??= () async {
    try {
      final cache = await _findFolder?.call();
      if (cache == null) return null;
      return await Directory('$cache/diagrams').create(recursive: true);
    } on Object {
      return null;
    }
  }();

  /// What memory has for [ask], now: a picture of the caller's own, a mistake, or null.
  DiagramDrawing? held(DiagramAsk ask) => _share(ask.key);

  DiagramDrawing? _share(String key) {
    final kept = _held.remove(key);
    if (kept == null) return null;
    // Shown again: the last to be let go.
    _held[key] = kept;
    return kept is DiagramPicture ? kept.share() : kept;
  }

  /// The drawing for [ask]: what memory has, else what the folder has, else what the web view draws when its turn
  /// comes. [slot] is who asks: asking again from the same slot lets go of what it asked before, and the answer to
  /// that is then null. A picture answered is the caller's own, to dispose.
  Future<DiagramDrawing?> draw(DiagramAsk ask, {required Object slot}) {
    final key = ask.key;
    _release(slot, except: key);
    final kept = _share(key);
    if (kept != null) return Future<DiagramDrawing?>.value(kept);
    var job = _jobs[key];
    if (job == null) {
      job = _jobs[key] = _Job(ask);
      unawaited(_begin(job));
    }
    return (job.waiting[slot] ??= Completer<DiagramDrawing?>()).future;
  }

  /// [slot] wants nothing any more: its block has left the page.
  void forget(Object slot) => _release(slot);

  void _release(Object slot, {String? except}) {
    for (final job in _jobs.values.toList()) {
      if (job.key == except) continue;
      job.waiting.remove(slot)?.complete(null);
      // Nobody waits for it and the web view has not begun it: out of the line.
      if (job.waiting.isEmpty && !job.running && _line.remove(job)) _jobs.remove(job.key);
    }
  }

  Future<void> _begin(_Job job) async {
    final kept = await _read(job.key);
    if (kept != null) {
      _finish(job, kept);
      return;
    }
    if (job.waiting.isEmpty) {
      _jobs.remove(job.key);
      return;
    }
    _line.add(job);
    _next();
  }

  void _next() {
    if (_drawing || _line.isEmpty) return;
    final job = _line.removeFirst();
    _drawing = true;
    job.running = true;
    unawaited(_render(job));
  }

  Future<void> _render(_Job job) async {
    DiagramDrawing made;
    try {
      renders += 1;
      final answer = await bridge.draw(job.ask);
      switch (answer) {
        case DiagramDrawn():
          made = DiagramPicture(image: await _decodePng(answer.png), block: answer.block, at: answer.at, scale: answer.scale);
          unawaited(_write(job.key, answer));
        case DiagramFailed():
          made = DiagramMistake(answer.said);
          // Mermaid's own words for these words are the same tomorrow: kept, so a note with a diagram written wrong
          // does not make a web view each time it is opened. What is not the person's mistake is asked again.
          if (answer.said.isNotEmpty) unawaited(_write(job.key, answer));
      }
    } on Object {
      // The line is only a place in line: one diagram's failure must not stop the ones behind it.
      made = const DiagramMistake('');
    }
    _drawing = false;
    _finish(job, made);
    _next();
  }

  void _finish(_Job job, DiagramDrawing made) {
    _jobs.remove(job.key);
    _put(job.key, made);
    for (final waiter in job.waiting.values) {
      waiter.complete(made is DiagramPicture ? made.share() : made);
    }
    job.waiting.clear();
  }

  void _put(String key, DiagramDrawing made) {
    final old = _held.remove(key);
    if (old is DiagramPicture) {
      _bytes -= old.bytes;
      old.dispose();
    }
    _held[key] = made;
    if (made is DiagramPicture) _bytes += made.bytes;
    while (_bytes > memory && _held.length > 1) {
      final oldest = _held.remove(_held.keys.first);
      if (oldest is DiagramPicture) {
        _bytes -= oldest.bytes;
        oldest.dispose();
      }
    }
  }

  /// Lets go of every picture in memory; the folder keeps its own. For a test, and for memory asked back.
  void clearMemory() {
    for (final kept in _held.values) {
      if (kept is DiagramPicture) kept.dispose();
    }
    _held.clear();
    _bytes = 0;
  }

  // -- the folder -------------------------------------------------------------------------------------------------

  static const List<int> _magic = <int>[0x47, 0x44, 0x47, 0x31]; // GDG1

  Future<DiagramDrawing?> _read(String key) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${diagramFile(key)}');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 8 || bytes[0] != _magic[0] || bytes[1] != _magic[1] || bytes[2] != _magic[2] || bytes[3] != _magic[3]) return null;
      final head = ByteData.sublistView(bytes, 4, 8).getUint32(0);
      if (bytes.length < 8 + head) return null;
      final said = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, 8, 8 + head))) as Map<String, Object?>;
      // Two keys with one name: not this picture.
      if (said['key'] != key) return null;
      final failed = said['failed'];
      if (failed is String) {
        reads += 1;
        return failed.isEmpty ? null : DiagramMistake(failed);
      }
      double number(String name) => (said[name] as num).toDouble();
      final image = await _decodePng(Uint8List.sublistView(bytes, 8 + head));
      reads += 1;
      // Shown again: among the last the folder lets go.
      unawaited(file.setLastModified(DateTime.now()).then<void>((_) {}, onError: (Object _) {}));
      return DiagramPicture(
        image: image,
        block: ui.Size(number('bw'), number('bh')),
        at: ui.Rect.fromLTWH(number('x'), number('y'), number('w'), number('h')),
        scale: number('s'),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, DiagramAnswer answer) async {
    final dir = await _dir();
    if (dir == null) return;
    try {
      final head = utf8.encode(
        jsonEncode(switch (answer) {
          DiagramDrawn() => <String, Object?>{'key': key, 'bw': answer.block.width, 'bh': answer.block.height, 'x': answer.at.left, 'y': answer.at.top, 'w': answer.at.width, 'h': answer.at.height, 's': answer.scale},
          DiagramFailed() => <String, Object?>{'key': key, 'failed': answer.said},
        }),
      );
      final out = BytesBuilder(copy: false)
        ..add(_magic)
        ..add((ByteData(4)..setUint32(0, head.length)).buffer.asUint8List())
        ..add(head);
      if (answer is DiagramDrawn) out.add(answer.png);
      final path = '${dir.path}/${diagramFile(key)}';
      // Whole or not at all: a picture half written is never read.
      final part = File('$path.part');
      await part.writeAsBytes(out.takeBytes(), flush: false);
      await part.rename(path);
      if (!_pruned) {
        _pruned = true;
        await _prune(dir);
      }
    } on Object {
      // A full disk, a folder taken away: the picture is in memory, and is drawn again another day.
    }
  }

  /// Past [files] pictures, the ones shown longest ago are let go, down to four fifths of it.
  Future<void> _prune(Directory dir) async {
    final all = <(File, DateTime)>[];
    await for (final entry in dir.list()) {
      if (entry is File) all.add((entry, (await entry.stat()).modified));
    }
    if (all.length <= files) return;
    all.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (file, _) in all.take(all.length - files * 4 ~/ 5)) {
      await file.delete();
    }
  }
}

/// The file a key's picture is kept in: the key's length and its FNV-1a hash, 64 bits wide. The key itself is
/// written inside, and read back before the picture is believed.
String diagramFile(String key) {
  var hash = fnvOffsetBasis;
  for (var i = 0; i < key.length; i += 1) {
    hash ^= key.codeUnitAt(i);
    hash *= 0x100000001b3;
  }
  String half(int value) => value.toRadixString(16).padLeft(8, '0');
  return '${key.length.toRadixString(36)}-${half(hash >>> 32)}${half(hash & 0xffffffff)}.diagram';
}

DiagramStore? _store;

/// Whether this is the app on a device of its own, with a web view behind `ghost_md/diagrams` and a cache folder:
/// not a test on the Mac, nor a platform the app has no web view on.
bool get _onDevice => Platform.isAndroid || runsAsMacApp || runsAsIPhoneApp;

/// The app's diagrams. The web view's, with the app's cache folder under it, unless a test has put its own here;
/// and where there is no web view to ask, every diagram is answered at once as one that cannot be drawn here, and
/// stays its text.
DiagramStore get diagramStore => _store ??= _onDevice ? DiagramStore(bridge: ChannelDiagramBridge(), folder: _cacheFolder) : DiagramStore(bridge: const NoDiagramBridge());

set diagramStore(DiagramStore store) => _store = store;

/// Nothing to draw a diagram with: each is "could not be drawn here", said at once.
class NoDiagramBridge implements DiagramBridge {
  const NoDiagramBridge();

  @override
  Future<DiagramAnswer> draw(DiagramAsk ask) async => const DiagramFailed('');
}

Future<String?> _cacheFolder() async => (await DevicePaths.find()).cacheDir;
