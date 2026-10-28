// Claude where the key is, and captions first (lib/ai/summaries.dart's "CLAUDE WHERE THE KEY IS, AND CAPTIONS FIRST",
// lib/ai/summary_claude.dart, lib/ai/summary_handoff.dart's "CLAUDE FIRST"; Matt, 2026-10-28: "We should be using
// Claude to generate the meeting summaries not the local processor on the Mac when the anthropic API key is set").
// That morning a 69-minute standup with Meet's captions sat "being written up on your device" for five hours while the
// Mac ran Whisper over it. Here: a meeting with its captions is summarized from them at once, by Claude with a key and
// by the device's model without one or with the switch off, in the shape the Slack post reads, and the sorting and the
// post are told; a later Whisper pass keeps the summary and its own is put aside; a Claude failure falls back to the
// device's model; a device with Claude takes a meeting still being heard, and one with only its model gives Claude a
// moment first.
//
// The queue and its stand-ins are summaries_test.dart's, the fake API and the cases summaries_claude_test.dart's: no
// request leaves the test, and the key is a test string that is no key at all.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/ai/summary_claude.dart';
import 'package:ghost_md/ai/summary_handoff.dart';
import 'package:ghost_md/ai/summary_keep.dart' show readSummary;
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/messages_api.dart' show ClaudeError, errorOf;
import 'package:ghost_md/core/library.dart' show withTranscript;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/summary_text.dart' show summarySection;
import 'package:ghost_md/format/prompt.dart' show recordingSummaryPrompt;
import 'package:ghost_md/meet/meet_note.dart' show awaitsWriteUp, withSpeakers;
import 'package:ghost_md/meet/speakers.dart' show CaptionTurn, captionWords, captionsSection;
import 'package:ghost_md/plugins/slack/meetings.dart' show meetingActions, meetingDecisions, meetingGist;

import 'summaries_claude_test.dart' as c;
import 'summaries_test.dart' as q;
import 'summary_handoff_test.dart' as h;

const turns = [
  CaptionTurn(speaker: 'Sam Lee', startMs: 4000, endMs: 15000, text: 'The release ships Friday. I have the press list.'),
  CaptionTurn(speaker: 'Matt', startMs: 15000, endMs: 26000, text: 'We decided no paid ads until the beta closes. I need to book the venue before the tenth.'),
];

/// The note a meeting Ghost was in becomes on a device that will write it up (lib/meet/meet_note.dart).
final String filed = '# Engineering standup\n\nGhost was in this meeting on 28 Oct, 09:00 to 10:09. It is being written up on your device.\n\n${captionsSection(turns)}\n';

const captioned = 'Sam Lee: The release ships Friday. I have the press list.\n\nMatt: We decided no paid ads until the beta closes. I need to book the venue before the tenth.';

/// Claude's answer in the summary prompt's shape: a heading, one sentence, points, a "Name: what", a "Decided:", a to-do.
const claudeAnswer = '# Release and launch plans\nA standup that set the release date and the launch rules.\n\n- The release ships Friday.\n- Sam Lee: the press list.\n\n- Decided: no paid ads until the beta closes.\n\n- [ ] Book the venue before the tenth.';

const phrases = [
  Segment(text: 'The release ships Friday.', startMs: 4200, endMs: 8000),
  Segment(text: 'I have the press list.', startMs: 8200, endMs: 14000),
  Segment(text: 'We decided no paid ads until the beta closes.', startMs: 15200, endMs: 20000),
  Segment(text: 'I need to book the venue before the tenth.', startMs: 20200, endMs: 25000),
];

final List<String> heard = [];

/// The queue started as the root starts it: told of each meeting's summary, as the sorting and Slack's post are.
void listen() {
  heard.clear();
  q.stop?.call();
  q.stop = q.summaries.startSummaries(() {}, q.summarized.add, meetingSummarized: (id, body) => heard.add(id));
}

/// The take filed and its write-up asked for, as lib/meet/meet_in.dart and lib/root/voice_wiring.dart do.
void file() {
  q.notes['n1'] = q.note('n1', filed, recordingMs: 4140000);
  q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
}

List<String> transcribing() => (jsonDecode(q.kept.readText('glyph-summary-transcribing') ?? '[]') as List).cast<String>();

