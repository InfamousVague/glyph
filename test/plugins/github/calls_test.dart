import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/github/issues.dart';
import 'package:ghost_md/plugins/github/manifest.dart';
import 'package:ghost_md/plugins/github/repos.dart';

import 'support.dart';

/// GitHub's issues API as the plugin calls it (issues.dart), stood in for by a recorded `Fetcher`: what is sent to
/// make, read, close and reopen an issue, the token that has to be there to write, and GitHub's refusals as
/// sentences a person can act on. A port of `src/app/plugins/github/calls.test.ts`, case for case.
void main() {
  Map<String, Object?> raw([Map<String, Object?> over = const {}]) =>
      {'number': 12, 'title': 'Ship the page', 'html_url': 'https://github.com/o/r/issues/12', 'state': 'open', 'labels': <Object?>[], 'assignees': <Object?>[], ...over};

  late TestGround ground;
  // The next answers, in order; the usual one after them.
  late List<FetchResponse> next;

  setUp(() {
    next = [];
    ground = useGround((request) async => next.isNotEmpty ? next.removeAt(0) : FetchResponse.json(200, raw()));
  });

  Matcher refuses(String message) => throwsA(isA<GithubFailure>().having((f) => f.message, 'message', message));

  group('writing issues', () {
    test('needs a token, and says where to add one, before asking GitHub anything', () async {
      await expectLater(createIssue(owner: 'o', repo: 'r', title: 'Ship it'), refuses(needsToken));
      await expectLater(setIssueOpen('https://github.com/o/r/issues/12', open: false), refuses(needsToken));
      expect(ground.asked, isEmpty);
    });

    test('makes an issue with the item’s words, cut to what GitHub takes, and the token', () async {
      await setGithubToken('ghp_secret');
      final issue = await createIssue(owner: 'o', repo: 'r', title: 'x' * 300);
      final request = ground.asked.single;
      expect(request.url.toString(), 'https://api.github.com/repos/o/r/issues');
      expect(request.method, 'POST');
      expect(header(request, 'Authorization'), 'Bearer ghp_secret');
      expect(header(request, 'Content-Type'), 'application/json');
      expect(header(request, 'Accept'), 'application/vnd.github+json');
      expect(header(request, 'X-GitHub-Api-Version'), '2022-11-28');
      expect(sentJson(request), {'title': 'x' * 250});
      expect([issue.owner, issue.repo, issue.number, issue.state], ['o', 'r', 12, 'open']);
    });

    test('closes an issue as completed, and opens one again without a reason', () async {
      await setGithubToken('ghp_secret');
      await setIssueOpen('https://github.com/o/r/issues/12', open: false);
      final closing = ground.asked.single;
      expect([closing.url.toString(), closing.method], ['https://api.github.com/repos/o/r/issues/12', 'PATCH']);
      expect(sentJson(closing), {'state': 'closed', 'state_reason': 'completed'});
      ground.asked.clear();
      await setIssueOpen('https://github.com/o/r/issues/12', open: true);
      expect(sentJson(ground.asked.single), {'state': 'open'});
    });
  });

  group('reading issues', () {
    test('reads one without a token, and refuses an address that is not an issue', () async {
      await readIssue('https://github.com/o/r/issues/12');
      final request = ground.asked.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.github.com/repos/o/r/issues/12');
      expect(header(request, 'Authorization'), isNull);
      expect(header(request, 'Content-Type'), isNull);
      expect(request.body, isNull);
      await expectLater(readIssue('https://github.com/o/r/pull/3'), refuses('That isn’t a GitHub issue.'));
    });
  });

  group('GitHub’s refusals', () {
    test('are said as what a person can do about them', () async {
      await setGithubToken('ghp_secret');
      Future<String> refusal(int status, String message, Future<Object?> Function() call) async {
        next.add(FetchResponse.json(status, {'message': message}));
        try {
          await call();
          return 'no refusal';
        } on GithubFailure catch (failure) {
          return failure.message;
        }
      }

      Future<Object?> read() => readIssue('https://github.com/o/r/issues/12');
      Future<Object?> write() => createIssue(owner: 'o', repo: 'r', title: 'Ship it');
      expect(await refusal(401, 'Bad credentials', read), 'GitHub didn’t accept that token. Check it in Settings > Plugins > GitHub.');
      expect(await refusal(403, 'API rate limit exceeded for 1.2.3.4', read), 'GitHub is rate limiting this phone. Try again in a few minutes.');
      expect(await refusal(404, 'Not Found', read), 'That issue isn’t readable with this token.');
      expect(await refusal(403, 'Resource not accessible by integration', write), 'That repo doesn’t allow this token to write issues.');
      expect(await refusal(410, 'Issues are disabled for this repo', write), 'Issues are switched off for that repo.');
      expect(await refusal(422, 'Validation Failed', write), 'GitHub: Validation Failed');
      next.add(textAnswer(502, 'upstream'));
      await expectLater(write(), refuses('GitHub answered 502.'));
    });
  });
}
