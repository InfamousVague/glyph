// A WEB device in a live room, for a test to drive: tool/web_live.mjs under Node (the web app's own
// core/live, its own Yjs and y-protocols, its own WebCrypto), spoken to a line of JSON at a time.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Why the web device cannot run here, or null when it can.
String? webSkip(String base) {
  if (base.isEmpty) return 'no local server: run tool/local-server.sh start and set GHOST_E2E_API';
  if (!Directory('tauri/node_modules/yjs').existsSync()) return 'tauri/ has no node_modules/yjs for the web client to load';
  try {
    if (Process.runSync('node', ['--version']).exitCode != 0) return '`node` did not run';
  } on ProcessException {
    return '`node` is not on the PATH';
  }
  return null;
}

class WebDevice {
  WebDevice._(this._process, this._lines, this.hello);

  /// Starts the web device on [job] (tool/web_live.mjs says what one is) and waits until it is in its room.
  static Future<WebDevice> start(String base, Map<String, Object?> job) async {
    final process = await Process.start('node', ['--experimental-transform-types', '--no-warnings', 'tool/web_live.mjs', jsonEncode(job)], environment: {'GHOST_E2E_API': base});
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final lines = StreamIterator(process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    if (!await lines.moveNext()) fail('the web device never came up (${await process.exitCode}):\n$errors');
    final hello = (jsonDecode(lines.current) as Map).cast<String, Object?>();
    expect(hello['apiBase'], base, reason: 'the web device spoke to the local server and nothing else');
    return WebDevice._(process, lines, hello).._errors = errors;
  }

  final Process _process;
  final StreamIterator<String> _lines;
  late final StringBuffer _errors;

  /// What it said once in its room: `handle`, `org`, `words`, `client`.
  final Map<String, Object?> hello;
  int _id = 0;

  /// One command, answered.
  Future<Map<String, Object?>> ask(Map<String, Object?> command) async {
    final id = _id += 1;
    _process.stdin.writeln(jsonEncode({...command, 'id': id}));
    await _process.stdin.flush();
    if (!await _lines.moveNext()) fail('the web device went away during ${command['do']}:\n$_errors');
    final said = (jsonDecode(_lines.current) as Map).cast<String, Object?>();
    if (said['error'] != null) fail('the web device failed at ${command['do']}:\n${said['error']}');
    expect(said['id'], id);
    return said;
  }

  /// Waits, on the web device, for what [want] names; fails with what it held instead.
  Future<Map<String, Object?>> until(Map<String, Object?> want, String what) async {
    final said = await ask({'do': 'until', ...want});
    expect(said['ok'], isTrue, reason: 'the web device never saw $what; it holds ${jsonEncode(said)}');
    return said;
  }

  Future<String> words() async => (await ask({'do': 'words'}))['words'] as String;

  Future<void> close() async {
    try {
      await ask({'do': 'close'});
    } catch (_) {
      _process.kill();
    }
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}
