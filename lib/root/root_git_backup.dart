part of 'ghost_root.dart';

/// The git backup as the app wires it (lib/plugins/git_backup; Matt, 2026-10-31: "add a plugin to backup on git"): the
/// service made once the library is the core's, with the library's `touched` as its changes, the account's handle as
/// the commit author, the pusher claim through the synced preferences as the ticket sweep's is, and Android's
/// foreground service for a push. On an iPhone the commit and the push run only in the foreground (whatever waited
/// runs on resume); on a phone a push over 100 MB is left to a desktop. Started where the build has the whole core
/// (a Mac, a phone), never on the web, which has no Library folder to commit.
class _RootGitBackup {
  _RootGitBackup(this._root);

  final _GhostRootState _root;

  GitBackupService? service;
  AppLifecycleListener? _life;

  Future<void> start() async {
    final native = _root._native;
    final folder = _root._libraryFolder;
    if (native == null || folder == null || kIsWeb) return;
    final library = _root._library;
    final appData = (await DevicePaths.find()).dataDir;
    final phone = isNativeMobile;
    final made = service = GitBackupService(
      invoke: native.invoke,
      libraryFolder: folder,
      appData: appData,
      library: library,
      changes: library is CoreLibrary ? library.touched : library,
      handle: () => _root._services?.session?.handle ?? '',
      preferences: () => preferences.value,
      setPreferences: preferences.update,
      syncNow: () async => await _root._services?.engine?.syncNow(),
      accountHeld: () => _root._services?.engine?.accountPrefs,
      isPhone: phone,
      foregroundOnly: runsAsIPhoneApp,
      inForeground: () => WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      background: phone ? ChannelBackgroundJobs() : const NoBackgroundJobs(),
      onOpenConflicts: () => _root._openSettingsAt('plugin:git-backup'),
    );
    GitBackupService.current = made;
    made.start();
    _life = AppLifecycleListener(onResume: made.resumed);
  }

  /// Back up now, for the palette: null until the plugin is set up.
  VoidCallback? get backUpNow {
    final made = service;
    if (made == null || !made.on || !gitBackupSettings().configured) return null;
    return () => unawaited(made.backup.backUpNow(personStarted: true));
  }

  void dispose() {
    _life?.dispose();
    service?.stop();
    if (identical(GitBackupService.current, service)) GitBackupService.current = null;
  }
}
