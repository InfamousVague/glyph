import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app_state.dart';
import '../split_handle.dart';
import '../window_chrome.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../../voice/roles.dart';
import '../hangout_screen.dart' show roleInk;
import '../ripple_avatar.dart';
import '../tile_grid.dart';
import 'space_design.dart';

/// A space's call laid out as Telegram's group voice chat (SpaceDesign.telegram, the app's default call screen):
/// headed by the space's name and how many are in voice, video tiles two across above a list of people, and at the foot
/// one big microphone button with two round buttons either side of it. Drawn in Ghost Messaging's own look, light or dark as the app is (Matt,
/// 2026-11-16: "Change the telegram one to be our colors without the gradients and our voice effects make the chat
/// window 33% of the screen"): flat paper and ink, hairlines, and the app's wobbly green ripples (RippleAvatar) round
/// whoever talks and round the microphone while you are live. No gradients anywhere. Made the app's own in its words
/// too (Matt, 2026-11-16: "make it ours and less like telegram"): talking, listening, muted; Mic on and Muted; the
/// app's RoleTag; no sheet grabber; corners and gaps from the app's tokens.
///
/// On a phone the chat opens as a second sheet over the voice chat; on a computer it is docked beside it, a third of
/// the window wide, open from the start.
class TelegramCall extends StatefulWidget {
  const TelegramCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<TelegramCall> createState() => _TelegramCallState();
}

/// The app's talking green and its red (as lib/ui/voice_screen.dart and lib/ui/ripple_avatar.dart use them).
Color _green(Tokens t) => t.colorOf('#2fb35a');
Color _red(Tokens t) => t.colorOf('#dd3a30');

class _TelegramCallState extends State<TelegramCall> {
  /// The chat beside or over the call; null until pressed, when a computer shows it and a phone does not.
  bool? _chat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final call = widget.call;
    final media = MediaQuery.of(context);
    return SizedBox.expand(
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760 && box.maxHeight >= 480;
          final chat = _chat ?? wide;
          void toggleChat() => setState(() => _chat = !chat);
          if (wide) return _computer(context, call, box, media, chat, toggleChat);
          return _phone(context, call, media, chat, toggleChat);
        }),
      ),
    );
  }

  /// The voice chat as a sheet with rounded top corners; open, the chat is a second sheet over it, behind a dimmed
  /// layer that closes it when tapped.
  Widget _phone(BuildContext context, SpaceCall call, MediaQueryData media, bool chat, VoidCallback toggleChat) {
    final t = context.tokens;
    final pad = media.padding;
    final top = BorderRadius.vertical(top: Radius.circular(t.radius('xl')));
    // Typing, the message bar stands just above the keyboard (Matt, 2026-11-16: "the chatbar doesn't move up when in
    // the chat section of a space"). The chat adds the screen's own foot to what it is given, so the keyboard's height
    // less that foot puts the bar on the keyboard; without a keyboard, room for the foot as before.
    final keyboard = media.viewInsets.bottom;
    final chatBottom = keyboard > 0 ? math.max(1.0, keyboard - pad.bottom) : pad.bottom;
    return ColoredBox(
      color: t.color('app-paper-2'),
      child: Stack(children: [
        Positioned.fill(
          top: pad.top + t.space(2),
          child: Container(
            decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: top, border: Border(top: BorderSide(color: t.color('app-rule')))),
            child: _VoicePanel(call: call, chatOpen: chat, onChat: toggleChat, bottom: pad.bottom),
          ),
        ),
        if (chat) ...[
          Positioned.fill(
            child: GestureDetector(onTap: toggleChat, child: const ColoredBox(color: Color(0x66000000))),
          ),
          Positioned.fill(
            top: pad.top + t.space(2) + 58 + t.space(1),
            child: ClipRRect(
              borderRadius: top,
              child: _ChatPanel(call: call, onClose: toggleChat, bottom: chatBottom),
            ),
          ),
        ],
      ]),
    );
  }

  /// The voice chat and, open, the chat docked to its right: the chat a third of the window, the voice chat the rest.
  Widget _computer(BuildContext context, SpaceCall call, BoxConstraints box, MediaQueryData media, bool chat, VoidCallback toggleChat) {
    final t = context.tokens;
    // A third of the window, or as dragged (lib/ui/split_handle.dart): from 280 to what leaves the voice chat 380.
    _chatWidth ??= PaneWidth.of(AppState.of(context), 'call_chat');
    double fit(double w) => w.clamp(280.0, (box.maxWidth - 380).clamp(280.0, double.infinity));
    final side = chat ? fit(_chatWidth ?? box.maxWidth / 3) : 0.0;
    final voice = box.maxWidth - side;
    final grip = SplitHandle.widthOf(context);
    return Stack(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        key: const ValueKey('tg-voice-panel'),
        width: voice,
        child: Padding(
          padding: EdgeInsets.only(top: media.padding.top),
          child: _VoicePanel(call: call, chatOpen: chat, onChat: toggleChat, bottom: media.padding.bottom, compact: true, maxWidth: 620),
        ),
      ),
      if (chat)
        Container(
          key: const ValueKey('tg-chat-panel'),
          width: side,
          padding: EdgeInsets.only(top: media.padding.top),
          decoration: BoxDecoration(
            color: t.color('glacier-bg'),
            border: Border(left: BorderSide(color: t.color('app-rule'))),
          ),
          child: _ChatPanel(call: call, onClose: toggleChat, bottom: media.padding.bottom),
        ),
      ]),
      if (chat)
        Positioned(
          key: const ValueKey('tg-chat-split'),
          left: voice - grip / 2,
          top: 0,
          bottom: 0,
          width: grip,
          child: SplitHandle(
            label: 'Resize the chat',
            onDrag: (dx) => setState(() => _chatWidth = fit(fit(_chatWidth ?? side) - dx)),
            onDone: () => PaneWidth.keep(AppState.of(context), 'call_chat', _chatWidth),
            onReset: () {
              setState(() => _chatWidth = null);
              PaneWidth.keep(AppState.of(context), 'call_chat', null);
            },
          ),
        ),
    ]);
  }

  /// The chat's width as dragged, kept between calls (PaneWidth 'call_chat'); null for a third of the window.
  double? _chatWidth;
}

