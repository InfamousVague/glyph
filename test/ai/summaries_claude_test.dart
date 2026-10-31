// A meeting's write-up through the app's own Claude (lib/ai/summary_claude.dart, lib/ai/summaries.dart's "CLAUDE, FOR
// MEETINGS"; Matt, 2026-10-19: "when claude is enabled the meeting summary should go through claude instead of
// gemma"). Which way a job goes (Claude chosen and enabled, the plugin off, no key, Local only, a voice note), what
// the request carries, the section landing as the phone's model's does in a closed note and an open one, a failure
// keeping the job in Claude's words, and a native meeting made a page job for Claude once its transcript is in.
//
// The queue and its stand-ins are summaries_test.dart's, made with this file's Claude; the API is a fake whose
// answers the test streams when it says so (the `FakeClaudeApi extends ClaudeApi` of test/claude), the settings a memory
// store with a test key that is no key at all.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/ai/backend.dart' show JobConfig, ModelInfo;
import 'package:ghost_md/ai/job_config.dart' show jobConfigFor;
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/ai/summary_claude.dart';
import 'package:ghost_md/ai/summary_keep.dart' show readSummary, summaryFactsOf, withoutSummaryFacts;
import 'package:ghost_md/claude/claude_settings.dart' show ClaudeSettings;
import 'package:ghost_md/claude/claude_spend.dart' show ClaudeUsage;
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart' show SseEvent;
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/meet/speakers.dart' show CaptionTurn, captionsSection;
import 'package:ghost_md/ai/summary_text.dart' show onePassChars, pieceChars;
import 'package:ghost_md/format/prompt.dart' show recordingNotesPrompt, recordingSummaryPrompt;

import 'summaries_test.dart' as q;

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// One request asked of the fake API: its body, its betas, and the events the test sends it.
class ClaudeAsk {
  ClaudeAsk(this.body, this.betas);

  final Map<String, Object?> body;
  final List<String> betas;
  final StreamController<SseEvent> events = StreamController<SseEvent>();
  bool cancelled = false;

  String get system => body['system']! as String;
  String get prompt => ((body['messages']! as List).single as Map)['content']! as String;

  /// The answer streamed as the API streams one: a thinking block, then the words in two deltas.
  void answer(String text, {String stop = 'end_turn'}) {
    final half = text.length ~/ 2;
    for (final event in [
      _e('message_start', {'type': 'message_start', 'message': {'model': body['model']}}),
      _e('content_block_start', {'index': 0, 'content_block': {'type': 'thinking', 'thinking': ''}}),
      _e('content_block_stop', {'index': 0}),
      _e('content_block_start', {'index': 1, 'content_block': {'type': 'text', 'text': ''}}),
      _e('content_block_delta', {'index': 1, 'delta': {'type': 'text_delta', 'text': text.substring(0, half)}}),
      _e('content_block_delta', {'index': 1, 'delta': {'type': 'text_delta', 'text': text.substring(half)}}),
      _e('content_block_stop', {'index': 1}),
      _e('message_delta', {'delta': {'stop_reason': stop}}),
      _e('message_stop', {}),
    ]) {
      events.add(event);
    }
    unawaited(events.close());
  }

  /// The request failed as [ClaudeApi.streamWith] says a failure.
  void fail(ClaudeError error) {
    events.addError(error);
    unawaited(events.close());
  }
}

class FakeClaudeApi extends ClaudeApi {
  FakeClaudeApi() : super(key: 'sk-ant-test');

  final List<ClaudeAsk> asked = [];

  @override
  ClaudeCall streamWith(Map<String, Object?> body, {List<String> betas = const []}) {
    final ask = ClaudeAsk(jsonDecode(jsonEncode(body)) as Map<String, Object?>, betas);
    asked.add(ask);
    return ClaudeCall(ask.events.stream, () {
      ask.cancelled = true;
      if (ask.events.isClosed) return;
      ask.events.addError(const ClaudeCancelled());
      unawaited(ask.events.close());
    });
  }
}

class Heard extends ChangeNotifier {
  void tell() => notifyListeners();
}

late FakeClaudeApi api;
late ClaudeSettings settings;
late Heard changes;
bool switchedOn = true;
bool localOnly = false;

const transcript = 'That is the March launch settled. Sam owns the press list.';
const body = '# March launch\n\n${q.section}\n\n$transcript';

