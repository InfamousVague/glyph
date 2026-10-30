/// A meeting's captions while Ghost is in it, on the device (Matt, 2026-10-30: "If possible add real time
/// transcriptions for meetings"; docs/MEET.md, "Live captions").
///
/// The bot hands glyph-api each batch of finished caption lines, with the line being said, every second and a half;
/// the service seals it to the account's encryption public key in that request and sends the frame to every
/// signed-in socket of the account (server/src/meet/live.rs), the one this device holds while it is in front for the
/// pokes (lib/live/poke.dart). Here each frame is opened with the account's private key, which never leaves its
/// devices, and its lines go into the meeting's live words ([liveTranscripts], lib/meet/live_transcript.dart), under
/// the note the meeting is ([meetLiveNoteId], made at its first caption by [LiveCaptionsHooks.noteFor]).
///
/// - **In order, each once.** A frame with finished lines has its `seq` (1, 2, ...) and the service keeps it; one with
///   only the line being said has `partial` and is not kept. A `seq` seen already is let go; one past the next (the
///   socket dropped, the app was behind, it came to the front mid-meeting) is caught up first from the kept frames
///   (`GET meet/{id}/live?after=<seq>`), and so is a meeting's first frame of any kind.
/// - **Opened as a take is**: its key out of `wrapped` in `meet-live-key:<meeting>:<n>`, the frame out of `data` in
///   `meet-live:<meeting>:<n>`, `<n>` its `seq` or `p<partial>`. One that will not open is let go (a newer service's,
///   or a key this device has not got yet): the take brings every line all the same.
/// - **Over**: `{ended: true}` (the take has come, or the meeting is done, failed or skipped). The words stay, not live,
///   until the take is filed into the note (meet_in.dart `syncMeet`, [handedOver]).
///
/// Nothing is written to the note as the captions come (live_transcript.dart says why); a meeting that ends with no
/// take to file has its live line changed once, later, by [settleLiveNotes].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/crypto_api.dart';
import '../core/bytes.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../sync/notes.dart' show LocalNotes;
import 'live_transcript.dart';
import 'meet_in.dart' show meetingNotesOf, withMeetingNote;

/// The context frame [n] of meeting [meeting] has its key wrapped in (server/src/meet/live.rs `key_context`).
String liveKeyContext(String meeting, String n) => 'meet-live-key:$meeting:$n';

/// The context the frame itself is sealed in (`seal_context`).
String liveSealContext(String meeting, String n) => 'meet-live:$meeting:$n';

/// What a frame holds, opened: its finished lines and the line being said.
typedef OpenedLive = ({List<LiveLine> lines, LiveLine? saying});

LiveLine? _line(Object? raw) {
  if (raw is! Map) return null;
  final text = raw['text'];
  if (text is! String || text.trim().isEmpty) return null;
  final at = raw['at'];
  final speaker = raw['speaker'];
  return LiveLine(at: at is num ? at.toInt() : 0, speaker: speaker is String ? speaker : '', text: text);
}

/// A frame's words out of its opened bytes (`{v: 1, meeting, startedAt, lines, partial}`).
OpenedLive readLive(Uint8List clear) {
  final said = jsonDecode(utf8.decode(clear));
  if (said is! Map) throw const FormatException('not a live frame');
  final lines = said['lines'];
  return (lines: [if (lines is List) for (final raw in lines) ?_line(raw)], saying: _line(said['partial']));
}

/// Frame [n] of meeting [meeting] opened with the account's [pair].
Future<OpenedLive> openLive(AccountCrypto crypto, EncryptionKey pair, {required String meeting, required String n, required String wrapped, required String data}) async {
  final raw = await crypto.unwrapWith(pair, wrapped, liveKeyContext(meeting, n));
  final key = await crypto.importSealKey(raw);
  return readLive(await crypto.openBytes(key, fromBase64Url(data), liveSealContext(meeting, n)));
}

/// What the captions ask of the account.
class LiveCaptionsHooks {
  const LiveCaptionsHooks({required this.open, required this.catchUp, required this.noteFor, this.ended});

  /// Note [noteId]'s meeting is over, as the service said it ([markLiveNoteEnded]).
  final void Function(String noteId)? ended;

  /// Frame [n] of [meeting] opened; throws for one that will not.
  final Future<OpenedLive> Function(String meeting, String n, String wrapped, String data) open;

