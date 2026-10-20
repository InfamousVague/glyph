/// A voice note from the watch, made a note on the phone (docs/WATCH.md, "On the phone"): each take waiting in the
/// phone's inbox (watch_link.dart) becomes a voice note as one recorded here does, its words the phone's own Whisper's.
///
/// For each take, oldest first, and one at a time:
///
/// 1. The note's id is made from the take's ([watchNoteId]). A note already there was made before (a pass cut short
///    after the note was written), and the take only goes from the inbox.
/// 2. The take's WAV becomes the note's recording, moved into place by the core as a meeting Ghost was in is
///    (lib/meet/tape.dart): 16 kHz mono 16-bit, the file the core's Whisper reads.
/// 3. A take of up to [meetingFromMs] is a voice note: its words are heard from the recording ([WatchListen]: the
///    larger model's timed phrases where it is on the phone, else the live model's words), written as a voice note's
///    are, cues and all (lib/capture/markdown.dart `renderNote`: "new paragraph", "bullet point", "check box"…), with
///    the phrases on its tape, and dated when the watch recorded it. Over three minutes ([longNoteMs]) it is a long
///    voice note, whose summary is asked for when Settings › Recording › Summaries says "Meetings and long voice
///    notes", as the recorder asks for one.
/// 4. A longer take is a meeting: the note is made with its title and its tape, marked a meeting, and its write-up
///    asked for as a meeting's is ([WatchNotes.writeUp]: the phone's service, Whisper span by span with the app
///    closed, then the summary by the Summaries setting, Write up straight away honoured).
/// 5. Only then does the take go from the inbox.
///
/// Where the words cannot be heard yet (the recorder is up, the engine is busy with another pass, no voice model on
/// the phone and Local only on), the take waits, its recording already the note's to be, and is tried again a minute
/// later while the app runs, when the app comes back to the front, and when another take arrives. Local only never
/// holds the words themselves: they are the phone's. Nothing is read aloud, nothing leaves the phone, and no command
/// said on the watch is carried out: a take is dictation.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../capture/markdown.dart' show RenderOptions, renderNote;
import '../capture/meeting.dart' show meetingTitle;
import '../core/note.dart';
import '../core/preferences.dart' show Preferences, longNoteMs;
import '../mail/mail_note.dart' show mailNoteId;
import 'watch_link.dart';

/// Over this a take is written up as a meeting, not heard as a voice note: the write-up goes span by span and survives
/// the app being closed, where a voice note's words are heard in one pass while the app runs.
const int meetingFromMs = 10 * 60 * 1000;

/// The id of the note take [takeId] becomes: a UUID made from the take's, never one a mail or a meeting would make.
String watchNoteId(String takeId) => mailNoteId('watch:$takeId');

/// "Watch recording, 20 Oct 14:05": a meeting's title, saying where it was recorded.
String watchRecordingTitle(int at) => meetingTitle(at).replaceFirst('Meeting', 'Watch recording');

/// A voice note's body from what was heard (see the header): the words as a note recorded here writes them, or, where
/// nothing was heard, the time it was recorded and that.
String watchNoteBody(List<Segment> heard, int recordedAt) {
  final words = renderNote(heard, '', const RenderOptions(titled: true)).markdown.trim();
  if (words.isNotEmpty) return '$words\n';
  return '# ${watchRecordingTitle(recordedAt)}\n\nNothing was heard in this recording.\n';
}

/// What came of listening to a take's recording.
sealed class Heard {
  const Heard();
}

/// The phrases, timed on the recording (none where it was silent).
class HeardWords extends Heard {
  const HeardWords(this.segments);
  final List<Segment> segments;
}

/// Not now ([why]): the take waits and is tried again.
class HeardLater extends Heard {
  const HeardLater(this.why);
  final String why;
}

/// Listens to note [noteId]'s recording, [recordingMs] long.
typedef WatchListen = Future<Heard> Function(String noteId, int recordingMs);

/// The library, as the takes are made notes in it.
abstract interface class WatchNoteStore {
  Future<Note?> getNote(String id);

  /// Whether note [id]'s recording is on this phone already.
  Future<bool> hasRecording(String id);

  /// The WAV at [path] moved into place as note [id]'s recording.
  Future<void> keepRecording(String id, String path);

  /// A new note dated [createdAt], with its recording's length and phrases.
  Future<Note> makeNote({required String id, required String body, required int createdAt, required int recordingMs, required List<Segment> segments});
}

/// Makes each take waiting in the inbox a note (see the header).
class WatchNotes {
  WatchNotes({
    required this.host,
    required this.store,
    required this.listen,
    required this.preferences,
    this.held,
    this.enqueueSummary,
    this.writeUp,
    this.markMeeting,
    this.made,
    this.retry = const Duration(minutes: 1),
  });

