/// The plugin's settings and what it last saw of the repository, kept as one JSON map under the plugin's storage key
/// (manifest.dart [stateKey]) on the device, and the non-secret part of them written into the committed
/// `.glyph/config.json` under `git` (docs/MARKDOWN_FIRST.md §6), so a clone knows its own remote and switches.
///
/// Nothing here is a secret: the token is the secure store's (manifest.dart [tokenSecret]).
library;

import 'dart:convert';
import 'dart:io';

import '../types.dart' show PluginHost;
import 'manifest.dart' as git;

/// The cap on a recording committed, by default: 50 MB (decision 11).
const int recordingsCapDefault = 50 * 1000 * 1000;

/// A push over this is a desktop's to make until resumable uploads exist (the critic's iOS finding): 100 MB.
const int phonePushMost = 100 * 1000 * 1000;

/// A first backup over this asks before it goes (the setup's cost ask): 200 MB.
const int firstBackupAsks = 200 * 1000 * 1000;

class GitBackupSettings {
  const GitBackupSettings({
    this.remote,
    this.branch = 'main',
    this.recordings = false,
    this.recordingsMaxBytes = recordingsCapDefault,
    this.orgsIncluded = const {},
    this.publish = false,
    this.mirror = false,
    this.authUser,
    this.repoPath,
    this.lastCommitAt,
    this.lastPushAt,
    this.lastPushedCommit,
    this.lastFailure,
    this.conflicts = const [],
    this.setUpAt,
  });

  /// The remote's HTTPS address, or null before the setup names one.
  final String? remote;
  final String branch;

  /// Recordings committed (off by default), each under the cap.
  final bool recordings;
  final int recordingsMaxBytes;

  /// The organizations (folder names under `orgs/`) whose notes are committed; the rest are ignored.
  final Set<String> orgsIncluded;

  /// The GitHub Pages workflow committed, so a push publishes (GitHub remotes only).
  final bool publish;

  /// The repository is a mirror under app data, not the Library (an Android SAF tree).
  final bool mirror;

  /// HTTP basic auth's user beside the token: `x-access-token` for GitHub, `oauth2` for GitLab, else what was pasted.
  final String? authUser;

  /// The folder with `.git` in it, as last used.
  final String? repoPath;

  final DateTime? lastCommitAt;
  final DateTime? lastPushAt;
  final String? lastPushedCommit;

  /// The last failure's plain sentence, for the page's red row; null once a backup went through.
  final String? lastFailure;

  /// The conflict copies the last merges wrote, by path, until the person opens or clears them.
  final List<String> conflicts;
  final DateTime? setUpAt;

  bool get configured => remote != null && remote!.isNotEmpty;

  GitBackupSettings copyWith({
    Object? remote = _keep,
    String? branch,
    bool? recordings,
    int? recordingsMaxBytes,
    Set<String>? orgsIncluded,
    bool? publish,
    bool? mirror,
    Object? authUser = _keep,
    Object? repoPath = _keep,
    Object? lastCommitAt = _keep,
    Object? lastPushAt = _keep,
    Object? lastPushedCommit = _keep,
    Object? lastFailure = _keep,
    List<String>? conflicts,
    Object? setUpAt = _keep,
  }) =>
      GitBackupSettings(
        remote: remote == _keep ? this.remote : remote as String?,
        branch: branch ?? this.branch,
        recordings: recordings ?? this.recordings,
        recordingsMaxBytes: recordingsMaxBytes ?? this.recordingsMaxBytes,
        orgsIncluded: orgsIncluded ?? this.orgsIncluded,
        publish: publish ?? this.publish,
        mirror: mirror ?? this.mirror,
        authUser: authUser == _keep ? this.authUser : authUser as String?,
        repoPath: repoPath == _keep ? this.repoPath : repoPath as String?,
        lastCommitAt: lastCommitAt == _keep ? this.lastCommitAt : lastCommitAt as DateTime?,
        lastPushAt: lastPushAt == _keep ? this.lastPushAt : lastPushAt as DateTime?,
        lastPushedCommit: lastPushedCommit == _keep ? this.lastPushedCommit : lastPushedCommit as String?,
        lastFailure: lastFailure == _keep ? this.lastFailure : lastFailure as String?,
        conflicts: conflicts ?? this.conflicts,
        setUpAt: setUpAt == _keep ? this.setUpAt : setUpAt as DateTime?,
      );

