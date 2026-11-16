import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import 'space_design.dart';

/// A space's call drawn like Group FaceTime (SpaceDesign.facetime): a dark, full-bleed stage where one other fills the
/// screen and several float as rounded tiles that grow for whoever talks, you in a small picture-in-picture in the top
/// corner, and frosted glass over it all: a card with the space's name and clock, and a capsule of round, labelled
/// buttons. Whoever talks gets FaceTime's soft white glow, you too, even alone. The chat is a glass sheet from the
/// foot on a phone and a glass panel at the side on a computer.
///
/// The stage stays dark in both themes, as FaceTime's does; the colours behind faces and the chat's sheet follow it.
class FaceTimeCall extends StatefulWidget {
  const FaceTimeCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<FaceTimeCall> createState() => _FaceTimeCallState();
}

const _white = Color(0xFFFFFFFF);
const _soft = Color(0xD9FFFFFF);
const _stageInk = Color(0xFF0B0B0E);

/// Wider than this is a computer's window: controls in one capsule, the chat beside the stage.
const _wide = 760.0;

/// Your picture-in-picture in the top corner.
const _pipPhone = Size(100, 136), _pipWide = Size(212, 132);

class _FaceTimeCallState extends State<FaceTimeCall> {
  bool _chat = false;

  /// Who had the big tile last: kept while nobody talks, so the tiles don't jump about at every pause.
  String? _featured;

  void _toggleChat() => setState(() => _chat = !_chat);

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= _wide;
      final panel = wide && _chat ? math.min(380.0, box.maxWidth * 0.32) : 0.0;
      return ColoredBox(
        color: _stageInk,
        child: Stack(children: [
          // The stage, and everything floating over it, narrows for the chat's panel on a computer.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: 0,
            top: 0,
            bottom: 0,
            right: panel,
            child: Stack(children: [
              Positioned.fill(
                child: ValueListenableBuilder<Map<String, double>>(
                  valueListenable: call.levels,
                  builder: (context, now, _) => _stage(context, now, wide, pad),
                ),
              ),
              if (call.others.isNotEmpty || call.me.video)
                Positioned(top: pad.top + 12, right: 12, child: _Pip(call: call, wide: wide)),
              Positioned(
                top: pad.top + 12,
                left: 12,
                right: call.others.isNotEmpty || call.me.video ? 12 + (wide ? _pipWide : _pipPhone).width + 12 : 12,
                child: Align(alignment: Alignment.topLeft, child: _Header(call: call)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 12,
                child: Center(child: wide ? FittedBox(fit: BoxFit.scaleDown, child: _Capsule(call: call, chat: _chat, onChat: _toggleChat)) : _PhoneControls(call: call, chat: _chat, onChat: _toggleChat)),
              ),
            ]),
          ),
          if (wide)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              right: _chat ? 0 : -400,
              width: math.max(panel, 380),
              child: _ChatPanel(call: call, onClose: _toggleChat, pad: pad, side: true),
            )
          else ...[
            // A scrim to tap the sheet away.
            IgnorePointer(
              ignoring: !_chat,
              child: AnimatedOpacity(
                opacity: _chat ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: GestureDetector(onTap: _toggleChat, child: const SizedBox.expand(child: ColoredBox(color: Color(0x66000000)))),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              height: box.maxHeight * 0.66,
              bottom: _chat ? 0 : -box.maxHeight * 0.7,
              child: _ChatPanel(call: call, onClose: _toggleChat, pad: pad, side: false),
            ),
          ],
        ]),
      );
    });
  }

  Widget _stage(BuildContext context, Map<String, double> now, bool wide, EdgeInsets pad) {
    final call = widget.call;
    final others = call.others;
    if (others.isEmpty) return _Alone(call: call, now: now, wide: wide);
    if (others.length == 1) return _Solo(call: call, person: others.first, talking: call.isTalking(others.first, now), wide: wide);

    final loud = call.loudest(now);
    if (loud != null && !loud.me) _featured = loud.id;
    final featured = others.firstWhere((p) => p.id == _featured, orElse: () => others.first);
    _featured = featured.id;
    return _Mosaic(call: call, featured: featured, now: now, wide: wide, pad: pad);
  }
}

