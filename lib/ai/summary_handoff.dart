/// A meeting's summary handed on to another of the account's devices, where the one that has it cannot write it
/// (Matt, 2026-10-26: "The engineering standup meeting was not auto summarized and sorted into the hello trade
/// meetings folder"). The port's own: the web app has one device's queue and nothing to hand on to.
///
/// What happened: Ghost recorded the standup, and Matt's Mac synced first, so it filed the take and wrote it up
/// (lib/meet/meet_in.dart). Whisper's transcript went into the note, and the summary never came: the Mac has no
/// summary model, and Claude, whose key is kept per device, is not set up on it. The write-up stopped at `needsModel`
/// and waited there for a model nobody was going to download, while the Fold, which has the model and Claude, never
/// heard of it. And the sorting into a workspace's Meetings folder (ai/meeting_sort.dart) follows the summary, so the
/// meeting stayed in the Inbox too.
///
/// THE HANDOFF, on the settings sync (lib/sync/prefs.dart), as the meetings' sorting marks are: one synced map,
/// [summaryHandoffsKey], `{noteId: entry}`, in the preferences' unknown keys ([Preferences.more]), so an older build
/// carries it untouched.
///
/// 1. **Waiting.** A meeting's job that reaches "needs a model" on a device (no summary model there, and no Claude to
///    write it: ai/summaries.dart's `needsModel`) is marked as waiting, `{from, fromName, at}`
///    ([SummaryHandoff.waitingHere]). Nothing else needs to go with it: the transcript is in the note already, its
///    phrases sync with it, and its words are under `## Transcript`.
/// 2. **Claimed once.** Every device looks at the map when the settings or its notes change
///    ([SummaryHandoff.look]). One that can write the summary (Claude chosen and free to run, or a summary model on it)
///    and has the note asks for the meeting's summary in its own queue, as a meeting recorded there is asked for. The
///    queue claims it before it runs ([SummaryHandoff.claim]): the claim, `{by, name, at}`, is written, a sync is
///    run, and only a claim the account then holds as this device's lets the run start ([accountHeld]). The account
///    writes the settings from the revision last seen and refuses a stale one (server/src/store/prefs.rs
///    `put_prefs`), so of two devices that claim at once the second one's write is refused, it reads the first's, and
///    its merge keeps a live claim it found over its own ([mergedHandoffs]): one device writes the summary.
/// 3. **A timeout.** A claim is live for [handoffClaimMs] from when it was made or last renewed, and the device writing
///    renews it as it goes, every [handoffRenewMs] at most ([SummaryHandoff.renew]): a device that dies mid-summary
///    holds the meeting for half an hour, not for ever, and another may claim it after. One whose job fails for good
///    lets it go ([SummaryHandoff.release]), and does not claim it again (its failed job stays on its own shelf).
/// 4. **Done.** The summary is written into the note by the queue's own writer, with the same prompts and Claude or
///    the model as any of its meetings, and its landing tells the sorting (ai/meeting_sort.dart) and the Slack post as
///    for any meeting; then the entry is marked `{done, by}` ([SummaryHandoff.finished]).
/// 5. **The device that had it** keeps saying it waits until the summary has come: its job stays, "Waiting for a
///    summary…" ([summaryWaitWords]), or "Being summarized on your phone." while another device's claim is live
///    ([SummaryHandoff.claimedElsewhere]). Once the entry says done its job is let go ([HandoffQueue.handedOff]), and
///    the summary is in the note when the note syncs.
///
/// MATT'S STANDUP, AND ANY MEETING LEFT LIKE IT ([strandedMeeting]). A meeting a build from before this left waiting
/// has no entry: the Mac that has it may not run the new build yet (the Mac app has no updater). So a device that can
/// write summaries also looks for the meetings Ghost filed in the last week that are stranded: the write-up done (no
/// "being written up" line), a transcript with words, no summary, never sorted, nothing queued for it here, and quiet
/// for an hour. It marks one waiting itself, and then claims it as above, so two such devices still write it once.
/// A Mac on the new build marks its own as soon as its queue looks at its jobs, so either way the next sync from the
/// Fold writes Matt's standup up and sorts it.
///
/// WHY THE MEETING STEP STILL FILES ON A DEVICE THAT CANNOT SUMMARIZE. The meet pass could leave a take on the service
/// for a device that can (each device could say in the synced settings whether it can, cheaply). It does not: the Mac
/// is where the transcript is cheapest (plugged in, Whisper on its own cores) and where the meeting shows at once,
/// while leaving the take would hide the meeting there until the phone app opens and make the phone run an hour of
/// Whisper on its battery. The handoff passes on only the step the Mac cannot do, which on the Fold is Claude: seconds.
///
/// CLAUDE FIRST, AND A MEETING STILL BEING HEARD (Matt, 2026-10-28: "We should be using Claude to generate the meeting
/// summaries not the local processor on the Mac when the anthropic API key is set"). That morning's standup was not
/// stranded by these rules: the Mac was an hour into Whisper on it at background priority, its note still saying it
/// was being written up, so no device marked it, and its summary waited on the Mac's transcript for five hours. Now:
/// - **A device with Claude takes a meeting at once; one with only a model gives it a moment.** A meeting marked
///   waiting is handed on at once by a device that would write it with Claude ([HandoffQueue.writesMeetingsWithClaude]),
///   and by a device that would write it only with its own model once [modelDeferMs] has passed since it was marked,
///   so a device with the key (the key follows the account, so any of them) claims it first. The claim itself is
///   unchanged: once, through the account. The device that marked it waiting holds nothing.
/// - **A meeting still being heard, with its captions** ([captionsStranded]): one Ghost filed in the last week whose
///   note still says it is being written up, with captions naming who said what, no summary, never sorted, nothing
///   queued for it here, and quiet for [captionsQuietMs]. A device that would write it with Claude marks it waiting
///   and takes it, as a stranded one, and writes it from the captions (ai/summaries.dart, CAPTIONS FIRST); the
///   device running Whisper goes on making the transcript, which lands under the summary, and its own write-up puts
///   aside any summary it makes (a device's kept summary says which section is its own, and the one another device
///   wrote is not). A device on the new build summarizes such a meeting itself from its captions straight away, so
///   this is for a device that is not, or is asleep.
///
/// Privacy is the summary's own: the transcript is already in the note on every device of the account; a device that
/// writes the summary with Claude sends it to Anthropic with that device's key, as it would for a meeting it recorded.
/// Local only is never asked to hand on: a meeting held for Claude by it waits as before, and a device under Local
/// only syncs nothing and claims only for itself.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/note.dart' show Note;
import '../core/preferences.dart' show Preferences;
import '../core/stored.dart';
import '../core/summary_text.dart' show summarySection;
import '../meet/meet_note.dart' show awaitsWriteUp, ghostLineStart;
import '../meet/speakers.dart' show captionWords, sectionOf;
import 'meeting_sort.dart' show meetingSortsKey;
import '../core/host_platform.dart';

