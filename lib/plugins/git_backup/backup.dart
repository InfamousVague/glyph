/// The backup itself: when a commit happens, what goes in it, and the push after it (docs/GIT_BACKUP.md; the design
/// is docs/MARKDOWN_FIRST.md §10 with Matt's decisions of 2026-10-31 in §11).
///
/// **Cadence.** [GitBackup.changed] is told of every change to the library (the root hands it the library's
/// `touched`); a commit follows two minutes of quiet ([quiet]), with a floor of one commit an hour ([floor]) while
/// anything waits, and Back up now ([backUpNow]) at any time. One commit a quiet spell, never one a keystroke. On an
/// iPhone, where the app is suspended as soon as it is behind another, a commit and push run only in the foreground
/// ([foregroundOnly]: whatever waited runs on resume, [resumed]).
///
/// **A commit** (`_commit`): the generated files are written first (`.gitignore` from the switches, `README.txt`,
/// the `git` key of `.glyph/config.json`, the Pages workflow when Publish is on), the attachments brought in
/// (files.dart `AttachmentMap`, the ones over the cap named), a mirror written from the library where the
/// repository is one (place.dart); then `git_status` says what changed and `git_commit` takes it with a message from
/// messages.dart. The author is the account's handle (its mail `handle@users.ghostmarkdown.com`), or `Ghost.md` with
/// `ghost@localhost` signed out. Organizations not included are `keep` folders: as the repository last had them,
/// never deleted by a device that leaves them out.
///
/// **A push** (`_push`): only the device holding the pusher claim (claim.dart) pushes; the others commit locally and
/// show who is backing up. Before each push a fetch; where the remote moved, the merge (merge.dart), its commit with
/// two parents, and the library told to read again; then the push. Never a force push. A phone does not push more
/// than [phonePushMost] (settings.dart): that is a desktop's to do, and the page says so.
///
/// **The record.** Each commit-and-push is a job on the activity record (lib/core/background_jobs.dart), kind sync,
/// with the plugin's glyph; a failure is a red row with Retry and a plain cause (the git host refused the token, not
/// fast-forward, no connection, repository too large, a file too large). On Android the push holds the device
/// through the foreground service while it runs ([background]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/background_jobs.dart';
import '../../core/library.dart' show NoteLibrary;
import '../../core/native/core.dart' show CoreInvoke;
import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import '../types.dart' show PluginHost;
import 'claim.dart';
import 'files.dart';
import 'manifest.dart' as git;
import 'merge.dart';
import 'messages.dart';
import 'place.dart';
import 'repo.dart';
import 'settings.dart';

/// The job's id on the activity record.
const String backupJobId = 'git-backup';

/// How quiet the library must be before a commit.
const Duration quiet = Duration(minutes: 2);

/// The longest anything waits uncommitted while the device is awake.
const Duration floor = Duration(hours: 1);

/// What one run did.
class BackupOutcome {
  const BackupOutcome({this.committed, this.pushed = false, this.merged = 0, this.conflicts = const [], this.refused = const [], this.failure, this.elsewhere, this.skipped});

  /// The commit's id, or null when nothing changed.
  final String? committed;
  final bool pushed;

  /// How many of the remote's commits were merged in before the push.
  final int merged;

  /// The conflict copies the merge wrote, by path.
  final List<String> conflicts;

  /// Files not committed for their size.
  final List<String> refused;
  final GitFailure? failure;

  /// The device that holds the pusher claim, when it is not this one.
  final PusherClaim? elsewhere;

  /// Why nothing ran: not set up, nothing to do, waiting for the foreground.
  final String? skipped;

  bool get ok => failure == null;

  @override
  String toString() => 'committed $committed, pushed $pushed, merged $merged, conflicts $conflicts, refused $refused, failure ${failure?.message}, skipped $skipped';
}

/// What the page shows of the repository now.
class GitBackupStatus {
  const GitBackupStatus({required this.settings, this.place, this.head, this.lastCommit, this.divergence, this.changes = 0, this.sizes, this.elsewhere, this.shallow = false});
  final GitBackupSettings settings;
  final RepoPlace? place;
  final String? head;
  final GitCommitInfo? lastCommit;
  final GitDivergence? divergence;

  /// Files changed since the last commit.
  final int changes;
  final RepoSizes? sizes;
  final PusherClaim? elsewhere;
  final bool shallow;
}