  static const Object _keep = Object();

  Map<String, Object?> toJson() => {
        if (remote != null) 'remote': remote,
        'branch': branch,
        'recordings': {'on': recordings, 'maxBytes': recordingsMaxBytes},
        'orgs': {'include': orgsIncluded.toList()..sort()},
        'publish': publish,
        'mirror': mirror,
        if (authUser != null) 'authUser': authUser,
        if (repoPath != null) 'repoPath': repoPath,
        if (lastCommitAt != null) 'lastCommitAt': lastCommitAt!.toUtc().toIso8601String(),
        if (lastPushAt != null) 'lastPushAt': lastPushAt!.toUtc().toIso8601String(),
        if (lastPushedCommit != null) 'lastPushedCommit': lastPushedCommit,
        if (lastFailure != null) 'lastFailure': lastFailure,
        if (conflicts.isNotEmpty) 'conflicts': conflicts,
        if (setUpAt != null) 'setUpAt': setUpAt!.toUtc().toIso8601String(),
      };

  /// The non-secret, non-device part, as `.glyph/config.json` carries it under `git`.
  Map<String, Object?> toConfigJson({required String madeBy}) => {
        if (remote != null) 'remote': remote,
        'branch': branch,
        'recordings': {'on': recordings, 'maxBytes': recordingsMaxBytes},
        'orgs': {'include': orgsIncluded.toList()..sort()},
        'publish': publish,
        'cadence': 'automatic',
        'madeBy': madeBy,
      };

  static GitBackupSettings fromJson(Object? raw) {
    if (raw is! Map) return const GitBackupSettings();
    final recordings = raw['recordings'];
    final orgs = raw['orgs'];
    DateTime? when(Object? value) => value is String ? DateTime.tryParse(value) : null;
    return GitBackupSettings(
      remote: raw['remote'] is String ? raw['remote'] as String : null,
      branch: raw['branch'] is String ? raw['branch'] as String : 'main',
      recordings: recordings is Map && recordings['on'] == true,
      recordingsMaxBytes: recordings is Map && recordings['maxBytes'] is num ? (recordings['maxBytes'] as num).toInt() : recordingsCapDefault,
      orgsIncluded: orgs is Map && orgs['include'] is List ? {for (final each in orgs['include'] as List) if (each is String) each} : const {},
      publish: raw['publish'] == true,
      mirror: raw['mirror'] == true,
      authUser: raw['authUser'] is String ? raw['authUser'] as String : null,
      repoPath: raw['repoPath'] is String ? raw['repoPath'] as String : null,
      lastCommitAt: when(raw['lastCommitAt']),
      lastPushAt: when(raw['lastPushAt']),
      lastPushedCommit: raw['lastPushedCommit'] is String ? raw['lastPushedCommit'] as String : null,
      lastFailure: raw['lastFailure'] is String ? raw['lastFailure'] as String : null,
      conflicts: raw['conflicts'] is List ? [for (final each in raw['conflicts'] as List) if (each is String) each] : const [],
      setUpAt: when(raw['setUpAt']),
    );
  }
}

/// The settings as kept on this device, through the plugin's host.
GitBackupSettings gitBackupSettings([PluginHost? via]) => GitBackupSettings.fromJson((via ?? git.host).storage.get<Object?>(git.stateKey, null));

void setGitBackupSettings(GitBackupSettings settings, [PluginHost? via]) => (via ?? git.host).storage.set(git.stateKey, settings.toJson());

void updateGitBackupSettings(GitBackupSettings Function(GitBackupSettings) change, [PluginHost? via]) => setGitBackupSettings(change(gitBackupSettings(via)), via);