/// A soft two-colour wash made from someone's name, the ground behind a face with no picture (FaceTime's monogram
/// backgrounds): lighter in the light theme, deep in the dark.
LinearGradient _washFor(BuildContext context, String name) {
  final dark = context.tokens.color('app-paper').computeLuminance() < 0.3;
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final top = HSLColor.fromAHSL(1, hue, 0.42, dark ? 0.30 : 0.55).toColor();
  final bottom = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.38, dark ? 0.13 : 0.32).toColor();
  return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom]);
}

/// A face with a soft white glow behind it while they talk; it ripples too (SpaceFace).
class _Monogram extends StatelessWidget {
  const _Monogram({required this.call, required this.person, required this.size, required this.talking});
  final SpaceCall call;
  final SpacePerson person;
  final double size;
  final bool talking;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [if (talking) BoxShadow(color: _white.withValues(alpha: 0.45), blurRadius: size * 0.35, spreadRadius: size * 0.02)],
        ),
        child: SpaceFace(call: call, person: person, size: size),
      );
}

/// A frosted panel: the stage blurred behind a translucent tint.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 22, this.padding = EdgeInsets.zero, this.tint = const Color(0x3D202024)});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color tint;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: _white.withValues(alpha: 0.14), width: 0.8),
            ),
            child: child,
          ),
        ),
      );
}

/// The card top left: the space, how many are in it, the clock.
class _Header extends StatelessWidget {
  const _Header({required this.call});
  final SpaceCall call;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = call.people.length;
    final sub = [n == 1 ? 'Just you' : '$n people', call.clock(DateTime.now())].join('  ·  ');
    return _Glass(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(10, 9, 16, 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: t.colorOf('#34c759'), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: AppIcon(call.video ? Lucide.video : Lucide.phone, size: 17, wash: false, color: _white),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(call.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: _white)),
            const SizedBox(height: 1),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: _soft))),
              if (call.micLocked) ...[
                const SizedBox(width: 8),
                const AppIcon(Lucide.lock, size: 11, wash: false, color: _soft),
                const SizedBox(width: 3),
                Text('Mic locked', style: pageText(t, t.fontSize('xs'), color: _soft)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Alone: your own face (or picture) big in the middle, rippling and glowing as you speak, and an Invite button.
class _Alone extends StatelessWidget {
  const _Alone({required this.call, required this.now, required this.wide});
  final SpaceCall call;
  final Map<String, double> now;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = call.me;
    final talking = call.isTalking(me, now);
    final selfView = me.video
        ? SizedBox(width: wide ? 300 : 220, height: wide ? 220 : 290, child: _Tile(call: call, person: me, talking: talking, radius: 28, faceSize: 96, label: false))
        : _Monogram(call: call, person: me, size: wide ? 168 : 148, talking: talking);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: _washFor(context, call.channel.name)),
      child: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0x00000000), Color(0x8C000000)], radius: 1.1)))),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            selfView,
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Waiting for others…', textAlign: TextAlign.center, style: pageText(t, t.fontSize('xl'), weight: 'semibold', color: _white)),
            ),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(call.muted ? LucideMore.micOff : Lucide.mic, size: 14, wash: false, color: talking ? _white : _soft),
              const SizedBox(width: 6),
              Text(call.muted ? 'You\'re muted' : (talking ? 'You\'re speaking' : 'Your mic is on'), style: pageText(t, t.fontSize('sm'), color: _soft)),
            ]),
            const SizedBox(height: 22),
            _GlassPill(icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => call.onInvite!(context)),
            SizedBox(height: wide ? 60 : 150),
          ]),
        ),
      ]),
    );
  }
}