  final WatchHost host;
  final WatchNoteStore store;
  final WatchListen listen;
  final Preferences Function() preferences;

  /// Whether a recorder holds the phone's cores now (lib/capture/refine.dart `refineHeld`): nothing is heard then.
  final bool Function()? held;

  /// A long voice note's summary, asked for (`Summaries.enqueueSummary(id, recording)`).
  final void Function(String noteId)? enqueueSummary;

  /// A meeting's write-up, asked for as a meeting Ghost was in asks for it (lib/meet/tape.dart `writeUp`); null where
  /// this device writes nothing up, and a long take is then heard as a voice note.
  final void Function(String noteId)? writeUp;

  /// Note [noteId] is a meeting, started at [at] (`prefs.meetings`).
  final void Function(String noteId, int at)? markMeeting;

  /// Told of each note made, with the watch it came from.
  final void Function(Note note, WatchTake take)? made;
  final Duration retry;

  StreamSubscription<String>? _arrivals;
  Timer? _again;
  Future<int>? _running;
  bool _askedAgain = false;

  /// Failures this run, by take: a take that fails three times waits for the next run.
  final Map<String, int> _failed = {};

  /// Listens for takes as they arrive, and makes those already waiting [after] a moment, so the app's first frames
  /// are not shared with Whisper.
  void start({Duration after = Duration.zero}) {
    _arrivals ??= host.arrivals.listen((_) => unawaited(kick()), onError: (Object _) {});
    if (after == Duration.zero) {
      unawaited(kick());
    } else {
      _again?.cancel();
      _again = Timer(after, () => unawaited(kick()));
    }
  }

  /// Looks at the inbox now (again once the pass in hand is done, when one is).
  Future<int> kick() {
    final running = _running;
    if (running != null) {
      _askedAgain = true;
      return running;
    }
    _again?.cancel();
    _again = null;
    final pass = _pass().whenComplete(() {
      _running = null;
      if (_askedAgain) {
        _askedAgain = false;
        unawaited(kick());
      }
    });
    _running = pass;
    return pass;
  }

  void _later() {
    _again?.cancel();
    _again = Timer(retry, () => unawaited(kick()));
  }

  /// One look at the inbox: answers how many notes it made.
  Future<int> _pass() async {
    List<WatchTake> waiting;
    try {
      waiting = await host.waiting();
    } catch (failure) {
      debugPrint('[watch] the inbox could not be read: $failure');
      return 0;
    }
    var count = 0;
    for (final take in waiting) {
      if ((_failed[take.id] ?? 0) >= 3) continue;
      if (held?.call() ?? false) {
        _later();
        break;
      }
      try {
        final outcome = await _make(take);
        if (outcome == _Outcome.later) {
          _later();
          break;
        }
        if (outcome == _Outcome.made) count += 1;
      } catch (failure) {
        _failed[take.id] = (_failed[take.id] ?? 0) + 1;
        debugPrint('[watch] a voice note from the watch was not made: $failure');
        _later();
      }
    }
    return count;
  }

  Future<_Outcome> _make(WatchTake take) async {
    final id = watchNoteId(take.id);
    if (await store.getNote(id) != null) {
      await host.done(take.id);
      return _Outcome.gone;
    }
    if (!await store.hasRecording(id)) {
      if (!File(take.wav).existsSync()) {
        // Neither in the inbox nor kept: there is nothing to make a note of.
        await host.done(take.id);
        return _Outcome.gone;
      }
      await store.keepRecording(id, take.wav);
    }
    final ms = take.durationMs;
    final writeUp = this.writeUp;
    final Note note;
    if (ms > meetingFromMs && writeUp != null) {
      note = await store.makeNote(id: id, body: '# ${watchRecordingTitle(take.recordedAt)}\n', createdAt: take.recordedAt, recordingMs: ms, segments: const []);
      markMeeting?.call(id, take.recordedAt);
      writeUp(id);
    } else {
      final heard = await listen(id, ms);
      switch (heard) {
        case HeardLater(:final why):
          debugPrint('[watch] a voice note from the watch waits: $why');
          return _Outcome.later;
        case HeardWords(:final segments):
          note = await store.makeNote(id: id, body: watchNoteBody(segments, take.recordedAt), createdAt: take.recordedAt, recordingMs: ms, segments: segments);
          if (ms > longNoteMs && segments.isNotEmpty && preferences().summaries == 'long') enqueueSummary?.call(id);
      }
    }
    await host.done(take.id);
    made?.call(note, take);
    return _Outcome.made;
  }

  void dispose() {
    _again?.cancel();
    _again = null;
    unawaited(_arrivals?.cancel());
    _arrivals = null;
  }
}

enum _Outcome { made, gone, later }
