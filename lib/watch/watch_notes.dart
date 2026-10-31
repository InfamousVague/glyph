/// A voice note from the watch, made a note on the phone (docs/WATCH.md, "On the phone"): each take waiting in the
/// phone's inbox (watch_link.dart) becomes a voice note as one recorded here does, its words the phone's own Whisper's.
///
/// For each take, oldest first, and one at a time:
///
/// 1. The note's id is made from the take's ([watchNoteId]). A note already there was made before (a pass cut short
///    after the note was written), and the take only goes from the inbox.
/// 2. The take's WAV becomes the note's recording, moved into place by the core as a meeting Ghost was in is
///    (lib/meet/tape.dart): 16 kHz mono 16-bit, the file the core's Whisper reads.
/// 3. A take of up to [meetingFromMs] is a voice note: its words are heard from the recording ([WatchListen]: the
///    larger model's timed phrases where it is on the phone, else the live model's words), written as a voice note's
///    are, cues and all (lib/capture/markdown.dart `renderNote`: "new paragraph", "bullet point", "check box"…), with
///    the phrases on its tape, and dated when the watch recorded it. Over three minutes ([longNoteMs]) it is a long
///    voice note, whose summary is asked for when Settings › Recording › Summaries says "Meetings and long voice
///    notes", as the recorder asks for one.
/// 4. A longer take is a meeting: the note is made with its title and its tape, marked a meeting, and its write-up
///    asked for as a meeting's is ([WatchNotes.writeUp]: the phone's service, Whisper span by span with the app
///    closed, then the summary by the Summaries setting, Write up straight away honoured).
/// 5. Only then does the take go from the inbox.
///
/// **To Claude** (Matt, 2026-10-20: "the voice messages sent from the phone should be parsed by the AI in the same way
/// the microphone button does … that way we can add to existing notes, make lists etc"). Where Claude is shown here
/// (its plugin on and a key on this device, which Local only holds off) and Settings › Recording › Watch's "Send short
/// watch recordings to Claude" is on, a take of up to [meetingFromMs] is heard as above, and its words are then asked
/// of Claude as the dock's Talk to Claude asks them ([WatchClaude], lib/root/root_claude.dart), saying they came from
/// the watch and when ([watchClaudePrompt]). No note of its own is made and its recording goes, as the microphone
/// keeps none, once Claude's run is over. Each take is asked once ([WatchAsks], a record on this phone kept before the
/// ask is sent): where Claude could not do it (the network, a key refused, the month's spending limit) the take is
/// made a voice note as above, saying why, so nothing said is lost; and a take found asked but never answered (the
/// app was closed under the run) is made a voice note too, never asked again. A longer take is a meeting as before.
///
/// Where the words cannot be heard yet (the recorder is up, the engine is busy with another pass, no voice model on
/// the phone and Local only on), the take waits, its recording already the note's to be, and is tried again a minute
/// later while the app runs, when the app comes back to the front, and when another take arrives. Local only never
/// holds the words themselves: they are the phone's. Nothing is read aloud, and no command said on the watch is
/// carried out by the phone: a take is dictation, or, sent to Claude (below), a request Claude does as one said to the
/// dock's microphone is. Only then do its words leave the phone, to Anthropic with the person's key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../capture/markdown.dart' show RenderOptions, renderNote;
import '../capture/meeting.dart' show meetingTitle;
import '../core/note.dart';
import '../core/preferences.dart' show Preferences, longNoteMs;
import '../meet/meeting_mark.dart' show MeetingMark, withMeetingMark;
import '../mail/mail_note.dart' show mailNoteId;
import 'watch_link.dart';

/// Over this a take is written up as a meeting, not heard as a voice note: the write-up goes span by span and survives
/// the app being closed, where a voice note's words are heard in one pass while the app runs.
const int meetingFromMs = 10 * 60 * 1000;

/// The id of the note take [takeId] becomes: a UUID made from the take's, never one a mail or a meeting would make.
String watchNoteId(String takeId) => mailNoteId('watch:$takeId');

/// "Watch recording, 20 Oct 14:05": a meeting's title, saying where it was recorded.
String watchRecordingTitle(int at) => meetingTitle(at).replaceFirst('Meeting', 'Watch recording');

/// A voice note's body from what was heard (see the header): the words as a note recorded here writes them, or, where
/// nothing was heard, the time it was recorded and that.
String watchNoteBody(List<Segment> heard, int recordedAt) {
  final words = renderNote(heard, '', const RenderOptions(titled: true)).markdown.trim();
  if (words.isNotEmpty) return '$words\n';
  return '# ${watchRecordingTitle(recordedAt)}\n\nNothing was heard in this recording.\n';
}

