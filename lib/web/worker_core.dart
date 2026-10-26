/// The browser's core, asked across to its worker (web/core/ghost_core_worker.js): what ghost_core.dart is to the
/// phone's isolate. Only in the web build.
///
/// A command is posted with its arguments written as JSON and answered by the core's own `{"ok"}` or `{"err"}`,
/// in the order asked, so the drawing never waits on a 600,000-round derivation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/native/core.dart';

class WorkerCore {
  WorkerCore._(this._worker);

  final web.Worker _worker;
  final Map<int, Completer<Object?>> _waiting = {};
  int _next = 0;

  /// Starts the worker and waits for its core to open. Throws [CoreError] where it will not: no WebAssembly, or
  /// the file could not be fetched.
  static Future<WorkerCore> open({String script = 'core/ghost_core_worker.js'}) async {
    final worker = web.Worker(script.toJS);
    final ready = Completer<void>();
    final core = WorkerCore._(worker);
    worker.onmessage = ((web.MessageEvent event) {
      final said = event.data.dartify();
      if (said is! Map) return;
      if (said['ready'] == true) {
        if (!ready.isCompleted) ready.complete();
      } else if (said['failed'] != null) {
        if (!ready.isCompleted) ready.completeError(CoreError('Ghost.md\'s core would not open in this browser: ${said['failed']}'));
      } else {
        core._answered(said);
      }
    }).toJS;
    worker.onerror = ((web.Event event) {
      final message = event.isA<web.ErrorEvent>() ? (event as web.ErrorEvent).message : 'the worker failed';
      if (!ready.isCompleted) ready.completeError(CoreError('Ghost.md\'s core would not open in this browser: $message'));
      core._lost('Ghost.md\'s core stopped: $message');
    }).toJS;
    await ready.future.timeout(const Duration(seconds: 30), onTimeout: () => throw const CoreError('Ghost.md\'s core took too long to open.'));
    return core;
  }

  /// Asks the core: a [CoreInvoke].
  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) {
    final id = _next++;
    final answer = Completer<Object?>();
    _waiting[id] = answer;
    final String sent;
    try {
      sent = jsonEncode(args);
    } catch (failure) {
      _waiting.remove(id);
      return Future.error(CoreError('Ghost.md\'s core could not be asked $command: $failure'));
    }
    _worker.postMessage({'id': id, 'command': command, 'args': sent}.jsify());
    return answer.future;
  }

  void _answered(Map<Object?, Object?> said) {
    final id = said['id'];
    final answer = id is num ? _waiting.remove(id.toInt()) : null;
    if (answer == null) return;
    try {
      final decoded = jsonDecode(said['answer'] as String);
      if (decoded case {'ok': final value}) {
        answer.complete(value);
      } else if (decoded case {'err': final String sentence}) {
        answer.completeError(CoreError(sentence));
      } else {
        answer.completeError(const CoreError('Ghost.md\'s core gave an answer that is neither ok nor err.'));
      }
    } catch (failure) {
      answer.completeError(CoreError('Ghost.md\'s core gave an answer that is not JSON: $failure'));
    }
  }

  void _lost(String why) {
    final lost = _waiting.values.toList();
    _waiting.clear();
    for (final answer in lost) {
      answer.completeError(CoreError(why));
    }
  }
}
