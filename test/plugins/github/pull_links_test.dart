// A ticket's pull requests (lib/plugins/github/pull_links.dart; Matt, 2026-10-31, "GitHub PR links"): a key in a
// title, a body, a branch or a commit's message links the pull request; its chip's state and checks; an unchanged
// repo answers 304 to its ETag; and a merge moves the ticket as the notebook says. GitHub is fakes, never asked.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/properties.dart' show defaultStatuses;
import 'package:ghost_md/plugins/github/pull_links.dart';

FetchResponse json(Object body, {int status = 200, String? etag}) => FetchResponse(status, headers: {'ETag': ?etag}, bytes: utf8.encode(jsonEncode(body)));

Map<String, Object?> pull(int number, String title, {String body = '', String branch = 'main', String state = 'open', bool draft = false, String? mergedAt, String sha = 'abc', String updated = '2026-10-30T10:00:00Z'}) => {
      'number': number,
      'title': title,
      'body': body,
      'state': state,
      'draft': draft,
      'merged_at': mergedAt,
      'html_url': 'https://github.com/ghost/app/pull/$number',
      'head': {'ref': branch, 'sha': sha},
      'updated_at': updated,
    };

void main() {
  test('a key is the notebook’s key and a number, never inside a longer one, any case in a branch', () {
    expect(ticketKeysIn('Fixes HT-12 and ht-9; see HT-123 and HT-0'), {'HT-12', 'HT-9', 'HT-123'});
    expect(ticketKeysIn('see WHT-12 and xHT-5'), {'WHT-12', 'XHT-5'}, reason: 'another notebook’s keys, never HT-12');
    expect(ticketKeysIn('feature/ht-12-fix-login'), {'HT-12'});
    expect(ticketKeysIn('nothing here'), isEmpty);
  });

  group('the pulls a ticket has', () {
    late List<String> asked;
    late Map<String, FetchResponse Function(FetchRequest request)> answers;
    late PullLinks links;

    setUp(() {
      asked = [];
      answers = {};
      links = PullLinks(
        token: () => 'test-token',
        fetch: (request) async {
          final path = request.url.toString().replaceFirst('https://api.github.com/', '');
          asked.add('${request.headers['If-None-Match'] ?? '-'} $path');
          expect(request.headers['Authorization'], 'Bearer test-token');
          for (final MapEntry(:key, :value) in answers.entries) {
            if (path.startsWith(key)) return value(request);
          }
          return json(const {'message': 'Not Found'}, status: 404);
        },
      );
    });

    test('a sync reads the repo’s recent pulls, matched by title, body and branch, each with its state', () async {
      answers['repos/ghost/app/pulls?state=all'] = (_) => json([
            pull(41, 'HT-12: keep the email', mergedAt: '2026-10-30T11:00:00Z', state: 'closed', updated: '2026-10-30T11:00:00Z'),
            pull(42, 'Tidy the form', body: 'Part of HT-12.', draft: true),
            pull(43, 'Login copy', branch: 'ht-12-copy'),
            pull(44, 'Abandoned', branch: 'feature/HT-12', state: 'closed', updated: '2026-10-29T10:00:00Z'),
            pull(45, 'Other work HT-13'),
          ], etag: 'W/"one"');
      await links.pollRepo('ghost/app');
      final found = links.pullsFor('HT-12', ['ghost/app']);
      expect([for (final linked in found) '${linked.words} via ${linked.via.name}'], ['#41 Merged via title', '#43 Open via branch', '#42 Draft via body', '#44 Closed via branch']);
      expect(links.pullsFor('ht-13', ['ghost/app']).single.pull.number, 45);
      expect(links.pullsFor('HT-12', ['ghost/other']), isEmpty);
    });

    test('asked again, an unchanged repo answers 304 to its ETag and keeps what it had', () async {
      var n = 0;
      answers['repos/ghost/app/pulls?state=all'] = (request) {
        n += 1;
        if (request.headers['If-None-Match'] == 'W/"one"') return FetchResponse(304);
        return json([pull(41, 'HT-12: keep the email')], etag: 'W/"one"');
      };
      await links.pollRepo('ghost/app');
      await links.pollRepo('ghost/app');
      expect(n, 2);
      expect(asked.last, startsWith('W/"one" repos/ghost/app/pulls'));
      expect(links.unchanged, 1);
      expect(links.pullsFor('HT-12', ['ghost/app']).single.pull.number, 41);
    });

    test('the panel’s look finds older ones by search, and one by its commit’s message, and the open ones’ checks', () async {
      answers['search/issues'] = (request) {
        expect(Uri.decodeQueryComponent(request.url.query), contains('repo:ghost/app is:pr "HT-12" in:title,body'));
        return json({
          'items': [
            {'number': 7, 'title': 'Old fix for HT-12', 'state': 'closed', 'html_url': 'https://github.com/ghost/app/pull/7', 'pull_request': {'merged_at': '2026-01-02T00:00:00Z'}},
          ],
        });
      };
      answers['search/commits'] = (_) => json({
            'items': [
              {'sha': 'c1', 'commit': {'message': 'Keep the email field (HT-12)'}},
              {'sha': 'c2', 'commit': {'message': 'Unrelated HT-120'}},
            ],
          });
      answers['repos/ghost/app/commits/c1/pulls'] = (_) => json([pull(50, 'Form work', branch: 'form', sha: 'h50')]);
      answers['repos/ghost/app/commits/h50/check-runs'] = (_) => json({
            'check_runs': [
              {'status': 'completed', 'conclusion': 'success'},
              {'status': 'completed', 'conclusion': 'failure'},
            ],
          });
      await links.lookFor('HT-12', ['ghost/app']);
      final found = links.pullsFor('HT-12', ['ghost/app']);
      expect([for (final linked in found) linked.toString()], ['LinkedPull(ghost/app#50 Open via commit, failing)', 'LinkedPull(ghost/app#7 Merged via title)']);
      expect(asked.where((line) => line.contains('commits/c2')), isEmpty, reason: 'HT-120 is not HT-12');
      final before = asked.length;
      await links.lookFor('HT-12', ['ghost/app']);
      expect(asked.length, before, reason: 'not again so soon');
    });

    test('nothing is asked without a token', () async {
      final none = PullLinks(token: () => '', fetch: (request) async => fail('asked ${request.url}'));
      await none.pollRepo('ghost/app');
      await none.lookFor('HT-12', ['ghost/app']);
    });

    test('checks: failing where any failed, running where any is not done, passed where all are', () {
      expect(checksOf({'check_runs': []}), isNull);
      expect(checksOf({'check_runs': [{'status': 'completed', 'conclusion': 'success'}, {'status': 'completed', 'conclusion': 'skipped'}]}), PullChecks.passing);
      expect(checksOf({'check_runs': [{'status': 'in_progress'}, {'status': 'completed', 'conclusion': 'success'}]}), PullChecks.pending);
      expect(checksOf({'check_runs': [{'status': 'in_progress'}, {'status': 'completed', 'conclusion': 'timed_out'}]}), PullChecks.failing);
    });
  });

  group('a merge', () {
    LinkedPull linked(PullState state) => LinkedPull(pull: PullRecord(repo: 'ghost/app', number: 41, title: 'HT-12', state: state), via: PullVia.title);

    test('moves the ticket to done, a status named, or nothing', () {
      expect(mergeMove(status: 'In review', statuses: defaultStatuses, onMerge: 'done', pulls: [linked(PullState.merged)]), 'Done');
      expect(mergeMove(status: 'In progress', statuses: defaultStatuses, onMerge: 'In review', pulls: [linked(PullState.merged)]), 'In review');
      expect(mergeMove(status: 'In progress', statuses: defaultStatuses, onMerge: null, pulls: [linked(PullState.merged)]), isNull, reason: 'off');
      expect(mergeMove(status: 'In progress', statuses: defaultStatuses, onMerge: 'done', pulls: [linked(PullState.open), linked(PullState.closed)]), isNull);
      expect(mergeMove(status: 'Done', statuses: defaultStatuses, onMerge: 'done', pulls: [linked(PullState.merged)]), isNull, reason: 'already there');
      expect(mergeMove(status: 'Shipped', statuses: const ['Ideas', 'Building', 'Shipped'], onMerge: 'done', pulls: [linked(PullState.merged)]), isNull);
      expect(mergeMove(status: 'Building', statuses: const ['Ideas', 'Building', 'Shipped'], onMerge: 'done', pulls: [linked(PullState.merged)]), 'Shipped');
    });

    test('is known by the same run id on every device', () {
      expect(mergeRunId(const PullRecord(repo: 'ghost/app', number: 41, title: '', state: PullState.merged), 'n12'), 'merge:ghost/app#41:n12');
    });
  });
}
