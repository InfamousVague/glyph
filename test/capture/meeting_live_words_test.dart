// A meeting recorded on this phone, its words live while someone looks (lib/capture/meeting_live_words.dart; Matt,
// 2026-10-30: "If possible add real time transcriptions for meetings"): the speech model listens beside the meeting
// service's recording only while that meeting records, the app is in front and the meeting screen or its Transcript
// is up, and the setting allows it; each phrase timed from the meeting's start, named by nobody. Over a fake
// recogniser and a fake service.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/meeting_live_words.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/meet/live_transcript.dart';

/// The service: no state of its own to ask; the test sets the meeting's.
class _Host implements MeetingHost {
  @override
  bool get hasMeetings => false;
  @override
  bool get visible => true;
  @override
  String? meetingStateJson() => null;
  @override
  bool canNotify() => false;
}

/// The meeting service's half: whether it hands its samples over.
class FakeFeed implements LiveWordsHost {
  FakeFeed({this.can = true});
  final bool can;
  bool on = false;
  final List<bool> asked = [];

  @override
  Future<bool> feed(bool on) async {
    asked.add(on);
    this.on = on && can;
    return can || !on;
  }
}

/// The speech model: says what it is told to, a phrase at a time.
class FakeRecogniser implements LiveRecogniser {
  FakeRecogniser({this.can = true});
  final bool can;
  final StreamController<CaptureEvent> _events = StreamController<CaptureEvent>.broadcast(sync: true);
  bool listening = false;
  int starts = 0;
  int stops = 0;

  void say(int startMs, String text) => _events.add(CaptureEventSegment(Segment(startMs: startMs, endMs: startMs + 2000, text: text)));

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    starts += 1;
    listening = can;
    return can;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    listening = false;
  }
}

const String noteId = 'meeting-1';

MeetingState recordingAt(int startedAt) => MeetingState(recording: true, noteId: noteId, title: 'Meeting, 30 Oct 10:00', startedAt: startedAt, elapsedMs: 0, silenced: false, writingUp: null, discarded: const []);

const MeetingState stopped = MeetingState(recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: noteId, discarded: []);

