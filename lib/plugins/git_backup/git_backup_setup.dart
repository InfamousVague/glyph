/// The plugin's setup (lib/plugins/onboarding/setup_flow.dart), voiced under `git-backup-*`:
///
/// 1. **Your notes, in a repository you own**: what and why, and the plaintext warning: the repository is readable by
///    whoever can read it, so make it private.
/// 2. **Make a token**: the GitHub page for a new fine-grained token with Contents read and write on the repository
///    ([githubTokenUrl]); other hosts' token pages beside it. In Advanced, "Use my GitHub token" takes the GitHub
///    plugin's where it may push ([reuseGithubToken]).
/// 3. **Paste your token**: kept in the secure store ([git.tokenSecret]), sealed to the account's other devices.
/// 4. **Make the repository**: "Create a private repository on GitHub" with the token ([GitHubApi.createRepository]),
///    or skip to paste an address.
/// 5. **The repository's address**: pasted (optional where step 4 made one), its shape checked ([remoteShape]).
/// 6. **Check it works**: the repository made where the Library is (or refused in a plain sentence: iCloud Drive, a
///    syncing folder), the remote fetched with the token, and the library's size said, with the cost ask over 200 MB.
/// 7. **First backup**: Back up now, with the recordings switch's state said.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../art/art.dart' show AppIcon;
import '../../art/lucide.g.dart';
import '../../settings/kit/settings_kit.dart';
import '../github/repos.dart' as github_plugin show githubToken;
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import '../types.dart' show PluginHost;
import 'backup.dart' show BackupOutcome;
import 'files.dart';
import 'github_api.dart';
import 'manifest.dart' as git;
import 'repo.dart';
import 'service.dart';
import 'settings.dart';

/// GitHub's page for a new fine-grained personal access token (unverified).
const String githubTokenUrl = 'https://github.com/settings/personal-access-tokens/new';

/// GitLab's personal access tokens (unverified).
const String gitlabTokenUrl = 'https://gitlab.com/-/user_settings/personal_access_tokens';

/// Codeberg's access tokens (unverified).
const String codebergTokenUrl = 'https://codeberg.org/user/settings/applications';

/// What the setup needs of the app, so a test can hand in its own: the service's parts, by function.
class GitBackupSetupHooks {
  GitBackupSetupHooks({
    PluginHost? via,
    Future<String?> Function({required String remote, String? authUser})? adopt,
    Future<RepoSizes?> Function()? sizes,
    Future<GitDivergence> Function()? fetch,
    GitHubApi? github,
    String Function()? githubPluginToken,
    Future<BackupOutcome> Function()? backUpNow,
  })  : via = via ?? git.host,
        _adopt = adopt,
        _sizes = sizes,
        _fetch = fetch,
        github = github ?? GitHubApi(via: via),
        githubPluginToken = githubPluginToken ?? github_plugin.githubToken,
        _backUpNow = backUpNow;

  final PluginHost via;
  final Future<String?> Function({required String remote, String? authUser})? _adopt;
  final Future<RepoSizes?> Function()? _sizes;
  final Future<GitDivergence> Function()? _fetch;
  final GitHubApi github;
  final String Function() githubPluginToken;
  final Future<BackupOutcome> Function()? _backUpNow;

  GitBackupService? get _service => GitBackupService.current;

  Future<String?> adopt({required String remote, String? authUser}) async {
    if (_adopt != null) return _adopt(remote: remote, authUser: authUser);
    final service = _service;
    if (service == null) return 'Backing up to git isn’t available in this build.';
    return service.adopt(remote: remote, authUser: authUser);
  }

  Future<RepoSizes?> sizes() async {
    if (_sizes != null) return _sizes();
    final service = _service;
    if (service == null) return null;
    return (await service.backup.status(sizes: true)).sizes;
  }

  Future<GitDivergence> fetch() async {
    if (_fetch != null) return _fetch();
    final service = _service;
    if (service == null) throw const GitFailure(GitTrouble.other, 'Backing up to git isn’t available in this build.');
    final where = await service.place();
    if (where == null) throw const GitFailure(GitTrouble.noRepo, 'No repository: there is nowhere to keep one here.');
    return GitRepo(service.invoke, where.path).fetch(await service.auth());
  }

  Future<BackupOutcome> backUpNow() async {
    if (_backUpNow != null) return _backUpNow();
    final service = _service;
    if (service == null) return const BackupOutcome(skipped: 'not available');
    return service.backup.backUpNow(personStarted: true);
  }
}

