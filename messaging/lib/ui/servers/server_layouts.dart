/// Five ways a server could look (Matt, 2026-11-17: "propose 5 different layouts for this based on existing
/// applications ... Insipre it by the designs we already have and try to keep things minimal and easy to understand,
/// consider user lists, server settings, moving channels and spaces around"). Each draws the same server
/// (server_mock.dart) from the same parts (server_parts.dart); on a wide window a channel opens beside the list, on a
/// phone as a page of its own.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../sms.dart' show Person;
import '../common.dart';
import 'server_mock.dart';
import 'server_parts.dart';

/// The five, with what each is modelled on and what it is like.
enum ServerLayout {
  rail('Rail', 'Discord', 'Servers in a strip down the side, the channels beside them, the people on the right.', Lucide.panelLeft),
  workspace('Workspace', 'Slack', 'One sidebar: the server\'s menu at its top, unreads and live spaces first, then each category.', Lucide.layoutList),
  community('Community', 'WhatsApp and Telegram communities', 'A home page for the server: what it is, announcements on top, then Chats, Spaces and People as tabs.', Lucide.users),
  hub('Hub', 'Microsoft Teams and Guilded', 'Tiles: spaces live now along the top, every channel as a card below.', Lucide.layoutGrid),
  folders('Folders', 'Ghost Messaging\'s own list', 'The conversation list\'s cards, in folding categories; press and hold to move one.', Lucide.folder);

  const ServerLayout(this.label, this.after, this.description, this.icon);
  final String label;
  final String after;
  final String description;
  final LucideIcon icon;
}

/// The server drawn in [layout].
Widget serverLayout(ServerLayout layout, MockServer server) => switch (layout) {
      ServerLayout.rail => _Rail(server: server),
      ServerLayout.workspace => _Workspace(server: server),
      ServerLayout.community => _Community(server: server),
      ServerLayout.hub => _Hub(server: server),
      ServerLayout.folders => _Folders(server: server),
    };

/// A server's menu: invite, settings, arrange, its people.
void showServerMenu(BuildContext context, MockServer server) => showChoices(context, title: server.name, choices: [
      Choice('Invite people', Lucide.userPlus, () => showInvite(context, server)),
      Choice('Server settings', Lucide.settings, () => openServerSettings(context, server)),
      Choice('Arrange channels and spaces', Lucide.listTree, () => push<void>(context, (_) => ChannelOrganizer(server: server))),
      Choice('People · ${server.members.length}', Lucide.users, () => openMembersPage(context, server)),
    ]);

/// The list, and on a wide window the channel chosen beside it; [extra] at the far right where there is room.
class _Split extends StatelessWidget {
  const _Split({required this.list, required this.listWidth, required this.server, required this.selected, this.extra});
  final Widget list;
  final double listWidth;
  final MockServer server;
  final MockChannel? selected;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 720) return list;
      final rule = Container(width: 1, color: t.color('app-rule'));
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: listWidth, child: list),
        rule,
        Expanded(child: selected == null ? const SizedBox.shrink() : ChannelView(key: ValueKey(selected!.id), server: server, channel: selected!)),
        if (extra != null && box.maxWidth >= 1100) ...[rule, SizedBox(width: 240, child: extra!)],
      ]);
    });
  }
}

/// Picking a channel: beside the list on a wide window, a page of its own on a phone.
mixin _Picks<T extends StatefulWidget> on State<T> {
  MockServer get server;
  late String _chosen = server.channels.firstWhere((c) => c.kind == ChannelKind.text).id;
  MockChannel? get chosen => server.channel(_chosen);

  void pick(MockChannel c) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      setState(() => _chosen = c.id);
      server.read(c);
    } else {
      openChannelPage(context, server, c);
    }
  }
}

// --- 1. Rail ---------------------------------------------------------------------------------------------------------

