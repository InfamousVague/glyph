// The app's own Claude's spending limit (lib/claude/claude_spend.dart; Matt, 2026-10-20: "Also enable setting
// spending limits in claude settings in the app"): what a request costs on each model from the usage Claude reports,
// cache tokens and Haiku's long-prompt card included; the month's count kept across requests and app restarts and
// started again on the 1st; the 80% notice once a month; and a stream's usage counted once it ends.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_settings.dart' show ClaudeSettings, claudeModels;
import 'package:ghost_md/claude/claude_spend.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

ClaudeUsage _usage({int input = 0, int output = 0, int write5m = 0, int write1h = 0, int read = 0}) => ClaudeUsage(input: input, output: output, cacheWrite5m: write5m, cacheWrite1h: write1h, cacheRead: read);

void main() {
  group('what a request costs', () {
    test('every model the app offers has its own prices', () {
      for (final model in claudeModels) {
        expect(claudePrices.containsKey(model.id), isTrue, reason: model.id);
      }
    });

    test('input and output at each model\'s price per million tokens', () {
      final usage = _usage(input: 1000000, output: 1000000);
      expect(claudeCost('claude-sonnet-5-5', usage), closeTo(2 + 10, 1e-9));
      expect(claudeCost('claude-opus-5-5', usage), closeTo(4 + 20, 1e-9));
      expect(claudeCost('claude-haiku-5-5', _usage(input: 50000, output: 20000)), closeTo(0.05 * 0.10 + 0.02 * 0.50, 1e-12));
    });

    test('cache writes at 1.25 and 2 times input, reads at the model\'s own rate', () {
      // Sonnet 5.5: input $2, so a 5-minute write $2.50 and a 1-hour one $4; a read $0.20.
      expect(claudeCost('claude-sonnet-5-5', _usage(write5m: 1000000)), closeTo(2.5, 1e-9));
      expect(claudeCost('claude-sonnet-5-5', _usage(write1h: 1000000)), closeTo(4, 1e-9));
      expect(claudeCost('claude-sonnet-5-5', _usage(read: 1000000)), closeTo(0.2, 1e-9));
      // Opus 5.5 reads at $0.20 (0.05 times its $4), not a tenth.
      expect(claudeCost('claude-opus-5-5', _usage(read: 1000000)), closeTo(0.2, 1e-9));
      final mixed = _usage(input: 2000, output: 500, write5m: 10000, read: 40000);
      expect(claudeCost('claude-opus-5-5', mixed), closeTo((2000 * 4 + 500 * 20 + 10000 * 5 + 40000 * 0.2) / 1e6, 1e-12));
    });

    test('Haiku 5.5 over 100K tokens of prompt, cache included, is billed on its second card', () {
      final short = _usage(input: 60000, read: 40000, output: 1000);
      final long = _usage(input: 60000, read: 40001, output: 1000);
      expect(claudeCost('claude-haiku-5-5', short), closeTo((60000 * 0.10 + 40000 * 0.01 + 1000 * 0.50) / 1e6, 1e-12));
      expect(claudeCost('claude-haiku-5-5', long), closeTo((60000 * 0.50 + 40001 * 0.05 + 1000 * 2.50) / 1e6, 1e-12));
    });

    test('a dated id is priced as its model; one the table does not know at the dearest prices', () {
      final usage = _usage(input: 1000000, output: 1000000, read: 1000000);
      expect(claudeCost('claude-haiku-4-5-20251001', usage), claudeCost('claude-haiku-4-5', usage));
      expect(claudeCost('claude-opus-5-5-fast', usage), claudeCost('claude-opus-5-5', usage));
      final unknown = claudeCost('claude-something-9', usage);
      for (final model in claudePrices.keys) {
        expect(unknown, greaterThanOrEqualTo(claudeCost(model, usage)), reason: model);
      }
      expect(unknown, closeTo(10 + 50 + 1, 1e-9));
    });

    test('usage is read from the stream\'s two reports, each count kept at its most', () {
      final usage = ClaudeUsage()
        ..take({'input_tokens': 1200, 'cache_creation_input_tokens': 300, 'cache_read_input_tokens': 5000, 'output_tokens': 1})
        ..take({'output_tokens': 870});
      expect((usage.input, usage.output, usage.cacheWrite5m, usage.cacheWrite1h, usage.cacheRead), (1200, 870, 300, 0, 5000));
      final split = ClaudeUsage()
        ..take({
          'input_tokens': 10,
          'cache_creation_input_tokens': 300,
          'cache_creation': {'ephemeral_5m_input_tokens': 100, 'ephemeral_1h_input_tokens': 200},
          'server_tool_use': {'web_search_requests': 3},
        });
      expect((split.cacheWrite5m, split.cacheWrite1h, split.webSearches), (100, 200, 3));
      expect(claudeCost('claude-sonnet-5-5', split), closeTo((10 * 2 + 100 * 2.5 + 200 * 4) / 1e6 + 0.03, 1e-12));
    });
  });

  group('the month\'s count', () {
    test('adds every request, is kept across a restart, and starts again on the 1st, local time', () async {
      final store = MemorySecureStore();
      var now = DateTime(2026, 10, 20, 9);
      final spend = ClaudeSpend(store, now: () => now);
      await spend.load();
      spend.record('claude-sonnet-5-5', _usage(input: 100000, output: 10000));
      spend.record('claude-opus-5-5', _usage(input: 100000, output: 10000));
      expect(spend.requests, 2);
      expect(spend.spent, closeTo(0.2 + 0.1 + 0.4 + 0.2, 1e-9));
      await spend.setOn(true);
      await spend.setLimit(12.5);
      await spend.setWarn(false);
      await pumpEventQueue();

      // The app closed and opened again: the same month, the same count.
      final again = ClaudeSpend(store, now: () => now);
      await again.load();
      expect((again.on, again.limit, again.warn, again.requests), (true, 12.5, false, 2));
      expect(again.spent, closeTo(0.9, 1e-9));

      // The last minute of October still counts; the 1st of November starts again.
      now = DateTime(2026, 10, 31, 23, 59);
      expect(again.requests, 2);
      now = DateTime(2026, 11, 1, 0, 0, 1);
      expect(again.spent, 0);
      expect(again.requests, 0);
      // The limit itself is kept.
      expect((again.on, again.limit), (true, 12.5));
    });

    test('Reset count starts this month again', () async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      spend.record('claude-opus-5-5', _usage(output: 1000000));
      expect(spend.spent, closeTo(20, 1e-9));
      await spend.resetCount();
      expect((spend.spent, spend.requests), (0, 0));
    });

    test('reached once the total is at the limit, and only while the limit is on', () async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      expect(spend.on, isFalse);
      spend.record('claude-opus-5-5', _usage(output: 250000)); // $5
      expect(spend.reached, isFalse);
      await spend.setOn(true);
      await spend.setLimit(5);
      expect(spend.reached, isTrue);
      expect(spend.limitMessage, 'Monthly spending limit reached (\$5). Change it in Settings › Claude.');
      await spend.setLimit(10);
      expect(spend.reached, isFalse);
    });

    test('warns once a month past 80%, and not at all with the warning off', () async {
      var now = DateTime(2026, 10, 20);
      final spend = ClaudeSpend(MemorySecureStore(), now: () => now);
      await spend.load();
      await spend.setOn(true);
      await spend.setLimit(10);
      spend.record('claude-opus-5-5', _usage(output: 350000)); // $7
      expect(spend.takeNotice(), isNull);
      spend.record('claude-opus-5-5', _usage(output: 75000)); // $8.50
      expect(spend.takeNotice(), 'You’ve used \$8.50 of your \$10 monthly limit for Claude (85%). Change it in Settings › Claude.');
      expect(spend.takeNotice(), isNull);
      now = DateTime(2026, 11, 2);
      spend.record('claude-opus-5-5', _usage(output: 425000));
      expect(spend.takeNotice(), isNotNull);
      await spend.setWarn(false);
      await spend.resetCount();
      spend.record('claude-opus-5-5', _usage(output: 425000));
      expect(spend.takeNotice(), isNull);
    });

    test('is the settings\' own, heard through them', () async {
      final settings = ClaudeSettings(MemorySecureStore());
      await settings.load();
      var heard = 0;
      settings.addListener(() => heard += 1);
      settings.spend.record('claude-sonnet-5-5', _usage(input: 10));
      expect(heard, 1);
    });
  });

  group('a stream, counted', () {
    test('is counted once it ends, on the model message_start names', () async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      final events = [
        _e('message_start', {
          'message': {
            'model': 'claude-opus-5-5',
            'usage': {'input_tokens': 1000, 'cache_read_input_tokens': 2000, 'output_tokens': 1},
          },
        }),
        _e('content_block_delta', {'index': 0, 'delta': {'type': 'text_delta', 'text': 'Hello'}}),
        _e('message_delta', {'delta': {'stop_reason': 'end_turn'}, 'usage': {'output_tokens': 300}}),
        _e('message_stop', {}),
      ];
      final call = meterClaude(ClaudeCall(Stream.fromIterable(events), () {}), model: 'claude-sonnet-5-5', spend: spend);
      final seen = await call.events.toList();
      expect(seen.map((e) => e.event), ['message_start', 'content_block_delta', 'message_delta', 'message_stop']);
      expect(spend.requests, 1);
      // Opus 5.5's prices, the model that answered, not Sonnet's asked for.
      expect(spend.spent, closeTo((1000 * 4 + 2000 * 0.2 + 300 * 20) / 1e6, 1e-12));
    });

    test('a stream that breaks is counted with what it reported, its output guessed from what streamed', () async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      final events = StreamController<SseEvent>();
      final call = meterClaude(ClaudeCall(events.stream, () {}), model: 'claude-sonnet-5-5', spend: spend);
      final errors = <Object>[];
      final done = call.events.handleError(errors.add).toList();
      events.add(_e('message_start', {
        'message': {'usage': {'input_tokens': 1000}},
      }));
      final delta = _e('content_block_delta', {'index': 0, 'delta': {'type': 'text_delta', 'text': 'x' * 400}});
      events.add(delta);
      events.addError(const ClaudeError('Claude could not be reached. Check the connection.'));
      await events.close();
      await done;
      expect(errors, hasLength(1));
      expect(spend.requests, 1);
      expect(spend.spent, closeTo((1000 * 2 + (delta.data.length / 4).ceil() * 10) / 1e6, 1e-12));
    });

    test('a request refused before it streamed costs nothing and is not counted', () async {
      final spend = ClaudeSpend(MemorySecureStore(), now: () => DateTime(2026, 10, 20));
      await spend.load();
      final call = meterClaude(ClaudeCall(Stream<SseEvent>.error(const ClaudeError('The API key was refused.', status: 401)), () {}), model: 'claude-sonnet-5-5', spend: spend);
      await call.events.handleError((Object _) {}).toList();
      expect(spend.requests, 0);
    });
  });
}
