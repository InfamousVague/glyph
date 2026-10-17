import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/partial_json.dart';

class _Heard extends FieldListener {
  final List<String> said = [];

  @override
  void started(String key) => said.add('start $key');

  @override
  void letters(String key, String text) => said.add('$key+$text');

  @override
  void ended(String key, String value) => said.add('end $key=$value');
}

/// [json] fed in pieces of [size].
_Heard _read(String json, int size, [PartialFields? into]) {
  final heard = _Heard();
  final reader = into ?? PartialFields(heard);
  for (var i = 0; i < json.length; i += size) {
    reader.add(json.substring(i, i + size > json.length ? json.length : i + size));
  }
  return heard;
}

void main() {
  group('a tool\'s input read as it streams', () {
    test('says each string field as it starts, its letters as they come, and its whole value', () {
      final heard = _read('{"id": "n1", "body": "# Plan\\n\\nSoon."}', 4);
      expect(heard.said.first, 'start id');
      expect(heard.said, contains('end id=n1'));
      expect(heard.said.last, 'end body=# Plan\n\nSoon.');
      final letters = heard.said.where((s) => s.startsWith('body+')).map((s) => s.substring(5)).join();
      expect(letters, '# Plan\n\nSoon.');
    });

    test('decodes escapes cut between pieces, a \\u escape and a surrogate pair among them', () {
      for (final size in [1, 2, 3, 5, 7]) {
        final heard = _Heard();
        final reader = PartialFields(heard);
        _read(r'{"text": "a\"b\\c \u00e9 \ud83d\ude00 end"}', size, reader);
        expect(reader.strings['text'], 'a"b\\c é 😀 end', reason: 'pieces of $size');
        final letters = heard.said.where((s) => s.startsWith('text+')).map((s) => s.substring(5)).join();
        expect(letters, 'a"b\\c é 😀 end', reason: 'pieces of $size');
        expect(reader.done, isTrue);
      }
    });

    test('steps over values that are not strings, and knows which fields are whole', () {
      final reader = PartialFields();
      reader.add('{"limit": 30, "tags": ["a", "b]"], "deep": {"x": "}"}, "query": "pla');
      expect(reader.strings, {'query': 'pla'});
      expect(reader.whole, isEmpty);
      reader.add('n"}');
      expect(reader.strings, {'query': 'plan'});
      expect(reader.whole, {'query'});
      expect(reader.done, isTrue);
      expect(reader.broken, isFalse);
    });

    test('stops at what is not JSON, and never throws', () {
      final reader = PartialFields();
      reader.add('not json');
      expect(reader.broken, isTrue);
      reader.add('{"a": "b"}');
      expect(reader.strings, isEmpty);
    });
  });
}
