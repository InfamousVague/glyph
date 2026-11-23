export 'call_plugins.dart' show SpaceExtra;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../../sms.dart';
import '../../voice/call_sound.dart';
import '../../voice/channels.dart';
import '../../voice/hangout.dart';
import '../../voice/open_space.dart';
import '../../voice/recorder.dart';
import '../../voice/roles.dart';
import '../../voice/voice.dart';
import '../common.dart';
import '../hangout_screen.dart';
import '../recording_ui.dart';
import '../ripple_avatar.dart';
import '../settings.dart';
import '../shell.dart';
import '../screen_share.dart';
import '../space_invite.dart';
import '../voice_screen.dart';
import 'call_plugins.dart';
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
    this.mutedForAll = false,
    this.mutedForMe = false,
    this.guest = false,
    this.video = false,
    this.screen = false,
    this.stream,
    this.back = false,
    this.role,
    this.owner = false,
    this.username,
    this.tag,
  });

  /// `me` for this device, else their id on the hub (the key [SpaceCall.levels] uses).
  final String id;
  final String name;
  final bool me;

  /// Not heard here, for any reason: they muted themselves, or one of the two below.
  final bool muted;

  /// Why, where it isn't their own doing (GMFB-49, Kevin: "muting should be split in communities"): a moderator muted
  /// them for everyone (they can't unmute themselves), or this device alone stopped hearing them (Mute for me). Each
  /// has its own mark on their tile ([SpaceWords.mutedIcon]).
  final bool mutedForAll, mutedForMe;
  final bool guest;

  /// Video turned on; [stream] is its picture once it arrives (null until then, and always in a test).
  final bool video;
  final MediaStream? stream;

  /// What [stream] shows is their shared screen (GMFB-27): drawn whole, never cropped or mirrored.
  final bool screen;

  /// This device's camera is the one on its back (GMFB-57): its own picture is not mirrored then, as a front
  /// camera's is.
  final bool back;

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
    this.micLockedWhy,
    this.micLockedByRole = false,
    this.videoLocked = false,
    this.screen = false,
    this.onScreen,
    this.onFlip,
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
    this.extras = const [],
  });

  /// A stage's items in the call's menu (GMFB-29, from the Uplink gap review: "A stage/stream mode: some people speak,
  /// many listen, with a listener count"): Raise hand for a listener, and, for whoever manages the space, making it a
  /// stage or ending one, with how many are listening.
  static List<SpaceExtra> stageExtras(VoiceSession s, HangoutRoom? room) {
    if (room == null || !s.channel.hasVoice) return const [];
    final listening = [if (room.listens(room.me)) room.me, for (final id in s.members.keys) if (room.listens(id)) id].length;
    final hands = s.members.values.where((m) => m.hand).length;
    return [
      if (room.stage && s.locked)
        SpaceExtra(label: s.hand ? 'Lower your hand' : 'Raise your hand', icon: LucideMore.hand, builtIn: true, run: (_) => s.raiseHand(!s.hand)),
      if (room.canManage)
        SpaceExtra(
          label: room.stage ? 'End the stage · $listening listening${hands > 0 ? ' · $hands ✋' : ''}' : 'Make it a stage',
          icon: Lucide.megaphone,
          builtIn: true,
          run: (context) async {
            final ok = await room.setStage(!room.stage);
            if (context.mounted) {
              toast(context, !ok ? 'The stage couldn\'t be changed' : (room.stage ? 'It\'s a stage: newcomers listen until you bring them up to speak' : 'Everyone can speak again'));
            }
          },
        ),
    ];
  }

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
        mutedForAll: room?.mutedForAll(meId) ?? false,
        video: s.video || s.screen,
        screen: media?.localScreen.value != null,
        stream: media?.localScreen.value ?? media?.localVideo.value,
        back: s.backCamera,
        role: roleOf(meId),
        owner: roster?.isOwner(meId) ?? false,
      ),
      for (final m in s.members.values)
        // The bridge to Discord is a member, but not a person: the people it brings are below.
        if (m.id != s.bridgeId)
        SpacePerson(
          id: m.id,
          // A hand raised to speak on a stage, before the name, so every design shows it (GMFB-29).
          name: m.hand ? '✋ ${v.nameOf(m.id)}' : v.nameOf(m.id),
          muted: m.muted || (room != null && !room.heard(m.id)) || v.silenced(m.id),
          mutedForAll: room?.mutedForAll(m.id) ?? false,
          mutedForMe: v.silenced(m.id),
          guest: m.guest,
          video: m.video,
          screen: m.screen,
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
      changes: Listenable.merge([v, s, ?room, ?media?.remote, ?media?.localVideo, ?media?.localScreen, CallRecorder.instance]),
      bridged: s.channel.discord != null,
      room: room,
      muted: s.muted,
      deafened: s.deafened,
      video: s.video,
      micLocked: s.locked,
      micLockedWhy: s.locked ? room?.micLockedWhy : null,
      micLockedByRole: s.locked && room != null && !room.mutedForAll(meId),
      videoLocked: s.videoLocked,
      screen: s.screen,
      onScreen: s.canShareScreen ? (context) => unawaited(toggleScreenShare(context, s)) : null,
      onFlip: s.canFlipCamera ? () => unawaited(s.flipCamera()) : null,
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
      // Sharing the screen, first in every design's menu (GMFB-27), where this device can.
      extras: [
        if (s.canShareScreen) SpaceExtra(label: screenShareLabel(s), icon: LucideMore.screenShare, builtIn: true, run: (context) => unawaited(toggleScreenShare(context, s))),
        ...stageExtras(s, room),
        ...CallPlugins.extras(),
        // In a browser, what its call leaves out, said where the call's choices are.
        if (Sms.browser)
          SpaceExtra(
            label: 'In a browser',
            icon: Lucide.info,
            builtIn: true,
            run: (context) => showChoices(context, title: 'In a browser', header: const Text(callsInBrowser), choices: [
              Choice('Voice and video settings', LucideMore.headphones, () => push(context, (_) => const SettingsSectionScreen('voice'))),
            ]),
          ),
      ],
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

  /// This device is sharing its screen (GMFB-27); [onScreen] starts or stops it, null where this device can't.
  final bool screen;
  final void Function(BuildContext context)? onScreen;

  /// Changes between the front and the back camera (GMFB-57, Kevin: "Add a button to flip camera on mobile
  /// versions"). Null where there is nothing to flip, and a design then draws no button: a computer, video off, or
  /// the screen shared in the camera's place.
  final VoidCallback? onFlip;

  /// This device may not unmute (muted for everyone, or its role may not speak), or turn video on.
  final bool micLocked, videoLocked;

  /// Why the microphone is locked, in a sentence for the mute button to say when pressed (GMFB-49); and whether it is
  /// this device's role that may not speak (a stage's listener), not a moderator's mute.
  final String? micLockedWhy;
  final bool micLockedByRole;

  /// When this device came into the call.
  final DateTime? since;

  final VoidCallback? onMute, onDeafen, onVideo, onLeave, onMinimize;
  final void Function(BuildContext context, SpacePerson person)? onPerson;
  final void Function(BuildContext context)? onSettings, onInvite, onDevices;
  final Widget Function({double bottom})? chatBuilder;

  /// The space is bridged to a Discord voice channel: its sound and chat go through the bridge, so it is not
  /// end-to-end encrypted. A design says so.
  final bool bridged;

  /// What the plugins that are on in this call offer in its menu (Slots.callControls): Record, for one.
  final List<SpaceExtra> extras;

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

  /// Whether [p] counts as talking at the levels [now]: not muted and louder than [talking].
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

/// What stands where the chat would in a group's channel, which has no chat of its own.
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
        // With how this device's connection to them stands, where it isn't simply through (GMFB-4).
        builder: (context, now, _) => LinkBadge(
          id: person.id,
          size: size,
          child: RippleAvatar(name: person.me ? (person.name.isEmpty ? 'You' : person.name) : person.name, level: person.muted ? 0 : (now[person.id] ?? 0), muted: person.muted, size: size, ringed: ringed),
        ),
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
    // One renderer per stream (GMFB-5; voice_screen.dart's _Tile says why).
    if (stream != null) {
      final view = StreamView(key: ObjectKey(stream), stream: stream, mirror: person.me && !person.screen && !person.back, contain: person.screen);
      return person.screen ? ColoredBox(color: const Color(0xFF000000), child: view) : view;
    }
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
  static const leave = 'Leave', chat = 'Chat', people = 'People', invite = 'Invite', settings = 'Settings', minimize = 'Minimise', devices = 'Devices', flip = 'Flip camera';
  static LucideIcon muteIcon(SpaceCall c) => c.muted ? LucideMore.micOff : Lucide.mic;

  /// The mark on someone who isn't heard, and its words (GMFB-49), so anyone can tell which mute it is: a lock where a
  /// moderator muted them for everyone, a crossed speaker where only this device stopped hearing them, the crossed
  /// microphone where they muted themselves.
  static LucideIcon mutedIcon(SpacePerson p) => p.mutedForAll ? Lucide.lock : (p.mutedForMe ? LucideMore.volumeX : LucideMore.micOff);
  static String mutedWords(SpacePerson p) => p.mutedForAll ? 'muted for everyone' : (p.mutedForMe ? 'muted for you' : 'muted');
  static LucideIcon videoIcon(SpaceCall c) => c.video ? Lucide.video : LucideMore.videoOff;
  static const LucideIcon flipIcon = Lucide.refreshCw;
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

  /// Whose shared screen was put away with Back to call (GMFB-27): theirs stays a line over the call, with View,
  /// until they share again or someone else does.
  String? _putAway;
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
      if (!widget.inline) _close();
      return;
    }
    setState(() {});
  }

  /// Closes the page this call is drawn on, once: only while its own route is the one on top. Voice tells its
  /// listeners again and again as a call ends (the room let go, the relay saying who is left), and those came while
  /// this page was still sliding away; a Navigator's maybePop then reached the page under it, the shell, whose own
  /// back put away the circle's space and then the circle itself (Matt, 2026-11-17: "leaving a space call takes us
  /// out of the circle completely it should take us back to the circle not the whole main screen").
  void _close() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).maybePop();
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
    final call = SpaceCall.live(minimize: _close);
    if (call == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: call.changes,
      builder: (context, _) {
        final now = SpaceCall.live(minimize: _close) ?? call;
        final page = KeyedSubtree(key: ValueKey('space-design-${widget.design.name}'), child: widget.design.page(now));
        // What the plugins put over the call, whatever its design (Slots.callBanner): a line everyone must see.
        final session = Voice.instance.session;
        // Someone else's shared screen, large over the call until put away (GMFB-27).
        final sharer = session == null ? null : sharerIn(session);
        if (sharer == null && _putAway != null) _putAway = null;
        final staged = sharer != null && sharer.id != _putAway;
        // A recording is told to everyone, whatever plugins are on (lib/ui/recording_ui.dart).
        final banners = [
          if (session != null && RecordingBanner.shows(session)) const RecordingBanner(),
          if (session != null && ScreenShareBanner.shows(session, viewing: staged)) ScreenShareBanner(session: session, onView: () => setState(() => _putAway = null)),
          ...CallPlugins.banners(context),
        ];
        final stage = staged ? Positioned.fill(child: ScreenStage(name: sharer.name, stream: sharer.stream, onBack: () => setState(() => _putAway = sharer.id))) : null;
        if (banners.isEmpty && stage == null) return page;
        return Stack(children: [page, ?stage, if (banners.isNotEmpty) CallBanners(top: MediaQuery.paddingOf(context).top + 62, children: banners)]);
      },
    );
  }
}

