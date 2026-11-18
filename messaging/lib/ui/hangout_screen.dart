import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../sms.dart' show Sms;
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../kit/semantic_colors.dart';
import '../voice/channels.dart';
import '../voice/hangout.dart';
import '../voice/roles.dart';
import '../voice/voice.dart';
import 'common.dart';
import '../app_state.dart';
import '../backgrounds.dart';
import '../sms.dart' show Person;
import 'circles/circle_face.dart' show SpaceKindBadge, TitleBarMark, spaceKindIcon;
import 'circles/members_drawer.dart' show showMembersDrawer;
import 'drawer_head.dart';
import 'composer_box.dart';
import 'dialup/bevel.dart';
import 'dialup/parts.dart' show DialupPanel;
import 'dialup/retro_button.dart';
import 'message_line.dart';
import 'translated_card.dart';
import '../plugins/plugin.dart' show MessageFacts;
import 'poof.dart';
import 'nav_bar.dart';
import 'ripple_avatar.dart';
import 'shell.dart';
import 'space_designs/space_design.dart';
import 'space_invite.dart';
import 'voice_screen.dart';
import 'jump_to_latest.dart';

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

/// A space's chat before its room can be opened (the relay server not reached yet): what it will show, and why not.
class _NoRoomYet extends StatelessWidget {
  const _NoRoomYet({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.space(6)),
        child: SettingsEmpty(
          icon: AppIcon(LucideMore.messageCircle, size: 28, color: t.color('app-ink-3')),
          title: 'Connecting to $name',
          body: const Text('Its messages show here as soon as the relay server is reached.'),
        ),
      ),
    );
  }
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
    if (!mounted) return;
    // One of the developer designs: the call opens as its page (lib/ui/space_designs).
    if (openSpaceCall(context)) return;
    // Beside the list: the chat (and the videos) go to the pane, the people stay here (HangoutStage).
    if (AppShell.wideOf(context)) AppShell.maybeOf(context)?.go('voice');
  }

  /// The call or the chat, on a phone: the people in the call, or the space's messages.
  Widget _callOrChat(Tokens t) => Padding(
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
      );

  /// The space's header, as a conversation's is (lib/ui/thread.dart): its kind's mark where a face goes, its name, and
  /// under it its description (Matt, 2026-11-17: "make the text header for spaces show the icon and the name and an
  /// area for a description of the channel so the header space taken up matches the space taken up on other areas like
  /// dms and telegram chats"). It sits in GhostPage's own bar, so it is the same height as theirs. Pressed, it opens the
  /// description for the owner and admins, and does nothing for anyone else.
  GhostPage _page(HangoutRoom? room, {required Widget body, List<Widget> actions = const []}) {
    final t = context.tokens;
    final c = widget.channel;
    final line = spaceHeaderLine(c, room);
    final edit = room != null && room.canManage ? () => editSpaceAbout(context, room) : null;
    final live = c.hasVoice && Voice.instance.inChannel(c).isNotEmpty;
    return GhostPage(
      title: c.name,
      actions: actions,
      // Dial-Up draws its own title bar and leaves titleWidget out: the line and the mark go there instead.
      subtitle: line,
      onTitle: edit,
      titleLeading: TitleBarMark(icon: spaceKindIcon(c.kind), child: SpaceKindBadge(kind: c.kind, size: 18, live: live)),
      titleWidget: GlacierPressable(
        onPressed: edit,
        builder: (context, state) => Row(children: [
          SpaceKindBadge(kind: c.kind, size: t.lenOf('2.1rem'), live: live),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold')),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
        ]),
      ),
      body: body,
    );
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
        // In the call on a narrow phone: the chosen design is the page (space_design.dart).
        final design = inlineSpaceCall(context, s);
        if (design != null) return design;
        final pad = MediaQuery.paddingOf(context).bottom;
        final wide = AppShell.wideOf(context);
        // Under the pill in the list's place: what stands at the foot (the composer, the dock) stands above it.
        final pill = widget.inSidebar ? AppShell.pillRoom(context) : 0.0;
        final dockAt = pad + (widget.inSidebar ? pill : NavPill.inset(t));
        // A circle's space beside the circle's list (a wide window): the list's own Invite stands just beside it, so the
        // space's page leaves its own out rather than show two of the same button side by side.
        final besideCircle = wide && widget.channel.circle != null;
        final actions = [
          if (room != null) _membersButton(context, room),
          if ((room == null || room.can(Perm.invite)) && !besideCircle) IconTap(icon: Lucide.userPlus, label: 'Invite people', onPressed: () => showSpaceInvite(context, widget.channel)),
          if (room != null) IconTap(icon: Lucide.shieldCheck, label: 'Space settings', onPressed: () => push(context, (_) => RolesScreen(room: room, settings: true))),
        ];
        if (room?.putOut != null) {
          return _page(
            room,
            body: Padding(padding: EdgeInsets.all(t.space(4)), child: SettingsCallout(child: Text(room!.putOut!))),
          );
        }
        // In a call on a phone the chat is a tab: while it is shown the call's controls are not, and the composer stands at
        // the foot as every conversation's does (Matt, 2026-11-15: "when we switch to chat please don't show the call
        // controls just make it appear like the bottom of all the compose windows look").
        final bottom = pill + (s != null && (wide || _tab != 'chat') ? NavPill.clearance(t) : 0);
        // Before the relay is reached there is no room yet: say so, rather than a bare title over nothing.
        final chat = room == null ? _NoRoomYet(name: widget.channel.name) : HangoutChat(room: room, bottom: bottom);
        // A texting or Files space has no call: no Join, no one "in voice", just its chat (SpaceKind).
        if (s == null && !widget.channel.hasVoice) {
          return _page(room, actions: actions, body: chat);
        }
        if (s == null) {
          // Out of the call: who is here, a way in, and the chat.
          final here = room?.present.values.toList() ?? const <HangoutPerson>[];
          final inVoice = v.inChannel(widget.channel);
          // Dial-Up: on the window's silver, and only who is in voice, since "People Here" under it counts the room.
          final dialup = isDialup(context);
          final row = Padding(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)),
            child: Row(children: [
              // Who is connected: their faces, then their names.
              for (final id in inVoice.take(4))
                Padding(padding: EdgeInsets.only(right: t.space(1)), child: RippleAvatar(name: v.nameOf(id), level: 0, size: 30)),
              if (inVoice.isNotEmpty) SizedBox(width: t.space(1)),
              Expanded(
                child: Text(
                  inVoice.isEmpty ? (here.isEmpty || dialup ? 'Nobody in voice' : '${here.length} here · nobody in voice') : '${inVoice.length} connected · ${inVoice.map(v.nameOf).join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                ),
              ),
              SizedBox(width: t.space(2)),
              _JoinButton(onPressed: () => _join()),
            ]),
          );
          // On a phone, with people talking in it: the call first, who is in it and Join, and the chat a tap away
          // (Matt, 2026-11-17: open "as a normal chat window when there are no people online and chatting", and
          // "switch between the call and chat UI"). Nobody in it: the chat, as any conversation opens.
          if (!wide && !dialup && inVoice.isNotEmpty) {
            return _page(
              room,
              actions: actions,
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _callOrChat(t),
                Expanded(
                  child: _tab == 'chat'
                      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [row, Expanded(child: chat)])
                      : _WhoIsTalking(ids: inVoice, nameOf: (id) => (room?.present[id]?.name ?? '').isNotEmpty ? room!.present[id]!.name : v.nameOf(id), onJoin: () => _join()),
                ),
              ]),
            );
          }
          return _page(
            room,
            actions: actions,
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              dialup ? ColoredBox(color: DialupColors.of(t).chrome, child: row) : row,
              Expanded(child: chat),
            ]),
          );
        }
        // In the call beside the list (a computer, a wide phone): the people and the dock here, the chat and the videos
        // in the pane (Matt, 2026-11-15: "the voice on desktop should show up on the left side with the right side
        // reserved for chat").
        if (wide) {
          return _page(
            room,
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
        return _page(
          room,
          actions: actions,
          body: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _callOrChat(t),
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
            if (room != null) _membersButton(context, room),
            if (room == null || room.can(Perm.invite)) IconTap(icon: Lucide.userPlus, label: 'Invite people', onPressed: () => showSpaceInvite(context, widget.channel)),
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

/// Who is in a space's call, seen from outside it on a phone: each face and name. Tapping them joins the call (Matt,
/// 2026-11-17: "remove the join voice and video chat button ... just make tapping on the list of people join the call
/// automatically").
class _WhoIsTalking extends StatelessWidget {
  const _WhoIsTalking({required this.ids, required this.nameOf, required this.onJoin});
  final List<String> ids;

  /// What each goes by: the name they gave the space's room, or the call's.
  final String Function(String id) nameOf;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final face = t.lenOf('3rem');
    return GlacierPressable(
      onPressed: onJoin,
      semanticLabel: 'Join the call with ${ids.length} in it',
      builder: (context, state) => ListView(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), MediaQuery.paddingOf(context).bottom + NavPill.clearance(t) + t.space(4)),
      children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: t.online)),
          SizedBox(width: t.space(2)),
          Text(ids.length == 1 ? '1 in voice' : '${ids.length} in voice', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.online)),
        ]),
        SizedBox(height: t.space(3)),
        for (final id in ids)
          Padding(
            padding: EdgeInsets.only(bottom: t.space(2)),
            child: Row(children: [
              RippleAvatar(name: nameOf(id), level: 0, size: face),
              SizedBox(width: t.space(3)),
              Expanded(child: Text(nameOf(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')))),
            ]),
          ),
        SizedBox(height: t.space(1)),
        Text('Tap to join', style: pageText(t, t.fontSize('sm'), color: t.color(state.pressed ? 'app-ink-2' : 'app-ink-3'))),
      ],
      ),
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
    // Dial-Up's is a raised silver button like the rest of its window's (lib/ui/dialup/retro_button.dart).
    if (isDialup(context)) return RetroButton(onPressed: onPressed, icon: LucideMore.headphones, label: 'Join voice');
    final (fill, words) = strongFill(t);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'Join voice',
      builder: (context, state) => Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
        decoration: BoxDecoration(color: fill.withValues(alpha: state.pressed ? 0.85 : 1), borderRadius: BorderRadius.circular(t.radius('full'))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(LucideMore.headphones, size: 16, wash: false, color: words),
          SizedBox(width: t.space(2)),
          Text('Join voice', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: words)),
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

  /// Where this space's chat was left, and its list's controller, which starts there (lib/ui/jump_to_latest.dart; Matt,
  /// 2026-11-17: "remember the scroll position when switching between chats"). The page can stay as the room changes
  /// (didUpdateWidget): the arrow then keeps the old room's spot and puts the list at the new one's, and a list made
  /// afresh for the new room (after its "No messages yet") starts at the new room's spot, since the controller asks
  /// which room it is each time a list takes it up.
  String get _spot => 'space:${widget.room.channel.room}';
  late final ScrollController _scroll = ScrollMemory.controllerFor(() => _spot);

  /// What others wrote, newest first, for the arrow to count while the person reads back.
  Iterable<Object> _incoming(HangoutRoom room) => room.messages.reversed.where((m) => m.from != room.me).map((m) => m.id);
  bool _typing = false;

  /// Messages going in a puff, deleted once it has gone off (lib/ui/poof.dart).
  final Set<String> _poofing = {};

  /// Who came into the room and who left while it was open here, for Dial-Up's Host lines ("Riley has entered the
  /// room."): kept by this page alone, as the era's transcripts were, so they start empty each time it is opened.
  final List<({int at, String id, bool came})> _comings = [];

  /// Who was here at the room's last change (null until it is joined), and the names they gave, kept for saying who left.
  Set<String>? _here;
  final Map<String, String> _names = {};

  /// Dial-Up's "People Here" opened out under its strip, on a phone.
  bool _peopleOpen = false;

  /// What is shown here is read: its unread mark in the list goes (Voice.markRead).
  void _read() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Voice.instance.markRead(widget.room.channel);
    });
  }

  void _roomChanged({bool first = false}) {
    _read();
    final room = widget.room;
    for (final p in room.present.values) {
      if (p.name.isNotEmpty) _names[p.id] = p.name;
    }
    if (!room.opened) {
      _here = null;
      return;
    }
    final now = {for (final id in room.present.keys) if (id != room.me) id};
    final was = _here;
    if (was == null) {
      // Who is here on joining is what "People Here" says; only later changes are comings and goings. Opened with
      // nobody listed yet, the list joining brings is still on its way (HangoutRoom.open): the next change is it.
      if (!(first && now.isEmpty)) _here = now;
      return;
    }
    _here = now;
    final at = DateTime.now().millisecondsSinceEpoch;
    for (final id in now.difference(was)) {
      _comings.add((at: at, id: id, came: true));
    }
    for (final id in was.difference(now)) {
      _comings.add((at: at, id: id, came: false));
    }
    if (_comings.length > 200) _comings.removeRange(0, _comings.length - 200);
  }

  String _nameOf(String id) {
    final said = widget.room.present[id]?.name ?? '';
    return said.isNotEmpty ? said : (_names[id] ?? Voice.instance.nameOf(id));
  }

  @override
  void didUpdateWidget(HangoutChat old) {
    super.didUpdateWidget(old);
    if (old.room != widget.room) {
      old.room.removeListener(_roomChanged);
      _comings.clear();
      _here = null;
      widget.room.addListener(_roomChanged);
      _roomChanged(first: true);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.room.addListener(_roomChanged);
    _roomChanged(first: true);
    // The composer lays itself out by whether there are words (lib/ui/composer_box.dart).
    _text.addListener(() {
      final typing = _text.text.isNotEmpty;
      if (typing != _typing && mounted) setState(() => _typing = typing);
    });
  }

  @override
  void dispose() {
    widget.room.removeListener(_roomChanged);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.room.send(_text.text)) _text.clear();
  }

  /// Pressed and held under Dial-Up: what a bubble's press offers ([_Message]), copy, or delete at once with a puff.
  void _menu(HangoutMessage m) {
    HapticFeedback.mediumImpact();
    showChoices(context, choices: [
      if (m.text.isNotEmpty) Choice('Copy', Lucide.copy, () => Clipboard.setData(ClipboardData(text: m.text))),
      ...translateChoices(context, spaceFacts(m, mine: m.from == widget.room.me)),
      if (widget.room.canDelete(m)) Choice('Delete for everyone', Lucide.trash2, () => setState(() => _poofing.add(m.id)), danger: true),
    ]);
  }

  /// Who is in the room: you first, then the others as they said they are, each with whether they are in its voice.
  List<({String id, String name, bool voice, bool me})> _people(HangoutRoom room) {
    final v = Voice.instance;
    final inVoice = v.inChannel(room.channel);
    return [
      (id: room.me, name: 'You', voice: v.session?.channel.room == room.channel.room, me: true),
      for (final p in room.present.values)
        if (p.id != room.me) (id: p.id, name: _nameOf(p.id), voice: p.inVoice || inVoice.contains(p.id), me: false),
    ];
  }

  /// The space as Dial-Up's chat room (Matt, 2026-11-16: "base one of them heavily on the old AOL chatrooms"): one
  /// transcript of "Name: words" lines with Host saying who came and went, and "People Here" with who is in it. On a
  /// wide window the people stand beside the transcript, one name to a row, a speaker by each one in voice, filled
  /// while they talk; on a phone they are a strip over it that opens out.
  Widget _chatRoom(HangoutRoom room) {
    final c = DialupColors.of(context.tokens);
    final people = _people(room);
    final entries = <({int at, HangoutMessage? m, ({int at, String id, bool came})? e})>[
      for (final m in room.messages) (at: m.at, m: m, e: null),
      for (final e in _comings) (at: e.at, m: null, e: e),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final list = entries.reversed.toList();
    bool sameDay(int a, int b) {
      final x = DateTime.fromMillisecondsSinceEpoch(a), y = DateTime.fromMillisecondsSinceEpoch(b);
      return x.year == y.year && x.month == y.month && x.day == y.day;
    }

    final transcript = JumpToLatest(
      controller: _scroll,
      chat: _spot,
      incoming: _incoming(room),
      inset: const EdgeInsets.only(right: 14, bottom: 12),
      child: Transcript(
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          // The oldest end: where the room starts, and that what is said in it is sealed (each space's own key).
          if (i == list.length) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HostLine('*** You are in "${room.channel.name}". ***'),
              const HostLine('Messages here are sealed end to end.'),
            ]);
          }
          final x = list[i];
          final older = i + 1 < list.length ? list[i + 1] : null;
          final newer = i > 0 ? list[i - 1] : null;
          final newDay = older == null || !sameDay(older.at, x.at);
          final Widget line;
          final e = x.e, m = x.m;
          if (e != null) {
            line = HostLine('${lineName(_nameOf(e.id))} has ${e.came ? 'entered' : 'left'} the room.');
          } else {
            final mine = m!.from == room.me;
            final name = mine ? 'You' : (m.name.isEmpty ? Voice.instance.nameOf(m.from) : m.name);
            final lastOfRun = newer == null || newer.m == null || newer.m!.from != m.from || !sameDay(newer.at, m.at);
            line = Poof(
              key: ValueKey('poof-${m.id}'),
              gone: _poofing.contains(m.id),
              side: AxisDirection.left,
              onDone: () {
                _poofing.remove(m.id);
                room.delete(m);
              },
              child: ShownWords(
                key: ValueKey(m.id),
                facts: spaceFacts(m, mine: mine),
                builder: (_, shown) => MessageLine(
                name: name,
                // Each person keeps one of the room's six colours, by their id, and yours is your own.
                nameColor: mine ? c.nameMine : c.nameFor(m.from),
                mine: mine,
                body: shown?.bubble ?? m.text,
                original: shown == null ? null : OriginalLine(view: shown),
                status: lastOfRun ? clock(DateTime.fromMillisecondsSinceEpoch(m.at)) : null,
                onLongPress: (_) => _menu(m),
              )),
            );
          }
          if (!newDay) return line;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [HostLine.day(DateTime.fromMillisecondsSinceEpoch(x.at)), line]);
        },
      ),
    ));
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 560) {
        return ColoredBox(
          color: c.chrome,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: transcript),
            SizedBox(width: 200, child: Padding(padding: const EdgeInsets.fromLTRB(0, 4, 6, 4), child: _DialupPeople(people: people, panel: true))),
          ]),
        );
      }
      return ColoredBox(
        color: c.chrome,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _DialupPeopleStrip(people: people, open: _peopleOpen, onToggle: () => setState(() => _peopleOpen = !_peopleOpen)),
          if (_peopleOpen) Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 2), child: SizedBox(height: math.min(people.length, 4) * 44.0 + 8, child: _DialupPeople(people: people))),
          Expanded(child: transcript),
        ]),
      );
    });
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
        final (mineBg, mineInk) = myBubble(t, AppState.of(context));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            // Dial-Up writes the space as a chat room: its transcript, and who is here beside it or over it.
            child: isDialup(context)
                ? _chatRoom(room)
                : list.isEmpty
                ? Center(child: Text('No messages yet', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))
                // The down arrow over the list's foot, back to the newest message (Matt, 2026-11-17: "add a down arrow
                // that pops up when we enter a chat and we're not scrolled to the bottom or after we scroll up a certain
                // amount").
                : JumpToLatest(
                  controller: _scroll,
                  chat: _spot,
                  incoming: _incoming(room),
                  inset: EdgeInsets.only(right: t.space(3), bottom: t.space(3)),
                  child: ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2)),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final m = list[i];
                      // Laid out as a conversation of texts is (Matt, 2026-11-16: "update the chat inside spaces to match
                      // the look and layout of the normal chats"): a run from one person is one stack of bubbles, the
                      // name over its first, the face and the time by its last, and a day's heading where the day turns.
                      // The list runs newest first: [i + 1] is the message before, [i - 1] the one after.
                      final at = DateTime.fromMillisecondsSinceEpoch(m.at);
                      final before = i == list.length - 1 ? null : list[i + 1];
                      final after = i == 0 ? null : list[i - 1];
                      bool sameDay(HangoutMessage? o) {
                        if (o == null) return false;
                        final d = DateTime.fromMillisecondsSinceEpoch(o.at);
                        return d.year == at.year && d.month == at.month && d.day == at.day;
                      }
                      final newDay = !sameDay(before);
                      final first = newDay || before!.from != m.from;
                      final last = !sameDay(after) || after!.from != m.from;
                      final message = Poof(
                        key: ValueKey('poof-${m.id}'),
                        gone: _poofing.contains(m.id),
                        side: AxisDirection.left,
                        onDone: () {
                          _poofing.remove(m.id);
                          room.delete(m);
                        },
                        child: _Message(key: ValueKey(m.id), room: room, message: m, first: first, last: last, mineBg: mineBg, mineInk: mineInk, onDelete: () => setState(() => _poofing.add(m.id))),
                      );
                      if (!newDay) return message;
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: EdgeInsets.only(top: t.space(4), bottom: t.space(1)),
                          child: Text(dayHeading(at), textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
                        ),
                        message,
                      ]);
                    },
                  ),
                ),
          ),
          _DialupFoot(
            child: Padding(
              // Laid out as every other conversation's foot is (Matt, 2026-11-15: "Use the same compose input on spaces
              // that we use for the rest of the app ... just make it appear like the bottom of all the compose windows look").
              // The screen's foot always, as a conversation of texts leaves it, and the call's dock on top where there is one.
              padding: composerFootPadding(t, bottom: widget.bottom + MediaQuery.paddingOf(context).bottom),
              child: mayWrite
                  ? Builder(builder: (context) {
                      // The same buttons in the same places as every other conversation (lib/ui/composer_box.dart): a
                      // space's chat is words only, so Add an attachment, stickers and the microphone are greyed out.
                      final buttons = composerButtons(
                        t,
                        hasSomething: _text.text.isNotEmpty,
                        onAttach: null,
                        onSticker: null,
                        onRecord: null,
                        onSend: _text.text.trim().isEmpty ? null : _send,
                        emoji: Sms.remote,
                        onEmoji: () {
                          _focus.requestFocus();
                          Sms.instance.emojiPanel().catchError((_) {});
                        },
                      );
                      return ComposerBox(
                        typing: _typing,
                        plus: buttons.plus,
                        ends: buttons.ends,
                        below: buttons.below,
                        field: ComposerField(controller: _text, focusNode: _focus, hint: 'Message ${room.channel.name}', onSubmitted: _send, enterSends: AppState.of(context).enterSends),
                      );
                    })
                  : Text('Your role can\'t send messages here.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            ),
          ),
        ]);
      },
    );
  }
}