/// A glass capsule with an icon and words: Invite when alone, the extras under a phone's buttons.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label, this.onPressed, this.small = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => AnimatedScale(
          scale: state.pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 100),
          child: _Glass(
            radius: 999,
            tint: const Color(0x33FFFFFF),
            padding: small ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7) : const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: small ? 14 : 17, wash: false, color: _white),
              SizedBox(width: small ? 6 : 8),
              Text(label, style: pageText(t, t.fontSize(small ? 'xs' : 'md'), weight: 'semibold', color: _white)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One other in the call: they fill the screen.
class _Solo extends StatelessWidget {
  const _Solo({required this.call, required this.person, required this.talking, required this.wide});
  final SpaceCall call;
  final SpacePerson person;
  final bool talking;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final picture = person.stream != null;
    final onPerson = call.onPerson == null ? null : () => call.onPerson!(context, person);
    return GlacierPressable(
      onPressed: onPerson,
      onLongPress: onPerson,
      semanticLabel: person.name,
      haptic: null,
      builder: (context, _) => Stack(fit: StackFit.expand, children: [
        if (picture)
          SpaceVideo(call: call, person: person)
        else
          DecoratedBox(
            decoration: BoxDecoration(gradient: _washFor(context, person.name)),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Monogram(call: call, person: person, size: wide ? 180 : 156, talking: talking),
                const SizedBox(height: 22),
                Text(person.name, style: pageText(t, t.fontSize('xl'), weight: 'semibold', color: _white)),
                const SizedBox(height: 4),
                Text(person.muted ? 'Muted' : (person.video ? 'Camera starting…' : (talking ? 'Speaking' : 'Audio only')), style: pageText(t, t.fontSize('sm'), color: _soft)),
                SizedBox(height: wide ? 40 : 120),
              ]),
            ),
          ),
        // FaceTime's speaking glow, round the edge of the screen.
        IgnorePointer(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(border: Border.all(color: _white.withValues(alpha: talking ? 0.55 : 0), width: 3)),
          ),
        ),
      ]),
    );
  }
}

/// Several others: floating rounded tiles, the featured one (whoever talks) big, the rest smaller beside it.
class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.call, required this.featured, required this.now, required this.wide, required this.pad});
  final SpaceCall call;
  final SpacePerson featured;
  final Map<String, double> now;
  final bool wide;
  final EdgeInsets pad;

  @override
  Widget build(BuildContext context) {
    final rest = [for (final p in call.others) if (p.id != featured.id) p];
    return DecoratedBox(
      decoration: BoxDecoration(gradient: _washFor(context, call.channel.name)),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0x99000000)),
        child: LayoutBuilder(builder: (context, box) {
          // Room under the header and above the controls.
          const gap = 10.0;
          // On a phone the tiles start under your picture in the corner; on a computer only the side column does.
          final top = pad.top + (wide ? 92 : 12 + _pipPhone.height + 12);
          final sideTop = pad.top + 12 + _pipWide.height + 12;
          final bottom = pad.bottom + (wide ? 120 : 172);
          final left = wide ? 24.0 : 12.0;
          final w = box.maxWidth - left * 2;
          final h = math.max(0.0, box.maxHeight - top - bottom);
          final rects = <String, Rect>{};
          if (wide) {
            // The featured tile on the left, the rest in a grid on the right.
            final cols = rest.length > 4 ? 2 : 1;
            final rows = math.max(1, (rest.length / cols).ceil());
            final sideW = math.min(w * 0.34, cols * 220.0);
            final bigW = w - sideW - gap;
            rects[featured.id] = Rect.fromLTWH(left, top, bigW, h);
            final cellW = (sideW - gap * (cols - 1)) / cols;
            final sideH = math.max(0.0, box.maxHeight - sideTop - bottom);
            final cellH = math.max(0.0, math.min((sideH - gap * (rows - 1)) / rows, cellW * 0.9));
            final used = rows * cellH + (rows - 1) * gap;
            for (var i = 0; i < rest.length; i++) {
              rects[rest[i].id] = Rect.fromLTWH(left + bigW + gap + (i % cols) * (cellW + gap), sideTop + (sideH - used) / 2 + (i ~/ cols) * (cellH + gap), cellW, cellH);
            }
          } else {
            // The featured tile across the top, the rest in rows of two or three below.
            final cols = rest.length > 4 ? 3 : 2;
            final rows = math.max(1, (rest.length / cols).ceil());
            final cellW = (w - gap * (cols - 1)) / cols;
            final cellH = math.max(0.0, math.min(cellW * (cols == 3 ? 1.1 : 0.95), (h * 0.5 - gap * rows) / rows));
            final bigH = h - rows * (cellH + gap);
            rects[featured.id] = Rect.fromLTWH(left, top, w, bigH);
            for (var i = 0; i < rest.length; i++) {
              final row = i ~/ cols;
              final inRow = math.min(cols, rest.length - row * cols);
              // A short last row is centred, as FaceTime's are.
              final shift = (cols - inRow) * (cellW + gap) / 2;
              rects[rest[i].id] = Rect.fromLTWH(left + shift + (i % cols) * (cellW + gap), top + bigH + gap + row * (cellH + gap), cellW, cellH);
            }
          }
          return Stack(children: [
            for (final p in call.others)
              AnimatedPositioned(
                key: ValueKey('ft-tile-${p.id}'),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                left: rects[p.id]!.left,
                top: rects[p.id]!.top,
                width: rects[p.id]!.width,
                height: rects[p.id]!.height,
                child: _Tile(call: call, person: p, talking: call.isTalking(p, now), big: p.id == featured.id, faceSize: p.id == featured.id ? (wide ? 140 : 112) : (wide ? 64 : 52)),
              ),
          ]);
        }),
      ),
    );
  }
}