  /// The frames the service keeps for [meeting] after [after] (`{live, first, frames}`); null where it cannot say.
  final Future<Map<String, Object?>?> Function(String meeting, int after) catchUp;

  /// The note [meeting] is, made now where it is not yet ([liveNoteBody]); null where none may be (signed out, or
  /// the person deleted the one made for it).
  final Future<String?> Function(String meeting) noteFor;
}

class _Meeting {
  int seq = 0;
  int partial = 0;
  bool caughtUp = false;
  String? noteId;
  Future<void> chain = Future<void>.value();
}

/// Every meeting's captions as they come to this device (see the header).
class LiveCaptions {
  LiveCaptions({required this.hooks, LiveTranscripts? store}) : store = store ?? liveTranscripts;

  final LiveCaptionsHooks hooks;
  final LiveTranscripts store;
  final Map<String, _Meeting> _meetings = {};

  /// One frame from the relay, handled after the last of its meeting's. Answers when it has been.
  Future<void> heard(Map<String, Object?> frame) {
    final meeting = frame['meeting'];
    if (meeting is! String || meeting.isEmpty) return Future<void>.value();
    final held = _meetings.putIfAbsent(meeting, _Meeting.new);
    return held.chain = held.chain.then((_) => _handle(meeting, held, frame)).catchError((Object failure) {
      debugPrint('[meet] a live caption was let go: $failure');
    });
  }

  /// Whatever the service kept for every meeting heard of here: after the app comes back to the front, whose
  /// socket dropped what came meanwhile.
  Future<void> catchUpAll() async {
    for (final MapEntry(key: meeting, value: held) in _meetings.entries.toList()) {
      held.chain = held.chain.then((_) async {
        final noteId = held.noteId;
        if (noteId != null && store.isLive(noteId)) await _catchUp(meeting, held, noteId);
      }).catchError((Object _) {});
    }
  }

  Future<void> _handle(String meeting, _Meeting held, Map<String, Object?> frame) async {
    if (frame['ended'] == true) {
      final noteId = held.noteId;
      if (noteId != null) {
        store.ended(noteId);
        hooks.ended?.call(noteId);
      }
      _meetings.remove(meeting);
      return;
    }
    final wrapped = frame['wrapped'], data = frame['data'];
    if (wrapped is! String || data is! String) return;
    final noteId = held.noteId ??= await hooks.noteFor(meeting);
    if (noteId == null) return;
    final seq = frame['seq'], partial = frame['partial'];
    if (seq is num) {
      final n = seq.toInt();
      if (n <= held.seq) return;
      if (n > held.seq + 1) await _catchUp(meeting, held, noteId);
      if (n <= held.seq) return;
      final opened = await hooks.open(meeting, '$n', wrapped, data);
      held.seq = n;
      held.caughtUp = true;
      store.heard(noteId, from: LiveFrom.bot, lines: opened.lines, saying: opened.saying, meeting: meeting);
    } else if (partial is num) {
      final n = partial.toInt();
      if (n <= held.partial) return;
      held.partial = n;
      if (!held.caughtUp) await _catchUp(meeting, held, noteId);
      final opened = await hooks.open(meeting, 'p$n', wrapped, data);
      store.heard(noteId, from: LiveFrom.bot, saying: opened.saying, meeting: meeting);
    }
  }

  /// The frames kept for [meeting] after the last one applied, applied in order.
  Future<void> _catchUp(String meeting, _Meeting held, String noteId) async {
    held.caughtUp = true;
    final said = await hooks.catchUp(meeting, held.seq);
    if (said == null) return;
    final frames = said['frames'];
    final lines = <LiveLine>[];
    if (frames is List) {
      for (final raw in frames) {
        if (raw is! Map) continue;
        final seq = raw['seq'], wrapped = raw['wrapped'], data = raw['data'];
        if (seq is! num || wrapped is! String || data is! String || seq.toInt() <= held.seq) continue;
        try {
          lines.addAll((await hooks.open(meeting, '${seq.toInt()}', wrapped, data)).lines);
        } catch (failure) {
          debugPrint('[meet] a kept live caption would not open: $failure');
        }
        held.seq = seq.toInt();
      }
    }
    if (lines.isNotEmpty || !store.isLive(noteId)) store.heard(noteId, from: LiveFrom.bot, lines: lines, meeting: meeting);
    if (said['live'] == false) {
      store.ended(noteId);
      hooks.ended?.call(noteId);
    }
  }
}

// --- the notes made while Ghost is in a meeting -------------------------------------------------------------------

