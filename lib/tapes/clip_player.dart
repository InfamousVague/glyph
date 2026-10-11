/// What plays a voice memo in a note: the [ClipPlayer] lib/editor/media/clips.dart leaves as a seam, over a
/// player of a recording that is the memos' own ([TapePlayer]; lib/tapes/phone_player.dart
/// `PhoneTapePlayer.clips` on a phone). What the page's `<audio>` per clip was in `src/app/editor/clips.ts`: the
/// note's recording, played between the clip's two times.
///
/// A memo's `src` is the id of the note whose recording it is a stretch of, which is what a [TapePlayer] loads by.
/// The recording is loaded at the press, the playhead put at the clip's start, and playing stops when the playhead
/// reaches its end, when the recording ends or fails, or when anything else pauses the player.
///
/// What differs:
/// - The page made an element for each clip, beside the tape's own, and let one clip play at a time. Here the
///   memos share one player among themselves, which comes to the same, and the tape at the note's top has
///   another: a memo played takes nothing from the tape's playhead, the tape's Play afterwards goes on from where
///   the tape was, and a memo pressed while the tape plays sounds over it, as the page's two elements did.
/// - A stretch's end is caught by the playhead as the phone tells it (every few tens of milliseconds), where the
///   page watched `timeupdate`: a memo may run that much over its end, as it did there.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../editor/media/clip_refs.dart' show Clip;
import '../editor/media/clips.dart' show ClipPlayer;
import 'player.dart';

class TapeClipPlayer extends ChangeNotifier implements ClipPlayer {
  TapeClipPlayer(this._player) {
    _player.position.addListener(_moved);
    _player.playing.addListener(_paused);
    _heard = _player.events.listen((_) => _over());
  }

  final TapePlayer _player;
  StreamSubscription<TapeEvent>? _heard;
  ({String src, Clip clip})? _playing;

  /// Whether the phone has begun the stretch: its player says "not playing" while it loads, which is not a pause.
  bool _begun = false;
  int _asks = 0;

  @override
  ({String src, Clip clip})? get playing => _playing;

  @override
  Future<void> play(String src, Clip clip) async {
    final ask = _asks += 1;
    _begun = false;
    _playing = (src: src, clip: clip);
    notifyListeners();
    try {
      await _player.load(src);
      if (ask != _asks) return;
      await _player.seek(clip.startMs);
      if (ask != _asks) return;
      await _player.play();
      if (ask == _asks) _begun = true;
    } catch (_) {
      if (ask == _asks) _over();
      rethrow;
    }
  }

  @override
  void stop() {
    if (_playing == null) return;
    _asks += 1;
    _over();
    unawaited(_player.pause().then<void>((_) {}, onError: (Object _) {}));
  }

  /// Nothing is sounding any more.
  void _over() {
    if (_playing == null) return;
    _playing = null;
    _begun = false;
    notifyListeners();
  }

  void _moved() {
    final now = _playing;
    if (now == null || !_begun) return;
    if (_player.position.value >= now.clip.endMs) stop();
  }

  /// The player was paused by something else (another note's memo loading into it).
  void _paused() {
    if (_playing != null && _begun && !_player.playing.value) _over();
  }

  @override
  void dispose() {
    _player.position.removeListener(_moved);
    _player.playing.removeListener(_paused);
    unawaited(_heard?.cancel());
    super.dispose();
  }
}
