import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../tile_grid.dart';
import 'space_design.dart';

/// A space's call as Discord draws a voice channel (SpaceDesign.discord): rounded tiles on a dark stage, a crisp
/// green outline round whoever talks, a "Voice Connected" header, a control bar at the foot (camera, mic with its
/// devices, deafen, a red leave) and "Text in voice" beside the stage on a computer, over it on a phone.
class DiscordCall extends StatefulWidget {
  const DiscordCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<DiscordCall> createState() => _DiscordCallState();
}

/// Discord's own dark greys, kept dark in both themes on the stage; the chat panel follows the app's theme.
abstract final class _D {
  static const ground = Color(0xFF1E1F22);
  static const tile = Color(0xFF2B2D31);
  static const button = Color(0xFF313338);
  static const buttonHover = Color(0xFF3F4147);
  static const deep = Color(0xFF111214);
  static const text = Color(0xFFF2F3F5);
  static const muted = Color(0xFFB5BAC1);
  static const faint = Color(0xFF80848E);
  static const green = Color(0xFF23A55A);
  static const red = Color(0xFFF23F42);
  static const leave = Color(0xFFDA373C);
  static const redTint = Color(0xFF3E2427);
  static const blurple = Color(0xFF5865F2);

  // A tile's ground and its avatar's colour, chosen by the person's id: as Discord takes a tile's colour from the
  // avatar, softened.
  static const grounds = [Color(0xFF353A6B), Color(0xFF2E4A3B), Color(0xFF5A3D2C), Color(0xFF4F2E4C), Color(0xFF2C4A55), Color(0xFF4F4630)];
  static const avatars = [Color(0xFF5865F2), Color(0xFF3BA55C), Color(0xFFE67E22), Color(0xFFEB459E), Color(0xFF1ABC9C), Color(0xFFD9A51C)];

  /// The index into [grounds] and [avatars] for a person: the same for the same id every time.
  static int hue(String id) => id.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff) % grounds.length;
}

class _DiscordCallState extends State<DiscordCall> {
  /// Whether the chat shows; null until chosen, which means open on a computer and closed on a phone.
  bool? _chat;

  SpaceCall get call => widget.call;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      final chatOpen = _chat ?? wide;
      void toggleChat() => setState(() => _chat = !chatOpen);
      final pad = MediaQuery.paddingOf(context);
      final stage = ColoredBox(
        color: _D.ground,
        child: Padding(
          padding: EdgeInsets.only(top: pad.top, bottom: wide ? 0 : pad.bottom),
          child: Column(children: [
            _Header(call: call, wide: wide, chatOpen: chatOpen && wide, onChat: toggleChat),
            Expanded(child: _Stage(call: call, wide: wide)),
            _ControlBar(call: call, wide: wide),
          ]),
        ),
      );
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: stage),
          if (chatOpen) SizedBox(width: 360, child: _ChatPanel(call: call, onClose: toggleChat, wide: true)),
        ]);
      }
      return Stack(fit: StackFit.expand, children: [
        stage,
        if (chatOpen) Positioned.fill(child: _ChatPanel(call: call, onClose: toggleChat, wide: false)),
      ]);
    });
  }
}