/// The synced map of meetings handed on, in [Preferences.more] (see the header).
const String summaryHandoffsKey = 'summaryHandoffs';

/// How long a claim holds without being renewed: a device that died mid-summary lets the meeting go after this.
const int handoffClaimMs = 30 * 60000;

/// How often the device writing a summary renews its claim, at most.
const int handoffRenewMs = 10 * 60000;

/// How long an entry is kept once done, and one still waiting at all: the map does not outgrow the meetings.
const int handoffKeptMs = 30 * 24 * 3600000;

/// A stranded meeting ([strandedMeeting]) is one of the last week's, quiet for an hour.
const int strandedWithinMs = 7 * 24 * 3600000;
const int strandedQuietMs = 3600000;

/// A meeting still being heard, with its captions ([captionsStranded]), is taken on once quiet this long.
const int captionsQuietMs = 10 * 60000;

/// How long a device that would write a meeting only with its own model leaves one marked waiting for a device with
/// Claude to claim (see CLAUDE FIRST in the header).
const int modelDeferMs = 5 * 60000;

/// This device, as the handoff names it: an id of its own, made once and kept in its storage, and what a person
/// calls it ("Mac", "phone").
@immutable
class SummaryDevice {
  const SummaryDevice({required this.id, required this.name});

  final String id;
  final String name;
}

