/// The plugin's page in Settings: the repository (remote, branch, last commit and push, ahead and behind, who pushes,
/// the mirror where it is one), the conflict copies with Open, the sizes, the switches (recordings and their cap, each
/// organization, Publish as a website), Back up now, Open library from git and Import from a repo folder, and Remove
/// (asks twice; keeps the files, deletes `.git`). In Simple the switches wait behind More (Matt, 2026-10-18).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart' show preferences;
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_card.dart';
import '../onboarding/setup_flow.dart' show PluginSetup;
import 'backup.dart';
import 'files.dart';
import 'git_backup_setup.dart';
import 'manifest.dart' as git;
import 'place.dart';
import 'service.dart';
import 'settings.dart';

/// What Settings' search finds on the page.
const List<SettingsFindable> gitBackupFindable = [
  SettingsFindable('Repository', 'git repository remote branch github gitlab codeberg backup push commit'),
  SettingsFindable('What is backed up', 'recordings organizations orgs publish website pages size'),
  SettingsFindable('Open library from git', 'restore clone import repo folder fresh device'),
  SettingsFindable('Remove', 'remove git backup delete .git'),
];

/// How the page is told the service's doings in a test: the service itself, or none.
class GitBackupPane extends StatefulWidget {
  const GitBackupPane({super.key, this.service, this.setup, this.now});

  /// A test's own; the app's [GitBackupService.current] where null.
  final GitBackupService? service;
  final PluginSetup? setup;
  final DateTime Function()? now;

  @override
  State<GitBackupPane> createState() => _GitBackupPaneState();
}

class _GitBackupPaneState extends State<GitBackupPane> {
  late final VoidCallback _stop;
  late final PluginSetup _setup = widget.setup ?? gitBackupSetup();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _token = TextEditingController();
  final TextEditingController _folder = TextEditingController();
  GitBackupStatus? _status;
  bool _more = false;
  bool _armed = false;
  bool _restoring = false;
  bool _showRestore = false;
  String? _said;
  String? _problem;
  Timer? _timer;

  GitBackupService? get _service => widget.service ?? GitBackupService.current;

  @override
  void initState() {
    super.initState();
    _stop = onPluginStorage(_redraw);
    // Simple or Advanced may change while the page is open.
    preferences.addListener(_redraw);
    _service?.backup.addListener(_moved);
    _url.addListener(_redraw);
    _folder.addListener(_redraw);
    unawaited(_read());
  }