/// The speaker icon and the space's name, "Voice Connected" with the clock, and the header's buttons.
class _Header extends StatelessWidget {
  const _Header({required this.call, required this.wide, required this.chatOpen, required this.onChat});
  final SpaceCall call;
  final bool wide;
  final bool chatOpen;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final minimize = call.onMinimize;
    final invite = call.onInvite;
    final settings = call.onSettings;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? t.space(4) : t.space(2), t.space(2), wide ? t.space(3) : t.space(2), t.space(2)),
      child: Row(children: [
        if (!wide) ...[
          _HeaderButton(icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: minimize),
          SizedBox(width: t.space(1)),
        ],
        Expanded(
          child: Row(children: [
            const AppIcon(Lucide.volume2, size: 22, wash: false, color: _D.faint),
            SizedBox(width: t.space(2)),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(call.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize(wide ? 'lg' : 'md'), weight: 'bold', color: _D.text)),
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const AppIcon(Lucide.wifi, size: 13, wash: false, color: _D.green),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('Voice Connected · ${call.clock(DateTime.now())}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _D.green)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
        // On a phone Invite and Settings keep only their icons (their words are still read), so the name has room.
        _HeaderButton(icon: Lucide.userPlus, label: SpaceWords.invite, compact: !wide, onPressed: invite == null ? null : () => invite(context)),
        _HeaderButton(icon: LucideMore.settings, label: SpaceWords.settings, compact: !wide, onPressed: settings == null ? null : () => settings(context)),
        _HeaderButton(icon: LucideMore.messageCircle, label: SpaceWords.chat, on: chatOpen, onPressed: onChat),
        if (wide) _HeaderButton(icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: minimize),
      ]),
    );
  }
}

/// A header icon with its word under it, light on the dark stage; [on] for the chat while it shows. [compact]: the
/// icon alone, the word only read aloud.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, this.onPressed, this.on = false, this.compact = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        toggled: on ? true : null,
        builder: (context, state) {
          final lit = on || state.hovered;
          return Container(
            width: compact ? 40 : 58,
            height: compact ? 40 : null,
            padding: compact ? null : const EdgeInsets.symmetric(vertical: 4),
            alignment: compact ? Alignment.center : null,
            decoration: BoxDecoration(color: on ? const Color(0x1FFFFFFF) : (state.hovered ? const Color(0x12FFFFFF) : null), borderRadius: BorderRadius.circular(8)),
            child: compact
                ? AppIcon(icon, size: 20, wash: false, color: lit ? _D.text : _D.muted)
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon(icon, size: 20, wash: false, color: lit ? _D.text : _D.muted),
                    const SizedBox(height: 3),
                    // The pressable already says the word; the visible one is not read twice. At a large text size
                    // it shrinks to fit rather than losing its end.
                    ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, maxLines: 1, style: pageText(t, 11, weight: 'semibold', color: lit ? _D.text : _D.muted)),
                      ),
                    ),
                  ]),
          );
        },
      ),
    );
  }
}

/// The tiles: everyone in a grid as large as fits, or this device's own tile alone with an invitation.
class _Stage extends StatelessWidget {
  const _Stage({required this.call, required this.wide});
  final SpaceCall call;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final side = wide ? t.space(4) : t.space(3);
    return Padding(
      padding: EdgeInsets.fromLTRB(side, t.space(1), side, t.space(2)),
      child: LayoutBuilder(builder: (context, box) {
        if (call.people.length <= 1) return _Alone(call: call, wide: wide, box: box);
        final n = call.people.length;
        // 4:3 on a computer; on a phone between upright and a little wide, whichever makes them biggest.
        final fit = _fit(box.biggest, n, gap, wide ? tileAspect : 0.75, wide ? tileAspect : 1.6);
        final rows = <Widget>[];
        for (var r = 0; r * fit.cols < n; r++) {
          final row = call.people.skip(r * fit.cols).take(fit.cols).toList();
          if (r > 0) rows.add(SizedBox(height: gap));
          rows.add(Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(width: fit.size.width, height: fit.size.height, child: _Tile(call: call, person: row[i])),
            ],
          ]));
        }
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: rows));
      }),
    );
  }

  /// The column count that gives the largest tiles for [n] in [room], each kept between [minAspect] and [maxAspect].
  static ({int cols, Size size}) _fit(Size room, int n, double gap, double minAspect, double maxAspect) {
    var best = (cols: 1, size: Size.zero);
    for (var cols = 1; cols <= n; cols++) {
      final rows = (n / cols).ceil();
      var w = (room.width - gap * (cols - 1)) / cols;
      var h = (room.height - gap * (rows - 1)) / rows;
      if (w <= 0 || h <= 0) continue;
      if (w / h > maxAspect) w = h * maxAspect;
      if (w / h < minAspect) h = w / minAspect;
      if (w * h > best.size.width * best.size.height) best = (cols: cols, size: Size(w.floorToDouble(), h.floorToDouble()));
    }
    return best;
  }
}