/// The kept token, or empty.
String gitToken([PluginHost? via]) => (via ?? git.host).secrets.held(git.tokenSecret) ?? '';

/// The GitHub plugin's token, where it may push: kept as this plugin's own, or a sentence saying why not.
Future<String?> reuseGithubToken(GitBackupSetupHooks on) async {
  final token = on.githubPluginToken();
  if (token.isEmpty) return 'The GitHub plugin has no token kept. Paste one here instead.';
  try {
    final scopes = await on.github.tokenScopes(token);
    if (scopes.mayPush == false) return 'The GitHub plugin’s token may not write to repositories (it has ${scopes.scopes.isEmpty ? 'no' : 'only the ${scopes.scopes.join(', ')}'} scope). Make a token with Contents read and write, and paste it here.';
    await on.via.secrets.write(git.tokenSecret, token);
    return null;
  } on GitHubRefusal catch (refusal) {
    return refusal.message;
  } catch (_) {
    return 'GitHub couldn’t be reached. Check the connection, then try again.';
  }
}

/// The check's answer (see the header, step 6).
Future<SetupResult> gitBackupSetupResult(GitBackupSetupHooks on) async {
  final settings = gitBackupSettings(on.via);
  if (gitToken(on.via).isEmpty) return const SetupResult.failed('No token is kept yet. Paste it first.', pasteAgain: true);
  final remote = settings.remote;
  if (remote == null || remote.isEmpty) return const SetupResult.failed('No repository address is kept yet. Paste it, or make one.', pasteAgain: true);
  final refusal = await on.adopt(remote: remote, authUser: settings.authUser);
  if (refusal != null) return SetupResult.failed(refusal);
  try {
    final divergence = await on.fetch();
    final sizes = await on.sizes();
    final size = sizes?.committed.bytes ?? 0;
    final words = StringBuffer();
    words.write(divergence.remote == null ? 'The repository is reachable and empty, ready for the first backup.' : 'The repository is reachable and already has a backup in it; the first push merges yours with it.');
    if (sizes != null) {
      words.write(' Your library is ${sizeWords(size)} in ${sizes.committed.files} files');
      if (sizes.recordings.bytes > 0 && !settings.recordings) words.write('; recordings (${sizeWords(sizes.recordings.bytes)}) are left out until you switch them on');
      if (sizes.orgsExcluded.bytes > 0) words.write('; organizations’ notes (${sizeWords(sizes.orgsExcluded.bytes)}) are left out until each is switched on');
      words.write('.');
    }
    if (size > firstBackupAsks) return SetupResult.warn('$words The first push is over ${sizeWords(firstBackupAsks)}: on a phone it waits for Wi-Fi and may take a while, and the host may count it against your storage. Back up now when you are ready.');
    return SetupResult.ok(words.toString());
  } on GitFailure catch (failure) {
    switch (failure.trouble) {
      case GitTrouble.signIn:
        await on.via.secrets.write(git.tokenSecret, null);
        return const SetupResult.failed('The git host didn’t accept that token. Copy it again, all of it, and make sure it may read and write this repository.', pasteAgain: true);
      case GitTrouble.noConnection:
        return const SetupResult.failed('The git host couldn’t be reached. Check the connection and the address, then check again.');
      case GitTrouble.noRepo:
      case GitTrouble.notFastForward:
      case GitTrouble.other:
        return SetupResult.failed(failure.plain);
    }
  } catch (failure) {
    return SetupResult.failed('The check failed: $failure');
  }
}

