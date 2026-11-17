/// The Servers tab (Matt, 2026-11-17: "replace the spaces item in the sidebar with servers, spaces outside of servers
/// move to the main chat list"): each server as a row that opens it in the list's place (AppShell.openServer), then
/// each linked Discord server's channels under its heading, as the Spaces tab had them. Spaces of one's own are in
/// Messages, among the conversations.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/settings_type.dart';
import '../../voice/discord.dart';
import '../../voice/space_groups.dart';
import '../shell.dart';
import '../space_groups_ui.dart';
import 'server_mock.dart';
import 'server_parts.dart';

/// A server, as a row of the Servers tab.
class ServerEntry {
  const ServerEntry(this.server);
  final MockServer server;
}

/// What the Servers tab lists, in order: [ServerEntry]s, then each Discord server's [SpaceGroupHeading] and its
/// [DiscordChannel]s.
List<Object> serverRows(List<MockServer> servers) {
  final discord = DiscordServers.instance;
  final groups = SpaceGroups.instance;
  return [
    for (final s in servers) ServerEntry(s),
    for (final l in discord.links) ...[
      SpaceGroupHeading(id: l.group, name: l.name, count: discord.stateOf(l).channels.length, discord: l, live: discord.stateOf(l).channels.fold(0, (n, c) => n + c.members.length)),
      if (!groups.folded(l.group)) ...discord.stateOf(l).channels,
    ],
  ];
}

/// A server's row: its face, its name, how many are on now and in its spaces, and its unread count.
class ServerRow extends StatelessWidget {
  const ServerRow({super.key, required this.server});
  final MockServer server;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final unread = server.channels.fold(0, (n, c) => n + c.unread);
        final live = server.liveSpaces.fold(0, (n, c) => n + c.inSpace.length);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')),
          child: GlacierPressable(
            onPressed: () => AppShell.maybeOf(context)?.openServer(server),
            semanticLabel: '${server.name}, ${server.online} on now${unread > 0 ? ', $unread unread' : ''}',
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(3)),
              decoration: BoxDecoration(color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
              child: Row(children: [
                ServerFace(name: server.name, hue: server.hue, size: 44),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: unread > 0 ? 'bold' : 'semibold')),
                    Text(
                      '${server.online} on now · ${server.channels.length} channels and spaces${live > 0 ? ' · $live in voice' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                    ),
                  ]),
                ),
                if (unread > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
                    decoration: BoxDecoration(color: t.color('app-accent'), borderRadius: BorderRadius.circular(99)),
                    child: Text('$unread', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-on-accent'))),
                  )
                else
                  AppIcon(Lucide.chevronRight, size: 16, color: t.color('app-ink-3')),
              ]),
            ),
          ),
        );
      },
    );
  }
}
