/// A meeting's note in two views, Note and Transcript (Matt, 2026-10-30: "Also use a button to switch to the
/// transcript in the note don't show the transcript on the note section"), as the shared page has Summary and
/// Transcript (tauri/src/read/MeetingRead.tsx): the kit's segmented toggle, small, at the top of the note under its
/// tape. Note is the note's words with the transcript folded out of them (lib/editor/view/transcript_fold.dart), and
/// Transcript the meeting's turns, each its speaker and time over its words, the one being heard lit, a press playing
/// the recording from there (lib/tapes/transcript_words.dart `TranscriptWords.turns`). The note is one file all the
/// same: only what is shown changes.
///
/// - **Which notes**: a meeting's ([Preferences.meetings], or one whose words carry the line Ghost files a meeting
///   with, lib/meet/meet_note.dart `ghostLine`, for a team member who did not file it), with a transcript or captions
///   to show, or a recording ([hasMeetingView]). Every other note is as it was.
/// - **Which view**: the one last chosen for the note on this device ([meetingViewKey]), else Note; a cassette pressed
///   on the shelf opens it at Transcript, playing.
/// - **Rebuild transcript** is the tape's (lib/tapes/note_tape.dart), and its pure half is lib/meet/meet_note.dart
///   `rebuiltTranscript`; [transcriptRange] is the stretch of the note it writes, so it is one edit of those lines.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/stored.dart';
import '../meet/meet_note.dart' show ghostLineStart;
import '../tapes/transcript_words.dart' show paragraphStartMs;

/// This device's memory of each meeting's last view, `{note id: "note" | "transcript"}`.
const String meetingViewKey = 'glyph-meeting-view';

/// How many notes' views are remembered: the newest.
const int _remembered = 200;

Map<String, String> _views() => stored.read<Map<String, String>>(meetingViewKey, const {}, (raw) => raw is Map ? {for (final e in raw.entries) if (e.key is String && e.value is String) e.key as String: e.value as String} : null);

/// The view last chosen for note [id] here: true for Transcript, false for Note, null for none.
bool? rememberedTranscript(String id) => switch (_views()[id]) {
      'transcript' => true,
      'note' => false,
      _ => null,
    };

/// Remembers [transcript] (or Note) as note [id]'s view, the newest of [_remembered].
void rememberView(String id, bool transcript) {
  final views = {..._views()}..remove(id);
  views[id] = transcript ? 'transcript' : 'note';
  final keys = views.keys.toList();
  stored.write(meetingViewKey, {for (final key in keys.skip(math.max(0, keys.length - _remembered))) key: views[key]});
}

final RegExp _sectioned = RegExp(r'^## (Transcript|Captions)[ \t]*$', multiLine: true);

/// Whether Ghost filed the note as a meeting: its line in the first words.
bool ghostFiled(String head) => head.contains(ghostLineStart);

/// Whether the note shows Note and Transcript (see the header): a meeting's ([meeting], or filed by Ghost) with a
/// transcript or captions in its words below their first line, or a recording ([taped]).
bool hasMeetingView(String body, {required bool meeting, required bool taped}) {
  if (!meeting && !ghostFiled(body.length > 800 ? body.substring(0, 800) : body)) return false;
  if (taped) return true;
  final at = _sectioned.firstMatch(body)?.start;
  return at != null && at > 0;
}

/// The stretch of [doc] its transcript takes: from its `## Transcript` line to the end of its last line before the
/// next level-2 heading, or the end; null where it has none.
({int from, int to})? transcriptRange(String doc) {
  final at = RegExp(r'^## Transcript[ \t]*$', multiLine: true).firstMatch(doc);
  if (at == null) return null;
  final next = RegExp(r'^## ', multiLine: true).allMatches(doc, at.end).firstOrNull?.start;
  final end = next ?? doc.length;
  var to = end;
  while (to > at.start && (doc[to - 1] == '\n' || doc[to - 1] == ' ')) {
    to -= 1;
  }
  return (from: at.start, to: to);
}

/// When the turn holding offset [pos] of [doc] began, in ms: its paragraph's time, or the last timed one's before it
/// in its section; null where none before it says one.
int? transcriptMsAt(String doc, int pos) {
  var heading = -1;
  for (final m in _sectioned.allMatches(doc)) {
    if (m.start > pos) break;
    heading = m.start;
  }
  if (heading < 0) return null;
  final next = doc.indexOf(RegExp(r'\n\s*\n'), pos.clamp(heading, doc.length));
  final upTo = doc.substring(heading, next < 0 ? doc.length : next);
  for (final p in upTo.split(RegExp(r'\n\s*\n')).skip(1).toList().reversed) {
    final at = paragraphStartMs(p.replaceAll(RegExp(r'\s+'), ' ').trim());
    if (at != null) return at;
  }
  return null;
}

/// Note and Transcript (see the header): the kit's segmented toggle, small, the column's width on a phone and a
/// fixed one on a wider window.
class MeetingViewSwitch extends StatelessWidget {
  const MeetingViewSwitch({super.key, required this.transcript, required this.onChanged});

  /// Whether Transcript is chosen.
  final bool transcript;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), t.space(1), t.len('app-gutter-end'), t.space(2)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlacierSegmentedControl(
            key: const ValueKey('meeting-view'),
            ariaLabel: 'Note or transcript',
            fullWidth: true,
            size: GlacierSegmentedSize.sm,
            options: const [
              GlacierSegmentedOption(value: 'note', label: Text('Note')),
              GlacierSegmentedOption(value: 'transcript', label: Text('Transcript')),
            ],
            value: transcript ? 'transcript' : 'note',
            onValueChange: (value) => onChanged(value == 'transcript'),
          ),
        ),
      ),
    );
  }
}