/// The chat's foot under Dial-Up: the silver panel every other conversation's composer stands in (GhostPage's), with
/// its light top edge, where the page's white showed through (the review of the looks, 2026-11-16). Elsewhere as it was.
class _DialupFoot extends StatelessWidget {
  const _DialupFoot({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDialup(context)) return child;
    final c = DialupColors.of(context.tokens);
    return DialupPanel(
      child: DecoratedBox(decoration: BoxDecoration(color: c.chrome, border: Border(top: BorderSide(color: c.hi, width: Bevel.ringOf(context)))), child: child),
    );
  }
}

typedef _Here = ({String id, String name, bool voice, bool me});

/// Dial-Up's "People Here: N" on a phone: a strip over the transcript with the count and the first names, which a press
/// opens out into the list ([_DialupPeople]) and closes again.
class _DialupPeopleStrip extends StatelessWidget {
  const _DialupPeopleStrip({required this.people, required this.open, required this.onToggle});
  final List<_Here> people;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = DialupColors.of(t);
    return GlacierPressable(
      onPressed: onToggle,
      semanticLabel: 'People Here: ${people.length}. ${open ? 'Hide' : 'Show'} who is here',
      builder: (context, state) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            CustomPaint(size: const Size(10, 10), painter: _Triangle(color: c.onChrome, open: open)),
            const SizedBox(width: 8),
            Text('People Here: ${people.length}', style: pageText(t, lineSize(context, 15), weight: 'bold', color: c.onChrome)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                people.map((p) => p.name).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pageText(t, lineSize(context, 14), color: c.inkSoft),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Dial-Up's list of who is in a space: one name to a 44px row in a white well, a speaker by each one in its voice,
/// filled while they talk (from the call's levels, as the faces ripple with them elsewhere). [panel] puts the count
/// over it, for the wide window where it stands beside the transcript.
class _DialupPeople extends StatelessWidget {
  const _DialupPeople({required this.people, this.panel = false});
  final List<_Here> people;
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = DialupColors.of(t);
    final v = Voice.instance;
    final levels = v.media?.levels ?? v.session?.media.levels;
    Widget rows(Map<String, double> loud) => Sunken(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final p in people)
                Semantics(
                  label: '${p.name}${p.voice ? ', in voice' : ''}',
                  excludeSemantics: true,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        SizedBox(
                          width: 18,
                          child: p.voice ? CustomPaint(size: const Size(16, 14), painter: _Speaker(color: c.ink, talking: (loud[p.me ? 'me' : p.id] ?? 0) > 0.08)) : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            lineName(p.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(t, lineSize(context), weight: p.me ? 'bold' : 'regular', color: p.me ? c.nameMine : c.ink),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        );
    final list = levels == null ? rows(const {}) : ValueListenableBuilder<Map<String, double>>(valueListenable: levels, builder: (context, loud, _) => rows(loud));
    if (!panel) return list;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 32,
        child: Align(alignment: Alignment.centerLeft, child: Text('People Here: ${people.length}', style: pageText(t, lineSize(context, 15), weight: 'bold', color: c.onChrome))),
      ),
      Expanded(child: list),
    ]);
  }
}

/// A disclosure triangle drawn as a path: pointing right while closed, down while open.
class _Triangle extends CustomPainter {
  const _Triangle({required this.color, required this.open});
  final Color color;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = open ? (Path()..moveTo(0, h * 0.2)..lineTo(w, h * 0.2)..lineTo(w / 2, h * 0.85)) : (Path()..moveTo(w * 0.2, 0)..lineTo(w * 0.85, h / 2)..lineTo(w * 0.2, h));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Triangle old) => old.color != color || old.open != open;
}