/// Opens the space call's page as [design] draws it, over everything. False where the standard layout is to be used
/// (Standard chosen, not in a space's call, or in an open space's, whose floor is its page: OpenSpaces.isCall).
bool openSpaceCall(BuildContext context, {SpaceDesign? design}) {
  final d = design ?? SpaceDesign.of(AppState.of(context));
  final s = Voice.instance.session;
  if (d == SpaceDesign.standard || s == null || !s.channel.hangout || OpenSpaces.isCall(s)) return false;
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

/// Whether the call there is is drawn by a design other than Standard: the app's own layout then stays out of the way
/// (lib/ui/shell.dart). Never an open space's, which is drawn as its floor whatever design is chosen.
bool spaceDesignChosen(BuildContext context) => SpaceDesign.of(AppState.of(context)) != SpaceDesign.standard && !OpenSpaces.isCall(Voice.instance.session);

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
/// the phone to fullscreen not when it's closed and skinny"). Null where the app's own layout is to be drawn, an open
/// space's floor among them.
Widget? inlineSpaceCall(BuildContext context, VoiceSession? s) {
  if (s == null || !s.channel.hangout || OpenSpaces.isCall(s) || AppShell.wideOf(context)) return null;
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


/// The lines over a call (the recording's, the plugins'), where they can be moved and folded (GMFB-16, @kevin, Android
/// 0.11.5: "Audio recording banner covers ui elements in a way that makes them unusable and cannot be moved"): they
/// stood over the call's header, its menu and the first people with no way out of the way. Drag them up or down the
/// screen; the grip folds them to a small red chip at the side, which unfolds them again. Where they were left is
/// kept while the app runs.
class CallBanners extends StatefulWidget {
  const CallBanners({super.key, required this.top, required this.children});

  /// Where they start, from the top of the screen.
  final double top;
  final List<Widget> children;

  /// Where they were moved to, and whether they are folded: for every call page while the app runs.
  @visibleForTesting
  static double? moved;
  @visibleForTesting
  static bool folded = false;

  @override
  State<CallBanners> createState() => _CallBannersState();
}

class _CallBannersState extends State<CallBanners> {
  /// Whether any of the lines draws anything. A plugin's line is listed while the plugin is on (the soundboard's, the
  /// voice changer's) and is empty until it has something to say, as the recording's is once it has stopped: with
  /// nothing drawn, neither the grip nor the folded chip shows (Matt, 2026-11-22: "the recording pill gets stuck on
  /// the screen even when not recording").
  bool _drawn = false;

  /// The lines' height after a layout. [_drawn] follows it a frame later: this is called during layout, where
  /// setState may not be.
  void _measured(double height) {
    final drawn = height > 0.5;
    if (drawn == _drawn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _drawn != drawn) setState(() => _drawn = drawn);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lines = _HeightOf(onHeight: _measured, child: Column(mainAxisSize: MainAxisSize.min, children: widget.children));
    return LayoutBuilder(builder: (context, box) {
      final pad = MediaQuery.paddingOf(context);
      final most = (box.maxHeight - pad.bottom - 72).clamp(pad.top, double.infinity);
      final top = (CallBanners.moved ?? widget.top).clamp(pad.top, most);
      void drag(DragUpdateDetails d) => setState(() => CallBanners.moved = (top + d.delta.dy).clamp(pad.top, most));
      if (!_drawn) return Offstage(child: lines);
      if (CallBanners.folded) {
        return Stack(children: [
          // Still laid out, unseen, so that the chip goes when the lines have nothing more to say. Positioned, as an
          // unpositioned child would size the stack to it (nothing) and leave the chip outside where it can be pressed.
          Positioned(left: 0, right: 0, top: top, child: Offstage(child: lines)),
          Positioned(
            right: t.space(3),
            top: top,
            child: GestureDetector(
              key: const ValueKey('call-banners-folded'),
              onVerticalDragUpdate: drag,
              child: GlacierPressable(
                onPressed: () => setState(() => CallBanners.folded = false),
                semanticLabel: 'Show the lines over this call',
                builder: (context, state) => Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  decoration: BoxDecoration(color: RecordingBanner.red.withValues(alpha: state.pressed ? 0.8 : 1), borderRadius: BorderRadius.circular(999), boxShadow: t.shadowOf('0 4px 14px rgba(0,0,0,0.25)')),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon(Lucide.circleDot, size: 14, strokeWidth: 2.4, color: Color(0xFFFFFFFF)),
                    SizedBox(width: t.space(1)),
                    const AppIcon(Lucide.chevronDown, size: 14, strokeWidth: 2.4, color: Color(0xFFFFFFFF)),
                  ]),
                ),
              ),
            ),
          ),
        ]);
      }
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: GestureDetector(
            key: const ValueKey('call-banners'),
            behavior: HitTestBehavior.deferToChild,
            onVerticalDragUpdate: drag,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              lines,
              // The grip: drag it (or any of the lines) to move them, press it to fold them away.
              GlacierPressable(
                onPressed: () => setState(() => CallBanners.folded = true),
                semanticLabel: 'Fold the lines over this call',
                builder: (context, state) => Container(
                  key: const ValueKey('call-banners-grip'),
                  padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(1)),
                  child: Container(width: 36, height: 5, decoration: BoxDecoration(color: RecordingBanner.red.withValues(alpha: state.pressed ? 1 : 0.7), borderRadius: BorderRadius.circular(3))),
                ),
              ),
            ]),
          ),
        ),
      ]);
    });
  }
}

/// Tells [onHeight] the height its child was laid out to, after each layout.
class _HeightOf extends SingleChildRenderObjectWidget {
  const _HeightOf({required this.onHeight, required super.child});
  final void Function(double height) onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightOf(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightOf renderObject) => renderObject.onHeight = onHeight;
}

/// [_HeightOf]'s render object: lays its child out as it would be, then reports the height.
class _RenderHeightOf extends RenderProxyBox {
  _RenderHeightOf(this.onHeight);
  void Function(double height) onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