class _Rail extends StatefulWidget {
  const _Rail({required this.server});
  final MockServer server;
  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> with _Picks {
  @override
  MockServer get server => widget.server;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rail = Container(
      width: 68,
      color: t.color('app-paper-2'),
      child: ListView(padding: EdgeInsets.symmetric(vertical: t.space(3)), children: [
        Center(child: ServerFace(name: server.name, hue: server.hue, selected: true)),
        Padding(padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)), child: Container(height: 2, color: t.color('app-rule'))),
        for (final (n, h) in otherServers)
          Padding(
            padding: EdgeInsets.only(bottom: t.space(2)),
            child: Center(child: GlacierPressable(onPressed: () => toast(context, 'Preview: only ${server.name} is filled in'), builder: (_, _) => ServerFace(name: n, hue: h))),
          ),
        Center(
          child: GlacierPressable(
            onPressed: () => toast(context, 'Preview: adding a server is not wired up'),
            semanticLabel: 'Add a server',
            builder: (_, _) => Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.color('app-rule'))), child: const Center(child: AppIcon(Lucide.plus, size: 20))),
          ),
        ),
      ]),
    );
    final channels = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlacierPressable(
        onPressed: () => showServerMenu(context, server),
        builder: (context, _) => Container(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(3), t.space(3)),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule')))),
          child: Row(children: [
            Expanded(child: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold'))),
            const AppIcon(Lucide.chevronDown, size: 16),
          ]),
        ),
      ),
      Expanded(
        child: ListView(padding: EdgeInsets.only(bottom: t.space(6)), children: [
          for (final g in server.categories) ...[
            CategoryHeading(server: server, category: g),
            if (!g.folded)
              for (final c in g.channels) ChannelTile(server: server, channel: c, dense: true, selected: c.id == chosen?.id && MediaQuery.sizeOf(context).width >= 720, onPress: () => pick(c)),
          ],
        ]),
      ),
      // You, at the foot, as the app\'s own: your face and a way to the server\'s people on a phone.
      Container(
        padding: EdgeInsets.all(t.space(2)),
        color: t.color('app-paper-2'),
        child: Row(children: [
          Avatar(people: const [Person(address: 'mock:me', name: 'You')], size: 30, presence: false),
          SizedBox(width: t.space(2)),
          Expanded(child: Text('You', style: pageText(t, t.fontSize('sm'), weight: 'medium'))),
          IconTap(icon: Lucide.users, label: 'People', size: 18, onPressed: () => openMembersPage(context, server)),
          IconTap(icon: Lucide.settings, label: 'Server settings', size: 18, onPressed: () => openServerSettings(context, server)),
        ]),
      ),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      rail,
      Expanded(child: _Split(list: channels, listWidth: 250, server: server, selected: chosen, extra: MemberList(server: server))),
    ]);
  }
}

// --- 2. Workspace ----------------------------------------------------------------------------------------------------

class _Workspace extends StatefulWidget {
  const _Workspace({required this.server});
  final MockServer server;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> with _Picks {
  @override
  MockServer get server => widget.server;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unread = [for (final c in server.channels) if (c.unread > 0) c];
    final live = server.liveSpaces;
    final wide = MediaQuery.sizeOf(context).width >= 720;
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
    final list = ListView(padding: EdgeInsets.only(bottom: t.space(8)), children: [
      GlacierPressable(
        onPressed: () => showServerMenu(context, server),
        builder: (context, _) => Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(3), t.space(2)),
          child: Row(children: [
            ServerFace(name: server.name, hue: server.hue, size: 34, selected: true),
            SizedBox(width: t.space(2) + 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(child: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold'))),
                  const AppIcon(Lucide.chevronDown, size: 16),
                ]),
                Text('${server.online} on now · ${server.members.length} people', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              ]),
            ),
            IconTap(icon: Lucide.userPlus, label: 'Invite', size: 18, onPressed: () => showInvite(context, server)),
          ]),
        ),
      ),
      quick(Lucide.messageSquare, 'Unreads', unread.length, () {
        if (unread.isNotEmpty) pick(unread.first);
      }),
      quick(LucideMore.headphones, 'Live spaces', live.length, () {
        if (live.isNotEmpty) pick(live.first);
      }),
      quick(Lucide.users, 'People', server.members.length, () => openMembersPage(context, server)),
      for (final g in server.categories) ...[
        CategoryHeading(server: server, category: g),
        if (!g.folded)
          for (final c in g.channels) ChannelTile(server: server, channel: c, dense: true, selected: wide && c.id == chosen?.id, onPress: () => pick(c), onLongPress: () => push<void>(context, (_) => ChannelOrganizer(server: server))),
      ],
      Padding(
        padding: EdgeInsets.all(t.space(3)),
        child: GlacierPressable(
          onPressed: () => push<void>(context, (_) => ChannelOrganizer(server: server)),
          builder: (_, _) => Row(children: [AppIcon(Lucide.plus, size: 16, color: t.color('app-ink-3')), SizedBox(width: t.space(2)), Text('Add or arrange channels', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))]),
        ),
      ),
    ]);
    return _Split(list: list, listWidth: 280, server: server, selected: chosen, extra: MemberList(server: server));
  }
}

