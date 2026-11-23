import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../tile_grid.dart';
import 'space_design.dart';

/// A space's call drawn after Google Meet (SpaceDesign.meet): soft rounded tiles on Meet's grey ground, each with a
/// coloured face; whoever talks gets a blue outline and three moving bars in the corner. Along the foot, the clock and
/// the space's name, round pill buttons with a wide red "Leave call", and Details, People and Chat on the right, which
/// open as a rounded card beside the tiles on a computer and as a page of their own on a phone.
class MeetCall extends StatefulWidget {
  const MeetCall({super.key, required this.call});
  final SpaceCall call;

  @override
  State<MeetCall> createState() => _MeetCallState();
}

/// Which side panel is open; one at a time, and pressing an open panel's button closes it.
enum _Panel { none, people, chat, details }

class _MeetCallState extends State<MeetCall> {
  _Panel _panel = _Panel.none;
  bool _more = false;
  String _filter = '';

  SpaceCall get call => widget.call;

  /// Opens panel [p], or closes it if it is the one open; the More menu closes either way.
  void _toggle(_Panel p) => setState(() {
        _more = false;
        _panel = _panel == p ? _Panel.none : p;
      });

  void _invite(BuildContext context) => call.onInvite?.call(context);

  @override
  Widget build(BuildContext context) {
    final c = _MeetColors.of(context);
    return ColoredBox(
      color: c.ground,
      child: LayoutBuilder(builder: (context, box) => box.maxWidth >= 720 ? _computer(context, c) : _phone(context, c)),
    );
  }

  // ---- A computer's window -----------------------------------------------------------------------------------

