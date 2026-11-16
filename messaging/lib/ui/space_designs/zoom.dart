import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import 'space_design.dart';

/// A space's call as a Zoom meeting window (SpaceDesign.zoom): a dark meeting area with a top bar (the green
/// "Encrypted" shield, the space's name, the clock, Speaker view / Gallery view, Minimise), the people as tiles that
/// light with a bright green border round whoever talks, and a labelled toolbar along the foot ending in a red Leave.
/// On a computer Participants and Chat open as a panel at the right; on a phone they open as full-height sheets, and
/// the toolbar keeps Zoom's mobile five (Mute, Video, Participants, Chat, More).
///
/// The meeting area stays dark in both themes, as Zoom's does; the panels and sheets follow the theme.
class ZoomCall extends StatefulWidget {
  const ZoomCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<ZoomCall> createState() => _ZoomCallState();
}

enum _Panel { people, chat, more }

/// Zoom's meeting colours.
abstract final class _Z {
  static const stage = Color(0xFF0E0E10);
  static const bar = Color(0xFF1A1A1C);
  static const tile = Color(0xFF2A2A2E);
  static const videoTile = Color(0xFF1B2330);
  static const raised = Color(0xFF2E2E32);
  static const line = Color(0xFF2C2C30);
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color(0xFFC9C9CE);
  static const ink3 = Color(0xFF8E8E95);
  static const green = Color(0xFF23D959);
  static const red = Color(0xFFE5383B);
  static const blue = Color(0xFF0B5CFF);
}

// Lucide's minimize-2 (ISC licence), and a speaker-view mark drawn in Lucide's style: a filmstrip over a big tile.
const _minimize = LucideIcon('minimize-2', ['m14 10 7-7', 'M20 10h-6V4', 'm3 21 7-7', 'M4 14h6v6'], []);
const _speakerView = LucideIcon('speaker-view', [
  'M4 3H7A1 1 0 0 1 8 4V6A1 1 0 0 1 7 7H4A1 1 0 0 1 3 6V4A1 1 0 0 1 4 3Z',
  'M10.5 3H13.5A1 1 0 0 1 14.5 4V6A1 1 0 0 1 13.5 7H10.5A1 1 0 0 1 9.5 6V4A1 1 0 0 1 10.5 3Z',
  'M17 3H20A1 1 0 0 1 21 4V6A1 1 0 0 1 20 7H17A1 1 0 0 1 16 6V4A1 1 0 0 1 17 3Z',
  'M5 10H19A2 2 0 0 1 21 12V19A2 2 0 0 1 19 21H5A2 2 0 0 1 3 19V12A2 2 0 0 1 5 10Z',
], [0, 1, 2, 3]);

/// A pressable that is read out by its [semanticLabel] alone: the words drawn inside it are left out, so a button
/// is "Chat", not "Chat Chat".
class _Press extends StatelessWidget {
  const _Press({required this.onPressed, required this.builder, this.onLongPress, this.semanticLabel});
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final Widget Function(BuildContext context, PressState state) builder;

  @override
  Widget build(BuildContext context) => GlacierPressable(
        onPressed: onPressed,
        onLongPress: onLongPress,
        semanticLabel: semanticLabel,
        builder: (context, state) => ExcludeSemantics(excluding: semanticLabel != null, child: builder(context, state)),
      );
}

class _ZoomCallState extends State<ZoomCall> {
  bool? _gallery;
  _Panel? _panel;

  /// The last one to talk, so the big tile stays on them through a pause.
  String? _last;

  SpaceCall get call => widget.call;