// --- 3. Community ----------------------------------------------------------------------------------------------------

class _Community extends StatefulWidget {
  const _Community({required this.server});
  final MockServer server;
  @override
  State<_Community> createState() => _CommunityState();
}

class _CommunityState extends State<_Community> with _Picks {
  @override
  MockServer get server => widget.server;
  String _tab = 'chats';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final texts = [for (final c in server.channels) if (c.kind == ChannelKind.text) c];
    final spaces = [for (final c in server.channels) if (c.kind == ChannelKind.space) c];
    final announcements = texts.where((c) => c.name == 'announcements').firstOrNull;
    Widget card(Widget child, {VoidCallback? onPress}) => GlacierPressable(
          onPressed: onPress,
          builder: (context, state) => Container(
            margin: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), t.space(2)),
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(color: state.pressed ? t.color('app-paper-3') : t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('lg'))),
            child: child,
          ),
        );
    Widget chat(MockChannel c) {
      final last = server.messagesOf(c).last;
      return card(
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: t.color('app-paper-3'), shape: BoxShape.circle), child: Center(child: AppIcon(channelIcon(c), size: 18, color: t.color('app-ink-2')))),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: pageText(t, t.fontSize('md'), weight: c.unread > 0 ? 'bold' : 'semibold')),
              Text('${last.from}: ${last.text}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            ]),
          ),
          if (c.unread > 0)
            Container(padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1), decoration: BoxDecoration(color: t.color('app-accent'), borderRadius: BorderRadius.circular(99)), child: Text('${c.unread}', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-on-accent')))),
        ]),
        onPress: () => pick(c),
      );
    }

    final list = ListView(padding: EdgeInsets.only(bottom: t.space(8)), children: [
      // The server's front: its colour, its face, what it is for, and the two things done most.
      GlacierScope(
        attrs: {'hue': server.hue},
        child: Builder(builder: (context) {
          final tt = context.tokens;
          return Container(
            margin: EdgeInsets.all(t.space(3)),
            padding: EdgeInsets.all(t.space(4)),
            decoration: BoxDecoration(color: settingsHueWash(tt), borderRadius: BorderRadius.circular(t.radius('xl'))),
            child: Column(children: [
              ServerFace(name: server.name, hue: server.hue, size: 64, selected: true),
              SizedBox(height: t.space(2)),
              Text(server.name, style: pageText(t, t.fontSize('xl'), weight: 'bold')),
              if (server.description.isNotEmpty) Text(server.description, textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'))),
              SizedBox(height: t.space(1)),
              Text('${server.members.length} people · ${server.online} on now', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              SizedBox(height: t.space(3)),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconTap(icon: Lucide.userPlus, label: 'Invite', onPressed: () => showInvite(context, server)),
                SizedBox(width: t.space(4)),
                IconTap(icon: Lucide.settings, label: 'Settings', onPressed: () => openServerSettings(context, server)),
                SizedBox(width: t.space(4)),
                IconTap(icon: Lucide.listTree, label: 'Arrange', onPressed: () => push<void>(context, (_) => ChannelOrganizer(server: server))),
              ]),
            ]),
          );
        }),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), t.space(3)),
        child: GlacierSegmentedControl(
          fullWidth: true,
          size: GlacierSegmentedSize.md,
          ariaLabel: 'Chats, spaces or people',
          value: _tab,
          onValueChange: (v) => setState(() => _tab = v),
          options: [
            GlacierSegmentedOption(value: 'chats', label: const Text('Chats')),
            GlacierSegmentedOption(value: 'spaces', label: const Text('Spaces')),
            GlacierSegmentedOption(value: 'people', label: const Text('People')),
          ],
        ),
      ),
      if (_tab == 'chats') ...[
        if (announcements != null) ...[
          Padding(padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(1)), child: Text('PINNED', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3')))),
          chat(announcements),
        ],
        for (final c in texts)
          if (!identical(c, announcements)) chat(c),
      ],
      if (_tab == 'spaces')
        for (final c in spaces)
          card(
            Row(children: [
              AppIcon(LucideMore.headphones, size: 20, color: t.color('app-ink-2')),
              SizedBox(width: t.space(3)),
              Expanded(child: Text(c.name, style: pageText(t, t.fontSize('md'), weight: 'semibold'))),
              if (c.inSpace.isEmpty) Text('Empty', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))) else SpaceFaces(server: server, channel: c, size: 26),
            ]),
            onPress: () => pick(c),
          ),
      if (_tab == 'people')
        for (final m in [...server.members]..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0))) MemberRow(member: m),
    ]);
    return _Split(list: list, listWidth: 360, server: server, selected: chosen);
  }
}

