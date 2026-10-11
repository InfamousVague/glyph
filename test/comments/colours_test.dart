import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/comments/ask.dart';
import 'package:ghost_md/comments/author.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/format.dart';

/// Whose colour a comment wears (lib/comments/colours.dart; docs/SHARED.md, S7): ink outside an organization, and
/// in one your colour from the kept list at once and each other member's once the organization has been read, read
/// once a session and asked again after a failure. The web's `src/app/core/comments/colours.test.tsx`, case for
/// case, with the rule asked as a function where the page draws a component round its hook; and with it the two
/// small modules that have no test of their own on the web, who a comment is by and the ask from a note's menu.
class _Signed extends ChangeNotifier implements AccountSource {
  _Signed(this.session);
  @override
  Session? session;
  @override
  Future<SealKey?> accountKey() async => null;
}

/// What `fetchOrg('o1').members` says of each member's colour.
const Map<String, String?> members = {'sam': 'sea', 'matt': 'moss', 'kit': 'tartan'};

void main() {
  group('the colours comments wear', () {
    test('are ink outside an organization', () {
      final seen = commentColours(orgId: null, handle: 'matt', mine: 'amber', theirs: members);
      expect(seen.of('sam'), 'ink');
      expect(seen.of('matt'), 'ink');
      expect(seen.key, '');
    });

    test('are yours from the kept list, and each member’s once the organization is read, ink for a hue not known', () async {
      var signedIn = true;
      final read = MemberColours(signedIn: () => signedIn, fetch: (orgId) async => members);
      var told = 0;
      read.addListener(() => told += 1);
      // Yours from the list, which a change of colour updates at once: amber, not the moss the rows were read with.
      var seen = commentColours(orgId: 'o1', handle: 'matt', mine: 'amber', theirs: read.of('o1'));
      expect(seen.of('matt'), 'amber');
      expect(seen.of('sam'), 'ink');
      final before = seen.key;
      await read.read('o1');
      expect(told, 1);
      seen = commentColours(orgId: 'o1', handle: 'matt', mine: 'amber', theirs: read.of('o1'));
      expect(seen.of('matt'), 'amber');
      expect(seen.of('sam'), 'sea');
      expect(seen.of('kit'), 'ink');
      expect(seen.of('nobody'), 'ink');
      expect(seen.key, contains('sam:sea'));
      expect(seen.key, isNot(before));
      // With no colour of your own in the list, yours is the row's like anyone's.
      expect(commentColours(orgId: 'o1', handle: 'matt', theirs: read.of('o1')).of('matt'), 'moss');
      read.forget();
      expect(read.of('o1'), isNull);
      expect(told, 2);
      signedIn = false;
    });

    test('reads an organization once a session, asks again after a failure, and asks nothing signed out', () async {
      var signedIn = true;
      var calls = 0;
      Future<Map<String, String?>> fetch(String orgId) async {
        calls += 1;
        if (calls == 1) throw StateError('offline');
        return members;
      }

      final read = MemberColours(signedIn: () => signedIn, fetch: (orgId) async => fail('The fetch handed in stands for this one.'));
      await read.read('o2', fetch);
      expect(read.of('o2'), isNull);
      await read.read('o2', fetch);
      await read.read('o2', fetch);
      expect(calls, 2);
      expect(read.of('o2'), members);
      signedIn = false;
      await read.read('o3', fetch);
      expect(calls, 2);
    });

    test('are one of the hues the stylesheets know, or ink', () {
      expect(hueOf('sea'), 'sea');
      expect(hueOf('ink'), 'ink');
      expect(hueOf('tartan'), 'ink');
      expect(hueOf(null), 'ink');
    });
  });

  group('who a comment is by', () {
    test('is the account’s handle, or me on a device with no account, stamped to the second', () {
      final account = _Signed(const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(commentHandle(account), 'matt');
      final stamp = stampHere(account, DateTime.utc(2026, 10, 5, 9, 1, 2, 345));
      expect((stamp.by, stamp.at), ('matt', '2026-10-05T09:01:02Z'));
      account.session = null;
      expect(commentHandle(account), 'me');
      expect(commentHandle(null), 'me');
      expect(stampHere(null).at, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')));
      // And what it stamps heads a thread that reads back.
      final body = applyEdits('x', addThread('x', const Target.line(1), stampHere(null, DateTime.utc(2026, 10, 5)), 'hi', 'c1')!);
      expect(readComments(body).threads.single.head, const Comment(by: 'me', at: '2026-10-05T00:00:00Z', words: 'hi', line: 4));
    });
  });

  group('a comment asked for from a note’s menu', () {
    test('is taken once, by the note it names', () {
      final asks = CommentAsks();
      var told = 0;
      asks.addListener(() => told += 1);
      expect(asks.take('n1'), isFalse);
      asks.ask('n1', 42);
      expect(asks.value, (noteId: 'n1', at: 42));
      expect(told, 1);
      expect(asks.take('n2'), isFalse);
      expect(asks.take('n1'), isTrue);
      expect(asks.take('n1'), isFalse);
      expect(asks.value, isNull);
      expect(told, 2);
    });
  });
}
