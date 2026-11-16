import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../../voice/channels.dart';
import '../../voice/hangout.dart';
import '../../voice/roles.dart';
import '../../voice/voice.dart';
import '../common.dart';
import '../hangout_screen.dart';
import '../ripple_avatar.dart';
import '../settings.dart';
import '../shell.dart';
import '../space_invite.dart';
import '../voice_screen.dart';
import 'discord.dart';
import 'facetime.dart';
import 'meet.dart';
import 'stage.dart';
import 'telegram.dart';
import 'zoom.dart';

/// Six other ways a space's call can look, behind a switch in Settings › Developer (Matt, 2026-11-16: "give me 6
/// alternate designs for the calling chat and video screens for spaces ... release all 6 versions under a developer
/// setting flag so I can toggle them on and off. Use iconography and good labeling and base the designs off popular
/// voice and video chat apps that exist today").
///
/// With one chosen, a space's call opens as a page of its own over the whole window (as Zoom's, FaceTime's and Meet's
/// calls do), drawn by that design from a [SpaceCall]: who is in it and how loud each is, their video, the chat, and
/// the call's buttons. Minimise puts it away to the call banner; pressing the banner brings it back. Standard is the
/// app's own layout (lib/ui/hangout_screen.dart), as before.
enum SpaceDesign {
  standard('Standard', 'Ghost Messaging', 'The app\'s own: people beside the list, the chat in the pane.', LucideMore.headphones),
  discord('Voice channel', 'Discord', 'Dark tiles that light green round whoever talks, the chat beside them, a control bar at the foot.', Lucide.users),
  zoom('Meeting', 'Zoom', 'Speaker and gallery views, a labelled toolbar along the foot, People and Chat as side panels.', Lucide.video),
  facetime('Full screen', 'FaceTime', 'Whoever talks fills the screen, you float in a corner, glass controls on top.', Lucide.smartphone),
  meet('Rounded tiles', 'Google Meet', 'Soft tiles with a pill toolbar, the people and the chat in a side panel.', Lucide.layoutGrid),
  stage('Audio stage', 'Clubhouse and X Spaces', 'Voice first: big rippling faces on a stage, the chat as comments below.', LucideMore.audioLines),
  telegram('Voice chat', 'Telegram', 'A list of people in the app\'s own colours, ripples round whoever talks, one big microphone button and the chat at a third of the window.', Lucide.mic);

  const SpaceDesign(this.label, this.after, this.description, this.icon);

  /// Its name, the app it is modelled on, and a line on what it looks like.
  final String label;
  final String after;
  final String description;
  final LucideIcon icon;

  static const pref = 'dev_space_design';

  /// The design a call opens in: Telegram's, made the app's default (Matt, 2026-11-16: "Change the telegram one to be
  /// our colors without the gradients and our voice effects ... then deploy this as the default version"), until
  /// another is chosen in Settings › Developer ("standard" is the app's earlier layout).
  static const fallback = SpaceDesign.telegram;

  static SpaceDesign of(AppState app) => named(app.choice(pref, '')) ?? fallback;

  static SpaceDesign? named(String name) {
    for (final d in values) {
      if (d.name == name) return d;
    }
    return null;
  }

  /// The design's own page for [call].
  Widget page(SpaceCall call) => switch (this) {
        SpaceDesign.standard => const SizedBox.shrink(),
        SpaceDesign.discord => DiscordCall(call: call),
        SpaceDesign.zoom => ZoomCall(call: call),
        SpaceDesign.facetime => FaceTimeCall(call: call),
        SpaceDesign.meet => MeetCall(call: call),
        SpaceDesign.stage => StageCall(call: call),
        SpaceDesign.telegram => TelegramCall(call: call),
      };
}

/// Someone in the call as a design draws them.
@immutable
class SpacePerson {
  const SpacePerson({
    required this.id,
    required this.name,
    this.me = false,
    this.muted = false,
    this.guest = false,
    this.video = false,
    this.stream,
    this.role,
    this.owner = false,
    this.username,
    this.tag,
  });