const String _deviceKey = 'glyph-handoff-device';

/// What a person calls this kind of device.
String deviceNameHere() => Platform.isMacOS ? 'Mac' : (Platform.isAndroid || Platform.isIOS ? 'phone' : 'computer');

SummaryDevice? _here;
Stored? _hereIn;

/// This device ([SummaryDevice]): its id read from [kept] (the app's [stored] unless given), or made and kept there.
/// A device whose storage refuses has one for this run.
SummaryDevice thisDevice([Stored? kept]) {
  final from = kept ?? stored;
  final known = _here;
  if (known != null && identical(_hereIn, from)) return known;
  var id = from.readText(_deviceKey);
  if (id == null || id.isEmpty) {
    final random = math.Random.secure();
    id = [for (var i = 0; i < 16; i += 1) random.nextInt(16).toRadixString(16)].join();
    from.writeText(_deviceKey, id);
  }
  _hereIn = from;
  return _here = SummaryDevice(id: id, name: deviceNameHere());
}

/// What a meeting waiting for its summary says on the device that has it (Matt, 2026-10-26), on a meeting plugin's
/// row and in the note: what to do here, or where else it will be written. [here] is this device's name.
String summaryWaitWords(String here) => here == 'Mac'
    ? 'Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone.'
    : 'Waiting for a summary: turn on Claude or download the summary model on this $here, or open Ghost.md on another of your devices.';

/// What it says while another device's claim on it is live.
String summaryElsewhereWords(String? there) => 'Being summarized on your ${there == null || there.isEmpty ? 'other device' : there}.';

/// What the meeting [noteId] says of its summary here, in the note and on a meeting plugin's row, or null where it
/// waits for none: being written on another device while that device's claim is live ([summaryElsewhereWords]); and
/// waiting, with what to do ([summaryWaitWords]), where its job here needs a model ([needsModelHere]) or this device
/// marked it waiting. A meeting done is said nothing of. [here] and [now] are this device and the clock's unless a
/// test says.
String? meetingWaitWords(Preferences prefs, String noteId, {required bool needsModelHere, SummaryDevice? here, int? now}) {
  final h = handoffsOf(prefs)[noteId];
  if (h?.done != null) return null;
  final me = here ?? thisDevice();
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  if (h != null && h.claimedAt(at)) return h.claimBy == me.id ? null : summaryElsewhereWords(h.claimName);
  if (needsModelHere || (h != null && h.from == me.id)) return summaryWaitWords(me.name);
  return null;
}

/// One meeting handed on, as the map keeps it (see the header).
@immutable
class Handoff {
  const Handoff({required this.from, this.fromName, required this.at, this.claimBy, this.claimName, this.claimAt, this.done, this.doneBy});

