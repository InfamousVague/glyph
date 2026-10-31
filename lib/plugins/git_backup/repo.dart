/// The core's git, from Dart: one class over the `git_*` commands of native/src/git.rs, each a call with its
/// arguments named, its answer read into a type, and its refusal read into [GitFailure] by the first words of the
/// sentence the core answers with (`No repository:`, `Sign-in refused:`, `Not fast-forward:`, `No connection:`).
///
/// Nothing here knows the Library, the cadence or the account: it is the plumbing backup.dart, merge.dart and
/// restore.dart stand on, and a test opens the core (test/team_sync/support.dart `openCore`) and drives it against a
/// bare repository on disk.
library;

import 'dart:io' show Directory;

import '../../core/native/core.dart';

/// Why git could not do what was asked, by kind, so the page can say the right thing and know whether trying again
/// could help.
enum GitTrouble {
  /// No repository at the path.
  noRepo,

  /// The remote refused the token, or there was none.
  signIn,

  /// The remote's branch has commits this device has not: fetch and merge first.
  notFastForward,

  /// DNS, the connection, TLS, or an HTTP answer that is not a refusal.
  noConnection,

  /// Everything else, said as the core said it.
  other,
}

class GitFailure implements Exception {
  const GitFailure(this.trouble, this.message);

  /// Read from the core's sentence: its first words are the kind.
  factory GitFailure.said(String message) {
    if (message.startsWith('No repository:')) return GitFailure(GitTrouble.noRepo, message);
    if (message.startsWith('Sign-in refused:')) return GitFailure(GitTrouble.signIn, message);
    if (message.startsWith('Not fast-forward:')) return GitFailure(GitTrouble.notFastForward, message);
    if (message.startsWith('No connection:')) return GitFailure(GitTrouble.noConnection, message);
    return GitFailure(GitTrouble.other, message);
  }

  final GitTrouble trouble;
  final String message;

  /// The sentence for a red row: the kind in plain words, the core's detail after it.
  String get plain => switch (trouble) {
        GitTrouble.noRepo => 'There is no repository here yet.',
        GitTrouble.signIn => 'The git host didn’t accept the token.',
        GitTrouble.notFastForward => 'Someone pushed changes this device hasn’t merged yet.',
        GitTrouble.noConnection => 'The git host couldn’t be reached.',
        GitTrouble.other => message,
      };

  @override
  String toString() => message;
}

/// Who a commit is by.
class GitWho {
  const GitWho({required this.name, required this.email});
  final String name;
  final String email;

  Map<String, Object?> toJson() => {'name': name, 'email': email};
}

/// The token a remote takes as HTTP basic auth's password, and the user beside it (GitHub takes any; GitLab wants
/// `oauth2`).
class GitAuth {
  const GitAuth({this.token, this.user});
  final String? token;
  final String? user;

  static const GitAuth none = GitAuth();

  Map<String, Object?> toJson() => {if (token != null) 'token': token, if (user != null) 'user': user};
}

/// One changed file, as the status lists it: `kind` is added, removed, modified, renamed, typechange or conflict.
class GitChange {
  const GitChange(this.path, this.kind, {this.from});
  final String path;
  final String kind;

  /// The old path of a rename, where the diff knows it.
  final String? from;

  static GitChange fromJson(Map<String, Object?> json) => GitChange(json['path'] as String, json['kind'] as String, from: json['from'] as String?);

  @override
  String toString() => '$kind $path';
}

class GitStatus {
  const GitStatus({this.head, required this.branch, this.shallow = false, required this.changes});
  final String? head;
  final String branch;
  final bool shallow;
  final List<GitChange> changes;

  bool get clean => changes.isEmpty;

  static GitStatus fromJson(Map<String, Object?> json) => GitStatus(
        head: json['head'] as String?,
        branch: json['branch'] as String? ?? 'main',
        shallow: json['shallow'] == true,
        changes: [for (final each in (json['changes'] as List?) ?? const []) GitChange.fromJson((each as Map).cast())],
      );
}

/// `main` against `origin/main`, as last fetched: `state` is empty, same, ahead, behind or diverged.
class GitDivergence {
  const GitDivergence({this.local, this.remote, this.base, required this.state, required this.ahead, required this.behind});
  final String? local;
  final String? remote;
  final String? base;
  final String state;
  final int ahead;
  final int behind;

  static GitDivergence fromJson(Map<String, Object?> json) => GitDivergence(
        local: json['local'] as String?,
        remote: json['remote'] as String?,
        base: json['base'] as String?,
        state: json['state'] as String? ?? 'empty',
        ahead: (json['ahead'] as num?)?.toInt() ?? 0,
        behind: (json['behind'] as num?)?.toInt() ?? 0,
      );
}

class GitCommitInfo {
  const GitCommitInfo({required this.id, required this.time, required this.message, required this.name});
  final String id;
  final DateTime time;
  final String message;
  final String name;