/// Whisper's pass, as the core's write-up and the meeting step leave the note (tauri/src-tauri/src/transcript.rs
/// `with_transcript`, which keeps everything above `## Transcript`; then meet_note.dart `withSpeakers`).
void whisperLands() {
  final was = q.notes['n1']!;
  final heardOut = withTranscript(was.body, '## Transcript\n\n${phrases.map((p) => p.text).join(' ')}');
  final named = withSpeakers(heardOut, phrases)!;
  q.notes['n1'] = q.note('n1', named, revision: was.revision + 1, recordingMs: was.recordingMs, segments: phrases);
}

Future<void> advance(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

void main() {
  group('with a key', () {
    c.claudeTest('a meeting with its captions is summarized by Claude at once, not after Whisper, in the shape the post reads, and the sorting and Slack are told', (tester) async {
      listen();
      file();
      await advance(tester, 0);
      // No wait for the write-up's result: the job is the page's, and Claude is asked from the captions.
      expect(q.summaries.summaryNative('n1'), isFalse);
      expect(transcribing(), ['n1']);
      final ask = c.api.asked.single;
      expect(ask.system, recordingSummaryPrompt);
      expect(ask.prompt, captioned);
      expect(q.fakes, isEmpty, reason: 'the device’s model is not asked');
      ask.answer(claudeAnswer);
      await advance(tester, 0);
      final body = q.notes['n1']!.body;
      final section = summarySection(body, readSummary('n1')?.text)!.text;
      expect(section, startsWith('## Summary\nA standup that set the release date'));
      expect(meetingGist(section), 'A standup that set the release date and the launch rules.');
      expect(meetingDecisions(section), ['no paid ads until the beta closes.']);
      expect([for (final a in meetingActions(section, attendees: const ['Sam Lee', 'Matt'])) (a.assignee, a.text)], [('Sam Lee', 'the press list.'), (null, 'Book the venue before the tenth.')]);
      expect(readSummary('n1')?.model, 'claude-sonnet-5-5');
      expect(heard, ['n1'], reason: 'the sorting, the Slack and Discord posts and the moodboard follow this');
      expect(q.queued(), isEmpty);
      // The captions and the write-up's line stay for Whisper's pass.
      expect(body, contains('## Captions'));
      expect(awaitsWriteUp(body), isTrue);
    });

    c.claudeTest('a later Whisper pass keeps the summary: the transcript lands under it, and the summary the write-up made is put aside', (tester) async {
      listen();
      file();
      await advance(tester, 0);
      c.api.asked.single.answer(claudeAnswer);
      await advance(tester, 0);
      final section = summarySection(q.notes['n1']!.body, readSummary('n1')?.text)!.text;
      // An hour on, Whisper's transcript and the names from the captions.
      whisperLands();
      expect(q.notes['n1']!.body, contains(section));
      expect(q.notes['n1']!.body, contains('**Sam Lee (0:04):** The release ships Friday.'));
      expect(q.notes['n1']!.body, isNot(contains('## Captions')));
      // The write-up's result, with a summary of its own model's (the Mac's, sent no config by an older build).
      q.phoneStates = [const RecordingJobState(id: 'n1', title: 'Engineering standup', phase: RecordingJobPhase.done, percent: 100)];
      q.phoneResults['n1'] = const RecordingResult(summary: '# Not this\n- From the Mac’s model.', model: 'qwen3.5-2b', transcriptChars: 180, finishedAt: 1);
      await advance(tester, 15000);
      expect(q.phoneTaken, contains('n1'));
      expect(q.notes['n1']!.body, contains(section));
      expect(q.notes['n1']!.body, isNot(contains('From the Mac')));
      expect(c.api.asked, hasLength(1), reason: 'the summary is not written again');
      expect(q.fakes, isEmpty);
      expect(q.queued(), isEmpty);
      expect(transcribing(), isEmpty);
      expect(heard, ['n1']);
    });

    c.claudeTest('the phone’s write-up saying it is done, with no summary (summaries off while Claude is chosen), asks Claude nothing more', (tester) async {
      listen();
      file();
      await advance(tester, 0);
      c.api.asked.single.answer(claudeAnswer);
      await advance(tester, 0);
      whisperLands();
      q.phoneResults['n1'] = const RecordingResult(summary: null, model: 'qwen3.5-2b', transcriptChars: 180, finishedAt: 1);
      q.glyph['recordingDone']!(jsonEncode({'id': 'n1', 'outcome': 'done'}));
      await advance(tester, 0);
      await advance(tester, 1000);
      expect(q.phoneTaken, contains('n1'));
      expect(c.api.asked, hasLength(1));
      expect(q.queued(), isEmpty);
      expect(transcribing(), isEmpty);
    });

    c.claudeTest('a Discord call’s captions name who spoke and no words: its job waits for Whisper as before', (tester) async {
      const spoke = [CaptionTurn(speaker: 'Sam Lee', startMs: 0, endMs: 4000, text: ''), CaptionTurn(speaker: 'Matt', startMs: 4000, endMs: 9000, text: '')];
      q.notes['n1'] = q.note('n1', '# General in Ghost HQ\n\nGhost was in this meeting on 28 Oct, from 09:00. It is being written up on your device.\n\n${captionsSection(spoke)}\n', recordingMs: 9000);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      await advance(tester, 0);
      await advance(tester, 15000);
      expect(q.summaries.summaryNative('n1'), isTrue);
      expect(c.api.asked, isEmpty);
      expect(transcribing(), isEmpty);
    });

    c.claudeTest('a failure falls back to the device’s model at once, said on the strip and logged, and the summary lands', (tester) async {
      listen();
      file();
      await advance(tester, 0);
      c.api.asked.single.fail(errorOfStatus(401));
      await advance(tester, 0);
      expect(q.fakes, hasLength(1), reason: 'written on this device instead');
      expect(q.fakes.single.prompt, captioned);
      expect(q.summaries.summariesNow().fellBack, {'n1': 'The API key was refused. Check it in Settings › Claude.'});
      expect(q.summaries.summariesNow().failed, isEmpty);
      expect(q.warned.single, startsWith('[glyph] Claude did not write the summary, so this device will: '));
      expect(q.queued().single['local'], isTrue);
      q.fakes.single.finish(claudeAnswer);
      await advance(tester, 0);
      expect(readSummary('n1')?.model, 'qwen3.5-4b');
      expect(q.notes['n1']!.body, contains('## Summary'));
      expect(heard, ['n1']);
      expect(q.summaries.summariesNow().fellBack, isEmpty);
    });

    c.claudeTest('no connection falls back too; Try again on a failed fallback asks Claude afresh', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      c.api.asked.single.fail(const ClaudeError('Claude could not be reached. Check the connection.'));
      await advance(tester, 0);
      expect(q.summaries.summariesNow().fellBack['n1'], 'Claude could not be reached. Check the connection.');
      for (var i = 0; i < 3; i += 1) {
        q.fakes.last.fail('the model broke');
        await advance(tester, 20000);
      }
      expect(q.summaries.summariesNow().failed, {'n1'});
      q.summaries.retrySummary('n1');
      await advance(tester, 0);
      expect(c.api.asked, hasLength(2));
      expect(q.queued().single.containsKey('local'), isFalse);
    });
  });

  group('without Claude', () {
    c.claudeTest('with no key, the device’s model writes a meeting from its captions at once', (tester) async {
      listen();
      file();
      await advance(tester, 0);
      expect(c.api.asked, isEmpty);
      expect(q.fakes.single.prompt, captioned);
      q.fakes.single.finish(claudeAnswer);
      await advance(tester, 0);
      expect(readSummary('n1')?.model, 'qwen3.5-4b');
      expect(heard, ['n1']);
    }, key: false);

    c.claudeTest('with Write meeting summaries with Claude off, the device’s model writes it, and nothing goes to Anthropic', (tester) async {
      await c.settings.setMeetings(false);
      listen();
      file();
      await advance(tester, 0);
      expect(c.api.asked, isEmpty);
      expect(q.fakes, hasLength(1));
      expect(q.fakes.single.model, 'qwen3.5-4b');
    });
  });

  group('the setting', () {
    test('is on by default, follows what is kept, and turns Claude off for meetings alone', () async {
      final store = MemorySecureStore();
      final settings = ClaudeSettings(store);
      await settings.load();
      expect(settings.meetings, isTrue);
      await settings.setKey('sk-ant-test');
      final claude = MeetingClaude(settings: settings, switchedOn: () => true, localOnly: () => false);
      expect(claude.chosen, isTrue);
      await settings.setMeetings(false);
      expect(claude.chosen, isFalse);
      expect(await store.read(claudeMeetingsName), 'off');
      final again = ClaudeSettings(store);
      await again.load();
      expect(again.meetings, isFalse);
    });

    test('the standup’s 362,000 characters fit Claude’s one pass, and its captions read with who said what', () {
      expect(claudeOnePassChars, greaterThan(362000));
      expect(captionWords(filed), captioned);
    });
  });

  group('which device writes it', () {
    c.claudeTest('a device with Claude takes a meeting still being heard elsewhere, from its captions, once quiet a while', (tester) async {
      h.now = 10 * 3600000;
      listen();
      q.notes['n2'] = Note(id: 'n2', body: filed, createdAt: 0, updatedAt: h.now - captionsQuietMs - 1, revision: 1);
      q.prefs = h.meeting(q.prefs, 'n2', at: h.now - 3600000);
      final handoff = q.summaries.handoff = h.handoffFor(h.phone);
      await handoff.look();
      expect(handoffsOf(q.prefs)['n2']?.from, '');
      await advance(tester, 0);
      expect(handoffsOf(q.prefs)['n2']?.claimBy, 'fold-1');
      expect(c.api.asked.single.prompt, captioned);
      c.api.asked.single.answer(claudeAnswer);
      await advance(tester, 0);
      expect(q.notes['n2']!.body, contains('## Summary'));
      expect(handoffsOf(q.prefs)['n2']?.done, h.now);
      expect(heard, ['n2']);
      q.summaries.handoff = null;
    });

    c.claudeTest('a device with only its own model leaves a meeting still being heard alone', (tester) async {
      h.now = 10 * 3600000;
      switchedOff();
      q.notes['n2'] = Note(id: 'n2', body: filed, createdAt: 0, updatedAt: h.now - captionsQuietMs - 1, revision: 1);
      q.prefs = h.meeting(q.prefs, 'n2', at: h.now - 3600000);
      final handoff = q.summaries.handoff = h.handoffFor(h.phone);
      await handoff.look();
      await advance(tester, 0);
      expect(handoffsOf(q.prefs), isEmpty);
      expect(q.summaries.summaryPending('n2'), isFalse);
      q.summaries.handoff = null;
    });

    c.claudeTest('a device with Claude claims a meeting just marked waiting at once', (tester) async {
      h.now = 10 * 3600000;
      q.prefs = h.meeting(q.prefs, 'n1');
      h.theirs('n1', Handoff(from: 'mac-1', fromName: 'Mac', at: h.now));
      final handoff = q.summaries.handoff = h.handoffFor(h.phone);
      await handoff.look();
      await advance(tester, 0);
      expect(handoffsOf(q.prefs)['n1']?.claimBy, 'fold-1');
      expect(c.api.asked, hasLength(1));
      q.summaries.handoff = null;
    });

    c.claudeTest('a device with only its own model gives a device with Claude a while to claim it first, then takes it', (tester) async {
      h.now = 10 * 3600000;
      switchedOff();
      q.prefs = h.meeting(q.prefs, 'n1');
      h.theirs('n1', Handoff(from: 'mac-1', fromName: 'Mac', at: h.now));
      final handoff = q.summaries.handoff = h.handoffFor(h.phone);
      await handoff.look();
      await advance(tester, 0);
      expect(q.summaries.summaryPending('n1'), isFalse);
      expect(handoffsOf(q.prefs)['n1']?.claimBy, isNull);
      // Nobody with Claude took it: the device looks again once the while is up, and writes it with its model.
      h.now += modelDeferMs;
      await advance(tester, modelDeferMs + 1000);
      await advance(tester, 0);
      expect(handoffsOf(q.prefs)['n1']?.claimBy, 'fold-1');
      expect(q.fakes, hasLength(1));
      q.summaries.handoff = null;
    });
  });
}

/// The Claude plugin switched off on this device: it writes meetings with its own model alone.
void switchedOff() {
  c.switchedOn = false;
  c.changes.tell();
}

/// A refused key as the API answers it.
ClaudeError errorOfStatus(int status) => errorOf(status, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');