  void _open(_Panel p) => setState(() => _panel = _panel == p ? null : p);
  void _close() => setState(() => _panel = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      final gallery = _gallery ?? (wide && call.people.length >= 3);
      final pad = MediaQuery.paddingOf(context);
      final meeting = ColoredBox(
        color: _Z.stage,
        child: Column(children: [
          _TopBar(
            call: call,
            wide: wide,
            top: pad.top,
            gallery: gallery,
            alone: call.others.isEmpty,
            onView: (g) => setState(() => _gallery = g),
          ),
          Expanded(child: _stage(context, wide: wide, gallery: gallery)),
          _Toolbar(call: call, wide: wide, bottom: pad.bottom, panel: _panel, onPanel: _open),
        ]),
      );
      if (wide) {
        final side = _panel == _Panel.people || _panel == _Panel.chat;
        return Row(children: [
          Expanded(child: meeting),
          if (side)
            SizedBox(
              width: 360,
              child: _SidePanel(call: call, chat: _panel == _Panel.chat, top: pad.top, bottom: pad.bottom, onTab: (chat) => setState(() => _panel = chat ? _Panel.chat : _Panel.people), onClose: _close),
            ),
        ]);
      }
      return Stack(children: [
        Positioned.fill(child: meeting),
        if (_panel != null) Positioned.fill(child: _Scrim(onTap: _close)),
        if (_panel == _Panel.people || _panel == _Panel.chat)
          Positioned.fill(
            top: pad.top + 12,
            child: _SidePanel(call: call, chat: _panel == _Panel.chat, sheet: true, bottom: pad.bottom, onTab: (chat) => setState(() => _panel = chat ? _Panel.chat : _Panel.people), onClose: _close),
          ),
        if (_panel == _Panel.more)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MoreSheet(
              call: call,
              bottom: pad.bottom,
              gallery: gallery,
              onView: (g) => setState(() {
                _gallery = g;
                _panel = null;
              }),
              onClose: _close,
            ),
          ),
      ]);
    });
  }

  Widget _stage(BuildContext context, {required bool wide, required bool gallery}) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: call.levels,
      builder: (context, now, _) {
        final others = call.others;
        if (others.isEmpty) return _Alone(call: call, wide: wide);
        // Zoom's active speaker: whoever is loudest now; else whoever spoke last; else someone with video.
        SpacePerson? speaker;
        var most = SpaceCall.talking;
        for (final p in others) {
          final l = now[p.id] ?? 0;
          if (!p.muted && l > most) {
            speaker = p;
            most = l;
          }
        }
        speaker ??= others.where((p) => p.id == _last).firstOrNull ?? others.where((p) => p.video).firstOrNull ?? others.first;
        _last = speaker.id;
        final pad = wide ? 16.0 : 10.0;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: gallery ? _Gallery(call: call, now: now, wide: wide) : _SpeakerView(call: call, speaker: speaker, now: now, wide: wide),
        );
      },
    );
  }
}

// The top bar ------------------------------------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.call, required this.wide, required this.top, required this.gallery, required this.alone, required this.onView});
  final SpaceCall call;
  final bool wide;
  final double top;
  final bool gallery;
  final bool alone;
  final ValueChanged<bool> onView;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = call.channel.name.isEmpty ? 'Meeting' : call.channel.name;
    final clock = call.clock(DateTime.now());
    final encrypted = Row(mainAxisSize: MainAxisSize.min, children: [
      const AppIcon(Lucide.shieldCheck, size: 14, wash: false, color: _Z.green),
      const SizedBox(width: 4),
      Text('Encrypted', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _Z.green)),
    ]);
    if (wide) {
      return Container(
        color: _Z.bar,
        padding: EdgeInsets.fromLTRB(16, top + 8, 12, 8),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Semantics(label: 'Encrypted call', child: encrypted),
              const SizedBox(width: 14),
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold', color: _Z.ink))),
              const SizedBox(width: 10),
              const AppIcon(Lucide.clock, size: 13, wash: false, color: _Z.ink3),
              const SizedBox(width: 4),
              Text(clock, style: pageText(t, t.fontSize('sm'), color: _Z.ink3)),
            ]),
          ),
          if (!alone) ...[_ViewSwitch(gallery: gallery, onView: onView), const SizedBox(width: 10)],
          _BarButton(icon: _minimize, label: SpaceWords.minimize, onPressed: call.onMinimize),
        ]),
      );
    }
    return Container(
      color: _Z.bar,
      padding: EdgeInsets.fromLTRB(8, top + 6, 10, 8),
      child: Row(children: [
        _BarButton(icon: _minimize, label: SpaceWords.minimize, onPressed: call.onMinimize, stacked: true),
        const SizedBox(width: 6),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold', color: _Z.ink)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const AppIcon(Lucide.shieldCheck, size: 13, wash: false, color: _Z.green),
              const SizedBox(width: 4),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Encrypted', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _Z.green)),
                    TextSpan(text: '  ·  $clock', style: pageText(t, t.fontSize('xs'), color: _Z.ink3)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        _LeaveButton(call: call, compact: true),
      ]),
    );
  }
}

