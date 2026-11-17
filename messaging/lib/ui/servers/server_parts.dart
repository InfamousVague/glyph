/// What a server is drawn from (its list: lib/ui/servers/server_sidebar.dart): a server's face, a channel's row, the
/// people in it, a channel opened, the server's settings, and the page where channels and spaces are moved about.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/semantic_colors.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../sms.dart' show Person;
import '../common.dart';
import '../shell.dart';
import 'server_mock.dart';

/// A server's face: its initials on its colour, a rounded square.
class ServerFace extends StatelessWidget {
  const ServerFace({super.key, required this.name, required this.hue, this.size = 44, this.selected = false});
  final String name;
  final String hue;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) => GlacierScope(
        attrs: {'hue': hue},
        child: Builder(builder: (context) {
          final t = context.tokens;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? settingsHue(t) : settingsHueWash(t),
              borderRadius: BorderRadius.circular(size * (selected ? 0.3 : 0.5)),
            ),
            child: Text(initials(name), style: pageText(t, size * 0.36, weight: 'bold', color: selected ? t.color('glacier-bg') : settingsHue(t))),
          );
        }),
      );
}

LucideIcon channelIcon(MockChannel c) => c.kind == ChannelKind.space ? LucideMore.headphones : (c.locked ? Lucide.lock : Lucide.hash);

/// The small faces of whoever is in a space, overlapped.
class SpaceFaces extends StatelessWidget {
  const SpaceFaces({super.key, required this.server, required this.channel, this.size = 20, this.most = 4});
  final MockServer server;
  final MockChannel channel;
  final double size;
  final int most;

  @override
  Widget build(BuildContext context) {
    final people = [for (final id in channel.inSpace) ?server.member(id)];
    if (people.isEmpty) return const SizedBox.shrink();
    final shown = people.take(most).toList();
    return SizedBox(
      height: size,
      width: size + (shown.length - 1) * size * 0.65,
      child: Stack(children: [
        for (final (i, m) in shown.indexed)
          Positioned(left: i * size * 0.65, child: Avatar(people: [Person(address: 'mock:${m.id}', name: m.name)], size: size, presence: false)),
      ]),
    );
  }
}

/// A channel's row: its mark, its name, how many are unread or who is in it.
class ChannelTile extends StatelessWidget {
  const ChannelTile({super.key, required this.server, required this.channel, required this.onPress, this.selected = false, this.onLongPress, this.dense = false});
  final MockServer server;
  final MockChannel channel;
  final VoidCallback onPress;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = channel;
    final bold = c.unread > 0;
    return GlacierPressable(
      onPressed: onPress,
      onLongPress: onLongPress,
      semanticLabel: '${c.kind == ChannelKind.space ? 'Space' : 'Channel'} ${c.name}',
      builder: (context, state) => Container(
        margin: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: dense ? t.space(1) + 1 : t.space(2)),
        decoration: BoxDecoration(
          color: selected ? t.color('app-paper-3') : (state.pressed || state.hovered ? t.color('app-paper-2') : null),
          borderRadius: BorderRadius.circular(t.radius('md')),
        ),
        child: Row(children: [
          AppIcon(channelIcon(c), size: 17, color: t.color(bold || selected ? 'app-ink' : 'app-ink-3')),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: bold ? 'semibold' : 'regular', color: t.color(bold || selected ? 'app-ink' : 'app-ink-2'))),
          ),
          if (c.kind == ChannelKind.space) SpaceFaces(server: server, channel: c),
          if (c.unread > 0)
            Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
              decoration: BoxDecoration(color: t.color('app-accent'), borderRadius: BorderRadius.circular(99)),
              child: Text('${c.unread}', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-on-accent'))),
            ),
        ]),
      ),
    );
  }
}

/// A category's heading, folding its channels away when pressed.
class CategoryHeading extends StatelessWidget {
  const CategoryHeading({super.key, required this.server, required this.category, this.foldable = true});
  final MockServer server;
  final MockCategory category;
  final bool foldable;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: foldable ? () => server.fold(category) : null,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(3), t.space(1)),
        child: Row(children: [
          if (foldable) AppIcon(category.folded ? Lucide.chevronRight : Lucide.chevronDown, size: 14, color: t.color('app-ink-3')),
          if (foldable) SizedBox(width: t.space(1)),
          Expanded(child: Text(category.name.toUpperCase(), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'), tracking: 0.6))),
        ]),
      ),
    );
  }
}