/// A loudspeaker drawn as a path, in the era's flat way: an outline while someone is in voice and quiet, filled with
/// its sound waves while they talk.
class _Speaker extends CustomPainter {
  const _Speaker({required this.color, required this.talking});
  final Color color;
  final bool talking;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(0, h * 0.35)
      ..lineTo(w * 0.22, h * 0.35)
      ..lineTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.5, h * 0.92)
      ..lineTo(w * 0.22, h * 0.65)
      ..lineTo(0, h * 0.65)
      ..close();
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(body, talking ? (Paint()..color = color) : stroke);
    if (talking) {
      canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h / 2), width: w * 0.5, height: h * 0.5), -0.9, 1.8, false, stroke);
      canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h / 2), width: w * 0.95, height: h * 0.95), -0.9, 1.8, false, stroke);
    }
  }

  @override
  bool shouldRepaint(_Speaker old) => old.color != color || old.talking != talking;
}


/// The facts a plugin that shows a message's words otherwise is asked by (the Translate plugin; Matt, 2026-11-17: "add
/// a translate plugin which can automatically translate texts when detected from another language"): none for your own.
MessageFacts? spaceFacts(HangoutMessage m, {required bool mine}) =>
    mine || m.text.trim().isEmpty ? null : MessageFacts(thread: -1, senders: [m.from], text: m.text, contact: false, outgoing: false, date: DateTime.fromMillisecondsSinceEpoch(m.at), id: 'space:${m.id}', network: 'space');

