/// The plugin's running parts, made once by the app's root and read by the page, the setup and the palette: the
/// backup engine (backup.dart) with the library's changes wired to it, the pusher claim (claim.dart), the restore
/// (restore.dart), and where the repository is (place.dart) asked of the library's folder each time.
///
/// [GitBackupService.current] is null in a test or a build with no core (the web): the page then shows the plugin as
/// not available here, and nothing runs.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/summary_handoff.dart' show SummaryDevice, thisDevice;
import '../../core/background_jobs.dart' show BackgroundJobs, NoBackgroundJobs;
import '../../core/library.dart' show NoteLibrary;
import '../../core/library_folder.dart' show LibraryFolder, LibraryStatus;
import '../../core/native/core.dart' show CoreInvoke;
import '../../core/preferences.dart';
import '../registry.dart' show plugins;
import '../types.dart' show PluginHost;
import 'backup.dart';
import 'claim.dart';
import 'manifest.dart' as git;
import 'place.dart';
import 'repo.dart';
import 'restore.dart';
import 'settings.dart';

class GitBackupService {
  GitBackupService({
    required this.invoke,
    required this.libraryFolder,
    required this.appData,
    required this.library,
    required this.changes,
    required String Function() handle,
    required Preferences Function() preferences,
    required void Function(Preferences Function(Preferences)) setPreferences,
    required Future<void> Function() syncNow,
    Map<String, Object?>? Function()? accountHeld,
    SummaryDevice Function()? device,
    bool isPhone = false,
    bool foregroundOnly = false,
    bool Function()? inForeground,
    BackgroundJobs background = const NoBackgroundJobs(),
    PluginHost? via,
    this.onOpenConflicts,
  })  : via = via ?? git.host,
        claims = PusherClaims(device: device ?? thisDevice, preferences: preferences, setPreferences: setPreferences, syncNow: syncNow, accountHeld: accountHeld, isPhone: isPhone) {
    backup = GitBackup(
      invoke: invoke,
      place: place,
      via: this.via,
      handle: handle,
      holdsPusher: claims.holds,
      pusherElsewhere: claims.elsewhere,
      library: library,
      appData: appData,
      isPhone: isPhone,
      foregroundOnly: foregroundOnly,
      inForeground: inForeground,
      background: background,
      onOpenConflicts: onOpenConflicts,
    );
    restore = GitRestore(invoke: invoke, appData: appData);
  }

  final CoreInvoke invoke;
  final LibraryFolder libraryFolder;
  final String appData;
  final NoteLibrary? library;

  /// The library's changes (its `touched`): each arms the quiet timer.
  final Listenable? changes;
  final PluginHost via;
  final PusherClaims claims;
  late final GitBackup backup;
  late final GitRestore restore;
  final VoidCallback? onOpenConflicts;

  bool _started = false;

  /// The service the root made; null where there is none.
  static GitBackupService? current;

  /// Where the repository is now, from the library's folder; the refusal, as a sentence, is [refusal].
  Future<RepoPlace?> place() async {
    final status = await libraryFolder.status();
    return placeFor(status, mirrorRoot: '$appData/git/library').place;
  }

  /// Why the Library cannot be the repository here, or null.
  Future<String?> refusal() async => placeFor(await libraryFolder.status(), mirrorRoot: '$appData/git/library').refusal;

  Future<LibraryStatus> libraryStatus() => libraryFolder.status();

  /// Listens to the library once the plugin is on; stops when it is switched off.
  void start() {
    if (_started) return;
    _started = true;
    changes?.addListener(_changed);
    plugins.addListener(_pluginsChanged);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    changes?.removeListener(_changed);
    plugins.removeListener(_pluginsChanged);
  }

  bool get on => plugins.isEnabled(git.manifest.id);

  void _changed() {
    if (on) backup.changed();
  }

  void _pluginsChanged() {
    if (!on) claims.release();
  }

  /// The app came to the front.
  void resumed() => backup.resumed();

  /// Sets the repository up where the setup finished: the remote kept, the repository made in its place, the remote
  /// written to it. Answers a refusal where the Library cannot hold one.
  Future<String?> adopt({required String remote, String? authUser}) async {
    final said = await refusal();
    if (said != null) return said;
    final where = await place();
    if (where == null) return 'Ghost.md has nowhere to keep a repository here.';
    final repo = GitRepo(invoke, where.path);
    await repo.init();
    await repo.setRemote(remote);
    updateGitBackupSettings((s) => s.copyWith(remote: remote, authUser: authUser ?? authUserFor(remote), repoPath: where.path, mirror: where.isMirror, setUpAt: DateTime.now(), lastFailure: null), via);
    return null;
  }

  /// The token kept, for a fetch or a push.
  Future<GitAuth> auth() async {
    final token = await via.secrets.read(git.tokenSecret);
    final settings = gitBackupSettings(via);
    if (token == null || token.isEmpty) return GitAuth.none;
    return GitAuth(token: token, user: settings.authUser ?? (settings.remote == null ? null : authUserFor(settings.remote!)));
  }

  /// A clone opened as the library (restore.dart, then the library's own move): the folder it is at.
  Future<RestoreOutcome> openFromGit({required String url, String? token, void Function(String)? progress}) async {
    final auth = token == null || token.isEmpty ? GitAuth.none : GitAuth(token: token, user: authUserFor(url));
    final outcome = await restore.cloneInto(url: url, auth: auth, progress: progress);
    await _openFolder(outcome);
    if (token != null && token.isNotEmpty) await via.secrets.write(git.tokenSecret, token);
    return outcome;
  }

  /// A clone made by hand, opened as the library.
  Future<RestoreOutcome> importFolder(String path) async {
    final outcome = await restore.importFolder(path);
    await _openFolder(outcome);
    return outcome;
  }

  Future<void> _openFolder(RestoreOutcome outcome) async {
    await invoke('library_inspect', {'path': outcome.folder});
    await libraryFolder.move();
    final settings = outcome.settings ?? const GitBackupSettings();
    setGitBackupSettings(settings.copyWith(repoPath: outcome.folder, mirror: false), via);
    unawaited(library?.refresh());
  }

  /// The history brought whole after a shallow clone, quietly.
  Future<void> deepen() async {
    final where = await place();
    if (where == null) return;
    await restore.deepen(where.path, await auth());
  }
}