/// A rounded FaceTime tile: their picture, or their face on their own wash, their name at the foot, and a white glow
/// while they talk.
class _Tile extends StatelessWidget {
  const _Tile({required this.call, required this.person, required this.talking, this.big = false, this.radius = 22, this.faceSize = 56, this.label = true});
  final SpaceCall call;
  final SpacePerson person;
  final bool talking;
  final bool big;
  final double radius;
  final double faceSize;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onPerson = call.onPerson == null ? null : () => call.onPerson!(context, person);
    final face = DecoratedBox(
      decoration: BoxDecoration(gradient: _washFor(context, person.name)),
      child: Center(child: _Monogram(call: call, person: person, size: faceSize, talking: talking)),
    );
    return GlacierPressable(
      onPressed: onPerson,
      onLongPress: onPerson,
      semanticLabel: person.shown,
      haptic: null,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: talking ? _white.withValues(alpha: 0.9) : _white.withValues(alpha: 0.08), width: talking ? 2.5 : 1),
          boxShadow: [
            if (talking) BoxShadow(color: _white.withValues(alpha: 0.38), blurRadius: 22, spreadRadius: 1),
            const BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: Stack(fit: StackFit.expand, children: [
            if (person.video)
              // Video on but no picture yet (and always in a test): their face on a darker wash, a camera mark below.
              SpaceVideo(call: call, person: person, faceSize: faceSize, fallback: Stack(fit: StackFit.expand, children: [const ColoredBox(color: Color(0xFF1C1C1F)), Center(child: _Monogram(call: call, person: person, size: faceSize, talking: talking))]))
            else
              face,
            if (label)
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Row(children: [
                  Flexible(
                    child: Text(
                      person.shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: pageText(t, t.fontSize(big ? 'md' : 'sm'), weight: 'semibold', color: _white).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)]),
                    ),
                  ),
                  if (person.muted) ...[
                    const SizedBox(width: 6),
                    const AppIcon(LucideMore.micOff, size: 13, wash: false, color: _white),
                  ],
                  if (person.video) ...[
                    const SizedBox(width: 6),
                    const AppIcon(Lucide.video, size: 13, wash: false, color: _soft),
                  ],
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// You, in the corner: your picture (or face), glowing white as you speak.
class _Pip extends StatelessWidget {
  const _Pip({required this.call, required this.wide});
  final SpaceCall call;
  final bool wide;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) => SizedBox(
          width: (wide ? _pipWide : _pipPhone).width,
          height: (wide ? _pipWide : _pipPhone).height,
          child: _Tile(call: call, person: call.me, talking: call.isTalking(call.me, now), radius: 18, faceSize: wide ? 56 : 48),
        ),
      );
}

/// A computer's controls: one glass capsule of round, labelled buttons, End apart on the right.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.call, required this.chat, required this.onChat});
  final SpaceCall call;
  final bool chat;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final b = _Buttons(context, call, chat: chat, onChat: onChat);
    Widget slot(Widget w) => SizedBox(width: 72, child: w);
    return _Glass(
      radius: 36,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final w in [b.chat, b.mute, b.video, b.deafen, b.invite]) slot(w),
        Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), color: _white.withValues(alpha: 0.18)),
        for (final w in [b.devices, b.settings, b.minimize]) slot(w),
        const SizedBox(width: 8),
        slot(b.end),
      ]),
    );
  }
}

