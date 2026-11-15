import 'dart:async';

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
import 'common.dart';
import 'ripple_avatar.dart';

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
        if (s != null) {
          return GhostPage(
            title: s.channel.name,
            actions: [
              // A hangout's, not a group's: a group's channel is its members' alone.
              if (s.channel.group == null) IconTap(icon: Lucide.link, label: 'Copy invite link', onPressed: () => copyInvite(context, s.channel)),
            ],
            body: Stack(children: [
              ListView(
                padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), 120 + MediaQuery.paddingOf(context).bottom),
                children: [CallPanel(session: s)],
              ),
              Positioned(left: 0, right: 0, bottom: MediaQuery.paddingOf(context).bottom + t.space(4), child: Center(child: CallDock(session: s))),
            ]),
          );
        }
        return GhostPage(
          title: 'Voice',
          actions: [IconTap(icon: Lucide.plus, label: 'New channel', onPressed: () => push(context, (_) => const NewChannelScreen()))],
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (v.channels.isEmpty)
                SettingsCallout(child: const Text('Every group of friends has a voice channel. Make one of your own with + and share it with friends you added by username.'))
              else
                PaneSection(title: 'Channels', children: [for (final c in v.channels) _ChannelRow(channel: c)]),
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
      onPress: here
          ? null
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
              label: 'Channel options',
              onPressed: () => showChoices(context, title: channel.name, choices: [
                Choice('Copy invite link', Lucide.link, () => copyInvite(context, channel)),
                Choice('Share with friends', Lucide.share2, () => push(context, (_) => ShareChannelScreen(channel: channel))),
                Choice('Remove channel', Lucide.trash2, () => v.forget(channel), danger: true),
              ]),
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
  const CallPanel({super.key, required this.session});
  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final media = v.media;
    final levels = media?.levels ?? session.media.levels;
    return ListenableBuilder(
      listenable: Listenable.merge([session, levels, ?media?.remote, ?media?.localVideo]),
      builder: (context, _) {
        final loud = levels.value;
        final people = <({String id, String name, bool guest, bool muted, MediaStream? video, bool me})>[
          (id: 'me', name: 'You', guest: false, muted: session.muted || session.deafened, video: media?.localVideo.value, me: true),
          for (final m in session.members.values)
            (id: m.id, name: v.nameOf(m.id), guest: m.guest, muted: m.muted, video: m.video ? media?.remote.value[m.id] : null, me: false),
        ];
        final withVideo = [for (final p in people) if (p.video != null) p];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (withVideo.isNotEmpty) ...[
            LayoutBuilder(builder: (context, box) {
              final across = withVideo.length == 1 ? 1 : (box.maxWidth / 240).floor().clamp(2, 4);
              final w = (box.maxWidth - t.space(2) * (across - 1)) / across;
              return Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
                for (final p in withVideo) SizedBox(width: w, height: w * 0.75, child: _Tile(name: p.guest ? '${p.name} (guest)' : p.name, muted: p.muted, stream: p.video, mirror: p.me)),
              ]);
            }),
            SizedBox(height: t.space(3)),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(t.radius('xl')),
            child: ColoredBox(
              color: t.color('app-paper-2'),
              // Room above and below for the first and last face's rings.
              child: Padding(padding: EdgeInsets.symmetric(vertical: t.space(2)), child: Column(children: [
                for (final p in people)
                  Padding(
                    padding: EdgeInsets.fromLTRB(t.space(5), t.space(2), t.space(3), t.space(2)),
                    child: Row(children: [
                      RippleAvatar(name: p.me ? (session.name.isEmpty ? 'You' : session.name) : p.name, level: loud[p.id] ?? 0, muted: p.muted, size: 40),
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
                      if (p.video != null) Padding(padding: EdgeInsets.only(right: t.space(2)), child: AppIcon(Lucide.video, size: 16, color: t.color('app-ink-3'))),
                      if (p.muted) Padding(padding: EdgeInsets.only(right: t.space(3)), child: AppIcon(LucideMore.micOff, size: 16, wash: false, color: t.colorOf('#dd3a30'))),
                    ]),
                  ),
              ])),
            ),
          ),
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
    final red = t.colorOf('#dd3a30');
    Widget button(LucideIcon icon, String label, VoidCallback onPress, {bool on = false, bool danger = false}) => GlacierPressable(
          onPressed: onPress,
          semanticLabel: label,
          builder: (context, state) => Container(
            width: 52,
            height: 52,
            margin: EdgeInsets.symmetric(horizontal: t.space(1)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger ? red : (on ? t.color('app-ink') : t.color(state.pressed ? 'app-paper-3' : 'app-paper-2')),
              border: danger || on ? null : Border.all(color: t.color('app-rule')),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 20, wash: false, color: danger ? const Color(0xFFFFFFFF) : (on ? t.color('app-paper') : t.color('app-ink'))),
          ),
        );
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Container(
        padding: EdgeInsets.all(t.space(2)),
        decoration: BoxDecoration(
          color: t.color('app-paper'),
          borderRadius: BorderRadius.circular(t.radius('full')),
          border: Border.all(color: t.color('app-rule')),
          boxShadow: t.shadowOf('0 8px 24px rgba(0,0,0,0.12)'),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          button(session.muted ? LucideMore.micOff : Lucide.mic, session.muted ? 'Unmute' : 'Mute', () => session.setMuted(!session.muted), on: session.muted),
          button(session.deafened ? LucideMore.headphoneOff : LucideMore.headphones, session.deafened ? 'Hear again' : 'Deafen', () => session.setDeafened(!session.deafened), on: session.deafened),
          button(session.video ? Lucide.video : LucideMore.videoOff, session.video ? 'Turn video off' : 'Turn video on', () => session.setVideo(!session.video), on: session.video),
          button(LucideMore.phoneOff, 'Leave', () => Voice.instance.leave(), danger: true),
        ]),
      ),
    );
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
              if (muted) ...[SizedBox(width: t.space(1)), AppIcon(LucideMore.micOff, size: 14, wash: false, color: t.colorOf('#dd3a30'))],
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
    if (friends.isNotEmpty) await v.share(c, friends);
    if (!mounted) return;
    toast(context, friends.isEmpty ? '${c.name} made' : '${c.name} shared with ${friends.length}');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final friends = Buddies.instance.friends;
    return GhostPage(
      title: 'New channel',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: StatefulBuilder(
          builder: (context, set) => ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              PaneSection(title: 'Name', children: [
                SettingRowBox(child: GlacierInput(controller: _name, placeholder: 'Hangout', ariaLabel: 'Channel name', autoFocus: true, autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
              ]),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'Share with',
                description: Text(friends.isEmpty ? 'Add friends by username (Settings › Me › Friends) to share channels with them.' : 'They can see who\'s in it and hop in any time.'),
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
              PaneSection(children: [SettingRow(icon: AppIcon(LucideMore.headphones, size: 18), label: 'Make channel', onPress: _make)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shares a channel of yours with more friends.
class ShareChannelScreen extends StatelessWidget {
  const ShareChannelScreen({super.key, required this.channel});
  final VoiceChannel channel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final friends = Buddies.instance.friends;
    return GhostPage(
      title: 'Share ${channel.name}',
      body: ListView(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)),
        children: [
          PaneSection(children: [
            if (friends.isEmpty) SettingRow(label: 'No friends added by username yet', disabled: true),
            for (final f in friends)
              SettingRow(
                icon: AppIcon(Lucide.userRound, size: 18),
                label: f.shown,
                value: const Text('Share'),
                onPress: () async {
                  await Voice.instance.share(channel, [f]);
                  if (context.mounted) toast(context, 'Shared with ${f.shown}');
                },
              ),
          ]),
        ],
      ),
    );
  }
}

/// A group calling: shown over everything until joined or put away.
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
                      AppIcon(LucideMore.phoneCall, size: 22, wash: false, color: t.color('app-paper')),
                      SizedBox(width: t.space(3)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(r.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold', color: t.color('app-paper'))),
                          Text('${r.from} is calling the group', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-paper'))),
                        ]),
                      ),
                      IconTap(icon: Lucide.x, label: 'Not now', color: t.color('app-paper'), onPressed: v.dismissRing),
                      SizedBox(width: t.space(1)),
                      GlacierPressable(
                        onPressed: () => v.join(r.channel),
                        semanticLabel: 'Join',
                        builder: (context, state) => Container(
                          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                          decoration: BoxDecoration(color: t.colorOf('#2fb35a'), borderRadius: BorderRadius.circular(t.radius('full'))),
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
    final green = t.colorOf('#2fb35a');
    final here = v.session?.channel.room == channel.room;
    final inIt = here ? ['me', ...v.session!.members.keys] : v.inChannel(channel);
    final live = inIt.isNotEmpty;
    final last = v.lastActive(channel);
    final who = here
        ? (inIt.length == 1 ? 'You\'re in · just you' : 'You\'re in · ${inIt.where((i) => i != 'me').map(v.nameOf).join(', ')}')
        : live
            ? inIt.map(v.nameOf).join(', ')
            : 'Nobody here · hop in any time';
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: '${channel.name}, voice channel, ${live ? '${inIt.length} in it' : 'nobody in it'}',
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
    );
  }
}

/// The voice channels as a strip of small cards over the list (the "strip" layout): live ones first, lit.
class VoiceStrip extends StatelessWidget {
  const VoiceStrip({super.key, required this.channels, required this.onPress});
  final List<VoiceChannel> channels;
  final ValueChanged<VoiceChannel> onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final green = t.colorOf('#2fb35a');
    return SizedBox(
      height: t.lenOf('4.6rem'),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: t.space(2)),
        itemCount: channels.length,
        separatorBuilder: (_, _) => SizedBox(width: t.space(2)),
        itemBuilder: (context, i) {
          final c = channels[i];
          final n = v.session?.channel.room == c.room ? v.session!.members.length + 1 : v.inChannel(c).length;
          return GlacierPressable(
            onPressed: () => onPress(c),
            semanticLabel: '${c.name}, ${n == 0 ? 'nobody in it' : '$n in it'}',
            builder: (context, state) => Container(
              width: t.lenOf('9rem'),
              padding: EdgeInsets.all(t.space(3)),
              decoration: BoxDecoration(
                color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
                borderRadius: BorderRadius.circular(t.lenOf('1rem')),
                border: Border.all(color: n > 0 ? green : t.color('app-rule'), width: n > 0 ? 2 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  AppIcon(LucideMore.headphones, size: 14, wash: false, color: n > 0 ? green : t.color('app-ink-3')),
                  SizedBox(width: t.space(1)),
                  Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink')))),
                ]),
                SizedBox(height: t.space(1)),
                Text(n == 0 ? 'Nobody here' : '$n here', style: pageText(t, t.fontSize('xs'), weight: n > 0 ? 'semibold' : 'regular', color: n > 0 ? green : t.color('app-ink-3'))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// While you're in a call, a banner at the top of the sidebar, above the list's title, that takes its own room and
/// pushes the list down (Matt, 2026-11-15: "rework the active call indicator", then "Make sure the active call runs
/// as a banner that expands space from the top of thr sidebar not a floating banner"): a beating green dot, the
/// channel and how long you've been in it, the faces of whoever is talking (rippling), and the microphone and leave.
/// A press on it opens the call. It folds away when the call ends.
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        final s = v.session;
        if (s == null) return const SizedBox(width: double.infinity);
        final levels = v.media?.levels ?? s.media.levels;
        final green = t.colorOf('#2fb35a');
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
            return GlacierPressable(
              onPressed: widget.onOpen,
              semanticLabel: 'In ${s.channel.name}, $people connected. Open the call.',
              builder: (context, state) => Container(
                // As wide as the search field and the cards under it, in the column's flow.
                margin: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(2), 0),
                padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(2), t.space(2)),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(green.withValues(alpha: state.pressed ? 0.2 : 0.12), t.color('app-paper')),
                  borderRadius: BorderRadius.circular(t.radius('xl')),
                  border: Border.all(color: green.withValues(alpha: 0.45), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.max, children: [
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
                  IconTap(icon: s.muted ? LucideMore.micOff : Lucide.mic, label: s.muted ? 'Unmute' : 'Mute', size: 18, color: s.muted ? t.colorOf('#dd3a30') : null, onPressed: () => s.setMuted(!s.muted)),
                  GlacierPressable(
                    onPressed: () => v.leave(),
                    semanticLabel: 'Leave the call',
                    builder: (context, state) => Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('#dd3a30').withValues(alpha: state.pressed ? 0.8 : 1)),
                      alignment: Alignment.center,
                      child: const AppIcon(LucideMore.phoneOff, size: 16, wash: false, color: Color(0xFFFFFFFF)),
                    ),
                  ),
                ]),
              ),
            );
          },
        );
      },
    ),
    );
  }
}