  /// 720 points wide or more: the tiles with the open panel as a 360-wide card beside them, and the bar along the foot.
  Widget _computer(BuildContext context, _MeetColors c) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: pad.top, left: pad.left, right: pad.right),
      child: Stack(children: [
        Column(children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _stage(context, c, wide: true)),
                if (_panel != _Panel.none) ...[
                  SizedBox(width: t.space(4)),
                  SizedBox(width: 360, child: _panelCard(context, c, page: false)),
                ],
              ]),
            ),
          ),
          _computerBar(context, c, bottom: pad.bottom),
        ]),
        if (_more) _moreMenu(context, c, wide: true),
      ]),
    );
  }

  Widget _computerBar(BuildContext context, _MeetColors c, {required double bottom}) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(5), t.space(3), t.space(4), t.space(3) + bottom),
      child: Row(children: [
        // Left: "12:05 | Friday hang", as Meet's "7:41 PM | abc-defg-hij".
        Expanded(
          child: Row(children: [
            Text(call.clock(DateTime.now()), style: pageText(t, t.fontSize('md'), weight: 'semibold', color: c.ink)),
            Padding(padding: EdgeInsets.symmetric(horizontal: t.space(2)), child: Text('|', style: pageText(t, t.fontSize('md'), color: c.ink3))),
            Flexible(child: Text(call.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: c.ink))),
          ]),
        ),
        _controls(context, c),
        // Right: Details, People (with how many), Chat.
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _SideButton(c: c, icon: Lucide.info, label: 'Details', on: _panel == _Panel.details, onPressed: () => _toggle(_Panel.details)),
            _SideButton(c: c, icon: Lucide.users, label: SpaceWords.people, badge: '${call.people.length}', on: _panel == _Panel.people, onPressed: () => _toggle(_Panel.people)),
            _SideButton(c: c, icon: Lucide.messageSquare, label: SpaceWords.chat, on: _panel == _Panel.chat, onPressed: () => _toggle(_Panel.chat)),
          ]),
        ),
      ]),
    );
  }

  /// The round pills in the middle of a computer's bar: the microphone (with its devices chevron), camera, deafen,
  /// more, and the wide red leave pill.
  Widget _controls(BuildContext context, _MeetColors c) {
    final t = context.tokens;
    const size = 44.0;
    final gap = SizedBox(width: t.space(2));
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _MicPill(c: c, call: call, size: size),
      gap,
      _Pill(
        c: c,
        icon: SpaceWords.videoIcon(call),
        label: SpaceWords.video(call),
        semantic: call.videoLocked ? 'Video is turned off for you' : null,
        off: !call.video,
        size: size,
        onPressed: call.videoLocked ? null : call.onVideo,
      ),
      gap,
      // The other camera, beside the camera's pill, on a wide phone or tablet while video is on (GMFB-57).
      if (call.onFlip != null) ...[
        _Pill(c: c, icon: SpaceWords.flipIcon, label: 'Flip', semantic: SpaceWords.flip, size: size, onPressed: call.onFlip),
        gap,
      ],
      _Pill(c: c, icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), off: call.deafened, size: size, onPressed: call.onDeafen),
      gap,
      _Pill(c: c, icon: Lucide.ellipsisVertical, label: 'More', semantic: 'More options', on: _more, size: size, onPressed: () => setState(() => _more = !_more)),
      gap,
      _Pill(c: c, icon: _hangUp, label: 'Leave call', danger: true, width: size * 1.6, size: size, onPressed: call.onLeave),
    ]);
  }

  // ---- A phone ----------------------------------------------------------------------------------------------

  /// Narrower than 720: a header, the tiles and a row of pills; an open panel takes the whole screen instead.
  Widget _phone(BuildContext context, _MeetColors c) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    if (_panel != _Panel.none) {
      // A panel is a page of its own on a phone.
      return ColoredBox(color: c.panel, child: Padding(padding: EdgeInsets.only(top: pad.top), child: _panelCard(context, c, page: true, bottom: pad.bottom)));
    }
    return Stack(children: [
      Padding(
        padding: EdgeInsets.only(top: pad.top, left: pad.left, right: pad.right),
        child: Column(children: [
          _phoneTop(context, c),
          Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: t.space(2)), child: _stage(context, c, wide: false))),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(1), t.space(3), t.space(1), t.space(2) + pad.bottom),
            child: _phoneBar(context, c),
          ),
        ]),
      ),
      if (_more) _moreMenu(context, c, wide: false),
    ]);
  }

  Widget _phoneTop(BuildContext context, _MeetColors c) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(1), t.space(1), t.space(1), t.space(2)),
      child: Row(children: [
        _IconTap(c: c, icon: Lucide.chevronDown, label: SpaceWords.minimize, onPressed: call.onMinimize),
        SizedBox(width: t.space(1)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(call.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: c.ink)),
            Text('${call.clock(DateTime.now())}  ·  ${call.people.length} in call', maxLines: 1, style: pageText(t, t.fontSize('sm'), color: c.ink2)),
          ]),
        ),
        _IconTap(c: c, icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => _invite(context)),
        _IconTap(c: c, icon: Lucide.users, label: SpaceWords.people, badge: '${call.people.length}', onPressed: () => _toggle(_Panel.people)),
      ]),
    );
  }

  Widget _phoneBar(BuildContext context, _MeetColors c) {
    const size = 50.0;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Pill(
        c: c,
        icon: SpaceWords.muteIcon(call),
        label: SpaceWords.mute(call),
        semantic: call.micLocked ? 'You can\'t unmute here' : null,
        off: call.muted,
        size: size,
        onPressed: call.micLocked ? null : call.onMute,
      ),
      _Pill(c: c, icon: SpaceWords.videoIcon(call), label: SpaceWords.video(call), off: !call.video, size: size, onPressed: call.videoLocked ? null : call.onVideo),
      _Pill(c: c, icon: SpaceWords.deafenIcon(call), label: SpaceWords.deafen(call), off: call.deafened, size: size, onPressed: call.onDeafen),
      _Pill(c: c, icon: Lucide.messageSquare, label: SpaceWords.chat, size: size, onPressed: () => _toggle(_Panel.chat)),
      _Pill(c: c, icon: Lucide.ellipsisVertical, label: 'More', semantic: 'More options', on: _more, size: size, onPressed: () => setState(() => _more = !_more)),
      _Pill(c: c, icon: _hangUp, label: SpaceWords.leave, semantic: 'Leave call', danger: true, size: size, onPressed: call.onLeave),
    ]);
  }

  // ---- The tiles --------------------------------------------------------------------------------------------

  /// Everyone's tiles in an even grid, the last row centred; alone, your own tile with the invite card.
  Widget _stage(BuildContext context, _MeetColors c, {required bool wide}) {
    final t = context.tokens;
    final people = call.people;
    if (people.length == 1) return _alone(context, c, wide: wide);
    return LayoutBuilder(builder: (context, box) {
      final gap = t.space(2);
      final n = people.length;
      // On a computer every tile 4:3, as many across as make them biggest, the grid centred.
      if (wide) {
        final fit = fitTiles(box.biggest, n, gap: gap);
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < fit.rows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final (i, p) in people.skip(r * fit.cols).take(fit.cols).indexed) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(width: fit.size.width, height: fit.size.height, child: _MeetTile(c: c, call: call, person: p, small: fit.size.height < 150)),
              ],
            ]),
          ],
        ]));
      }
      // Columns on a phone: as Meet does, the arrangement whose tiles come out closest to 4:5, filling the screen.
      const aim = 4 / 5;
      var cols = 1;
      var best = double.infinity;
      for (var k = 1; k <= n; k++) {
        final rows = (n / k).ceil();
        final w = (box.maxWidth - gap * (k - 1)) / k, h = (box.maxHeight - gap * (rows - 1)) / rows;
        // How far the tile's shape is from the aim, plus a little for every empty cell in the grid.
        final miss = (math.log(w / h) - math.log(aim)).abs() + (rows * k - n) * 0.15;
        if (miss < best) {
          best = miss;
          cols = k;
        }
      }
      final rows = (n / cols).ceil();
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      final h = (box.maxHeight - gap * (rows - 1)) / rows;
      final lines = <Widget>[];
      for (var r = 0; r < rows; r++) {
        final row = people.skip(r * cols).take(cols).toList();
        if (r > 0) lines.add(SizedBox(height: gap));
        lines.add(Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < row.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            SizedBox(width: w, height: h, child: _MeetTile(c: c, call: call, person: row[i], small: h < 150)),
          ],
        ]));
      }
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: lines));
    });
  }

  /// Alone: your own tile, big, still showing your voice, and Meet's card saying no one else is here.
  Widget _alone(BuildContext context, _MeetColors c, {required bool wide}) {
    final t = context.tokens;
    final card = Container(
      width: wide ? 380 : null,
      padding: EdgeInsets.all(t.space(5)),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.dark ? const Color(0xFF4A4E52) : const Color(0xFFDADCE0)), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('You\'re the only one here', style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: c.cardInk)),
        SizedBox(height: t.space(2)),
        Text('Bring people into the call: friends in the app, or anyone by a text or the link.', style: pageText(t, t.fontSize('sm'), color: c.cardInk2)),
        SizedBox(height: t.space(4)),
        _BluePill(c: c, icon: Lucide.userPlus, label: 'Invite people', onPressed: call.onInvite == null ? null : () => _invite(context)),
      ]),
    );
    final tile = _MeetTile(c: c, call: call, person: call.me, alone: true);
    if (wide) {
      return Stack(children: [
        // Your tile 4:3 in the middle of the stage, the card over its corner.
        Positioned.fill(child: Center(child: AspectRatio(aspectRatio: tileAspect, child: tile))),
        Positioned(left: t.space(5), bottom: t.space(12), child: card),
      ]);
    }
    return Column(children: [
      Expanded(child: tile),
      SizedBox(height: t.space(3)),
      SizedBox(width: double.infinity, child: card),
    ]);
  }

  // ---- Panels -----------------------------------------------------------------------------------------------

  /// The open panel under its title: a rounded card with a close button on a computer, a full page with a back arrow
  /// on a phone ([page]). [bottom] is the screen's inset the panel's own list or composer must clear.
  Widget _panelCard(BuildContext context, _MeetColors c, {required bool page, double bottom = 0}) {
    final t = context.tokens;
    final title = switch (_panel) {
      _Panel.people => 'People',
      _Panel.chat => 'In-call messages',
      _Panel.details => 'Call details',
      _Panel.none => '',
    };
    final body = switch (_panel) {
      _Panel.people => _peopleList(context, c, bottom: bottom),
      _Panel.chat => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            margin: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(2)),
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
            decoration: BoxDecoration(color: c.panel2, borderRadius: BorderRadius.circular(8)),
            child: Text('Messages stay in this space\'s chat.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), color: c.panelInk2)),
          ),
          Expanded(child: call.chat(bottom: bottom)),
        ]),
      _Panel.details => _details(context, c),
      _Panel.none => const SizedBox.shrink(),
    };
    return Container(
      decoration: BoxDecoration(color: c.panel, borderRadius: page ? null : BorderRadius.circular(16)),
      clipBehavior: page ? Clip.none : Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(page ? t.space(1) : t.space(5), t.space(3), t.space(2), t.space(3)),
          child: Row(children: [
            if (page) _IconTap(c: c, icon: Lucide.arrowLeft, label: 'Back to the call', ink: c.panelInk, onPressed: () => _toggle(_panel)),
            Expanded(child: Text(title, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: c.panelInk))),
            if (!page) _IconTap(c: c, icon: Lucide.x, label: 'Close', ink: c.panelInk, onPressed: () => _toggle(_panel)),
          ]),
        ),
        Expanded(child: body),
      ]),
    );
  }

  /// The People panel: Add people, a search by name, then everyone in the call with their role in the room.
  Widget _peopleList(BuildContext context, _MeetColors c, {double bottom = 0}) {
    final t = context.tokens;
    final roster = call.room?.roster;
    final want = _filter.trim().toLowerCase();
    final shown = [for (final p in call.people) if (want.isEmpty || p.name.toLowerCase().contains(want)) p];
    return ListView(padding: EdgeInsets.only(bottom: t.space(4) + bottom), children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space(4)),
        child: Row(children: [_BluePill(c: c, icon: Lucide.userPlus, label: 'Add people', onPressed: call.onInvite == null ? null : () => _invite(context))]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), t.space(2)),
        child: GlacierInput(
          placeholder: 'Search for people',
          ariaLabel: 'Search for people',
          size: GlacierFieldSize.md,
          leadingIcon: AppIcon(Lucide.search, size: 16, wash: false, color: c.panelInk2),
          onChange: (v) => setState(() => _filter = v),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(1)),
        child: Text('IN CALL  ·  ${call.people.length}', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: c.panelInk2)),
      ),
      for (final p in shown) _PersonRow(c: c, call: call, person: p, role: p.roleLabel(roster)),
    ]);
  }

  Widget _details(BuildContext context, _MeetColors c) {
    final t = context.tokens;
    return ListView(padding: EdgeInsets.symmetric(horizontal: t.space(5)), children: [
      Text('Joining info', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: c.panelInk)),
      SizedBox(height: t.space(2)),
      Text('${call.channel.name}, a space in Ghost Messaging. Add people to bring them into the call.', style: pageText(t, t.fontSize('sm'), color: c.panelInk2)),
      SizedBox(height: t.space(4)),
      Row(children: [_BluePill(c: c, icon: Lucide.userPlus, label: 'Add people', onPressed: call.onInvite == null ? null : () => _invite(context))]),
      SizedBox(height: t.space(6)),
      Text('You\'ve been in this call for ${call.clock(DateTime.now())}.', style: pageText(t, t.fontSize('sm'), color: c.panelInk2)),
    ]);
  }

  /// Meet's "More options" menu: settings, devices, invite and minimise.
  Widget _moreMenu(BuildContext context, _MeetColors c, {required bool wide}) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    void run(VoidCallback f) {
      setState(() => _more = false);
      f();
    }

    final items = <Widget>[
      // The other camera (GMFB-57): a narrow phone's bar has no room for a seventh pill, so it is first in More.
      if (!wide && call.onFlip != null) _MenuRow(c: c, icon: SpaceWords.flipIcon, label: SpaceWords.flip, onPressed: () => run(call.onFlip!)),
      _MenuRow(c: c, icon: LucideMore.settings, label: SpaceWords.settings, onPressed: call.onSettings == null ? null : () => run(() => call.onSettings!(context))),
      _MenuRow(c: c, icon: Lucide.slidersHorizontal, label: SpaceWords.devices, onPressed: call.onDevices == null ? null : () => run(() => call.onDevices!(context))),
      _MenuRow(c: c, icon: Lucide.userPlus, label: SpaceWords.invite, onPressed: call.onInvite == null ? null : () => run(() => _invite(context))),
      for (final x in call.extras) _MenuRow(c: c, icon: x.icon, label: x.label, onPressed: () => run(() => x.run(context))),
      if (!wide) _MenuRow(c: c, icon: Lucide.info, label: 'Details', onPressed: () => run(() => _toggle(_Panel.details))),
      _MenuRow(c: c, icon: _minimise, label: SpaceWords.minimize, onPressed: call.onMinimize == null ? null : () => run(call.onMinimize!)),
    ];
    final menu = Container(
      width: 240,
      padding: EdgeInsets.symmetric(vertical: t.space(2)),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.dark ? const Color(0xFF4A4E52) : const Color(0xFFDADCE0)), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 20, offset: Offset(0, 6))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _more = false),
        child: Align(
          alignment: wide ? Alignment.bottomCenter : Alignment.bottomRight,
          child: Padding(
            // Just above the bar, under the More button.
            padding: EdgeInsets.only(bottom: (wide ? 84 : 92) + pad.bottom, right: wide ? 0 : t.space(3), left: wide ? 150 : 0),
            child: GestureDetector(onTap: () {}, child: menu),
          ),
        ),
      ),
    );
  }
}

