import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/orgs/types.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/slack.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/sync/arrived.dart';

import '../support.dart' show manifestOf;
import 'support.dart';

/// An organization's news to its Slack channel: only the new rows of a pass, never a device's first look, only the
/// organization a channel was chosen for, only its news, each row once however often it comes back above the
/// cursor, and nothing from before the channel was chosen. A port of `src/app/plugins/slack/news.test.ts`, case
/// for case; posting itself is stood in for in its cases, and channels_test.dart has the posting.
void main() {
  const hook = 'https://hooks.slack.com/services/T0/B0/abc';
  const setAt = 1000;

  FeedNotification row(String id, int rev, {String kind = 'member-joined', int? at, int? readAt, String? from = 'sam', NotificationOrg? org = (id: 'acme', name: 'Acme'), Map<String, Object?>? body}) =>
      FeedNotification(id: id, rev: rev, kind: kind, at: at ?? setAt + rev, readAt: readAt, from: from, org: org, body: body);

  late FakeSlack slack;
  late List<({String channel, String text})> sent;
  late int asked;
  Object? failNext;

  Future<void> post(Channel channel, String text) async {
    asked += 1;
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    sent.add((channel: channel.name, text: text));
  }

  bool member(String orgId) => orgId == 'acme' || orgId == 'globex';

  setUp(() async {
    slack = FakeSlack();
    sent = [];
    asked = 0;
    failNext = null;
    final launch = await addChannel('#acme', hook);
    setNewsChannel('acme', launch.id, setAt);
  });

  group('an organization’s news in Slack', () {
    test('posts the rows a pass brought, oldest first, as the bell’s sentences', () async {
      final rows = [row('r3', 13, kind: 'role-changed', body: const {'role': 'admin'}), row('r2', 12), row('r1', 11)];
      expect(await forwardNews(11, rows, post: post, member: member), 2);
      expect(sent, [(channel: '#acme', text: 'sam joined Acme.'), (channel: '#acme', text: 'sam made you an admin of Acme.')]);
    });

    test('posts nothing on a device’s first look at the feed', () async {
      expect(await forwardNews(0, [row('r1', 5)], post: post, member: member), 0);
      expect(asked, 0);
    });

    test('posts each row once, however often it comes back above the cursor', () async {
      await forwardNews(10, [row('r1', 11)], post: post, member: member);
      // Read on another device: written again, at a later revision.
      await forwardNews(11, [row('r1', 14, readAt: 2000)], post: post, member: member);
      expect(sent, hasLength(1));
    });

    test('posts only the organization a channel was chosen for, and only its news', () async {
      final rows = [
        row('g1', 11, org: (id: 'globex', name: 'Globex')),
        row('i1', 12, kind: 'invite'),
        row('c1', 13, kind: 'note-edited', org: null),
        row('a1', 14, kind: 'org-renamed', body: const {'was': 'Acme Ltd'}),
      ];
      await forwardNews(10, rows, post: post, member: member);
      expect([for (final s in sent) s.text], ['sam renamed Acme Ltd to Acme.']);
    });

    test('posts nothing from before the channel was chosen, nor for an organization the person has left', () async {
      await forwardNews(10, [row('old', 11, at: setAt - 1)], post: post, member: member);
      await forwardNews(10, [row('left', 12)], post: post, member: (_) => false);
      expect(sent, isEmpty);
    });

    test('stops when the channel is set to nowhere, or forgotten', () async {
      setNewsChannel('acme', null);
      expect(newsChannelFor('acme'), isNull);
      expect(await forwardNews(10, [row('r1', 11)], post: post, member: member), 0);
      // Forgotten: the choice still names it, and finds no channel.
      final ops = await addChannel('#ops', hook);
      setNewsChannel('acme', ops.id, setAt);
      expect(newsChannelFor('acme')?.name, '#ops');
      await forgetChannel(ops.id);
      expect(newsChannelFor('acme'), isNull);
      expect(await forwardNews(10, [row('r2', 12)], post: post, member: member), 0);
      expect(asked, 0);
    });

    test('escapes what Slack would read as its own marks', () async {
      await forwardNews(10, [row('r1', 11, from: '<!channel>')], post: post, member: member);
      expect(sent.first.text, '&lt;!channel&gt; joined Acme.');
    });

    test('is not tried again when a post fails', () async {
      failNext = const SlackFailure('Slack had a problem.');
      expect(await forwardNews(10, [row('r1', 11)], post: post, member: member), 0);
      expect(await forwardNews(10, [row('r1', 12)], post: post, member: member), 0);
      expect(asked, 1);
    });

    // Not a case of the page's, which stood in for both: the real post, and membership by the account's own list.
    test('goes to the channel’s webhook for an organization the account is a member of', () async {
      slackOrgs = SlackOrgs(list: () => const [OrgRow(id: 'acme', name: 'Acme', role: 'member', state: 'member'), OrgRow(id: 'globex', name: 'Globex', role: 'member', state: 'invited')]);
      final globex = await addChannel('#globex', '$hook-globex');
      setNewsChannel('globex', globex.id, setAt);
      expect(await forwardNews(10, [row('r1', 11), row('g1', 12, org: (id: 'globex', name: 'Globex'))]), 1);
      expect(slack.posts, [(url: hook, text: 'sam joined Acme.')]);
      expect(isWebhookPost(slack.ground.asked.single, hook), isTrue);
      // The ids posted are kept, and nothing else of the rows.
      expect(slack.ground.kept.getItem('glyph-slack-posted'), '["r1"]');
    });

    test('is the plugin’s `newRows`, which does nothing with no channel or on a first look', () async {
      slackOrgs = SlackOrgs(list: () => const [OrgRow(id: 'acme', name: 'Acme', role: 'member', state: 'member')]);
      await slackPlugin.newRows!(0, [row('r1', 11)]);
      expect(slack.posts, isEmpty);
      await slackPlugin.newRows!(10, [row('r1', 11)]);
      expect(slack.posts, [(url: hook, text: 'sam joined Acme.')]);
    });
  });

  group('the feed’s new rows', () {
    test('reach a plugin through the registry only while it is on', () async {
      final heard = <(int, List<FeedNotification>)>[];
      var quiet = 0;
      final on = GlyphPlugin(manifest: manifestOf('listens', standard: true), icon: 'hash', newRows: (before, rows) async => heard.add((before, rows)));
      final off = GlyphPlugin(manifest: manifestOf('quiet', standard: false), icon: 'hash', newRows: (before, rows) async => quiet += 1);
      final registry = createRegistry([on, off], store: MemorySwitches());
      final rows = [row('r1', 5)];
      await registry.newRows(4, rows);
      expect(heard, [(4, rows)]);
      expect(quiet, 0);
    });

    test('are told to every listener, and one that throws stops nobody', () {
      final second = <(int, List<FeedNotification>)>[];
      final stopFirst = onArrived((before, rows) => throw StateError('mine'));
      final stopSecond = onArrived((before, rows) => second.add((before, rows)));
      tellArrived(3, const []);
      expect(second, [(3, const <FeedNotification>[])]);
      stopFirst();
      stopSecond();
    });
  });
}
