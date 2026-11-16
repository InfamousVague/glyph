import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../voice/channels.dart';
import '../voice/hangout.dart';
import '../voice/roles.dart';
import '../voice/voice.dart';
import 'common.dart';
import '../app_state.dart';
import 'composer_box.dart';
import 'poof.dart';
import 'nav_bar.dart';
import 'ripple_avatar.dart';
import 'shell.dart';
import 'voice_screen.dart';

/// A hangout: its chat, who is in it, and its call (Matt, 2026-11-15: "add a chat to hangouts so the whole group can
/// send messages to the hangout as well as voice and video"; roles: "Implement a permissions system similar to
/// discord for hangouts ... make default roles such as admin, moderator, member").
///
/// Out of the call it is the chat, with who is here and a way into voice at its top. In the call, a toggle chooses the
/// people or the chat, with the call's dock over either. The shield opens its roles (RolesScreen).
class HangoutScreen extends StatefulWidget {
  const HangoutScreen({super.key, required this.channel, this.onClose, this.inSidebar = false});
  final VoiceChannel channel;

  /// Opened in the list's place, under the pill: the chat's composer and the call's dock leave it room (Matt,
  /// 2026-11-15: "When opening a hangout the left side should show the chat with some space below reserved for the
  /// navbar controls").
  final bool inSidebar;

  /// Leaves the page where it is not a pushed route (the Voice tab showing it): back to the list.
  final VoidCallback? onClose;

  @override
  State<HangoutScreen> createState() => _HangoutScreenState();
}

class _HangoutScreenState extends State<HangoutScreen> {
  HangoutRoom? _room;
  String _tab = 'people';

  @override
  void initState() {
    super.initState();
    unawaited(Voice.instance.hold(widget.channel).then((r) {
      if (mounted) setState(() => _room = r);
    }));
  }

  @override
  void dispose() {
    unawaited(Voice.instance.release(widget.channel));
    super.dispose();
  }