// ---- Colours --------------------------------------------------------------------------------------------------

/// Meet's palette: #202124 ground and #3C4043 tiles in the dark, a near-white ground in the light; its blue for
/// whoever talks, its red for a mic or camera that is off and for leaving. The panels take the app's own paper and
/// ink, as the chat inside them does.
class _MeetColors {
  _MeetColors._(this.dark, Tokens t)
      : ground = dark ? const Color(0xFF202124) : const Color(0xFFF1F3F4),
        tile = dark ? const Color(0xFF3C4043) : const Color(0xFFFFFFFF),
        tileEdge = dark ? const Color(0x00000000) : const Color(0xFFDADCE0),
        ink = dark ? const Color(0xFFE8EAED) : const Color(0xFF202124),
        ink2 = dark ? const Color(0xFFBDC1C6) : const Color(0xFF5F6368),
        ink3 = const Color(0xFF9AA0A6),
        button = dark ? const Color(0xFF3C4043) : const Color(0xFFE3E5E8),
        buttonHover = dark ? const Color(0xFF4A4E52) : const Color(0xFFD6D9DC),
        red = dark ? const Color(0xFFEA4335) : const Color(0xFFD93025),
        blue = dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8),
        onBlue = dark ? const Color(0xFF202124) : const Color(0xFFFFFFFF),
        blueWash = dark ? const Color(0xFF394457) : const Color(0xFFD3E3FD),
        card = dark ? const Color(0xFF2D2E31) : const Color(0xFFFFFFFF),
        cardInk = dark ? const Color(0xFFE8EAED) : const Color(0xFF202124),
        cardInk2 = dark ? const Color(0xFFBDC1C6) : const Color(0xFF5F6368),
        panel = t.color('app-paper'),
        panel2 = t.color('app-paper-2'),
        panelInk = t.color('app-ink'),
        panelInk2 = t.color('app-ink-2');

  factory _MeetColors.of(BuildContext context) {
    final t = context.tokens;
    return _MeetColors._(t.color('app-paper').computeLuminance() < 0.3, t);
  }

  final bool dark;
  final Color ground, tile, tileEdge, ink, ink2, ink3, button, buttonHover, red, blue, onBlue, blueWash, card, cardInk, cardInk2;
  final Color panel, panel2, panelInk, panelInk2;

  /// The coloured circle a face sits in, chosen by name (Meet's avatar colours).
  static Color face(String name) {
    const colours = [Color(0xFF1A73E8), Color(0xFFE8710A), Color(0xFF188038), Color(0xFF9334E6), Color(0xFFD93025), Color(0xFF12B5CB), Color(0xFFE52592), Color(0xFFB06000)];
    var h = 0;
    for (final u in name.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return colours[h % colours.length];
  }
}

