import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import 'space_design.dart';

/// A space's call as Telegram draws its group voice chat (SpaceDesign.telegram): a dark navy sheet headed "Voice
/// Chat", video tiles two across above a list of people whose faces wear a soft moving blob while they talk, and at
/// the foot one big microphone button on a living gradient, two round buttons either side of it. The chat opens as a
/// second sheet on a phone and stands to the right of the voice chat on a computer. Dark in both themes, as
/// Telegram's is.
class TelegramCall extends StatefulWidget {
  const TelegramCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<TelegramCall> createState() => _TelegramCallState();
}

/// Telegram's group call colours (its voipgroup_* theme keys, near enough).
abstract final class _Tg {
  static const backdrop = Color(0xFF0D1117);
  static const sheet = Color(0xFF1C2229);
  static const card = Color(0xFF242C35);
  static const chat = Color(0xFF151A20);
  static const raised = Color(0xFF2D3640);
  static const rule = Color(0x14FFFFFF);
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color(0xFFB4BCC4);
  static const grey = Color(0xFF7E868C);
  static const blue = Color(0xFF4DA6FF);
  static const blueDeep = Color(0xFF3E88F7);
  static const green = Color(0xFF3DD68C);
  static const greenDeep = Color(0xFF17B07B);
  static const red = Color(0xFFF1585B);
  static const mutedRed = Color(0xFFD97C80);
  static const purple = Color(0xFF8E70E0);
  static const slate = Color(0xFF5E6A78);

  /// Telegram's avatar gradients, picked by the name.
  static const faces = [
    [Color(0xFFFF885E), Color(0xFFFF516A)],
    [Color(0xFFFFCD6A), Color(0xFFFFA85C)],
    [Color(0xFF82B1FF), Color(0xFF665FFF)],
    [Color(0xFFA0DE7E), Color(0xFF54CB68)],
    [Color(0xFF53EDD6), Color(0xFF28C9B7)],
    [Color(0xFF72D5FD), Color(0xFF2A9EF1)],
    [Color(0xFFE0A2F3), Color(0xFFD669ED)],
  ];
}

class _TelegramCallState extends State<TelegramCall> {
  /// The chat beside or over the call; null until pressed, when a computer shows it and a phone does not.
  bool? _chat;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final media = MediaQuery.of(context);
    // Telegram's voice chat is dark whatever the app's theme; the chat keeps the app's own theme (its bubbles and
    // composer are drawn from it).
    return SizedBox.expand(
      child: ColoredBox(
        color: _Tg.backdrop,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760 && box.maxHeight >= 480;
          // Docked beside the voice chat by default only where both fit at a comfortable width.
          final chat = _chat ?? (wide && box.maxWidth >= 920);
          void toggleChat() => setState(() => _chat = !chat);
          if (wide) return _computer(context, call, box, chat, toggleChat);
          return _phone(context, call, media, chat, toggleChat);
        }),
      ),
    );
  }

  Widget _phone(BuildContext context, SpaceCall call, MediaQueryData media, bool chat, VoidCallback toggleChat) {
    final pad = media.padding;
    const top = BorderRadius.vertical(top: Radius.circular(18));
    return Stack(children: [
      Positioned.fill(
        top: pad.top + 8,
        child: ClipRRect(
          borderRadius: top,
          child: ColoredBox(
            color: _Tg.sheet,
            child: _VoicePanel(call: call, chatOpen: chat, onChat: toggleChat, bottom: pad.bottom, grabber: true),
          ),
        ),
      ),
      if (chat) ...[
        Positioned.fill(
          child: GestureDetector(onTap: toggleChat, child: const ColoredBox(color: Color(0x99000000))),
        ),
        Positioned.fill(
          top: pad.top + 56,
          child: ClipRRect(
            borderRadius: top,
            child: _ChatPanel(call: call, onClose: toggleChat, bottom: pad.bottom, grabber: true),
          ),
        ),
      ],
    ]);
  }

  Widget _computer(BuildContext context, SpaceCall call, BoxConstraints box, bool chat, VoidCallback toggleChat) {
    final height = math.min(box.maxHeight - 48, 760.0);
    final radius = BorderRadius.circular(16);
    Widget panel(double width, Widget child) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 32)],
          ),
          child: ClipRRect(borderRadius: radius, child: child),
        );
    // The voice chat grows from 440 to 540 with the window, the chat beside it up to 440.
    final voice = (box.maxWidth - 64 - (chat ? 16 + 360 : 0)).clamp(440.0, 540.0);
    final side = math.min(440.0, box.maxWidth - voice - 80);
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        panel(voice, ColoredBox(color: _Tg.sheet, child: _VoicePanel(call: call, chatOpen: chat, onChat: toggleChat, bottom: 0, compact: true))),
        if (chat) ...[
          const SizedBox(width: 16),
          panel(side, _ChatPanel(call: call, onClose: toggleChat, bottom: 0)),
        ],
      ]),
    );
  }
}

