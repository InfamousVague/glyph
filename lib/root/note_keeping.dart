/// What the app keeps beside a note, let go once the note is deleted for good; and a meeting's write-up, stopped as
/// its note goes into the trash and asked for again as it comes out. The halves of
/// `src/app/notes/useNoteActions.ts` that lib/notes/note_actions.dart leaves to whoever has the recorder
/// ([NoteActions.onForget], [NoteActions.onTrashed], [NoteActions.onRestored]): `forgetKept`, the meeting's part of
/// `remove`, and `resumeWriteUp`.
///
/// What differs: the page's functions reach the queue, the phone and the preferences as modules; here they are handed
/// in, since voice is made after the app is and a build may have none. The filing in a workspace (`forgetNote`) is
/// the actions' own.
library;

import 'dart:async';

import '../ai/log.dart' show forgetRuns;
import '../ai/marks.dart' show forgetMarks;
import '../ai/summaries.dart' show RecordingJobState, Summaries, SummaryKind;
import '../ai/summary_keep.dart' show forgetSummary;
import '../core/library.dart' show transcriptOf;
import '../core/note.dart';
import '../core/place_tags.dart' show PlaceTags;
import '../core/preferences.dart';
import '../core/summary_text.dart' show summaryLine;
import '../format/results.dart' show forgetResults;

/// A note deleted for good (`forgetKept`): its gist (format/results.dart), the runs it has seen (ai/log.dart), the
/// changes marked in it (ai/marks.dart), the summary it was written (ai/summary_keep.dart), the job to write one
/// (ai/summaries.dart) and a tag waiting to say where it was written (core/place_tags.dart).
void forgetKept(String id, {Summaries? summaries, PlaceTags? places}) {
  forgetResults(id);
  forgetRuns(id);
  forgetMarks(id);
  forgetSummary(id);
  summaries?.dropSummary(id);
  places?.setPendingTag(id, null);
}

/// A note gone into the trash (`remove`): a meeting's write-up on the phone stops (any meeting, since Summaries off
/// makes no job to ask by), and a summary job waiting for it goes; restored, it is asked again ([resumeWriteUp]).
void meetingTrashed(Note note, {required Preferences prefs, Future<void> Function(String noteId)? cancelWriteUp, Summaries? summaries}) {
  if (!prefs.meetings.containsKey(note.id)) return;
  if (cancelWriteUp != null) unawaited(cancelWriteUp(note.id).then<void>((_) {}, onError: (Object _) {}));
  if (summaries != null && summaries.summaryNative(note.id)) summaries.dropSummary(note.id);
}

/// A meeting out of the trash, by Restore or by the toast's Undo alike (`resumeWriteUp`): its write-up asked of the
/// phone again, only where there is something to write up: a job the phone still holds (cancelled by the trash,
/// failed, waiting for a model, or done and not landed yet), or a note that never got its transcript. A meeting
/// whose result the app already took has its words in the note, and asking again would transcribe the hour afresh
/// and write over whatever the person corrected in it.
Future<void> resumeWriteUp(Note note, {required Preferences prefs, Summaries? summaries}) async {
  if (!prefs.meetings.containsKey(note.id) || summaries == null) return;
  final jobs = await summaries.recordingJobState().then<List<RecordingJobState>>((jobs) => jobs, onError: (Object _) => const <RecordingJobState>[]);
  final held = jobs.any((job) => job.id == note.id);
  if (!held && transcriptOf(note.body) != null) return;
  if (!summaries.writeUpOnHost(note.id, false)) return;
  if (prefs.summaries != 'off' && summaryLine(note.body) == null) summaries.enqueueSummary(note.id, SummaryKind.meeting, native: true);
}