// ---- Icons ----------------------------------------------------------------------------------------------------

/// Lucide's minimize-2 (ISC licence), not in the app's set.
const _minimise = LucideIcon.phosphor('minimize-2', 'M224,48V208a16,16,0,0,1-16,16H48a16,16,0,0,1-16-16V48A16,16,0,0,1,48,32H208A16,16,0,0,1,224,48Z', 'M213.66,53.66,163.31,104H192a8,8,0,0,1,0,16H144a8,8,0,0,1-8-8V64a8,8,0,0,1,16,0V92.69l50.34-50.35a8,8,0,0,1,11.32,11.32ZM112,136H64a8,8,0,0,0,0,16H92.69L42.34,202.34a8,8,0,0,0,11.32,11.32L104,163.31V192a8,8,0,0,0,16,0V144A8,8,0,0,0,112,136Z');

/// Leaving: the phone put down.
const _hangUp = LucideMore.phoneOff;

// ---- Tiles ----------------------------------------------------------------------------------------------------

/// One person's tile: their camera or their face, the name along the foot, a blue edge and moving bars while they
/// talk, a mic-off dot while muted. Pressing it (or holding) opens what can be done with them.
class _MeetTile extends StatelessWidget {
  const _MeetTile({required this.c, required this.call, required this.person, this.small = false, this.alone = false});
  final _MeetColors c;
  final SpaceCall call;
  final SpacePerson person;
  final bool small;
  final bool alone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final video = person.video;
    final nameInk = video ? const Color(0xFFFFFFFF) : c.ink;
    final press = call.onPerson == null ? null : () => call.onPerson!(context, person);
    return _Press(
      onPressed: press,
      onLongPress: press,
      semanticLabel: '${person.shown}${person.muted ? ', muted' : ''}',
      builder: (context, state) => ValueListenableBuilder<Map<String, double>>(
        valueListenable: call.levels,
        builder: (context, now, _) {
          final talking = call.isTalking(person, now);
          final level = person.muted ? 0.0 : (now[person.id] ?? 0);
          return LayoutBuilder(builder: (context, box) {
            final faceSize = (math.min(box.maxWidth, box.maxHeight) * (alone ? 0.32 : 0.42)).clamp(36.0, 160.0);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: video ? const Color(0xFF17181A) : c.tile,
                borderRadius: BorderRadius.circular(small ? 12 : 16),
                border: Border.all(color: talking ? c.blue : (state.hovered ? c.ink3 : c.tileEdge), width: talking ? 3 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                Positioned.fill(
                  child: video
                      ? SpaceVideo(call: call, person: person, fallback: _VideoWaiting(c: c, person: person, level: level, size: faceSize))
                      : Center(child: _MeetFace(name: person.name, level: level, size: faceSize, c: c)),
                ),
                // Top right: three moving bars while they talk, a mic-off circle while muted.
                Positioned(
                  top: t.space(2),
                  right: t.space(2),
                  child: person.muted
                      ? _CornerDot(color: const Color(0x99202124), child: AppIcon(SpaceWords.mutedIcon(person), size: 14, wash: false, color: const Color(0xFFFFFFFF)))
                      : (talking ? _Bars(level: level, talking: true, c: c) : const SizedBox.shrink()),
                ),
                // Bottom left: the name.
                Positioned(
                  left: t.space(3),
                  right: t.space(3),
                  bottom: t.space(2),
                  child: Row(children: [
                    Flexible(
                      child: Text(
                        person.me ? '${person.name.isEmpty ? 'You' : person.name} (You)' : person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: pageText(t, t.fontSize(small ? 'xs' : 'sm'), weight: 'semibold', color: nameInk)
                            .copyWith(shadows: video || c.dark ? const [Shadow(color: Color(0x88000000), blurRadius: 4)] : null),
                      ),
                    ),
                    if (person.guest) ...[
                      SizedBox(width: t.space(1)),
                      Text('Guest', style: pageText(t, t.fontSize('xs'), color: video ? const Color(0xCCFFFFFF) : c.ink2)),
                    ],
                  ]),
                ),
              ]),
            );
          });
        },
      ),
    );
  }
}

