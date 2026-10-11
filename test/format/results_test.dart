// A port of src/app/format/results.test.ts.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/format/results.dart';

void main() {
  group('the gist kept on the page', () {
    setUp(() => useStored(MemoryStored()));

    test('keeps a gist per note, with the body it came from', () {
      keepGist('n1', const Gist(text: 'Call the plumber by Thursday', forBody: 11, model: 'qwen3.5-2b', len: 40, head: 'plumber'));
      keepGist('n2', const Gist(text: 'The weekend trip', forBody: 22, model: 'qwen3.5-2b'));
      expect(readGist('n1'), const Gist(text: 'Call the plumber by Thursday', forBody: 11, model: 'qwen3.5-2b', len: 40, head: 'plumber'));
      expect(readGist('n2')?.text, 'The weekend trip');
      expect(readGist('n3'), isNull);
      // What is kept is the page's JSON, key for key: a gist written here is one the web app reads, and the other way.
      expect(jsonDecode(stored.readText('glyph-ai-results')!), {
        'n1': {'gist': {'text': 'Call the plumber by Thursday', 'for': 11, 'model': 'qwen3.5-2b', 'len': 40, 'head': 'plumber'}},
        'n2': {'gist': {'text': 'The weekend trip', 'for': 22, 'model': 'qwen3.5-2b'}},
      });
    });

    test('forgets a note on request', () {
      keepGist('n1', const Gist(text: 'A line', forBody: 11, model: 'qwen3.5-2b'));
      forgetResults('n1');
      expect(readGist('n1'), isNull);
      expect(stored.readText('glyph-ai-results'), '{}');
    });

    test('survives a broken sheet, and reads past an older sheet’s mode texts', () {
      stored.writeText('glyph-ai-results', '[not json');
      expect(readGist('n1'), isNull);
      stored.writeText(
        'glyph-ai-results',
        jsonEncode({
          'n1': {
            'summarize': {'text': '# Short\n', 'for': 11, 'model': 'x'},
            'gist': {'text': 'A line', 'for': 11, 'model': 'x'},
          },
        }),
      );
      expect(readGist('n1')?.text, 'A line');
      // Read past and kept: a new gist leaves the older text beside it.
      keepGist('n1', const Gist(text: 'Another', forBody: 12, model: 'x'));
      expect((jsonDecode(stored.readText('glyph-ai-results')!) as Map)['n1'], {
        'summarize': {'text': '# Short\n', 'for': 11, 'model': 'x'},
        'gist': {'text': 'Another', 'for': 12, 'model': 'x'},
      });
    });
  });
}