  /// An entry as kept, or null for anything that is not one.
  static Handoff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? ms(Object? v) => v is num && v.isFinite ? v.toInt() : null;
    final claim = raw['claim'];
    final c = claim is Map ? claim : const {};
    return Handoff(
      from: raw['from'] is String ? raw['from'] as String : '',
      fromName: raw['fromName'] is String ? raw['fromName'] as String : null,
      at: ms(raw['at']) ?? 0,
      claimBy: c['by'] is String ? c['by'] as String : null,
      claimName: c['name'] is String ? c['name'] as String : null,
      claimAt: ms(c['at']),
      done: ms(raw['done']),
      doneBy: raw['by'] is String ? raw['by'] as String : null,
    );
  }

  /// The device that could not write it ('' for a meeting found stranded), and what it is called.
  final String from;
  final String? fromName;

  /// When it was marked waiting.
  final int at;

  /// The device writing it, what it is called, and when it claimed it or last renewed the claim.
  final String? claimBy;
  final String? claimName;
  final int? claimAt;

  /// When the summary was written, and by which device.
  final int? done;
  final String? doneBy;

  /// Whether a claim on it holds at [now].
  bool claimedAt(int now) => done == null && claimBy != null && claimAt != null && now - claimAt! < handoffClaimMs;

  Map<String, Object?> toJson() => {
        'from': from,
        if (fromName != null) 'fromName': fromName,
        'at': at,
        if (claimBy != null) 'claim': {'by': claimBy, if (claimName != null) 'name': claimName, 'at': claimAt ?? 0},
        if (done != null) 'done': done,
        if (doneBy != null) 'by': doneBy,
      };

  Handoff _claimed(SummaryDevice? by, int now) => Handoff(from: from, fromName: fromName, at: at, claimBy: by?.id, claimName: by?.name, claimAt: by == null ? null : now, done: done, doneBy: doneBy);

  Handoff _done(String by, int now) => Handoff(from: from, fromName: fromName, at: at, done: now, doneBy: by);
}

Map<String, Object?> _rawOf(Object? map) {
  final raw = map is Map ? map[summaryHandoffsKey] : null;
  return raw is Map ? raw.cast<String, Object?>() : const {};
}

/// The meetings handed on, by note id.
Map<String, Handoff> handoffsOf(Preferences prefs) => {
      for (final MapEntry(:key, :value) in _rawOf(prefs.more).entries)
        key: ?Handoff.fromJson(value),
    };

/// [prefs] with [noteId]'s entry set to [entry] (null takes it out). The entries for notes that are no longer
/// meetings, and those older than [handoffKeptMs], go at the same time.
Preferences withHandoff(Preferences prefs, String noteId, Handoff? entry, {required int now}) {
  final kept = <String, Object?>{
    for (final MapEntry(:key, :value) in _rawOf(prefs.more).entries)
      if (key != noteId && prefs.meetings.containsKey(key))
        if (Handoff.fromJson(value) case final h? when now - math.max(h.at, h.done ?? 0) < handoffKeptMs) key: value,
    if (entry != null) noteId: entry.toJson(),
  };
  return prefs.copyWith(more: {...prefs.more, summaryHandoffsKey: kept});
}

/// Which of two devices' changes to one entry stands, where both changed it since they last agreed (see the header):
/// a summary written, then a live claim that was the account's first, then this device's.
Object? chosenHandoff(Object? mine, Object? theirs, {required int now}) {
  final m = Handoff.fromJson(mine), t = Handoff.fromJson(theirs);
  if (t == null) return mine;
  if (m == null) return theirs;
  if (t.done != null) return theirs;
  if (m.done != null) return mine;
  if (t.claimedAt(now) && t.claimBy != m.claimBy) return theirs;
  return mine;
}

String _said(Map<String, Object?> map, String key) => map.containsKey(key) ? jsonEncode(map[key]) : '\u0000';

/// The map as the settings' merge takes it where this device and another both changed it since [base]
/// (lib/sync/prefs.dart `merged`): an entry only one of them changed is that one's, and one both changed is
/// [chosenHandoff]'s.
Map<String, Object?> mergedHandoffs(Map<String, Object?> base, Map<String, Object?> mine, Map<String, Object?> theirs, {int? now}) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final out = <String, Object?>{};
  for (final key in {...theirs.keys, ...mine.keys}) {
    final Object? chosen;
    if (_said(mine, key) == _said(base, key)) {
      chosen = theirs[key];
    } else if (_said(theirs, key) == _said(base, key)) {
      chosen = mine[key];
    } else {
      chosen = chosenHandoff(mine[key], theirs[key], now: at);
    }
    if (chosen != null) out[key] = chosen;
  }
  return out;
}