/// The people of the server: who is on, by role, then who is not.
class MemberList extends StatelessWidget {
  const MemberList({super.key, required this.server, this.padding});
  final MockServer server;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = [for (final m in server.members) if (m.online) m]..sort((a, b) => a.role.index.compareTo(b.role.index));
    final off = [for (final m in server.members) if (!m.online) m];
    Widget heading(String s) => Padding(
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(3), t.space(1)),
          child: Text(s.toUpperCase(), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'), tracking: 0.6)),
        );
    return ListView(padding: padding ?? EdgeInsets.only(bottom: t.space(6)), children: [
      heading('On now · ${on.length}'),
      for (final m in on) MemberRow(member: m),
      heading('Away · ${off.length}'),
      for (final m in off) MemberRow(member: m),
    ]);
  }
}

class MemberRow extends StatelessWidget {
  const MemberRow({super.key, required this.member, this.trailing, this.onPress});
  final MockMember member;
  final Widget? trailing;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = member;
    final role = m.role == MockRole.member ? null : (m.role.name[0].toUpperCase() + m.role.name.substring(1));
    return GlacierPressable(
      onPressed: onPress ?? () => showChoices(context, title: '${m.name}${role == null ? '' : ' · $role'}', choices: [
            Choice('Message ${m.name}', Lucide.messageSquare, () => toast(context, 'Preview: messages are not sent')),
            Choice('Invite to a space', LucideMore.headphones, () => toast(context, 'Preview: invites are not sent')),
          ]),
      builder: (context, state) => Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1) + 2),
        child: Opacity(
          opacity: m.online ? 1 : 0.55,
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Avatar(people: [Person(address: 'mock:${m.id}', name: m.name)], size: 32, presence: false),
              if (m.online)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(width: 11, height: 11, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF34C759), border: Border.all(color: t.color('glacier-bg'), width: 2))),
                ),
            ]),
            SizedBox(width: t.space(2) + 2),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium'))),
                  if (role != null) ...[
                    SizedBox(width: t.space(1)),
                    Text(role, style: pageText(t, t.fontSize('xs'), color: t.color('app-accent'), weight: 'semibold')),
                  ],
                ]),
                if (m.status != null) Text(m.status!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

/// A channel opened: a text channel's messages and a box to write in, or a space's people and a way in.
class ChannelView extends StatelessWidget {
  const ChannelView({super.key, required this.server, required this.channel, this.header = true});
  final MockServer server;
  final MockChannel channel;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = channel;
    final top = !header
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(2)),
            child: Row(children: [
              AppIcon(channelIcon(c), size: 18, color: t.color('app-ink-2')),
              SizedBox(width: t.space(2)),
              Text(c.name, style: pageText(t, t.fontSize('lg'), weight: 'semibold')),
              if (c.topic.isNotEmpty) ...[
                SizedBox(width: t.space(3)),
                Expanded(child: Text(c.topic, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
              ] else
                const Spacer(),
            ]),
          );
    if (c.kind == ChannelKind.space) {
      final people = [for (final id in c.inSpace) ?server.member(id)];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        top,
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (people.isEmpty)
                Text('Nobody is here yet', style: pageText(t, t.fontSize('md'), color: t.color('app-ink-3')))
              else
                Wrap(spacing: t.space(5), runSpacing: t.space(4), alignment: WrapAlignment.center, children: [
                  for (final m in people)
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(people: [Person(address: 'mock:${m.id}', name: m.name)], size: 64, presence: false),
                      SizedBox(height: t.space(1)),
                      Text(m.name, style: pageText(t, t.fontSize('sm'))),
                    ]),
                ]),
              SizedBox(height: t.space(6)),
              GlacierPressable(
                onPressed: () => toast(context, 'Preview: joining a space is not wired up'),
                builder: (context, state) => Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(6), vertical: t.space(3)),
                  decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(99)),
                  child: Text(people.isEmpty ? 'Start the space' : 'Join ${people.length == 1 ? people.first.name : '${people.length} people'}', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('glacier-bg'))),
                ),
              ),
            ]),
          ),
        ),
      ]);
    }
    final messages = server.messagesOf(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      top,
      Expanded(
        child: ListView(
          reverse: true,
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
          children: [
            for (final m in messages.reversed)
              Padding(
                padding: EdgeInsets.only(bottom: t.space(3)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Avatar(people: [Person(address: 'mock:${m.from.toLowerCase()}', name: m.from)], size: 34, presence: false),
                  SizedBox(width: t.space(2) + 2),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(m.from, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-accent'))),
                        SizedBox(width: t.space(2)),
                        Text(m.minutesAgo < 60 ? '${m.minutesAgo} min ago' : (m.minutesAgo < 1440 ? '${m.minutesAgo ~/ 60} h ago' : '${m.minutesAgo ~/ 1440} d ago'), style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                      ]),
                      Text(m.text, style: pageText(t, t.fontSize('md'), height: 1.35)),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(1), t.space(3), t.space(3)),
        child: GlacierInput(placeholder: 'Message #${c.name}', ariaLabel: 'Message ${c.name}', size: GlacierFieldSize.md, readOnly: true),
      ),
    ]);
  }
}