  @override
  void dispose() {
    _stop();
    preferences.removeListener(_redraw);
    _service?.backup.removeListener(_moved);
    _url.dispose();
    _token.dispose();
    _folder.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _moved() {
    _redraw();
    if (!(_service?.backup.running ?? false)) unawaited(_read());
  }

  Future<void> _read() async {
    final service = _service;
    if (service == null) return;
    try {
      final status = await service.backup.status(sizes: true);
      if (mounted) setState(() => _status = status);
    } catch (failure) {
      if (mounted) setState(() => _problem = failure.toString());
    }
  }

  Future<void> _backUpNow() async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _said = null;
      _problem = null;
    });
    final outcome = await service.backup.backUpNow(personStarted: true);
    if (!mounted) return;
    setState(() {
      if (outcome.failure != null) {
        _problem = outcome.failure!.plain;
      } else if (outcome.elsewhere != null) {
        _said = 'Committed here. ${outcome.elsewhere!.name ?? 'Another device'} is the one that pushes.';
      } else {
        _said = outcome.pushed ? 'Backed up.' : (outcome.committed != null ? 'Committed; nothing new for the remote.' : 'Nothing to back up.');
      }
    });
    unawaited(_read());
  }

  void _remove() {
    _timer?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() {
      _armed = false;
      _said = 'The repository is gone from this device; your notes are as they were. The remote keeps what was pushed.';
      _status = null;
    });
    unawaited(_service?.backup.remove().then((_) => _read()));
  }

  Future<void> _openFromGit() async {
    final service = _service;
    final url = _url.text.trim();
    if (service == null || url.isEmpty) return;
    final shape = remoteShape(url);
    if (shape != null) {
      setState(() => _problem = shape);
      return;
    }
    setState(() {
      _restoring = true;
      _problem = null;
      _said = null;
    });
    try {
      final outcome = await service.openFromGit(url: url, token: _token.text.trim(), progress: (line) {
        if (mounted) setState(() => _said = line);
      });
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _showRestore = false;
        _said = 'Opened ${outcome.notes} ${outcome.notes == 1 ? 'note' : 'notes'} from the repository${outcome.orgsHeld.isEmpty ? '' : '; ${outcome.orgsHeld.length == 1 ? 'one organization’s notes' : '${outcome.orgsHeld.length} organizations’ notes'} come from your team once you sign in'}.';
      });
      _url.clear();
      _token.clear();
      unawaited(service.deepen());
      unawaited(_read());
    } catch (failure) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _problem = failure is Exception ? failure.toString() : '$failure';
        });
      }
    }
  }

  Future<void> _importFolder() async {
    final service = _service;
    final path = _folder.text.trim();
    if (service == null || path.isEmpty) return;
    setState(() {
      _restoring = true;
      _problem = null;
    });
    try {
      final outcome = await service.importFolder(path);
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _showRestore = false;
        _said = 'Opened ${outcome.notes} ${outcome.notes == 1 ? 'note' : 'notes'} from $path.';
      });
      _folder.clear();
      unawaited(_read());
    } catch (failure) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _problem = failure.toString();
        });
      }
    }
  }

  String _ago(DateTime? when) {
    if (when == null) return 'never';
    final now = (widget.now ?? DateTime.now)();
    final gap = now.difference(when.toLocal());
    if (gap.inSeconds < 60) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) return '${gap.inHours} h ago';
    return '${gap.inDays} ${gap.inDays == 1 ? 'day' : 'days'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final service = _service;
    final settings = gitBackupSettings();
    final status = _status;
    final simple = preferences.value.simple;
    if (!_more && settingsSought(context, const ['What is backed up'])) _more = true;
    final full = !simple || _more;
    final elsewhere = status?.elsewhere;
    final divergence = status?.divergence;
    final sizes = status?.sizes;
    final orgs = status?.place == null ? const <String>[] : orgFoldersAt(status!.place!.path);
    final busy = service?.backup.running ?? false;
    return PaneBody(
      children: [
        PluginSetupCard(setup: _setup),
        if (service == null) const SettingsCallout(child: Text('Backing up to git isn’t available in this build: it needs Ghost.md’s core, which the web app has not.')),
        if (_problem != null) SettingsCallout(icon: const AppIcon(Lucide.triangleAlert, size: 18), child: Text(_problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        if (settings.lastFailure != null && _problem == null) SettingsCallout(icon: const AppIcon(Lucide.triangleAlert, size: 18), action: RowAction(onPress: () => unawaited(_backUpNow()), disabled: busy, child: const Text('Retry')), child: Text('The last backup failed: ${settings.lastFailure}')),
        if (status?.place?.isMirror ?? false) const SettingsCallout(icon: AppIcon(Lucide.info, size: 18), child: Text(mirrorExplained)),
        PaneSection(
          title: 'Repository',
          description: const Text('Your Library folder is the repository: every note, its history and its pictures committed two minutes after your last change, and pushed when you are online.'),
          children: [
            SettingRow(
              key: const ValueKey('git-backup-remote'),
              icon: const AppIcon(Lucide.gitBranch, size: 16),
              label: settings.remote == null ? 'No repository yet' : remoteShort(settings.remote!),
              hint: Text(settings.remote == null ? 'Run the setup to add one.' : '${remoteHostName(settings.remote!)} · branch ${settings.branch}'),
            ),
            SettingRow(
              key: const ValueKey('git-backup-last'),
              icon: const AppIcon(Lucide.history, size: 16),
              label: 'Last commit ${_ago(status?.lastCommit?.time ?? settings.lastCommitAt)}',
              hint: Text([
                if (status?.lastCommit != null) status!.lastCommit!.message,
                'Last push ${_ago(settings.lastPushAt)}',
                if (divergence != null && (divergence.ahead > 0 || divergence.behind > 0)) '${divergence.ahead} ahead, ${divergence.behind} behind',
                if ((status?.changes ?? 0) > 0) '${status!.changes} ${status.changes == 1 ? 'file' : 'files'} to back up',
              ].join(' · ')),
            ),
            SettingRow(
              key: const ValueKey('git-backup-pusher'),
              icon: const AppIcon(Lucide.hardDriveUpload, size: 16),
              label: elsewhere == null ? 'This device pushes' : 'Backing up from your ${elsewhere.name ?? 'other device'}',
              hint: Text(elsewhere == null ? 'Of your signed-in devices, one pushes; the others commit and watch.' : 'This device commits; ${elsewhere.name ?? 'the other device'} pushes.'),
            ),
            if (settings.conflicts.isNotEmpty)
              SettingRow(
                key: const ValueKey('git-backup-conflicts'),
                icon: const AppIcon(Lucide.triangleAlert, size: 16),
                label: '${settings.conflicts.length} ${settings.conflicts.length == 1 ? 'conflict copy' : 'conflict copies'}',
                hint: Text(settings.conflicts.take(3).map(titleOfConflict).join(', ')),
                value: RowAction(
                    onPress: () {
                      service?.onOpenConflicts?.call();
                      updateGitBackupSettings((s) => s.copyWith(conflicts: const []));
                    },
                    child: const Text('Open')),
              ),
            if (sizes != null)
              SettingRow(
                key: const ValueKey('git-backup-size'),
                icon: const AppIcon(Lucide.hardDrive, size: 16),
                label: '${sizeWords(sizes.committed.bytes)} backed up',
                hint: Text([
                  '${sizes.committed.files} files',
                  if (sizes.git.bytes > 0) 'repository ${sizeWords(sizes.git.bytes)}',
                  if (!settings.recordings && sizes.recordings.bytes > 0) 'recordings ${sizeWords(sizes.recordings.bytes)} left out',
                  if (sizes.orgsExcluded.bytes > 0) 'organizations ${sizeWords(sizes.orgsExcluded.bytes)} left out',
                  if (sizes.video.bytes > 0) 'films ${sizeWords(sizes.video.bytes)} never',
                ].join(' · ')),
              ),
            SettingRow(
              key: const ValueKey('git-backup-now'),
              icon: const AppIcon(Lucide.refreshCw, size: 16),
              label: 'Back up now',
              hint: Text(settings.configured ? 'Commits what changed and pushes it.' : 'Set the repository up first.'),
              value: RowAction(onPress: () => unawaited(_backUpNow()), disabled: busy || service == null || !settings.configured, child: Text(busy ? 'Backing up…' : 'Back up')),
            ),
          ],
        ),
        if (full)
          PaneSection(
            title: 'What is backed up',
            description: const Text('Notes, their history, pictures and files always. Recordings and each organization’s notes only when you say: a team’s notes are the team’s.'),
            children: [
              SettingRow(
                key: const ValueKey('git-backup-recordings'),
                label: 'Recordings',
                hint: Text('Each under ${sizeWords(settings.recordingsMaxBytes)}; larger ones are left out and named.'),
                control: GlacierSwitch(ariaLabel: 'Back up recordings', checked: settings.recordings, onCheckedChange: (on) => updateGitBackupSettings((s) => s.copyWith(recordings: on))),
              ),
              for (final org in orgs)
                SettingRow(
                  key: ValueKey('git-backup-org-$org'),
                  label: org,
                  hint: const Text('An organization’s notes, as the team has them.'),
                  control: GlacierSwitch(
                    ariaLabel: 'Back up $org',
                    checked: settings.orgsIncluded.contains(org),
                    onCheckedChange: (on) => updateGitBackupSettings((s) => s.copyWith(orgsIncluded: on ? {...s.orgsIncluded, org} : ({...s.orgsIncluded}..remove(org)))),
                  ),
                ),
              if (isGitHubRemote(settings.remote))
                SettingRow(
                  key: const ValueKey('git-backup-publish'),
                  label: 'Publish as a website',
                  hint: Text(settings.publish ? 'A GitHub Pages workflow is committed; the site will be at ${pagesSiteFor(settings.remote) ?? 'your GitHub Pages address'} once Pages is on for the repository.' : 'Commits a GitHub Pages workflow, so a push publishes the notes as a site. Off unless you say.'),
                  control: GlacierSwitch(ariaLabel: 'Publish as a website', checked: settings.publish, onCheckedChange: (on) => updateGitBackupSettings((s) => s.copyWith(publish: on))),
                ),
            ],
          )
        else
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('git-backup-more'),
                label: 'More',
                hint: const Text('Recordings, each organization, and publishing as a website.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ],
          ),
        PaneSection(
          title: 'Open library from git',
          description: const Text('On a fresh device: clone a repository made by this plugin and open it as the library. Your team’s notes come from your team once you sign in, not from the repository.'),
          children: [
            if (!_showRestore)
              SettingRow(
                key: const ValueKey('git-backup-restore'),
                icon: const AppIcon(Lucide.hardDriveDownload, size: 16),
                label: 'Open library from git…',
                hint: const Text('Paste the repository’s address and a token that may read it.'),
                onPress: service == null ? null : () => setState(() => _showRestore = true),
                disabled: service == null,
              )
            else ...[
              SettingRow(
                key: const ValueKey('git-backup-restore-fields'),
                icon: const AppIcon(Lucide.hardDriveDownload, size: 16),
                label: 'Repository',
                layout: SettingRowLayout.stacked,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    PlainField(key: const ValueKey('git-backup-restore-url'), label: 'HTTPS address', controller: _url, placeholder: 'https://github.com/you/notes.git'),
                    PlainField(key: const ValueKey('git-backup-restore-token'), label: 'Token', controller: _token, placeholder: 'github_pat_…', secret: true),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RowAction(onPress: () => unawaited(_openFromGit()), disabled: _restoring || _url.text.trim().isEmpty, child: Text(_restoring ? 'Cloning…' : 'Clone and open')),
                    ),
                  ],
                ),
              ),
              if (!(status?.place?.isMirror ?? false))
                SettingRow(
                  key: const ValueKey('git-backup-import'),
                  icon: const AppIcon(Lucide.folderInput, size: 16),
                  label: 'Import from a repo folder',
                  layout: SettingRowLayout.stacked,
                  control: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: t.space(2),
                    children: [
                      PlainField(key: const ValueKey('git-backup-import-path'), label: 'Folder', controller: _folder, placeholder: '/Users/you/notes'),
                      Align(alignment: AlignmentDirectional.centerEnd, child: RowAction(onPress: () => unawaited(_importFolder()), disabled: _restoring || _folder.text.trim().isEmpty, child: const Text('Open folder'))),
                    ],
                  ),
                ),
            ],
          ],
        ),
        // Always on the page (the search finds it); its row waits until there is a repository to remove.
          PaneSection(
            title: 'Remove',
            children: [
              SettingRow(
                key: const ValueKey('git-backup-remove'),
                icon: const AppIcon(Lucide.trash2, size: 16),
                label: 'Remove the repository from this device',
                hint: const Text('Your notes stay as they are; only the .git folder goes. What was pushed stays on the remote.'),
                value: RowAction(onPress: _remove, disabled: busy || (settings.repoPath == null && !settings.configured), child: Text(_armed ? 'Tap again' : 'Remove')),
              ),
            ],
          ),
        const SettingsFootnote(
          child: Text('The repository is plain text: anyone who can read it can read your notes, so keep it private. The token is kept in this device’s secure storage and follows your account, sealed, to your other devices. SSH keys are not in this version; use an HTTPS address with a token.'),
        ),
      ],
    );
  }
}

/// A conflict copy's title from its path, for the row.
String titleOfConflict(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Whether the page is shown for this account: always; the service's absence is said on the page.
bool gitBackupOffered(Object? _) => true;

/// The manifest's id, for the row's plugin.
String get gitBackupId => git.manifest.id;
