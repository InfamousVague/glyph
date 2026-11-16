import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../../voice/roles.dart';
import '../ripple_avatar.dart';
import 'space_design.dart';

/// A space's call as an audio stage, after Clubhouse and X (Twitter) Spaces (SpaceDesign.stage): the room's name with
/// a LIVE pill, the speakers on stage as big faces that ripple purple while they talk, the muted listening below in
/// smaller faces, the chat as "Comments" (a sheet on a phone, a column on a computer), and Clubhouse's foot: "Leave
/// quietly" on the left, round labelled buttons and a big mic on the right.
class StageCall extends StatefulWidget {
  const StageCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<StageCall> createState() => _StageCallState();
}

/// X Spaces' purple, for LIVE, the talking rings and the mic.
const _purple = Color(0xFF7856FF);
const _red = Color(0xFFE0245E);
const _white = Color(0xFFFFFFFF);

/// The stage's colours: Clubhouse's warm cream behind white cards when light, near-black behind grey cards when dark.
class _Look {
  _Look(Tokens t) : dark = t.color('app-paper').computeLuminance() < 0.4 {
    ground = dark ? const Color(0xFF0E0E10) : const Color(0xFFF2F0E4);
    card = dark ? const Color(0xFF1B1B1F) : _white;
    raised = dark ? const Color(0xFF2A2A30) : const Color(0xFFF0EEE6);
    rule = dark ? const Color(0xFF2E2E34) : const Color(0xFFE6E2D3);
    ink = t.color('app-ink');
    ink2 = t.color('app-ink-2');
    ink3 = t.color('app-ink-3');
    tint = dark ? const Color(0xFF2A2340) : const Color(0xFFEEEAFF);
    tintInk = dark ? const Color(0xFFB9A8FF) : const Color(0xFF5B3FE0);
  }
  final bool dark;
  late final Color ground, card, raised, rule, ink, ink2, ink3, tint, tintInk;
}

class _StageCallState extends State<StageCall> {
  /// The comments: a sheet over the stage on a phone (shut until asked for), a column on a computer (open until shut).
  bool? _comments;

  static const _wide = 880.0;

  SpaceCall get call => widget.call;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = _Look(t);
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: look.ground,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= _wide;
        final comments = _comments ?? wide;
        void toggle() => setState(() => _comments = !comments);
        final bar = _Bar(call: call, look: look, camera: wide, comments: comments, onComments: toggle, bottom: wide ? t.space(3) : pad.bottom + t.space(2));
        final header = _Header(call: call, look: look, camera: !wide, top: wide ? t.space(3) : pad.top + t.space(1));
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                header,
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Padding(padding: EdgeInsets.symmetric(horizontal: t.space(4)), child: _StageCard(call: call, look: look, wide: true)),
                    ),
                  ),
                ),
                bar,
              ]),
            ),
            if (comments)
              Container(
                width: 380,
                decoration: BoxDecoration(color: look.card, border: Border(left: BorderSide(color: look.rule))),
                child: _Comments(call: call, look: look, top: t.space(3), onClose: toggle),
              ),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: Padding(padding: EdgeInsets.symmetric(horizontal: t.space(3)), child: _StageCard(call: call, look: look, wide: false))),
              if (comments) ...[
                // The stage dimmed behind the sheet; pressing it puts the sheet away.
                Positioned.fill(
                  child: GestureDetector(onTap: toggle, child: ColoredBox(color: const Color(0xFF000000).withValues(alpha: look.dark ? 0.45 : 0.18))),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  top: box.maxHeight * 0.16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: look.card,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius('xl'))),
                      boxShadow: [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, -4))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _Comments(call: call, look: look, top: t.space(2), onClose: toggle, grabber: true),
                  ),
                ),
              ],
            ]),
          ),
          bar,
        ]);
      }),
    );
  }
}

/// Minimise on the left, as Clubhouse's "⌄ All rooms"; Deafen, Devices and Settings on the right.
class _Header extends StatelessWidget {
  const _Header({required this.call, required this.look, required this.top, required this.camera});
  final SpaceCall call;
  final _Look look;
  final double top;