/// The voice chat itself: header, the people, the buttons. Holds the header's menu.
class _VoicePanel extends StatefulWidget {
  const _VoicePanel({required this.call, required this.chatOpen, required this.onChat, required this.bottom, this.grabber = false, this.compact = false});
  final SpaceCall call;
  final bool chatOpen;
  final VoidCallback onChat;
  final double bottom;
  final bool grabber;

  /// Rows a little tighter, as on a computer's shorter panel.
  final bool compact;

  @override
  State<_VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<_VoicePanel> {
  bool _menu = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    return Stack(children: [
      Column(children: [
        if (widget.grabber) const _Grabber(),
        _Header(call: call, onMenu: () => setState(() => _menu = !_menu), menuOpen: _menu),
        Expanded(
          // The list fades under the buttons (over its last 20px) rather than stopping at a line.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              stops: [0, r.height <= 40 ? 0.5 : 1 - 20 / r.height, 1],
            ).createShader(r),
            child: _People(call: call, compact: widget.compact),
          ),
        ),
        _Controls(call: call, chatOpen: widget.chatOpen, onChat: widget.onChat, bottom: widget.bottom),
      ]),
      if (_menu) ...[
        Positioned.fill(child: GestureDetector(onTap: () => setState(() => _menu = false), child: const ColoredBox(color: Color(0x00000000)))),
        Positioned(
          top: (widget.grabber ? 14 : 0) + 58,
          right: 12,
          child: _Menu(call: call, close: () => setState(() => _menu = false)),
        ),
      ],
    ]);
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({this.color = const Color(0x33FFFFFF)});
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      );
}

/// "Voice Chat", the space and how many are in it; Minimise on the left, the menu on the right.
class _Header extends StatelessWidget {
  const _Header({required this.call, required this.onMenu, required this.menuOpen});
  final SpaceCall call;
  final VoidCallback onMenu;
  final bool menuOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = call.people.length;
    final name = call.channel.name.isEmpty ? 'Space' : call.channel.name;
    return SizedBox(
      height: 58,
      child: Row(children: [
        const SizedBox(width: 10),
        _IconButton(icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: call.onMinimize),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Voice Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: _Tg.ink)),
            const SizedBox(height: 1),
            Text('$name · $n ${n == 1 ? 'participant' : 'participants'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: _Tg.ink2)),
          ]),
        ),
        _IconButton(icon: Lucide.ellipsisVertical, label: _menuLabel, onPressed: onMenu, on: menuOpen),
        const SizedBox(width: 10),
      ]),
    );
  }
}

/// The header menu's words for a screen reader: what it holds.
final _menuLabel = 'More: ${[SpaceWords.invite, SpaceWords.devices, SpaceWords.settings, SpaceWords.leave].join(', ').toLowerCase()}';

