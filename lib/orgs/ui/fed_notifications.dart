/// The notifications drawer fed from the account's own feed: lib/notes/notifications_drawer.dart was written before
/// there was a feed, and takes its rows and what the person does to them as arguments. This hands it both from the
/// [AccountServices] - the rows as the feed lists them, each sealed row's words as the feed opens it, mark read,
/// mark all read, clear and clear all as the feed's own marks, an invitation's answer as
/// [AccountServices.answerInvite], and a pass of the notifications as the drawer opens.
///
/// It is what `src/app/notes/NotificationsDrawer.tsx` reads from its modules (`useNotifications`, `openDetails`,
/// `markRead`, `markAllRead`, `hide`, `hideAll`, `useOrgs`, `syncNotificationsNow`), and nothing else.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../core/notifications.dart';
import '../../core/preferences.dart';
import '../../notes/notifications_drawer.dart';
import '../../team/updates.dart';

/// The notifications drawer for [services]; with none, the signed-out drawer.
class FedNotificationsDrawer extends StatelessWidget {
  const FedNotificationsDrawer({super.key, required this.services, required this.onClose, required this.onOpenNote, required this.onOpenOrganization, required this.onAccount, this.emptyArt, this.now, this.onUnwatch, this.docs});

  final AccountServices? services;
  final VoidCallback onClose;
  final void Function(String id, String? at) onOpenNote;
  final void Function(String orgId) onOpenOrganization;
  final VoidCallback onAccount;
  final Widget? emptyArt;
  final int? now;

  /// A ticket's row's Unwatch (lib/notes/notifications_drawer.dart).
  final void Function(String noteId)? onUnwatch;

  /// The changes to the pages the account follows, the inbox's Docs (lib/team/updates.dart); none where absent.
  final DocUpdatesFeed? docs;

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final store = services?.prefs ?? preferences;
    return AccountBuilder(
      services: services,
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([store, ?docs]),
        builder: (context, _) {
          final prefs = store.value;
          final docs = this.docs;
          final feed = services?.feed;
          return NotificationsDrawer(
            notifications: services?.notifications ?? const [],
            prefs: prefs.notifications,
            signedIn: services?.signedIn ?? false,
            localOnly: prefs.localOnly,
            memberOf: {for (final row in services?.joined ?? const []) row.id},
            detailsOf: feed?.openDetails,
            onMarkRead: feed?.markRead,
            onMarkAllRead: feed?.markAllRead,
            onHide: feed?.hide,
            onHideAll: feed?.hideAll,
            onAnswerInvite: services?.answerInvite,
            // Opened: the feed taken again now, so what arrived while the app was away is here before it is read.
            onOpened: services == null ? null : () => unawaited(services.syncNotificationsNow()),
            onClose: onClose,
            onOpenNote: onOpenNote,
            onOpenOrganization: onOpenOrganization,
            onAccount: onAccount,
            emptyArt: emptyArt,
            now: now ?? services?.now(),
            onUnwatch: onUnwatch,
            docs: docs?.value ?? const [],
            docRead: docs?.isRead,
            onDocRead: docs?.markRead,
            onDocsAllRead: docs?.markAllRead,
            onDocsHide: docs?.hide,
          );
        },
      ),
    );
  }
}

/// How many rows the bell counts (`unreadCount`): the unread among what Settings › Notifications lets through.
int unreadNotifications(AccountServices? services, NotificationPrefs prefs) => services == null ? 0 : unreadCount(prefs, services.notifications);
