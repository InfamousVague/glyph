/// GitHub's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest
/// of the plugins"). Lovart's shape, in GitHub's indigo, over the token the plugin's page keeps (repos.dart):
///
/// 1. **Notes linked to repos**: what it does: a repo read for context on the phone, and list items sent as issues.
///    Public repos are read without a token; issues and private repos need one.
/// 2. **A GitHub account**: github.com's sign-up ([githubSignUpUrl]), in Advanced only, since nearly everyone setting
///    this up has one.
/// 3. **Make a token**: GitHub's page for a new fine-grained token ([githubTokenUrl]), with Issues read and write and
///    Contents read only, for the repos to link; the classic tokens' page beside it ([githubClassicTokensUrl]).
///    Neither address was opened while this was written (unverified).
/// 4. **Paste your token**: its shape checked ([githubTokenShape]), then kept where the page keeps it
///    ([setGithubToken]: the secure store's [tokenSecret], sealed to the account's other devices).
/// 5. **Check it works**: `GET /user` ([githubLogin]), which changes nothing, said in plain words
///    ([githubSetupResult]): the login it belongs to; a 401 let go of, as a refused key is everywhere in the setups;
///    no connection.
/// 6. **Try it**: a repo linked to a note from its cog.
library;

import '../../art/lucide.g.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import 'manifest.dart' show GithubFailure;
import 'repos.dart';

/// GitHub's sign-up (unverified).
const String githubSignUpUrl = 'https://github.com/signup';

/// GitHub's page for a new fine-grained personal access token (unverified).
const String githubTokenUrl = 'https://github.com/settings/personal-access-tokens/new';

/// GitHub's classic tokens (unverified).
const String githubClassicTokensUrl = 'https://github.com/settings/tokens';

/// What is wrong with the shape of a pasted token, or null where it looks like one: a fine-grained `github_pat_…`, or
/// a classic `ghp_…` (GitHub's other `gh?_` kinds are let through to the check).
String? githubTokenShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the token alone: it has no spaces in it.';
  if (!text.startsWith('github_pat_') && !RegExp(r'^gh[a-z]_').hasMatch(text)) return 'That doesn’t look like a GitHub token. Those start with github_pat_ or ghp_.';
  if (text.length < 20) return 'That token looks cut short. Copy all of it from GitHub.';
  return null;
}

/// The check's answer (see the header). [login] asks GitHub whose the kept token is; [githubLogin] where null.
Future<SetupResult> githubSetupResult({Future<String> Function()? login}) async {
  if (githubToken().isEmpty) return const SetupResult.failed('No token is kept yet. Paste it first.', pasteAgain: true);
  try {
    final name = await (login ?? githubLogin)();
    return SetupResult.ok(name.isEmpty ? 'Your token works.' : 'Your token works. It is $name’s.');
  } on GithubFailure catch (failure) {
    if (failure.status == 401) {
      // Never kept once refused.
      await setGithubToken('');
      return const SetupResult.failed('GitHub didn’t accept that token. Copy it again from GitHub: all of it, from github_pat_ to the end.', pasteAgain: true);
    }
    return SetupResult.failed(failure.message);
  } catch (_) {
    return const SetupResult.failed('GitHub couldn’t be reached. Check the connection, then check again.');
  }
}

/// GitHub's setup (see the header).
PluginSetup githubSetup({Future<String> Function()? login}) => PluginSetup(
      id: 'github',
      name: 'GitHub',
      hues: const ['indigo', 'purple', 'blue'],
      tiles: const [Lucide.gitBranch, Lucide.listChecks, Lucide.keyRound, Lucide.link],
      ready: () => githubToken().isNotEmpty,
      watch: onPluginStorage,
      prepare: warmGithub,
      about: 'A few short steps: a token from GitHub, and a check that it works.',
      again: 'The steps from the start: the token, and a check that it works.',
      steps: [
        const SetupIntro(
          id: 'intro',
          title: 'Notes linked to repos',
          icon: Lucide.gitBranch,
          mark: false,
          points: [
            (Lucide.link, 'Link a note to a repo, from the cog on the note'),
            (Lucide.listChecks, 'Its list items become issues, ticked off from either side'),
            (Lucide.bookOpen, 'The repo read on your phone, so its names come out right as the note is formatted'),
            (Lucide.keyRound, 'Public repos need no token; issues and private repos do'),
          ],
        ),
        const SetupOpen(id: 'account', title: 'A GitHub account', icon: Lucide.userPlus, advanced: true, links: [SetupLink('Open GitHub', githubSignUpUrl, verified: false)]),
        const SetupOpen(
          id: 'key',
          title: 'Make a token',
          icon: Lucide.keyRound,
          links: [SetupLink('Make a token', githubTokenUrl, verified: false), SetupLink('Classic tokens', githubClassicTokensUrl, verified: false)],
        ),
        SetupPaste(
          id: 'paste',
          title: 'Paste your token',
          icon: Lucide.clipboardPaste,
          fields: const [SetupField(id: 'token', label: 'Token', placeholder: 'github_pat_…', shape: githubTokenShape)],
          save: (values) async {
            await setGithubToken(values['token']!);
            return null;
          },
        ),
        SetupCheck(id: 'check', title: 'Check it works', icon: Lucide.shieldCheck, checking: 'Asking GitHub…', run: () => githubSetupResult(login: login)),
        const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
      ],
    );
