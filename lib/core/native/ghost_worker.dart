/// The isolate that owns the Rust core's library and calls into it: the far end of ghost_core.dart, and the only
/// Dart that touches `dart:ffi`. It speaks to native/src/ffi.rs, whose header has the C signatures.
///
/// The web app had no such file: Tauri's `invoke` crossed to Rust on Tauri's own threads. Here a command is a
/// blocking C call (a save writes a file and the index; `list_notes` walks the folder), so it is made on this
/// isolate and never on the one that draws.
///
/// **One at a time, in the order asked.** The isolate's port is the queue: a request is read, run to its end and
/// answered before the next is read. Rust would take the library's lock for each anyway (dispatch.rs's
/// `NotesStore`), so nothing is lost, and a save followed by a list is answered in that order.
///
/// **What crosses the port** is plain lists, which an isolate copies without ceremony:
///
/// - to the worker: `[id, command, args]` for a command (`args` the JSON-able map the page would have sent), or
///   `null` to close;
/// - from the worker, once: its `SendPort`, or a `String` saying why the library could not be opened;
/// - from the worker, per request: `[id, true, value]` or `[id, false, sentence]`;
/// - from the worker, per event from Rust: `[event, payload]` (a name and its decoded payload).
///
/// **Events** (native/src/events.rs) reach this isolate through a `NativeCallable.listener`, which any Rust
/// thread may call: the call is posted here and read on this isolate's next turn, so an event waits for the
/// command in hand, and that is why a long job answers its id at once (native/src/work.rs). Rust allocated the
/// event's bytes; they are decoded and given back to `ghost_free` here. The last worker to open is the one that
/// hears: a process has one core and the core one listener.
///
/// The arguments are written as JSON here and the answer is read from JSON here, so the drawing isolate neither
/// encodes nor parses: it receives the decoded value.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

/// What [ghostWorkerMain] is started with: where to send answers, and the library to open (`null` for the
/// platform's own name, [defaultLibraryName]).
typedef GhostWorkerStart = (SendPort answers, String? libraryPath);

/// The library as the app carries it: `libghost_core.so` in the APK's `jniLibs` (tool/build-native.sh puts it
/// there), found by name. Elsewhere the name the linker would look for; the Mac's tests give a path instead.
String get defaultLibraryName {
  if (Platform.isAndroid || Platform.isLinux) return 'libghost_core.so';
  if (Platform.isWindows) return 'ghost_core.dll';
  return 'libghost_core.dylib';
}

typedef _AllocC = Pointer<Uint8> Function(Size len);
typedef _Alloc = Pointer<Uint8> Function(int len);
typedef _FreeC = Void Function(Pointer<Uint8> ptr, Size len);
typedef _Free = void Function(Pointer<Uint8> ptr, int len);
typedef _InvokeC =
    Pointer<Uint8> Function(Pointer<Uint8> cmd, Size cmdLen, Pointer<Uint8> args, Size argsLen, Pointer<Size> outLen);
typedef _Invoke =
    Pointer<Uint8> Function(Pointer<Uint8> cmd, int cmdLen, Pointer<Uint8> args, int argsLen, Pointer<Size> outLen);
typedef _ListenerC = Void Function(Pointer<Uint8> json, Size len);
typedef _SetListenerC = Void Function(Pointer<NativeFunction<_ListenerC>> listener);
typedef _SetListener = void Function(Pointer<NativeFunction<_ListenerC>> listener);

/// What an event from Rust is decoded to before it crosses to the app's isolate: `[event, payload]`, or null
/// for bytes that are not an event.
List<Object?>? _eventOf(Object? said) {
  if (said case {'event': final String event}) return [event, said['payload']];
  return null;
}