  /// `me` for this device, else their id on the hub (the key [SpaceCall.levels] uses).
  final String id;
  final String name;
  final bool me;
  final bool muted;
  final bool guest;

  /// Video turned on; [stream] is its picture once it arrives (null until then, and always in a test).
  final bool video;
  final MediaStream? stream;

  /// Their role in the space, where it has roles (null for a group's channel).
  final Role? role;
  final bool owner;
  final String? username;

  /// Where they are from when not from Ghost Messaging: 'Discord' for someone in the Discord voice channel a space is
  /// bridged to. Shown beside their name; they can't be acted on from here.
  final String? tag;

  /// What to call them on a tile: "You" for this device.
  String get shown => me ? 'You' : name;

  /// The role's name to show beside them, where it is worth showing (not the one everyone starts with).
  String? roleLabel(Roster? roster) {
    if (owner) return 'Owner';
    if (role == null || roster == null || role!.id == roster.newcomer) return null;
    return role!.name;
  }
}

/// Everything a design needs to draw a space's call, and do what its buttons say. Made from the call there is
/// ([SpaceCall.live]); a test makes one of its own ([SpaceCall.new]) with no WebRTC underneath.
class SpaceCall {
  SpaceCall({
    required this.channel,
    required this.people,
    required this.levels,
    required this.changes,
    this.room,
    this.muted = false,
    this.deafened = false,
    this.video = false,
    this.micLocked = false,
    this.videoLocked = false,
    this.since,
    this.onMute,
    this.onDeafen,
    this.onVideo,
    this.onLeave,
    this.onMinimize,
    this.onPerson,
    this.onSettings,
    this.onInvite,
    this.onDevices,
    this.chatBuilder,
    this.bridged = false,
  });

  /// Whether this device may invite people into [channel]'s call: never a group's (its members' alone, and it has no
  /// [room]), and in a space with roles only where this device's role may invite.
  static bool mayInvite(VoiceChannel channel, HangoutRoom? room) => channel.group == null && (room == null || room.can(Perm.invite));

  /// The call [Voice] is in, as it stands now; null when there is none. [minimize] puts the page away.
  static SpaceCall? live({VoidCallback? minimize}) {
    final v = Voice.instance;
    final s = v.session;
    if (s == null) return null;
    final media = v.media;
    final room = v.hangoutFor(s.channel);
    final roster = room?.roster;
    final meId = room?.me ?? v.me ?? 'me';
    Role? roleOf(String id) => roster?.roleOf(id);
    final people = <SpacePerson>[
      SpacePerson(
        id: 'me',
        name: s.name.isEmpty ? 'You' : s.name,
        me: true,
        muted: s.muted || s.deafened,
        video: s.video,
        stream: media?.localVideo.value,
        role: roleOf(meId),
        owner: roster?.isOwner(meId) ?? false,
      ),
      for (final m in s.members.values)
        // The bridge to Discord is a member, but not a person: the people it brings are below.
        if (m.id != s.bridgeId)
        SpacePerson(
          id: m.id,
          name: v.nameOf(m.id),
          muted: m.muted || (room != null && !room.heard(m.id)),
          guest: m.guest,
          video: m.video,
          stream: m.video ? media?.remote.value[m.id] : null,
          role: roleOf(m.id),
          owner: roster?.isOwner(m.id) ?? false,
          username: m.username,
        ),
      // Everyone in the Discord voice channel the space is bridged to (VoiceSession.discordPeople).
      for (final d in s.discordPeople)
        if (!d.bot) SpacePerson(id: 'dc:${d.id}', name: d.name, muted: d.muted || d.deafened, tag: 'Discord'),
    ];
    return SpaceCall(
      channel: s.channel,
      people: people,
      levels: s.discordPeople.isEmpty ? (media?.levels ?? s.media.levels) : MergedLevels(media?.levels ?? s.media.levels, s.discordLevels),
      changes: Listenable.merge([v, s, ?room, ?media?.remote, ?media?.localVideo]),
      bridged: s.channel.discord != null,
      room: room,
      muted: s.muted,
      deafened: s.deafened,
      video: s.video,
      micLocked: s.locked,
      videoLocked: s.videoLocked,
      since: s.since,
      onMute: () => s.setMuted(!s.muted),
      onDeafen: () => s.setDeafened(!s.deafened),
      onVideo: () => unawaited(s.setVideo(!s.video)),
      onLeave: () => unawaited(v.leave()),
      onMinimize: minimize,
      // Someone in Discord can't be muted or given a role from here: their press does nothing yet.
      onPerson: (context, p) {
        if (p.tag == null) showPerson(context, s, p.id, p.name);
      },
      onSettings: room == null ? null : (context) => push(context, (_) => RolesScreen(room: room, settings: true)),
      onInvite: mayInvite(s.channel, room) ? (context) => showSpaceInvite(context, s.channel) : null,
      onDevices: (context) => push(context, (_) => const SettingsSectionScreen('voice')),
      chatBuilder: room == null ? null : ({double bottom = 0}) => HangoutChat(room: room, bottom: bottom),
    );
  }

