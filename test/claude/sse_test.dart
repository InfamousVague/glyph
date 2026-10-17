import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/sse.dart';

void main() {
  group('server-sent events', () {
    test('read as the Messages API streams them, an event to each empty line', () {
      final reader = SseReader();
      final made = <SseEvent>[];
      for (final line in ['event: message_start', 'data: {"type":"message_start"}', '', ': a comment', 'event: ping', 'data: {}', '']) {
        final event = reader.add(line);
        if (event != null) made.add(event);
      }
      expect([for (final e in made) (e.event, e.data)], [('message_start', '{"type":"message_start"}'), ('ping', '{}')]);
    });

    test('join several data lines, and an event with no name is a message', () {
      final reader = SseReader();
      reader.add('data: one');
      reader.add('data:two');
      final event = reader.add('')!;
      expect((event.event, event.data), ('message', 'one\ntwo'));
    });

    test('come whole from bytes cut anywhere, a letter and a line end in two', () async {
      final text = 'event: content_block_delta\r\ndata: {"text":"café"}\r\n\r\nevent: message_stop\ndata: {}\n';
      final bytes = utf8.encode(text);
      final pieces = <List<int>>[for (var i = 0; i < bytes.length; i += 3) bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3)];
      final events = await sseEvents(Stream<List<int>>.fromIterable(pieces)).toList();
      expect([for (final e in events) (e.event, e.data)], [('content_block_delta', '{"text":"café"}'), ('message_stop', '{}')]);
    });
  });
}