/// Speaker view / Gallery view, as Zoom's View menu offers them: both visible, the one in use filled.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.gallery, required this.onView});
  final bool gallery;
  final ValueChanged<bool> onView;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget option(bool isGallery, LucideIcon icon, String label) {
      final on = gallery == isGallery;
      return _Press(
        onPressed: () => onView(isGallery),
        semanticLabel: label,
        builder: (context, state) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: on ? _Z.raised : (state.hovered ? const Color(0xFF242428) : null), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 15, wash: false, color: on ? _Z.ink : _Z.ink3),
            const SizedBox(width: 6),
            Text(label, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: on ? _Z.ink : _Z.ink3)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xCC151517), border: Border.all(color: _Z.line), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        option(false, _speakerView, 'Speaker view'),
        option(true, Lucide.layoutGrid, 'Gallery view'),
      ]),
    );
  }
}

/// A small icon button in the top bar, its word beside it (or under it on a phone).
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, this.onPressed, this.stacked = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = Text(label, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _Z.ink2));
    final mark = AppIcon(icon, size: stacked ? 18 : 15, wash: false, color: _Z.ink);
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: _Press(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          padding: EdgeInsets.symmetric(horizontal: stacked ? 6 : 10, vertical: stacked ? 4 : 6),
          decoration: BoxDecoration(color: state.hovered || state.pressed ? _Z.raised : null, borderRadius: BorderRadius.circular(6)),
          child: stacked
              ? Column(mainAxisSize: MainAxisSize.min, children: [mark, const SizedBox(height: 3), words])
              : Row(mainAxisSize: MainAxisSize.min, children: [mark, const SizedBox(width: 6), words]),
        ),
      ),
    );
  }
}

/// Zoom's red Leave: a rounded red button with its word.
class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.call, this.compact = false});
  final SpaceCall call;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: call.onLeave == null ? 0.4 : 1,
      child: _Press(
        onPressed: call.onLeave,
        semanticLabel: SpaceWords.leave,
        builder: (context, state) => Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: compact ? 7 : 10),
          decoration: BoxDecoration(color: state.pressed ? const Color(0xFFC42B2E) : _Z.red, borderRadius: BorderRadius.circular(compact ? 8 : 10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const AppIcon(LucideMore.phoneOff, size: 16, wash: false, color: _Z.ink),
            const SizedBox(width: 6),
            Text(SpaceWords.leave, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: _Z.ink)),
          ]),
        ),
      ),
    );
  }
}

// The people --------------------------------------------------------------------------------------------------------

/// Someone's tile: their video (or their face on a dark ground), their name bottom-left with a red mic-off when
/// muted, and Zoom's bright green border while they talk.
class _Tile extends StatelessWidget {
  const _Tile({required this.call, required this.person, required this.talking, this.small = false});
  final SpaceCall call;
  final SpacePerson person;
  final bool talking;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onPerson = call.onPerson;
    return _Press(
      onPressed: onPerson == null ? null : () => onPerson(context, person),
      onLongPress: onPerson == null ? null : () => onPerson(context, person),
      semanticLabel: '${person.shown}${person.muted ? ', muted' : ''}${talking ? ', talking' : ''}',
      builder: (context, state) => LayoutBuilder(builder: (context, box) {
        final face = (box.biggest.shortestSide * (small ? 0.46 : 0.36)).clamp(24.0, 128.0);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: person.video ? _Z.videoTile : _Z.tile, borderRadius: BorderRadius.circular(small ? 6 : 10)),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(small ? 6 : 10),
            border: talking ? Border.all(color: _Z.green, width: small ? 2.5 : 3.5) : Border.all(color: state.hovered ? const Color(0xFF45454B) : _Z.line),
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (person.video)
              SpaceVideo(call: call, person: person, faceSize: face, fallback: _VideoWaiting(call: call, person: person, face: face, small: small))
            else
              Center(child: SpaceFace(call: call, person: person, size: face)),
            Positioned(
              left: small ? 4 : 8,
              bottom: small ? 4 : 8,
              right: small ? 4 : 8,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 2 : 3),
                  decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (person.muted) ...[AppIcon(LucideMore.micOff, size: small ? 11 : 13, wash: false, color: _Z.red), SizedBox(width: small ? 3 : 4)],
                    Flexible(child: Text(person.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: _Z.ink))),
                  ]),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