/// The voice chat itself: header, the people, the buttons. Holds the header's menu.
class _VoicePanel extends StatefulWidget {
  const _VoicePanel({required this.call, required this.chatOpen, required this.onChat, required this.bottom, this.compact = false, this.maxWidth});
  final SpaceCall call;
  final bool chatOpen;
  final VoidCallback onChat;
  final double bottom;

  /// Rows a little tighter, as on a computer.
  final bool compact;

  /// The people and the buttons no wider than this, centred (a computer's wide panel); the header spans it all.
  final double? maxWidth;

  @override
  State<_VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<_VoicePanel> {
  bool _menu = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    Widget narrow(Widget child) => widget.maxWidth == null ? child : Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth!), child: child));
    return Stack(children: [
      Column(children: [
        _Header(call: call, onMenu: () => setState(() => _menu = !_menu), menuOpen: _menu),
        Expanded(child: narrow(_People(call: call, compact: widget.compact))),
        narrow(_Controls(call: call, chatOpen: widget.chatOpen, onChat: widget.onChat, bottom: widget.bottom)),
      ]),
      if (_menu) ...[
        Positioned.fill(child: GestureDetector(onTap: () => setState(() => _menu = false), child: const ColoredBox(color: Color(0x00000000)))),
        Positioned(
          top: 58,
          right: context.tokens.space(3),
          child: _Menu(call: call, close: () => setState(() => _menu = false)),
        ),
      ],
    ]);
  }
}

/// The space's name and how many are in voice ("Just you" alone); Minimise on the left, the menu on the right.
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
    // On the Mac this page covers the window, so its header is the top bar: dragged to move the window, and clear of
    // the three buttons at its left (lib/ui/window_chrome.dart).
    return WindowDragArea(
      child: SizedBox(
      height: 58,
      child: Row(children: [
        SizedBox(width: (MacChrome.enabled ? MacChrome.lightsRoom - t.space(3) : 0) + t.space(3)),
        // A back arrow, as every page's way back is (Matt, 2026-11-17: "make the down chevron a back arrow as well"): it still
        // puts the call away to its banner.
        _IconButton(icon: Lucide.arrowLeft, label: 'Back', onPressed: call.onMinimize),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
            const SizedBox(height: 1),
            Text(n <= 1 ? 'Just you' : '$n in voice', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            // Bridged to Discord: its sound and chat pass through the bridge, so say what that costs.
            if (call.bridged) Text('Bridged to Discord · not end-to-end encrypted', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
          ]),
        ),
        _IconButton(icon: Lucide.ellipsisVertical, label: _menuLabel, onPressed: onMenu, on: menuOpen),
        SizedBox(width: t.space(3)),
      ]),
      ),
    );
  }
}

