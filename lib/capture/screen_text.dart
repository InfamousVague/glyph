/// The recorder's own words, the ones that are not the note: the line at the top, which says where the words are
/// going or what is holding them up, and the line under the empty page, which says how this recording ends. A port
/// of `src/app/capture/screenText.ts`.
///
/// Pure, so each state's line is a test; the capture screen draws them.
///
/// What differs: `statusLine`'s one object argument is named parameters; `whereLine`'s `target` is the note's body,
/// or null, where the web takes any object with a `body`.
library;

import '../core/note_text.dart' show noteTitle;
import '../core/text.dart' show capitalise;
import 'capture_session.dart' show Phase;

/// What the top line says while something stands between the person and the recording - it has not started, it could
/// not, the voice model is downloading, it is saving, or it failed before a word - or null when it is listening, and
/// the line says where the words are going instead ([whereLine]).
///
/// [heardWords] is whether any phrase has been committed: an error after the first words is the diagnostics line's
/// to show.
String? statusLine({
  required Phase phase,
  required String? error,
  required ({num received, num total})? download,
  required bool heardWords,
}) {
  if (phase == Phase.failed) return error ?? 'Could not start';
  if (download != null) return 'Downloading voice model ${(download.received / 1e6).round()} / ${(download.total / 1e6).round()} MB';
  if (phase == Phase.starting) return 'Starting';
  if (phase == Phase.finishing) return 'Saving';
  if (error != null && error.isNotEmpty && !heardWords) return 'Problem: $error';
  return null;
}

/// Where the words are going: a new note, one named on a card and made at Done ([named]), or the note being written
/// to - named, except over the lock screen, where a note a command switched to ([routed]) is only "the note you
/// named". A meeting (capture/meeting.dart) is recorded, not read, and its line says only that.
String whereLine(String? target, bool locked, {bool routed = false, String? named, bool meeting = false}) {
  if (meeting) return 'Meeting';
  if (target == null) return named != null && !locked ? 'New note “$named”' : 'New note';
  if (locked) return routed ? 'Adding to the note you named' : 'Adding to your last note';
  return 'Adding to “${noteTitle(target)}”';
}

/// What ends this recording, in a line under "Start talking.": the side key when this phone lets it stop one (a
/// press, or the hold that opened it), going quiet when that is switched on, and otherwise Done.
String stopHint(bool fromSideKey, bool pressStops, bool quietStops) {
  final key = pressStops
      ? 'press the side key'
      : fromSideKey
          ? 'hold the side key again'
          : null;
  if (quietStops) return key != null ? 'Stop talking to finish, or $key.' : 'Stop talking to finish, or tap Done.';
  if (key != null) return '${capitalise(key)} to stop.';
  return 'Tap Done to stop.';
}
