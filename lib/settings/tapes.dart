/// The Tapes row's sums (lib/settings/panes/recording_pane.dart; docs/DESIGN.md §127 section 6 of ../glyph): how
/// much room the recordings take on this device, said from their lengths rather than measured (16 kHz, 16-bit,
/// mono: an hour is about 115 MB), and which of them the row offers to remove the audio of. Pure, so the pane's
/// words can be tested without a store. A port of `src/app/settings/tapes.ts`.
library;

import 'dart:math' as math;

import '../core/note.dart';

/// Bytes a recording of one millisecond takes: 16 kHz, 16-bit, mono (`BYTES_PER_MS`).
const int bytesPerMs = 32;

/// A tape older than this is one the row offers to remove the audio of (`OLD_MS`).
const int oldMs = 30 * 24 * 60 * 60 * 1000;

/// The tapes among [notes] whose audio is on this device: a length, and not [away] (its audio removed by this row,
/// or said by its file not to be here, which is a synced note whose audio stayed on the device that made it). The
/// words "on this device" are only true of these (`tapesHere`).
List<Note> tapesHere(Iterable<Note> notes, bool Function(String id) away) => [
      for (final note in notes)
        if ((note.recordingMs ?? 0) > 0 && !away(note.id)) note,
    ];

/// How much room the tapes among [notes] take, from their lengths (`tapeBytes`).
int tapeBytes(Iterable<Note> notes) => notes.fold(0, (sum, note) => sum + math.max(0, note.recordingMs ?? 0) * bytesPerMs);

/// "2.3 GB" or "410 MB": how much room the tapes take, never less than a megabyte once there is one (`tapeSize`).
String tapeSize(int bytes) => bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${math.max(1, (bytes / 1e6).round())} MB';

/// The notes whose audio the row would remove: a tape, not archived, made more than a month before [now]
/// (`oldTapes`).
List<Note> oldTapes(Iterable<Note> notes, int now) => [
      for (final note in notes)
        if ((note.recordingMs ?? 0) > 0 && (note.archivedAt ?? 0) == 0 && now - note.createdAt > oldMs) note,
    ];