/// A camera that is on but whose picture has not come: a dark tile with the face and a small camera mark, so it reads
/// as video on its way rather than an empty tile.
class _VideoWaiting extends StatelessWidget {
  const _VideoWaiting({required this.c, required this.person, required this.level, required this.size});
  final _MeetColors c;
  final SpacePerson person;
  final double level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A2C30), Color(0xFF111214)])),
      child: Stack(children: [
        Center(child: _MeetFace(name: person.name, level: level, size: size, c: c, dark: true)),
        Positioned(
          top: t.space(2),
          left: t.space(2),
          child: _CornerDot(color: const Color(0x66000000), child: AppIcon(Lucide.video, size: 14, wash: false, color: const Color(0xFFFFFFFF))),
        ),
      ]),
    );
  }
}

/// Meet's face: a coloured circle with the first letter, and a soft blue halo that swells with their voice.
class _MeetFace extends StatelessWidget {
  const _MeetFace({required this.name, required this.level, required this.size, required this.c, this.dark = false});
  final String name;
  final double level;
  final double size;
  final _MeetColors c;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final letter = (name.trim().characters.firstOrNull ?? '?').toUpperCase();
    final swell = level <= SpaceCall.talking ? 0.0 : (0.25 + level * 1.4).clamp(0.0, 1.0);
    final halo = (dark || c.dark) ? const Color(0xFF8AB4F8) : const Color(0xFF1A73E8);
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size * (1 + 0.28 * swell),
          height: size * (1 + 0.28 * swell),
          decoration: BoxDecoration(shape: BoxShape.circle, color: halo.withValues(alpha: 0.28 * swell)),
        ),
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _MeetColors.face(name)),
          child: Text(letter, style: pageText(t, size * 0.42, weight: 'regular', color: const Color(0xFFFFFFFF))),
        ),
      ]),
    );
  }
}