/// What came of listening to a take's recording.
sealed class Heard {
  const Heard();
}

/// The phrases, timed on the recording (none where it was silent).
class HeardWords extends Heard {
  const HeardWords(this.segments);
  final List<Segment> segments;
}

/// Not now ([why]): the take waits and is tried again.
class HeardLater extends Heard {
  const HeardLater(this.why);
  final String why;
}

/// Listens to note [noteId]'s recording, [recordingMs] long.
typedef WatchListen = Future<Heard> Function(String noteId, int recordingMs);

/// What came of asking Claude a take's words.
sealed class WatchAsked {
  const WatchAsked();
}

/// Claude's run is over: it did what it was asked (or was stopped by the person, the ask in the chat).
class WatchAskedDone extends WatchAsked {
  const WatchAskedDone([this.answer = '']);
  final String answer;
}

/// Claude could not be asked, or its run failed ([why], in words a person reads): the take is made a voice note.
class WatchAskFailed extends WatchAsked {
  const WatchAskFailed(this.why);
  final String why;
}

/// The app's own Claude, as a take's words are asked of it (lib/root/root_claude.dart).
abstract interface class WatchClaude {
  /// Whether a take goes to Claude now: Claude shown here (its plugin on and a key on this device) and Settings ›
  /// Recording › Watch's switch on (`ClaudeSettings.watch`). Under the spending limit or not: an ask at the limit is
  /// refused by the runner, and the take is made a voice note saying so.
  Future<bool> ready();

  /// Asks [prompt] ([watchClaudePrompt]); [words] are what was heard, as the sheet shows them. Answers once Claude's
  /// run is over.
  Future<WatchAsked> ask({required String words, required String prompt, required WatchTake take});
}

/// What is known of a take sent to Claude.
enum WatchAskState {
  /// The ask was sent, and its run had not ended when last heard of.
  asking,

  /// Claude's run is over: the take only goes from the inbox.
  asked,

  /// Claude could not do it: the take is a voice note, saying why.
  failed,
}

/// The takes sent to Claude, kept on this phone so that none is asked twice (see the header).
abstract interface class WatchAsks {
  Future<({WatchAskState state, String why})?> of(String takeId);
  Future<void> mark(String takeId, WatchAskState state, {String why = ''});
}

/// [WatchAsks] in a JSON file: `{takeId: {state, why, at}}`, a record let go a month after it was written.
class FileWatchAsks implements WatchAsks {
  FileWatchAsks(this.file, {int Function()? now}) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final File file;
  final int Function() _now;

  static const int _keepMs = 30 * 24 * 60 * 60 * 1000;

