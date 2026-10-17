import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_inbox.dart';
import 'package:ghost_md/claude/claude_run.dart' show ClaudeDesk;
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_tools.dart' show ClaudeNotes;
import 'package:ghost_md/claude/messages_api.dart' show ClaudeError;

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

  // The app's own Claude is the Claude plugin's (lib/plugins/claude): off, nothing is asked, from the chat or the
  // inbox.
  group('under the Claude plugin', () {
    late ClaudeSettings settings;
    late List<String> keys;
    late bool on;
    late ClaudeRunner runner;

    setUp(() async {
      settings = ClaudeSettings(MemorySecureStore());
      await settings.setKey('sk-ant-test-0000000000');
      keys = [];
      on = false;
      runner = ClaudeRunner(
        settings: settings,
        notes: _NoNotes(),
        desk: _NoDesk(),
        api: (key) {
          keys.add(key);
          throw const ClaudeError('asked');
        },
        allowed: () => on,
      );
    });
    tearDown(() => runner.dispose());

    test('refuses an ask while it is off, and says where it is switched on', () async {
      await expectLater(runner.ask('Hello'), throwsA(isA<ClaudeError>().having((e) => e.message, 'message', contains('Settings › Plugins'))));
      expect(keys, isEmpty);
      expect(runner.conversation, isEmpty);
    });

    test('asks nothing of the inbox while it is off, and looks again when it is switched on', () {
      fakeAsync((async) {
        final changes = ValueNotifier<int>(0);
        var looked = 0;
        final inbox = ClaudeInbox(
          runner: runner,
          body: () {
            looked += 1;
            return (id: 'inbox', body: '# Ask Claude\n\n- [ ] Write the plan');
          },
          changes: changes,
          write: (id, change) async {},
          on: () => on,
        )..start();
        async.elapse(inboxSettle + const Duration(seconds: 1));
        expect(looked, 0);
        expect(keys, isEmpty);
        on = true;
        changes.value += 1;
        async.elapse(inboxSettle + const Duration(seconds: 1));
        expect(looked, 1);
        expect(keys, ['sk-ant-test-0000000000']);
        inbox.dispose();
      });
    });
  });
}

class _NoNotes implements ClaudeNotes {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Object?>.value(null);
}

class _NoDesk implements ClaudeDesk {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
