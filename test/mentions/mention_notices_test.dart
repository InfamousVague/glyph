// A member named in a team note is told once (lib/mentions/mention_notices.dart; Matt, 2026-10-30: "add all 12"):
// by the device whose own change wrote the mention, after the pass, sealed under the organization key, and never
// twice - not on every edit, not from Matt's other device, not after a lost answer. Against the service in memory
// (test/support/fake_service.dart), whose mentions route writes a row into the member's feed once per id, as
// server/src/notifications.rs does.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/mentions/mention_notices.dart';
import 'package:ghost_md/sync/feed.dart';

import '../feed/signed.dart';
import '../support/fake_service.dart';

/// One of Matt's devices: what it keeps of its mentions, and its notes' words.
class Device {
  Device(this.service) : ledger = MentionLedger(kept: MemoryStored(), now: () => 1000);
  final FakeService service;
  final MentionLedger ledger;
  final Map<String, String> notes = {};

  /// Words this device typed into a note, from what it had.
  void types(String noteId, String words) {
    final before = notes[noteId] ?? '';
    notes[noteId] = words;
    ledger.made(7, org, noteId, before, words);
  }

  /// Words that arrived from the team's log: never this device's to tell.
  void hears(String noteId, String words) => notes[noteId] = words;

  late String org;
  late SealKey key;

  Future<int> pass() => sendMentions(
        ledger,
        MentionSend(
          accountId: 7,
          token: service.signedIn(),
          orgId: org,
          key: key,
          generation: 1,
          api: apiOf(service),
          crypto: service.crypto,
          me: 'matt',
          words: (id) async => notes[id],
          title: (id, words) => words.split('\n').first.replaceFirst('# ', ''),
        ),
      );
}