/// The header menu's words for a screen reader: what it holds.
final _menuLabel = 'More: ${[SpaceWords.invite, SpaceWords.devices, SpaceWords.settings, SpaceWords.leave].join(', ').toLowerCase()}';

/// A round icon in a header, its words for a screen reader.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.label, required this.onPressed, this.on = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.color(on || state.hovered || state.pressed ? 'app-paper-3' : 'app-paper-2')),
          alignment: Alignment.center,
          child: AppIcon(icon, size: 20, wash: false, color: t.color('app-ink')),
        ),
      ),
    );
  }
}

/// The header's menu: invite, devices, the space's settings, leave.
class _Menu extends StatelessWidget {
  const _Menu({required this.call, required this.close});
  final SpaceCall call;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    void Function()? run(void Function(BuildContext)? action) => action == null
        ? null
        : () {
            close();
            action(context);
          };
    return Container(
      width: 270,
      padding: EdgeInsets.symmetric(vertical: t.space(1)),
      decoration: BoxDecoration(
        color: t.color('app-paper'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule')),
        boxShadow: t.shadowOf('0 8px 28px rgba(0,0,0,0.22)'),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _MenuRow(icon: Lucide.userPlus, label: SpaceWords.invite, hint: 'Friends, a text or the link', onPressed: run(call.onInvite)),
        _MenuRow(icon: LucideMore.headphones, label: SpaceWords.devices, hint: 'Microphone, camera and speaker', onPressed: run(call.onDevices)),
        _MenuRow(icon: Lucide.settings, label: SpaceWords.settings, hint: 'Roles and permissions', onPressed: run(call.onSettings)),
        // What the plugins that are on in this call offer (Slots.callControls).
        for (final x in call.extras) _MenuRow(icon: x.icon, label: x.label, hint: x.builtIn ? 'A screen or a window, to everyone here' : 'A plugin', danger: x.danger, onPressed: run(x.run)),
        Container(height: 1, margin: EdgeInsets.symmetric(vertical: t.space(1)), color: t.color('app-rule')),
        _MenuRow(
          icon: LucideMore.phoneOff,
          label: SpaceWords.leave,
          hint: 'Leave voice',
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

/// A line of the menu: an icon, a name and a quieter hint under it.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.hint, required this.onPressed, this.danger = false});
  final LucideIcon icon;
  final String label, hint;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = danger ? _red(t) : t.color('app-ink');
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          color: state.hovered || state.pressed ? t.color('app-paper-2') : null,
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
          child: Row(children: [
            AppIcon(icon, size: 20, wash: false, color: danger ? _red(t) : t.color('app-ink-2')),
            SizedBox(width: t.space(4)),
            Expanded(
              child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
                Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
              ])),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Video tiles two across, "Invite to space", then everyone in a list.
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
    // A face of 38 whose ripples reach 1.85 times its radius (about 35 px) needs rows of about 70 for its rings to
    // stay inside its own row: 16 above and below (14 where the panel is docked and short).
    final rowPad = compact ? 14.0 : 16.0;
    return LayoutBuilder(builder: (context, box) {
      // The video gives way to the list: its tiles shrink (to no less than 84 a row) so everyone in the call fits
      // under them where the panel is short.
      // The invite row, the rows, and the list's padding and gap under the video (the app's spacing, which grows a
      // little on a wide window).
      final list = 48 + call.people.length * (_faceSize + rowPad * 2 + 1) + t.space(1) + t.space(3) * 2 + 2;
      final room = box.maxHeight - list;
      return ListView(
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(1), t.space(3), t.space(3)),
        children: [
          if (videos.isNotEmpty) ...[
            _VideoGrid(call: call, people: videos, room: room),
            SizedBox(height: t.space(3)),
          ],
          Container(
            decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('xl')), border: Border.all(color: t.color('app-rule'))),
            // Not clipped: a speaker's outermost ring may lean a pixel or two past the card rather than be cut flat.
            // The rows round their own hover at the card's corners instead.
            child: Column(children: [
              _InviteRow(onPressed: call.onInvite == null ? null : () => call.onInvite!(context)),
              for (final p in call.people) ...[
                Container(height: 1, margin: const EdgeInsets.only(left: _textStart), color: t.color('app-rule')),
                _PersonRow(call: call, person: p, role: p.roleLabel(roster), pad: rowPad, last: identical(p, call.people.last)),
              ],
            ]),
          ),
          if (alone) ...[
            SizedBox(height: t.space(10)),
            Column(children: [
              // You, large, your voice moving the ripples round you while you wait.
              SpaceFace(key: const ValueKey('tg-alone-me'), call: call, person: call.me, size: 88),
              SizedBox(height: t.space(10)),
              Text('Waiting for others to join', textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
              SizedBox(height: t.space(1)),
              Text('Invite people, and they\'ll show up here as they join.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
            ]),
          ],
        ],
      );
    });
  }
}

/// The first row of the list of people, in the accent colour: "Invite to space".
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-accent');
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: _inviteWords,
        builder: (context, state) => Container(
          decoration: BoxDecoration(
            color: state.hovered || state.pressed ? t.color('app-paper-3') : null,
            borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius('xl') - 1)),
          ),
          padding: const EdgeInsets.fromLTRB(_rowLeft, 12, 14, 12),
          child: Row(children: [
            SizedBox(width: _faceSize, child: Center(child: AppIcon(Lucide.link, size: 22, wash: false, color: ink))),
            const SizedBox(width: _faceGap),
            Expanded(child: ExcludeSemantics(child: Text(_inviteWords, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)))),
          ]),
        ),
      ),
    );
  }
}