  Future<void> _join({bool video = false}) async {
    try {
      await Voice.instance.join(widget.channel, video: video);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t join: ${e is StateError ? e.message : e}', tone: GlacierToastTone.danger);
      return;
    }
    // Beside the list: the chat (and the videos) go to the pane, the people stay here (HangoutStage).
    if (mounted && AppShell.wideOf(context)) AppShell.maybeOf(context)?.go('voice');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final room = _room ?? v.hangoutFor(widget.channel);
    return ListenableBuilder(
      listenable: Listenable.merge([v, ?room]),
      builder: (context, _) {
        final s = v.session?.channel.room == widget.channel.room ? v.session : null;
        final pad = MediaQuery.paddingOf(context).bottom;
        final wide = AppShell.wideOf(context);
        // Under the pill in the list's place: what stands at the foot (the composer, the dock) stands above it.
        final pill = widget.inSidebar ? AppShell.pillRoom(context) : 0.0;
        final dockAt = pad + (widget.inSidebar ? pill : NavPill.inset(t));
        final actions = [
          if (room == null || room.can(Perm.invite)) IconTap(icon: Lucide.link, label: 'Copy invite link', onPressed: () => copyInvite(context, widget.channel)),
          if (room != null) IconTap(icon: Lucide.shieldCheck, label: 'Space settings', onPressed: () => push(context, (_) => RolesScreen(room: room, settings: true))),
        ];
        if (room?.putOut != null) {
          return GhostPage(
            title: widget.channel.name,
            body: Padding(padding: EdgeInsets.all(t.space(4)), child: SettingsCallout(child: Text(room!.putOut!))),
          );
        }
        // In a call on a phone the chat is a tab: while it is shown the call's controls are not, and the composer stands at
        // the foot as every conversation's does (Matt, 2026-11-15: "when we switch to chat please don't show the call
        // controls just make it appear like the bottom of all the compose windows look").
        final chat = room == null ? const SizedBox.shrink() : HangoutChat(room: room, bottom: pill + (s != null && (wide || _tab != 'chat') ? NavPill.clearance(t) : 0));
        if (s == null) {
          // Out of the call: who is here, a way in, and the chat.
          final here = room?.present.values.toList() ?? const <HangoutPerson>[];
          final inVoice = v.inChannel(widget.channel);
          return GhostPage(
            title: widget.channel.name,
            actions: actions,
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)),
                child: Row(children: [
                  // Who is connected: their faces, then their names.
                  for (final id in inVoice.take(4))
                    Padding(padding: EdgeInsets.only(right: t.space(1)), child: RippleAvatar(name: v.nameOf(id), level: 0, size: 30)),
                  if (inVoice.isNotEmpty) SizedBox(width: t.space(1)),
                  Expanded(
                    child: Text(
                      inVoice.isEmpty ? (here.isEmpty ? 'Nobody in voice' : '${here.length} here · nobody in voice') : '${inVoice.length} connected · ${inVoice.map(v.nameOf).join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                    ),
                  ),
                  SizedBox(width: t.space(2)),
                  _JoinButton(onPressed: () => _join()),
                ]),
              ),
              Expanded(child: chat),
            ]),
          );
        }
        // In the call beside the list (a computer, a wide phone): the people and the dock here, the chat and the videos
        // in the pane (Matt, 2026-11-15: "the voice on desktop should show up on the left side with the right side
        // reserved for chat").
        if (wide) {
          return GhostPage(
            title: widget.channel.name,
            actions: actions,
            body: Stack(children: [
              ListView(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), dockAt + NavPill.clearance(t) + t.space(4)),
                children: [CallPanel(session: s, videos: false)],
              ),
              Positioned(left: 0, right: 0, bottom: dockAt, child: Center(child: CallDock(session: s))),
            ]),
          );
        }
        // In the call: the people or the chat, and the dock.
        return GhostPage(
          title: widget.channel.name,
          actions: actions,
          body: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)),
                child: GlacierSegmentedControl(
                  fullWidth: true,
                  size: GlacierSegmentedSize.md,
                  ariaLabel: 'People or chat',
                  value: _tab,
                  onValueChange: (x) => setState(() => _tab = x),
                  options: [
                    GlacierSegmentedOption(value: 'people', label: Semantics(label: 'People', child: AppIcon(Lucide.users, size: 18, wash: false))),
                    GlacierSegmentedOption(value: 'chat', label: Semantics(label: 'Chat', child: AppIcon(LucideMore.messageCircle, size: 18, wash: false))),
                  ],
                ),
              ),
              Expanded(
                child: _tab == 'chat'
                    ? chat
                    : ListView(
                        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), dockAt + NavPill.clearance(t) + t.space(4)),
                        children: [CallPanel(session: s)],
                      ),
              ),
            ]),
            if (_tab != 'chat') Positioned(left: 0, right: 0, bottom: dockAt, child: Center(child: CallDock(session: s))),
          ]),
        );
      },
    );
  }
}

/// A hangout's call beside the list on a wide screen: its chat, and once anyone turns on video, the videos in the top
/// half and the chat in the bottom (Matt, 2026-11-15: "when a video starts split the right side 50/50 showing the
/// videos above the chat"). The people and the dock are in the list's place (HangoutScreen).
class HangoutStage extends StatefulWidget {
  const HangoutStage({super.key, required this.channel});
  final VoiceChannel channel;

  @override
  State<HangoutStage> createState() => _HangoutStageState();
}

class _HangoutStageState extends State<HangoutStage> {
  HangoutRoom? _room;

  @override
  void initState() {
    super.initState();
    unawaited(Voice.instance.hold(widget.channel).then((r) {
      if (mounted) setState(() => _room = r);
    }));
  }

  @override
  void dispose() {
    unawaited(Voice.instance.release(widget.channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final room = _room ?? v.hangoutFor(widget.channel);
    final media = v.media;
    return ListenableBuilder(
      listenable: Listenable.merge([v, ?room, ?media?.remote, ?media?.localVideo, ?v.session]),
      builder: (context, _) {
        final s = v.session?.channel.room == widget.channel.room ? v.session : null;
        final chat = room == null ? const SizedBox.shrink() : HangoutChat(room: room);
        final videos = s != null && CallVideos.any(s);
        return GhostPage(
          title: 'Chat',
          back: false,
          actions: [
            if (room == null || room.can(Perm.invite)) IconTap(icon: Lucide.link, label: 'Copy invite link', onPressed: () => copyInvite(context, widget.channel)),
            if (room != null) IconTap(icon: Lucide.shieldCheck, label: 'Space settings', onPressed: () => push(context, (_) => RolesScreen(room: room, settings: true))),
          ],
          body: videos
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: Padding(padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)), child: CallVideos(session: s))),
                  Container(height: t.len('glacier-hairline'), color: t.color('app-rule')),
                  Expanded(child: chat),
                ])
              : chat,
        );
      },
    );
  }
}

