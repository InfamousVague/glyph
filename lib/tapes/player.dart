/// A note's tape, playing: where the playhead is, whether it is moving, and the phrases as they were spoken, for the
/// tape at the top of a note (`note_tape.dart`) and its transcript (`transcript_words.dart`). A port of
/// `src/app/tapes/useTape.ts`, with the two functions of `core/recordings.ts` it reads ([audioRemoved],
/// [markAudioRemoved]).
///
/// A tape that will not play says why, where the why is known: its audio was removed from this device by the Tapes
/// row, or the note came from another device and its audio stayed there. Otherwise only that it could not be played.
///
/// What differs: the page played the WAV through an `<audio>` element the hook was handed a ref to, and in a browser
/// a clock stood in for it. Here both are one seam, [TapePlayer], which whoever wires the app gives; nothing in this
/// file reaches a platform channel, and the real player comes with the native audio piece. So the hook's `web` and
/// `audio` (the element's ref and its five events) are gone: [Tape] listens to the player instead. The element
/// loaded its file by having a `src`; here the file is loaded at the first Play, so a tape nobody plays asks the
/// phone for nothing. The page's `rec` scheme answered a HEAD with 404 for a file not on the device; the seam says
/// it as [TapePlayer.onDevice]. A browser put an ended element back at its start on the next Play by itself; [Tape]
/// seeks the player to 0 when it ends. The hook lived and died with one note's screen; a [Tape] can be handed
/// another note ([Tape.note]), which stops the first and forgets its playhead, its problem and its phrases. The
/// player's own [TapePlayer.duration] is not read: the tape's length is the note's `recordingMs`, as on the page.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../ai/support/failure.dart';
import '../core/note.dart';
import '../core/stored.dart';

/// What a player says happened, beside what its listenables hold.
enum TapeEvent {
  /// The recording played to its end. The player has stopped ([TapePlayer.playing] is false).
  ended,

  /// The recording could not be read or played, after it had loaded (the `<audio>` element's `error`).
  failed,
}

/// The thing that plays a note's recording. One player serves the whole app: a [Tape] loads its note's recording
/// into it by the note's id, and stops it on the way out. The app's real one comes with the native audio channel;
/// until then a screen is given whatever stands in for it (the tests' is `test/tapes/fake_player.dart`).
abstract class TapePlayer {
  /// Makes [noteId]'s recording the one this player plays, stopped at its start. Throws when there is no such
  /// recording on this device, or it cannot be read.
  Future<void> load(String noteId);

  /// Plays from where the playhead is; from the start, after [TapeEvent.ended] and a seek to 0. Throws when the
  /// phone will not play (the page's `el.play()` rejecting).
  Future<void> play();

  Future<void> pause();

  /// Moves the playhead to [ms], playing or not.
  Future<void> seek(int ms);

  /// Where the playhead is, in milliseconds, told as it moves (the element's `timeupdate`).
  ValueListenable<int> get position;

  /// The loaded recording's length in milliseconds; null until one has loaded.
  ValueListenable<int?> get duration;

  /// Whether it is playing (the element's `play` and `pause`).
  ValueListenable<bool> get playing;

  /// The end of a recording, and a failure while playing.
  Stream<TapeEvent> get events;

  /// Whether [noteId]'s recording is on this device: false is the `rec` scheme's 404 (a meeting's audio, or one
  /// over the sync limit, stayed on the device that made it), null is not knowing.
  Future<bool?> onDevice(String noteId);

  /// Lets go of the recording loaded, keeping the player for another [load] (the channel's `release`): what the
  /// shelf's previews do with a cassette scrolled away (lib/tapes/previews.dart). Never a [Tape]'s to call.
  Future<void> release();

  /// Stops, and lets go of the phone's player. Whoever made the player calls this, never a [Tape].
  void dispose();
}

/// The line for a tape whose audio the Tapes row removed from this device.
const String audioRemovedLine = 'The audio was removed.';

/// The line for a tape whose audio stayed on the device that made it.
const String notOnThisDevice = 'This recording is not on this device.';

/// The line for a tape that would not play for a reason nothing here knows.
const String couldNotPlay = 'This tape couldn’t be played.';

/// The notes whose audio was removed from this device by the Tapes row (`REMOVED_KEY`, core/recordings.ts).
const String _removedKey = 'glyph-audio-removed';

List<String> _removedIds() => stored.read<List<String>>(_removedKey, const [], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : null);

/// Remember that these notes' audio is gone from this device (`markAudioRemoved`).
void markAudioRemoved(Iterable<String> ids) {
  if (ids.isEmpty) return;
  stored.write(_removedKey, {..._removedIds(), ...ids}.toList());
}

/// Whether [id]'s audio was removed from this device (`audioRemoved`).
bool audioRemoved(String id) => _removedIds().contains(id);

/// Why [note]'s tape did not play, by what this device knows and what its file answers ([head]: the status the
/// file answers with, 404 when it is not on this device) (`whyNotPlayed`).
Future<String> whyNotPlayed(({String id, int? recordingMs}) note, Future<int?> Function(String id) head) async {
  if (note.recordingMs == null || note.recordingMs == 0) return couldNotPlay;
  if (audioRemoved(note.id)) return audioRemovedLine;
  int? status;
  try {
    status = await head(note.id);
  } catch (_) {
    // Not answered at all: the same as not knowing.
    status = null;
  }
  return status == 404 ? notOnThisDevice : couldNotPlay;
}