/// A small round ground for a mark in a tile's corner (mic off, camera on its way).
class _CornerDot extends StatelessWidget {
  const _CornerDot({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: child);
}

/// Meet's audio indicator: three bars in a blue circle, moving with the voice; three low still bars while quiet.
class _Bars extends StatefulWidget {
  const _Bars({required this.level, required this.talking, required this.c});
  final double level;
  final bool talking;
  final _MeetColors c;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_Bars old) {
    super.didUpdateWidget(old);
    _follow();
  }

  void _follow() {
    if (widget.talking && !_time.isAnimating) _time.repeat();
    if (!widget.talking && _time.isAnimating) _time.stop();
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final talking = widget.talking;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(shape: BoxShape.circle, color: talking ? c.blue : const Color(0x55202124)),
      child: AnimatedBuilder(
        animation: _time,
        builder: (context, _) {
          final strength = talking ? (0.35 + widget.level * 1.6).clamp(0.0, 1.0) : 0.0;
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2.5),
              Container(
                width: 3.5,
                // The middle bar the tallest, the outer two out of step with it.
                height: 4 + strength * (i == 1 ? 9 : 6) * (0.55 + 0.45 * math.sin((_time.value + i * 0.33) * math.pi * 2).abs()),
                decoration: BoxDecoration(color: talking ? c.onBlue : const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

// ---- Buttons --------------------------------------------------------------------------------------------------

/// A Meet bar button: a grey circle (red while that thing is off, or for leaving), its words under it.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.c,
    required this.icon,
    required this.label,
    this.onPressed,
    this.semantic,
    this.off = false,
    this.on = false,
    this.danger = false,
    this.size = 44,
    this.width,
  });
  final _MeetColors c;
  final LucideIcon icon;
  final String label;
  final String? semantic;
  final VoidCallback? onPressed;
  final bool off, on, danger;
  final double size;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final red = off || danger;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: _Press(
        onPressed: onPressed,
        semanticLabel: semantic ?? label,
        builder: (context, state) => SizedBox(
          width: math.max(width ?? size, size + 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: width ?? size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: red ? (state.hovered ? Color.lerp(c.red, const Color(0xFF000000), 0.1) : c.red) : (on ? c.blueWash : (state.hovered ? c.buttonHover : c.button)),
                borderRadius: BorderRadius.circular(size / 2),
              ),
              child: AppIcon(icon, size: size * 0.44, wash: false, color: red ? const Color(0xFFFFFFFF) : (on ? c.blue : c.ink)),
            ),
            SizedBox(height: t.space(1)),
            Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: c.ink2)),
          ]),
        ),
      ),
    );
  }
}

