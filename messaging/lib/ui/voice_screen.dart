import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../voice/channels.dart';
import '../voice/voice.dart';
import '../sms.dart';
import 'common.dart';
import '../voice/rtc.dart';
import 'shell.dart';
import 'nav_bar.dart';
import 'ripple_avatar.dart';
import 'hangout_screen.dart';
import 'space_designs/space_design.dart';
import 'space_invite.dart';
import '../kit/semantic_colors.dart';

/// Voice channels (Matt, 2026-11-14: "always open voice channels that you can jump in and out at any time and you can
/// see who's connected and also toggle video on and off"): each channel with who is in it, a press to hop in, and,
/// while in one, everyone in it (their picture where their video is on) and the buttons for the microphone, the
/// sound, the camera and leaving.
class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final s = v.session;
        // In a call, the page is the call and nothing else: who is in it, and its buttons in the dock (Matt,
        // 2026-11-15: "I want the call screen to be super simple too just a list of chatters and the call controls").
        // A hangout's call is its page: the people or the chat, its roles (lib/ui/hangout_screen.dart).
        // Beside the list on a wide screen the people are in the list's place (HangoutScreen there) and this side is
        // the hangout's chat, with its videos above it once anyone turns one on (HangoutStage).
        // On a narrow phone with a design chosen, the design is the call page (space_design.dart).
        final design = inlineSpaceCall(context, s);
        if (design != null) return design;
        if (s != null && s.channel.hangout && AppShell.wideOf(context)) return HangoutStage(key: ValueKey('stage-${s.channel.room}'), channel: s.channel);
        if (s != null && s.channel.hangout) return HangoutScreen(key: ValueKey('hangout-${s.channel.room}'), channel: s.channel);
        // A hangout pressed in the list: its chat where a conversation would be, who is in it and Join at its top.
        final seen = v.viewing;
        if (s == null && seen != null && v.channels.any((c) => c.seed == seen.seed)) return HangoutScreen(key: ValueKey('hangout-${seen.room}'), channel: seen);
        if (s != null) {
          return GhostPage(
            title: s.channel.name,
            actions: [
              // A hangout's, not a group's: a group's channel is its members' alone.
              if (s.channel.group == null) IconTap(icon: Lucide.userPlus, label: 'Invite people', onPressed: () => showSpaceInvite(context, s.channel)),
            ],
            body: Stack(children: [
              ListView(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), 120 + MediaQuery.paddingOf(context).bottom),
                children: [CallPanel(session: s)],
              ),
              Positioned(left: 0, right: 0, bottom: MediaQuery.paddingOf(context).bottom + NavPill.inset(t), child: Center(child: CallDock(session: s))),
            ]),
          );
        }
        return GhostPage(
          title: 'Spaces',
          actions: [IconTap(icon: Lucide.plus, label: 'New space', onPressed: () => push(context, (_) => const NewChannelScreen()))],
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (v.channels.isEmpty)
                SettingsCallout(child: const Text('Every group of friends has a space. Make one of your own with + and share it with friends you added by username.'))
              else
                PaneSection(title: 'Spaces', children: [for (final c in v.channels) _ChannelRow(channel: c)]),
            ],
          ),
        );
      },
    );
  }
}

class _ChannelRow extends StatelessWidget implements PaneRow {
  const _ChannelRow({required this.channel});
  final VoiceChannel channel;

  @override
  Widget build(BuildContext context) {
    final v = Voice.instance;
    final here = v.session?.channel.room == channel.room;
    // In it: who the call has; otherwise who the hub says is there.
    final inIt = here ? v.session!.members.keys.toList() : v.inChannel(channel);
    final who = inIt.isEmpty ? (here ? 'Just you' : 'Nobody here') : inIt.map(v.nameOf).join(', ');
    return SettingRow(
      icon: AppIcon(channel.group != null ? Lucide.users : LucideMore.headphones, size: 18),
      label: channel.name,
      hint: Text(here ? 'You and ${inIt.isEmpty ? 'nobody else yet' : who}' : who, maxLines: 1, overflow: TextOverflow.ellipsis),
      value: Text(here ? 'Connected' : (inIt.isEmpty ? 'Join' : 'Join · ${inIt.length}')),
      // A hangout opens its page (its chat, and a way into voice); a group's channel is joined at once.
      onPress: here
          ? null
          : channel.hangout
              ? () => push(context, (_) => HangoutScreen(channel: channel))
              : () async {
                  try {
                    await v.join(channel);
                  } catch (e) {
                    if (context.mounted) toast(context, 'Couldn\'t join: $e', tone: GlacierToastTone.danger);
                  }
                },
      control: channel.group != null
          ? null
          : IconTap(
              icon: Lucide.ellipsis,
              label: 'Space options',
              onPressed: () => showHangoutMenu(context, channel),
            ),
    );
  }
}