  static GitCommitInfo fromJson(Map<String, Object?> json) => GitCommitInfo(
        id: json['id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(((json['time'] as num?)?.toInt() ?? 0) * 1000, isUtc: true),
        message: json['message'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class GitPushed {
  const GitPushed({this.old, required this.now, required this.upToDate});
  final String? old;
  final String now;
  final bool upToDate;

  static GitPushed fromJson(Map<String, Object?> json) => GitPushed(old: json['old'] as String?, now: json['new'] as String, upToDate: json['upToDate'] == true);
}

/// A file's three texts for a merge: at the merge base, at `main` and at `origin/main`; null where that commit has
/// no such file.
class GitThreeWay {
  const GitThreeWay({this.base, this.ours, this.theirs});
  final String? base;
  final String? ours;
  final String? theirs;
}

/// A repository on disk, driven through the core's `git_*` commands.
class GitRepo {
  const GitRepo(this.invoke, this.path);

  final CoreInvoke invoke;

  /// The folder with `.git` in it.
  final String path;

  Future<Object?> _call(String command, Map<String, Object?> args) async {
    try {
      return await invoke(command, {'repo': path, ...args});
    } on CoreError catch (error) {
      throw GitFailure.said(error.message);
    }
  }

  static Map<String, Object?> _map(Object? answer) => (answer as Map).cast<String, Object?>();

  /// A repository at [path], made if there was none: true when one was made.
  Future<bool> init() async => _map(await _call('git_init', const {}))['created'] == true;

  /// Whether a repository is there at all.
  Future<bool> exists() async {
    try {
      await status();
      return true;
    } on GitFailure catch (failure) {
      if (failure.trouble == GitTrouble.noRepo) return false;
      rethrow;
    }
  }

  Future<GitStatus> status() async => GitStatus.fromJson(_map(await _call('git_status', const {})));

  /// A commit of everything in the folder, the [keep] folders as HEAD has them (`orgs/Acme`: an organization left
  /// out stays as the repository last had it); null when nothing changed and there is no merge to record.
  Future<String?> commit(String message, GitWho who, {String? alsoParent, List<String> keep = const []}) async {
    final answer = _map(await _call('git_commit', {'message': message, 'author': who.toJson(), 'alsoParent': ?alsoParent, if (keep.isNotEmpty) 'keep': keep}));
    return answer['id'] as String?;
  }

  Future<void> setRemote(String url) => _call('git_remote_set', {'url': url});

  Future<String?> remote() async {
    final answer = await _call('git_remote', const {});
    return answer == null ? null : _map(answer)['url'] as String?;
  }

  Future<GitDivergence> fetch(GitAuth auth, {bool deepen = false}) async => GitDivergence.fromJson(_map(await _call('git_fetch', {...auth.toJson(), if (deepen) 'deepen': true})));

  Future<GitDivergence> divergence() async => GitDivergence.fromJson(_map(await _call('git_divergence', const {})));

  Future<GitPushed> push(GitAuth auth) async => GitPushed.fromJson(_map(await _call('git_push', auth.toJson())));

  Future<String?> mergeBase(String a, String b) async => await _call('git_merge_base', {'a': a, 'b': b}) as String?;

  Future<String?> blob(String commit, String path) async => await _call('git_blob', {'commit': commit, 'path': path}) as String?;

  Future<GitThreeWay> threeWay(String path) async {
    final answer = _map(await _call('git_three_way', {'path': path}));
    return GitThreeWay(base: answer['base'] as String?, ours: answer['ours'] as String?, theirs: answer['theirs'] as String?);
  }

  Future<List<GitCommitInfo>> log({int count = 20}) async => [for (final each in (await _call('git_log', {'count': count}) as List)) GitCommitInfo.fromJson((each as Map).cast())];

  /// What [to]'s tree has over [from]'s; everything, as added, when [from] is null.
  Future<List<GitChange>> diff({String? from, required String to}) async => [for (final each in (await _call('git_diff', {'from': ?from, 'to': to}) as List)) GitChange.fromJson((each as Map).cast())];

  /// The file's bytes at [commit] written to [into]; how many, or null where the commit has no such file.
  Future<int?> writeBlob(String commit, String path, String into) async {
    final answer = await _call('git_write_blob', {'commit': commit, 'path': path, 'into': into});
    return answer == null ? null : (_map(answer)['bytes'] as num).toInt();
  }

  /// A clone of [url] into [into], checked out, shallow (depth 1) when asked: the HEAD commit and how many files.
  static Future<({String? head, int files})> clone(CoreInvoke invoke, {required String url, required String into, GitAuth auth = GitAuth.none, bool shallow = false}) async {
    // gix makes the folder, not its parents.
    Directory(into).parent.createSync(recursive: true);
    try {
      final answer = _map(await invoke('git_clone', {'url': url, 'into': into, ...auth.toJson(), 'shallow': shallow}));
      return (head: answer['head'] as String?, files: (answer['files'] as num?)?.toInt() ?? 0);
    } on CoreError catch (error) {
      throw GitFailure.said(error.message);
    }
  }
}