  /// The camera up here, not in the foot: a phone's foot has no room for it beside "Leave quietly".
  final bool camera;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), top, t.space(3), t.space(2)),
      child: Row(children: [
        Flexible(child: _Pill(look: look, icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: call.onMinimize)),
        SizedBox(width: t.space(2)),
        const Spacer(),
        if (camera) ...[_Camera(call: call, look: look, size: 38), SizedBox(width: t.space(1))],
        _Round(look: look, icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), on: call.deafened, onPressed: call.onDeafen, size: 38),
        SizedBox(width: t.space(1)),
        _Round(look: look, icon: Lucide.slidersHorizontal, label: SpaceWords.devices, onPressed: call.onDevices == null ? null : () => call.onDevices!(context), size: 38),
        SizedBox(width: t.space(1)),
        _Round(look: look, icon: Lucide.settings, label: SpaceWords.settings, onPressed: call.onSettings == null ? null : () => call.onSettings!(context), size: 38),
      ]),
    );
  }
}

/// The room: LIVE, how many are here and for how long, its name, then who is on stage and who is listening.
class _StageCard extends StatelessWidget {
  const _StageCard({required this.call, required this.look, required this.wide});
  final SpaceCall call;
  final _Look look;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final alone = call.people.length == 1;
    // On stage: whoever is not muted, and always this device (so its own voice shows); listening: the muted rest.
    final stage = [for (final p in call.people) if (p.me || !p.muted) p];
    final listening = [for (final p in call.people) if (!p.me && p.muted) p];
    final cameras = call.withVideo;
    final here = call.people.length;
    final inset = wide ? t.space(6) : t.space(4);
    final gap = wide ? t.space(4) : t.space(5);
    return Container(
      decoration: BoxDecoration(
        color: look.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius('xl')), bottom: Radius.circular(wide ? t.radius('xl') : 0)),
        border: look.dark ? Border.all(color: look.rule) : null,
        boxShadow: look.dark ? null : [BoxShadow(color: const Color(0xFF5A4E1E).withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth - inset * 2;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(inset, wide ? t.space(4) : t.space(5), inset, t.space(5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const _Live(),
              SizedBox(width: t.space(2)),
              AppIcon(Lucide.users, size: 15, wash: false, color: look.ink3),
              SizedBox(width: t.space(1)),
              Flexible(
                child: Text(
                  '$here ${here == 1 ? 'person' : 'people'} here · ${call.clock(DateTime.now())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: look.ink3),
                ),
              ),
            ]),
            SizedBox(height: t.space(2)),
            Text(call.channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, wide ? 30 : 24, weight: 'bold', color: look.ink)),
            if (cameras.isNotEmpty) ...[
              SizedBox(height: gap),
              _Section(look: look, icon: Lucide.video, label: 'On camera', count: cameras.length),
              SizedBox(height: t.space(3)),
              _Cameras(call: call, people: cameras, wide: wide),
            ],
            SizedBox(height: gap),
            _Section(look: look, icon: LucideMore.audioLines, label: 'On stage', count: stage.length),
            SizedBox(height: t.space(4)),
            if (alone)
              _Alone(call: call, look: look)
            else
              _Grid(width: width, tile: wide ? 132 : 112, children: [for (final p in stage) _Speaker(call: call, person: p, look: look, size: wide ? 96 : 84)]),
            if (listening.isNotEmpty) ...[
              SizedBox(height: gap),
              _Section(look: look, icon: LucideMore.headphones, label: 'Listening', count: listening.length),
              SizedBox(height: t.space(3)),
              _Grid(width: width, tile: wide ? 96 : 86, children: [for (final p in listening) _Listener(call: call, person: p, look: look)]),
            ],
          ]),
        );
      }),
    );
  }
}

/// X Spaces' LIVE pill: purple with a little sound wave.
class _Live extends StatelessWidget {
  const _Live();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 3),
      decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(t.radius('full'))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const AppIcon(LucideMore.audioLines, size: 13, wash: false, color: _white),
        const SizedBox(width: 4),
        Text('LIVE', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: _white).copyWith(letterSpacing: 0.8)),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.look, required this.icon, required this.label, required this.count});
  final _Look look;
  final LucideIcon icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(children: [
      AppIcon(icon, size: 16, wash: false, color: look.ink2),
      SizedBox(width: t.space(2)),
      Text(label, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: look.ink2)),
      SizedBox(width: t.space(2)),
      Text('$count', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: look.ink3)),
    ]);
  }
}

