/// The app's one [Updates] (lib/core/updates.dart) as each screen that speaks of an update is handed it, and the
/// invitation's card as the account's feed fills it: what `src/app/App.tsx` did by passing its `updates` down, and
/// what `InviteNotice` (src/app/notes/Notices.tsx) read from `useNotifications` and `useOrgs` itself.
///
/// - [launchUpdatesOf]: the launch screen's line ("Checking for updates", "Ghost.md 0.2.0 is out"), the check that
///   screen runs as the app opens.
/// - [settingsUpdatesOf]: Settings › About's hero line, its Updates row and Check for updates, which opens the activity
///   tray's Update section.
/// - [InviteWaiting]: the newest invitation still waiting, with Accept and Decline.
///
/// The update itself, its Install, Restart to update and download, is said in the activity tray alone, under the
/// ring's badge (Matt, 2026-10-30: "show the updates stuff in the activity drawer only now with a badge"): the
/// [Updates] tell the record where they stand (`Updates.offer`, `Activity.update`), and the card above the notes is
/// gone.
///
/// What differs from the web:
/// - **Nothing here is ever `ready`.** A Flutter app has no page to download and reload into, so About's "A new
///   version is downloaded" and the launch screen's "Updating Ghost.md" are never reached; the words stay in their
///   screens, as ported. The Mac's app has a ready of its own instead (`ApkPhaseReady`: the new app in place beside
///   the running one): "Ghost.md 2.3.16 is downloaded" with "Restart to update" in the tray, and "Updated to Ghost.md
///   2.3.16" on the launch screen of the version it restarted into.
/// - **About has no alerts switch and no What's new**: the phone's own notifier (`UpdateCheckWorker.kt`) and the
///   list of releases (`releases.json`) are not ported. The page read both from where it took its updates.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../core/notifications.dart';
import '../core/updates.dart';
import '../launch/launch_screen.dart';
import '../notes/notices.dart' as notices;
import '../orgs/types.dart';
import '../settings/invite_actions.dart';
import '../settings/panes/about_pane.dart' show ghostVersion;
import '../settings/panes/settings_host.dart';

void _nothing() {}

/// What the launch screen reads (`LaunchScreen`'s `updates`). With no [updates], a build that never checks: the
/// line is not drawn at all.
LaunchUpdates launchUpdatesOf(Updates? updates) {
  if (updates == null) return LaunchUpdates.none;
  final apk = updates.apk;
  return LaunchUpdates(
    apkVersion: apk is ApkPhaseAvailable ? apk.info.version : null,
    updatedTo: (updates.installed?.justUpdated ?? false) ? updates.installed?.version : null,
    checking: updates.checking,
    lastError: updates.lastError,
    check: () => updates.check(),
    reload: _nothing,
  );
}

/// Where the account's sync stands, as the launch screen says it (`syncStatus.phase`, the page's third line:
/// "Syncing your devices", "In sync", "Sync will try again"): off with no account, or signed out. The root did not
/// hand the screen this at all, so a signed-in launch never said it was in sync.
SyncPhase launchSyncOf(String? phase) => switch (phase) {
      'syncing' => SyncPhase.syncing,
      'error' => SyncPhase.error,
      'idle' => SyncPhase.idle,
      _ => SyncPhase.off,
    };

/// What Settings › About is told (`AboutPane`'s `updates`): the version as the phone has it, where its updates come
/// from, and the Updates card's ladder (settings/updateLines.ts). Its Check for updates looks again and [onShow]s the
/// activity tray's Update section, which says what it found: About announces nothing of its own, and installs nothing.
SettingsUpdates settingsUpdatesOf(Updates updates, {VoidCallback? onShow}) {
  final apk = updates.apk;
  // An app the card offers to install: one found, or one whose install stopped short (`installable`).
  final installable = switch (apk) {
    ApkPhaseAvailable(:final info) || ApkPhaseFailed(:final info) || ApkPhaseNeedsPermission(:final info) => info.version,
    _ => null,
  };
  return SettingsUpdates(
    version: updates.installed?.version ?? ghostVersion,
    built: ghostBuild.isEmpty ? null : describeBuild(ghostBuild),
    sourceHost: updates.host,
    checking: updates.checking,
    lastError: updates.lastError,
    checked: updates.lastChecked != null,
    downloading: apk is ApkPhaseDownloading ? apk.info.version : null,
    installable: installable,
    restartable: apk is ApkPhaseReady ? apk.info.version : null,
    restarting: apk is ApkPhaseRestarting ? apk.info.version : null,
    onCheck: () {
      unawaited(updates.check());
      onShow?.call();
    },
  );
}

/// The invitation the card stands for (`InviteNotice`): the newest one still pending whose organization is in the
/// account's list as invited, so a card never stands for an organization that was deleted under it, or an
/// invitation answered on another device. [feed] is newest first, as the feed lists it.
FeedNotification? waitingInvite(List<FeedNotification> feed, List<OrgRow> orgs) {
  final invited = {for (final row in orgs) if (row.state == 'invited') row.id};
  for (final n in feed) {
    final org = n.org;
    if (n.kind == 'invite' && n.state == 'pending' && org != null && invited.contains(org.id)) return n;
  }
  return null;
}

/// An invitation to an organization, waiting, above the notes (`InviteNotice`), fed from the account: its sentence
/// and Accept and Decline (lib/settings/invite_actions.dart). Accepted, the organization opens ([onOpen]). Nothing
/// at all with no invitation, and in a build with no account nobody makes one.
class InviteWaiting extends StatelessWidget {
  const InviteWaiting({super.key, required this.services, this.onOpen});

  final AccountServices services;
  final void Function(String orgId)? onOpen;

  @override
  Widget build(BuildContext context) => AccountBuilder(
        services: services,
        builder: (context) {
          final invite = waitingInvite(services.notifications, services.orgState.list);
          final org = invite?.org;
          if (invite == null || org == null) return const SizedBox.shrink();
          return notices.InviteNotice(
            sentence: sentenceOf(invite),
            actions: InviteActions(
              // One pair of words to an organization: a second invitation does not inherit the first's answer.
              key: ValueKey('invite-actions-${org.id}'),
              services: services,
              orgId: org.id,
              onAnswered: (accepted) {
                if (accepted) onOpen?.call(org.id);
              },
            ),
          );
        },
      );
}