/// Join voice: a pill filled with ink, the headphones and the words.
class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'Join voice',
      builder: (context, state) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
        decoration: BoxDecoration(color: t.color('app-ink').withValues(alpha: state.pressed ? 0.85 : 1), borderRadius: BorderRadius.circular(t.radius('full'))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(LucideMore.headphones, size: 16, wash: false, color: t.color('app-paper')),
          SizedBox(width: t.space(2)),
          Text('Join voice', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-paper'))),
        ]),
      ),
    );
  }
}

/// A hangout's chat: its messages, newest at the foot, and the composer, which says why where this device may not
/// write. A message held down offers to delete it where this device may.
class HangoutChat extends StatefulWidget {
  const HangoutChat({super.key, required this.room, this.bottom = 0});
  final HangoutRoom room;

  /// Room left under the composer (the call's dock).
  final double bottom;

  @override
  State<HangoutChat> createState() => _HangoutChatState();
}

class _HangoutChatState extends State<HangoutChat> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _typing = false;

  /// Messages going in a puff, deleted once it has gone off (lib/ui/poof.dart).
  final Set<String> _poofing = {};

  @override
  void initState() {
    super.initState();
    // The composer lays itself out by whether there are words (lib/ui/composer_box.dart).
    _text.addListener(() {
      final typing = _text.text.isNotEmpty;
      if (typing != _typing && mounted) setState(() => _typing = typing);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.room.send(_text.text)) _text.clear();
  }

  static String _time(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final room = widget.room;
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final list = room.messages.reversed.toList();
        final mayWrite = room.can(Perm.chat);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No messages yet', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))
                : ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(2)),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final m = list[i];
                      // Messages in a run from one person show their name once.
                      final first = i == list.length - 1 || list[i + 1].from != m.from;
                      return Poof(
                        key: ValueKey('poof-${m.id}'),
                        gone: _poofing.contains(m.id),
                        side: AxisDirection.left,
                        onDone: () {
                          _poofing.remove(m.id);
                          room.delete(m);
                        },
                        child: _Message(key: ValueKey(m.id), room: room, message: m, first: first, time: _time(m.at), onDelete: () => setState(() => _poofing.add(m.id))),
                      );
                    },
                  ),
          ),
          Padding(
            // Laid out as every other conversation's foot is (Matt, 2026-11-15: "Use the same compose input on spaces
            // that we use for the rest of the app ... just make it appear like the bottom of all the compose windows look").
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2) + widget.bottom + MediaQuery.paddingOf(context).bottom * (widget.bottom > 0 ? 1 : 0)),
            child: mayWrite
                ? Builder(builder: (context) {
                    final send = IconTap(icon: Lucide.arrowUp, label: 'Send', filled: true, size: 19, box: t.lenOf('2.25rem'), onPressed: _text.text.trim().isEmpty ? null : _send);
                    return ComposerBox(
                      typing: _typing,
                      ends: [send],
                      below: [send],
                      field: ComposerField(controller: _text, focusNode: _focus, hint: 'Message ${room.channel.name}', onSubmitted: _send, enterSends: AppState.of(context).enterSends),
                    );
                  })
                : Text('Your role can\'t send messages here.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ),
        ]);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.room, required this.message, required this.first, required this.time, this.onDelete});
  final HangoutRoom room;
  final HangoutMessage message;
  final bool first;
  final String time;

  /// Deletes it, with its puff.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = message;
    final mine = m.from == room.me;
    final role = room.roster.roleOf(m.from);
    final owner = room.roster.isOwner(m.from);
    final name = mine ? 'You' : (m.name.isEmpty ? Voice.instance.nameOf(m.from) : m.name);
    // Pressed and held: copy it, or delete it at once with a puff (Matt, 2026-11-15: "Don't ask for confirmation when
    // deleting a message and show a poof animation when one is deleted").
    void menu() {
      HapticFeedback.mediumImpact();
      showChoices(context, choices: [
        if (m.text.isNotEmpty) Choice('Copy', Lucide.copy, () => Clipboard.setData(ClipboardData(text: m.text))),
        if (room.canDelete(m)) Choice('Delete for everyone', Lucide.trash2, () => onDelete?.call(), danger: true),
      ]);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: menu,
      onSecondaryTap: menu,
      child: Padding(
        padding: EdgeInsets.only(top: first ? t.space(3) : t.space(1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (first)
            Padding(
              padding: EdgeInsets.only(bottom: t.space(1)),
              child: Row(children: [
                // In the app's primary colour, as over a conversation's bubbles (lib/ui/thread.dart).
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: t.color('app-accent')))),
                if (owner || role.id != room.roster.newcomer) ...[SizedBox(width: t.space(2)), RoleTag(role: role, owner: owner)],
                SizedBox(width: t.space(2)),
                Text(time, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              ]),
            ),
          Text(m.text, style: pageText(t, t.fontSize('md'), color: t.color('app-ink'))),
        ]),
      ),
    );
  }
}