/// A tile whose video is on but whose picture has not arrived: their face on a cooler ground, a camera mark in the
/// corner, so it reads as "video" rather than an empty box.
class _VideoWaiting extends StatelessWidget {
  const _VideoWaiting({required this.call, required this.person, required this.face, required this.small});
  final SpaceCall call;
  final SpacePerson person;
  final double face;
  final bool small;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF233046), Color(0xFF151C28)])),
        child: Stack(children: [
          Center(child: SpaceFace(call: call, person: person, size: face)),
          Positioned(
            top: small ? 4 : 8,
            right: small ? 4 : 8,
            child: Semantics(
              label: 'Video on',
              child: Container(
                padding: EdgeInsets.all(small ? 3 : 5),
                decoration: BoxDecoration(color: const Color(0x80000000), borderRadius: BorderRadius.circular(4)),
                child: AppIcon(Lucide.video, size: small ? 10 : 13, wash: false, color: _Z.ink),
              ),
            ),
          ),
        ]),
      );
}

/// Speaker view: the active speaker big, everyone else in a filmstrip along the top.
class _SpeakerView extends StatelessWidget {
  const _SpeakerView({required this.call, required this.speaker, required this.now, required this.wide});
  final SpaceCall call;
  final SpacePerson speaker;
  final Map<String, double> now;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final strip = [for (final p in call.people) if (p.id != speaker.id) p];
    final h = wide ? 100.0 : 76.0;
    return Column(children: [
      SizedBox(
        height: h,
        child: LayoutBuilder(builder: (context, box) {
          // As wide as 16:9 (4:3 on a phone) allows, narrower so a phone's strip fits without scrolling where it can.
          final fit = strip.isEmpty ? 0.0 : box.maxWidth / strip.length - 6;
          final w = (h * (wide ? 16 / 9 : 4 / 3)).clamp(0.0, fit < h ? h : fit);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final p in strip)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: SizedBox(width: w, height: h, child: _Tile(call: call, person: p, talking: call.isTalking(p, now), small: true)),
                  ),
              ]),
            ),
          );
        }),
      ),
      SizedBox(height: wide ? 14 : 10),
      Expanded(
        child: wide
            ? Center(child: AspectRatio(aspectRatio: 16 / 9, child: _Tile(call: call, person: speaker, talking: call.isTalking(speaker, now))))
            : _Tile(call: call, person: speaker, talking: call.isTalking(speaker, now)),
      ),
    ]);
  }
}

/// Gallery view: everyone in an even grid, the tiles as big as fit (16:9 on a computer, filling the screen on a phone).
class _Gallery extends StatelessWidget {
  const _Gallery({required this.call, required this.now, required this.wide});
  final SpaceCall call;
  final Map<String, double> now;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final people = call.people;
    const gap = 8.0;
    return LayoutBuilder(builder: (context, box) {
      final n = people.length;
      var cols = 1;
      var tw = 0.0, th = 0.0;
      if (wide) {
        var best = 0.0;
        for (var c = 1; c <= n; c++) {
          final r = (n / c).ceil();
          var w = (box.maxWidth - gap * (c - 1)) / c;
          var h = (box.maxHeight - gap * (r - 1)) / r;
          if (w / h > 16 / 9) {
            w = h * 16 / 9;
          } else {
            h = w * 9 / 16;
          }
          if (w * h > best) {
            best = w * h;
            cols = c;
            tw = w;
            th = h;
          }
        }
      } else {
        cols = n <= 2 ? 1 : 2;
        final r = (n / cols).ceil();
        tw = (box.maxWidth - gap * (cols - 1)) / cols;
        th = ((box.maxHeight - gap * (r - 1)) / r).clamp(0.0, tw * 1.25);
      }
      final rows = <List<SpacePerson>>[for (var i = 0; i < n; i += cols) people.sublist(i, (i + cols).clamp(0, n))];
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
          for (final row in rows)
            Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
              for (final p in row) SizedBox(width: tw, height: th, child: _Tile(call: call, person: p, talking: call.isTalking(p, now))),
            ]),
        ]),
      );
    });
  }
}