/// This device's own record of the notes it made for meetings Ghost was in, `{note id: {at, ended?}}`: so a note the
/// person deleted is not made again by the next caption, and one whose take never came is settled.
const String liveNotesKey = 'glyph-meet-live-notes';

/// The note meeting [meeting] is while Ghost is in it ([meetLiveNoteId]), made here now where it is not yet: titled
/// [title], marked a meeting as a filed one is (`prefs.meetings`, and kept against the booking, meet_in.dart
/// [withMeetingNote]), and [made] told, for the list and the sync. None where this device made one for it before and
/// it is gone (the person deleted it), or the meeting was filed already as a note of its own (an older build's take).
Future<String?> liveNoteFor(String meeting, {required LocalNotes notes, required PreferencesStore prefs, required Stored kept, String? title, required int now, FutureOr<void> Function()? made}) async {
  final id = meetLiveNoteId(meeting);
  if (await notes.get(id) != null) return id;
  if (liveNoteMadeBefore(kept, id)) return null;
  final filedAs = meetingNotesOf(prefs.value)[meeting];
  if (filedAs != null && filedAs != id && await notes.get(filedAs) != null) return null;
  await notes.apply(Note(id: id, body: liveNoteBody(title), createdAt: now, updatedAt: now, source: NoteSource.capture));
  markLiveNoteMade(kept, id, now);
  prefs.update((was) => withMeetingNote(was.copyWith(meetings: {...was.meetings, id: now}), meeting, id));
  await made?.call();
  return id;
}

/// How long after its meeting ended a note with no take is settled, and how long after it was made at the most.
const int liveSettleAfterMs = 3600 * 1000;
const int liveSettleMostMs = 6 * 3600 * 1000;

Map<String, Map<String, int>> liveNotesMade(Stored kept) => kept.read<Map<String, Map<String, int>>>(liveNotesKey, const {}, (raw) {
      if (raw is! Map) return null;
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is Map) key: {for (final e in value.entries) if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt()},
      };
    });

void _keepMade(Stored kept, Map<String, Map<String, int>> made) => kept.write(liveNotesKey, made);

/// Note [noteId] made here for a meeting at [at].
void markLiveNoteMade(Stored kept, String noteId, int at) => _keepMade(kept, {...liveNotesMade(kept), noteId: {'at': at}});

/// Whether this device made note [noteId] for a meeting before (so it is not made again once deleted).
bool liveNoteMadeBefore(Stored kept, String noteId) => liveNotesMade(kept).containsKey(noteId);

/// Note [noteId]'s meeting ended at [at], as this device heard it.
void markLiveNoteEnded(Stored kept, String noteId, int at) {
  final made = liveNotesMade(kept);
  final was = made[noteId];
  if (was == null || was.containsKey('ended')) return;
  _keepMade(kept, {...made, noteId: {...was, 'ended': at}});
}

/// The notes this device made for meetings Ghost was in, each settled once it can be (a step of the sync pass, before
/// the takes): one whose take was filed is forgotten here; one whose meeting ended an hour ago, or that was made six
/// hours ago, with no take, has its live line changed to say so ([withoutTake]), the same words on every device, and
/// is forgotten too. Answers how many notes changed.
Future<int> settleLiveNotes({required Stored kept, required Future<({String body, Future<void> Function(String body) write})?> Function(String noteId) note, required int now, Set<String> waiting = const {}, LiveTranscripts? store}) async {
  final made = liveNotesMade(kept);
  if (made.isEmpty) return 0;
  final still = <String, Map<String, int>>{};
  var changed = 0;
  for (final MapEntry(key: id, value: times) in made.entries) {
    // Its take is waiting to be filed: not settled.
    if (waiting.contains(id)) {
      still[id] = times;
      continue;
    }
    final found = await note(id);
    if (found == null || !isLiveNote(found.body)) {
      // Deleted, or filed: kept only so a deleted one is not made again, for as long as its meeting could run.
      if (found == null && now - (times['at'] ?? now) < liveSettleMostMs) still[id] = times;
      continue;
    }
    final ended = times['ended'];
    if ((ended != null && now - ended >= liveSettleAfterMs) || now - (times['at'] ?? now) >= liveSettleMostMs) {
      await found.write(withoutTake(found.body));
      (store ?? liveTranscripts).forget(id);
      changed += 1;
      continue;
    }
    still[id] = times;
  }
  _keepMade(kept, still);
  return changed;
}