/// A role's name in a small pill: the owner's says Owner.
class RoleTag extends StatelessWidget {
  const RoleTag({super.key, required this.role, this.owner = false});
  final Role role;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strong = owner || role.id == Role.admin;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
      decoration: BoxDecoration(
        color: strong ? t.color('app-ink') : t.color('app-paper-3'),
        borderRadius: BorderRadius.circular(t.radius('full')),
      ),
      child: Text(owner ? 'Owner' : role.name, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: strong ? t.color('app-paper') : t.color('app-ink-2'))),
    );
  }
}

/// A hangout's roles: who has which, what each may do, and the role newcomers get. Anyone can read it; the owner and
/// admins change it.
class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key, required this.room, this.settings = false});
  final HangoutRoom room;

  /// As the hangout's settings: its link, sharing it and deleting it around the roles.
  final bool settings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final r = room.roster;
        final manage = room.canManage;
        final gap = SizedBox(height: t.space(6));
        // Everyone known: here now, or given a role.
        final people = <String>{r.ownerId, ...room.present.keys, ...r.assigned.keys, room.me}..remove('');
        final byRole = <String, List<String>>{};
        for (final id in people) {
          if (r.banned.contains(id)) continue;
          byRole.putIfAbsent(r.roleOf(id).id, () => []).add(id);
        }
        final c = room.channel;
        return GhostPage(
          title: settings ? c.name : 'Roles and permissions',
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (settings) ...[
                PaneSection(title: 'Space', children: [
                  if (room.can(Perm.invite)) SettingRow(icon: AppIcon(Lucide.link, size: 18), label: 'Copy invite link', hint: const Text('Anyone with it can join, from the app or a browser.'), onPress: () => copyInvite(context, c)),
                  if (room.can(Perm.invite)) SettingRow(icon: AppIcon(Lucide.share2, size: 18), label: 'Share with friends', onPress: () => push(context, (_) => ShareChannelScreen(channel: c))),
                  SettingRow(icon: AppIcon(Lucide.users, size: 18), label: 'Owner', value: Text(r.isOwner(room.me) ? 'You' : (r.hasOwner ? _nameOf(room, r.ownerId) : 'None'))),
                ]),
                gap,
              ],
              if (!r.hasOwner)
                SettingsCallout(child: const Text('This space was made before roles, so it has no owner: everyone in it is a member, and no one can change that.'))
              else if (!manage)
                SettingsCallout(child: Text('You\'re ${r.isOwner(room.me) ? 'the owner' : 'a ${r.roleOf(room.me).name.toLowerCase()}'}. The owner and admins change roles.')),
              if (r.hasOwner) ...[
                PaneSection(
                  title: 'People',
                  description: const Text('Press someone to change their role. Admins are made by the owner alone.'),
                  children: [
                    for (final role in r.ranked)
                      for (final id in byRole[role.id] ?? const <String>[])
                        SettingRow(
                          icon: AppIcon(Lucide.users, size: 18),
                          label: id == room.me ? 'You' : _nameOf(room, id),
                          value: RoleTag(role: role, owner: r.isOwner(id)),
                          onPress: manage && r.outranks(room.me, id) ? () => pickRole(context, room, id, _nameOf(room, id)) : null,
                        ),
                  ],
                ),
                gap,
                PaneSection(
                  title: 'Roles',
                  description: const Text('Highest first. A role can act on the ones below it: mute, remove, delete their messages.'),
                  children: [
                    for (final role in r.ranked)
                      SettingRow(
                        icon: AppIcon(role.id == Role.admin ? Lucide.crown : Lucide.shieldCheck, size: 18),
                        label: role.name,
                        hint: Text(role.id == Role.admin ? 'Everything' : (role.perms.isEmpty ? 'Nothing' : role.perms.map((p) => p.label).join(', ')), maxLines: 2, overflow: TextOverflow.ellipsis),
                        value: Text(role.id == r.newcomer ? 'New people' : ''),
                        onPress: () => push(context, (_) => RoleScreen(room: room, roleId: role.id)),
                      ),
                    if (manage)
                      SettingRow(
                        icon: AppIcon(Lucide.plus, size: 18),
                        label: 'Add a role',
                        onPress: () async {
                          final id = 'r${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
                          final ok = await room.saveRole(Role(id: id, name: 'New role', rank: 15, perms: {...Role.defaults.last.perms}));
                          if (ok && context.mounted) unawaited(push(context, (_) => RoleScreen(room: room, roleId: id)));
                        },
                      ),
                  ],
                ),
                gap,
                PaneSection(
                  title: 'New people',
                  children: [
                    SettingRow(
                      icon: AppIcon(Lucide.userPlus, size: 18),
                      label: 'Join as',
                      value: Text(r.roleById(r.newcomer)?.name ?? 'Member'),
                      onPress: manage
                          ? () => showChoices(context, title: 'New people join as', choices: [
                                for (final role in r.ranked)
                                  if (role.id != Role.admin) Choice('${role.id == r.newcomer ? '✓  ' : ''}${role.name}', Lucide.shieldCheck, () => room.setNewcomer(role.id)),
                              ])
                          : null,
                    ),
                  ],
                ),
                if (settings) ...[
                  gap,
                  PaneSection(title: '', children: [
                    SettingRow(icon: AppIcon(Lucide.trash2, size: 18), label: 'Delete space', hint: const Text('From this phone and your computer.'), onPress: () => confirmDeleteHangout(context, c)),
                  ]),
                ],
                if (r.banned.isNotEmpty) ...[
                  gap,
                  PaneSection(
                    title: 'Banned',
                    children: [
                      for (final id in r.banned)
                        SettingRow(
                          icon: AppIcon(Lucide.ban, size: 18),
                          label: _nameOf(room, id),
                          value: manage ? const Text('Unban') : null,
                          onPress: manage ? () => room.ban(id, on: false) : null,
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

String _nameOf(HangoutRoom room, String id) {
  final said = room.present[id]?.name;
  if (said != null && said.isNotEmpty) return said;
  for (final m in room.messages.reversed) {
    if (m.from == id && m.name.isNotEmpty) return m.name;
  }
  final named = Voice.instance.nameOf(id);
  return named == 'Someone' ? 'Someone (${id.substring(0, 6)})' : named;
}

/// One role: its name, and a switch for each thing it may do. Admin may do everything; it can't be changed.
class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.room, required this.roleId});
  final HangoutRoom room;
  final String roleId;

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  late final _name = TextEditingController(text: widget.room.roster.roleById(widget.roleId)?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final room = widget.room;
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final role = room.roster.roleById(widget.roleId);
        if (role == null) return const GhostPage(title: 'Role', body: SizedBox.shrink());
        final admin = role.id == Role.admin;
        final edit = room.canManage && !admin;
        final builtIn = Role.defaults.any((d) => d.id == role.id);
        return GhostPage(
          title: role.name,
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (admin) SettingsCallout(child: const Text('Admins may do everything, and give out every role but admin. The owner makes admins.')),
              if (edit && !builtIn)
                PaneSection(title: 'Name', children: [
                  SettingRowBox(
                    child: GlacierInput(
                      controller: _name,
                      placeholder: 'Role name',
                      ariaLabel: 'Role name',
                      autoCapitalize: TextCapitalization.words,
                      size: GlacierFieldSize.md,
                      onSubmitted: (x) {
                        if (x.trim().isNotEmpty) room.saveRole(role.copyWith(name: x.trim()));
                      },
                    ),
                  ),
                ]),
              if (edit && !builtIn)
                PaneSection(title: 'Place', description: const Text('Above Member to act on members; below Moderator to be acted on by moderators.'), children: [
                  SettingRow(
                    icon: AppIcon(Lucide.shieldCheck, size: 18),
                    label: 'Ranks',
                    value: Text(role.rank > 20 ? 'Above Moderator' : role.rank > 10 ? 'Between Member and Moderator' : 'Below Member'),
                    onPress: () => showChoices(context, title: 'Where ${role.name} ranks', choices: [
                      Choice('Above Moderator', Lucide.arrowUp, () => room.saveRole(role.copyWith(rank: 25))),
                      Choice('Between Member and Moderator', Lucide.minus, () => room.saveRole(role.copyWith(rank: 15))),
                      Choice('Below Member', Lucide.arrowDown, () => room.saveRole(role.copyWith(rank: 5))),
                    ]),
                  ),
                ]),
              PaneSection(
                title: 'What ${role.name.toLowerCase()}s may do',
                children: [
                  for (final p in Perm.values)
                    SettingRow(
                      label: p.label,
                      hint: Text(p.hint),
                      disabled: !edit,
                      control: GlacierSwitch(
                        checked: admin || role.perms.contains(p),
                        disabled: !edit,
                        ariaLabel: p.label,
                        onCheckedChange: (on) => room.saveRole(role.copyWith(perms: on ? {...role.perms, p} : ({...role.perms}..remove(p)))),
                      ),
                    ),
                ],
              ),
              if (edit && !builtIn && role.id != room.roster.newcomer)
                PaneSection(title: '', children: [
                  SettingRow(
                    icon: AppIcon(Lucide.trash2, size: 18),
                    label: 'Delete ${role.name}',
                    hint: const Text('Whoever has it goes back to the role new people get.'),
                    onPress: () async {
                      if (await room.deleteRole(role.id) && context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                ]),
            ],
          ),
        );
      },
    );
  }
}

/// Chooses [id]'s role: the roles below this device's own (the owner can give admin).
void pickRole(BuildContext context, HangoutRoom room, String id, String name) {
  final r = room.roster;
  final mine = r.isOwner(room.me) ? 1000 : r.roleOf(room.me).rank;
  showChoices(context, title: '$name\'s role', choices: [
    for (final role in r.ranked)
      if (role.rank < mine || (role.id == Role.admin && r.isOwner(room.me)))
        Choice('${r.roleOf(id).id == role.id ? '✓  ' : ''}${role.name}', role.id == Role.admin ? Lucide.crown : Lucide.shieldCheck, () async {
          final ok = await room.setRole(id, role.id);
          if (!ok && context.mounted) toast(context, 'Couldn\'t change their role', tone: GlacierToastTone.danger);
        }),
  ]);
}

/// What can be done about [id] in the hangout from this device, by its role: their role, muting them for everyone,
/// removing them, banning them. In the call's press-and-hold sheet (voice_screen.dart).
class HangoutModeration extends StatelessWidget {
  const HangoutModeration({super.key, required this.room, required this.id, required this.name});
  final HangoutRoom room;
  final String id;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final r = room.roster;
        final above = r.outranks(room.me, id);
        final mutedAll = r.muted.contains(id) || room.heldMutes.contains(id);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingRow(
            icon: AppIcon(Lucide.shieldCheck, size: 18),
            label: 'Role',
            value: RoleTag(role: r.roleOf(id), owner: r.isOwner(id)),
            onPress: room.canManage && above ? () => pickRole(context, room, id, name) : null,
          ),
          if (above && room.can(Perm.muteOthers))
            SettingRow(
              icon: AppIcon(LucideMore.micOff, size: 18),
              label: 'Mute for everyone',
              hint: const Text('No one in the space hears them until they\'re unmuted.'),
              control: GlacierSwitch(checked: mutedAll, onCheckedChange: (on) => room.muteForAll(id, on), ariaLabel: 'Mute $name for everyone'),
            ),
          if (above && room.can(Perm.removeMembers))
            SettingRow(
              icon: AppIcon(Lucide.userMinus, size: 18),
              label: 'Remove from space',
              hint: const Text('They can come back with the link.'),
              onPress: () {
                room.remove(id);
                Navigator.of(context).maybePop();
              },
            ),
          if (above && room.can(Perm.ban) && room.canManage)
            SettingRow(
              icon: AppIcon(Lucide.ban, size: 18),
              label: 'Ban',
              hint: const Text('Kept out for good, even with the link.'),
              onPress: () => showChoices(context, title: 'Ban $name? They\'re removed now and can\'t come back.', choices: [
                Choice('Ban', Lucide.ban, () async {
                  await room.ban(id);
                  if (context.mounted) Navigator.of(context).maybePop();
                }, danger: true),
              ]),
            ),
        ]);
      },
    );
  }
}

