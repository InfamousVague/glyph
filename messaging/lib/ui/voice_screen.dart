import 'package:flutter/services.dart' show TextCapitalization;
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
    return GhostPage(
      title: 'Voice',
      actions: [IconTap(icon: Lucide.plus, label: 'New channel', onPressed: () => push(context, (_) => const NewChannelScreen()))],
      body: ListenableBuilder(
        listenable: v,
        builder: (context, _) {
          final s = v.session;
          return ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              if (s != null) ...[CallPanel(session: s), SizedBox(height: t.space(6))],
              if (v.channels.isEmpty)
                SettingsCallout(child: const Text('Every group of friends has a voice channel. Make one of your own with + and share it with friends you added by username.'))
              else
                PaneSection(
                  title: 'Channels',
                  children: [for (final c in v.channels) _ChannelRow(channel: c)],
                ),
            ],
          );
        },
      ),
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
                Choice('Share with friends', Lucide.share2, () => push(context, (_) => ShareChannelScreen(channel: channel))),
                Choice('Remove channel', Lucide.trash2, () => v.forget(channel), danger: true),
              ]),
            ),
    );
  }
}

/// Everyone in the channel you're in, and the buttons.
class CallPanel extends StatelessWidget {
  const CallPanel({super.key, required this.session});
  final VoiceSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = Voice.instance;
    final media = v.media;
    final red = t.colorOf('#dd3a30');
    Widget button(LucideIcon icon, String label, VoidCallback onPress, {bool on = false, bool danger = false}) => GlacierPressable(
          onPressed: onPress,
          semanticLabel: label,
          builder: (context, state) => Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger ? red : (on ? t.color('app-accent') : t.color(state.pressed ? 'app-paper-3' : 'app-paper')),
              border: danger || on ? null : Border.all(color: t.color('app-rule')),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 20, wash: false, color: danger ? const Color(0xFFFFFFFF) : (on ? t.color('app-on-accent') : t.color('app-ink'))),
          ),
        );
    return ListenableBuilder(
      listenable: Listenable.merge([session, ?media?.remote, ?media?.localVideo]),
      builder: (context, _) {
        final tiles = <Widget>[
          _Tile(name: 'You', muted: session.muted || session.deafened, stream: media?.localVideo.value, mirror: true),
          for (final m in session.members.values) _Tile(name: v.nameOf(m.id), muted: m.muted, stream: m.video ? media?.remote.value[m.id] : null),
        ];
        return ClipRRect(
          borderRadius: BorderRadius.circular(t.radius('xl')),
          child: ColoredBox(
            color: t.color('app-paper-2'),
            child: Padding(
              padding: EdgeInsets.all(t.space(4)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(session.channel.name, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
                Text(session.members.isEmpty ? 'Just you so far' : '${session.members.length + 1} connected', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                SizedBox(height: t.space(3)),
                LayoutBuilder(builder: (context, box) {
                  // Tiles about 240 wide: two across a phone, more across a wide window.
                  final across = (box.maxWidth / 240).floor().clamp(2, 6);
                  final w = (box.maxWidth - t.space(2) * (across - 1)) / across;
                  return Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [for (final tile in tiles) SizedBox(width: w, height: w * 0.75, child: tile)]);
                }),
                SizedBox(height: t.space(4)),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  button(session.muted ? LucideMore.micOff : Lucide.mic, session.muted ? 'Unmute' : 'Mute', () => session.setMuted(!session.muted), on: session.muted),
                  button(session.deafened ? LucideMore.headphoneOff : LucideMore.headphones, session.deafened ? 'Hear again' : 'Deafen', () => session.setDeafened(!session.deafened), on: session.deafened),
                  button(session.video ? Lucide.video : LucideMore.videoOff, session.video ? 'Turn video off' : 'Turn video on', () => session.setVideo(!session.video), on: session.video),
                  button(LucideMore.phoneOff, 'Leave', () => v.leave(), danger: true),
                ]),
              ]),
            ),
          ),
        );
      },
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
    final s = stream;
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radius('lg')),
      child: ColoredBox(
        color: t.color('app-paper-3'),
        child: Stack(fit: StackFit.expand, children: [
          if (s != null)
            StreamView(stream: s, mirror: mirror)
          else
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper')),
                alignment: Alignment.center,
                child: Text(name.isEmpty ? '?' : name.replaceAll('@', '').characters.first.toUpperCase(), style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink'))),
              ),
            ),
          Positioned(
            left: t.space(2),
            bottom: t.space(2),
            right: t.space(2),
            child: Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: s != null ? const Color(0xFFFFFFFF) : t.color('app-ink')))),
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