/// A note's tape (`Tape`, and the hook that made it): a listenable a screen draws from.
class Tape extends ChangeNotifier {
  /// [note]'s tape over [player]. [getNote] reads a note again by its id, for the phrases a list left out of the
  /// notes it loaded (`getNote`, core/store.ts); without it a note that came without phrases has none. [loaded]
  /// says [player] holds this note's recording already, stopped at its start, so the first Play only plays: the
  /// shelf's cassettes, loaded ahead under the mouse (lib/tapes/previews.dart).
  Tape(Note note, {required this.player, this.getNote, this.haptic = fireMotor, bool loaded = false}) : _note = note, _segments = note.segments, _loaded = loaded {
    player.position.addListener(_moved);
    player.playing.addListener(_turned);
    _events = player.events.listen(_heard);
    _fetch();
  }

  final TapePlayer player;
  final Future<Note?> Function(String id)? getNote;

  /// The touch of Play (`fireNativeHaptic('selection')`).
  final HapticFn haptic;

  Note _note;
  List<Segment>? _segments;
  int _at = 0;
  bool _playing = false;
  String? _problem;
  bool _loaded;
  bool _loading = false;
  bool _gone = false;
  StreamSubscription<TapeEvent>? _events;

  Note get note => _note;

  /// The note whose tape this is. The same note again with another length (its recording removed, or put back by
  /// Undo) keeps the playhead and the phrases; another note stops the tape and starts over.
  set note(Note next) {
    final other = next.id != _note.id;
    _note = next;
    if (other) {
      if (_loaded && player.playing.value) unawaited(player.pause().catchError((Object _) {}));
      _loaded = false;
      _loading = false;
      _at = 0;
      _playing = false;
      _problem = null;
      _segments = next.segments;
    }
    _fetch();
    notifyListeners();
  }

  /// Milliseconds recorded, 0 when the note was not spoken.
  int get length => _note.recordingMs ?? 0;
  int get at => _at;
  bool get playing => _playing;

  /// The phrases as spoken, null until they have been fetched.
  List<Segment>? get segments => _segments;

  /// The phrase under the playhead, or -1.
  int get current => _segments?.indexWhere((s) => _at >= s.startMs && _at < s.endMs) ?? -1;
  String? get problem => _problem;

  /// The list leaves the phrases out of the notes it loads, so fetch them by id.
  void _fetch() {
    if (_segments != null || length == 0) return;
    final read = getNote;
    if (read == null) {
      _segments = const [];
      return;
    }
    final id = _note.id;
    unawaited(read(id).then<Note?>((full) => full, onError: (Object _) => null).then((full) {
      if (_stale(id) || _segments != null) return;
      _segments = full?.segments ?? const [];
      notifyListeners();
    }));
  }

  bool _stale(String id) => _gone || _note.id != id;

  void _moved() {
    if (!_loaded || _gone) return;
    final now = player.position.value;
    if (now == _at) return;
    _at = now;
    notifyListeners();
  }

  void _turned() {
    if (!_loaded || _gone) return;
    final now = player.playing.value;
    if (now == _playing) return;
    _playing = now;
    notifyListeners();
  }

  void _heard(TapeEvent event) {
    if (!_loaded || _gone) return;
    switch (event) {
      case TapeEvent.ended:
        _playing = false;
        _at = 0;
        notifyListeners();
        unawaited(player.seek(0).catchError((Object _) {}));
      case TapeEvent.failed:
        _failed();
    }
  }

  /// It would not play: say so at once, then why, once the device has been asked (the element's `onError`).
  void _failed() {
    final id = _note.id;
    _problem = couldNotPlay;
    notifyListeners();
    unawaited(whyNotPlayed((id: id, recordingMs: _note.recordingMs), (id) async {
      final here = await player.onDevice(id);
      return here == null ? null : (here ? 200 : 404);
    }).then((why) {
      if (_stale(id)) return;
      _problem = why;
      notifyListeners();
    }));
  }

  /// Play, or pause.
  Future<void> toggle() async {
    haptic(HapticKind.selection);
    if (_problem != null) {
      _problem = null;
      notifyListeners();
    }
    if (_loading) return;
    final id = _note.id;
    if (_loaded && player.playing.value) {
      await player.pause();
      return;
    }
    if (!_loaded) {
      _loading = true;
      try {
        await player.load(id);
      } catch (_) {
        if (_stale(id)) return;
        _loading = false;
        _failed();
        return;
      }
      if (_stale(id)) return;
      _loading = false;
      _loaded = true;
      // A phrase tapped before the first Play: the recording starts from it.
      if (_at > 0) await player.seek(_at);
    }
    try {
      await player.play();
    } catch (failure) {
      if (_stale(id)) return;
      _problem = failureText(failure);
      notifyListeners();
    }
  }

  /// Takes the tape to [ms].
  void seek(int ms) {
    _at = ms;
    notifyListeners();
    if (_loaded) unawaited(player.seek(ms).catchError((Object _) {}));
  }

  /// Leaving the note stops the tape. The player is not this tape's to dispose.
  @override
  void dispose() {
    _gone = true;
    player.position.removeListener(_moved);
    player.playing.removeListener(_turned);
    unawaited(_events?.cancel());
    if (_loaded && player.playing.value) unawaited(player.pause().catchError((Object _) {}));
    super.dispose();
  }
}