/// A round icon in the header, its words for a screen reader.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.label, required this.onPressed, this.on = false, this.ink});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;

  /// The icon's colour on a light ground (its circle a wash of it); white on the navy otherwise.
  final Color? ink;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        child: GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(shape: BoxShape.circle, color: (ink ?? _Tg.ink).withValues(alpha: on || state.hovered ? 0.14 : 0.08)),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 20, wash: false, color: ink ?? _Tg.ink),
          ),
        ),
      );
}

/// The header's menu, as Telegram's "⋮": invite, devices, the space's settings, leave.
class _Menu extends StatelessWidget {
  const _Menu({required this.call, required this.close});
  final SpaceCall call;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    void Function()? run(void Function(BuildContext)? action) => action == null
        ? null
        : () {
            close();
            action(context);
          };
    return Container(
      width: 270,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _Tg.raised,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _MenuRow(icon: Lucide.userPlus, label: SpaceWords.invite, hint: 'Copy the space\'s invite link', onPressed: run(call.onInvite)),
        _MenuRow(icon: LucideMore.headphones, label: SpaceWords.devices, hint: 'Microphone, camera and speaker', onPressed: run(call.onDevices)),
        _MenuRow(icon: Lucide.settings, label: SpaceWords.settings, hint: 'Roles and permissions', onPressed: run(call.onSettings)),
        Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: _Tg.rule),
        _MenuRow(
          icon: LucideMore.phoneOff,
          label: SpaceWords.leave,
          hint: 'Leave the voice chat',
          danger: true,
          onPressed: call.onLeave == null
              ? null
              : () {
                  close();
                  call.onLeave!();
                },
        ),
      ]),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.hint, required this.onPressed, this.danger = false});
  final LucideIcon icon;
  final String label, hint;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = danger ? _Tg.red : _Tg.ink;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          color: state.hovered || state.pressed ? const Color(0x10FFFFFF) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(children: [
            AppIcon(icon, size: 20, wash: false, color: danger ? _Tg.red : _Tg.ink2),
            const SizedBox(width: 16),
            Expanded(
              child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
                Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: _Tg.grey)),
              ])),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Video tiles two across, "Invite members", then everyone in a list.
class _People extends StatelessWidget {
  const _People({required this.call, this.compact = false});
  final SpaceCall call;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final videos = call.withVideo;
    final alone = call.others.isEmpty;
    final roster = call.room?.roster;
    final rowPad = compact ? 7.0 : 10.0;
    return LayoutBuilder(builder: (context, box) {
      // The video gives way to the list: its tiles shrink (to no less than 84 a row) so everyone in the call fits
      // under them where the panel is short.
      final list = 48 + call.people.length * (46 + rowPad * 2 + 1) + 16 + 12;
      final room = box.maxHeight - list;
      return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        if (videos.isNotEmpty) ...[
          _VideoGrid(call: call, people: videos, room: room),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(color: _Tg.card, borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _InviteRow(onPressed: call.onInvite == null ? null : () => call.onInvite!(context)),
            for (final p in call.people) ...[
              Container(height: 1, margin: const EdgeInsets.only(left: 72), color: _Tg.rule),
              _PersonRow(call: call, person: p, role: p.roleLabel(roster), pad: rowPad),
            ],
          ]),
        ),
        if (alone) ...[
          const SizedBox(height: 20),
          Column(children: [
            // You, large, your voice moving the blob round you while you wait.
            const SizedBox(height: 12),
            ValueListenableBuilder<Map<String, double>>(
              valueListenable: call.levels,
              builder: (context, now, _) => _Face(
                key: const ValueKey('tg-alone-me'),
                name: call.me.name.isEmpty ? 'You' : call.me.name,
                level: call.me.muted ? 0 : (now['me'] ?? 0),
                size: 88,
              ),
            ),
            const SizedBox(height: 28),
            Text('Waiting for others to join', textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: _Tg.ink)),
            const SizedBox(height: 4),
            Text('Invite members, and they will appear here as they come in.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: _Tg.grey)),
          ]),
        ],
      ],
    );
    });
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: 'Invite members',
        builder: (context, state) => Container(
          color: state.hovered || state.pressed ? const Color(0x0CFFFFFF) : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const SizedBox(width: 46, child: Center(child: AppIcon(Lucide.userPlus, size: 22, wash: false, color: _Tg.blue))),
            const SizedBox(width: 12),
            Expanded(child: ExcludeSemantics(child: Text('Invite members', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: _Tg.blue)))),
          ]),
        ),
      ),
    );
  }
}