class GitBackup extends ChangeNotifier {
  GitBackup({
    required this.invoke,
    required this.place,
    PluginHost? via,
    required this.handle,
    required this.holdsPusher,
    this.pusherElsewhere,
    Future<GitAuth> Function()? auth,
    NoteLibrary? library,
    this.appData,
    this.isPhone = false,
    this.foregroundOnly = false,
    bool Function()? inForeground,
    this.background = const NoBackgroundJobs(),
    Activity? activity,
    DateTime Function()? clock,
    this.quietFor = quiet,
    this.floorAt = floor,
    this.freshId,
    this.onOpenConflicts,
    void Function(String)? warn,
  })  : via = via ?? git.host,
        _auth = auth,
        _library = library,
        _inForeground = inForeground ?? (() => true),
        _activity = activity,
        clock = clock ?? DateTime.now,
        warn = warn ?? debugPrint;

  final CoreInvoke invoke;

  /// Where the repository is, asked each run (the Library can move); null where the plugin has nowhere to work.
  final Future<RepoPlace?> Function() place;
  final PluginHost via;

  /// The account's handle, or empty signed out.
  final String Function() handle;

  /// Whether this device pushes (claim.dart `PusherClaims.holds`).
  final Future<bool> Function() holdsPusher;
  final PusherClaim? Function()? pusherElsewhere;
  final Future<GitAuth> Function()? _auth;
  final NoteLibrary? _library;

  /// The app's data folder, where attachments still live (files.dart); null where there is none to map.
  final String? appData;
  final bool isPhone;
  final bool foregroundOnly;
  final bool Function() _inForeground;
  final BackgroundJobs background;
  final Activity? _activity;
  final DateTime Function() clock;
  final Duration quietFor;
  final Duration floorAt;
  final String Function()? freshId;

  /// Opens the conflict copies for the person (the page's Open), from the job's row.
  final VoidCallback? onOpenConflicts;
  final void Function(String) warn;

  Activity get _record => _activity ?? activity;

  Timer? _quietTimer;
  Timer? _floorTimer;
  bool _pending = false;
  bool _running = false;
  bool _waitingForForeground = false;
  BackupOutcome? _last;

  /// What the last run did.
  BackupOutcome? get last => _last;
  bool get running => _running;
  bool get pending => _pending;

  /// Whether the plugin has a repository to work on at all.
  bool get configured => gitBackupSettings(via).configured || gitBackupSettings(via).repoPath != null;

  /// A change to the library: the quiet timer is armed afresh, the floor timer once.
  void changed() {
    if (!configured) return;
    _pending = true;
    _quietTimer?.cancel();
    _quietTimer = Timer(quietFor, () => unawaited(_tick('quiet')));
    _floorTimer ??= Timer(floorAt, () => unawaited(_tick('floor')));
    notifyListeners();
  }

  /// The app came to the front (iPhone): whatever waited runs now.
  void resumed() {
    if (_waitingForForeground) {
      _waitingForForeground = false;
      unawaited(_tick('resumed'));
    }
  }

  Future<void> _tick(String why) async {
    if (!_pending || _running) return;
    if (foregroundOnly && !_inForeground()) {
      _waitingForForeground = true;
      return;
    }
    await backUpNow(why: why);
  }

  void _disarm() {
    _quietTimer?.cancel();
    _quietTimer = null;
    _floorTimer?.cancel();
    _floorTimer = null;
    _pending = false;
  }

  @override
  void dispose() {
    _disarm();
    super.dispose();
  }

  GitWho _who() {
    final name = handle();
    return name.isEmpty ? const GitWho(name: 'Ghost.md', email: 'ghost@localhost') : GitWho(name: name, email: '$name@users.ghostmarkdown.com');
  }

  Future<GitAuth> _authFor(GitBackupSettings settings) async {
    final auth = _auth;
    if (auth != null) return auth();
    final token = await via.secrets.read(git.tokenSecret);
    if (token == null || token.isEmpty) return GitAuth.none;
    return GitAuth(token: token, user: settings.authUser ?? (settings.remote == null ? null : authUserFor(settings.remote!)));
  }

  String? _titleOf(String path) {
    final library = _library;
    if (library == null) return null;
    for (final note in library.value) {
      if (note.path == path) return noteTitle(note.body);
    }
    return null;
  }

