/// Ghost in a Google Meet, on the device (docs/MEET.md, "On the device"): the step of a sync pass that files each
/// meeting Ghost recorded as a note and has it written up here, and the setting's side (Settings › Meetings › Ghost in
/// meetings).
///
/// The service sealed each take to the account's encryption public key as it arrived, as it seals a mail
/// (meet_api.dart `openSealedTake`), so only the account's devices open it, and the write-up is the device's: Matt's
/// rule, summaries on the device, never on the server.
///
/// [syncMeet] is a step of the pass (lib/sync/engine.dart `meetIn`), beside the mail's, before the notes. For each
/// take waiting:
///
/// 1. Its note's id is made from the take's ([meetNoteId]); a note already there was filed before, by this device or
///    another, and the take only goes from the service.
/// 2. The take is fetched and opened. One that will not open is left for a newer app.
/// 3. The sound is kept as the note's recording ([MeetDevice.keepTape]: decoded to the WAV a recorded meeting keeps,
///    under the note's id), where this device can. Where it cannot (an iPhone, which records nothing; a sound it
///    cannot read), the take is left on the service for a day for a device that can, and then filed from the
///    captions alone, so a person with only an iPhone still gets the meeting.
/// 4. The note is written through the door a note from another device comes in by ([LocalNotes.apply]), with the
///    recording's length; marked a meeting (`prefs.meetings`, {noteId: startedAtMs}), as a meeting recorded here
///    is, so sync treats its audio as a meeting's (Settings › Meetings › Sync meeting recordings); the meeting it
///    was of is kept against it ([meetingNotesKey]), so the meetings' list opens it; and its write-up asked for
///    ([MeetDevice.writeUp]: Whisper over the recording, then the summary, honouring Write up straight away), as a
///    meeting recorded here is.
/// 5. Only then is the take deleted from the service.
///
/// And each pass, before the takes: a meeting whose write-up has put Whisper's transcript in the note has its
/// speakers named from the captions it kept (meet_note.dart `withSpeakers`), then leaves the list of those waiting
/// ([pendingKey]).
///
/// Quiet against a service with no meeting routes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/enc_key.dart';
import '../account/keystore.dart';
import '../account/session.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../sync/notes.dart' show LocalNotes;
import 'gmt.dart';
import 'meet_api.dart';
import 'meet_note.dart';

/// What this device can do with a meeting's sound (lib/meet/tape.dart is the app's).
abstract interface class MeetDevice {
  /// Keeps [audio] (of type [mime]) as note [noteId]'s recording, as a meeting recorded here is kept; answers its
  /// length in ms, or null where this device cannot (a sound it cannot read, no decoder).
  Future<int?> keepTape(String noteId, Uint8List audio, String mime);

  /// Asks for note [noteId]'s write-up: Whisper over its recording, then its summary, as a meeting recorded here is
  /// written up, honouring Write up straight away.
  void writeUp(String noteId);
}

/// This device's, once voice is made (lib/root/voice_wiring.dart); null where nothing can keep a meeting's sound
/// or write it up (an iPhone).
MeetDevice? meetDevice;

/// The notes waiting for their speakers to be named once the write-up has come (see the header), in the device's
/// storage.
const String pendingKey = 'glyph-meet-pending';

/// How long a take this device cannot keep the sound of is left on the service for one that can.
const int leftForAnotherMs = 24 * 3600 * 1000;

/// What the meeting step works with.
class MeetPassContext {
  MeetPassContext({required this.token, required this.api, required this.crypto, required this.pair, required this.notes, required this.prefs, required this.kept, required this.now, MeetDevice? Function()? device}) : device = device ?? (() => meetDevice);
  final String token;
  final Api api;
  final AccountCrypto crypto;

  /// The account's encryption pair, asked for only when there is a take to open.
  final Future<EncryptionKey> Function() pair;
  final LocalNotes notes;
  final PreferencesStore prefs;
  final Stored kept;
  final int Function() now;
  final MeetDevice? Function() device;
}