/// Puts [c]'s link on the clipboard: anyone with it can join from a browser (site/join).
void copyInvite(BuildContext context, VoiceChannel c) {
  Clipboard.setData(ClipboardData(text: c.link));
  toast(context, 'Invite link copied. Anyone with it can join ${c.name} from a browser.');
}

/// The channel you're in (Matt, 2026-11-15: "make the voice chats a list of participants don't show the squares
/// unless someone turns on video"): a picture for each who has video on, then everyone as a list, each face rippling
/// while they talk.
class CallPanel extends StatelessWidget {
  const CallPanel({super.key, required this.session, this.videos = true});
  final VoiceSession session;

  /// With the pictures of whoever has video on above the people; off where they are shown elsewhere (CallVideos,
  /// the pane beside a hangout's people on a wide screen).
  final bool videos;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final media = v.media;
    final levels = media?.levels ?? session.media.levels;
    return ListenableBuilder(
      listenable: Listenable.merge([session, levels, ?media?.remote, ?media?.localVideo, ?v.hangoutFor(session.channel)]),
      builder: (context, _) {
        final loud = levels.value;
        final people = <({String id, String name, bool guest, bool muted, MediaStream? video, bool me})>[
          (id: 'me', name: 'You', guest: false, muted: session.muted || session.deafened, video: media?.localVideo.value, me: true),
          for (final m in session.members.values)
            (id: m.id, name: v.nameOf(m.id), guest: m.guest, muted: m.muted, video: m.video ? media?.remote.value[m.id] : null, me: false),
        ];
        final withVideo = [for (final p in people) if (p.video != null) p];
        // A hangout's: each person's role beside their name, where it is not the one everyone starts with.
        final room = v.hangoutFor(session.channel);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (videos && withVideo.isNotEmpty) ...[
            LayoutBuilder(builder: (context, box) {
              final across = withVideo.length == 1 ? 1 : (box.maxWidth / 240).floor().clamp(2, 4);
              final w = (box.maxWidth - t.space(2) * (across - 1)) / across;
              return Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
                for (final p in withVideo) SizedBox(width: w, height: w * 0.75, child: _Tile(name: p.guest ? '${p.name} (guest)' : p.name, muted: p.muted, stream: p.video, mirror: p.me)),
              ]);
            }),
            SizedBox(height: t.space(3)),
          ],
          // The people as plain rows, not in a card (Matt, 2026-11-15: "Make the lists of people not in a card"), with
          // room above and below for the first and last face's rings.
          Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(2)),
              child: Column(children: [
                for (final p in people)
                  // Press and hold (or press with the other button) for what can be done about them here.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => showPerson(context, session, p.id, p.name),
                    onSecondaryTap: () => showPerson(context, session, p.id, p.name),
                    child: Padding(
                    padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(2), t.space(2)),
                    child: Row(children: [
                      // A little larger on a computer (Matt, 2026-11-15: "make the voice chat avatars a little larger on desktop").
                      RippleAvatar(name: p.me ? (session.name.isEmpty ? 'You' : session.name) : p.name, level: loud[p.id] ?? 0, muted: p.muted, size: Sms.computer ? 52 : 40),
                      SizedBox(width: t.space(3)),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: p.name),
                            if (p.guest) TextSpan(text: '  guest', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')),
                        ),
                      ),
                      if (room != null)
                        if ((p.me ? room.me : p.id) case final who when room.roster.isOwner(who) || room.roster.roleOf(who).id != room.roster.newcomer)
                          Padding(padding: EdgeInsets.only(right: t.space(2)), child: RoleTag(role: room.roster.roleOf(who), owner: room.roster.isOwner(who))),
                      if (p.video != null) Padding(padding: EdgeInsets.only(right: t.space(2)), child: AppIcon(Lucide.video, size: 16, color: t.color('app-ink-3'))),
                      if (p.muted) Padding(padding: EdgeInsets.only(right: t.space(3)), child: AppIcon(LucideMore.micOff, size: 16, wash: false, color: t.danger)),
                    ]),
                  )),
              ])),
        ]);
      },
    );
  }
}