/// What someone is doing now, in the list's words and colour.
({String words, Color color, LucideIcon icon}) _status(SpaceCall call, SpacePerson p, Map<String, double> now) {
  if (p.muted) return (words: p.me && call.micLocked ? 'muted by a moderator' : 'muted', color: _Tg.mutedRed, icon: LucideMore.micOff);
  if (call.isTalking(p, now)) return (words: 'speaking', color: _Tg.green, icon: Lucide.mic);
  return (words: 'listening', color: _Tg.blue, icon: Lucide.mic);
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.call, required this.person, required this.role, this.pad = 10});
  final SpaceCall call;
  final SpacePerson person;
  final String? role;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = person;
    return GlacierPressable(
      onPressed: call.onPerson == null ? null : () => call.onPerson!(context, p),
      onLongPress: call.onPerson == null ? null : () => call.onPerson!(context, p),
      semanticLabel: p.shown,
      builder: (context, state) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) {
          final s = _status(call, p, now);
          final level = p.muted ? 0.0 : (now[p.id] ?? 0);
          return Container(
            color: state.hovered || state.pressed ? const Color(0x0CFFFFFF) : null,
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: pad),
            child: Row(children: [
              _Face(key: ValueKey('tg-face-${p.id}'), name: p.me ? (p.name.isEmpty ? 'You' : p.name) : p.name, level: level, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: ExcludeSemantics(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: _Tg.ink))),
                    if (p.guest) ...[const SizedBox(width: 6), const _Tag(words: 'guest', color: _Tg.grey)],
                    if (role != null) ...[const SizedBox(width: 6), _Tag(words: role!.toLowerCase(), color: _Tg.blue)],
                  ]),
                  const SizedBox(height: 2),
                  Text(s.words, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: s.color)),
                ])),
              ),
              const SizedBox(width: 8),
              if (p.video) const Padding(padding: EdgeInsets.only(right: 10), child: AppIcon(Lucide.video, size: 18, wash: false, color: _Tg.grey)),
              _MicMark(icon: s.icon, color: s.words == 'listening' ? _Tg.grey : s.color, level: level),
            ]),
          );
        },
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.words, required this.color});
  final String words;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
      child: Text(words, maxLines: 1, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: color)),
    );
  }
}

/// The row's microphone, swelling a little with the voice as Telegram's animated one does.
class _MicMark extends StatelessWidget {
  const _MicMark({required this.icon, required this.color, required this.level});
  final LucideIcon icon;
  final Color color;
  final double level;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: 1 + (level > SpaceCall.talking ? math.min(level, 0.6) * 0.35 : 0),
        duration: const Duration(milliseconds: 120),
        child: AppIcon(icon, size: 22, wash: false, color: color),
      );
}

/// A Telegram face: initials on a gradient circle, a soft blob of colour swelling round it while they talk.
class _Face extends StatefulWidget {
  const _Face({super.key, required this.name, required this.level, this.size = 46});
  final String name;
  final double level;
  final double size;

  @override
  State<_Face> createState() => _FaceState();
}