/// Opens [c] as a page of its own: on a phone, where there is no room beside the list.
/// Opens [page] in the pane, as a conversation is: beside the server's list in a wide window, over it on a phone. A
/// page opened from a page already in the pane goes on over it (push).
void _inPane(BuildContext context, Widget page, {String? channel, MockServer? server}) {
  final shell = AppShell.maybeOf(context);
  if (shell == null) {
    push<void>(context, (_) => page);
    return;
  }
  if (server != null) server.open = channel;
  shell.show(page, showing: 'server');
}

/// Opens a channel or a space: with its own header beside the list, as a page with a way back on a phone.
void openChannel(BuildContext context, MockServer server, MockChannel c) {
  server.read(c);
  final wide = AppShell.maybeOf(context)?.wide ?? false;
  final view = ChannelView(server: server, channel: c, header: wide);
  _inPane(
    context,
    wide ? KeyedSubtree(key: ValueKey('server-channel-${c.id}'), child: view) : GhostPage(key: ValueKey('server-channel-${c.id}'), title: c.kind == ChannelKind.space ? c.name : '#${c.name}', body: view),
    channel: c.id,
    server: server,
  );
}

void openMembersPage(BuildContext context, MockServer server) =>
    _inPane(context, GhostPage(key: const ValueKey('server-people'), title: 'People · ${server.members.length}', body: MemberList(server: server)), server: server);

void openOrganizer(BuildContext context, MockServer server) => _inPane(context, ChannelOrganizer(key: const ValueKey('server-arrange'), server: server), server: server);

/// The invite: copy its link, or make a new one.
void showInvite(BuildContext context, MockServer server) => showChoices(context, title: 'Invite people to ${server.name}\n${server.invite}', choices: [
      Choice('Copy the invite link', Lucide.copy, () {
        Clipboard.setData(ClipboardData(text: 'https://${server.invite}'));
        toast(context, 'Invite link copied');
      }),
      Choice('Make a new link', Lucide.refreshCw, () {
        server.newInvite();
        toast(context, 'New invite link made');
      }),
    ]);

void openServerSettings(BuildContext context, MockServer server) => _inPane(context, ServerSettingsPage(key: const ValueKey('server-settings'), server: server), server: server);

/// A server's settings: its name and what it is for, the invite, roles and what each may do, its channels and
/// spaces, its people, and its notifications.
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, required this.server});
  final MockServer server;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late final _name = TextEditingController(text: widget.server.name);
  late final _about = TextEditingController(text: widget.server.description);

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.server;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => GhostPage(
        title: 'Server settings',
        body: ListView(padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(10)), children: [
          Center(child: ServerFace(name: s.name, hue: s.hue, size: 72)),
          SizedBox(height: t.space(3)),
          PaneSection(title: 'Overview', children: [
            SettingRow(
              label: 'Name',
              layout: SettingRowLayout.stacked,
              control: GlacierInput(controller: _name, ariaLabel: 'Server name', size: GlacierFieldSize.md, autoCapitalize: TextCapitalization.words, onBlur: () {
                if (_name.text.trim().isNotEmpty) {
                  s.name = _name.text.trim();
                  s.changed();
                }
              }),
            ),
            SettingRow(
              label: 'What it\'s for',
              layout: SettingRowLayout.stacked,
              control: GlacierInput(controller: _about, ariaLabel: 'Description', size: GlacierFieldSize.md, onBlur: () {
                s.description = _about.text.trim();
                s.changed();
              }),
            ),
          ]),
          PaneSection(title: 'Inviting', children: [
            SettingRow(icon: AppIcon(Lucide.link, size: 18), label: 'Invite link', hint: Text(s.invite), onPress: () => showInvite(context, s)),
            SettingRow(
              icon: AppIcon(Lucide.shieldCheck, size: 18),
              label: 'Approve new members',
              hint: const Text('A moderator lets each one in.'),
              control: GlacierSwitch(checked: s.approveJoins, ariaLabel: 'Approve new members', onCheckedChange: (on) {
                s.approveJoins = on;
                s.changed();
              }),
            ),
          ]),
          PaneSection(title: 'Roles', description: const Text('What each role may do. Press one to change it.'), children: [
            for (final r in MockRole.values)
              SettingRow(
                icon: AppIcon(r == MockRole.owner ? Lucide.crown : Lucide.userRound, size: 18),
                label: r.name[0].toUpperCase() + r.name.substring(1),
                hint: Text('${rolePowers[r]} · ${s.members.where((m) => m.role == r).length} people'),
                onPress: r == MockRole.owner ? null : () => push<void>(context, (_) => _RolePage(server: s, role: r)),
              ),
          ]),
          PaneSection(title: 'Channels and spaces', children: [
            SettingRow(icon: AppIcon(Lucide.listTree, size: 18), label: 'Arrange channels and spaces', hint: Text('${s.categories.length} categories · ${s.channels.length} channels and spaces'), onPress: () => push<void>(context, (_) => ChannelOrganizer(server: s))),
          ]),
          PaneSection(title: 'People · ${s.members.length}', children: [
            for (final m in s.members)
              MemberRow(
                member: m,
                onPress: m.role == MockRole.owner
                    ? () {}
                    : () => showChoices(context, title: m.name, choices: [
                          for (final r in MockRole.values.skip(1))
                            if (r != m.role) Choice('Make ${r.name}', r == MockRole.admin ? Lucide.crown : Lucide.userRound, () => s.setRole(m, r)),
                          Choice('Remove from the server', Lucide.userX, () => s.kick(m), danger: true),
                        ]),
              ),
          ]),
          PaneSection(title: 'Notifications', children: [
            for (final n in const ['Everything', 'Mentions only', 'Nothing'])
              SettingRow(
                label: n,
                control: Pick(checked: s.notifications == n, label: n, onPress: () {
                  s.notifications = n;
                  s.changed();
                }),
              ),
          ]),
          PaneSection(children: [
            SettingRow(icon: AppIcon(Lucide.logOut, size: 18, color: t.danger), label: 'Leave the server', onPress: () => toast(context, 'Preview: nothing is left')),
          ]),
        ]),
      ),
    );
  }
}