/// The pictures of whoever in [session] has video on, filling the space given: one alone, two to four two across,
/// more three across (Matt, 2026-11-15: "when a video starts split the right side 50/50 showing the videos above the
/// chat"). Nothing where nobody has video on ([any]).
class CallVideos extends StatelessWidget {
  const CallVideos({super.key, required this.session});
  final VoiceSession session;

  /// Whether anyone in [session] has video on now, this device included.
  static bool any(VoiceSession session) {
    final media = Voice.instance.media;
    if (media?.localVideo.value != null) return true;
    return session.members.values.any((m) => m.video && media?.remote.value[m.id] != null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final media = v.media;
    return ListenableBuilder(
      listenable: Listenable.merge([session, ?media?.remote, ?media?.localVideo]),
      builder: (context, _) {
        final tiles = <({String name, MediaStream stream, bool muted, bool me})>[
          if (media?.localVideo.value case final mine?) (name: 'You', stream: mine, muted: session.muted || session.deafened, me: true),
          for (final m in session.members.values)
            if (m.video && media?.remote.value[m.id] != null) (name: m.guest ? '${v.nameOf(m.id)} (guest)' : v.nameOf(m.id), stream: media!.remote.value[m.id]!, muted: m.muted, me: false),
        ];
        if (tiles.isEmpty) return const SizedBox.shrink();
        final across = tiles.length == 1 ? 1 : (tiles.length <= 4 ? 2 : 3);
        final rows = (tiles.length / across).ceil();
        final gap = t.space(2);
        return Column(children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            Expanded(
              child: Row(children: [
                for (var c = 0; c < across; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: r * across + c < tiles.length
                        ? _Tile(name: tiles[r * across + c].name, muted: tiles[r * across + c].muted, stream: tiles[r * across + c].stream, mirror: tiles[r * across + c].me)
                        : const SizedBox.shrink(),
                  ),
                ],
              ]),
            ),
          ],
        ]);
      },
    );
  }
}

