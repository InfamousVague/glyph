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
import 'package:ghost_md/ai/summary_keep.dart' show readSummary;
import 'package:ghost_md/claude/claude_settings.dart' show ClaudeSettings;
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart' show SseEvent;
import 'package:ghost_md/core/preferences.dart' show Preferences;
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
void claudeTest(String name, Future<void> Function(WidgetTester tester) run, {bool key = true}) {
  testWidgets(name, (tester) async {
    api = FakeClaudeApi();
    settings = ClaudeSettings(MemorySecureStore());
    if (key) await settings.setKey('sk-ant-test');
    changes = Heard();
    switchedOn = true;
    localOnly = false;
    q.claudeSeam = MeetingClaude(settings: settings, switchedOn: () => switchedOn, localOnly: () => localOnly, api: (_) => api, changes: changes);
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
      expect(q.notes['n1']?.body, body);
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
      expect(q.notes['n1']?.body, body);
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

    claudeTest('a meeting is written up by Claude with the app off the screen; a voice note waits for it to come back', (tester) async {
      q.visible(false);
      q.summaries.enqueueSummary('n2', SummaryKind.recording);
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(q.notes['n1']?.body, body);
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

    claudeTest('a long meeting goes in the same pieces, each piece’s notes checkpointed, then the summary of the notes', (tester) async {
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
    });
  });

  group('the section', () {
    claudeTest('lands in a closed note as the phone model’s does, kept as Claude’s', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting);
      await advance(tester, 0);
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(q.notes['n1']?.body, body);
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
    claudeTest('of the connection, or Claude overloaded, keeps the job and counts a try; the third fails it with Claude’s words', (tester) async {
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

    claudeTest('of the key fails the job at once, for Try again', (tester) async {
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

    claudeTest('a decline, or an answer cut off or empty, is no section: declined fails at once, the others count a try', (tester) async {
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
      expect(q.notes['n1']?.body, body);
      expect(readSummary('n1')?.model, 'claude-sonnet-5-5');
      expect(q.queued(), isEmpty);
    });

    claudeTest('puts aside a summary the phone wrote anyway, for Claude’s', (tester) async {
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: '# Not this\n- From the phone.', model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await advance(tester, 0);
      expect(api.asked, hasLength(1));
      api.asked.single.answer(q.answer);
      await advance(tester, 0);
      expect(q.notes['n1']?.body, body);
    });

    claudeTest('with Claude not chosen, lands the phone’s summary as before', (tester) async {
      switchedOn = false;
      q.summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      q.phoneResults['n1'] = const RecordingResult(summary: q.answer, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await advance(tester, 0);
      expect(api.asked, isEmpty);
      expect(q.notes['n1']?.body, body);
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