/// Alone in the call: Zoom's waiting card, with your own face rippling as you talk, and Invite.
class _Alone extends StatelessWidget {
  const _Alone({required this.call, required this.wide});
  final SpaceCall call;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = call.channel.name.isEmpty ? 'this space' : call.channel.name;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
          decoration: BoxDecoration(color: _Z.tile, border: Border.all(color: _Z.line), borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Room for the ripples round the face.
            Padding(padding: const EdgeInsets.all(22), child: SpaceFace(call: call, person: call.me, size: wide ? 104 : 92)),
            const SizedBox(height: 10),
            ValueListenableBuilder<Map<String, double>>(
              valueListenable: call.levels,
              builder: (context, now, _) {
                final talking = call.isTalking(call.me, now);
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(call.muted ? LucideMore.micOff : Lucide.mic, size: 13, wash: false, color: call.muted ? _Z.red : (talking ? _Z.green : _Z.ink3)),
                  const SizedBox(width: 5),
                  Text(call.muted ? 'You are muted' : (talking ? 'Your mic is picking you up' : 'Your mic is on'), style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: call.muted ? _Z.red : (talking ? _Z.green : _Z.ink3))),
                ]);
              },
            ),
            const SizedBox(height: 18),
            Text("You're the only one here", textAlign: TextAlign.center, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: _Z.ink)),
            const SizedBox(height: 6),
            Text('Invite people to join $name.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: _Z.ink2)),
            const SizedBox(height: 22),
            Opacity(
              opacity: call.onInvite == null ? 0.4 : 1,
              child: _Press(
                onPressed: call.onInvite == null ? null : () => call.onInvite!(context),
                semanticLabel: SpaceWords.invite,
                builder: (context, state) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(color: state.pressed ? const Color(0xFF0848CC) : _Z.blue, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon(Lucide.userPlus, size: 16, wash: false, color: _Z.ink),
                    const SizedBox(width: 8),
                    Text(SpaceWords.invite, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: _Z.ink)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// The toolbar -------------------------------------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.call, required this.wide, required this.bottom, required this.panel, required this.onPanel});
  final SpaceCall call;
  final bool wide;
  final double bottom;
  final _Panel? panel;
  final ValueChanged<_Panel> onPanel;

  @override
  Widget build(BuildContext context) {
    final devices = call.onDevices == null ? null : () => call.onDevices!(context);
    // Muted for everyone, or a role that may not speak: Unmute can't be pressed, and says why.
    final muteLocked = call.micLocked && call.muted;
    final videoLocked = call.videoLocked && !call.video;
    final mute = _ToolButton(
      icon: muteLocked ? Lucide.lock : SpaceWords.muteIcon(call),
      label: SpaceWords.mute(call),
      semanticLabel: muteLocked ? 'Unmute, not allowed here' : null,
      alert: call.muted,
      onPressed: muteLocked ? null : call.onMute,
      // On a phone the devices are under More.
      onChevron: wide ? devices : null,
    );
    final video = _ToolButton(
      icon: videoLocked ? Lucide.lock : SpaceWords.videoIcon(call),
      label: SpaceWords.video(call),
      semanticLabel: videoLocked ? 'Video, not allowed here' : null,
      alert: !call.video,
      onPressed: videoLocked ? null : call.onVideo,
      onChevron: wide ? devices : null,
    );
    final people = _ToolButton(icon: Lucide.users, label: 'Participants', count: call.people.length, on: panel == _Panel.people, onPressed: () => onPanel(_Panel.people));
    final chat = _ToolButton(icon: LucideMore.messageCircle, label: SpaceWords.chat, on: panel == _Panel.chat, onPressed: () => onPanel(_Panel.chat));
    if (!wide) {
      return Container(
        decoration: const BoxDecoration(color: _Z.bar, border: Border(top: BorderSide(color: _Z.line))),
        padding: EdgeInsets.fromLTRB(4, 6, 4, bottom + 6),
        child: Row(children: [
          Expanded(child: Center(child: mute)),
          Expanded(child: Center(child: video)),
          Expanded(child: Center(child: people)),
          Expanded(child: Center(child: chat)),
          Expanded(child: Center(child: _ToolButton(icon: Lucide.ellipsis, label: 'More', on: panel == _Panel.more, onPressed: () => onPanel(_Panel.more)))),
        ]),
      );
    }
    return Container(
      decoration: const BoxDecoration(color: _Z.bar, border: Border(top: BorderSide(color: _Z.line))),
      padding: EdgeInsets.fromLTRB(12, 8, 16, bottom + 8),
      child: Row(children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [mute, video]))),
        Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          people,
          chat,
          _ToolButton(icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => call.onInvite!(context)),
          _ToolButton(icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), alert: call.deafened, onPressed: call.onDeafen),
          _ToolButton(icon: Lucide.settings, label: SpaceWords.settings, onPressed: call.onSettings == null ? null : () => call.onSettings!(context)),
        ]),
        Expanded(child: Align(alignment: Alignment.centerRight, child: _LeaveButton(call: call))),
      ]),
    );
  }
}