  final VoiceChannel channel;

  /// This device first, then everyone else in the call.
  final List<SpacePerson> people;

  /// How loud each is now, 0 to 1, by [SpacePerson.id] (`me` for this device): the ripples, the green rings, the
  /// waves. Changes several times a second; listen to it where the picture should move.
  final ValueListenable<Map<String, double>> levels;

  /// Anything else in the call changing (who is in it, mute, video, the chat): build the page again from
  /// [SpaceCall.live] when it fires (SpaceCallPage does).
  final Listenable changes;

  /// The space's chat and roles; null for a group's channel.
  final HangoutRoom? room;

  final bool muted, deafened, video;

  /// This device may not unmute (muted for everyone, or its role may not speak), or turn video on.
  final bool micLocked, videoLocked;

  /// When this device came into the call.
  final DateTime? since;

  final VoidCallback? onMute, onDeafen, onVideo, onLeave, onMinimize;
  final void Function(BuildContext context, SpacePerson person)? onPerson;
  final void Function(BuildContext context)? onSettings, onInvite, onDevices;
  final Widget Function({double bottom})? chatBuilder;

  /// The space is bridged to a Discord voice channel: its sound and chat go through the bridge, so it is not
  /// end-to-end encrypted. A design says so.
  final bool bridged;

  /// The level at which someone counts as talking (RippleAvatar.talking).
  static const talking = RippleAvatar.talking;

  SpacePerson get me => people.first;
  List<SpacePerson> get others => people.skip(1).toList();
  List<SpacePerson> get withVideo => [for (final p in people) if (p.video) p];

  /// Who is loudest now, if anyone is talking (not muted): the "active speaker".
  SpacePerson? loudest(Map<String, double> now) {
    SpacePerson? best;
    var most = talking;
    for (final p in people) {
      final l = now[p.id] ?? 0;
      if (!p.muted && l > most) {
        best = p;
        most = l;
      }
    }
    return best;
  }

  bool isTalking(SpacePerson p, Map<String, double> now) => !p.muted && (now[p.id] ?? 0) > talking;

  /// The chat, with [bottom] left clear under its composer; a line saying there is none for a group's channel.
  Widget chat({double bottom = 0}) => chatBuilder?.call(bottom: bottom) ?? const _NoChat();

  /// How long this device has been in the call, as a clock: 4:05, 1:02:09.
  String clock(DateTime now) {
    final d = now.difference(since ?? now);
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _NoChat extends StatelessWidget {
  const _NoChat();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(child: Text('A group\'s chat is its conversation', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))));
  }
}

/// A face that ripples while they talk, from [SpaceCall.levels]: the app's RippleAvatar, kept moving on its own.
class SpaceFace extends StatelessWidget {
  const SpaceFace({super.key, required this.call, required this.person, this.size = 44, this.ringed = false});
  final SpaceCall call;
  final SpacePerson person;
  final double size;
  final bool ringed;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) => RippleAvatar(name: person.me ? (person.name.isEmpty ? 'You' : person.name) : person.name, level: person.muted ? 0 : (now[person.id] ?? 0), muted: person.muted, size: size, ringed: ringed),
      );
}