  /// The commit and the push, now (see the header). [personStarted] is Back up now: the job shows at once.
  Future<BackupOutcome> backUpNow({bool personStarted = false, String why = 'now'}) async {
    if (_running) return _last ?? const BackupOutcome(skipped: 'already running');
    _running = true;
    _disarm();
    notifyListeners();
    JobHandle? job;
    try {
      final where = await place();
      var settings = gitBackupSettings(via);
      if (where == null) return _last = const BackupOutcome(skipped: 'nowhere to keep a repository');
      final repo = GitRepo(invoke, where.path);
      if (!await repo.exists()) {
        if (!settings.configured) return _last = const BackupOutcome(skipped: 'not set up');
        await repo.init();
      }
      if (settings.repoPath != where.path || settings.mirror != where.isMirror) {
        settings = settings.copyWith(repoPath: where.path, mirror: where.isMirror);
        setGitBackupSettings(settings, via);
      }
      job = _record.begin(backupJobId, kind: JobKind.sync, title: 'Backing up to git', line: 'Looking for changes', personStarted: personStarted, plugin: git.manifest.id, showAfter: personStarted ? null : const Duration(seconds: 1));
      final outcome = await _run(repo, where, settings, job);
      _last = outcome;
      if (outcome.failure != null) {
        final failure = outcome.failure!;
        job.failed(failure.plain, fix: failure.trouble == GitTrouble.signIn ? activityRoutes.signIn(git.manifest.id) : JobFix(JobFixKind.retry, () => unawaited(backUpNow(personStarted: true))));
        updateGitBackupSettings((s) => s.copyWith(lastFailure: failure.plain), via);
      } else if (outcome.committed == null && !outcome.pushed) {
        job.done(result: JobResult(outcome.elsewhere != null ? 'Up to date here; ${outcome.elsewhere!.name ?? 'another device'} pushes' : 'Nothing to back up'), quiet: !personStarted);
        updateGitBackupSettings((s) => s.copyWith(lastFailure: null), via);
      } else {
        final words = StringBuffer(outcome.pushed ? 'Backed up' : 'Committed');
        if (outcome.merged > 0) words.write(', ${outcome.merged} ${outcome.merged == 1 ? 'commit' : 'commits'} merged in');
        if (outcome.conflicts.isNotEmpty) words.write(', ${outcome.conflicts.length} ${outcome.conflicts.length == 1 ? 'conflict copy' : 'conflict copies'}');
        if (outcome.refused.isNotEmpty) words.write('; ${outcome.refused.length} ${outcome.refused.length == 1 ? 'file' : 'files'} over the size cap left out');
        job.done(result: JobResult(words.toString(), action: 'Open', onOpen: outcome.conflicts.isNotEmpty ? onOpenConflicts : null), tally: const JobTally('backup', 'backups'), quiet: !personStarted && outcome.conflicts.isEmpty);
        updateGitBackupSettings((s) => s.copyWith(lastFailure: null, conflicts: [...s.conflicts, ...outcome.conflicts]), via);
      }
      return outcome;
    } catch (failure, stack) {
      warn('[git-backup] $failure\n$stack');
      final said = failure is GitFailure ? failure : GitFailure(GitTrouble.other, failure.toString());
      job?.failed(said.plain, fix: JobFix(JobFixKind.retry, () => unawaited(backUpNow(personStarted: true))));
      updateGitBackupSettings((s) => s.copyWith(lastFailure: said.plain), via);
      return _last = BackupOutcome(failure: said);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<BackupOutcome> _run(GitRepo repo, RepoPlace where, GitBackupSettings settings, JobHandle job) async {
    // The generated files, the attachments, the mirror.
    final orgs = orgFoldersAt(where.path);
    _writeGenerated(where, settings, orgs);
    final refused = AttachmentMap(repoPath: where.path, appData: appData).bring(settings);
    if (where.isMirror) {
      final library = _library;
      if (library != null) writeMirror(where.path, library.value);
    }
    final keep = [for (final org in orgs) if (!settings.orgsIncluded.contains(org)) 'orgs/$org'];

    // The commit.
    job.progress(line: 'Committing');
    final status = await repo.status();
    String? committed;
    if (status.changes.isNotEmpty) {
      committed = await repo.commit(commitMessage(status.changes, titleOf: _titleOf), _who(), keep: keep);
      if (committed != null) updateGitBackupSettings((s) => s.copyWith(lastCommitAt: clock()), via);
    }

    // The push.
    if (!settings.configured) return BackupOutcome(committed: committed, refused: refused);
    final remote = await repo.remote();
    if (remote != settings.remote) await repo.setRemote(settings.remote!);
    if (!await holdsPusher()) return BackupOutcome(committed: committed, refused: refused, elsewhere: pusherElsewhere?.call());
    final auth = await _authFor(settings);
    job.progress(line: 'Fetching');
    var divergence = await repo.fetch(auth);
    if (divergence.state == 'same' || (divergence.state == 'empty')) {
      return BackupOutcome(committed: committed, refused: refused, pushed: false);
    }
    var merged = 0;
    var conflicts = const <String>[];
    if (divergence.state == 'behind' || divergence.state == 'diverged') {
      job.progress(line: 'Merging ${divergence.behind} ${divergence.behind == 1 ? 'commit' : 'commits'} from the remote');
      final outcome = await mergeRemoteInto(repo, theirs: divergence.remote!, base: divergence.base, ours: divergence.local ?? divergence.remote!, freshId: freshId);
      merged = divergence.behind;
      conflicts = outcome.conflictCopies;
      // With no commit of ours yet the "merge" has the remote's commit as its one parent: a fast-forward in effect.
      final mergeCommit = await repo.commit(mergeMessage(theirs: divergence.behind, conflicts: outcome.conflicts), _who(), alsoParent: divergence.remote, keep: keep);
      committed = mergeCommit ?? committed;
      await _library?.refresh();
      divergence = await repo.divergence();
    }
    if (isPhone) {
      final size = repoSizes(repoPath: where.path, appData: appData, settings: settings, orgs: orgs);
      if (size.committed.bytes > phonePushMost) {
        return BackupOutcome(committed: committed, merged: merged, conflicts: conflicts, refused: refused, failure: GitFailure(GitTrouble.other, 'This backup is ${sizeWords(size.committed.bytes)}, more than a phone pushes in one go. Open Ghost.md on a Mac to push it; the phone keeps committing meanwhile.'));
      }
    }
    job.progress(line: 'Pushing');
    await background.running(backupJobId, title: 'Backing up to git', text: 'Pushing');
    try {
      final pushed = await repo.push(auth);
      updateGitBackupSettings((s) => s.copyWith(lastPushAt: clock(), lastPushedCommit: pushed.now), via);
      return BackupOutcome(committed: committed, pushed: !pushed.upToDate, merged: merged, conflicts: conflicts, refused: refused);
    } finally {
      await background.ended(backupJobId, title: 'Backed up to git', quiet: true);
    }
  }

  void _writeGenerated(RepoPlace where, GitBackupSettings settings, List<String> orgs) {
    final root = where.path;
    _writeIfChanged('$root/.gitignore', gitignoreText(settings, orgs: orgs));
    _writeIfChanged('$root/README.txt', readmeText(madeBy: _who().name));
    writeGitConfig(root, settings, madeBy: _who().name);
    final workflow = File('$root/$pagesWorkflowPath');
    if (settings.publish && isGitHubRemote(settings.remote)) {
      _writeIfChanged(workflow.path, placeholderPagesWorkflow);
    } else if (workflow.existsSync()) {
      workflow.deleteSync();
    }
  }

  static void _writeIfChanged(String path, String text) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync() == text) return;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  /// What the page shows now: cheap where the repository is clean.
  Future<GitBackupStatus> status({bool sizes = false}) async {
    final settings = gitBackupSettings(via);
    final where = await place();
    if (where == null) return GitBackupStatus(settings: settings, elsewhere: pusherElsewhere?.call());
    final repo = GitRepo(invoke, where.path);
    if (!await repo.exists()) return GitBackupStatus(settings: settings, place: where, elsewhere: pusherElsewhere?.call());
    final status = await repo.status();
    final log = await repo.log(count: 1);
    GitDivergence? divergence;
    try {
      divergence = await repo.divergence();
    } on GitFailure {
      divergence = null;
    }
    return GitBackupStatus(
      settings: settings,
      place: where,
      head: status.head,
      lastCommit: log.isEmpty ? null : log.first,
      divergence: divergence,
      changes: status.changes.length,
      shallow: status.shallow,
      sizes: sizes ? repoSizes(repoPath: where.path, appData: appData, settings: settings, orgs: orgFoldersAt(where.path)) : null,
      elsewhere: pusherElsewhere?.call(),
    );
  }

  /// Takes `.git` out of the repository's folder, the files left as they are (the page's Remove, after asking).
  Future<void> remove() async {
    _disarm();
    final where = await place();
    if (where != null) {
      final dotGit = Directory('${where.path}/.git');
      if (dotGit.existsSync()) dotGit.deleteSync(recursive: true);
      if (where.isMirror) Directory(where.path).deleteSync(recursive: true);
    }
    setGitBackupSettings(const GitBackupSettings(), via);
    notifyListeners();
  }
}

/// The mirror written from the library's notes (place.dart): each note at its path under [mirrorPath], notes gone
/// from the library taken out, dot folders and the generated files left alone. Answers how many were written.
int writeMirror(String mirrorPath, List<Note> notes) {
  final wanted = <String>{};
  var written = 0;
  for (final note in notes) {
    final path = note.path;
    if (path == null || path.isEmpty) continue;
    wanted.add(path);
    final file = File('$mirrorPath/$path');
    if (file.existsSync() && file.readAsStringSync() == note.body) continue;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(note.body);
    written += 1;
  }
  final root = Directory(mirrorPath);
  if (root.existsSync()) {
    for (final entry in root.listSync(recursive: true, followLinks: false)) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.md')) continue;
      final relative = entry.path.substring(mirrorPath.length).replaceFirst(RegExp(r'^[\\/]+'), '');
      if (relative.split('/').any((part) => part.startsWith('.'))) continue;
      if (!wanted.contains(relative)) entry.deleteSync();
    }
  }
  return written;
}