/// One meeting step, as the engine is handed it: answers how many notes it wrote.
typedef MeetPass = Future<int> Function(MeetPassContext ctx);

List<String> _pending(Stored kept) => kept.read<List<String>>(pendingKey, const <String>[], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : const <String>[]);

void _setPending(Stored kept, List<String> ids) => kept.write(pendingKey, ids);

/// The speakers named in each meeting whose transcript has come (see the header); answers how many notes changed.
Future<int> nameSpeakers(MeetPassContext ctx) async {
  final waiting = _pending(ctx.kept);
  if (waiting.isEmpty) return 0;
  final still = <String>[];
  var changed = 0;
  for (final id in waiting) {
    final note = await ctx.notes.get(id);
    if (note == null) continue;
    final next = withSpeakers(note.body, note.segments ?? const <Segment>[]);
    if (next == null) {
      // The write-up is still to come: wait for it, captions or not (its line is taken off when it has come).
      if (note.body.contains('\n## Captions') || awaitsWriteUp(note.body)) still.add(id);
      continue;
    }
    if (next != note.body) {
      await ctx.notes.apply(note.copyWith(body: next, updatedAt: ctx.now()));
      changed += 1;
    }
  }
  _setPending(ctx.kept, still);
  return changed;
}

/// The meeting step (see the header). Answers how many notes it wrote.
Future<int> syncMeet(MeetPassContext ctx) async {
  final meet = MeetApi(ctx.api);
  var written = await nameSpeakers(ctx);
  final waiting = await meet.takes(ctx.token);
  if (waiting == null || waiting.isEmpty) return written;
  EncryptionKey? pair;
  for (final take in waiting) {
    final noteId = meetNoteId(take.id);
    if (await ctx.notes.get(noteId) != null) {
      // Filed before, maybe by a build that kept no meeting against it.
      if (take.meeting.isNotEmpty && meetingNotesOf(ctx.prefs.value)[take.meeting] != noteId) ctx.prefs.update((was) => withMeetingNote(was, take.meeting, noteId));
    } else {
      final sealed = await meet.take(ctx.token, take);
      // Filed by another device a moment ago.
      if (sealed == null) continue;
      final OpenedTake opened;
      try {
        opened = await openSealedTake(ctx.crypto, pair ??= await ctx.pair(), id: take.id, wrapped: sealed.wrapped, sealed: sealed.sealed);
      } catch (failure) {
        // Left waiting: a newer app may read what this one cannot.
        debugPrint('[meet] a meeting would not open: $failure');
        continue;
      }
      final now = ctx.now();
      final device = ctx.device();
      int? ms;
      if (opened.audio.isNotEmpty && device != null) {
        try {
          ms = await device.keepTape(noteId, opened.audio, opened.mime);
        } catch (failure) {
          debugPrint('[meet] a meeting\'s sound was not kept: $failure');
        }
      }
      final writeUp = ms != null;
      if (!writeUp && opened.audio.isNotEmpty && now - (take.at > 0 ? take.at : now) < leftForAnotherMs) {
        // Left for a device that can keep its sound, for a day.
        continue;
      }
      final startedAt = opened.startedAt > 0 ? opened.startedAt : (take.at > 0 ? take.at : now);
      await ctx.notes.apply(Note(
        id: noteId,
        body: meetNoteBody(opened, now: now, writeUp: writeUp, why: opened.audio.isEmpty ? CaptionsOnly.noSound : CaptionsOnly.notKept),
        createdAt: startedAt,
        updatedAt: now,
        source: NoteSource.capture,
        recordingMs: ms,
      ));
      written += 1;
      final meeting = take.meeting.isNotEmpty ? take.meeting : opened.meeting;
      ctx.prefs.update((was) => withMeetingNote(was.copyWith(meetings: {...was.meetings, noteId: startedAt}), meeting, noteId));
      if (writeUp) {
        _setPending(ctx.kept, [..._pending(ctx.kept).where((id) => id != noteId), noteId]);
        device!.writeUp(noteId);
      }
    }
    // Filed, here or before: the sealed copy goes from the service.
    await meet.drop(ctx.token, take.id);
  }
  return written;
}