class _Message extends StatelessWidget {
  const _Message({super.key, required this.room, required this.message, required this.first, required this.last, required this.mineBg, required this.mineInk, this.onDelete});
  final HangoutRoom room;
  final HangoutMessage message;

  /// The first and the last of a run from one person on one day.
  final bool first, last;

  /// This person's own bubble colours (lib/backgrounds.dart myBubble), as in a conversation of texts.
  final Color mineBg, mineInk;

  /// Deletes it, with its puff.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => ShownWords(facts: spaceFacts(message, mine: message.from == room.me), builder: _build);

  /// The message, saying [shown]'s words where a plugin shows them otherwise, with the words as they came over it.
  Widget _build(BuildContext context, ShownView? shown) {
    final t = context.tokens;
    final m = message;
    final mine = m.from == room.me;
    final role = room.roster.roleOf(m.from);
    final owner = room.roster.isOwner(m.from);
    final name = m.name.isEmpty ? Voice.instance.nameOf(m.from) : m.name;
    final round = Radius.circular(lookCorner(t, '1.125rem', most: 1));
    final tight = Radius.circular(lookCorner(t, '0.375rem', most: 1));
    final faceSize = t.lenOf('1.75rem');
    final faceGap = mine ? 0.0 : faceSize + t.space(2);
    // Pressed and held: copy it, or delete it at once with a puff (Matt, 2026-11-15: "Don't ask for confirmation when
    // deleting a message and show a poof animation when one is deleted").
    void menu() {
      HapticFeedback.mediumImpact();
      showChoices(context, choices: [
        if (m.text.isNotEmpty) Choice('Copy', Lucide.copy, () => Clipboard.setData(ClipboardData(text: m.text))),
        ...translateChoices(context, spaceFacts(m, mine: mine)),
        if (room.canDelete(m)) Choice('Delete for everyone', Lucide.trash2, () => onDelete?.call(), danger: true),
      ]);
    }

    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
        decoration: BoxDecoration(
          color: mine ? mineBg : theirBubble(t, onBackground: false),
          border: !mine ? theirRim(t) : bubbleNeedsRim(mineBg, t.color('glacier-bg')) ? Border.all(color: t.color('app-ink-4'), width: 1) : null,
          borderRadius: BorderRadius.only(
            topLeft: !mine && !first ? tight : round,
            bottomLeft: !mine && !last ? tight : round,
            topRight: mine && !first ? tight : round,
            bottomRight: mine && !last ? tight : round,
          ),
        ),
        child: Text(shown?.bubble ?? m.text, style: pageText(t, t.fontSize('md'), color: mine ? mineInk : t.color('app-ink'), height: 1.3)),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: menu,
      onSecondaryTap: menu,
      child: Padding(
        padding: EdgeInsets.only(top: first ? t.space(2) : 2),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          // The name over a run's first bubble in the app's primary colour, as over a group of texts', and the space's
          // own role beside it where it is more than a member's.
          if (first && !mine)
            Padding(
              padding: EdgeInsets.only(left: faceGap + t.space(3), bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-accent')))),
                if (owner || role.id != room.roster.newcomer) ...[SizedBox(width: t.space(1) + 2), RoleTag(role: role, owner: owner)],
              ]),
            ),
          if (first && mine && (owner || role.id != room.roster.newcomer))
            Padding(padding: EdgeInsets.only(right: t.space(1), bottom: 2), child: RoleTag(role: role, owner: owner)),
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Their face by the run's last bubble, as in a group of texts.
            if (!mine) ...[
              SizedBox(width: faceSize, child: last ? Avatar(people: [Person(address: 'space:${m.from}', name: name)], size: faceSize) : null),
              SizedBox(width: t.space(2)),
            ],
            // The words as they came, dimmed, in a card over a translated bubble.
            Flexible(child: shown == null ? bubble : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [OriginalCard(view: shown, maxWidth: maxWidth), bubble])),
          ]),
          if (last)
            Padding(
              padding: EdgeInsets.only(top: 2, left: faceGap + t.space(2), right: t.space(2)),
              child: Text(clock(DateTime.fromMillisecondsSinceEpoch(m.at)), style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ),
        ]),
      ),
    );
  }
}