/// The call's buttons: the microphone, the sound, the camera and leaving, in a dock like the app's pill.
class CallDock extends StatelessWidget {
  const CallDock({super.key, required this.session});
  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final red = t.danger;
    // The size of the sidebar's dock (Matt, 2026-11-15: "the call controls are also too large they should match the
    // size of the sidebar control dock"): its rings, its frosted pill and the step between them (NavPill), and on a
    // computer the size that dock rests at (pillScrolledScale).
    final ring = t.len('app-ring');
    final gap = t.space(2);
    final radius = BorderRadius.circular(t.radius('full'));
    final mark = t.lenOf('1.15rem');
    Widget button(LucideIcon icon, String label, VoidCallback onPress, {bool on = false, bool danger = false}) => GlacierPressable(
          onPressed: onPress,
          semanticLabel: label,
          builder: (context, state) => Container(
            width: ring,
            height: ring,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger ? red.withValues(alpha: state.pressed ? 0.8 : 1) : (on ? t.color('app-ink') : t.color(state.pressed ? 'app-paper-3' : 'glacier-bg')),
              border: danger || on ? null : Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: mark, wash: false, color: danger ? const Color(0xFFFFFFFF) : (on ? t.color('app-paper') : t.color('app-ink'))),
          ),
        );
    final dock = ListenableBuilder(
      listenable: session,
      builder: (context, _) => ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
            foregroundDecoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: radius),
            decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 82%, transparent)'), borderRadius: radius),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
              // Pills, each with a chevron that opens the devices to choose from (Matt, 2026-11-15: "on the microphone
              // icon and the deafen icon make them pill shaped with a little chevron facing up that opens a popover to
              // select input and output devices respectively").
              DevicePill(
                icon: session.muted ? LucideMore.micOff : Lucide.mic,
                label: session.muted ? 'Unmute' : 'Mute',
                on: session.muted,
                onPress: () => session.setMuted(!session.muted),
                kind: 'audioinput',
              ),
              DevicePill(
                icon: session.deafened ? LucideMore.headphoneOff : LucideMore.headphones,
                label: session.deafened ? 'Hear again' : 'Deafen',
                on: session.deafened,
                onPress: () => session.setDeafened(!session.deafened),
                kind: 'audiooutput',
              ),
              button(session.video ? Lucide.video : LucideMore.videoOff, session.video ? 'Turn video off' : 'Turn video on', () => session.setVideo(!session.video), on: session.video),
              button(LucideMore.phoneOff, 'Leave', () => Voice.instance.leave(), danger: true),
            ]),
          ),
        ),
      ),
    );
    return Sms.computer ? Transform.scale(scale: pillScrolledScale, alignment: Alignment.bottomCenter, child: dock) : dock;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.name, required this.muted, this.stream, this.mirror = false});
  final String name;
  final bool muted;
  final MediaStream? stream;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radius('lg')),
      child: ColoredBox(
        color: t.color('app-paper-3'),
        child: Stack(fit: StackFit.expand, children: [
          if (stream != null) StreamView(stream: stream!, mirror: mirror),
          Positioned(
            left: t.space(2),
            bottom: t.space(2),
            right: t.space(2),
            child: Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: const Color(0xFFFFFFFF)))),
              if (muted) ...[SizedBox(width: t.space(1)), AppIcon(LucideMore.micOff, size: 14, wash: false, color: t.danger)],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A picture from a call.
class StreamView extends StatefulWidget {
  const StreamView({super.key, required this.stream, this.mirror = false});
  final MediaStream stream;
  final bool mirror;

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) {
      if (!mounted) return;
      _renderer.srcObject = widget.stream;
      setState(() => _ready = true);
    });
  }

  @override
  void didUpdateWidget(StreamView old) {
    super.didUpdateWidget(old);
    if (_ready && !identical(old.stream, widget.stream)) _renderer.srcObject = widget.stream;
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready ? RTCVideoView(_renderer, mirror: widget.mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover) : const SizedBox.shrink();
}

/// A new channel: its name, and the friends it is shared with.
class NewChannelScreen extends StatefulWidget {
  const NewChannelScreen({super.key});

  @override
  State<NewChannelScreen> createState() => _NewChannelScreenState();
}