/// The core's C functions, looked up once.
class _Native {
  _Native(DynamicLibrary library)
    : _alloc = library.lookupFunction<_AllocC, _Alloc>('ghost_alloc'),
      _free = library.lookupFunction<_FreeC, _Free>('ghost_free'),
      _invoke = library.lookupFunction<_InvokeC, _Invoke>('ghost_invoke'),
      setListener = library.lookupFunction<_SetListenerC, _SetListener>('ghost_set_listener'),
      forgetListener = library.lookupFunction<_SetListenerC, _SetListener>('ghost_forget_listener') {
    _outLen = _alloc(sizeOf<Size>()).cast<Size>();
    if (_outLen == nullptr) throw StateError('no memory');
  }

  final _Alloc _alloc;
  final _Free _free;
  final _Invoke _invoke;
  final _SetListener setListener;
  final _SetListener forgetListener;

  /// Where `ghost_invoke` writes its answer's length: one slot, kept for the life of the worker.
  late final Pointer<Size> _outLen;

  static final _readAnswer = utf8.decoder.fuse(json.decoder);

  /// `bytes` in a buffer of the core's own (ghost_alloc), to be given back with [_free].
  Pointer<Uint8> _lend(List<int> bytes) {
    final ptr = _alloc(bytes.length);
    if (ptr == nullptr) throw StateError('no memory');
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }

  /// An event's bytes (Rust's buffer, ours to give back) as `[event, payload]`.
  List<Object?>? takeEvent(Pointer<Uint8> json, int length) {
    try {
      return _eventOf(_readAnswer.convert(json.asTypedList(length)));
    } on Object {
      return null;
    } finally {
      _free(json, length);
    }
  }

  /// One command, answered as the core's `{"ok": ..}` or `{"err": ".."}`, decoded.
  Object? call(String command, Object? args) {
    final cmd = utf8.encode(command);
    final sent = args == null ? const <int>[] : utf8.encode(jsonEncode(args));
    final cmdPtr = _lend(cmd);
    final sentPtr = _lend(sent);
    try {
      final out = _invoke(cmdPtr, cmd.length, sentPtr, sent.length, _outLen);
      final length = _outLen.value;
      try {
        return _readAnswer.convert(out.asTypedList(length));
      } finally {
        _free(out, length);
      }
    } finally {
      _free(cmdPtr, cmd.length);
      _free(sentPtr, sent.length);
    }
  }
}

/// The worker isolate's entry (`Isolate.spawn(ghostWorkerMain, (port, path))`): opens the library, says it is
/// ready, and answers requests until it is sent `null`.
void ghostWorkerMain(GhostWorkerStart start) {
  final (answers, libraryPath) = start;
  final _Native native;
  try {
    native = _Native(DynamicLibrary.open(libraryPath ?? defaultLibraryName));
  } on Object catch (e) {
    answers.send('Ghost.md\'s core could not be loaded: $e');
    return;
  }
  final requests = ReceivePort('ghost core requests');
  // Rust calls this from its own threads; the body runs here, on this isolate, a turn later.
  final listener = NativeCallable<_ListenerC>.listener((Pointer<Uint8> json, int length) {
    final event = native.takeEvent(json, length);
    if (event != null) answers.send(event);
  });
  native.setListener(listener.nativeFunction);
  answers.send(requests.sendPort);
  requests.listen((message) {
    if (message == null) {
      // The library stays loaded and its notes stay open: a process has one core (dispatch.rs `CORE`), which
      // another worker opened after this one finds as it was left. Rust forgets this listener before it is
      // closed (and only this one: a newer worker's stays), after which it is never called again.
      native.forgetListener(listener.nativeFunction);
      listener.close();
      requests.close();
      return;
    }
    final [id as int, command as String, args] = message as List<Object?>;
    try {
      final said = native.call(command, args);
      if (said case {'ok': final value}) {
        answers.send([id, true, value]);
      } else if (said case {'err': final String sentence}) {
        answers.send([id, false, sentence]);
      } else {
        answers.send([id, false, 'Ghost.md\'s core gave an answer that is neither ok nor err.']);
      }
    } on Object catch (e) {
      // What Dart itself refused: arguments that are not JSON, an answer that is not, no memory.
      answers.send([id, false, 'Ghost.md\'s core could not be asked $command: $e']);
    }
  });
}