/// Alone in the channel: your own tile large in the middle, still lighting green as you talk, and a way to invite.
class _Alone extends StatelessWidget {
  const _Alone({required this.call, required this.wide, required this.box});
  final SpaceCall call;
  final bool wide;
  final BoxConstraints box;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final invite = call.onInvite;
    const words = 170.0;
    // 4:3, narrower where the window is too short for the whole width.
    final h = math.min(math.min(box.maxWidth, wide ? 560.0 : 420.0) / tileAspect, math.max(120.0, box.maxHeight - words));
    final w = h * tileAspect;
    return Center(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: w, height: h, child: _Tile(call: call, person: call.me)),
          SizedBox(height: t.space(5)),
          Text('Waiting for others to join', textAlign: TextAlign.center, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: _D.text)),
          SizedBox(height: t.space(1)),
          Text('Invite friends to ${call.channel.name} to start talking.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: _D.muted)),
          if (invite != null) ...[
            SizedBox(height: t.space(4)),
            GlacierPressable(
              onPressed: () => invite(context),
              semanticLabel: 'Invite friends',
              builder: (context, state) => Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(5), vertical: t.space(2) + 2),
                decoration: BoxDecoration(color: state.hovered ? const Color(0xFF4752C4) : _D.blurple, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const AppIcon(Lucide.userPlus, size: 18, wash: false, color: Color(0xFFFFFFFF)),
                  SizedBox(width: t.space(2)),
                  ExcludeSemantics(child: Text('Invite friends', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: const Color(0xFFFFFFFF)))),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// One person's tile: their avatar on their colour (or their video), their name in a dark pill, a red mic-off when
/// muted, and the green outline while they talk.
class _Tile extends StatelessWidget {
  const _Tile({required this.call, required this.person});
  final SpaceCall call;
  final SpacePerson person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = person;
    final onPerson = call.onPerson;
    final deafened = p.me && call.deafened;
    final hue = _D.hue(p.id);
    return LayoutBuilder(builder: (context, box) {
      final small = box.maxWidth < 200;
      final face = (math.min(box.maxWidth, box.maxHeight) * 0.36).clamp(36.0, 104.0);
      return ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) {
          final talking = call.isTalking(p, now);
          final avatar = _Avatar(name: p.name, color: _D.avatars[hue], size: face, talking: talking);
          final body = p.video
              ? SpaceVideo(call: call, person: p, fallback: DecoratedBox(
                    // Video on, its picture not here yet: a camera's dark frame, faintly in their colour.
                    decoration: BoxDecoration(gradient: RadialGradient(radius: 1.1, colors: [Color.lerp(_D.deep, _D.grounds[hue], 0.55)!, _D.deep])),
                    child: Center(child: avatar),
                  ))
              : ColoredBox(color: _D.grounds[hue], child: Center(child: avatar));
          return GlacierPressable(
            key: ValueKey('discord-tile-${p.id}'),
            onPressed: onPerson == null ? null : () => onPerson(context, p),
            onLongPress: onPerson == null ? null : () => onPerson(context, p),
            semanticLabel: [p.shown, if (p.muted) 'muted', if (talking) 'talking', if (p.video) 'video on'].join(', '),
            builder: (context, state) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _D.tile,
                border: Border.all(color: talking ? _D.green : (state.hovered ? const Color(0x33FFFFFF) : const Color(0x00000000)), width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(fit: StackFit.expand, children: [
                  body,
                  if (p.video)
                    Positioned(
                      top: t.space(2),
                      right: t.space(2),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
                        child: const AppIcon(Lucide.video, size: 14, wash: false, color: _D.text),
                      ),
                    ),
                  Positioned(
                    left: t.space(2),
                    bottom: t.space(2),
                    right: t.space(2),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (p.muted) ...[
                            AppIcon(deafened ? LucideMore.headphoneOff : SpaceWords.mutedIcon(p), size: 14, wash: false, color: _D.red),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, small ? 12 : 13, weight: 'semibold', color: _D.text)),
                          ),
                          if (p.guest) ...[
                            const SizedBox(width: 6),
                            Text('Guest', style: pageText(t, 11, weight: 'semibold', color: _D.muted)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
    });
  }
}

/// A round avatar with the first letter, ringed green while they talk, with a dark gap between ring and face as
/// Discord's has.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color, required this.size, required this.talking});
  final String name;
  final Color color;
  final double size;
  final bool talking;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final letter = (name.trim().characters.firstOrNull ?? '?').toUpperCase();
    return Container(
      width: size + 10,
      height: size + 10,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The fill shows only in the 2px gap round the face: dark, so the ring reads crisp on any tile colour.
        color: talking ? _D.ground : null,
        border: Border.all(color: talking ? _D.green : const Color(0x00000000), width: 3),
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(letter, style: pageText(t, size * 0.42, weight: 'bold', color: const Color(0xFFFFFFFF))),
      ),
    );
  }
}

/// Discord's bar at the foot: camera, the mic with its devices behind a chevron, deafen, and a red leave.
class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.call, required this.wide});
  final SpaceCall call;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final devices = call.onDevices;
    // Each column is its button plus a fixed margin for the word, so the buttons sit evenly whatever the words say.
    final gap = SizedBox(width: wide ? t.space(2) : t.space(1));
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), wide ? t.space(4) : t.space(3)),
      // Too wide for the screen (a large text size, a narrow phone): the whole bar shrinks rather than overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _BarButton(
            icon: call.videoLocked ? Lucide.lock : SpaceWords.videoIcon(call),
            label: call.videoLocked ? 'Video locked' : SpaceWords.video(call),
            onPressed: call.videoLocked ? null : call.onVideo,
            look: call.videoLocked ? _Look.alarm : (call.video ? _Look.lit : _Look.plain),
          ),
          gap,
          // The other camera, beside the camera's button, on a phone while video is on (GMFB-57).
          if (call.onFlip != null) ...[
            _BarButton(icon: SpaceWords.flipIcon, label: 'Flip', onPressed: call.onFlip, look: _Look.plain),
            gap,
          ],
          // Discord's Share Your Screen, beside the camera (GMFB-27), where this device can.
          if (call.onScreen != null) ...[
            _BarButton(
              icon: LucideMore.screenShare,
              label: call.screen ? 'Stop sharing' : 'Screen',
              onPressed: call.videoLocked && !call.screen ? null : () => call.onScreen!(context),
              look: call.screen ? _Look.lit : _Look.plain,
            ),
            gap,
          ],
          _BarButton(
            icon: call.micLocked ? Lucide.lock : SpaceWords.muteIcon(call),
            label: call.micLocked ? 'Mic locked' : SpaceWords.mute(call),
            onPressed: call.micLocked ? null : call.onMute,
            look: call.muted || call.micLocked ? _Look.alarm : _Look.plain,
            onMore: devices == null ? null : () => devices(context),
          ),
          gap,
          _BarButton(
            icon: SpaceWords.deafenIcon(call),
            label: SpaceWords.deafen(call),
            onPressed: call.onDeafen,
            look: call.deafened ? _Look.alarm : _Look.plain,
          ),
          gap,
          _BarButton(icon: LucideMore.phoneOff, label: SpaceWords.leave, onPressed: call.onLeave, look: _Look.danger, width: wide ? 76 : 68),
        ]),
      ),
    );
  }
}

