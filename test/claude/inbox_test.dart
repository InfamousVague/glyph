import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/claude_inbox.dart';

void main() {
  group('the Ask Claude inbox', () {
    const body = '# Ask Claude\n\nWrite a request.\n\n- [x] Old one\n  - Done it.\n- [ ] Plan my week\n- [ ] Answered already\n  - Wrote [[Notes]].\n- [ ] \n```\n- [ ] in a fence\n```';

    test('finds the open requests with words and no answer under them, never in a fence', () {
      expect([for (final r in openRequests(body)) (r.line, r.text)], [(6, 'Plan my week')]);
    });

    test('answers a request under it and ticks it, found by its words wherever it has moved', () {
      final request = openRequests(body).single;
      final moved = 'A new first line\n$body';
      final next = answerRequest(moved, request, 'Wrote [[Week plan]].', done: true)!;
      expect(next, contains('- [x] Plan my week\n  - Wrote [[Week plan]].\n- [ ] Answered already'));
      expect(openRequests(next), isEmpty);
      // Not done: answered, left open.
      final open = answerRequest(body, request, 'Needs a calendar.', done: false)!;
      expect(open, contains('- [ ] Plan my week\n  - Needs a calendar.'));
      // Changed meanwhile: nothing written.
      expect(answerRequest(body.replaceFirst('Plan my week', 'Plan my month'), request, 'x', done: true), isNull);
    });

    test('reads the verdict on Claude\'s last line', () {
      expect(inboxVerdict('Made it.\n\nDONE: Wrote [[Week plan]].'), (done: true, sentence: 'Wrote [[Week plan]].'));
      expect(inboxVerdict('`COULD NOT: ` There is no calendar.'), (done: false, sentence: 'There is no calendar.'));
      expect(inboxVerdict('Just words.'), (done: true, sentence: 'Just words.'));
    });

    test('takes a request from the chat in the empty to-do the connector leaves, or at the end', () {
      expect(addInboxRequest('# Ask Claude\n\nWords.\n\n- [ ] ', '- [ ] Plan my week'), '# Ask Claude\n\nWords.\n\n- [ ] Plan my week');
      expect(addInboxRequest('# Ask Claude\n\n- [x] Done', '- [ ] Next'), '# Ask Claude\n\n- [x] Done\n- [ ] Next\n');
      expect(openRequests(newInboxBody('- [ ] First')).single.text, 'First');
    });
  });
}
