// What the tests of the native capture and the native model share (test/capture_native, test/ai_native): the
// Mac's core opened on a folder of the test's own, the web app's model files (tauri/models, only ever read:
// linked to, or served from 127.0.0.1), the fixture recording as samples, and a server on 127.0.0.1 that can cut
// a download partway.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const library = 'native/target/debug/libghost_core.dylib';

/// The web app's models: `GLYPH_MODELS_DIR`, or tauri/models.
Directory get webModels => Directory(Platform.environment['GLYPH_MODELS_DIR'] ?? 'tauri/models').absolute;

/// A core for one test file, with a data directory of its own, removed by [close].
class TestCore {
  TestCore._(this.core, this.root);

  final GhostCore core;
  final Directory root;

  String get dataDir => '${root.path}/data';
  Directory get models => Directory('$dataDir/models');
  Directory get recordings => Directory('$dataDir/recordings');

  /// Why the tests cannot run here, or null: the library not built, or built without the engines.
  static Future<String?> missing() async {
    if (!File(library).existsSync()) return 'the Mac\'s core is not built: run tool/build-native.sh host';
    return null;
  }

  /// Opens the core on a fresh folder. [link] names the model files (under tauri/models, `llm/` included) to
  /// link into its `models/`, so the core finds them present without a byte being copied.
  static Future<TestCore> open(String label, {List<String> link = const []}) async {
    final root = Directory.systemTemp.createTempSync('ghost-$label-');
    final models = Directory('${root.path}/data/models')..createSync(recursive: true);
    for (final name in link) {
      Link('${models.path}/${name.split('/').last}').createSync('${webModels.path}/$name');
    }
    final core = await GhostCore.open(libraryPath: File(library).absolute.path);
    await core.init(dataDir: '${root.path}/data', cacheDir: '${root.path}/cache');
    return TestCore._(core, root);
  }

  /// Whether this library has the engines at all (built with GHOST_VOICE=0 it has no such command).
  Future<bool> get hasVoice async {
    try {
      await core.invoke('native_status');
      return true;
    } on CoreError {
      return false;
    }
  }

  Future<void> close() async {
    await core.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// A WAV file's samples as 16 kHz mono floats: PCM16, whatever chunks come before its `data`.
Float32List wavSamples(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var at = 12;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = data.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      final count = (size.clamp(0, bytes.length - at - 8)) ~/ 2;
      final out = Float32List(count);
      for (var i = 0; i < count; i += 1) {
        out[i] = data.getInt16(at + 8 + i * 2, Endian.little) / 32768;
      }
      return out;
    }
    at += 8 + size + (size & 1);
  }
  throw StateError('${file.path} has no data chunk');
}

/// [samples] in chunks of 200 ms, as the microphone hands them over.
List<Float32List> chunksOf(Float32List samples, [int chunk = 3200]) => [
      for (var at = 0; at < samples.length; at += chunk) Float32List.sublistView(samples, at, at + chunk > samples.length ? samples.length : at + chunk),
    ];

/// A server on 127.0.0.1 that serves the files of [folder] by name, honours `Range: bytes=n-`, and closes its
/// FIRST connection after [cutAfter] bytes of the body (null: never), the way a phone's connection drops.
class CuttingServer {
  CuttingServer._(this._server, this.folder, this.cutAfter);

  final ServerSocket _server;
  final Directory folder;
  final int? cutAfter;

  /// Each request as its path, " from " and the first byte asked for.
  final List<String> requests = [];

  String get base => 'http://127.0.0.1:${_server.port}';

  static Future<CuttingServer> start(Directory folder, {int? cutAfter}) async {
    final server = CuttingServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), folder, cutAfter);
    server._server.listen(server._serve);
    return server;
  }

  Future<void> _serve(Socket socket) async {
    final head = BytesBuilder();
    final asked = Completer<String>();
    final sub = socket.listen((bytes) {
      head.add(bytes);
      final text = String.fromCharCodes(head.toBytes());
      if (text.contains('\r\n\r\n') && !asked.isCompleted) asked.complete(text);
    }, onError: (Object _) {}, onDone: () {
      if (!asked.isCompleted) asked.complete('');
    });
    final request = await asked.future;
    try {
      final path = Uri.decodeComponent(request.split(' ').elementAtOrNull(1) ?? '/');
      final range = RegExp(r'range: bytes=(\d+)-', caseSensitive: false).firstMatch(request);
      final from = range == null ? 0 : int.parse(range.group(1)!);
      final first = requests.isEmpty;
      requests.add('$path from $from');
      final file = File('${folder.path}$path');
      if (path.contains('..') || !file.existsSync()) {
        socket.write('HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n');
        await socket.flush();
        return;
      }
      final total = file.lengthSync();
      socket.write(from > 0
          ? 'HTTP/1.1 206 Partial Content\r\ncontent-range: bytes $from-${total - 1}/$total\r\ncontent-length: ${total - from}\r\nconnection: close\r\n\r\n'
          : 'HTTP/1.1 200 OK\r\ncontent-length: $total\r\nconnection: close\r\n\r\n');
      final cut = cutAfter;
      final end = first && cut != null ? (from + cut).clamp(0, total) : total;
      await socket.addStream(file.openRead(from, end));
      await socket.flush();
    } catch (_) {
      // The other side went away: nothing to answer.
    } finally {
      await sub.cancel();
      socket.destroy();
    }
  }

  Future<void> close() => _server.close();
}