/// A phone's controls: the main six as round buttons in a glass panel, the rest as small glass pills under them.
class _PhoneControls extends StatelessWidget {
  const _PhoneControls({required this.call, required this.chat, required this.onChat});
  final SpaceCall call;
  final bool chat;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final b = _Buttons(context, call, chat: chat, onChat: onChat, size: 50);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _Glass(
          radius: 30,
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in [b.chat, b.mute, b.video, b.deafen, b.invite, b.end]) Expanded(child: w),
          ]),
        ),
        const SizedBox(height: 10),
        // Scaled down rather than clipped on the narrowest phones.
        FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
          _GlassPill(icon: LucideMore.headphones, label: SpaceWords.devices, small: true, onPressed: call.onDevices == null ? null : () => call.onDevices!(context)),
          const SizedBox(width: 8),
          _GlassPill(icon: Lucide.settings, label: SpaceWords.settings, small: true, onPressed: call.onSettings == null ? null : () => call.onSettings!(context)),
          const SizedBox(width: 8),
          _GlassPill(icon: Lucide.chevronDown, label: SpaceWords.minimize, small: true, onPressed: call.onMinimize),
        ])),
      ]),
    );
  }
}

/// Every call button, in FaceTime's round glass, for either layout.
class _Buttons {
  _Buttons(BuildContext context, SpaceCall call, {required bool chat, required VoidCallback onChat, double size = 52})
      : chat = SpaceButton(icon: LucideMore.messageCircle, label: SpaceWords.chat, onPressed: onChat, on: chat, dark: true, size: size),
        // A locked mic can't be unmuted from here: the button rests, and the header says why.
        mute = SpaceButton(icon: SpaceWords.muteIcon(call), label: SpaceWords.mute(call), onPressed: call.micLocked && call.muted ? null : call.onMute, on: call.muted, dark: true, size: size),
        video = SpaceButton(icon: SpaceWords.videoIcon(call), label: SpaceWords.video(call), onPressed: call.videoLocked && !call.video ? null : call.onVideo, on: call.video, dark: true, size: size),
        deafen = SpaceButton(icon: call.deafened ? LucideMore.volumeX : Lucide.volume2, label: SpaceWords.deafen(call), onPressed: call.onDeafen, on: call.deafened, dark: true, size: size),
        invite = SpaceButton(icon: Lucide.share2, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => call.onInvite!(context), dark: true, size: size),
        devices = SpaceButton(icon: LucideMore.headphones, label: SpaceWords.devices, onPressed: call.onDevices == null ? null : () => call.onDevices!(context), dark: true, size: size),
        settings = SpaceButton(icon: Lucide.settings, label: SpaceWords.settings, onPressed: call.onSettings == null ? null : () => call.onSettings!(context), dark: true, size: size),
        minimize = SpaceButton(icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: call.onMinimize, dark: true, size: size),
        end = SpaceButton(icon: LucideMore.phoneOff, label: SpaceWords.leave, onPressed: call.onLeave, danger: true, dark: true, size: size);

  final Widget chat, mute, video, deafen, invite, devices, settings, minimize, end;
}

/// The chat, as a frosted sheet from the foot (phone) or a frosted panel at the side (computer), in the app's theme.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.call, required this.onClose, required this.pad, required this.side});
  final SpaceCall call;
  final VoidCallback onClose;
  final EdgeInsets pad;
  final bool side;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = side ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(26));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: t.color('glacier-bg').withValues(alpha: 0.86),
            border: side ? Border(left: BorderSide(color: t.color('app-rule'))) : Border(top: BorderSide(color: t.color('app-rule'))),
          ),
          padding: EdgeInsets.only(top: side ? pad.top + 8 : 8),
          child: Column(children: [
            if (!side)
              Container(width: 38, height: 5, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: t.color('app-ink-3').withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 10, 8),
              child: Row(children: [
                AppIcon(LucideMore.messageCircle, size: 18, wash: false, color: t.color('app-ink')),
                const SizedBox(width: 8),
                Expanded(child: Text(SpaceWords.chat, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink')))),
                GlacierPressable(
                  onPressed: onClose,
                  semanticLabel: 'Close chat',
                  builder: (context, _) => Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: t.color('app-paper-3'), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon(Lucide.x, size: 15, wash: false, color: t.color('app-ink-2')),
                  ),
                ),
              ]),
            ),
            Expanded(child: call.chat(bottom: pad.bottom)),
          ]),
        ),
      ),
    );
  }
}