/// A role's name in a small pill: the owner's says Owner.
/// The button in a space's header that opens its members in a drawer (Matt, 2026-11-17: "the member list should show
/// up as a drawer like the add user, it should include a button to switch to add user at the top"). It had put the
/// members in the chat's place, and the chat back.
Widget _membersButton(BuildContext context, HangoutRoom room) =>
    IconTap(key: const ValueKey('space-members'), icon: Lucide.users, label: 'Members', onPressed: () => showSpaceMembers(context, room));

/// [room]'s members in the drawer (lib/ui/circles/members_drawer.dart), with Add people at its top opening the space's
/// invite drawer; greyed for someone the space does not let invite, and left out for a group's space, which nobody is
/// invited into.
Future<void> showSpaceMembers(BuildContext context, HangoutRoom room) => showMembersDrawer(
      context,
      title: 'Members',
      subtitle: room.channel.name,
      list: (_) => SpaceMembers(room: room, shrinkWrap: true),
      onAddPeople: room.channel.group != null ? null : () => showSpaceInvite(context, room.channel),
      mayAdd: room.can(Perm.invite),
    );

/// Everyone a space knows, for its member list and its settings: the owner, whoever is here now, whoever has been given
/// a role, and you; not the banned.
Map<String, List<String>> spacePeopleByRole(HangoutRoom room) {
  final r = room.roster;
  final people = <String>{r.ownerId, ...room.present.keys, ...r.assigned.keys, room.me}..remove('');
  final byRole = <String, List<String>>{};
  for (final id in people) {
    if (r.banned.contains(id)) continue;
    byRole.putIfAbsent(r.roleOf(id).id, () => []).add(id);
  }
  return byRole;
}