/// How a bar button is coloured: plain grey; lit (white, the camera while on); alarm (red on a red tint: muted,
/// deafened, or locked off); danger (solid red, Leave).
enum _Look { plain, lit, alarm, danger }

/// A rounded button of the bar with its word under it. [onMore] adds Discord's chevron for devices beside the icon.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onPressed, required this.look, this.onMore, this.width = 56});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final _Look look;
  final VoidCallback? onMore;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const height = 48.0;
    final (ground, hover, mark) = switch (look) {
      _Look.plain => (_D.button, _D.buttonHover, _D.text),
      _Look.lit => (_D.text, const Color(0xFFDBDEE1), _D.ground),
      _Look.alarm => (_D.redTint, const Color(0xFF4F2A2E), _D.red),
      _Look.danger => (_D.leave, const Color(0xFFA12828), const Color(0xFFFFFFFF)),
    };
    Widget face(VoidCallback? press, String said, Widget child, BorderRadius radius, double w) => Opacity(
          opacity: press == null ? 0.55 : 1,
          child: GlacierPressable(
            onPressed: press,
            semanticLabel: said,
            builder: (context, s) => Container(
              width: w,
              height: height,
              decoration: BoxDecoration(color: s.hovered && press != null ? hover : ground, borderRadius: radius),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
    final more = onMore;
    final main = face(
      onPressed,
      label,
      AppIcon(icon, size: 22, wash: false, color: mark),
      more == null ? BorderRadius.circular(14) : const BorderRadius.horizontal(left: Radius.circular(14)),
      width,
    );
    final column = width + (more == null ? 0 : 31) + 20;
    return SizedBox(
      width: column,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (more == null)
          main
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            main,
            Container(width: 1, height: height, color: _D.ground),
            face(more, SpaceWords.devices, const AppIcon(Lucide.chevronUp, size: 16, wash: false, color: _D.muted), const BorderRadius.horizontal(right: Radius.circular(14)), 30),
          ]),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: pageText(t, 11, weight: 'semibold', color: _D.muted))),
        ),
      ]),
    );
  }
}