/// A hangout's menu, held or pressed with the other button on its row (Matt, 2026-11-15: "there also needs to be a
/// context menu to open settings for hangouts and manage permissions and such as well as delete the hangouts"): open
/// it, its settings and roles, its link, share it, delete it.
void showHangoutMenu(BuildContext context, VoiceChannel channel, {VoidCallback? onOpen}) {
  final v = Voice.instance;
  final room = v.hangoutFor(channel);
  showChoices(context, title: channel.name, choices: [
    if (onOpen != null) Choice('Open', LucideMore.messageCircle, onOpen),
    Choice('Settings and permissions', Lucide.shieldCheck, () => push(context, (_) => HangoutSettingsScreen(channel: channel))),
    if (room == null || room.can(Perm.invite)) Choice('Copy invite link', Lucide.link, () => copyInvite(context, channel)),
    if (room == null || room.can(Perm.invite)) Choice('Share with friends', Lucide.share2, () => push(context, (_) => ShareChannelScreen(channel: channel))),
    Choice('Delete space', Lucide.trash2, () => confirmDeleteHangout(context, channel), danger: true),
  ]);
}

/// Asks first, then takes [channel] off this phone and its computer (Voice.forget). Others keep their copy.
void confirmDeleteHangout(BuildContext context, VoiceChannel channel) {
  showChoices(context, title: 'Delete ${channel.name}? It goes from this phone and your computer; people who have the link keep it.', choices: [
    Choice('Delete space', Lucide.trash2, () async {
      final v = Voice.instance;
      if (v.viewing?.seed == channel.seed) v.view(null);
      await v.forget(channel);
      if (context.mounted) toast(context, 'Deleted ${channel.name}');
    }, danger: true),
  ]);
}