// --- the setting ----------------------------------------------------------------------------------------------------

/// The preference that keeps which note each meeting became, `{meeting id: note id}` (Matt, 2026-10-24: "add the
/// ability to click a meeting to jump to the associated note"). The service forgets a take once a device has it, and
/// a take's id is the note's, not the meeting's, so nothing else says which note a meeting is. Kept in the
/// preferences, so it follows the account to every device beside [Preferences.meetings] (lib/sync/prefs.dart
/// `syncedPrefs`), and in [Preferences.more], as the smart notebooks are (lib/core/smart_notebooks.dart), so the
/// shared class is untouched and an older build writes it back as it read it.
const String meetingNotesKey = 'meetingNotes';

/// The meetings' notes as the preferences keep them ([meetingNotesKey]); anything else there is nothing.
Map<String, String> meetingNotesOf(Preferences prefs) {
  final raw = prefs.more[meetingNotesKey];
  return {
    if (raw is Map)
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
  };
}

/// [prefs] with [meeting] kept as having become note [noteId]. Only the meetings whose notes are still meetings
/// ([Preferences.meetings]) are kept, so the map does not outgrow the notes it names.
Preferences withMeetingNote(Preferences prefs, String meeting, String noteId) {
  if (meeting.isEmpty) return prefs;
  final kept = {
    for (final MapEntry(:key, :value) in meetingNotesOf(prefs).entries)
      if (prefs.meetings.containsKey(value)) key: value,
    meeting: noteId,
  };
  return prefs.copyWith(more: {...prefs.more, meetingNotesKey: kept});
}

/// How long before a meeting's start Ghost's recording of it may have begun: the bot joins a little early.
const int meetingEarlyMs = 15 * 60000;

/// The note [booking] became, among [notes] (this device's, by id, not the trash); null while there is none.
///
/// The one the meeting step kept against it ([meetingNotesOf], [filed]). A meeting Ghost was in before that was
/// kept has none there, so for one that is done: the note Ghost filed (its first line [ghostLineStart]) whose
/// recording began while the meeting was on ([meetings], a note's start), the nearest its start, and kept against
/// no other meeting. Ghost is in one meeting at a time (`busy`), so two such notes for one meeting do not happen.
String? meetingNoteFor(MeetBooking booking, {required Map<String, String> filed, required Map<String, num> meetings, required Map<String, Note> notes}) {
  final kept = filed[booking.id];
  if (kept != null) return notes.containsKey(kept) ? kept : null;
  if (booking.state != MeetState.done || booking.startsAt <= 0) return null;
  final claimed = filed.values.toSet();
  final from = booking.startsAt - meetingEarlyMs;
  final to = booking.endsAt > booking.startsAt ? booking.endsAt : booking.startsAt + 2 * 3600000;
  String? best;
  var nearest = 0;
  for (final MapEntry(key: id, value: at) in meetings.entries) {
    final note = notes[id];
    if (note == null || claimed.contains(id) || at < from || at > to || !note.body.contains(ghostLineStart)) continue;
    final off = (at - booking.startsAt).abs().toInt();
    if (best == null || off < nearest) {
      best = id;
      nearest = off;
    }
  }
  return best;
}

/// A failure's detail in a person's words: why Ghost could not join.
String meetDetailWords(String? detail) => switch ((detail ?? '').toLowerCase().replaceAll(' ', '_')) {
      'signed_out' => 'Ghost was signed out of Google',
      'not_admitted' => 'nobody let Ghost in',
      'refused' => 'the meeting refused Ghost',
      'busy' => 'Ghost was in another meeting',
      'upload' => 'the recording did not reach Ghost.md',
      'missed' => 'Ghost missed it',
      _ => '',
    };