/// "Text in voice": the space's chat beside the stage on a computer, over it on a phone; it follows the app's theme.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.call, required this.onClose, required this.wide});
  final SpaceCall call;
  final VoidCallback onClose;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final ink = t.color('app-ink');
    final ink3 = t.color('app-ink-3');
    final close = GlacierPressable(
      onPressed: onClose,
      semanticLabel: wide ? 'Close chat' : 'Back to call',
      builder: (context, s) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: s.hovered ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(8)),
        child: AppIcon(wide ? Lucide.x : Lucide.arrowLeft, size: 20, wash: false, color: t.color('app-ink-2')),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: wide ? Border(left: BorderSide(color: t.color('app-rule'))) : null,
      ),
      padding: EdgeInsets.only(top: pad.top),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: EdgeInsets.fromLTRB(wide ? t.space(4) : t.space(2), t.space(2), t.space(2), t.space(2)),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule')))),
          child: Row(children: [
            if (!wide) ...[close, SizedBox(width: t.space(1))],
            AppIcon(LucideMore.messageCircle, size: 20, wash: false, color: ink3),
            SizedBox(width: t.space(2)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Text in voice', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold', color: ink)),
                Text(call.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: ink3)),
              ]),
            ),
            if (!wide) _VoicePill(call: call),
            if (wide) close,
          ]),
        ),
        Expanded(child: call.chat(bottom: wide ? 0 : pad.bottom)),
      ]),
    );
  }
}

/// On the phone's chat page: still in the call, for how long, and the mic to hand.
class _VoicePill extends StatelessWidget {
  const _VoicePill({required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final off = call.muted || call.micLocked;
    return GlacierPressable(
      onPressed: call.micLocked ? null : call.onMute,
      semanticLabel: call.micLocked ? 'Mic locked' : SpaceWords.mute(call),
      builder: (context, s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: (off ? _D.red : _D.green).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(off ? LucideMore.micOff : Lucide.mic, size: 15, wash: false, color: off ? _D.red : _D.green),
          const SizedBox(width: 6),
          Text(call.clock(DateTime.now()), style: pageText(t, 12, weight: 'semibold', color: off ? _D.red : _D.green)),
        ]),
      ),
    );
  }
}