/// Whether [note] is a meeting a build from before the handoff left without its summary (see the header): one Ghost
/// filed ([ghostLineStart]) in the last week, its write-up done, a transcript with words, no summary, never sorted,
/// with summaries on, and quiet for an hour.
bool strandedMeeting(Note note, Preferences prefs, {required int now}) {
  if (prefs.summaries == 'off') return false;
  final started = prefs.meetings[note.id];
  if (started == null || now - started > strandedWithinMs) return false;
  if (now - note.updatedAt < strandedQuietMs) return false;
  final body = note.body;
  if (!body.contains(ghostLineStart) || awaitsWriteUp(body) || summarySection(body) != null) return false;
  final sorts = prefs.more[meetingSortsKey];
  final mark = sorts is Map ? sorts[note.id] : null;
  if (mark is Map && mark.containsKey('sorted')) return false;
  return hasMeetingWords(note);
}

/// Whether [note] is a meeting still being heard that a device with Claude may write from its captions (see CLAUDE
/// FIRST in the header): one Ghost filed in the last week, its note still saying it is being written up, its
/// captions naming who said what ([captionWords]), no summary, never sorted, with summaries on, and quiet for
/// [captionsQuietMs].
bool captionsStranded(Note note, Preferences prefs, {required int now}) {
  if (prefs.summaries == 'off') return false;
  final started = prefs.meetings[note.id];
  if (started == null || now - started > strandedWithinMs) return false;
  if (now - note.updatedAt < captionsQuietMs) return false;
  final body = note.body;
  if (!body.contains(ghostLineStart) || !awaitsWriteUp(body) || summarySection(body) != null || captionWords(body) == null) return false;
  final sorts = prefs.more[meetingSortsKey];
  final mark = sorts is Map ? sorts[note.id] : null;
  return !(mark is Map && mark.containsKey('sorted'));
}

/// Whether [note] carries a meeting's words to summarize: its phrases, its written transcript, or its captions.
bool hasMeetingWords(Note note) =>
    (note.segments ?? const []).any((s) => s.text.trim().isNotEmpty) || (sectionOf(note.body, '## Transcript') ?? '').trim().isNotEmpty || captionWords(note.body) != null;

/// What the handoff asks of this device's summary queue (ai/summaries.dart `Summaries`).
abstract interface class HandoffQueue {
  /// Whether the note has a job in the queue, running, waiting or failed.
  bool hasJob(String id);

  /// Whether a meeting's summary could be written here now: Claude chosen and free to run, or, where Claude is not
  /// chosen, a summary model on the device.
  Future<bool> canWriteUpMeetings();

  /// Whether a meeting's summary would be written here by Claude, chosen and free to run now (see CLAUDE FIRST).
  Future<bool> writesMeetingsWithClaude();

  /// The meeting's summary asked for here, as a meeting recorded here is asked for.
  void handOn(String id);

  /// Another device wrote the summary: a job here that only waited for it goes.
  void handedOff(String id);
}

/// The handoff, as the app wires it: given this device, the preferences, the sync, the notes, and the queue it asks
/// ([attach]).
class SummaryHandoff {
  SummaryHandoff({
    required this.device,
    required this.preferences,
    required this.setPreferences,
    required this.syncNow,
    required this.getNote,
    required this.notes,
    this.accountHeld,
    this.isTrashed,
    int Function()? clock,
    void Function(String message)? warn,
  })  : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        warn = warn ?? debugPrint;

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;

  /// A sync now, waited for; its failure is no throw (lib/sync/engine.dart `syncNow`).
  final Future<void> Function() syncNow;

  /// The synced settings as the account holds them (lib/sync/engine.dart `accountPrefs`); null, or none given, where
  /// this device syncs nothing (signed out, Local only), and then nobody else can see the meeting, nor claim it.
  final Map<String, Object?>? Function()? accountHeld;
  final Future<Note?> Function(String id) getNote;

  /// This device's notes, for the stranded meetings.
  final List<Note> Function() notes;
  final bool Function(String id)? isTrashed;
  final int Function() clock;
  final void Function(String message) warn;

  HandoffQueue? _queue;

  /// The claims this device made that the account was seen to hold, so a job looked at again does not sync again.
  final Set<String> _confirmed = <String>{};

