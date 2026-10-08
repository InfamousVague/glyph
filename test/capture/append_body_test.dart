import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/append_body.dart';

/// Words on the end of a note (lib/capture/append_body.dart), case for case with the web's
/// `capture/appendBody.test.ts`.
void main() {
  group('words on the end of a note', () {
    test('puts a recording under the note it continues, one blank line between, and nothing for nothing said', () {
      expect(appendBody('# Trip\n\nBook the cabin.\n\n', 'Ask Sam.'), '# Trip\n\nBook the cabin.\n\nAsk Sam.');
      expect(appendBody('', 'Ask Sam.'), 'Ask Sam.');
      expect(appendBody('# Trip', '  \n'), '# Trip');
    });

    test('ends a block of its own with a line break, and starts an empty note with it', () {
      expect(appendBlock('# Bugbash\n\nFriday.\n', '| A |\n| --- |'), '# Bugbash\n\nFriday.\n\n| A |\n| --- |\n');
      expect(appendBlock('  \n', '- Milk'), '- Milk\n');
    });
  });
}