class _FaceState extends State<_Face> with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..addListener(_step);
  double _strength = 0;
  Duration _last = Duration.zero;

  bool get _talking => widget.level > SpaceCall.talking;
  double get _want => _talking ? (0.4 + widget.level * 1.5).clamp(0.0, 1.0) : 0.0;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  /// Eases the blob toward the voice once a tick, by the time since the last (so it is the same at any frame rate);
  /// stops the clock once a quiet blob has gone.
  void _step() {
    final now = _time.lastElapsedDuration ?? Duration.zero;
    final dt = now < _last ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final want = _want;
    _strength += (want - _strength) * _ease(want > _strength ? 0.3 : 0.08, dt);
    if (want == 0 && _strength < 0.02) {
      _strength = 0;
      _time.stop();
    }
  }

  @override
  void didUpdateWidget(_Face old) {
    super.didUpdateWidget(old);
    _follow();
  }

  void _follow() {
    if (_talking && !_time.isAnimating) {
      _last = Duration.zero;
      _time.repeat();
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = _Tg.faces[widget.name.codeUnits.fold<int>(0, (a, b) => a + b) % _Tg.faces.length];
    final words = widget.name.replaceAll('@', '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final letters = words.isEmpty ? '?' : (words.first.characters.first + (words.length > 1 ? words[1].characters.first : '')).toUpperCase();
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _time,
        builder: (context, _) {
          return CustomPaint(
            painter: _Blob(time: _time.value, strength: _strength, color: const Color(0xFF6FF0B4), second: _Tg.blue, radius: widget.size / 2, spread: 0.32),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(child: Text(letters, style: pageText(t, widget.size * 0.36, weight: 'bold', color: _Tg.ink))),
            ),
          );
        },
      ),
    );
  }
}

/// The share of the way to close in [dt] seconds for an easing that closes [perFrame] of it each 60th of a second.
double _ease(double perFrame, double dt) => 1 - math.pow(1 - perFrame, dt * 60).toDouble();

/// A soft, wobbling blob of colour behind a circle of [radius]: two layers, the outer fainter, growing with
/// [strength] (0 to 1). Telegram's speaking avatars and its big microphone button wear one.
class _Blob extends CustomPainter {
  _Blob({required this.time, required this.strength, required this.color, required this.radius, this.spread = 0.3, this.second});
  final double time;
  final double strength;
  final Color color;
  final double radius;

  /// How far past the circle the blob reaches at full strength, as a share of [radius].
  final double spread;

  /// The outer layer's colour, where it differs (the microphone's gradient).
  final Color? second;

  Path _shape(Offset c, double r, double wobble, double phase) {
    final path = Path();
    const steps = 72;
    for (var s = 0; s <= steps; s++) {
      final a = s / steps * math.pi * 2;
      final d = r * (1 + wobble * math.sin(a * 3 + phase) + wobble * 0.7 * math.sin(a * 5 - phase * 1.4) + wobble * 0.4 * math.cos(a * 2 + phase * 0.6));
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (strength < 0.02) return;
    final c = size.center(Offset.zero);
    final phase = time * math.pi * 2;
    final k = strength.clamp(0.0, 1.0);
    final outer = _shape(c, radius * (1 + spread * k), 0.05 + 0.05 * k, phase);
    final inner = _shape(c, radius * (1 + spread * 0.55 * k), 0.04 + 0.04 * k, -phase * 1.3 + 1);
    canvas.drawPath(outer, Paint()..color = (second ?? color).withValues(alpha: 0.2 * k));
    canvas.drawPath(inner, Paint()..color = color.withValues(alpha: 0.32 * k));
  }

  @override
  bool shouldRepaint(_Blob old) => old.time != time || old.strength != strength || old.color != color || old.second != second;
}

/// Everyone with video on, two across (one alone, or the last of an odd number, across the whole width).
class _VideoGrid extends StatelessWidget {
  const _VideoGrid({required this.call, required this.people, required this.room});
  final SpaceCall call;
  final List<SpacePerson> people;