/// Meet's microphone: one pill, the devices chevron on its left, the mic on its right.
class _MicPill extends StatelessWidget {
  const _MicPill({required this.c, required this.call, required this.size});
  final _MeetColors c;
  final SpaceCall call;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final off = call.muted;
    final locked = call.micLocked;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: size,
        decoration: BoxDecoration(color: c.button, borderRadius: BorderRadius.circular(size / 2)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Press(
            onPressed: call.onDevices == null ? null : () => call.onDevices!(context),
            semanticLabel: SpaceWords.devices,
            builder: (context, state) => Container(
              width: size * 0.7,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: state.hovered ? c.buttonHover : null, borderRadius: BorderRadius.horizontal(left: Radius.circular(size / 2))),
              child: AppIcon(Lucide.chevronUp, size: size * 0.36, wash: false, color: c.ink),
            ),
          ),
          Opacity(
            opacity: locked ? 0.5 : 1,
            child: _Press(
              onPressed: locked ? null : call.onMute,
              semanticLabel: locked ? 'You can\'t unmute here' : SpaceWords.mute(call),
              builder: (context, state) => Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: off ? c.red : (state.hovered ? c.buttonHover : c.button), shape: BoxShape.circle),
                child: AppIcon(SpaceWords.muteIcon(call), size: size * 0.44, wash: false, color: off ? const Color(0xFFFFFFFF) : c.ink),
              ),
            ),
          ),
        ]),
      ),
      SizedBox(height: t.space(1)),
      ExcludeSemantics(child: Text(locked ? 'Muted for you' : SpaceWords.mute(call), maxLines: 1, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: c.ink2))),
    ]);
  }
}

/// The plain icon buttons at the bar's right end (Details, People, Chat): words under, a count on People, blue while
/// its panel is open.
class _SideButton extends StatelessWidget {
  const _SideButton({required this.c, required this.icon, required this.label, required this.onPressed, this.on = false, this.badge});
  final _MeetColors c;
  final LucideIcon icon;
  final String label;
  final VoidCallback onPressed;
  final bool on;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Press(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.blueWash : (state.hovered ? c.buttonHover : null)),
            child: Stack(clipBehavior: Clip.none, children: [
              AppIcon(icon, size: 22, wash: false, color: on ? c.blue : c.ink),
              if (badge != null) Positioned(right: -10, top: -8, child: _Badge(c: c, text: badge!)),
            ]),
          ),
          SizedBox(height: t.space(1)),
          Text(label, maxLines: 1, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: on ? c.blue : c.ink2)),
        ]),
      ),
    );
  }
}

