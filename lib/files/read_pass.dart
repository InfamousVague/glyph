/// The reading of words in pictures, scans and PDFs, on this phone (lib/files/phone_documents.dart `read`), kept as
/// each one's sidecar (lib/files/read_text.dart).
///
/// Two kinds of asking, one reader:
///
/// - **Something just added** (a picture picked or pasted, a file attached, a document scanned) is read at once,
///   ahead of everything else: [ReadPass.readSoon].
/// - **What the notes already show** is read slowly, one thing at a time, behind the person: [ReadPass.readExisting].
///   It begins on its own a while after the app opens, and from Settings › Files and scans at once. Between one
///   thing and the next it waits while the app is busy (a touch, a key or a scroll in the last [quietFor]) and
///   while Battery saver is on, when it says so and stops until it is off.
///
/// The reading itself is the phone's, on a thread of its own at background priority: nothing runs on the UI's
/// isolate but the bookkeeping. Settings' Read words in pictures (on unless switched off, kept on this device) stops
/// both kinds, and what was read stays.
///
/// A thing read after its note went to the account's other devices owes them the note again
/// ([ReadPass.onRead]), so they hear of the words and fetch them (lib/sync/notes.dart).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../core/attachment_refs.dart';
import '../core/stored.dart';
import 'phone_documents.dart';
import 'read_text.dart';

/// The key Read words in pictures is kept under on this device: `off`, or nothing for on.
const String readKey = 'glyph-read-words';

/// How long the app is left alone before the slow reading takes its next thing.
const Duration quietFor = Duration(seconds: 3);

/// How many of a PDF's pages are read: past this a long document is found by its first pages.
const int readPagesMost = 60;

/// How far the slow reading has got.
@immutable
class ReadProgress {
  const ReadProgress({required this.done, required this.total, this.waiting});

  final int done;
  final int total;

  /// Why it is waiting, where it is: Battery saver.
  final String? waiting;

  bool get finished => done >= total;

  @override
  bool operator ==(Object other) => other is ReadProgress && other.done == done && other.total == total && other.waiting == waiting;

  @override
  int get hashCode => Object.hash(done, total, waiting);
}

/// The reader.
class ReadPass extends ChangeNotifier {
  ReadPass({
    required this.texts,
    required this.device,
    required this.pathOf,
    required this.bodies,
    this.onRead,
    Stored? kept,
    Duration? quiet,
    bool listenForInput = true,
  })  : _kept = kept,
        _quiet = quiet ?? quietFor {
    if (listenForInput) _listen();
  }

  final ReadTexts texts;
  final DocumentDevice device;

  /// Where the thing lies on this device, or null where it is not here (a picture still on its way).
  final Future<String?> Function(ReadThing thing) pathOf;

  /// Every note's id and words, for the slow reading to find what the notes show, and for [onRead] to find who
  /// shows a thing just read.
  final Future<List<({String id, String body})>> Function() bodies;

  /// Told the notes that show a thing whose words were just read, once they are kept.
  final void Function(Iterable<String> noteIds)? onRead;

  final Stored? _kept;
  final Duration _quiet;
  Stored get _store => _kept ?? stored;

  /// Whether this device reads words at all.
  bool get possible => device.reads;

  /// Read words in pictures: on unless switched off here.
  bool get on => possible && _store.readText(readKey) != 'off';

  set on(bool value) {
    _store.writeText(readKey, value ? null : 'off');
    notifyListeners();
    if (value) {
      _wake();
    } else {
      _soon.clear();
      _slow.clear();
      if (_progress != null && !_progress!.finished) _progress = ReadProgress(done: _progress!.done, total: _progress!.done);
    }
  }

  final List<ReadThing> _soon = <ReadThing>[];
  final List<ReadThing> _slow = <ReadThing>[];
  final Set<String> _failed = <String>{};

  /// Which notes show each thing the slow reading found, so a thing read need not have its notes looked for.
  final Map<String, List<String>> _shownBy = <String, List<String>>{};
  bool _running = false;
  ReadProgress? _progress;

  /// How far the slow reading has got, while it runs and after; null before it first began.
  ReadProgress? get progress => _progress;

  /// Whether anything is being read or waits to be.
  bool get busy => _running;

  // ---- what the person is doing --------------------------------------------------------------------------------

  DateTime _lastInput = DateTime.fromMillisecondsSinceEpoch(0);