/// A space's members (Matt, 2026-11-17: "add a button to switch the chat to a member list"; now in a drawer,
/// showSpaceMembers), as a chat app's member list is: by role, highest first, each with their face, whether they are
/// here now or in voice, and their role. Pressing someone you outrank changes their role, where you may.
class SpaceMembers extends StatelessWidget {
  const SpaceMembers({super.key, required this.room, this.bottom = 0, this.shrinkWrap = false});
  final HangoutRoom room;

  /// What stands over the list's foot (the pill, the dock): room is left for it.
  final double bottom;

  /// As tall as its rows and no taller, for the drawer, which is as tall as what it holds.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Listenable.merge([room, Voice.instance]),
      builder: (context, _) {
        final r = room.roster;
        final byRole = spacePeopleByRole(room);
        final inVoice = Voice.instance.inChannel(room.channel).toSet();
        int order(String id) => inVoice.contains(id) ? 0 : (room.present.containsKey(id) ? 1 : 2);
        final total = byRole.values.fold<int>(0, (n, l) => n + l.length);
        final here = byRole.values.expand((l) => l).where((id) => order(id) < 2).length;
        int byOrder(String a, String b) {
          final o = order(a).compareTo(order(b));
          return o != 0 ? o : _nameOf(room, a).toLowerCase().compareTo(_nameOf(room, b).toLowerCase());
        }

        // The owner under an Owner heading of their own, as a circle's members list has it, so the heading and the
        // pill beside them say the same; then each role, highest first.
        final groups = <(String, Role, List<String>)>[
          if (r.ownerId.isNotEmpty && !r.banned.contains(r.ownerId) && byRole.values.any((l) => l.contains(r.ownerId))) ('Owner', r.roleOf(r.ownerId), [r.ownerId]),
          for (final role in r.ranked)
            if ([for (final id in byRole[role.id] ?? const <String>[]) if (!r.isOwner(id)) id] case final ids when ids.isNotEmpty) (role.name, role, ids..sort(byOrder)),
        ];
        // The count line and the headings on the drawer's gutter, where its head and Add people start.
        return ListView(
          shrinkWrap: shrinkWrap,
          padding: EdgeInsets.fromLTRB(DrawerHead.gutter(t), t.space(3), DrawerHead.gutter(t), t.space(4) + bottom),
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: t.space(3)),
              child: Text('$total member${total == 1 ? '' : 's'} · $here here now', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            ),
            for (final (heading, role, ids) in groups) ...[
              DrawerHeading('$heading · ${ids.length}'),
              PaneSection(
                children: [
                  for (final id in ids)
                    SettingRow(
                      // Your face from your own name, as a circle's members list draws it.
                      icon: Opacity(opacity: order(id) == 2 ? 0.5 : 1, child: RippleAvatar(name: id == room.me ? youFaceName() : _nameOf(room, id), level: 0, size: 30, ringed: inVoice.contains(id))),
                      label: id == room.me ? 'You' : _nameOf(room, id),
                      hint: Text(inVoice.contains(id) ? 'In voice' : (room.present.containsKey(id) ? 'Here now' : 'Away')),
                      value: RoleTag(role: role, owner: r.isOwner(id)),
                      onPress: room.canManage && r.outranks(room.me, id) ? () => pickRole(context, room, id, _nameOf(room, id)) : null,
                    ),
                ],
              ),
              SizedBox(height: t.space(5)),
            ],
          ],
        );
      },
    );
  }
}