  /// The height the list leaves for the grid; its rows shrink to fit it, to no less than 84 each.
  final double room;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final half = (box.maxWidth - gap) / 2;
      final rows = (people.length + 1) ~/ 2;
      final fit = math.max(84.0, (room - gap * (rows - 1)) / rows);
      final pair = math.min(half * 0.82, fit);
      final wide = math.min(math.min(box.maxWidth * 9 / 16, 200.0), fit);
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < people.length; i++)
          if (people.length.isOdd && i == people.length - 1)
            SizedBox(width: box.maxWidth, height: wide, child: _VideoTile(call: call, person: people[i]))
          else
            SizedBox(width: half, height: pair, child: _VideoTile(call: call, person: people[i])),
      ]);
    });
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.call, required this.person});
  final SpaceCall call;
  final SpacePerson person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = person;
    return GlacierPressable(
      onPressed: call.onPerson == null ? null : () => call.onPerson!(context, p),
      semanticLabel: '${p.shown}, video',
      builder: (context, state) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) {
          final talking = call.isTalking(p, now);
          final s = _status(call, p, now);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: talking ? _Tg.green : const Color(0x00000000), width: 2.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9.5),
              child: Stack(fit: StackFit.expand, children: [
                SpaceVideo(
                  call: call,
                  person: p,
                  fallback: DecoratedBox(
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF26313D), Color(0xFF151B22)])),
                    child: Center(child: _Face(key: ValueKey('tg-tile-${p.id}'), name: p.me ? (p.name.isEmpty ? 'You' : p.name) : p.name, level: p.muted ? 0 : (now[p.id] ?? 0), size: 64)),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x99000000)]))),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Row(children: [
                    AppIcon(s.icon, size: 15, wash: false, color: s.words == 'listening' ? _Tg.ink : s.color),
                    const SizedBox(width: 5),
                    Expanded(child: ExcludeSemantics(child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: _Tg.ink)))),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// The foot: Video and Deafen, the big microphone, Chat and Leave.
class _Controls extends StatelessWidget {
  const _Controls({required this.call, required this.chatOpen, required this.onChat, required this.bottom});
  final SpaceCall call;
  final bool chatOpen;
  final VoidCallback onChat;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    Widget side(Widget child) => Expanded(child: Center(child: child));
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 6, 8, bottom + 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        side(_RoundButton(
          icon: SpaceWords.videoIcon(call),
          label: SpaceWords.video(call),
          on: call.video,
          onPressed: call.videoLocked ? null : call.onVideo,
        )),
        side(_RoundButton(icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), on: call.deafened, onPressed: call.onDeafen)),
        SizedBox(width: 128, child: _MicButton(call: call)),
        side(_RoundButton(icon: LucideMore.messageCircle, label: SpaceWords.chat, on: chatOpen, onPressed: onChat)),
        side(_RoundButton(icon: Lucide.x, label: SpaceWords.leave, danger: true, onPressed: call.onLeave)),
      ]),
    );
  }
}

/// One of the four round buttons round the microphone: a translucent circle, its words under it.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onPressed, this.on = false, this.danger = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on, danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ground = danger ? _Tg.red.withValues(alpha: 0.28) : (on ? _Tg.blueDeep : const Color(0x1FFFFFFF));
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Padding(
          // Level with the middle of the microphone button.
          padding: const EdgeInsets.only(top: 34),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered && !on ? Color.lerp(ground, _Tg.ink, 0.06) : ground),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 22, wash: false, color: danger ? const Color(0xFFFF8A8C) : _Tg.ink),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _Tg.ink2))),
          ]),
        ),
      ),
    );
  }
}