  /// The queue the handoff asks; given once both are made.
  void attach(HandoffQueue queue) => _queue = queue;

  Handoff? _entry(String id) => handoffsOf(preferences())[id];

  /// Whether another device holds a live claim on the meeting's summary.
  bool claimedElsewhere(String id) {
    final h = _entry(id);
    return h != null && h.claimedAt(clock()) && h.claimBy != device().id;
  }

  /// The name of the device writing it, while [claimedElsewhere].
  String? claimantName(String id) => claimedElsewhere(id) ? _entry(id)!.claimName : null;

  /// Whether the meeting's summary has been written, here or anywhere.
  bool isDone(String id) => _entry(id)?.done != null;

  /// Whether the meeting is marked as waiting for a summary at all, and not yet written.
  bool isWaiting(String id) {
    final h = _entry(id);
    return h != null && h.done == null;
  }

  /// The meetings whose jobs need a model here: each not yet marked is marked waiting, from this device. Asked every
  /// time the queue says what it holds, so it changes nothing for those already marked.
  void waitingHere(Iterable<String> ids) {
    final all = handoffsOf(preferences());
    final fresh = [for (final id in ids) if (!all.containsKey(id)) id];
    if (fresh.isEmpty) return;
    final me = device();
    final now = clock();
    setPreferences((prefs) {
      var next = prefs;
      for (final id in fresh) {
        if (!prefs.meetings.containsKey(id) || handoffsOf(next).containsKey(id)) continue;
        next = withHandoff(next, id, Handoff(from: me.id, fromName: me.name, at: now), now: now);
      }
      return next;
    });
  }

  /// The meeting's summary claimed for this device, before its queue writes it (see the header): true where it may
  /// run - no entry (a meeting nobody waits on elsewhere), or a claim the account holds as this device's once a sync
  /// has run; false where another device holds it, it is done, or the claim could not be seen to be the account's
  /// (no connection: asked again at the queue's next look).
  Future<bool> claim(String id) async {
    final h = _entry(id);
    if (h == null) return true;
    if (h.done != null) return false;
    final me = device();
    final now = clock();
    if (h.claimedAt(now) && h.claimBy != me.id) return false;
    if (h.claimedAt(now) && h.claimBy == me.id && _confirmed.contains(id)) return true;
    setPreferences((prefs) {
      final was = handoffsOf(prefs)[id];
      if (was == null || was.done != null || (was.claimedAt(now) && was.claimBy != me.id)) return prefs;
      return withHandoff(prefs, id, was._claimed(me, now), now: now);
    });
    try {
      await syncNow();
    } catch (failure) {
      warn('[ghost] the meeting’s summary could not be claimed: $failure');
    }
    final held = accountHeld?.call();
    final said = held == null ? _entry(id) : Handoff.fromJson(_rawOf(held)[id]);
    final mine = said != null && said.done == null && said.claimBy == me.id;
    if (mine) {
      _confirmed.add(id);
    } else {
      _confirmed.remove(id);
    }
    return mine;
  }

  /// The claim kept live while this device writes the summary: renewed once it is [handoffRenewMs] old.
  void renew(String id) {
    final me = device().id;
    final now = clock();
    final h = _entry(id);
    if (h == null || h.claimBy != me || h.done != null || now - (h.claimAt ?? 0) < handoffRenewMs) return;
    setPreferences((prefs) {
      final was = handoffsOf(prefs)[id];
      if (was == null || was.claimBy != me || was.done != null) return prefs;
      return withHandoff(prefs, id, was._claimed(device(), now), now: now);
    });
  }

  /// The summary written here (or the job ended with nothing to write): the entry marked done, by this device.
  void finished(String id) {
    _confirmed.remove(id);
    final h = _entry(id);
    if (h == null || h.done != null) return;
    final me = device().id;
    final now = clock();
    setPreferences((prefs) {
      final was = handoffsOf(prefs)[id];
      if (was == null || was.done != null) return prefs;
      return withHandoff(prefs, id, was._done(me, now), now: now);
    });
  }