class _RolePage extends StatelessWidget {
  const _RolePage({required this.server, required this.role});
  final MockServer server;
  final MockRole role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) => GhostPage(
        title: role.name[0].toUpperCase() + role.name.substring(1),
        body: ListView(padding: EdgeInsets.all(t.space(3)), children: [
          PaneSection(title: 'May', children: [
            for (final e in server.powers[role]!.entries)
              SettingRow(
                label: e.key,
                control: GlacierSwitch(checked: e.value, ariaLabel: e.key, onCheckedChange: (on) {
                  server.powers[role]![e.key] = on;
                  server.changed();
                }),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Channels and spaces moved about: dragged by their handle within a category, sent to another by their menu,
/// categories moved up and down, and new ones of each made.
class ChannelOrganizer extends StatelessWidget {
  const ChannelOrganizer({super.key, required this.server});
  final MockServer server;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) => GhostPage(
        title: 'Arrange',
        body: ListView(padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(10)), children: [
          Padding(
            padding: EdgeInsets.only(bottom: t.space(2)),
            child: Text('Drag a channel by its handle to reorder it. Press one to move it to another category or remove it.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ),
          for (final (i, g) in server.categories.indexed) ...[
            Row(children: [
              Expanded(child: CategoryHeading(server: server, category: g, foldable: false)),
              IconTap(icon: Lucide.arrowUp, label: 'Move ${g.name} up', size: 16, onPressed: i == 0 ? null : () => server.shiftCategory(g, -1)),
              IconTap(icon: Lucide.arrowDown, label: 'Move ${g.name} down', size: 16, onPressed: i == server.categories.length - 1 ? null : () => server.shiftCategory(g, 1)),
              IconTap(icon: Lucide.plus, label: 'Add to ${g.name}', size: 16, onPressed: () => showChoices(context, title: 'Add to ${g.name}', choices: [
                    Choice('Text channel', Lucide.hash, () => server.add(g, 'new-channel', ChannelKind.text)),
                    Choice('Space', LucideMore.headphones, () => server.add(g, 'New space', ChannelKind.space)),
                  ])),
            ]),
            ReorderableList(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: g.channels.length,
              onReorderItem: (from, to) => server.move(g.channels[from], g, to > from ? to + 1 : to),
              itemBuilder: (context, j) {
                final c = g.channels[j];
                return Container(
                  key: ValueKey(c.id),
                  margin: EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('md'))),
                  child: Row(children: [
                    Expanded(
                      child: ChannelTile(
                        server: server,
                        channel: c,
                        dense: true,
                        onPress: () => showChoices(context, title: c.name, choices: [
                          for (final other in server.categories)
                            if (!identical(other, g)) Choice('Move to ${other.name}', Lucide.folderInput, () => server.move(c, other, other.channels.length)),
                          Choice('Remove', Lucide.trash2, () => server.remove(c), danger: true),
                        ]),
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: j,
                      child: Padding(padding: EdgeInsets.all(t.space(2)), child: AppIcon(Lucide.gripVertical, size: 18, color: t.color('app-ink-3'))),
                    ),
                  ]),
                );
              },
            ),
            if (g.channels.isEmpty) Padding(padding: EdgeInsets.all(t.space(3)), child: Text('Nothing here yet', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
          ],
          SizedBox(height: t.space(3)),
          SettingRow(icon: AppIcon(Lucide.folderPlus, size: 18), label: 'Add a category', onPress: () => server.addCategory('New category')),
        ]),
      ),
    );
  }
}