/// Telegram's big microphone: a gradient circle on a moving blob (blue while live and quiet, green while you talk,
/// slate while muted, red and purple when a moderator has muted you), and what it means under it.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.call});
  final SpaceCall call;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..addListener(_step)
    ..repeat();
  double _strength = 0.3;
  Duration _last = Duration.zero;

  /// Always breathing a little; swelling with your voice while live. Eased once a tick, by the time since the last.
  void _step() {
    final call = widget.call;
    final live = !call.muted && !call.deafened && !call.micLocked;
    final level = live ? (call.levels.value['me'] ?? 0) : 0.0;
    final want = live && level > SpaceCall.talking ? (0.55 + level * 1.2).clamp(0.0, 1.0) : (live ? 0.35 : 0.22);
    final now = _time.lastElapsedDuration ?? Duration.zero;
    final dt = now < _last ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _strength += (want - _strength) * _ease(0.12, dt);
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final call = widget.call;
    final locked = call.micLocked;
    final live = !call.muted && !call.deafened && !locked;
    // Deafened, the button undeafens: hearing comes back first (and your voice with it, unless you muted too).
    final deaf = call.deafened && !locked;
    const size = 96.0;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: call.levels,
      builder: (context, now, _) {
        final level = live ? (now['me'] ?? 0) : 0.0;
        final speaking = live && level > SpaceCall.talking;
        final colors = locked
            ? const [_Tg.red, _Tg.purple]
            : !live
                ? const [Color(0xFF6E7C8C), _Tg.slate]
                : speaking
                    ? const [_Tg.green, _Tg.greenDeep]
                    : const [Color(0xFF5BB0FF), _Tg.blueDeep];
        final title = locked ? 'Muted by a moderator' : (deaf ? SpaceWords.deafen(call) : (live ? 'You\'re live' : 'Unmute'));
        final hint = locked ? 'You can listen' : (deaf ? (call.muted ? 'Tap to listen' : 'Tap to listen and speak') : (live ? 'Tap to mute' : 'Tap to speak'));
        return GlacierPressable(
          onPressed: locked ? null : (deaf ? call.onDeafen : call.onMute),
          semanticLabel: locked || deaf ? title : SpaceWords.mute(call),
          builder: (context, state) => Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 118,
              child: Center(
                child: AnimatedBuilder(
                  animation: _time,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _Blob(time: _time.value, strength: _strength, color: colors.first, second: colors.last, radius: size / 2, spread: 0.24),
                      child: child,
                    );
                  },
                  child: AnimatedScale(
                    scale: state.pressed ? 0.95 : 1,
                    duration: const Duration(milliseconds: 100),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 24)],
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(deaf ? LucideMore.headphoneOff : (live ? Lucide.mic : LucideMore.micOff), size: 38, wash: false, color: _Tg.ink),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: pageText(t, t.fontSize(locked ? 'sm' : 'md'), weight: 'bold', color: _Tg.ink))),
            ExcludeSemantics(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), color: _Tg.grey))),
          ]),
        );
      },
    );
  }
}

/// The space's chat as a sheet of its own (a phone) or a panel beside the voice chat (a computer).
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.call, required this.onClose, required this.bottom, this.grabber = false});
  final SpaceCall call;
  final VoidCallback onClose;
  final double bottom;
  final bool grabber;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = call.channel.name.isEmpty ? 'Space' : call.channel.name;
    // The app's chat (its bubbles, its composer) is drawn from the app's theme, so the panel round it follows that
    // theme too: on the voice chat's navy in dark, and in light one light sheet, header and body alike, rather than a
    // navy header over a white body.
    final dark = t.isDark;
    final paper = dark ? _Tg.chat : t.color('glacier-bg');
    final ink = dark ? _Tg.ink : t.color('app-ink');
    final ink2 = dark ? _Tg.ink2 : t.color('app-ink-3');
    return ColoredBox(
      color: paper,
      child: Column(children: [
        Container(
          decoration: BoxDecoration(
            color: dark ? _Tg.sheet : paper,
            border: dark ? null : Border(bottom: BorderSide(color: t.color('app-ink-4').withValues(alpha: 0.35))),
          ),
          child: Column(children: [
            if (grabber) _Grabber(color: dark ? const Color(0x33FFFFFF) : t.color('app-ink-4')),
            SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 16),
                AppIcon(LucideMore.messageCircle, size: 20, wash: false, color: dark ? _Tg.blue : _Tg.blueDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(SpaceWords.chat, maxLines: 1, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: ink)),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: ink2)),
                  ]),
                ),
                _IconButton(icon: Lucide.x, label: 'Close chat', onPressed: onClose, ink: dark ? null : ink),
                const SizedBox(width: 10),
              ]),
            ),
          ]),
        ),
        Expanded(child: call.chat(bottom: bottom)),
      ]),
    );
  }
}