/// Someone's picture where their video is on and has arrived; else [fallback] (or their face on a dark ground), so a
/// tile is never empty.
class SpaceVideo extends StatelessWidget {
  const SpaceVideo({super.key, required this.call, required this.person, this.fallback, this.faceSize = 64});
  final SpaceCall call;
  final SpacePerson person;
  final Widget? fallback;
  final double faceSize;

  @override
  Widget build(BuildContext context) {
    final stream = person.stream;
    if (stream != null) return StreamView(stream: stream, mirror: person.me);
    return fallback ?? ColoredBox(color: const Color(0xFF1C1C1F), child: Center(child: SpaceFace(call: call, person: person, size: faceSize)));
  }
}

/// A call button as most of these apps draw theirs: a round or rounded icon, its words under it. [on] fills it (a
/// toggle that is on); [danger] makes it red (leave).
class SpaceButton extends StatelessWidget {
  const SpaceButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.on = false,
    this.danger = false,
    this.size = 52,
    this.showLabel = true,
    this.dark = false,
    this.square = false,
  });
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;
  final bool danger;
  final double size;
  final bool showLabel;

  /// Drawn for a dark ground whatever the theme (FaceTime's glass, Telegram's sheet).
  final bool dark;

  /// A rounded square, not a circle (Zoom, Meet).
  final bool square;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final red = t.colorOf('#dd3a30');
    final ink = dark ? const Color(0xFFFFFFFF) : t.color('app-ink');
    final paper = dark ? const Color(0xFF000000) : t.color('app-paper');
    final ground = danger ? red : (on ? ink : (dark ? const Color(0x33FFFFFF) : t.color('app-paper-2')));
    final mark = danger ? const Color(0xFFFFFFFF) : (on ? paper : ink);
    final off = onPressed == null;
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedScale(
            scale: state.pressed ? 0.94 : 1,
            duration: const Duration(milliseconds: 100),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: ground,
                shape: square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: square ? BorderRadius.circular(size * 0.28) : null,
              ),
              alignment: Alignment.center,
              child: AppIcon(icon, size: size * 0.4, wash: false, color: mark),
            ),
          ),
          if (showLabel) ...[
            SizedBox(height: t.space(1)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: dark ? const Color(0xFFE6E6E8) : t.color('app-ink-2'))),
          ],
        ]),
      ),
    );
  }
}

/// The words a design's buttons say, the same in all six: so "Mute" is "Mute" everywhere.
abstract final class SpaceWords {
  static String mute(SpaceCall c) => c.muted ? 'Unmute' : 'Mute';
  static String video(SpaceCall c) => c.video ? 'Stop video' : 'Video';
  static String deafen(SpaceCall c) => c.deafened ? 'Undeafen' : 'Deafen';
  static const leave = 'Leave', chat = 'Chat', people = 'People', invite = 'Invite', settings = 'Settings', minimize = 'Minimise', devices = 'Devices';
  static LucideIcon muteIcon(SpaceCall c) => c.muted ? LucideMore.micOff : Lucide.mic;
  static LucideIcon videoIcon(SpaceCall c) => c.video ? Lucide.video : LucideMore.videoOff;
  static LucideIcon deafenIcon(SpaceCall c) => c.deafened ? LucideMore.headphoneOff : LucideMore.headphones;
}

/// A space's call as the chosen [design] draws it, over the whole window: built again from the call as it changes,
/// and closed when the call ends.
class SpaceCallPage extends StatefulWidget {
  const SpaceCallPage({super.key, required this.design, this.inline = false});
  final SpaceDesign design;

  /// Drawn as the call page itself (a narrow phone's), not pushed over everything: when the call ends the page under
  /// it shows what is there then, and nothing is popped.
  final bool inline;