/// A toolbar button as Zoom draws them: a light icon with its word under it, a red icon for a mic or camera that is
/// off, a count by Participants, and a small ^ beside the icon that opens the devices.
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, this.onPressed, this.onChevron, this.semanticLabel, this.alert = false, this.on = false, this.count});
  final LucideIcon icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onChevron;
  final bool alert;
  final bool on;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final main = _Press(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      builder: (context, state) => Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Container(
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: on ? _Z.raised : (state.hovered || state.pressed ? const Color(0xFF26262A) : null), borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 24,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(icon, size: 22, wash: false, color: alert ? _Z.red : _Z.ink),
                if (count != null) ...[
                  const SizedBox(width: 3),
                  Text('$count', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: _Z.ink)),
                ],
              ]),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: on ? _Z.ink : _Z.ink2)),
          ]),
        ),
      ),
    );
    final chevron = onChevron;
    if (chevron == null) return main;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      main,
      _Press(
        onPressed: chevron,
        semanticLabel: SpaceWords.devices,
        builder: (context, state) => Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(color: state.hovered || state.pressed ? const Color(0xFF2E2E33) : null, borderRadius: BorderRadius.circular(4)),
          child: const AppIcon(Lucide.chevronUp, size: 13, wash: false, color: _Z.ink2),
        ),
      ),
    ]);
  }
}

// Panels and sheets (these follow the app's theme) -----------------------------------------------------------------

class _Scrim extends StatelessWidget {
  const _Scrim({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: const ColoredBox(color: Color(0x8C000000)));
}

/// Participants and Chat: a panel at the right on a computer, a full-height sheet on a phone. Two tabs at the top, as
/// Zoom's side panel can hold both.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.call, required this.chat, required this.onTab, required this.onClose, this.sheet = false, this.top = 0, this.bottom = 0});
  final SpaceCall call;
  final bool chat;
  final bool sheet;
  final double top;
  final double bottom;
  final ValueChanged<bool> onTab;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget tab(bool isChat, LucideIcon icon, String label) {
      final on = chat == isChat;
      return Expanded(
        child: _Press(
          onPressed: () => onTab(isChat),
          semanticLabel: label,
          builder: (context, state) => Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: on ? t.color('app-paper') : null, borderRadius: BorderRadius.circular(7)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              AppIcon(icon, size: 15, wash: false, color: on ? t.color('app-ink') : t.color('app-ink-3')),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: on ? t.color('app-ink') : t.color('app-ink-3')))),
            ]),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: sheet ? null : Border(left: BorderSide(color: t.color('app-rule'))),
        borderRadius: sheet ? const BorderRadius.vertical(top: Radius.circular(16)) : null,
      ),
      clipBehavior: sheet ? Clip.antiAlias : Clip.hardEdge,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, top + 10, 8, 8),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(9)),
                child: Row(children: [
                  tab(false, Lucide.users, 'Participants (${call.people.length})'),
                  tab(true, LucideMore.messageCircle, SpaceWords.chat),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            _Press(
              onPressed: onClose,
              semanticLabel: 'Close',
              builder: (context, state) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: state.hovered || state.pressed ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(8)),
                child: AppIcon(Lucide.x, size: 18, wash: false, color: t.color('app-ink-2')),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: t.color('app-rule')),
        Expanded(child: chat ? call.chat(bottom: bottom) : _People(call: call, bottom: bottom)),
      ]),
    );
  }
}