/// A case with the queue made with this file's Claude: switched on, a key kept, Local only off unless it says.
void claudeTest(String name, Future<void> Function(WidgetTester tester) run, {bool key = true, int onePassChars = claudeOnePassChars, int pieceChars = claudePieceChars}) {
  testWidgets(name, (tester) async {
    api = FakeClaudeApi();
    settings = ClaudeSettings(MemorySecureStore());
    if (key) await settings.setKey('sk-ant-test');
    changes = Heard();
    switchedOn = true;
    localOnly = false;
    q.claudeSeam = MeetingClaude(settings: settings, switchedOn: () => switchedOn, localOnly: () => localOnly, api: (_) => api, changes: changes, onePassChars: onePassChars, pieceChars: pieceChars);
    q.begin();
    try {
      await run(tester);
    } finally {
      for (final ask in api.asked) {
        if (!ask.events.isClosed) ask.fail(const ClaudeError('over'));
      }
      await q.end(tester);
      q.claudeSeam = null;
    }
  });
}

Future<void> advance(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

void main() {
  group('which way a write-up goes', () {
    claudeTest('a meeting goes to Claude when it is enabled, and the phone’s model is not asked', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(q.fakes, isEmpty);
      expect(api.asked, hasLength(1));
      expect(q.summaries.summariesNow().needsModel, isEmpty);
      // No model on the phone is no matter: none is looked for.
      q.present = [];
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
    });

    claudeTest('a meeting goes to the phone’s model with the Claude plugin switched off', (tester) async {
      switchedOn = false;
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.fakes, hasLength(1));
      expect(q.fakes.single.model, 'qwen3.5-4b');
    });

    claudeTest('a meeting goes to the phone’s model with no key on this device', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.fakes, hasLength(1));
    }, key: false);

    claudeTest('a voice note stays the phone’s model’s, Claude enabled or not', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.recording);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.fakes, hasLength(1));
    });

    claudeTest('with Local only on, a meeting waits for Claude (not the phone’s model, not "Needs a model"), and is asked once it is off', (tester) async {
      localOnly = true;
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.fakes, isEmpty);
      final held = q.summaries.summariesNow();
      expect(held.claudeHeld, {'n1'});
      expect(held.needsModel, isEmpty);
      expect(held.pending, {'n1'});
      localOnly = false;
      changes.tell();
      await advance(tester, 500);
      expect(api.asked, hasLength(1));
      expect(q.summaries.summariesNow().claudeHeld, isEmpty);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
    });

    claudeTest('Local only turned on while Claude writes stops the request, and the job waits, uncounted', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      localOnly = true;
      changes.tell();
      await advance(tester, 0);
      expect(api.asked.single.cancelled, isTrue);
      expect(q.queued().single['tries'], 0);
      expect(q.queued().single['failed'], isNull);
      await advance(tester, 20000);
      expect(q.summaries.summariesNow().claudeHeld, {'n1'});
      expect(q.fakes, isEmpty);
    });

    // Matt, 2026-10-20: "Also enable setting spending limits in claude settings in the app" (lib/claude/claude_spend.dart).
    claudeTest('at the month’s spending limit a meeting waits for Claude, saying so, uncounted, and is asked once the limit is raised', (tester) async {
      settings.spend.now = () => DateTime(2026, 10, 20);
      await tester.runAsync(() async {
        await settings.spend.setOn(true);
        await settings.spend.setLimit(5);
      });
      // $5 of Opus 5.5's output already this month.
      settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 250000));
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.fakes, isEmpty);
      final held = q.summaries.summariesNow();
      expect(held.claudeHeld, {'n1'});
      expect(held.reasons, {'n1': 'Monthly spending limit reached (\$5). Change it in Settings › Claude.'});
      expect(held.failed, isEmpty);
      // Looked at again and again, it is never counted as a try.
      await advance(tester, 200000);
      expect(api.asked, isEmpty);
      expect(q.queued().single['tries'], 0);
      expect(q.queued().single['failed'], isNull);
      await tester.runAsync(() => settings.spend.setLimit(25));
      changes.tell();
      await advance(tester, 500);
      expect(api.asked, hasLength(1));
      expect(q.summaries.summariesNow().claudeHeld, isEmpty);
      expect(q.summaries.summariesNow().reasons, isEmpty);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
    });

    claudeTest('the limit reached while Claude writes a meeting up lets that request finish, and the write-up lands', (tester) async {
      settings.spend.now = () => DateTime(2026, 10, 20);
      await tester.runAsync(() async {
        await settings.spend.setOn(true);
        await settings.spend.setLimit(5);
      });
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      settings.spend.record('claude-opus-5-5', ClaudeUsage(output: 250000));
      changes.tell();
      await advance(tester, 0);
      expect(api.asked.single.cancelled, isFalse);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      // The next waits.
      q.notes['n2'] = q.note('n2', '# Second meeting\n\n$transcript', recordingMs: 4000, segments: q.phrases);
      q.summaries.enqueueSummary('n2', SummaryKind.meeting);
      await advance(tester, 1000);
      expect(api.asked, hasLength(1));
      expect(q.summaries.summariesNow().claudeHeld, {'n2'});
    });

    claudeTest('a meeting is written up by Claude with the app off the screen; a voice note waits for it to come back', (tester) async {
      q.visible(false);
      q.summaries.enqueueSummary('n2', SummaryKind.recording);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      expect(q.fakes, isEmpty);
    });
  });

  group('the request', () {
    claudeTest('carries the tape’s words and the summary prompt, with the model chosen, room to think, and the fallback', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final ask = api.asked.single;
      expect(ask.system, recordingSummaryPrompt);
      expect(ask.prompt, transcript);
      expect(ask.body['model'], 'claude-sonnet-5-5');
      expect(ask.body['max_tokens'], claudeSummaryMaxTokens);
      expect(ask.body['fallbacks'], 'default');
      expect(ask.betas, [claudeFallbackBeta]);
      // No effort chosen: the model's own, so none is sent; and no thinking asked for, the model's adaptive own.
      expect(ask.body.containsKey('output_config'), isFalse);
      expect(ask.body.containsKey('thinking'), isFalse);
    });

    claudeTest('a meeting\'s words go with who said them, from the captions the note keeps', (tester) async {
      const turns = [
        CaptionTurn(speaker: 'Sam Lee', startMs: 0, endMs: 4000, text: 'That is the March launch settled.'),
        CaptionTurn(speaker: 'Ana Ruiz', startMs: 4000, endMs: 9000, text: 'Sam owns the press list.'),
      ];
      final segments = [
        const Segment(startMs: 0, endMs: 3800, text: 'That is the March launch settled.'),
        const Segment(startMs: 4200, endMs: 8800, text: 'Sam owns the press list.'),
      ];
      q.notes['n1'] = q.note('n1', '# March launch\n\n${captionsSection(turns)}', recordingMs: 9000, segments: segments);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final ask = api.asked.single;
      expect(ask.prompt, 'Sam Lee: That is the March launch settled.\n\nAna Ruiz: Sam owns the press list.');
      expect(ask.system, contains('A turn that begins with a name and a colon'));
    });

    claudeTest('a meeting with only its written-up transcript here reads the names from it, times left out', (tester) async {
      q.notes['n1'] = q.note('n1', '# March launch\n\n## Transcript\n\n**Sam Lee (0:00):** That is the March launch settled.\n\n**Ana Ruiz (0:04):** Sam owns the press list.', recordingMs: 9000);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked.single.prompt, contains('Sam Lee: That is the March launch settled.'));
      expect(api.asked.single.prompt, contains('Ana Ruiz: Sam owns the press list.'));
      expect(api.asked.single.prompt, isNot(contains('**')));
    });

    claudeTest('sends the effort chosen, and no fallback for Haiku, which has none', (tester) async {
      await settings.setModel('claude-haiku-5-5');
      await settings.setEffort('low');
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final ask = api.asked.single;
      expect(ask.body['model'], 'claude-haiku-5-5');
      expect(ask.body['output_config'], {'effort': 'low'});
      expect(ask.body.containsKey('fallbacks'), isFalse);
      expect(ask.betas, isEmpty);
    });

    claudeTest('a long meeting that fits goes to Claude whole, in one request, where the device’s model would read it in pieces', (tester) async {
      final tape = q.longTape();
      q.notes['n1'] = q.note('n1', '# Long', recordingMs: 600000, segments: tape);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final ask = api.asked.single;
      expect(ask.system, recordingSummaryPrompt);
      expect(ask.prompt.length, greaterThan(onePassChars), reason: 'past the device model’s one pass, inside Claude’s');
      expect(ask.prompt, contains(tape.last.text));
      ask.answer(q.answer);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      expect(q.notes['n1']?.body, contains('## Summary'));
    });

    // The 69-minute standup of 2026-10-28 was 362,000 characters; one past Claude's limit goes in its pieces.
    claudeTest('a meeting past Claude’s one pass is chunked: each piece’s notes checkpointed, then the summary of the notes', (tester) async {
      q.notes['n1'] = q.note('n1', '# Long', recordingMs: 600000, segments: q.longTape());
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked.single.system, recordingNotesPrompt);
      api.asked[0].answer('notes one');
      await advance(tester, 0);
      expect(q.queued().single['pieces'], ['notes one']);
      expect(api.asked[1].system, recordingNotesPrompt);
      api.asked[1].answer('notes two');
      await advance(tester, 0);
      expect(api.asked, hasLength(3));
      expect(api.asked[2].system, recordingSummaryPrompt);
      expect(api.asked[2].prompt, endsWith('notes one\n\nnotes two'));
      expect(q.fakes, isEmpty);
    }, onePassChars: onePassChars, pieceChars: pieceChars);
  });

  group('on the app\'s record of running work (docs/ACTIVITY.md)', () {
    late Activity record;
    late List<Job> ended;
    late StreamSubscription<JobEvent> hearing;
    void listen() {
      final kept = MemoryStored();
      useActivity(record = Activity(store: () => kept));
      ended = [];
      hearing = record.events.where((e) => e.kind == JobEventKind.ended).listen((e) => ended.add(e.job!));
      // Let go once the queue has been stopped (the case's own end), not before.
      addTearDown(() async {
        await hearing.cancel();
        useActivity(Activity());
      });
    }

    claudeTest('a summary is one job: "Summary of March launch", writing with Claude, then "Summarized “March launch”" with Open', (tester) async {
      listen();
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final job = record['summary:n1']!;
      expect((job.kind, job.title, job.liveLine, job.here), (JobKind.ai, 'Summary of March launch', 'Writing the summary with Claude', true));
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(record.value, isEmpty);
      expect(ended.single.result!.words, 'Summarized “March launch”');
      expect(ended.single.result!.action, 'Open');
      expect(record.log.today.words, '1 summary');
    });

    claudeTest('the summary\'s words stream onto the record as Claude writes them, for the note to draw; none once it lands', (tester) async {
      listen();
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      final heard = <String>[];
      final words = record.wordsOf('summary:n1');
      void hear() => heard.add(words.value);
      words.addListener(hear);
      addTearDown(() => words.removeListener(hear));
      final answer = q.answer;
      api.asked.single.answer(answer);
      await advance(tester, 0);
      expect(heard.take(2), [answer.substring(0, answer.length ~/ 2), answer], reason: 'the words so far, piece by piece');
      expect(words.value, '', reason: 'nothing once the write has landed');
    });

    claudeTest('a long meeting says its parts: "Reading the meeting, 1 of 2 parts", then writing from them', (tester) async {
      listen();
      q.notes['n1'] = q.note('n1', '# Long', recordingMs: 600000, segments: q.longTape());
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(record['summary:n1']!.liveLine, 'Reading the meeting, 1 of 2 parts');
      expect(record['summary:n1']!.fraction, 0);
      api.asked[0].answer('notes one');
      await advance(tester, 0);
      expect(record['summary:n1']!.liveLine, 'Reading the meeting, 2 of 2 parts');
      api.asked[1].answer('notes two');
      await advance(tester, 0);
      expect(record['summary:n1']!.liveLine, 'Writing the summary, from 2 parts');
      expect(record['summary:n1']!.fraction, closeTo(2 / 3, 1e-9));
    }, onePassChars: onePassChars, pieceChars: pieceChars);

    claudeTest('a try that fails goes quietly; the third is red in the tray, with Retry', (tester) async {
      listen();
      q.present = [];
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked.single.fail(errorOf(401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'));
      await advance(tester, 0);
      final failed = record['summary:n1']!;
      expect(failed.state, JobState.failed);
      expect(failed.cause, 'The API key was refused. Check it in Settings › Claude.');
      expect(failed.fix!.label, 'Retry');
      failed.fix!.onPress();
      await advance(tester, 0);
      expect(api.asked, hasLength(2));
      expect(record['summary:n1']!.state, JobState.running);
    });
  });

  group('in the background', () {
    test('the device is held while Claude is asked, and let go quietly once the last answer is read', () async {
      final jobs = _Jobs();
      final store = ClaudeSettings(MemorySecureStore());
      await store.setKey('sk-ant-test');
      final fake = FakeClaudeApi();
      final claude = MeetingClaude(settings: store, switchedOn: () => true, localOnly: () => false, api: (_) => fake, background: jobs);
      final one = claude.write(system: 's', prompt: 'p1');
      final two = claude.write(system: 's', prompt: 'p2');
      expect(jobs.heard, ['running $claudeWriteUpJobId']);
      fake.asked[0].answer('First.');
      await one.done;
      expect(jobs.heard, ['running $claudeWriteUpJobId'], reason: 'one still being asked');
      fake.asked[1].answer('Second.');
      await two.done;
      expect(jobs.heard, ['running $claudeWriteUpJobId', 'ended $claudeWriteUpJobId quiet']);
    });
  });

  group('the section', () {
    claudeTest('lands in a closed note as the phone model’s does, kept as Claude’s', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      final written = readSummary('n1');
      expect((written?.text, written?.model, written?.forMs), (q.section, 'claude-sonnet-5-5', 4000));
      expect(q.queued(), isEmpty);
      expect(q.summarized, contains((id: 'n1', title: 'March launch')));
    });

    claudeTest('is handed whole to an open note’s editor, which lands it, and nothing is written plain', (tester) async {
      final asks = <SummaryAsk>[];
      q.summaries.openForSummaries('n1', (ask) {
        asks.add(ask);
        return const SummaryLanded(q.section);
      });
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      // Claude is asked by the queue, not the editor's run.
      expect(asks, isEmpty);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(asks.map(q.asked), [(words: transcript, context: null, model: 'claude-sonnet-5-5', replace: false, text: q.answer)]);
      expect(q.updates(), isEmpty);
      expect(readSummary('n1')?.text, q.section);
      expect(q.queued(), isEmpty);
    });
  });

  group('a failure', () {
    claudeTest('with no model on the device, of the connection, or Claude overloaded, keeps the job and counts a try; the third fails it with Claude’s words', (tester) async {
      q.present = [];
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked[0].fail(const ClaudeError('Claude could not be reached. Check the connection.'));
      await advance(tester, 0);
      expect(q.queued().single['tries'], 1);
      expect(q.queued().single['failed'], isNull);
      await advance(tester, 20000);
      api.asked[1].fail(errorOf(529, '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'));
      await advance(tester, 0);
      await advance(tester, 20000);
      api.asked[2].fail(errorOf(429, '{"type":"error","error":{"type":"rate_limit_error","message":"Rate limited"}}'));
      await advance(tester, 0);
      final now = q.summaries.summariesNow();
      expect(now.failed, {'n1'});
      expect(now.reasons['n1'], 'Too many requests for this key just now. Try again in a moment.');
      expect(q.queued().single['failed'], isTrue);
      // Try again: the job back, the reason gone, Claude asked afresh.
      q.summaries.retrySummary('n1');
      expect(q.summaries.summariesNow().reasons, isEmpty);
      await advance(tester, 0);
      expect(api.asked, hasLength(4));
    });

    claudeTest('of the key, with no model on the device, fails the job at once, for Try again', (tester) async {
      q.present = [];
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked.single.fail(errorOf(401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'));
      await advance(tester, 0);
      final now = q.summaries.summariesNow();
      expect(now.failed, {'n1'});
      expect(now.reasons['n1'], 'The API key was refused. Check it in Settings › Claude.');
      await advance(tester, 60000);
      expect(api.asked, hasLength(1));
      expect(q.notes['n1']?.body, isNot(contains('## Summary')));
    });

    claudeTest('a decline, or an answer cut off or empty, is no section: with no model here, declined fails at once, the others count a try', (tester) async {
      q.present = [];
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked[0].answer(q.answer, stop: 'max_tokens');
      await advance(tester, 0);
      expect(q.queued().single['tries'], 1);
      expect(q.notes['n1']?.body, isNot(contains('## Summary')));
      await advance(tester, 20000);
      api.asked[1].answer('Partial words', stop: 'refusal');
      await advance(tester, 0);
      expect(q.summaries.summariesNow().reasons['n1'], 'Claude declined to write this one up.');
      expect(q.queued().single['failed'], isTrue);
      expect(q.notes['n1']?.body, isNot(contains('Partial')));
    });
  });

  group('a meeting the phone writes up', () {
    claudeTest('becomes the page’s job once its transcript is in, and Claude writes it up: the phone wrote no summary', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.summaries.summaryNative('n1'), isTrue);
      q.phoneResults['n1'] = const RecordingResult(summary: null, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      q.glyph['recordingDone']!(jsonEncode({'id': 'n1', 'outcome': 'done'}));
      await advance(tester, 0);
      expect(q.summaries.summaryNative('n1'), isFalse);
      expect(q.fakes, isEmpty);
      expect(api.asked, hasLength(1));
      expect(api.asked.single.prompt, transcript);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      expect(readSummary('n1')?.model, 'claude-sonnet-5-5');
      // The facts in the note's own front matter say the same (summary_keep.dart `withSummaryFacts`).
      expect(summaryFactsOf(q.notes['n1']!.body)?.model, 'claude-sonnet-5-5');
      expect(summaryFactsOf(q.notes['n1']!.body)?.text, readSummary('n1')?.text);
      expect(q.queued(), isEmpty);
    });

    // Matt's Mac, 2026-10-26: its write-up stopped at "needs a model" with the transcript in the note, and turning on
    // Claude there must write it, as the waiting line says.
    claudeTest('stopped for a model with its transcript in, becomes the page’s job once Claude is chosen, and Claude writes it up', (tester) async {
      switchedOn = false;
      q.present = [];
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneStates = [RecordingJobState.fromJson({'id': 'n1', 'title': 'Standup', 'phase': 'needsModel', 'percent': 100, 'updatedAt': 1})];
      await advance(tester, 15000);
      expect(q.summaries.summariesNow().needsModel, {'n1'});
      expect(api.asked, isEmpty);
      switchedOn = true;
      changes.tell();
      await advance(tester, 15000);
      expect(q.summaries.summaryNative('n1'), isFalse);
      expect(api.asked, hasLength(1));
      expect(api.asked.single.prompt, transcript);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      expect(q.queued(), isEmpty);
      expect(q.summaries.summariesNow().needsModel, isEmpty);
    });

    claudeTest('puts aside a summary the phone wrote anyway, for Claude’s', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: '# Not this\n- From the phone.', model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
    });

    claudeTest('with Claude not chosen, lands the phone’s summary as before', (tester) async {
      switchedOn = false;
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: q.answer, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(withoutSummaryFacts(q.notes['n1']?.body ?? ''), body);
      expect(readSummary('n1')?.model, 'qwen3.5-2b');
    });

    claudeTest('with Summaries off, or nothing heard, ends as before', (tester) async {
      q.prefs = Preferences.defaults.copyWith(summaries: 'off');
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: null, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await advance(tester, 0);
      expect(q.queued(), isEmpty);
      q.prefs = Preferences.defaults;
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: null, model: 'qwen3.5-2b', transcriptChars: 0, finishedAt: 1);
      await advance(tester, 500);
      expect(q.queued(), isEmpty);
      expect(api.asked, isEmpty);
    });
  });

  group('the phone’s config', () {
    test('says summaries off where meetings are Claude’s, and the preference otherwise', () {
      final prefs = Preferences.defaults.copyWith(summaries: 'meetings');
      final models = [const ModelInfo(id: 'qwen3.5-4b', file: '', bytes: 0, present: true, path: '')];
      JobConfig config(bool claude) => jobConfigFor(models, prefs, claude: claude);
      expect(config(false).summaries, 'meetings');
      expect(config(true).summaries, 'off');
      expect(config(true).model, config(false).model);
    });
  });
}

class _Jobs implements BackgroundJobs {
  final List<String> heard = [];

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async => heard.add('running $id');

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async => heard.add('ended $id${quiet ? ' quiet' : ''}');

  @override
  void onStop(void Function(String id)? stop) {}
}