class _NewChannelScreenState extends State<NewChannelScreen> {
  final _name = TextEditingController();
  final Set<String> _with = {};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final v = Voice.instance;
    final c = await v.make(_name.text);
    final friends = [for (final f in Buddies.instance.friends) if (_with.contains(f.id)) f];
    final missed = friends.isEmpty ? const <Buddy>[] : await v.share(c, friends);
    if (!mounted) return;
    toast(context, friends.isEmpty ? '${c.name} made' : '${c.name} shared with ${friends.length - missed.length}${missed.isEmpty ? '' : '; couldn\'t reach ${missed.map((f) => f.shown).join(', ')}'}');
    // A call, started: in it at once, its page in this one's place.
    try {
      await v.join(c);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t join: $e', tone: GlacierToastTone.danger);
    }
    if (!mounted) return;
    final shell = AppShell.maybeOf(context);
    if (shell != null) {
      shell.go('voice');
    } else {
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(pageBuilder: (context, _, _) => const VoiceScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final friends = Buddies.instance.friends;
    return GhostPage(
      title: 'New space',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: StatefulBuilder(
          builder: (context, set) => ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              PaneSection(title: 'Name', children: [
                SettingRowBox(child: GlacierInput(controller: _name, placeholder: 'Space name', ariaLabel: 'Space name', autoFocus: true, autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
              ]),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'Share with',
                description: Text(friends.isEmpty ? 'Add friends by username (Settings › Me › Friends) to share spaces with them.' : 'They can see who\'s in it and hop in any time.'),
                children: [
                  for (final f in friends)
                    SettingRow(
                      icon: AppIcon(Lucide.userRound, size: 18),
                      label: f.shown,
                      control: GlacierSwitch(checked: _with.contains(f.id), onCheckedChange: (on) => set(() => on ? _with.add(f.id) : _with.remove(f.id)), ariaLabel: f.shown),
                    ),
                ],
              ),
              SizedBox(height: t.space(6)),
              PaneSection(children: [SettingRow(icon: AppIcon(LucideMore.phoneCall, size: 18), label: 'Start the call', onPress: _make)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group calling, or a friend's invite into a space: shown over everything until joined or put away.
class RingCard extends StatelessWidget {
  const RingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final r = v.ringing;
        if (r == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.fromLTRB(t.space(3), MediaQuery.paddingOf(context).top + t.space(2), t.space(3), 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.lenOf('30rem')),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radius('xl')),
                child: ColoredBox(
                  color: t.color('app-ink'),
                  child: Padding(
                    padding: EdgeInsets.all(t.space(3)),
                    child: Row(children: [
                      AppIcon(r.invite ? Lucide.userPlus : LucideMore.phoneCall, size: 22, wash: false, color: t.color('app-paper')),
                      SizedBox(width: t.space(3)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(r.invite ? '${r.from} invited you to ${r.channel.name}' : r.channel.name, maxLines: r.invite ? 2 : 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold', color: t.color('app-paper'))),
                          Text(r.invite ? 'Now in your spaces' : '${r.from} is calling the group', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-paper'))),
                        ]),
                      ),
                      IconTap(icon: Lucide.x, label: 'Not now', color: t.color('app-paper'), onPressed: v.dismissRing),
                      SizedBox(width: t.space(1)),
                      GlacierPressable(
                        onPressed: () async {
                          try {
                            await v.join(r.channel);
                          } catch (e) {
                            if (context.mounted) toast(context, 'Couldn\'t join: $e', tone: GlacierToastTone.danger);
                          }
                        },
                        semanticLabel: 'Join',
                        builder: (context, state) => Container(
                          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                          decoration: BoxDecoration(color: t.online, borderRadius: BorderRadius.circular(t.radius('full'))),
                          child: Text('Join', style: pageText(t, t.fontSize('sm'), weight: 'bold', color: const Color(0xFFFFFFFF))),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A voice channel among the conversations (Matt, 2026-11-15: "add voice chats to the list as well"): a card like a
/// conversation's, who is in it now (live, in green) or when it last had anyone, and a press to hop in.
class VoiceRow extends StatelessWidget {
  const VoiceRow({super.key, required this.channel, required this.onPress});
  final VoiceChannel channel;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final face = t.lenOf('3rem');
    final green = t.online;
    final here = v.session?.channel.room == channel.room;
    final inIt = here ? ['me', ...v.session!.members.keys] : v.inChannel(channel);
    final live = inIt.isNotEmpty;
    final last = v.lastActive(channel);
    final who = here
        ? (inIt.length == 1 ? 'You\'re in · just you' : 'You\'re in · ${inIt.where((i) => i != 'me').map(v.nameOf).join(', ')}')
        : live
            ? inIt.map(v.nameOf).join(', ')
            : 'Nobody here · hop in any time';
    // Held, or pressed with the other button: a hangout's menu (Matt, 2026-11-15: "there also needs to be a context
    // menu to open settings for hangouts and manage permissions and such as well as delete the hangouts").
    void menu() {
      if (channel.hangout) showHangoutMenu(context, channel, onOpen: onPress);
    }

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPress: channel.hangout ? menu : null,
      onSecondaryTap: channel.hangout ? menu : null,
      child: GlacierPressable(
      onPressed: onPress,
      semanticLabel: '${channel.name}, space, ${live ? '${inIt.length} in it' : 'nobody in it'}',
      builder: (context, state) => Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')),
        child: Container(
          decoration: BoxDecoration(
            color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
            borderRadius: BorderRadius.circular(t.lenOf('1rem')),
            border: Border.all(color: here ? green : const Color(0x00000000), width: 2),
          ),
          padding: EdgeInsets.symmetric(horizontal: t.space(3) - 2, vertical: t.space(3) - 2),
          child: Row(children: [
            Container(
              width: face,
              height: face,
              decoration: BoxDecoration(shape: BoxShape.circle, color: live ? green.withValues(alpha: 0.16) : t.color('app-paper-3')),
              alignment: Alignment.center,
              child: AppIcon(channel.group != null ? Lucide.users : LucideMore.headphones, size: 20, wash: false, color: live ? green : t.color('app-ink-2')),
            ),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: live ? 'bold' : 'semibold', color: t.color('app-ink')))),
                  SizedBox(width: t.space(2)),
                  if (live)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: green)),
                      SizedBox(width: t.space(1)),
                      Text('Live', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: green)),
                    ])
                  else if (last != null)
                    Text(listWhen(last), style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                ]),
                SizedBox(height: t.lenOf('0.15rem')),
                Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color(live ? 'app-ink-2' : 'app-ink-3'))),
              ]),
            ),
          ]),
        ),
      ),
    ),
    );
  }
}