// --- 4. Hub ----------------------------------------------------------------------------------------------------------

class _Hub extends StatefulWidget {
  const _Hub({required this.server});
  final MockServer server;
  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with _Picks {
  @override
  MockServer get server => widget.server;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final live = server.liveSpaces;
    Widget tile(MockChannel c) => GlacierPressable(
          onPressed: () => pick(c),
          onLongPress: () => push<void>(context, (_) => ChannelOrganizer(server: server)),
          builder: (context, state) => Container(
            width: 150,
            height: 96,
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(
              color: state.pressed ? t.color('app-paper-3') : t.color('app-paper-2'),
              borderRadius: BorderRadius.circular(t.radius('lg')),
              border: c.unread > 0 ? Border.all(color: t.color('app-accent'), width: 1.5) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AppIcon(channelIcon(c), size: 18, color: t.color('app-ink-2')),
                const Spacer(),
                if (c.unread > 0) Text('${c.unread} new', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-accent'))),
              ]),
              const Spacer(),
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
              if (c.kind == ChannelKind.space) Text(c.inSpace.isEmpty ? 'Empty' : '${c.inSpace.length} here', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
        );
    final list = ListView(padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(8)), children: [
      Row(children: [
        ServerFace(name: server.name, hue: server.hue, size: 40, selected: true),
        SizedBox(width: t.space(3)),
        Expanded(child: Text(server.name, style: pageText(t, t.fontSize('xl'), weight: 'bold'))),
        IconTap(icon: Lucide.userPlus, label: 'Invite', onPressed: () => showInvite(context, server)),
        IconTap(icon: Lucide.users, label: 'People', onPressed: () => openMembersPage(context, server)),
        IconTap(icon: Lucide.settings, label: 'Settings', onPressed: () => openServerSettings(context, server)),
      ]),
      if (live.isNotEmpty) ...[
        SizedBox(height: t.space(4)),
        Text('LIVE NOW', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'), tracking: 0.6)),
        SizedBox(height: t.space(2)),
        for (final c in live)
          GlacierPressable(
            onPressed: () => pick(c),
            builder: (context, state) => Container(
              margin: EdgeInsets.only(bottom: t.space(2)),
              padding: EdgeInsets.all(t.space(3)),
              decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: const Color(0xFF34C759), width: 1.5)),
              child: Row(children: [
                AppIcon(LucideMore.headphones, size: 20, color: t.color('app-ink-2')),
                SizedBox(width: t.space(3)),
                Expanded(child: Text('${c.name} · ${c.inSpace.length} talking', style: pageText(t, t.fontSize('md'), weight: 'semibold'))),
                SpaceFaces(server: server, channel: c, size: 28),
              ]),
            ),
          ),
      ],
      for (final g in server.categories) ...[
        SizedBox(height: t.space(4)),
        Text(g.name.toUpperCase(), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'), tracking: 0.6)),
        SizedBox(height: t.space(2)),
        Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [for (final c in g.channels) tile(c)]),
      ],
    ]);
    return _Split(list: list, listWidth: 500, server: server, selected: chosen);
  }
}