  void _listen() {
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_heard);
      HardwareKeyboard.instance.addHandler(_key);
    } catch (_) {
      // No binding (a plain Dart run): nothing is heard, and the reader never waits for quiet.
    }
  }

  void _heard(PointerEvent event) => _lastInput = DateTime.now();

  bool _key(KeyEvent event) {
    _lastInput = DateTime.now();
    return false;
  }

  /// The app is busy: something was touched or typed a moment ago.
  bool get _busyNow => DateTime.now().difference(_lastInput) < _quiet;

  // ---- asking -------------------------------------------------------------------------------------------------

  /// Reads [thing] ahead of everything else, where it has not been read: a thing just added.
  void readSoon(ReadThing thing) {
    if (!on || !thing.readable || texts.has(thing)) return;
    _soon
      ..remove(thing)
      ..add(thing);
    _slow.remove(thing);
    _wake();
  }

  /// Reads, slowly, every picture and readable file the notes show that this device has and has not read.
  /// Answers once they are all asked for (not read).
  Future<void> readExisting() async {
    if (!on) return;
    await texts.load();
    final seen = <String>{};
    final waiting = <ReadThing>[];
    _shownBy.clear();
    for (final note in await bodies()) {
      for (final thing in thingsIn(note.body)) {
        if (!thing.readable || texts.has(thing) || _failed.contains(thing.key)) continue;
        (_shownBy[thing.key] ??= <String>[]).add(note.id);
        if (seen.add(thing.key)) waiting.add(thing);
      }
    }
    final here = <ReadThing>[];
    for (final thing in waiting) {
      final path = await pathOf(thing);
      if (path != null) here.add(thing);
    }
    _slow
      ..clear()
      ..addAll(here.where((thing) => !_soon.contains(thing)));
    _progress = ReadProgress(done: 0, total: _slow.length);
    notifyListeners();
    _wake();
  }

  void _wake() {
    if (_running || !on) return;
    if (_soon.isEmpty && _slow.isEmpty) return;
    _running = true;
    notifyListeners();
    unawaited(_run().whenComplete(() {
      _running = false;
      notifyListeners();
    }));
  }

  Future<void> _run() async {
    while (on && (_soon.isNotEmpty || _slow.isNotEmpty)) {
      final soon = _soon.isNotEmpty;
      if (!soon) {
        // Behind the person: wait for the app to be quiet, and for Battery saver to be off.
        if (_busyNow) {
          await Future<void>.delayed(_quiet);
          continue;
        }
        if (await device.saving()) {
          _say(waiting: 'Waiting while Battery saver is on.');
          await Future<void>.delayed(const Duration(seconds: 30));
          continue;
        }
        _say();
      }
      final thing = soon ? _soon.removeAt(0) : _slow.removeAt(0);
      if (texts.has(thing)) {
        if (!soon) _count();
        continue;
      }
      await _read(thing);
      if (!soon) _count();
    }
  }

  void _say({String? waiting}) {
    final was = _progress;
    if (was == null || was.waiting == waiting) return;
    _progress = ReadProgress(done: was.done, total: was.total, waiting: waiting);
    notifyListeners();
  }

  void _count() {
    final was = _progress;
    if (was == null) return;
    _progress = ReadProgress(done: was.done + 1 > was.total ? was.total : was.done + 1, total: was.total);
    notifyListeners();
  }

  Future<void> _read(ReadThing thing) async {
    final path = await pathOf(thing);
    if (path == null || !await File(path).exists()) return;
    final pdf = !thing.picture && attachmentKindOf(thing.name) == AttachmentKind.pdf;
    List<String>? pages;
    try {
      pages = await device.read(path, pdf: pdf, most: readPagesMost);
    } on PlatformException catch (failure) {
      if (failure.code == 'notready') {
        // The reader is still on its way (Play services fetches it once): this one waits at the back, a while.
        _say(waiting: 'Waiting for the reader to arrive.');
        _slow.add(thing);
        _progress = _progress == null ? null : ReadProgress(done: _progress!.done, total: _progress!.total + 1, waiting: _progress!.waiting);
        await Future<void>.delayed(const Duration(seconds: 20));
        return;
      }
      _failed.add(thing.key);
      debugPrint('[files] the words in ${thing.key} were not read: ${failure.message}');
      return;
    } catch (failure) {
      // One that will not be read is not asked again this run.
      _failed.add(thing.key);
      debugPrint('[files] the words in ${thing.key} were not read: $failure');
      return;
    }
    if (pages == null) return;
    await texts.keep(thing, textOfPages(pages));
    final told = onRead;
    if (told == null) return;
    try {
      final shown = _shownBy.remove(thing.key) ??
          <String>[
            for (final note in await bodies())
              if (thingsIn(note.body).contains(thing)) note.id,
          ];
      if (shown.isNotEmpty) told(shown);
    } catch (_) {
      // The notes would not be listed: the next time the note is sent, its words go with it.
    }
  }

  @override
  void dispose() {
    try {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_heard);
      HardwareKeyboard.instance.removeHandler(_key);
    } catch (_) {}
    super.dispose();
  }
}

/// What a device that reads no words says, for Settings.
const String readsNoWords = 'This device does not read words in pictures yet.';

/// Whether [device] can read here, as Settings asks before it draws the switch.
bool readsWords(DocumentDevice device) => device.reads;