/// The setup (see the header). [hooks] are a test's own; the app's reach the service.
PluginSetup gitBackupSetup({GitBackupSetupHooks? hooks}) {
  final on = hooks ?? GitBackupSetupHooks();
  return PluginSetup(
    id: 'git-backup',
    name: 'Back up to git',
    hues: const ['green', 'mint', 'lime'],
    tiles: const [Lucide.gitBranch, Lucide.hardDriveUpload, Lucide.history, Lucide.lock],
    ready: () => gitToken(on.via).isNotEmpty && gitBackupSettings(on.via).configured,
    watch: onPluginStorage,
    prepare: on.via.secrets.warm,
    about: 'A few short steps: a token from your git host, a repository, and a check that it works.',
    again: 'The steps from the start: the token, the repository, and a check that it works.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Your notes, in a repository you own',
        icon: Lucide.gitBranch,
        points: [
          (Lucide.history, 'Every note and its history committed two minutes after your last change, and pushed'),
          (Lucide.hardDriveUpload, 'GitHub, GitLab, Codeberg, Gitea or your own git host, over HTTPS with a token'),
          (Lucide.hardDriveDownload, 'A fresh device opens the library again by cloning it: Open library from git'),
          (Lucide.lock, 'The repository is plain text: anyone who can read it can read your notes. Make it private.'),
        ],
      ),
      const SetupOpen(
        id: 'token',
        title: 'Make a token',
        icon: Lucide.keyRound,
        links: [SetupLink('GitHub: new fine-grained token', githubTokenUrl, verified: false), SetupLink('GitLab tokens', gitlabTokenUrl, verified: false), SetupLink('Codeberg tokens', codebergTokenUrl, verified: false)],
      ),
      SetupAct(id: 'reuse', title: 'Use my GitHub token', icon: Lucide.keyRound, advanced: true, label: 'Use the GitHub plugin’s token', again: 'Try the GitHub token again', onward: true, run: () => reuseGithubToken(on)),
      SetupPaste(
        id: 'paste',
        title: 'Paste your token',
        icon: Lucide.clipboardPaste,
        fields: const [SetupField(id: 'token', label: 'Token', placeholder: 'github_pat_…', shape: gitTokenShape)],
        save: (values) async {
          await on.via.secrets.write(git.tokenSecret, values['token']);
          return null;
        },
      ),
      SetupAct(
        id: 'create',
        title: 'Make the repository',
        icon: Lucide.folderPlus,
        label: 'Create a private repository on GitHub',
        again: 'Create it again',
        onward: true,
        run: () async {
          final token = gitToken(on.via);
          if (token.isEmpty) return 'Paste a token first.';
          try {
            final url = await on.github.createRepository(token, name: 'ghost-notes');
            updateGitBackupSettings((s) => s.copyWith(remote: url, authUser: authUserFor(url)), on.via);
            return null;
          } on GitHubRefusal catch (refusal) {
            return refusal.status == 422 ? 'GitHub says a repository named ghost-notes is there already. Paste its address on the next step instead.' : refusal.message;
          } catch (_) {
            return 'GitHub couldn’t be reached. Check the connection, then try again, or paste an address on the next step.';
          }
        },
      ),
      SetupPaste(
        id: 'repository',
        title: 'The repository’s address',
        icon: Lucide.link,
        fields: const [SetupField(id: 'remote', label: 'HTTPS address', placeholder: 'https://github.com/you/notes.git', shape: remoteShape, optional: true, secret: false)],
        save: (values) async {
          final remote = (values['remote'] ?? '').trim();
          if (remote.isEmpty) return gitBackupSettings(on.via).configured ? null : 'Paste the repository’s HTTPS address, or go back and make one.';
          updateGitBackupSettings((s) => s.copyWith(remote: remote, authUser: authUserFor(remote)), on.via);
          return null;
        },
      ),
      SetupCheck(id: 'check', title: 'Check it works', icon: Lucide.shieldCheck, checking: 'Asking the git host…', run: () => gitBackupSetupResult(on)),
      SetupDone(id: 'done', title: 'First backup', icon: Lucide.hardDriveUpload, body: (context, simple) => _FirstBackup(on: on)),
    ],
  );
}

/// The last step's body: Back up now, and what the recordings switch says.
class _FirstBackup extends StatefulWidget {
  const _FirstBackup({required this.on});
  final GitBackupSetupHooks on;

  @override
  State<_FirstBackup> createState() => _FirstBackupState();
}

class _FirstBackupState extends State<_FirstBackup> {
  bool _running = false;
  String? _said;

  Future<void> _go() async {
    setState(() => _running = true);
    final outcome = await widget.on.backUpNow();
    if (!mounted) return;
    setState(() {
      _running = false;
      _said = outcome.failure != null ? outcome.failure!.plain : (outcome.pushed ? 'Backed up.' : (outcome.committed != null ? 'Committed; it pushes when you are online.' : 'Nothing to back up yet.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = gitBackupSettings(widget.on.via);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingRow(
          key: const ValueKey('git-backup-first'),
          icon: const AppIcon(Lucide.hardDriveUpload, size: 16),
          label: 'Back up now',
          hint: Text(_said ?? (settings.recordings ? 'Recordings are included, each under ${sizeWords(settings.recordingsMaxBytes)}.' : 'Recordings are left out; the switch is on the plugin’s page.')),
          value: RowAction(onPress: () => unawaited(_go()), disabled: _running, child: Text(_running ? 'Backing up…' : 'Back up')),
        ),
      ],
    );
  }
}