  Map<String, Object?> _read() {
    try {
      if (!file.existsSync()) return {};
      final said = jsonDecode(file.readAsStringSync());
      return said is Map ? Map<String, Object?>.from(said) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<({WatchAskState state, String why})?> of(String takeId) async {
    final raw = _read()[takeId];
    if (raw is! Map) return null;
    final state = WatchAskState.values.where((s) => s.name == raw['state']).firstOrNull;
    if (state == null) return null;
    return (state: state, why: raw['why'] is String ? raw['why'] as String : '');
  }

  @override
  Future<void> mark(String takeId, WatchAskState state, {String why = ''}) async {
    final now = _now();
    final all = _read()..removeWhere((_, raw) => raw is! Map || (raw['at'] is num && now - (raw['at'] as num) > _keepMs));
    all[takeId] = {'state': state.name, 'why': why, 'at': now};
    file.parent.createSync(recursive: true);
    // Written whole, then put in place: a record half written is never read.
    final next = File('${file.path}.new')..writeAsStringSync(jsonEncode(all), flush: true);
    next.renameSync(file.path);
  }
}

/// The words heard, as one line for Claude: the phrases as they were said (Claude reads a spoken cue as it reads
/// anything else said).
String watchHeardWords(List<Segment> heard) => heard.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join(' ');

/// What Claude is asked: the words, as Talk to Claude asks them, and where and when they were said.
String watchClaudePrompt(String words, WatchTake take) {
  final at = DateTime.fromMillisecondsSinceEpoch(take.recordedAt);
  final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final day = '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  final watch = take.watch.trim().isEmpty ? 'my watch' : 'my watch (${take.watch.trim()})';
  return '$words\n\n(Said into $watch at $time on $day and heard by the phone: a voice request, as if said to the microphone.)';
}

/// What a voice note made in Claude's place says under its words.
String watchNotSentLine(String why) {
  final reason = why.trim().replaceAll(RegExp(r'[.\s]+$'), '');
  return '*Not done by Claude${reason.isEmpty ? '' : ': $reason'}. Kept as a voice note.*';
}

/// The library, as the takes are made notes in it.
abstract interface class WatchNoteStore {
  Future<Note?> getNote(String id);

  /// Whether note [id]'s recording is on this phone already.
  Future<bool> hasRecording(String id);

  /// The WAV at [path] moved into place as note [id]'s recording.
  Future<void> keepRecording(String id, String path);

  /// Note [id]'s recording, kept to hear a take Claude was then asked, removed: no note has it.
  Future<void> dropRecording(String id);

  /// A new note dated [createdAt], with its recording's length and phrases.
  Future<Note> makeNote({required String id, required String body, required int createdAt, required int recordingMs, required List<Segment> segments});
}

/// Makes each take waiting in the inbox a note (see the header).
class WatchNotes {
  WatchNotes({
    required this.host,
    required this.store,
    required this.listen,
    required this.preferences,
    this.held,
    this.enqueueSummary,
    this.writeUp,
    this.markMeeting,
    this.made,
    this.claude,
    this.asks,
    this.retry = const Duration(minutes: 1),
  });

  final WatchHost host;
  final WatchNoteStore store;
  final WatchListen listen;
  final Preferences Function() preferences;

  /// Whether a recorder holds the phone's cores now (lib/capture/refine.dart `refineHeld`): nothing is heard then.
  final bool Function()? held;

  /// A long voice note's summary, asked for (`Summaries.enqueueSummary(id, recording)`).
  final void Function(String noteId)? enqueueSummary;

  /// A meeting's write-up, asked for as a meeting Ghost was in asks for it (lib/meet/tape.dart `writeUp`); null where
  /// this device writes nothing up, and a long take is then heard as a voice note.
  final void Function(String noteId)? writeUp;

  /// Note [noteId] is a meeting, started at [at] (`prefs.meetings`).
  final void Function(String noteId, int at)? markMeeting;

  /// Told of each note made, with the watch it came from.
  final void Function(Note note, WatchTake take)? made;

  /// Claude, where a short take's words go to it (see the header); set by the root once it has one, null until then
  /// and where there is none, and every take is a voice note.
  WatchClaude? claude;

  /// The record that keeps each take from being asked of Claude twice; none, and nothing is asked.
  final WatchAsks? asks;
  final Duration retry;

  StreamSubscription<String>? _arrivals;
  Timer? _again;
  Future<int>? _running;
  bool _askedAgain = false;

  /// Failures this run, by take: a take that fails three times waits for the next run.
  final Map<String, int> _failed = {};

  /// Listens for takes as they arrive, and makes those already waiting [after] a moment, so the app's first frames
  /// are not shared with Whisper.
  void start({Duration after = Duration.zero}) {
    _arrivals ??= host.arrivals.listen((_) => unawaited(kick()), onError: (Object _) {});
    if (after == Duration.zero) {
      unawaited(kick());
    } else {
      _again?.cancel();
      _again = Timer(after, () => unawaited(kick()));
    }
  }

  /// Looks at the inbox now (again once the pass in hand is done, when one is).
  Future<int> kick() {
    final running = _running;
    if (running != null) {
      _askedAgain = true;
      return running;
    }
    _again?.cancel();
    _again = null;
    final pass = _pass().whenComplete(() {
      _running = null;
      if (_askedAgain) {
        _askedAgain = false;
        unawaited(kick());
      }
    });
    _running = pass;
    return pass;
  }

  void _later() {
    _again?.cancel();
    _again = Timer(retry, () => unawaited(kick()));
  }

  /// One look at the inbox: answers how many notes it made.
  Future<int> _pass() async {
    List<WatchTake> waiting;
    try {
      waiting = await host.waiting();
    } catch (failure) {
      debugPrint('[watch] the inbox could not be read: $failure');
      return 0;
    }
    var count = 0;
    for (final take in waiting) {
      if ((_failed[take.id] ?? 0) >= 3) continue;
      if (held?.call() ?? false) {
        _later();
        break;
      }
      try {
        final outcome = await _make(take);
        if (outcome == _Outcome.later) {
          _later();
          break;
        }
        if (outcome == _Outcome.made) count += 1;
      } catch (failure) {
        _failed[take.id] = (_failed[take.id] ?? 0) + 1;
        debugPrint('[watch] a voice note from the watch was not made: $failure');
        _later();
      }
    }
    return count;
  }

  Future<_Outcome> _make(WatchTake take) async {
    final id = watchNoteId(take.id);
    if (await store.getNote(id) != null) {
      await host.done(take.id);
      return _Outcome.gone;
    }
    if (!await store.hasRecording(id)) {
      if (!File(take.wav).existsSync()) {
        // Neither in the inbox nor kept: there is nothing to make a note of.
        await host.done(take.id);
        return _Outcome.gone;
      }
      await store.keepRecording(id, take.wav);
    }
    final ms = take.durationMs;
    final writeUp = this.writeUp;
    final asks = this.asks;
    final asked = asks == null ? null : await asks.of(take.id);
    if (asked?.state == WatchAskState.asked) {
      // Claude did it: the recording that was kept to hear it goes, and the take with it.
      await _dropRecording(id);
      await host.done(take.id);
      return _Outcome.gone;
    }
    final Note note;
    if (ms > meetingFromMs && writeUp != null) {
      // Marked a meeting in the note itself (lib/meet/meeting_mark.dart) and in the preferences ([markMeeting]).
      final body = withMeetingMark('# ${watchRecordingTitle(take.recordedAt)}\n', MeetingMark(startMs: take.recordedAt, kind: 'phone'));
      note = await store.makeNote(id: id, body: body, createdAt: take.recordedAt, recordingMs: ms, segments: const []);
      markMeeting?.call(id, take.recordedAt);
      writeUp(id);
    } else {
      final heard = await listen(id, ms);
      switch (heard) {
        case HeardLater(:final why):
          debugPrint('[watch] a voice note from the watch waits: $why');
          return _Outcome.later;
        case HeardWords(:final segments):
          String? notSent;
          switch (asked?.state) {
            case WatchAskState.asking:
              notSent = 'the app was closed before Claude finished, and Claude may have done some of it';
            case WatchAskState.failed:
              notSent = asked!.why;
            case WatchAskState.asked:
            case null:
              final words = watchHeardWords(segments);
              if (asks != null && words.isNotEmpty && ms <= meetingFromMs && await _toClaude()) {
                final why = await _ask(asks, take, words);
                if (why == null) {
                  await _dropRecording(id);
                  await host.done(take.id);
                  return _Outcome.asked;
                }
                notSent = why;
              }
          }
          var body = watchNoteBody(segments, take.recordedAt);
          if (notSent != null) body = '${body.trimRight()}\n\n${watchNotSentLine(notSent)}\n';
          note = await store.makeNote(id: id, body: body, createdAt: take.recordedAt, recordingMs: ms, segments: segments);
          if (ms > longNoteMs && segments.isNotEmpty && preferences().summaries == 'long') enqueueSummary?.call(id);
      }
    }
    await host.done(take.id);
    made?.call(note, take);
    return _Outcome.made;
  }

  /// Whether a take heard now goes to Claude: Local only off, Claude shown and the switch on.
  Future<bool> _toClaude() async {
    final claude = this.claude;
    if (claude == null || preferences().localOnly) return false;
    try {
      return await claude.ready();
    } catch (_) {
      return false;
    }
  }

  /// Asks Claude once: the record written before it is sent and after its run is over. Answers null where Claude did
  /// it, else why not.
  Future<String?> _ask(WatchAsks asks, WatchTake take, String words) async {
    await asks.mark(take.id, WatchAskState.asking);
    WatchAsked outcome;
    try {
      outcome = await claude!.ask(words: words, prompt: watchClaudePrompt(words, take), take: take);
    } catch (failure) {
      outcome = WatchAskFailed('$failure');
    }
    switch (outcome) {
      case WatchAskedDone():
        await asks.mark(take.id, WatchAskState.asked);
        return null;
      case WatchAskFailed(:final why):
        debugPrint('[watch] Claude could not do a request from the watch: $why');
        await asks.mark(take.id, WatchAskState.failed, why: why);
        return why;
    }
  }

  Future<void> _dropRecording(String id) async {
    try {
      await store.dropRecording(id);
    } catch (failure) {
      debugPrint('[watch] a recording Claude was asked from was not removed: $failure');
    }
  }

  void dispose() {
    _again?.cancel();
    _again = null;
    unawaited(_arrivals?.cancel());
    _arrivals = null;
  }
}

enum _Outcome { made, asked, gone, later }