/// The call you're in, as a banner in the sidebar just above the dock (Matt, 2026-11-15: "switch the active call to
/// be a banner again in the sidebar just above the navigation bar"): a beating green dot, the channel, how long and
/// who is talking, their faces rippling, and mute and leave. Pressed, it opens the call.
class CallBanner extends StatefulWidget {
  const CallBanner({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<CallBanner> createState() => _CallBannerState();
}

class _CallBannerState extends State<CallBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The time in the call, a second at a time.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && Voice.instance.session != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _beat.dispose();
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final s = v.session;
        if (s == null) return const SizedBox.shrink();
        final levels = v.media?.levels ?? s.media.levels;
        final green = t.online;
        final red = t.danger;
        return ListenableBuilder(
          listenable: Listenable.merge([s, levels]),
          builder: (context, _) {
            final loud = levels.value;
            final talking = [
              if ((loud['me'] ?? 0) > RippleAvatar.talking && !s.muted) ('me', s.name.isEmpty ? 'You' : s.name),
              for (final m in s.members.values)
                if ((loud[m.id] ?? 0) > RippleAvatar.talking && !m.muted) (m.id, v.nameOf(m.id)),
            ];
            final people = s.members.length + 1;
            final radius = BorderRadius.circular(t.radius('full'));
            return GlacierPressable(
              onPressed: widget.onOpen,
              semanticLabel: 'In ${s.channel.name}, $people connected${s.muted ? ', muted' : ''}. Open the call.',
              builder: (context, state) => ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(t.space(4), t.space(1) + 2, t.space(1) + 2, t.space(1) + 2),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(green.withValues(alpha: state.pressed ? 0.24 : 0.16), t.colorOf('color-mix(in srgb, var(--glacier-bg) 88%, transparent)')),
                      borderRadius: radius,
                      border: Border.all(color: green.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Row(children: [
                      FadeTransition(
                        opacity: Tween(begin: 0.35, end: 1.0).animate(_beat),
                        child: Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: green)),
                      ),
                      SizedBox(width: t.space(2)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(s.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: t.color('app-ink'))),
                          Text(
                            '${_clock(DateTime.now().difference(s.since ?? DateTime.now()))} · ${talking.isEmpty ? (people == 1 ? 'just you' : '$people here') : '${talking.map((x) => x.$2).join(', ')} talking'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(t, t.fontSize('xs'), color: talking.isEmpty ? t.color('app-ink-3') : green),
                          ),
                        ]),
                      ),
                      for (final (id, name) in talking.take(3))
                        Padding(padding: EdgeInsets.only(left: t.space(1)), child: RippleAvatar(name: name, level: loud[id] ?? 0, size: 26)),
                      SizedBox(width: t.space(2)),
                      IconTap(icon: s.muted ? LucideMore.micOff : Lucide.mic, label: s.muted ? 'Unmute' : 'Mute', size: 18, color: s.muted ? red : null, onPressed: () => s.setMuted(!s.muted)),
                      SizedBox(width: t.space(1)),
                      GlacierPressable(
                        onPressed: () => v.leave(),
                        semanticLabel: 'Leave the call',
                        builder: (context, state) => Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: red.withValues(alpha: state.pressed ? 0.8 : 1)),
                          alignment: Alignment.center,
                          child: const AppIcon(LucideMore.phoneOff, size: 16, wash: false, color: Color(0xFFFFFFFF)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// What can be done about someone in the call, from this device (Matt, 2026-11-15: "add the ability to press and hold
/// on a user to habe options like muting changing volume levels for that user and more"): silence them here, how loud
/// they are here, add them as a friend where they have a username, copy their name. For yourself: mute and deafen.
void showPerson(BuildContext context, VoiceSession session, String id, String name) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: context.tokens.sheetScrim,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _PersonSheet(session: session, id: id, name: name),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.session, required this.id, required this.name});
  final VoiceSession session;
  final String id;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final v = Voice.instance;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), pad.bottom + t.space(3)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.lenOf('30rem')),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radius('xl')),
                child: ColoredBox(
                  color: t.color('app-paper-2'),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([v, session]),
                    builder: (context, _) {
                      final me = id == 'me';
                      final m = session.members[id];
                      final gone = !me && m == null;
                      final friend = m?.username == null ? null : Buddies.instance.all.where((b) => b.username == m!.username).firstOrNull;
                      return Padding(
                        padding: EdgeInsets.all(t.space(4)),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            RippleAvatar(name: name, level: 0, size: 44),
                            SizedBox(width: t.space(3)),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
                                Text(
                                  me ? 'You' : gone ? 'Left the call' : m!.guest ? 'Guest, from a link' : (m.username == null ? 'In the call' : '@${m.username}'),
                                  style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                                ),
                              ]),
                            ),
                          ]),
                          SizedBox(height: t.space(3)),
                          if (me) ...[
                            SettingRow(label: 'Mute', control: GlacierSwitch(checked: session.muted, onCheckedChange: session.setMuted, ariaLabel: 'Mute')),
                            SettingRow(label: 'Deafen', hint: const Text('Hear nobody, and say nothing.'), control: GlacierSwitch(checked: session.deafened, onCheckedChange: session.setDeafened, ariaLabel: 'Deafen')),
                          ] else if (!gone) ...[
                            SettingRow(
                              icon: AppIcon(LucideMore.micOff, size: 18),
                              label: 'Mute for me',
                              hint: const Text('Only you stop hearing them.'),
                              control: GlacierSwitch(checked: v.silenced(id), onCheckedChange: (on) => v.setSilenced(id, on), ariaLabel: 'Mute $name for me'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: t.space(2)),
                              child: Row(children: [
                                AppIcon(Lucide.volume2, size: 18, color: t.color('app-ink-2')),
                                SizedBox(width: t.space(3)),
                                Expanded(child: VolumeSlider(value: v.volumeOf(id), onChanged: (x) => v.setVolume(id, x), label: 'Volume for $name')),
                                SizedBox(width: t.space(3)),
                                SizedBox(width: 44, child: Text('${(v.volumeOf(id) * 100).round()}%', textAlign: TextAlign.end, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink')))),
                              ]),
                            ),
                            if (m!.username != null && friend?.state != 'yes')
                              SettingRow(
                                icon: AppIcon(Lucide.userPlus, size: 18),
                                label: friend?.state == 'asked' ? 'Friend request sent' : 'Add @${m.username} as a friend',
                                disabled: friend != null,
                                onPress: () async {
                                  try {
                                    await Buddies.instance.add(m.username!);
                                    if (context.mounted) toast(context, 'Asked @${m.username}');
                                  } catch (e) {
                                    if (context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
                                  }
                                },
                              ),
                            SettingRow(
                              icon: AppIcon(Lucide.copy, size: 18),
                              label: 'Copy name',
                              onPress: () {
                                Clipboard.setData(ClipboardData(text: m.username == null ? name : '@${m.username}'));
                                toast(context, 'Copied');
                              },
                            ),
                            // A hangout's: their role, and what this device's role may do about them.
                            if (v.hangoutFor(session.channel) case final room?) HangoutModeration(room: room, id: id, name: name),
                          ],
                          if (me)
                            if (v.hangoutFor(session.channel) case final room?)
                              SettingRow(icon: AppIcon(Lucide.shieldCheck, size: 18), label: 'Your role', value: RoleTag(role: room.roster.roleOf(room.me), owner: room.roster.isOwner(room.me))),
                        ]),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A volume from nothing to twice as loud, dragged or tapped along its track; 100% marked.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({super.key, required this.value, required this.onChanged, required this.label, this.max = 2.0});
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final double max;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: label,
      value: '${(value * 100).round()}%',
      increasedValue: '${((value + 0.1).clamp(0, max) * 100).round()}%',
      decreasedValue: '${((value - 0.1).clamp(0, max) * 100).round()}%',
      onIncrease: () => onChanged((value + 0.1).clamp(0, max)),
      onDecrease: () => onChanged((value - 0.1).clamp(0, max)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        void at(double x) {
          var v = (x / w).clamp(0.0, 1.0) * max;
          // Held at 100% when near it.
          if ((v - 1).abs() < 0.04) v = 1;
          onChanged(v);
        }

        final frac = (value / max).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          child: SizedBox(
            height: 32,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Container(height: 6, decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(3))),
              Container(width: w * frac, height: 6, decoration: BoxDecoration(color: t.color('app-accent'), borderRadius: BorderRadius.circular(3))),
              Positioned(left: w / 2 - 1, child: Container(width: 2, height: 12, color: t.color('app-ink-4'))),
              Positioned(
                left: (w * frac - 11).clamp(0.0, w - 22),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper'), border: Border.all(color: t.color('app-accent'), width: 2), boxShadow: t.shadowOf('0 1px 4px rgba(0,0,0,0.2)')),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}


/// A dock button as a pill: its toggle, and beside it a chevron facing up that opens the devices of [kind]
/// (`audioinput`: the microphones; `audiooutput`: the speakers and headsets) to choose from, the one in use ticked,
/// and a way to Settings › Voice and video.
class DevicePill extends StatefulWidget {
  const DevicePill({super.key, required this.icon, required this.label, required this.on, required this.onPress, required this.kind});
  final LucideIcon icon;
  final String label;
  final bool on;
  final VoidCallback onPress;
  final String kind;

  @override
  State<DevicePill> createState() => _DevicePillState();
}

class _DevicePillState extends State<DevicePill> {
  bool _open = false;
  List<MediaDeviceInfo> _devices = const [];

  Future<void> _load() async {
    final found = await RtcMedia.devices(widget.kind);
    if (mounted) setState(() => _devices = found);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final input = widget.kind == 'audioinput';
    final current = input ? v.settings.input : v.settings.output;
    final ink = widget.on ? t.color('app-paper') : t.color('app-ink');
    final ground = widget.on ? t.color('app-ink') : t.color('glacier-bg');
    Widget row(String id, String name) => GlacierMenuItem(
          icon: AppIcon(input ? Lucide.mic : LucideMore.headphones, size: 16),
          shortcut: id == current ? AppIcon(Lucide.check, size: 16, color: t.color('app-ink')) : const SizedBox(width: 16),
          onSelect: () => input ? v.useInput(id) : v.useOutput(id),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final ring = t.len('app-ring');
    return Container(
      height: ring,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(ring / 2),
        border: widget.on ? null : Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GlacierPressable(
          onPressed: widget.onPress,
          semanticLabel: widget.label,
          builder: (context, state) => Container(
            width: ring - 6,
            height: ring,
            padding: const EdgeInsets.only(left: 6),
            alignment: Alignment.center,
            child: AppIcon(widget.icon, size: t.lenOf('1.15rem'), wash: false, color: ink),
          ),
        ),
        GlacierMenu(
          open: _open,
          onOpenChange: (open) {
            setState(() => _open = open);
            if (open) _load();
          },
          placement: Placement.top,
          ariaLabel: input ? 'Microphone' : 'Speaker',
          style: GlacierMenuStyle(minWidth: t.lenOf('15rem'), maxWidth: t.lenOf('20rem')),
          trigger: (context, trigger) => GlacierPressable(
            onPressed: trigger.toggle,
            semanticLabel: input ? 'Choose a microphone' : 'Choose a speaker',
            builder: (context, state) => Container(
              width: 24,
              height: ring,
              padding: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              child: AppIcon(Lucide.chevronUp, size: 14, strokeWidth: 2.4, wash: false, color: ink.withValues(alpha: 0.75)),
            ),
          ),
          children: [
            GlacierMenuLabel(child: Text(input ? 'Microphone' : 'Speaker or headset')),
            row('', input ? 'The system\'s own' : 'The system\'s own'),
            for (final d in _devices) row(d.deviceId, d.label.isEmpty ? 'A device' : d.label),
            const GlacierMenuSeparator(),
            GlacierMenuItem(
              icon: const AppIcon(Lucide.settings, size: 16),
              onSelect: () {
                final shell = AppShell.maybeOf(context);
                if (shell != null) shell.settings('voice');
              },
              child: const Text('Voice settings…'),
            ),
          ],
        ),
      ]),
    );
  }
}