const _inviteWords = 'Invite to space';

/// The list's face, its left inset and the gap to the name: the rings (to 1.85 × 19 ≈ 35 px from the face's middle)
/// end at 72, short of the name at [_textStart].
const double _faceSize = 38;
const double _rowLeft = 18;
const double _faceGap = 18;
const double _textStart = _rowLeft + _faceSize + _faceGap;

/// What someone is doing now, in the list's words and colour: green talking, red muted, quiet ink listening.
({String words, Color color, LucideIcon icon}) _status(Tokens t, SpaceCall call, SpacePerson p, Map<String, double> now) {
  if (p.muted) return (words: p.me && call.micLocked ? 'muted by a moderator' : 'muted', color: _red(t), icon: LucideMore.micOff);
  if (call.isTalking(p, now)) return (words: 'talking', color: _green(t), icon: Lucide.mic);
  return (words: 'listening', color: t.color('app-ink-3'), icon: Lucide.mic);
}

/// One person in the list: the face with its talking rings, the name, and what they are doing now ([_status]).
/// Pressing or holding the row opens what can be done with them.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.call, required this.person, required this.role, this.pad = 16, this.last = false});
  final SpaceCall call;
  final SpacePerson person;

  /// The role worth showing beside them (SpacePerson.roleLabel), shown as the app's RoleTag; null for none.
  final String? role;
  final double pad;
  final bool last;

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
          final s = _status(t, call, p, now);
          final level = p.muted ? 0.0 : (now[p.id] ?? 0);
          return Container(
            decoration: BoxDecoration(
              color: state.hovered || state.pressed ? t.color('app-paper-3') : null,
              borderRadius: last ? BorderRadius.vertical(bottom: Radius.circular(t.radius('xl') - 1)) : null,
            ),
            padding: EdgeInsets.fromLTRB(_rowLeft, pad, 14, pad),
            child: Row(children: [
              ExcludeSemantics(child: SpaceFace(key: ValueKey('tg-face-${p.id}'), call: call, person: p, size: _faceSize)),
              const SizedBox(width: _faceGap),
              Expanded(
                child: ExcludeSemantics(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    // Their role's colour, and the owner's crown, instead of a tag (Matt, 2026-11-17).
                    Flexible(child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: (role != null ? roleInk(t, p.role ?? _ownerRole) : null) ?? t.color('app-ink')))),
                    // A guest as the app's call list shows one: the word, quiet, after the name.
                    if (p.guest) ...[SizedBox(width: t.space(2)), Text('guest', maxLines: 1, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))],
                    if (p.tag != null) ...[SizedBox(width: t.space(2)), Text(p.tag!, maxLines: 1, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))],
                  ]),
                  const SizedBox(height: 2),
                  Text(s.words, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: s.words == 'listening' ? 'regular' : 'semibold', color: s.color)),
                ])),
              ),
              const SizedBox(width: 8),
              if (p.video) Padding(padding: const EdgeInsets.only(right: 10), child: AppIcon(Lucide.video, size: 18, wash: false, color: t.color('app-ink-3'))),
              _MicMark(icon: s.icon, color: s.color, level: level),
            ]),
          );
        },
      ),
    );
  }
}