/// Each part of a space's settings in a colour of its own, as Settings' sections are (Matt, 2026-11-17: "add colors to
/// the spaces settings"): the rows' icons sit on a wash of it.
Widget _hued(String hue, Widget section) => GlacierScope(attrs: {'hue': hue}, child: section);

class RoleTag extends StatelessWidget {
  const RoleTag({super.key, required this.role, this.owner = false});
  final Role role;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strong = owner || role.id == Role.admin;
    final (fill, words) = strongFill(t);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
      decoration: BoxDecoration(
        color: strong ? fill : t.color('app-paper-3'),
        borderRadius: BorderRadius.circular(t.radius('full')),
      ),
      child: Text(owner ? 'Owner' : role.name, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: strong ? words : t.color('app-ink-2'))),
    );
  }
}

/// The line under a space's name in its header: its description, or else what kind of space it is, or how many are
/// here in a voice space with people in it.
String spaceHeaderLine(VoiceChannel c, HangoutRoom? room) {
  final about = room?.about;
  if (about != null) return about.replaceAll(RegExp(r'\s+'), ' ');
  final here = room?.present.length ?? 0;
  if (c.hasVoice && here > 0) return '$here here';
  return c.kind.label;
}

/// Opens the space's description to write, for the owner and admins (HangoutRoom.setAbout).
void editSpaceAbout(BuildContext context, HangoutRoom room) {
  if (!room.canManage) return;
  unawaited(push<void>(context, (_) => _AboutPage(room: room)));
}