void main() {
  late MeetingLive meeting;
  late FakeFeed feed;
  late FakeRecogniser model;
  late LiveWordsSetting setting;
  late LiveTranscripts store;
  late MeetingLiveWords words;
  var front = true;
  var charging = false;
  var dictating = false;
  var clock = 1000000;

  setUp(() {
    useStored(MemoryStored());
    front = true;
    charging = false;
    dictating = false;
    clock = 1000000;
    meeting = MeetingLive(host: _Host(), writeUpRunningNow: () => false, now: () => clock);
    feed = FakeFeed();
    model = FakeRecogniser();
    setting = LiveWordsSetting(phone: true);
    setting.value = LiveWordsChoice.on;
    store = LiveTranscripts();
    words = MeetingLiveWords(meeting: meeting, host: feed, recogniser: model, setting: setting, charging: () => charging, inFront: () => front, dictating: () => dictating, now: () => clock, store: store);
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('while the meeting records and its screen is up, each phrase comes, timed from the meeting’s start and named by nobody', () async {
    meeting.setMeetingStateForTests(recordingAt(clock - 65000));
    final off = words.watch(noteId);
    await settle();
    expect((model.listening, feed.on, words.hearing), (true, true, noteId));
    expect(store.isLive(noteId), isTrue, reason: 'Live from the first moment it listens');
    model.say(0, 'so the launch is on Tuesday.');
    model.say(4000, 'and the pricing page is drafted.');
    expect(store.of(noteId)!.turns, [(speaker: null, startMs: 65000, text: 'So the launch is on Tuesday. And the pricing page is drafted.')]);
    expect(store.of(noteId)!.from, LiveFrom.device);
    // Nobody looking: the model lets go, the service stops handing samples over, the words stay.
    off();
    await settle();
    expect((model.listening, feed.on, words.hearing), (false, false, null));
    expect(store.of(noteId)!.lines, hasLength(2));
    await words.close();
  });

  test('no live words when nothing is recording: never listened, whoever looks', () async {
    meeting.setMeetingStateForTests(stopped);
    final off = words.watch(noteId);
    await settle();
    expect((model.starts, feed.asked.isEmpty, words.hearing), (0, true, null));
    expect(store.of(noteId), isNull);
    // Another note being recorded is not this one.
    meeting.setMeetingStateForTests(MeetingState(recording: true, noteId: 'another', title: null, startedAt: clock, elapsedMs: 0, silenced: false, writingUp: null, discarded: const []));
    await settle();
    expect(model.starts, 0);
    off();
    await words.close();
  });

  test('the screen going off stops it at once, and it starts again with the app in front; the meeting’s end ends it', () async {
    meeting.setMeetingStateForTests(recordingAt(clock));
    final off = words.watch(noteId);
    await settle();
    expect(model.listening, isTrue);
    front = false;
    words.check();
    await settle();
    expect((model.listening, feed.on), (false, false));
    front = true;
    words.check();
    await settle();
    expect((model.listening, feed.on, model.starts), (true, true, 2));
    // Done: the meeting stops; the words stay, not live, for the write-up to replace.
    model.say(1000, 'last words.');
    meeting.setMeetingStateForTests(stopped);
    await settle();
    expect((model.listening, feed.on), (false, false));
    expect(store.of(noteId)!.live, isFalse);
    expect(store.of(noteId)!.lines.single.text, 'last words.');
    off();
    await words.close();
  });

  test('the setting: off never listens, while charging only on the charger, on always; each says why on the screens', () async {
    meeting.setMeetingStateForTests(recordingAt(clock));
    setting.value = LiveWordsChoice.off;
    final off = words.watch(noteId);
    await settle();
    expect(model.starts, 0);
    expect(words.why(noteId), 'Live transcript is off. Turn it on in Settings › Recording.');
    setting.value = LiveWordsChoice.charging;
    await settle();
    expect(model.starts, 0);
    expect(words.why(noteId), contains('while the phone is charging'));
    charging = true;
    words.check();
    await settle();
    expect((model.listening, words.why(noteId)), (true, null));
    charging = false;
    words.check();
    await settle();
    expect(model.listening, isFalse, reason: 'off the charger, it lets go');
    setting.value = LiveWordsChoice.on;
    await settle();
    expect(model.listening, isTrue);
    off();
    await words.close();
  });

  test('the choice is this device’s own, kept on it: a phone starts at While charging, the Mac at On', () {
    useStored(MemoryStored());
    expect(LiveWordsSetting(phone: true).value, LiveWordsChoice.charging);
    expect(LiveWordsSetting(phone: false).value, LiveWordsChoice.on);
    final kept = LiveWordsSetting(phone: true)..value = LiveWordsChoice.off;
    expect(kept.value, LiveWordsChoice.off);
    expect(stored.read<Object?>(liveWordsKey, null, (raw) => raw), 'off');
    expect(LiveWordsSetting(phone: true).value, LiveWordsChoice.off, reason: 'read back');
  });

  test('an older build has none: a core that does not know the meeting’s mode, or a service that cannot hand samples over', () async {
    meeting.setMeetingStateForTests(recordingAt(clock));
    final oldCore = MeetingLiveWords(meeting: meeting, host: feed, recogniser: FakeRecogniser(can: false), setting: setting, charging: () => true, inFront: () => true, dictating: () => false, store: store);
    final off = oldCore.watch(noteId);
    await settle();
    expect((oldCore.hearing, feed.on), (null, false));
    expect(oldCore.why(noteId), contains('This build can’t show the words live'));
    off();
    await oldCore.close();
    final oldService = MeetingLiveWords(meeting: meeting, host: FakeFeed(can: false), recogniser: model, setting: setting, charging: () => true, inFront: () => true, dictating: () => false, store: store);
    final off2 = oldService.watch(noteId);
    await settle();
    expect((oldService.hearing, model.listening, model.stops), (null, false, 1), reason: 'the model let go at once');
    off2();
    await oldService.close();
  });

  test('a dictation keeps the model: the meeting’s words wait for it and never let it go under it', () async {
    meeting.setMeetingStateForTests(recordingAt(clock));
    final off = words.watch(noteId);
    await settle();
    expect(model.listening, isTrue);
    dictating = true;
    model.say(0, 'a dictation’s words.');
    expect(store.of(noteId)!.lines, isEmpty, reason: 'its words are not the meeting’s');
    words.check();
    await settle();
    expect((words.hearing, feed.on, model.stops), (null, false, 0));
    dictating = false;
    words.check();
    await settle();
    expect((words.hearing, model.starts), (noteId, 2));
    off();
    await words.close();
  });
}
