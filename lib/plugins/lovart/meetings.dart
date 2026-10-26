/// Inspiration for design meetings: once a design meeting is written up, Lovart makes a moodboard of four from its
/// summary and it goes under the note's `## Inspiration` (Matt, 2026-10-26: "during design meetings the Lovart.ai
/// plugin can generate inspo images and such"). The root tells [LovartMeetings.meetingSummarized] beside the meeting
/// sorter and the Slack poster (lib/root/root_voice.dart).
///
/// The rules:
/// - **Only where asked.** The plugin on (Local only holds it off), both keys kept, and "Inspiration for design
///   meetings" on in its page ([designMeetingsOn], this device's, off until switched on), since it spends credits.
/// - **Only design meetings.** [looksLikeDesignMeeting] over the title and the summary.
/// - **Once per meeting.** Marked in the plugin's storage before Lovart is asked ([meetingsDoneKey]), so a summary made
///   again, or a failure, asks nothing more; "Inspiration images" on the note is there to ask again.
/// - **Into the note as it is then.** The note is read again once the images are kept, and written over the revision
///   read; one that moved on meanwhile is read again and written once more.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../core/images.dart' show PictureStore;
import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import '../../core/summary_text.dart' show summarySection;
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'client.dart';
import 'inspiration.dart';
import 'keep.dart';
import 'manifest.dart';

/// How many meetings are remembered as done: the newest.
const int _doneKept = 200;

/// Whether design meetings get inspiration on this device.
bool designMeetingsOn([PluginHost? via]) => (via ?? host).storage.get<Object?>(meetingsKey, false) == true;

/// Switches it.
void setDesignMeetings(bool on, [PluginHost? via]) => (via ?? host).storage.set(meetingsKey, on);

List<String> _done(PluginHost on) {
  final Object? kept = on.storage.get<Object?>(meetingsDoneKey, const <Object?>[]);
  return kept is List ? [for (final id in kept) if (id is String) id] : <String>[];
}

/// Gives design meetings their inspiration as they are written up.
class LovartMeetings {
  LovartMeetings({required this.getNote, required this.update, this.pictures, this.client, this.warn, PluginHost? via}) : _host = via;

  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String id, String body, int expectedRevision) update;

  /// Where the images are kept: the root's ([lovartPictureStore]) unless given.
  final PictureStore? pictures;

  /// The client to ask; the one with the kept keys unless given.
  final LovartClient? Function()? client;
  final void Function(String message)? warn;
  final PluginHost? _host;

  PluginHost get _on => _host ?? host;

  /// A meeting [id] was written up as [body]. Answers whether its inspiration was added.
  Future<bool> meetingSummarized(String id, String body) async {
    if (!pluginOn(manifest) || !designMeetingsOn(_on) || !hasLovartKeys(_on)) return false;
    final done = _done(_on);
    if (done.contains(id)) return false;
    final summary = summarySection(body)?.text ?? '';
    if (!looksLikeDesignMeeting(noteTitle(body), summary)) return false;
    // Marked before Lovart is asked: once per meeting, whatever happens next.
    final next = [...done, id];
    _on.storage.set(meetingsDoneKey, next.length > _doneKept ? next.sublist(next.length - _doneKept) : next);
    final lovart = client != null ? client!() : (_host == null ? lovartClient() : LovartClient.kept(via: _host));
    if (lovart == null) return false;
    final List<Uint8List> images;
    try {
      images = await lovart.generate(inspirationPrompt(body));
    } on LovartFailure catch (failure) {
      warn?.call('[lovart] no inspiration for the meeting: ${failure is LovartNeedsConfirmation ? failure.said : failure.message}');
      return false;
    }
    final names = await keepLovartImages(images, into: pictures);
    if (names.isEmpty) return false;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final note = await getNote(id);
      if (note == null) return false;
      try {
        await update(id, withInspiration(note.body, names), note.revision);
        return true;
      } catch (failure) {
        if (attempt == 1) warn?.call('[lovart] the inspiration was not written into the meeting: $failure');
      }
    }
    return false;
  }
}
