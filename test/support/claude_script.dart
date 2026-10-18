// Anthropic's Messages API as a script, for a test that drives the app's own Claude through the root (set as
// `debugClaudeApi`, lib/claude/claude_runner.dart): each request answered with its turn, the events paced as a stream
// comes, so a note Claude writes in is typed into while the test watches.
import 'dart:convert';

import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// One reply: [words] said, then [tool] called with its input in [pieces], or no tool.
List<SseEvent> scriptedTurn({String words = '', String? tool, List<String> pieces = const []}) => [
      _e('message_start', {'type': 'message_start'}),
      if (words.isNotEmpty) ...[
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': words},
        }),
        _e('content_block_stop', {'index': 0}),
      ],
      if (tool != null) ...[
        _e('content_block_start', {
          'index': 1,
          'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': tool, 'input': <String, Object?>{}},
        }),
        for (final piece in pieces)
          _e('content_block_delta', {
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': piece},
          }),
        _e('content_block_stop', {'index': 1}),
      ],
      _e('message_delta', {
        'delta': {'stop_reason': tool == null ? 'end_turn' : 'tool_use'},
      }),
      _e('message_stop', {'type': 'message_stop'}),
    ];

/// [json] in pieces of [size], as the API cuts a tool's input.
List<String> scriptedPieces(String json, int size) => [for (var i = 0; i < json.length; i += size) json.substring(i, i + size > json.length ? json.length : i + size)];

/// The API answering each request with the next of [turns], an event every [beat].
class ScriptedClaudeApi extends ClaudeApi {
  ScriptedClaudeApi(this.turns, {this.beat = const Duration(milliseconds: 20)}) : super(key: 'sk-ant-test');

  final List<List<SseEvent>> turns;
  final Duration beat;
  int asked = 0;

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    final events = turns[asked++];
    Stream<SseEvent> paced() async* {
      for (final event in events) {
        await Future<void>.delayed(beat);
        yield event;
      }
    }

    return ClaudeCall(paced(), () {});
  }
}