/// Tiles of one width in rows, as many across as fit, spread evenly.
class _Grid extends StatelessWidget {
  const _Grid({required this.width, required this.tile, required this.children});
  final double width;
  final double tile;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final across = (width / tile).floor().clamp(1, 8);
    final w = width / across;
    return Wrap(runSpacing: context.tokens.space(4), children: [for (final c in children) SizedBox(width: w, child: c)]);
  }
}

/// A face that ripples purple from [SpaceCall.levels] while they talk.
class _Face extends StatelessWidget {
  const _Face({required this.call, required this.person, required this.size});
  final SpaceCall call;
  final SpacePerson person;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) => RippleAvatar(name: person.name, level: person.muted ? 0 : (now[person.id] ?? 0), muted: person.muted, size: size, color: _purple),
      );
}

/// Their role as Clubhouse and Spaces name it: the owner hosts, an admin co-hosts, others by their role's name.
String? _roleOf(SpaceCall call, SpacePerson p) {
  if (p.owner) return 'Host';
  final label = p.roleLabel(call.room?.roster);
  if (label == null) return null;
  return p.role?.id == Role.admin ? 'Co-host' : label;
}

/// Someone on stage: a big face, a mic-off or camera badge, their name with a wave while they talk, their role.
class _Speaker extends StatelessWidget {
  const _Speaker({required this.call, required this.person, required this.look, required this.size});
  final SpaceCall call;
  final SpacePerson person;
  final _Look look;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final role = _roleOf(call, person);
    final tap = call.onPerson == null ? null : () => call.onPerson!(context, person);
    return GlacierPressable(
      onPressed: tap,
      semanticLabel: '${person.shown}${role == null ? '' : ', $role'}${person.muted ? ', muted' : ''}',
      builder: (context, state) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: size + 8,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            _Face(call: call, person: person, size: size),
            if (person.muted) Positioned(right: 0, bottom: 0, child: _Badge(look: look, icon: LucideMore.micOff, color: look.ink2)),
            if (person.video) Positioned(left: 0, bottom: 0, child: _Badge(look: look, icon: Lucide.video, color: _purple)),
          ]),
        ),
        SizedBox(height: t.space(3)),
        ValueListenableBuilder<Map<String, double>>(
          valueListenable: call.levels,
          builder: (context, now, _) {
            final talking = call.isTalking(person, now);
            return Row(mainAxisSize: MainAxisSize.min, children: [
              if (talking) ...[const AppIcon(LucideMore.audioLines, size: 13, wash: false, color: _purple), const SizedBox(width: 3)],
              Flexible(
                child: Text(person.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: talking ? look.ink : look.ink2)),
              ),
            ]);
          },
        ),
        if (role != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: role == 'Host' || role == 'Co-host' ? look.tint : look.raised, borderRadius: BorderRadius.circular(t.radius('full'))),
            child: Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: role == 'Host' || role == 'Co-host' ? look.tintInk : look.ink2)),
          ),
        ],
      ]),
    );
  }
}

/// Someone listening: a smaller face and their first name.
class _Listener extends StatelessWidget {
  const _Listener({required this.call, required this.person, required this.look});
  final SpaceCall call;
  final SpacePerson person;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final first = person.shown.split(' ').first;
    return GlacierPressable(
      onPressed: call.onPerson == null ? null : () => call.onPerson!(context, person),
      semanticLabel: '${person.shown}, listening',
      builder: (context, state) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: 60,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            _Face(call: call, person: person, size: 56),
            if (person.video) Positioned(left: 0, bottom: 0, child: _Badge(look: look, icon: Lucide.video, color: _purple, small: true)),
          ]),
        ),
        SizedBox(height: t.space(1)),
        Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: look.ink2)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.look, required this.icon, required this.color, this.small = false});
  final _Look look;
  final LucideIcon icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final s = small ? 22.0 : 28.0;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(color: look.card, shape: BoxShape.circle, border: Border.all(color: look.rule)),
      alignment: Alignment.center,
      child: AppIcon(icon, size: s * 0.52, wash: false, color: color),
    );
  }
}