// --- 5. Folders ------------------------------------------------------------------------------------------------------

class _Folders extends StatefulWidget {
  const _Folders({required this.server});
  final MockServer server;
  @override
  State<_Folders> createState() => _FoldersState();
}

class _FoldersState extends State<_Folders> with _Picks {
  @override
  MockServer get server => widget.server;

  void _moveMenu(MockChannel c) => showChoices(context, title: c.name, choices: [
        for (final g in server.categories)
          if (!identical(g, server.categoryOf(c))) Choice('Move to ${g.name}', Lucide.folderInput, () => server.move(c, g, g.channels.length)),
        Choice('Arrange everything', Lucide.listTree, () => push<void>(context, (_) => ChannelOrganizer(server: server))),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    Widget row(MockChannel c) {
      final last = c.kind == ChannelKind.text ? server.messagesOf(c).last : null;
      return GlacierPressable(
        onPressed: () => pick(c),
        onLongPress: () => _moveMenu(c),
        builder: (context, state) => Container(
          margin: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(1) + 2),
          padding: EdgeInsets.all(t.space(3)),
          decoration: BoxDecoration(
            color: (wide && c.id == chosen?.id) || state.pressed ? t.color('app-paper-3') : t.color('app-paper-2'),
            borderRadius: BorderRadius.circular(t.lenOf('1rem')),
          ),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: t.color('glacier-bg'), shape: BoxShape.circle), child: Center(child: AppIcon(channelIcon(c), size: 18, color: t.color('app-ink-2')))),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: pageText(t, t.fontSize('md'), weight: c.unread > 0 ? 'bold' : 'semibold')),
                Text(
                  last != null ? '${last.from}: ${last.text}' : (c.inSpace.isEmpty ? 'Nobody here' : '${c.inSpace.length} here now'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                ),
              ]),
            ),
            if (c.kind == ChannelKind.space) SpaceFaces(server: server, channel: c, size: 24),
            if (c.unread > 0) Container(width: 10, height: 10, decoration: BoxDecoration(color: t.color('app-accent'), shape: BoxShape.circle)),
          ]),
        ),
      );
    }

    final list = ListView(padding: EdgeInsets.only(bottom: t.space(8)), children: [
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(2), t.space(2)),
        child: Row(children: [
          ServerFace(name: server.name, hue: server.hue, size: 40),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.name, style: pageText(t, t.fontSize('lg'), weight: 'bold')),
              Text('${server.online} on now', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
          IconTap(icon: Lucide.users, label: 'People', onPressed: () => openMembersPage(context, server)),
          IconTap(icon: Lucide.ellipsis, label: 'Server menu', onPressed: () => showServerMenu(context, server)),
        ]),
      ),
      for (final g in server.categories) ...[
        CategoryHeading(server: server, category: g),
        if (!g.folded) for (final c in g.channels) row(c),
      ],
    ]);
    return _Split(list: list, listWidth: 380, server: server, selected: chosen, extra: MemberList(server: server));
  }
}