/// A hangout's settings: its link and sharing, its roles and permissions, deleting it. Holds the hangout's room open
/// while shown, so changes reach the others.
class HangoutSettingsScreen extends StatefulWidget {
  const HangoutSettingsScreen({super.key, required this.channel});
  final VoiceChannel channel;

  @override
  State<HangoutSettingsScreen> createState() => _HangoutSettingsScreenState();
}

class _HangoutSettingsScreenState extends State<HangoutSettingsScreen> {
  HangoutRoom? _room;

  @override
  void initState() {
    super.initState();
    _room = Voice.instance.hangoutFor(widget.channel);
    unawaited(Voice.instance.hold(widget.channel).then((r) {
      if (mounted) setState(() => _room = r);
    }));
  }

  @override
  void dispose() {
    unawaited(Voice.instance.release(widget.channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) {
      return GhostPage(title: widget.channel.name, body: Padding(padding: EdgeInsets.all(context.tokens.space(4)), child: SettingsCallout(child: const Text('The relay server isn\'t connected, so this space\'s settings can\'t be reached right now.'))));
    }
    return RolesScreen(room: room, settings: true);
  }
}

/// Who is in the hangout's call, in the list's place beside the pane while in it on a wide screen: the call's dock
/// stands where the pill was (lib/ui/shell.dart; Matt, 2026-11-15: "hide the default navbar when in a hangout and show
/// the call controls where it was").
class HangoutPeople extends StatelessWidget {
  const HangoutPeople({super.key, required this.session});
  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = session.channel;
    final room = Voice.instance.hangoutFor(c);
    return GhostPage(
      title: c.name,
      back: false,
      actions: [
        IconTap(icon: Lucide.shieldCheck, label: 'Space settings', onPressed: () => room == null ? null : push(context, (_) => RolesScreen(room: room, settings: true))),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), AppShell.pillRoom(context) + MediaQuery.paddingOf(context).bottom),
        children: [CallPanel(session: session, videos: false)],
      ),
    );
  }
}