class _AboutPage extends StatefulWidget {
  const _AboutPage({required this.room});
  final HangoutRoom room;

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  late final _words = TextEditingController(text: widget.room.about ?? '');

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.room.setAbout(_words.text);
    if (!mounted) return;
    if (!ok) {
      toast(context, 'Only the owner and admins can change the description.', tone: GlacierToastTone.danger);
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GhostPage(
      title: 'Description',
      body: ListView(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
        children: [
          PaneSection(
            description: const Text('Shown under the space\'s name, to everyone in it. Leave it empty to show none.'),
            children: [
              SettingRowBox(
                child: GlacierInput(
                  key: const ValueKey('about-words'),
                  controller: _words,
                  ariaLabel: 'Description',
                  placeholder: 'What this space is for',
                  autoFocus: true,
                  autoCapitalize: TextCapitalization.sentences,
                  maxLength: SpaceAbout.most,
                  size: GlacierFieldSize.md,
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space(4)),
          PaneSection(children: [SettingRow(key: const ValueKey('about-save'), icon: AppIcon(Lucide.check, size: 18), label: 'Save', onPress: _save)]),
        ],
      ),
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
        final byRole = spacePeopleByRole(room);
        final c = room.channel;
        return GhostPage(
          title: settings ? c.name : 'Roles and permissions',
          // As a Settings page: each row's icon on its section's colour.
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (settings) ...[
                _hued('blue', PaneSection(title: 'Space', children: [
                  if (room.can(Perm.invite)) SettingRow(icon: AppIcon(Lucide.userPlus, size: 18), label: 'Invite people', hint: const Text('Friends in the app, anyone by a text, or the link.'), onPress: () => showSpaceInvite(context, c)),
                  SettingRow(icon: AppIcon(Lucide.users, size: 18), label: 'Owner', value: Text(r.isOwner(room.me) ? 'You' : (r.hasOwner ? _nameOf(room, r.ownerId) : 'None'))),
                  // What the space is for, under its name in the header; the owner and admins write it (Matt, 2026-11-17).
                  SettingRow(
                    icon: AppIcon(Lucide.fileText, size: 18),
                    label: 'Description',
                    hint: Text(room.about ?? (manage ? 'None yet. Shown under the space\'s name.' : 'None'), maxLines: 2, overflow: TextOverflow.ellipsis),
                    onPress: manage ? () => editSpaceAbout(context, room) : null,
                  ),
                ])),
                gap,
              ],
              if (!r.hasOwner)
                SettingsCallout(child: const Text('This space was made before roles, so it has no owner: everyone in it is a member, and no one can change that.'))
              else if (!manage)
                SettingsCallout(child: Text('You\'re ${r.isOwner(room.me) ? 'the owner' : 'a ${r.roleOf(room.me).name.toLowerCase()}'}. The owner and admins change roles.')),
              if (r.hasOwner) ...[
                _hued('green', PaneSection(
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
                )),
                gap,
                _hued('purple', PaneSection(
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
                )),
                gap,
                _hued('mint', PaneSection(
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
                )),
                if (settings) ...[
                  gap,
                  _hued('red', PaneSection(title: '', children: [
                    SettingRow(icon: AppIcon(Lucide.trash2, size: 18), label: 'Delete space', hint: const Text('From this phone and your computer.'), onPress: () => confirmDeleteHangout(context, c)),
                  ])),
                ],
                if (r.banned.isNotEmpty) ...[
                  gap,
                  _hued('coral', PaneSection(
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
                  )),
                ],
              ],
            ],
          ),
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
                  // A Files space's permissions only in a Files space (Perm.files).
                  for (final p in Perm.values.where(Perm.of(room.channel.kind).contains))
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
/// it, its settings and roles, invite people into it (space_invite.dart), delete it.
void showHangoutMenu(BuildContext context, VoiceChannel channel, {VoidCallback? onOpen}) {
  final v = Voice.instance;
  final room = v.hangoutFor(channel);
  showChoices(context, title: channel.name, choices: [
    if (onOpen != null) Choice('Open', LucideMore.messageCircle, onOpen),
    Choice('Settings and permissions', Lucide.shieldCheck, () => push(context, (_) => HangoutSettingsScreen(channel: channel))),
    if (room == null || room.can(Perm.invite)) Choice('Invite people', Lucide.userPlus, () => showSpaceInvite(context, channel)),
    Choice('Delete space', Lucide.trash2, () => confirmDeleteHangout(context, channel), danger: true),
  ]);
}

/// Asks first, then leaves [channel]: its call if this phone is in it, and the space itself, off this phone and its
/// computer (Voice.forget), as a swipe on its row asks (Matt, 2026-11-17: "can be swiped to leave a space or delete /
/// archive"). Its link brings it back.
void confirmLeaveHangout(BuildContext context, VoiceChannel channel) {
  showChoices(context, title: 'Leave ${channel.name}? It goes from your list; its link brings you back.', choices: [
    Choice('Leave space', Lucide.logOut, () async {
      final v = Voice.instance;
      if (v.viewing?.seed == channel.seed) v.view(null);
      await v.forget(channel);
      if (context.mounted) toast(context, 'Left ${channel.name}');
    }, danger: true),
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