/// A meeting's state in a person's words, as the card shows it.
String meetStateWords(MeetBooking meeting) {
  switch (meeting.state) {
    case MeetState.booked:
      return 'Booked';
    case MeetState.joining:
      return 'Joining';
    case MeetState.inCall:
      return 'In the meeting';
    case MeetState.leave:
      return 'Leaving';
    case MeetState.done:
      return 'Written up';
    case MeetState.failed:
      final why = meetDetailWords(meeting.detail);
      return why.isEmpty ? 'Couldn’t join' : 'Couldn’t join: $why';
    case MeetState.skipped:
      return 'Skipped';
    case MeetState.cancelled:
      return 'Cancelled';
    case MeetState.other:
      return 'Booked';
  }
}

/// A Google Meet link, as a person pastes one: `https://meet.google.com/abc-defg-hij`, with or without the scheme.
String? meetLink(String typed) {
  final text = typed.trim();
  final match = RegExp(r'^(?:https?://)?meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3})(?:[/?#].*)?$', caseSensitive: false).firstMatch(text);
  if (match == null) return null;
  return 'https://meet.google.com/${match.group(1)!.toLowerCase()}';
}

/// The setting's side of Ghost in meetings: the meetings as the service last said them, and what a person may do
/// with them.
class MeetIn extends ChangeNotifier {
  MeetIn({required this.account, required this.keys, required this.api, required this.crypto}) {
    account.addListener(_accountChanged);
  }

  final AccountSource account;
  final KeyStore keys;
  final Api api;
  final AccountCrypto crypto;

  List<MeetBooking>? _meetings;
  bool _available = true;

  /// The meetings as last read, soonest first; null until they have been.
  List<MeetBooking>? get meetings => _meetings;

  /// Whether the service books meetings at all: an older one does not.
  bool get available => _available;

  String _token() {
    final session = account.session;
    if (session == null) throw const ApiError(401, 'Sign in under Settings › Account first.');
    return session.token;
  }

  Future<void>? _reading;
  int _triedAt = 0;
  int? _for;

  /// Reads the meetings soon, once a minute at the most however often the page is drawn.
  void readSoon() {
    if (_reading != null || account.session == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _triedAt < 60000) return;
    _triedAt = now;
    _reading = refresh().then<void>((_) {}, onError: (Object _) {}).whenComplete(() => _reading = null);
  }

  void _accountChanged() {
    final now = account.session?.accountId;
    if (now == _for) return;
    _for = now;
    _triedAt = 0;
    if (_meetings != null) {
      _meetings = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    super.dispose();
  }

  String? _problem;

  /// Why the meetings could not be read, the last time they were not; null once they were.
  String? get problem => _problem;

  /// What the service says now.
  Future<List<MeetBooking>> refresh() async {
    final List<MeetBooking>? said;
    try {
      said = await MeetApi(api).meetings(_token());
    } catch (failure) {
      _problem = 'Your meetings could not be read just now.';
      notifyListeners();
      rethrow;
    }
    _problem = null;
    _available = said != null;
    _meetings = said ?? const [];
    notifyListeners();
    return _meetings!;
  }

  void _put(MeetBooking? meeting) {
    if (meeting == null) return;
    final list = [...?_meetings];
    final at = list.indexWhere((m) => m.id == meeting.id);
    if (at >= 0) {
      list[at] = meeting;
    } else {
      list.add(meeting);
      list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    _meetings = list;
    notifyListeners();
  }

  /// Ghost joins the Meet at [url] now: the account's encryption key seen to first, since the recording is sealed
  /// to it as it arrives.
  Future<MeetBooking?> sendNow(String url, {String? title}) async {
    final link = meetLink(url);
    if (link == null) throw const ApiError(400, 'That is not a Google Meet link. It looks like meet.google.com/abc-defg-hij.');
    final token = _token();
    final accountKey = await account.accountKey();
    if (accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
    await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto));
    final booked = await MeetApi(api).book(token, link, title: title);
    _put(booked);
    return booked;
  }

  /// Ghost does not join [id], or leaves it now.
  Future<void> skip(String id) async => _put(await MeetApi(api).skip(_token(), id));
}
