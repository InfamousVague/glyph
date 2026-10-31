/// Which notes are meetings, written into the note (docs/MARKDOWN_FIRST.md §5, gap 6). The port's own, 2026-10-31.
///
/// A meeting's note said `source: capture` and nothing else: that it was a meeting, when it started, which booking it
/// came from and where the app filed it lived in the synced preferences alone (`prefs.meetings`, `meetingNotes`,
/// `meetingSorts`), so a Library folder opened on a fresh device showed every meeting as an ordinary note and the
/// shelf of their tapes empty. Now the note carries it, one flow map in its page front matter, as `verified:` is:
///
///     meeting: {start: 2026-10-31T10:00:00.000Z, kind: meet, booking: 7f3a, app: w-ab12cd}
///
/// `start` is the ISO instant the meeting began (what `prefs.meetings` held, in milliseconds), `kind` is the service
/// it was on (`meet`, `zoom`, `discord`, `phone` for one recorded on the phone itself), `booking` the service's
/// booking id where it came from one (`meetingNotes`), `app` the folder the app filed it in (`meetingSorts`'s
/// `app`), and `sorted` the folder the AI sorted it to or `kept`. Only `start` is always there. Written by the code
/// that makes the note, as it makes the body ([withMeetingMark]), so there is no second write and no open editor to
/// fight; read with the preferences for a release ([meetingsOf] is the union), the preferences still written as
/// before so an older build on the account keeps its shelf.
///
/// Flat, one line, no quotes: lib/core/front_matter.dart reads a key's value to the end of its line and
/// frontmatter.rs reads it as text, so a map across lines would be read by neither. The values hold no comma, no
/// colon but the stamp's, and no brace, so the line is cut at its commas and each part at its first colon.
library;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterValue;
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/properties.dart' show withFrontMatterValue;

/// The front matter key.
const String meetingKey = 'meeting';

/// What a note says of the meeting it is.
@immutable
class MeetingMark {
  const MeetingMark({required this.startMs, this.kind, this.booking, this.app, this.sorted});

  /// When it began, in milliseconds since the epoch: what `prefs.meetings` holds.
  final int startMs;

  /// `meet`, `zoom`, `discord` or `phone`; null where the writer did not know.
  final String? kind;

  /// The service's booking id, where the meeting came from one.
  final String? booking;

  /// The folder the app filed the note in as it was made, by workspace id (lib/ai/meeting_sort.dart `app`).
  final String? app;

  /// The folder the AI sorted it to, by workspace id, or `kept` where the person kept it where it was (`sorted`).
  final String? sorted;

  MeetingMark copyWith({String? kind, String? booking, String? app, String? sorted}) =>
      MeetingMark(startMs: startMs, kind: kind ?? this.kind, booking: booking ?? this.booking, app: app ?? this.app, sorted: sorted ?? this.sorted);

  /// The value as the line carries it.
  String get value {
    final parts = <String>[
      'start: ${DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toIso8601String()}',
      if (kind != null && _plain(kind!)) 'kind: $kind',
      if (booking != null && _plain(booking!)) 'booking: $booking',
      if (app != null && _plain(app!)) 'app: $app',
      if (sorted != null && _plain(sorted!)) 'sorted: $sorted',
    ];
    return '{${parts.join(', ')}}';
  }

  @override
  bool operator ==(Object other) => other is MeetingMark && other.startMs == startMs && other.kind == kind && other.booking == booking && other.app == app && other.sorted == sorted;

  @override
  int get hashCode => Object.hash(startMs, kind, booking, app, sorted);

  @override
  String toString() => 'MeetingMark($value)';
}

final RegExp _plainWord = RegExp(r'^[A-Za-z0-9_.@+-]{1,128}$');

/// A word the line can carry as it is: no comma, colon, brace, quote or space.
bool _plain(String word) => _plainWord.hasMatch(word);

/// The mark a body carries, or null for a note that is not a meeting, or whose `meeting:` is not one this reads
/// (a bare value, a start that is not an instant).
MeetingMark? meetingMarkOf(String body) {
  final raw = frontMatterValue(body, meetingKey);
  if (raw == null) return null;
  final text = raw.trim();
  if (!text.startsWith('{') || !text.endsWith('}')) return null;
  final fields = <String, String>{};
  for (final part in text.substring(1, text.length - 1).split(',')) {
    final at = part.indexOf(':');
    if (at < 0) continue;
    fields[part.substring(0, at).trim()] = part.substring(at + 1).trim();
  }
  final start = fields['start'];
  final at = start == null ? null : DateTime.tryParse(start);
  if (at == null) return null;
  String? word(String key) {
    final value = fields[key];
    return value != null && _plain(value) ? value : null;
  }
  return MeetingMark(startMs: at.millisecondsSinceEpoch, kind: word('kind'), booking: word('booking'), app: word('app'), sorted: word('sorted'));
}

/// [body] carrying [mark], in place of the one it had; null takes the key off (the note is not a meeting after all).
String withMeetingMark(String body, MeetingMark? mark) => withFrontMatterValue(body, meetingKey, mark?.value);

/// Which notes are meetings and when each began, read both ways for a release: the preferences' map, and every note
/// whose body says so that the preferences lack (a note from a restored library, or from a device whose settings
/// have not synced in yet). The preferences' time wins where both say.
Map<String, num> meetingsOf(Preferences prefs, Iterable<Note> notes) {
  Map<String, num>? merged;
  for (final note in notes) {
    if (prefs.meetings.containsKey(note.id)) continue;
    // Cheap first: a note with no front matter at all, or none naming a meeting, is most notes.
    if (!note.body.startsWith('---') || !note.body.contains('\n$meetingKey:')) continue;
    final mark = meetingMarkOf(note.body);
    if (mark == null) continue;
    (merged ??= {...prefs.meetings})[note.id] = mark.startMs;
  }
  return merged == null ? prefs.meetings : Map.unmodifiable(merged);
}

/// Which booking each meeting note came from, as the notes say it: booking id to note id, for the notes the
/// preferences' `meetingNotes` lack (lib/meet/meet_in.dart `meetingNotesOf` is the preferences' half).
Map<String, String> bookingsOf(Iterable<Note> notes) {
  final out = <String, String>{};
  for (final note in notes) {
    if (!note.body.startsWith('---') || !note.body.contains('\n$meetingKey:')) continue;
    final booking = meetingMarkOf(note.body)?.booking;
    if (booking != null) out.putIfAbsent(booking, () => note.id);
  }
  return out;
}