/// The small count on the People button: how many are in the call.
class _Badge extends StatelessWidget {
  const _Badge({required this.c, required this.text});
  final _MeetColors c;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.dark ? const Color(0xFF5F6368) : const Color(0xFFDADCE0), borderRadius: BorderRadius.circular(9), border: Border.all(color: c.ground, width: 2)),
      child: Text(text, style: pageText(t, 10, weight: 'bold', color: c.ink)),
    );
  }
}

/// An icon button with no words beside it (the phone's header, a panel's close), where space is tight: its name is
/// read out.
class _IconTap extends StatelessWidget {
  const _IconTap({required this.c, required this.icon, required this.label, required this.onPressed, this.badge, this.ink});
  final _MeetColors c;
  final LucideIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final String? badge;
  final Color? ink;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: _Press(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? c.buttonHover : null),
            child: Stack(clipBehavior: Clip.none, children: [
              AppIcon(icon, size: 22, wash: false, color: ink ?? c.ink),
              if (badge != null) Positioned(right: -10, top: -8, child: _Badge(c: c, text: badge!)),
            ]),
          ),
        ),
      );
}

/// Meet's blue pill: "Invite people", "Add people".
class _BluePill extends StatelessWidget {
  const _BluePill({required this.c, required this.icon, required this.label, required this.onPressed});
  final _MeetColors c;
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
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: t.space(4)),
          decoration: BoxDecoration(color: state.hovered ? Color.lerp(c.blue, const Color(0xFF000000), 0.08) : c.blue, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 18, wash: false, color: c.onBlue),
            SizedBox(width: t.space(2)),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: c.onBlue))),
          ]),
        ),
      ),
    );
  }
}

/// A line of the More options menu: icon and words; dimmed when there is nothing to run.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.c, required this.icon, required this.label, required this.onPressed});
  final _MeetColors c;
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
          height: 48,
          color: state.hovered ? c.buttonHover.withValues(alpha: 0.5) : null,
          padding: EdgeInsets.symmetric(horizontal: t.space(4)),
          child: Row(children: [
            AppIcon(icon, size: 20, wash: false, color: c.cardInk2),
            SizedBox(width: t.space(4)),
            Expanded(child: Text(label, style: pageText(t, t.fontSize('md'), color: c.cardInk))),
          ]),
        ),
      ),
    );
  }
}

/// A row in the People panel: face, name, role tag, and the mic as it stands (bars while talking).
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.c, required this.call, required this.person, this.role});
  final _MeetColors c;
  final SpaceCall call;
  final SpacePerson person;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final press = call.onPerson == null ? null : () => call.onPerson!(context, person);
    return _Press(
      onPressed: press,
      onLongPress: press,
      semanticLabel: person.shown,
      builder: (context, state) => Container(
        color: state.hovered ? c.panel2 : null,
        padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
        child: ValueListenableBuilder<Map<String, double>>(
          valueListenable: call.levels,
          builder: (context, now, _) {
            final level = person.muted ? 0.0 : (now[person.id] ?? 0);
            return Row(children: [
              _MeetFace(name: person.name, level: level, size: 36, c: c),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(person.me ? '${person.name} (You)' : person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: c.panelInk)),
                  if (role != null || person.guest) Text([?role, if (person.guest) 'Guest'].join(' · '), maxLines: 1, style: pageText(t, t.fontSize('xs'), color: c.panelInk2)),
                ]),
              ),
              if (person.muted) AppIcon(SpaceWords.mutedIcon(person), size: 18, wash: false, color: c.panelInk2) else if (call.isTalking(person, now)) _Bars(level: level, talking: true, c: c) else AppIcon(Lucide.mic, size: 18, wash: false, color: c.panelInk2),
            ]);
          },
        ),
      ),
    );
  }
}

/// GlacierPressable read out by its [semanticLabel] alone: the words drawn inside it are not added to the name, so
/// "Mute" is read (and found) as "Mute", not "Mute Mute".
class _Press extends StatelessWidget {
  const _Press({required this.onPressed, required this.semanticLabel, required this.builder, this.onLongPress});
  final VoidCallback? onPressed, onLongPress;
  final String semanticLabel;
  final Widget Function(BuildContext context, PressState state) builder;

  @override
  Widget build(BuildContext context) => GlacierPressable(
        onPressed: onPressed,
        onLongPress: onLongPress,
        semanticLabel: semanticLabel,
        builder: (context, state) => ExcludeSemantics(child: builder(context, state)),
      );
}