/// Whoever has their camera on, as dark rounded tiles in a row above the stage.
class _Cameras extends StatelessWidget {
  const _Cameras({required this.call, required this.people, required this.wide});
  final SpaceCall call;
  final List<SpacePerson> people;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final h = wide ? 112.0 : 112.0;
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, _) => SizedBox(width: t.space(2)),
        itemBuilder: (context, i) {
          final p = people[i];
          return GlacierPressable(
            onPressed: call.onPerson == null ? null : () => call.onPerson!(context, p),
            semanticLabel: '${p.shown}, camera on',
            builder: (context, state) => ClipRRect(
              borderRadius: BorderRadius.circular(t.radius('lg')),
              child: SizedBox(
                width: h * 1.4,
                child: Stack(fit: StackFit.expand, children: [
                  SpaceVideo(
                    call: call,
                    person: p,
                    // No picture yet: a deep purple tile with their face, so it reads as a camera waiting, not a hole.
                    fallback: DecoratedBox(
                      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2C78), Color(0xFF17132B)])),
                      child: Center(child: _Face(call: call, person: p, size: h * 0.42)),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    right: 8,
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(t.radius('full'))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const AppIcon(Lucide.video, size: 12, wash: false, color: _white),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: h * 1.4 - 50),
                            child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _white)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Alone on stage: your face rippling with your own voice, and a nudge to bring people in.
class _Alone extends StatelessWidget {
  const _Alone({required this.call, required this.look});
  final SpaceCall call;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final invite = call.onInvite == null ? null : () => call.onInvite!(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: t.space(4)),
        SizedBox(width: 160, child: _Speaker(call: call, person: call.me, look: look, size: 112)),
        SizedBox(height: t.space(6)),
        Text('It\'s just you', style: pageText(t, t.fontSize('lg'), weight: 'bold', color: look.ink)),
        SizedBox(height: t.space(1)),
        Text('Invite people to listen in', textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), color: look.ink3)),
        SizedBox(height: t.space(4)),
        Opacity(
          opacity: invite == null ? 0.45 : 1,
          child: GlacierPressable(
            onPressed: invite,
            semanticLabel: SpaceWords.invite,
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(5), vertical: t.space(2) + 2),
              decoration: BoxDecoration(color: _purple.withValues(alpha: state.pressed ? 0.85 : 1), borderRadius: BorderRadius.circular(t.radius('full'))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const AppIcon(Lucide.userPlus, size: 18, wash: false, color: _white),
                SizedBox(width: t.space(2)),
                ExcludeSemantics(child: Text(SpaceWords.invite, style: pageText(t, t.fontSize('md'), weight: 'bold', color: _white))),
              ]),
            ),
          ),
        ),
        SizedBox(height: t.space(2)),
      ]),
    );
  }
}

/// The chat as the room's comments.
class _Comments extends StatelessWidget {
  const _Comments({required this.call, required this.look, required this.top, required this.onClose, this.grabber = false});
  final SpaceCall call;
  final _Look look;
  final double top;
  final VoidCallback onClose;
  final bool grabber;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (grabber)
        Center(
          child: Container(
            margin: EdgeInsets.only(top: t.space(2)),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: look.rule, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(4), top, t.space(2), t.space(2)),
        child: Row(children: [
          AppIcon(Lucide.messageSquare, size: 18, wash: false, color: look.ink),
          SizedBox(width: t.space(2)),
          Expanded(child: Text('Comments', style: pageText(t, t.fontSize('lg'), weight: 'bold', color: look.ink))),
          GlacierPressable(
            onPressed: onClose,
            semanticLabel: 'Close comments',
            builder: (context, state) => Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: state.pressed ? look.raised : null, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon(Lucide.x, size: 18, wash: false, color: look.ink2),
            ),
          ),
        ]),
      ),
      Container(height: 1, color: look.rule),
      Expanded(child: call.chat()),
    ]);
  }
}