/// The participants list: face, name, role tag, mic and camera; pressing someone opens them.
class _People extends StatelessWidget {
  const _People({required this.call, required this.bottom});
  final SpaceCall call;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final roster = call.room?.roster;
    final red = t.colorOf('#dd3a30');
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text('In the meeting (${call.people.length})', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
          ),
          for (final p in call.people)
            _Press(
              onPressed: call.onPerson == null ? null : () => call.onPerson!(context, p),
              onLongPress: call.onPerson == null ? null : () => call.onPerson!(context, p),
              semanticLabel: 'Participant ${p.shown}',
              builder: (context, state) {
                final role = p.roleLabel(roster);
                return Container(
                  color: state.hovered || state.pressed ? t.color('app-paper-2') : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    SpaceFace(call: call, person: p, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(children: [
                        Flexible(child: Text(p.me ? '${p.name} (You)' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink')))),
                        if (role != null || p.guest) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(4)),
                            child: Text(role ?? 'Guest', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-2'))),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Semantics(label: p.muted ? 'Muted' : 'Mic on', child: AppIcon(p.muted ? LucideMore.micOff : Lucide.mic, size: 16, wash: false, color: p.muted ? red : t.color('app-ink-2'))),
                    const SizedBox(width: 10),
                    Semantics(label: p.video ? 'Video on' : 'Video off', child: AppIcon(p.video ? Lucide.video : LucideMore.videoOff, size: 16, wash: false, color: p.video ? t.color('app-ink-2') : red)),
                  ]),
                );
              },
            ),
        ]),
      ),
      Container(height: 1, color: t.color('app-rule')),
      Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, bottom + 10),
        child: Row(children: [
          Expanded(child: _PanelAction(icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => call.onInvite!(context))),
          const SizedBox(width: 8),
          Expanded(child: _PanelAction(icon: SpaceWords.muteIcon(call), label: call.muted ? 'Unmute me' : 'Mute me', onPressed: call.micLocked && call.muted ? null : call.onMute)),
        ]),
      ),
    ]);
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.icon, required this.label, this.onPressed});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: _Press(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: state.pressed ? t.color('app-paper-3') : t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AppIcon(icon, size: 15, wash: false, color: t.color('app-ink')),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink')))),
          ]),
        ),
      ),
    );
  }
}

/// A phone's More: the rest of the toolbar as Zoom's action sheet (the view, Deafen, Invite, Devices, Settings).
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.call, required this.bottom, required this.gallery, required this.onView, required this.onClose});
  final SpaceCall call;
  final double bottom;
  final bool gallery;
  final ValueChanged<bool> onView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget row(LucideIcon icon, String label, VoidCallback? onPressed, {bool alert = false}) => Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: _Press(
            onPressed: onPressed,
            semanticLabel: label,
            builder: (context, state) => Container(
              color: state.pressed ? t.color('app-paper-2') : null,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              child: Row(children: [
                AppIcon(icon, size: 20, wash: false, color: alert ? t.colorOf('#dd3a30') : t.color('app-ink')),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: pageText(t, t.fontSize('md'), color: t.color('app-ink')))),
              ]),
            ),
          ),
        );
    // Closes the sheet, then does what the row says.
    VoidCallback? then(void Function(BuildContext)? f) => f == null
        ? null
        : () {
            onClose();
            f(context);
          };
    return Container(
      decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
      padding: EdgeInsets.only(top: 8, bottom: bottom + 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: t.color('app-rule'), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('More', style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink')))),
        ),
        if (call.others.isNotEmpty) row(gallery ? _speakerView : Lucide.layoutGrid, gallery ? 'Switch to Speaker view' : 'Switch to Gallery view', () => onView(!gallery)),
        row(SpaceWords.deafenIcon(call), SpaceWords.deafen(call), call.onDeafen == null
            ? null
            : () {
                onClose();
                call.onDeafen!();
              }, alert: call.deafened),
        row(Lucide.userPlus, SpaceWords.invite, then(call.onInvite)),
        row(LucideMore.headphones, SpaceWords.devices, then(call.onDevices)),
        row(Lucide.settings, SpaceWords.settings, then(call.onSettings)),
        Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: t.color('app-rule')),
        row(Lucide.x, 'Cancel', onClose),
      ]),
    );
  }
}