/// Writes the `git` key of `.glyph/config.json` at [repoPath], the other keys kept as they are. A guard refuses a
/// value that looks like a secret (docs/MARKDOWN_FIRST.md §6): there is none in [GitBackupSettings.toConfigJson],
/// and this keeps it so.
void writeGitConfig(String repoPath, GitBackupSettings settings, {required String madeBy}) {
  final file = File('$repoPath/.glyph/config.json');
  Map<String, Object?> config = {'version': 1};
  if (file.existsSync()) {
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is Map) config = parsed.cast<String, Object?>();
    } catch (_) {
      // Rewritten whole below.
    }
  }
  final value = settings.toConfigJson(madeBy: madeBy);
  final text = jsonEncode(value).toLowerCase();
  if (RegExp(r'token|secret|password|webhook').hasMatch(text)) throw StateError('The git settings carry something that looks like a secret; not written to config.json.');
  config['version'] ??= 1;
  config['git'] = value;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(config)}\n');
}

/// The `git` key of `.glyph/config.json` at [repoPath], as settings for a device that has none (a clone).
GitBackupSettings? readGitConfig(String repoPath) {
  final file = File('$repoPath/.glyph/config.json');
  if (!file.existsSync()) return null;
  try {
    final parsed = jsonDecode(file.readAsStringSync());
    if (parsed is! Map || parsed['git'] is! Map) return null;
    return GitBackupSettings.fromJson(parsed['git']);
  } catch (_) {
    return null;
  }
}

/// The git host's name for a remote, in the words the page uses: "GitHub", "GitLab", "Codeberg", "Gitea", or the host.
String remoteHostName(String remote) {
  final host = Uri.tryParse(remote)?.host.toLowerCase() ?? '';
  if (host == 'github.com' || host.endsWith('.github.com')) return 'GitHub';
  if (host == 'gitlab.com' || host.endsWith('.gitlab.com')) return 'GitLab';
  if (host == 'codeberg.org') return 'Codeberg';
  if (host == 'bitbucket.org') return 'Bitbucket';
  return host.isEmpty ? 'the git host' : host;
}

bool isGitHubRemote(String? remote) => remote != null && remoteHostName(remote) == 'GitHub';

/// HTTP basic auth's user for [remote]'s host, where the person pasted none.
String authUserFor(String remote) {
  final name = remoteHostName(remote);
  if (name == 'GitHub') return 'x-access-token';
  if (name == 'GitLab') return 'oauth2';
  return 'git';
}

/// What is wrong with a pasted remote, or null for an HTTPS git address.
String? remoteShape(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 'Paste the repository’s address.';
  if (trimmed.startsWith('git@') || trimmed.startsWith('ssh://')) return 'That is an SSH address. Ghost.md pushes over HTTPS with a token; copy the HTTPS address instead (SSH keys are not in this version).';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return 'That doesn’t look like a repository’s HTTPS address, like https://github.com/you/notes.git.';
  if (uri.pathSegments.where((s) => s.isNotEmpty).isEmpty) return 'The address needs the repository after the host: https://github.com/you/notes.git.';
  return null;
}

/// What is wrong with a pasted token, or null.
String? gitTokenShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the token alone: it has no spaces in it.';
  if (text.length < 8) return 'That token looks cut short. Copy all of it.';
  return null;
}

/// The remote's address with the repository's name alone for a page: `you/notes` for GitHub, the path otherwise.
String remoteShort(String remote) {
  final uri = Uri.tryParse(remote);
  if (uri == null) return remote;
  final path = uri.path.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'\.git$'), '');
  return path.isEmpty ? uri.host : path;
}

/// Where the site the Publish switch makes will be, for a GitHub remote: `https://<owner>.github.io/<repo>/`.
String? pagesSiteFor(String? remote) {
  if (!isGitHubRemote(remote)) return null;
  final parts = remoteShort(remote!).split('/');
  if (parts.length < 2) return null;
  return 'https://${parts[0].toLowerCase()}.github.io/${parts[1]}/';
}