/// Clubhouse's foot: "Leave quietly" on the left; Comments, Invite, Camera and the big mic on the right.
class _Bar extends StatelessWidget {
  const _Bar({required this.call, required this.look, required this.camera, required this.comments, required this.onComments, required this.bottom});
  final SpaceCall call;
  final bool camera;
  final _Look look;
  final bool comments;
  final VoidCallback onComments;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locked = call.micLocked && call.muted;
    final mic = locked ? 'Muted by a moderator' : SpaceWords.mute(call);
    return Container(
      decoration: BoxDecoration(color: look.card, border: Border(top: BorderSide(color: look.rule))),
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(2) + 2, t.space(3), bottom),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Flexible(
          child: GlacierPressable(
            onPressed: call.onLeave,
            semanticLabel: 'Leave quietly',
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
              decoration: BoxDecoration(color: state.pressed ? look.raised : look.raised.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(t.radius('full'))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const AppIcon(LucideMore.hand, size: 17, wash: false, color: _red),
                const SizedBox(width: 6),
                Flexible(child: ExcludeSemantics(child: Text('Leave quietly', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: _red)))),
              ]),
            ),
          ),
        ),
        const Spacer(),
        _Round(look: look, icon: Lucide.messageSquare, label: 'Comments', on: comments, onPressed: onComments),
        _Round(look: look, icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => call.onInvite!(context)),
        if (camera) _Camera(call: call, look: look),
        SizedBox(width: t.space(1)),
        _Round(look: look, icon: SpaceWords.muteIcon(call), label: mic, onPressed: locked ? null : call.onMute, size: 58, mic: true, live: !call.muted, width: 76),
      ]),
    );
  }
}

/// Camera on or off: secondary on an audio stage, so a plain round button.
class _Camera extends StatelessWidget {
  const _Camera({required this.call, required this.look, this.size = 44});
  final SpaceCall call;
  final _Look look;
  final double size;

  @override
  Widget build(BuildContext context) => _Round(
        look: look,
        icon: call.video ? Lucide.video : LucideMore.videoOff,
        label: call.video ? 'Stop camera' : 'Camera',
        on: call.video,
        size: size,
        onPressed: call.videoLocked && !call.video ? null : call.onVideo,
      );
}

/// A round button with its words under it. [mic] is the big one: purple while you are live, plain while muted.
class _Round extends StatelessWidget {
  const _Round({required this.look, required this.icon, required this.label, this.onPressed, this.on = false, this.size = 44, this.mic = false, this.live = false, this.width});
  final _Look look;
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;
  final double size;
  final bool mic;
  final bool live;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ground = mic ? (live ? _purple : look.raised) : (on ? look.tint : look.raised);
    final mark = mic ? (live ? _white : look.ink) : (on ? look.tintInk : look.ink);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => SizedBox(
          width: width ?? size + 22,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedScale(
              scale: state.pressed ? 0.93 : 1,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: ground,
                  shape: BoxShape.circle,
                  boxShadow: mic && live ? [BoxShadow(color: _purple.withValues(alpha: 0.35), blurRadius: 12)] : null,
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: size * 0.42, wash: false, color: mark),
              ),
            ),
            const SizedBox(height: 4),
            // The button's own label says it; the words are not read twice.
            ExcludeSemantics(child: Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: look.ink2).copyWith(height: 1.15))),
          ]),
        ),
      ),
    );
  }
}

/// A rounded pill with an icon and words, as Clubhouse's "⌄ All rooms".
class _Pill extends StatelessWidget {
  const _Pill({required this.look, required this.icon, required this.label, this.onPressed});
  final _Look look;
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2)),
          decoration: BoxDecoration(color: state.pressed ? look.raised : look.card.withValues(alpha: look.dark ? 1 : 0.7), borderRadius: BorderRadius.circular(t.radius('full'))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 18, wash: false, color: look.ink),
            const SizedBox(width: 4),
            Flexible(child: ExcludeSemantics(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: look.ink)))),
          ]),
        ),
      ),
    );
  }
}
