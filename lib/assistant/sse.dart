/// Server-sent events, as the Messages API streams them (docs/CLAUDE_APP.md, "The stream") and as OpenAI's Chat
/// Completions and Gemini's `streamGenerateContent?alt=sse` do too (docs/AI_PROVIDERS.md): lines of `event:` and
/// `data:` ended by an empty line, each such block one event. Only what the APIs send is read: `event`, `data` (more
/// than one joined by a line end, as the format says) and comments (a line starting with `:`), which are dropped.
/// Lines may end in `\n`, `\r\n` or `\r`, and a chunk of bytes may end anywhere, a line or a letter cut in two. An
/// event with no `event:` line is named `message`, as the format says: OpenAI's and Gemini's are all such.
///
/// It was lib/claude/sse.dart, which now hands this one on: every provider's client reads its stream through it.
library;

import 'dart:async';
import 'dart:convert';

/// One event: its name (`message_start`, `content_block_delta`, ...) and its data, the JSON as one string.
class SseEvent {
  const SseEvent(this.event, this.data);

  final String event;
  final String data;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Reads events from lines as they come. [add] a line at a time, without its end; an empty line closes the event.
class SseReader {
  String _event = '';
  final StringBuffer _data = StringBuffer();
  bool _hasData = false;

  /// The event the line closes, or null.
  SseEvent? add(String line) {
    if (line.isEmpty) {
      if (!_hasData && _event.isEmpty) return null;
      final made = SseEvent(_event.isEmpty ? 'message' : _event, _data.toString());
      _event = '';
      _data.clear();
      _hasData = false;
      return made;
    }
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      if (_hasData) _data.write('\n');
      _data.write(value);
      _hasData = true;
    }
    return null;
  }

  /// What is left when the stream ends without its last empty line.
  SseEvent? close() => add('');
}

/// The events in a stream of bytes.
Stream<SseEvent> sseEvents(Stream<List<int>> bytes) async* {
  final reader = SseReader();
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    final event = reader.add(line);
    if (event != null) yield event;
  }
  final last = reader.close();
  if (last != null) yield last;
}