/// RoleTag wants a role; an owner with none known reads as Owner all the same (RoleTag shows "Owner" for an owner).
final _ownerRole = Role.defaults.first;

/// The row's microphone, swelling a little with the voice.
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

/// Everyone with video on, two across, each tile 4:3 (one alone as wide as the panel; the last of an odd number centred
/// under the rest at their size).
class _VideoGrid extends StatelessWidget {
  const _VideoGrid({required this.call, required this.people, required this.room});
  final SpaceCall call;
  final List<SpacePerson> people;

  /// The height the list leaves for the grid; its rows shrink to fit it, to no less than 84 each.
  final double room;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final gap = context.tokens.space(2);
      final half = (box.maxWidth - gap) / 2;
      final rows = (people.length + 1) ~/ 2;
      final fit = math.max(84.0, (room - gap * (rows - 1)) / rows);
      // 4:3, narrower where the list needs the height.
      final h = math.min((people.length == 1 ? box.maxWidth : half) / tileAspect, fit);
      return Column(spacing: gap, children: [
        for (var r = 0; r < rows; r++)
          Row(mainAxisAlignment: MainAxisAlignment.center, spacing: gap, children: [
            for (final p in people.skip(r * 2).take(2)) SizedBox(width: h * tileAspect, height: h, child: _VideoTile(call: call, person: p)),
          ]),
      ]);
    });
  }
}

/// Someone whose camera is on, as a rounded tile: their picture (the face until it comes), edged green while they
/// talk.
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
          final s = _status(t, call, p, now);
          return Container(
            decoration: BoxDecoration(
              color: t.color('app-paper-2'),
              borderRadius: BorderRadius.circular(t.radius('xl')),
              border: Border.all(color: talking ? _green(t) : t.color('app-rule'), width: talking ? 2.5 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(t.radius('xl') - (talking ? 2.5 : 1)),
              child: Stack(fit: StackFit.expand, children: [
                SpaceVideo(
                  call: call,
                  person: p,
                  // The face in the middle of the part above the name chip (the chip's top is 28 from the foot), sized
                  // so its ripples, which reach 1.85 times its radius, stay above the chip too.
                  fallback: LayoutBuilder(builder: (context, box) {
                    final above = math.max(0.0, box.maxHeight - 30);
                    return Stack(children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: above,
                        child: Center(child: ExcludeSemantics(child: SpaceFace(key: ValueKey('tg-tile-${p.id}'), call: call, person: p, size: math.min(56.0, above / 1.85)))),
                      ),
                    ]);
                  }),
                ),
                // The name on a flat chip of the page's paper, readable over a picture too.
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Row(children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                        decoration: BoxDecoration(color: t.color('glacier-bg').withValues(alpha: 0.9), borderRadius: BorderRadius.circular(t.radius('full'))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          AppIcon(s.icon, size: 14, wash: false, color: s.words == 'listening' ? t.color('app-ink-2') : s.color),
                          const SizedBox(width: 4),
                          Flexible(child: ExcludeSemantics(child: Text(p.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink'))))),
                        ]),
                      ),
                    ),
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
    // No rule above the controls: it stopped short of the page's edges (Matt, 2026-11-17: "the border at the bottom for the
    // controls should span the full width of the page or remove the border completely").
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom + 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        side(_RoundButton(
          icon: SpaceWords.videoIcon(call),
          label: SpaceWords.video(call),
          on: call.video,
          onPressed: call.videoLocked ? null : call.onVideo,
        )),
        side(_RoundButton(icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), on: call.deafened, onPressed: call.onDeafen)),
        SizedBox(width: 104, child: _MicButton(call: call)),
        side(_RoundButton(icon: LucideMore.messageCircle, label: SpaceWords.chat, on: chatOpen, onPressed: onChat)),
        side(_RoundButton(icon: Lucide.x, label: SpaceWords.leave, danger: true, onPressed: call.onLeave)),
      ]),
    );
  }
}

/// One of the four round buttons round the microphone: a flat circle, its words under it. On, it is filled with the
/// ink; Leave is the app's red.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onPressed, this.on = false, this.danger = false});
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on, danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) {
          final ground = danger ? _red(t) : (on ? t.color('app-accent') : t.color(state.hovered || state.pressed ? 'app-paper-3' : 'app-paper-2'));
          final mark = danger ? const Color(0xFFFFFFFF) : (on ? t.color('app-paper') : t.color('app-ink'));
          return Padding(
            // Level with the middle of the microphone button.
            padding: const EdgeInsets.only(top: (_MicButton.box - 50) / 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedScale(
                scale: state.pressed ? 0.94 : 1,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ground, border: on || danger ? null : Border.all(color: t.color('app-rule'))),
                  alignment: Alignment.center,
                  child: AppIcon(icon, size: 22, wash: false, color: mark),
                ),
              ),
              const SizedBox(height: 6),
              ExcludeSemantics(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-2')))),
            ]),
          );
        },
      ),
    );
  }
}