Future<({FakeService service, String org, SealKey key})> team() async {
  final service = await FakeService.start(seed: testAccount, peers: const ['sam', 'ana', 'zed']);
  final made = await apiOf(service).callMap('POST', 'orgs', token: service.signedIn(), body: {'name': 'Ghost'});
  final org = (made['org'] as Map)['id'] as String;
  final rows = service.orgs[org]!.rows;
  rows['sam'] = OrgRowKept(handle: 'sam', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
  rows['ana'] = OrgRowKept(handle: 'ana', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
  rows['zed'] = OrgRowKept(handle: 'zed', role: 'member', state: 'invited', since: 1, invitedBy: 'matt');
  final key = await service.crypto.importSealKey(Uint8List.fromList(List<int>.filled(32, 7)));
  return (service: service, org: org, key: key);
}

Device deviceOn(({FakeService service, String org, SealKey key}) t) => Device(t.service)
  ..org = t.org
  ..key = t.key;

void main() {
  test('a mention typed is told once the pass runs, to the member named, at its line', () async {
    final t = await team();
    final mac = deviceOn(t);
    mac.types('n1', '# Launch plan\n\nAsk @sam to check the copy');
    expect(mac.ledger.owedIn(7, t.org), hasLength(1));
    expect(await mac.pass(), 1);
    expect(t.service.mentioned.keys, ['sam']);
    final row = t.service.mentioned['sam']!.values.single;
    expect((row.from, row.org, row.generation), ('matt', t.org, 1));
    expect(mac.ledger.owedIn(7, t.org), isEmpty);
    // Typing on - the line, the note - tells nobody again.
    mac.types('n1', '# Launch plan\n\nAsk @sam to check the copy before Friday');
    expect(await mac.pass(), 0);
    expect(t.service.mentionPosts, hasLength(1));
  });

  test('typed a letter at a time, only the name that stays is told', () async {
    final t = await team();
    final mac = deviceOn(t);
    var words = '# Plan\n';
    for (final letter in '@sam '.split('')) {
      words += letter;
      mac.types('n1', words);
    }
    expect(mac.ledger.owedIn(7, t.org).map((o) => o.handle), containsAll(['s', 'sa', 'sam']));
    expect(await mac.pass(), 1);
    expect(t.service.mentionPosts.single['to'], ['sam']);
    expect(mac.ledger.owedIn(7, t.org), isEmpty, reason: 'the names on the way to it are dropped, untold');
  });

  test('notify once per mention across two devices: the other device hears it and tells nobody, and a second telling lands once', () async {
    final t = await team();
    final mac = deviceOn(t), phone = deviceOn(t);
    const words = '# Launch plan\nAsk @sam to check the copy';
    mac.types('n1', words);
    // The phone has the words from the team's log: not its own change.
    phone.hears('n1', words);
    expect(phone.ledger.owedIn(7, t.org), isEmpty);
    expect(await mac.pass(), 1);
    expect(await phone.pass(), 0);
    expect(t.service.mentioned['sam'], hasLength(1));
    // Both devices owing the same mention (the phone's own copy reconciled as a change of its own): the same id, so
    // the service writes nothing more.
    phone.types('n1', '');
    phone.types('n1', words);
    expect(phone.ledger.owedIn(7, t.org), hasLength(1));
    await phone.pass();
    expect(t.service.mentionPosts, hasLength(2));
    expect(t.service.mentioned['sam'], hasLength(1), reason: 'one row in sam’s bell');
    expect(mentionId(t.org, 'n1', 'sam', 1), mentionId(t.org, 'n1', 'SAM', 1), reason: 'a person is the same person in any case');
  });

  test('a second mention of the same person is told; one deleted and typed again is not', () async {
    final t = await team();
    final mac = deviceOn(t);
    mac.types('n1', '# Plan\n@sam first');
    await mac.pass();
    mac.types('n1', '# Plan\n@sam first\nand @sam again, with @ana');
    expect(await mac.pass(), 2);
    expect(t.service.mentioned['sam'], hasLength(2));
    expect(t.service.mentioned['ana'], hasLength(1));
    mac.types('n1', '# Plan\nfirst\nand again');
    mac.types('n1', '# Plan\n@sam first\nand again');
    expect(await mac.pass(), 0);
    expect(t.service.mentionPosts, hasLength(3), reason: 'the one told already is not posted again');
  });

  test('yourself, a stranger and an invitee are not told; a mention in code is no mention', () async {
    final t = await team();
    final mac = deviceOn(t);
    mac.types('n1', '# Plan\n@matt @nobody @zed `@sam`');
    await mac.pass();
    expect(t.service.mentioned, isEmpty);
    expect([for (final post in t.service.mentionPosts) post['to']], [
      ['nobody'],
      ['zed'],
    ], reason: 'the service, not the device, knows who is a member');
  });

  test('a service without the route keeps the mention for a later pass', () async {
    final service = await FakeService.start(seed: testAccount, teams: false);
    final mac = Device(service)
      ..org = 'org-1'
      ..key = await service.crypto.importSealKey(Uint8List(32));
    mac.types('n1', '# Plan\n@sam');
    expect(await mac.pass(), 0);
    expect(mac.ledger.owedIn(7, 'org-1'), hasLength(1));
  });

  group('the sealed payload', () {
    test('is sealed under the organization key, for this mention alone, and says who, where and the line', () async {
      final t = await team();
      final mac = deviceOn(t);
      mac.types('n1', '# Launch plan\n\nAsk @sam to check the copy');
      await mac.pass();
      final id = t.service.mentioned['sam']!.keys.single;
      expect(id, mentionId(t.org, 'n1', 'sam', 1));
      final blob = t.service.mentioned['sam']![id]!.blob;
      expect(blob, isNot(contains('Launch')));
      final opened = await t.service.crypto.open(t.key, blob, mentionContext(t.org, id));
      expect(opened, {'kind': 'mention', 'noteId': 'n1', 'title': 'Launch plan', 'by': 'matt', 'first': 'Ask @sam to check the copy', 'at': 'line:3'});
      // Not under another key, nor moved to another mention's id or organization.
      await expectLater(t.service.crypto.open(t.service.accountKey, blob, mentionContext(t.org, id)), throwsA(anything));
      await expectLater(t.service.crypto.open(t.key, blob, mentionContext(t.org, 'another')), throwsA(anything));
      await expectLater(t.service.crypto.open(t.key, blob, mentionContext('org-else', id)), throwsA(anything));
    });

    test('sam\'s bell opens it with the organization key and reads who mentioned them where', () async {
      final t = await team();
      final mac = deviceOn(t);
      mac.types('n1', '# Launch plan\n\nAsk @sam to check the copy');
      await mac.pass();
      final id = t.service.mentioned['sam']!.keys.single;
      final row = FeedNotification(id: id, rev: 3, kind: 'mention', at: 1, from: 'matt', org: (id: t.org, name: 'Ghost'), body: const {'name': 'Ghost', 'generation': 1}, blob: t.service.mentioned['sam']![id]!.blob);
      final account = SignedAccount(session: testSession, key: t.service.accountKey);
      final feed = NotificationFeed(account: account, crypto: t.service.crypto, kept: MemoryStored());
      // No organization key here: drawn by its kind, in the clear words the service gave.
      expect(await feed.detailsFor(row), isNull);
      expect(sentenceOf(row), 'matt mentioned you in a note');
      feed.forgetOpened();
      feed.orgKey = (org, generation) async => org == t.org && generation == 1 ? t.key : null;
      final details = await feed.detailsFor(row);
      expect((details?.kind, details?.noteId, details?.at, details?.by), ('mention', 'n1', 'line:3', 'matt'));
      expect(sentenceOf(row, details), 'matt mentioned you in Launch plan');
      expect(detailOf(details), 'Ask @sam to check the copy');
      expect(categoryOf('mention'), 'mentions');
      expect(isMention(row), isTrue);
      feed.dispose();
    });

    test('a self row of a mention under the account key is never one', () async {
      final service = await FakeService.start(seed: testAccount);
      final account = SignedAccount(session: testSession, key: service.accountKey);
      final feed = NotificationFeed(account: account, crypto: service.crypto, kept: MemoryStored());
      final blob = await service.crypto.seal(service.accountKey, {'kind': 'mention', 'noteId': 'n1', 'title': 'Forged', 'by': 'sam'}, 'notification:x1');
      expect(await feed.detailsFor(FeedNotification(id: 'x1', kind: 'note-edited', at: 1, blob: blob)), isNull);
      feed.dispose();
    });
  });

  test('an api refusal in the service\'s words drops the mention; a lapsed minute keeps the rest', () async {
    final t = await team();
    final mac = deviceOn(t);
    mac.types('n1', '# Plan\n@sam');
    // Not a member of the organization any more: "No such organization." is an answer, and there is nothing to tell.
    t.service.orgs[t.org]!.rows['matt']!.state = 'invited';
    expect(await mac.pass(), 0);
    expect(mac.ledger.owedIn(7, t.org), isEmpty);
  });
}
