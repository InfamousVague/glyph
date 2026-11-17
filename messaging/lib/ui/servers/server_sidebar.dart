/// A server, in the list's place (Matt, 2026-11-17: "Let's go with the workspace view for servers but it should
/// takeover the normal sidebar when i enter a server with a back button at the top"): the Workspace layout, after
/// Slack, of the five the preview offered. Its header has the way back to the conversations, the server's name (its
/// menu), and Invite; then Unreads, Live spaces and People; then each category's channels and spaces. A channel opens
/// in the pane, beside the list in a wide window and over it on a phone, as a conversation does (AppShell.openServer).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../common.dart';
import '../shell.dart';
import 'server_mock.dart';
import 'server_parts.dart';

/// A server's menu: invite, settings, arrange, its people.
void showServerMenu(BuildContext context, MockServer server) => showChoices(context, title: server.name, choices: [
      Choice('Invite people', Lucide.userPlus, () => showInvite(context, server)),
      Choice('Server settings', Lucide.settings, () => openServerSettings(context, server)),
      Choice('Arrange channels and spaces', Lucide.listTree, () => openOrganizer(context, server)),
      Choice('People · ${server.members.length}', Lucide.users, () => openMembersPage(context, server)),
    ]);

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({super.key, required this.server, this.onBack});
  final MockServer server;

  /// Back to the conversations; the list's own navigator's pop where not given.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final unread = [for (final c in server.channels) if (c.unread > 0) c];
        final live = server.liveSpaces;
        final open = AppShell.showingOf(context) == 'server' ? server.open : null;
        Widget quick(LucideIcon icon, String label, int n, VoidCallback onPress) => GlacierPressable(
              onPressed: onPress,
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                child: Row(children: [
                  AppIcon(icon, size: 17, color: t.color('app-ink-2')),
                  SizedBox(width: t.space(2)),
                  Expanded(child: Text(label, style: pageText(t, t.fontSize('md'), weight: 'medium'))),
                  if (n > 0) Text('$n', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                ]),
              ),
            );
        return ColoredBox(
          color: t.color('app-paper'),
          child: SafeArea(
            bottom: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2)),
                child: Row(children: [
                  IconTap(key: const ValueKey('server-back'), icon: Lucide.arrowLeft, label: 'Back to conversations', size: 20, onPressed: onBack ?? () => Navigator.of(context).maybePop()),
                  SizedBox(width: t.space(1)),
                  Expanded(
                    child: GlacierPressable(
                      onPressed: () => showServerMenu(context, server),
                      builder: (context, _) => Row(children: [
                        ServerFace(name: server.name, hue: server.hue, size: 34, selected: true),
                        SizedBox(width: t.space(2) + 2),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Row(children: [
                              Flexible(child: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold'))),
                              AppIcon(Lucide.chevronDown, size: 16, color: t.color('app-ink-2')),
                            ]),
                            Text('${server.online} on now · ${server.members.length} people', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  IconTap(icon: Lucide.userPlus, label: 'Invite', size: 18, onPressed: () => showInvite(context, server)),
                ]),
              ),
              Expanded(
                child: ListView(padding: EdgeInsets.only(bottom: AppShell.pillRoom(context) + t.space(4)), children: [
                  quick(Lucide.messageSquare, 'Unreads', unread.length, () {
                    if (unread.isNotEmpty) openChannel(context, server, unread.first);
                  }),
                  quick(LucideMore.headphones, 'Live spaces', live.length, () {
                    if (live.isNotEmpty) openChannel(context, server, live.first);
                  }),
                  quick(Lucide.users, 'People', server.members.length, () => openMembersPage(context, server)),
                  for (final g in server.categories) ...[
                    CategoryHeading(server: server, category: g),
                    if (!g.folded)
                      for (final c in g.channels)
                        ChannelTile(server: server, channel: c, dense: true, selected: c.id == open, onPress: () => openChannel(context, server, c), onLongPress: () => openOrganizer(context, server)),
                  ],
                  Padding(
                    padding: EdgeInsets.all(t.space(3)),
                    child: GlacierPressable(
                      onPressed: () => openOrganizer(context, server),
                      builder: (_, _) => Row(children: [AppIcon(Lucide.plus, size: 16, color: t.color('app-ink-3')), SizedBox(width: t.space(2)), Text('Add or arrange channels', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