  @override
  State<SpaceCallPage> createState() => _SpaceCallPageState();
}

class _SpaceCallPageState extends State<SpaceCallPage> {
  VoiceChannel? _held;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final s = Voice.instance.session;
    if (s != null && s.channel.hangout) {
      _held = s.channel;
      unawaited(Voice.instance.hold(s.channel));
    }
    // The clock in a call's header, a second at a time.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    Voice.instance.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (Voice.instance.session == null) {
      if (!widget.inline) Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    Voice.instance.removeListener(_changed);
    final held = _held;
    if (held != null) unawaited(Voice.instance.release(held));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = SpaceCall.live(minimize: () => Navigator.of(context).maybePop());
    if (call == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: call.changes,
      builder: (context, _) {
        final now = SpaceCall.live(minimize: () => Navigator.of(context).maybePop()) ?? call;
        return KeyedSubtree(key: ValueKey('space-design-${widget.design.name}'), child: widget.design.page(now));
      },
    );
  }
}

/// Opens the space call's page as [design] draws it, over everything. False where the standard layout is to be used
/// (Standard chosen, or not in a space's call).
bool openSpaceCall(BuildContext context, {SpaceDesign? design}) {
  final d = design ?? SpaceDesign.of(AppState.of(context));
  final s = Voice.instance.session;
  if (d == SpaceDesign.standard || s == null || !s.channel.hangout) return false;
  // On a narrow phone the call page itself is the design (inlineSpaceCall), so there is nothing to push over it.
  if (AppShell.maybeOf(context) != null && !AppShell.wideOf(context)) return false;
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'space-call'),
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => SpaceCallPage(design: d),
    transitionsBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
    ),
  ));
  return true;
}

/// Whether a design other than Standard is chosen: the app's own layout then stays out of the way (lib/ui/shell.dart).
bool spaceDesignChosen(BuildContext context) => SpaceDesign.of(AppState.of(context)) != SpaceDesign.standard;

/// What a design not yet drawn shows: its name and the people, so the switch can be tried before it is done.
class SpaceDesignStub extends StatelessWidget {
  const SpaceDesignStub({super.key, required this.call, required this.name});
  final SpaceCall call;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: SafeArea(
        child: Column(children: [
          Text(name, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink'))),
          for (final p in call.people) Row(children: [SpaceFace(call: call, person: p, size: 40), Text(p.shown)]),
          SpaceButton(icon: SpaceWords.muteIcon(call), label: SpaceWords.mute(call), onPressed: call.onMute),
          SpaceButton(icon: Lucide.phone, label: SpaceWords.leave, onPressed: call.onLeave, danger: true),
        ]),
      ),
    );
  }
}

/// The chosen design drawn as the call page itself, where the call is a space's and the window is narrow (a phone, a
/// folded Fold): wherever the call page is reached from — joining, the call banner, the Spaces tab — it is the design
/// (Matt, 2026-11-16: "I don't see the new telegram like UI as the default in ghost calls ... i only see it when I open
/// the phone to fullscreen not when it's closed and skinny"). Null where the app's own layout is to be drawn.
Widget? inlineSpaceCall(BuildContext context, VoiceSession? s) {
  if (s == null || !s.channel.hangout || AppShell.wideOf(context)) return null;
  final d = SpaceDesign.of(AppState.of(context));
  if (d == SpaceDesign.standard) return null;
  return SpaceCallPage(key: ValueKey('inline-${d.name}-${s.channel.room}'), design: d, inline: true);
}

/// Two sets of levels read as one: the call's own and the Discord people's (keys don't overlap).
class MergedLevels implements ValueListenable<Map<String, double>> {
  MergedLevels(this.a, this.b);
  final ValueListenable<Map<String, double>> a, b;

  @override
  Map<String, double> get value => {...a.value, ...b.value};

  @override
  void addListener(VoidCallback listener) {
    a.addListener(listener);
    b.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    a.removeListener(listener);
    b.removeListener(listener);
  }
}
