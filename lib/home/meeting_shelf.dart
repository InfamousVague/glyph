/// The meetings' tapes on the home page (GHST-112; Matt, 2026-10-23: "Add a shelf for meeting recordings and show
/// the note title on the cassette"): under "Meetings" and how many, a row of cassettes that scrolls sideways, the
/// newest meeting first, each with its note's title on its label in two lines and, under it, how long it is and the
/// day it was. A tap opens the note. The meeting being recorded now is first, its reels turning and "Recording now"
/// under it. Nothing at all when there are no meetings with a tape.
///
/// A meeting is a note `prefs.meetings` has (lib/core/preferences.dart), the ones Ghost's Meet bot files among them;
/// it is shelved when it has a recording here or is known to have one elsewhere (`recordingMs`, lib/core/note_text.dart
/// `hasTape`), or is the one being recorded. The home page draws it under the notices, the upcoming meetings among
/// them, and not while searching, nor in simple mode (lib/home/home_screen.dart).
///
/// After the web's shelf of tapes (`src/app/home/TapeShelf.tsx`, gone with the dashboard, docs/DESIGN.md §147): a row
/// that scrolls, the cassettes drawn against the longest tape on the shelf, so a short meeting is a thin ring beside
/// an hour's full reel. What differs: the title is on the cassette's label (lib/tapes/tape_art.dart `titleLines`)
/// rather than under it, there is no caption or Summarize, and the row stays a row on a wide page.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart' show hasTape;
import '../tapes/shelf.dart';
import '../tapes/tape.dart';
import '../tapes/tape_art.dart';
import 'home_organizations.dart' show HomeHeading;
import 'home_text.dart';

/// The most cassettes the shelf holds; See all opens the rest.
const int meetingShelfMost = 12;

/// A cassette's width on the shelf, in logical pixels: its title reads at about eleven.
const double meetingTapeWidth = 188;

/// When a meeting was: when it was started, as the meetings say, or when its note was made.
int meetingStart(Note note, Map<String, num> meetings) => meetings[note.id]?.toInt() ?? note.createdAt;

/// The meetings to shelve, the newest first: notes the meetings name, not archived, with a tape here or known to have
/// one, and the one being recorded now ([live]) first whatever its tape.
List<Note> shelvedMeetings(Iterable<Note> notes, Map<String, num> meetings, {String? live}) {
  if (meetings.isEmpty) return const [];
  final kept = [
    for (final note in notes)
      if (note.archivedAt == null && meetings.containsKey(note.id) && (hasTape(note) || note.id == live)) note,
  ];
  final indexed = kept.indexed.toList()
    ..sort((a, b) {
      final first = (b.$2.id == live ? 1 : 0) - (a.$2.id == live ? 1 : 0);
      if (first != 0) return first;
      final by = meetingStart(b.$2, meetings).compareTo(meetingStart(a.$2, meetings));
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
  return [for (final (_, note) in indexed) note];
}

/// What a screen reader says of a cassette: "Meeting, Standup, 23 Oct, 12:40".
String meetingSaid(Note note, Map<String, num> meetings, {bool live = false}) =>
    'Meeting, ${_title(note)}, ${tapeDate(meetingStart(note, meetings))}, ${live ? 'recording now' : counter(note.recordingMs ?? 0)}';

String _title(Note note) {
  final facts = NoteFacts.of(note);
  return facts.title.trim().isEmpty ? 'Untitled' : facts.shownTitle;
}

class MeetingShelf extends StatelessWidget {
  const MeetingShelf({super.key, required this.notes, required this.meetings, required this.onOpen, this.live, this.onSeeAll});

  /// The notes to look through: the page's, the workspace chosen's.
  final List<Note> notes;

  /// Which notes are meetings, and when each was started (`prefs.meetings`).
  final Map<String, num> meetings;

  /// The note of the meeting being recorded now.
  final String? live;

  final ValueChanged<String> onOpen;

  /// All notes with its Tapes word on: shown when the shelf holds fewer than there are.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final all = shelvedMeetings(notes, meetings, live: live);
    if (all.isEmpty) return const SizedBox.shrink();
    final shown = all.take(meetingShelfMost).toList(growable: false);
    final t = context.tokens;
    final ink3 = t.color('app-ink-3');
    // The longest tape on the shelf, at least five minutes: what every cassette here is drawn against.
    final lengthMs = shown.fold<int>(tapeMs, (most, note) => math.max(most, note.recordingMs ?? 0));
    final gap = t.space(4);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: const ValueKey('meeting-shelf'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: HomeHeading(mark: TapeMark(em: t.fontSize('sm'), color: ink3), words: 'Meetings', count: all.length)),
              if (onSeeAll != null && all.length > shown.length) AppWord(key: const ValueKey('meeting-shelf-all'), onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          SizedBox(height: t.space(2)),
          SingleChildScrollView(
            key: const ValueKey('meeting-shelf-row'),
            scrollDirection: Axis.horizontal,
            // Room for the focus ring, which the row would clip at its edges.
            padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(1)),
            clipBehavior: Clip.hardEdge,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, note) in shown.indexed) ...[
                  if (i > 0) SizedBox(width: gap),
                  _MeetingTape(key: ValueKey('meeting-tape-${note.id}'), note: note, meetings: meetings, lengthMs: lengthMs, live: note.id == live, onOpen: onOpen),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One cassette: the note's title on its label, its length and its day under it; a tap opens it.
class _MeetingTape extends StatelessWidget {
  const _MeetingTape({super.key, required this.note, required this.meetings, required this.lengthMs, required this.live, required this.onOpen});

  final Note note;
  final Map<String, num> meetings;
  final int lengthMs;
  final bool live;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final radius = t.radius('md');
    return GlacierPressable(
      onPressed: () => onOpen(note.id),
      semanticLabel: meetingSaid(note, meetings, live: live),
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: radius,
        child: SizedBox(
          width: meetingTapeWidth,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // `.cassette:active`: it gives a little when pressed, as the web's did.
                AnimatedScale(
                  scale: state.pressed ? 0.97 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: TapeArt(positionMs: note.recordingMs ?? 0, lengthMs: lengthMs, playing: live, title: _title(note), titleLines: 2, hue: tapeHue(note.id)),
                ),
                SizedBox(height: t.space(2)),
                Text.rich(
                  TextSpan(
                    children: [
                      ...tapeWordSpans(t, note, live: live, em: xs, dot: !live),
                      TextSpan(text: tapeDate(meetingStart(note, meetings)), style: tabular(pageText(t, xs, color: t.color('glacier-text-subtle')))),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