/// The big microphone: a flat circle, green while you are live with the app's wobbly ripples going out from it as you
/// talk (RippleAvatar's rings, driven by levels['me']); quiet paper while muted; a lock when a moderator has muted
/// you; and what it means under it.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.call});
  final SpaceCall call;

  /// Only a little bigger than the buttons beside it (50) (Matt, 2026-11-16: "make the mic on button only slightly
  /// bigger than the other icons").
  static const size = 60.0;

  /// The ripples are drawn round a hidden face of this size, so that the rings, which run from its edge out to 1.85
  /// times its radius (40 px), show as a band round the 60 px button and stay inside its 88 px box.
  static const ringFace = 43.0;

  /// The box the button and its rings stand in; the buttons beside it are centred on it ([_RoundButton]).
  static const box = 88.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locked = call.micLocked;
    final live = !call.muted && !call.deafened && !locked;
    // Deafened, the button undeafens: hearing comes back first (and your voice with it, unless you muted too).
    final deaf = call.deafened && !locked;
    final green = _green(t);
    final title = locked ? 'Muted by a moderator' : (deaf ? SpaceWords.deafen(call) : (live ? 'Mic on' : 'Muted'));
    final hint = locked ? 'You can listen' : (deaf ? (call.muted ? 'Tap to listen' : 'Tap to listen and speak') : (live ? 'Tap to mute' : 'Tap to unmute'));
    final icon = locked ? Lucide.lock : (deaf ? LucideMore.headphoneOff : (live ? Lucide.mic : LucideMore.micOff));
    return GlacierPressable(
      onPressed: locked ? null : (deaf ? call.onDeafen : call.onMute),
      semanticLabel: locked || deaf ? title : SpaceWords.mute(call),
      builder: (context, state) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: box,
          child: Center(
            child: Stack(alignment: Alignment.center, children: [
              // The app's ripples, the face under them hidden by the button.
              ExcludeSemantics(
                child: ValueListenableBuilder<Map<String, double>>(
                  valueListenable: call.levels,
                  builder: (context, now, _) => RippleAvatar(key: const ValueKey('tg-mic-ripples'), name: ' ', level: live ? (now['me'] ?? 0) : 0, muted: !live, size: ringFace, color: green),
                ),
              ),
              AnimatedScale(
                scale: state.pressed ? 0.95 : 1,
                duration: const Duration(milliseconds: 100),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? green : t.color(locked ? 'app-paper-3' : 'app-paper-2'),
                    border: live ? null : Border.all(color: locked ? t.color('app-ink-4') : t.color('app-rule'), width: locked ? 1.5 : 1),
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(icon, size: locked ? 22 : 26, wash: false, color: live ? const Color(0xFFFFFFFF) : t.color(locked ? 'app-ink-3' : 'app-ink')),
                ),
              ),
            ]),
          ),
        ),
        ExcludeSemantics(child: Text(title, maxLines: locked ? 2 : 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'bold', color: live ? green : t.color('app-ink')))),
        ExcludeSemantics(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')))),
      ]),
    );
  }
}

/// The space's chat as a sheet of its own (a phone) or a panel docked beside the voice chat (a computer), in the
/// app's own paper and ink as its bubbles and composer are.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.call, required this.onClose, required this.bottom});
  final SpaceCall call;
  final VoidCallback onClose;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = call.channel.name.isEmpty ? 'Space' : call.channel.name;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule')))),
          child: Column(children: [
            SizedBox(
              height: 58,
              child: Row(children: [
                SizedBox(width: t.space(4)),
                AppIcon(LucideMore.messageCircle, size: 20, wash: false, color: t.color('app-ink')),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(SpaceWords.chat, maxLines: 1, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                  ]),
                ),
                _IconButton(icon: Lucide.x, label: 'Close chat', onPressed: onClose),
                SizedBox(width: t.space(3)),
              ]),
            ),
          ]),
        ),
        Expanded(child: call.chat(bottom: bottom)),
      ]),
    );
  }
}