  /// This device's job gave up: its claim let go, for another device to take.
  void release(String id) {
    _confirmed.remove(id);
    final me = device().id;
    final h = _entry(id);
    if (h == null || h.claimBy != me || h.done != null) return;
    setPreferences((prefs) {
      final was = handoffsOf(prefs)[id];
      if (was == null || was.claimBy != me || was.done != null) return prefs;
      return withHandoff(prefs, id, was._claimed(null, clock()), now: clock());
    });
  }

  bool _looking = false;
  bool _again = false;

  /// One look over the map and the stranded meetings (see the header): a meeting done elsewhere lets this device's
  /// waiting job go; one waiting, not held by another device, whose note is here with its words, is asked of this
  /// device's queue where it can write it; and a stranded meeting is marked waiting and asked for the same way.
  Future<void> look() async {
    if (_looking) {
      _again = true;
      return;
    }
    _looking = true;
    try {
      do {
        _again = false;
        await _lookOnce();
      } while (_again);
    } catch (failure) {
      warn('[ghost] the meetings waiting for a summary were not looked at: $failure');
    } finally {
      _looking = false;
    }
  }

  Future<void> _lookOnce() async {
    final queue = _queue;
    if (queue == null) return;
    final prefs = preferences();
    final now = clock();
    final all = handoffsOf(prefs);
    bool? able, withClaude;
    Future<bool> canWrite() async => able ??= await queue.canWriteUpMeetings();
    Future<bool> claudeHere() async => withClaude ??= await queue.writesMeetingsWithClaude();
    // When a meeting left for a device with Claude is this one's to take, if none has by then.
    int? deferredUntil;
    for (final MapEntry(key: id, value: h) in all.entries) {
      if (h.done != null) {
        if (queue.hasJob(id)) queue.handedOff(id);
        continue;
      }
      if (queue.hasJob(id) || (h.claimedAt(now) && h.claimBy != device().id)) continue;
      if (isTrashed?.call(id) ?? false) continue;
      final note = await getNote(id);
      if (note == null || !hasMeetingWords(note)) continue;
      if (!await canWrite()) return;
      // A device with only its own model leaves a meeting just marked to one with Claude for a while (CLAUDE FIRST).
      if (!await claudeHere() && now - h.at < modelDeferMs) {
        final until = h.at + modelDeferMs;
        deferredUntil = deferredUntil == null ? until : math.min(deferredUntil, until);
        continue;
      }
      queue.handOn(id);
    }
    if (deferredUntil != null) _lookAt(deferredUntil - now);
    for (final note in notes()) {
      if (all.containsKey(note.id) || queue.hasJob(note.id) || (isTrashed?.call(note.id) ?? false)) continue;
      final stranded = strandedMeeting(note, prefs, now: now);
      // A meeting still being heard is only taken on from its captions by a device with Claude (CLAUDE FIRST).
      if (!stranded && !(captionsStranded(note, prefs, now: now) && await claudeHere())) continue;
      if (!await canWrite()) return;
      setPreferences((was) => handoffsOf(was).containsKey(note.id) ? was : withHandoff(was, note.id, Handoff(from: '', at: now), now: now));
      queue.handOn(note.id);
    }
  }

  Timer? _later;

  /// One more look in [ms], for a meeting left to a device with Claude for a while.
  void _lookAt(int ms) {
    _later?.cancel();
    _later = Timer(Duration(milliseconds: math.max(0, ms) + 1000), () => unawaited(look()));
  }

  /// Looks whenever [changes] says something changed (the preferences, the notes), a second after the last word, and
  /// once now; answers the way to stop.
  VoidCallback start(Listenable changes, {Duration settle = const Duration(seconds: 1)}) {
    Timer? soon;
    void heard() {
      soon?.cancel();
      soon = Timer(settle, () => unawaited(look()));
    }

    changes.addListener(heard);
    heard();
    return () {
      soon?.cancel();
      _later?.cancel();
      changes.removeListener(heard);
    };
  }
}
