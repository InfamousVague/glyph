// The git backup's setup (lib/plugins/git_backup/git_backup_setup.dart; Matt, 2026-10-31): its steps and their words,
// the token pasted and kept in the secure store, the GitHub plugin's token reused only where it may push, the
// repository made on GitHub or its address pasted, the check in plain words (empty remote, one with a backup already,
// the size and the cost ask over 200 MB, a refused token let go of, no connection), and the GitHub API as the plugin
// asks it. GitHub is a ground of the test's own: nothing is asked of the network.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/git_backup/git_backup.dart';
import 'package:ghost_md/plugins/git_backup/manifest.dart' as git;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';

import '../support.dart';

const String token = 'github_pat_11ABCDEFG0123456789_abcdefghijklmnop';

void main() {
  late TestGround ground;
  late List<FetchRequest> asked;

  setUp(() {
    useStored(MemoryStored());
    ground = TestGround(answer: (request) async {
      if (request.url.path == '/user') return FetchResponse(200, headers: {'x-oauth-scopes': 'repo, read:org'}, bytes: utf8.encode(jsonEncode({'login': 'octocat'})));
      if (request.url.path == '/user/repos') return FetchResponse.json(201, {'clone_url': 'https://github.com/octocat/ghost-notes.git', 'full_name': 'octocat/ghost-notes'});
      return FetchResponse.json(404, {'message': 'Not Found'});
    });
    usePluginGround(ground.ground);
    asked = ground.asked;
  });

  tearDown(() => usePluginGround(PluginGround()));

  GitBackupSetupHooks hooks({Future<String?> Function({required String remote, String? authUser})? adopt, Future<RepoSizes?> Function()? sizes, Future<GitDivergence> Function()? fetch, String githubToken = ''}) => GitBackupSetupHooks(
        adopt: adopt ?? ({required remote, authUser}) async => null,
        sizes: sizes ?? () async => const RepoSizes(committed: FolderSize(12000000, 300), recordings: FolderSize(40000000, 4), orgsExcluded: FolderSize.none, video: FolderSize.none, git: FolderSize.none),
        fetch: fetch ?? () async => const GitDivergence(state: 'empty', ahead: 0, behind: 0),
        githubPluginToken: () => githubToken,
        backUpNow: () async => const BackupOutcome(pushed: true, committed: 'abc'),
      );

  test('the steps, in order, each with words to say, Simple’s too, and the addresses unverified', () {
    final setup = gitBackupSetup(hooks: hooks());
    expect(setup.id, git.manifest.id);
    expect([for (final step in setup.steps) step.id], ['intro', 'token', 'reuse', 'paste', 'create', 'repository', 'check', 'done']);
    expect(setup.steps.whereType<SetupAct>().map((s) => s.advanced), [true, false], reason: 'the GitHub token’s reuse is Advanced; making the repository is for everyone');
    for (final step in setup.steps) {
      expect(setup.wordsOf(step, simple: false), isNotEmpty, reason: step.id);
      expect(setup.wordsOf(step, simple: true), isNotEmpty, reason: step.id);
    }
    expect(setupVoice['git-backup-intro'], contains('anyone who can read it can read your notes'));
    for (final link in setup.steps.whereType<SetupOpen>().expand((s) => s.links)) {
      expect(link.verified, isFalse, reason: link.url);
    }
    expect(setup.ready(), isFalse);
    expect(setup.tiles, isNotEmpty);
    expect(setup.hues.first, 'green');
  });

  test('the token is kept in the secure store, and a GitHub token with the repo scope can be reused', () async {
    final on = hooks(githubToken: token);
    final setup = gitBackupSetup(hooks: on);
    final paste = setup.steps.whereType<SetupPaste>().first;
    expect(paste.fields.single.shape!.call('x y'), contains('no spaces'));
    expect(await paste.save({'token': 'ghp_abcdefghijklmnopqrstuvwxyz'}), isNull);
    expect(gitToken(), 'ghp_abcdefghijklmnopqrstuvwxyz');
    await git.host.secrets.write(git.tokenSecret, null);
    expect(await reuseGithubToken(on), isNull);
    expect(gitToken(), token);
    expect(asked.single.url.path, '/user');
    expect(asked.single.headers['Authorization'], 'Bearer $token');
  });

  test('a GitHub token without the repo scope is refused for reuse, and none is said so', () async {
    expect(await reuseGithubToken(hooks()), contains('has no token kept'));
    ground = TestGround(answer: (request) async => FetchResponse(200, headers: {'x-oauth-scopes': 'read:user'}, bytes: utf8.encode(jsonEncode({'login': 'octocat'}))));
    usePluginGround(ground.ground);
    expect(await reuseGithubToken(hooks(githubToken: 'ghp_abcdefghijklmnopqrstuvwxyz')), contains('may not write to repositories'));
    expect(gitToken(), isEmpty);
    // A fine-grained token says nothing of its scopes: taken on the person’s word, the first push being the check.
    ground = TestGround(answer: (request) async => FetchResponse.json(200, {'login': 'octocat'}));
    usePluginGround(ground.ground);
    expect(await reuseGithubToken(hooks(githubToken: token)), isNull);
    final scopes = await GitHubApi().tokenScopes(token);
    expect((scopes.fineGrained, scopes.mayPush, scopes.login), (true, null, 'octocat'));
  });

  test('the repository made on GitHub, private, named ghost-notes; or its address pasted, SSH refused', () async {
    final setup = gitBackupSetup(hooks: hooks());
    await git.host.secrets.write(git.tokenSecret, token);
    final create = setup.steps.whereType<SetupAct>().last;
    expect(await create.run(), isNull);
    final made = asked.single;
    expect((made.method, made.url.path), ('POST', '/user/repos'));
    final body = jsonDecode(made.text) as Map;
    expect((body['name'], body['private']), ('ghost-notes', true));
    expect(gitBackupSettings().remote, 'https://github.com/octocat/ghost-notes.git');
    expect(gitBackupSettings().authUser, 'x-access-token');
    final address = setup.steps.whereType<SetupPaste>().last;
    expect(address.fields.single.shape!.call('git@github.com:me/notes.git'), contains('SSH'));
    expect(await address.save({'remote': ''}), isNull, reason: 'one was made');
    expect(await address.save({'remote': 'https://gitlab.com/me/notes.git'}), isNull);
    expect(gitBackupSettings().remote, 'https://gitlab.com/me/notes.git');
    expect(gitBackupSettings().authUser, 'oauth2');
    setGitBackupSettings(const GitBackupSettings());
    expect(await address.save({'remote': ''}), contains('Paste the repository’s HTTPS address'));
    // Without a token, nothing is made.
    await git.host.secrets.write(git.tokenSecret, null);
    expect(await create.run(), 'Paste a token first.');
  });

  test('the check: no token or no address sends back; reachable and empty, with the size; one with a backup already; over 200 MB a warning; refused token let go of; no connection; a syncing Library refused', () async {
    Future<SetupResult> check(GitBackupSetupHooks on) => gitBackupSetup(hooks: on).steps.whereType<SetupCheck>().single.run();
    var result = await check(hooks());
    expect((result.kind, result.pasteAgain, result.words), (SetupCheckKind.failed, true, contains('No token')));
    await git.host.secrets.write(git.tokenSecret, token);
    result = await check(hooks());
    expect((result.kind, result.words), (SetupCheckKind.failed, contains('No repository address')));
    setGitBackupSettings(const GitBackupSettings(remote: 'https://github.com/me/notes.git'));
    result = await check(hooks());
    expect(result.kind, SetupCheckKind.ok);
    expect(result.words, allOf(contains('reachable and empty'), contains('12 MB in 300 files'), contains('recordings (40 MB) are left out')));
    result = await check(hooks(fetch: () async => const GitDivergence(remote: 'abc', state: 'behind', ahead: 0, behind: 3)));
    expect(result.words, contains('already has a backup'));
    result = await check(hooks(sizes: () async => const RepoSizes(committed: FolderSize(250000000, 3000), recordings: FolderSize.none, orgsExcluded: FolderSize(5000, 2), video: FolderSize.none, git: FolderSize.none)));
    expect((result.kind, result.words), (SetupCheckKind.warn, allOf(contains('250 MB'), contains('over 200 MB'), contains('organizations’ notes'))));
    result = await check(hooks(fetch: () async => throw const GitFailure(GitTrouble.signIn, 'Sign-in refused: 401')));
    expect((result.kind, result.pasteAgain), (SetupCheckKind.failed, true));
    expect(gitToken(), isEmpty, reason: 'never kept once refused');
    await git.host.secrets.write(git.tokenSecret, token);
    result = await check(hooks(fetch: () async => throw const GitFailure(GitTrouble.noConnection, 'No connection: dns')));
    expect(result.words, contains('couldn’t be reached'));
    result = await check(hooks(adopt: ({required remote, authUser}) async => 'Your Library is inside iCloud Drive, which syncs every file by itself.'));
    expect((result.kind, result.words), (SetupCheckKind.failed, contains('iCloud Drive')));
    expect(gitBackupSetup(hooks: hooks()).ready(), isTrue, reason: 'a token and a remote');
  });
}
