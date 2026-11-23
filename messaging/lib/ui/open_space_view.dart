import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/open_space.dart';
import '../voice/voice.dart';
import 'common.dart';
import 'hangout_screen.dart' show SpaceFace;
import 'ripple_avatar.dart';
import 'voice_screen.dart' show LinkBadge, showPerson;

/// Draws one person on an open space's floor. Today's is [avatarFigure]; a character (a ghost dressed in cosmetics)
/// is another of these, handed the same [OpenFigure]: which way they face and whether they walk are already in it.
typedef OpenFigureBuilder = Widget Function(BuildContext context, OpenFigure who, Widget face);

/// A person as their profile picture with the call's ripple round it while they talk.
Widget avatarFigure(BuildContext context, OpenFigure who, Widget face) => RippleAvatar(name: who.name, level: who.level, muted: who.muted, size: who.size, child: face);

/// An open space's floor seen from above (lib/voice/open_space.dart; Matt, 2026-11-23: "a top down view and lets you
/// move around in the space ... allow walking around with wasd or arrow keys"). This device stays in the middle of the
/// view and the floor moves under it. Walk with W A S D or the arrow keys while the floor has the keyboard, or press
/// (or drag) where to go. Groups are drawn as target circles that grow with who is in them; press a group's name for
/// what can be done with it. Everyone else is drawn where they said they stand, eased between their words, and fainter
/// the less of them is heard from here.
class OpenSpaceView extends StatefulWidget {
  const OpenSpaceView({super.key, required this.session, required this.floor, this.figure = avatarFigure, this.bottomInset = 0});
  final VoiceSession session;
  final OpenSpace floor;
  final OpenFigureBuilder figure;

  /// Room left at the foot for what is drawn over it (the call's dock).
  final double bottomInset;

  /// How many of the screen's units one of the floor's is, for a view [size] big: a little smaller on a phone, so
  /// about as much floor is seen.
  static double scaleFor(Size size) => (size.shortestSide / 760).clamp(0.6, 1.1);

  @override
  State<OpenSpaceView> createState() => _OpenSpaceViewState();
}

class _OpenSpaceViewState extends State<OpenSpaceView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_frame);
  final FocusNode _focus = FocusNode(debugLabel: 'open space floor');

  /// Where each person is drawn (eased towards where they said they stand), and each group's circle as drawn.
  final Map<String, Offset> _shown = {};
  final Map<String, double> _radius = {};
  Duration _last = Duration.zero;

  /// The floor and the call as one thing to listen to: made once for each floor, never anew at each drawing, so a
  /// floor let go of while this is still on the screen for a frame is not listened to again.
  late Listenable _both = Listenable.merge([widget.floor, widget.session]);

  /// The keys held that walk: which ways are wanted.
  final Set<LogicalKeyboardKey> _held = {};

  static final _left = {LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft};
  static final _right = {LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight};
  static final _up = {LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp};
  static final _down = {LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown};

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    widget.floor.addListener(_wake);
    _wake();
  }

  @override
  void didUpdateWidget(OpenSpaceView old) {
    super.didUpdateWidget(old);
    if (identical(old.floor, widget.floor)) return;
    old.floor.removeListener(_wake);
    widget.floor.addListener(_wake);
    _both = Listenable.merge([widget.floor, widget.session]);
    _shown.clear();
    _radius.clear();
    _wake();
  }

  /// Something on the floor changed: frames are drawn until everyone has reached where they stand ([_frame] stops them
  /// again), so a floor nobody is walking on costs nothing.
  void _wake() {
    if (_ticker.isActive || widget.floor.gone) return;
    _last = Duration.zero;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.floor.removeListener(_wake);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    // Not left walking into a wall by a key that was down as the view went.
    if (_held.isNotEmpty) widget.floor.head(0, 0);
    super.dispose();
  }

  /// Each frame: everyone eased towards where they stand, and the circles towards their size. Drawn again only while
  /// something is still on its way; once all have arrived the frames stop until the floor next changes ([_wake]).
  void _frame(Duration now) {
    if (widget.floor.gone) {
      _ticker.stop();
      return;
    }
    // A ticker's time starts at nothing each time it is started.
    final dt = _last == Duration.zero ? 1 / 60 : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final floor = widget.floor;
    // Closes most of the gap in a tenth of a second: smooth between words said ten times a second, never lagging far.
    final ease = 1 - math.exp(-dt * 14);
    var moved = false;
    final ids = floor.people;
    _shown.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      final at = floor.placeOf(id).at;
      final want = Offset(at.x, at.y);
      final had = _shown[id];
      // This device is drawn where it is: it is what the view is centred on.
      final next = had == null || id == OpenSpace.meId ? want : Offset.lerp(had, want, ease)!;
      if (had == null || (next - had).distanceSquared > 0.01) moved = true;
      _shown[id] = (next - want).distanceSquared < 0.25 ? want : next;
    }
    final groups = {for (final g in floor.groups) g.id};
    _radius.removeWhere((id, _) => !groups.contains(id));
    for (final id in groups) {
      final want = floor.radiusOf(id);
      final had = _radius[id];
      final next = had == null ? want : had + (want - had) * (1 - math.exp(-dt * 8));
      if (had == null || (next - had).abs() > 0.05) moved = true;
      _radius[id] = (next - want).abs() < 0.3 ? want : next;
    }
    if (!mounted) return;
    if (moved) {
      setState(() {});
    } else {
      _ticker.stop();
    }
  }

  void _focusChanged() {
    if (!_focus.hasFocus && _held.isNotEmpty) {
      _held.clear();
      widget.floor.head(0, 0);
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (!_left.contains(k) && !_right.contains(k) && !_up.contains(k) && !_down.contains(k)) return KeyEventResult.ignored;
    // With Ctrl, Alt or Cmd it is a command of the app's, not a step.
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) return KeyEventResult.ignored;
    if (e is KeyUpEvent) {
      _held.remove(k);
    } else {
      _held.add(k);
    }
    double way(Set<LogicalKeyboardKey> plus, Set<LogicalKeyboardKey> minus) => (_held.any(plus.contains) ? 1.0 : 0.0) - (_held.any(minus.contains) ? 1.0 : 0.0);
    widget.floor.head(way(_right, _left), way(_down, _up));
    return KeyEventResult.handled;
  }

  /// A group's name pressed: what can be done with it.
  void _groupMenu(SpaceGroup g) {
    final floor = widget.floor;
    showChoices(context, title: g.name, choices: [
      Choice('Walk there', Lucide.compass, () => floor.walkTo(g.at)),
      Choice('Rename', Lucide.pencil, () async {
        final name = await push<String>(context, (_) => _NameGroupPage(title: 'Rename group', start: g.name));
        if (name != null) floor.renameGroup(g.id, name);
      }),
      Choice('Move it here', LucideMore.move, () => floor.moveGroupHere(g.id), hint: 'Round where you stand now'),
      Choice('Remove', Lucide.trash2, () => floor.removeGroup(g.id), danger: true, hint: 'For everyone in the space'),
    ]);
  }

  /// New group pressed: a few ready names, or one of your own; made round where this device stands.
  void _newGroup() {
    final floor = widget.floor;
    if (floor.groups.length >= OpenWorld.mostGroups) {
      toast(context, 'This space has all the groups it can hold.');
      return;
    }
    void make(String name) {
      if (floor.addGroup(name) == null && mounted) toast(context, 'Couldn\'t make that group.');
    }

    showChoices(context, title: 'New group here', choices: [
      Choice('Game', LucideMore.gamepad, () => make('Game'), hint: 'A circle for whoever is playing'),
      Choice('Casual chat', LucideMore.messageCircle, () => make('Casual chat')),
      Choice('Movie night', Lucide.film, () => make('Movie night')),
      Choice('Name it yourself', Lucide.pencil, () async {
        final name = await push<String>(context, (_) => const _NameGroupPage(title: 'New group'));
        if (name != null) make(name);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final floor = widget.floor, session = widget.session;
    // The call was left a moment ago and the page has not gone yet.
    if (floor.gone) return const SizedBox.expand();
    final voice = Voice.instance;
    final room = voice.hangoutFor(session.channel);
    final levels = voice.media?.levels ?? session.media.levels;
    return ListenableBuilder(
      listenable: _both,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final scale = OpenSpaceView.scaleFor(size);
        final me = _shown[OpenSpace.meId] ?? Offset(floor.me.at.x, floor.me.at.y);
        // This device in the middle of what is seen above the dock.
        final centre = Offset(size.width / 2, (size.height - widget.bottomInset) / 2);
        Offset onScreen(Offset world) => centre + (world - me) * scale;
        final face = (56 * scale).clamp(40.0, 60.0);
        final groups = floor.groups;
        final people = floor.people;
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A press, or a finger dragged: walk to there. Also takes the keyboard back from the chat's box.
            onTapUp: (d) {
              _focus.requestFocus();
              final w = me + (d.localPosition - centre) / scale;
              floor.walkTo(Offset2(w.dx, w.dy));
            },
            onPanUpdate: (d) {
              final w = me + (d.localPosition - centre) / scale;
              floor.walkTo(Offset2(w.dx, w.dy));
            },
            child: ClipRect(
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FloorPainter(
                      me: me,
                      centre: centre,
                      scale: scale,
                      ground: t.color('app-paper'),
                      floor: t.color('app-paper-2'),
                      rule: t.color('app-rule'),
                      ink: t.color('app-ink-3'),
                      groups: [for (final g in groups) (at: Offset(g.at.x, g.at.y), radius: _radius[g.id] ?? floor.radiusOf(g.id), color: t.hueSwatch(g.hue), mine: floor.groupOf(OpenSpace.meId) == g.id)],
                    ),
                  ),
                ),
                // Each group's name over its circle, with how many are in it.
                for (final g in groups)
                  () {
                    final at = onScreen(Offset(g.at.x, g.at.y - (_radius[g.id] ?? floor.radiusOf(g.id))));
                    final n = floor.countIn(g.id);
                    return Positioned(
                      key: ValueKey('open-group-${g.id}'),
                      left: at.dx - 110,
                      top: at.dy - 34,
                      width: 220,
                      child: Center(child: _GroupName(name: g.name, count: n, color: t.hueSwatch(g.hue), onPress: () => _groupMenu(g))),
                    );
                  }(),
                // Everyone, this device last so it is on top.
                for (final id in [...people.where((id) => id != OpenSpace.meId), OpenSpace.meId])
                  () {
                    final mine = id == OpenSpace.meId;
                    final place = floor.placeOf(id);
                    final at = onScreen(_shown[id] ?? Offset(place.at.x, place.at.y));
                    final member = mine ? null : session.members[id];
                    // As they said they are called in this call; else as the app knows them.
                    final name = mine ? (session.name.isEmpty ? 'You' : session.name) : ((member?.name ?? '').isNotEmpty ? member!.name : voice.nameOf(id));
                    final heard = mine ? 1.0 : floor.gainOf(id);
                    final muted = mine ? (session.muted || session.deafened) : (member?.muted ?? false);
                    final picture = room == null ? Avatar(people: [Person(address: 'space:$id', name: name)], size: face, presence: false) : SpaceFace(room: room, id: mine ? room.me : id, name: name, size: face);
                    Widget figure = ValueListenableBuilder<Map<String, double>>(
                      valueListenable: levels,
                      builder: (context, loud, _) => widget.figure(context, OpenFigure(id: id, name: name, me: mine, size: face, level: loud[id] ?? 0, muted: muted, facing: place.facing, walking: place.walking, heard: heard), picture),
                    );
                    if (!mine) figure = LinkBadge(id: id, size: face, child: figure);
                    return Positioned(
                      key: ValueKey('open-person-$id'),
                      left: at.dx - 70,
                      top: at.dy - face / 2,
                      width: 140,
                      child: IgnorePointer(
                        ignoring: mine,
                        child: GestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          // Press and hold (or the other button) for what can be done about them, as in any call.
                          onLongPress: mine ? null : () => showPerson(context, session, id, name),
                          onSecondaryTap: mine ? null : () => showPerson(context, session, id, name),
                          child: Opacity(
                            // Fainter the less of them is heard from here; never gone, so they can be walked to.
                            opacity: 0.4 + 0.6 * heard,
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              figure,
                              SizedBox(height: t.space(1)),
                              _NameTag(name: mine ? 'You' : name, muted: muted),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }(),
                Positioned(
                  left: t.space(3),
                  top: t.space(3),
                  right: t.space(3),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _Pill(
                      child: Text(
                        Sms.computer ? (_focus.hasFocus ? 'Walk with W A S D or the arrow keys, or press where to go' : 'Press the floor, then walk with W A S D or the arrow keys') : 'Press where to go. The nearer someone is, the louder they are.',
                        style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2')),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: t.space(3),
                  bottom: t.space(3) + widget.bottomInset,
                  child: GestureDetector(
                    key: const ValueKey('open-new-group'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _newGroup,
                    child: _Pill(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppIcon(LucideMore.target, size: 16, color: t.color('app-ink')),
                        SizedBox(width: t.space(2)),
                        Text('New group', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

/// A small raised capsule over the floor: the hint, the New group button.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(999), border: Border.all(color: t.color('app-rule'))),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)), child: child),
    );
  }
}

/// A person's name under them, with a crossed microphone while theirs is off.
class _NameTag extends StatelessWidget {
  const _NameTag({required this.name, required this.muted});
  final String name;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(color: t.color('app-paper-3').withValues(alpha: 0.9), borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink')))),
          if (muted) Padding(padding: const EdgeInsets.only(left: 4), child: AppIcon(LucideMore.micOff, size: 11, wash: false, color: t.danger)),
        ]),
      ),
    );
  }
}

/// A group's name over its circle, in its colour, with how many are in it. Pressed for its menu.
class _GroupName extends StatelessWidget {
  const _GroupName({required this.name, required this.count, required this.color, required this.onPress});
  final String name;
  final int count;
  final Color color;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPress,
      child: DecoratedBox(
        decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(999), border: Border.all(color: color, width: 1.5)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: t.color('app-ink')))),
            SizedBox(width: t.space(2)),
            Text('$count', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: color)),
          ]),
        ),
      ),
    );
  }
}

/// The floor under everyone: its edge, a grid of dots to walk against, how far this device hears, and each group as a
/// target (a washed circle, its edge, and a ring and four marks inside it).
class _FloorPainter extends CustomPainter {
  _FloorPainter({required this.me, required this.centre, required this.scale, required this.ground, required this.floor, required this.rule, required this.ink, required this.groups});
  final Offset me, centre;
  final double scale;
  final Color ground, floor, rule, ink;
  final List<({Offset at, double radius, Color color, bool mine})> groups;

  Offset _at(Offset world) => centre + (world - me) * scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final edge = RRect.fromRectAndRadius(Rect.fromPoints(_at(Offset.zero), _at(const Offset(OpenWorld.width, OpenWorld.height))), Radius.circular(36 * scale));
    canvas.drawRRect(edge, Paint()..color = floor);
    canvas.drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = rule);
    // Dots every 80 of the floor's units, only those in sight.
    const step = 80.0;
    final dot = Paint()..color = ink.withValues(alpha: 0.22);
    final x0 = math.max(0.0, me.dx - centre.dx / scale), x1 = math.min(OpenWorld.width, me.dx + (size.width - centre.dx) / scale);
    final y0 = math.max(0.0, me.dy - centre.dy / scale), y1 = math.min(OpenWorld.height, me.dy + (size.height - centre.dy) / scale);
    for (var x = (x0 / step).ceil() * step; x <= x1; x += step) {
      for (var y = (y0 / step).ceil() * step; y <= y1; y += step) {
        canvas.drawCircle(_at(Offset(x, y)), 1.4, dot);
      }
    }
    for (final g in groups) {
      final c = _at(g.at), r = g.radius * scale;
      canvas.drawCircle(c, r, Paint()..color = g.color.withValues(alpha: g.mine ? 0.2 : 0.11));
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.mine ? 2.5 : 1.8
        ..color = g.color.withValues(alpha: g.mine ? 0.95 : 0.7);
      canvas.drawCircle(c, r, line);
      final faint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = g.color.withValues(alpha: 0.35);
      canvas.drawCircle(c, r * 0.55, faint);
      // A target's four marks, across its edge.
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * (r - 10 * scale), c + d * (r + 10 * scale), line);
      }
      canvas.drawCircle(c, 3, Paint()..color = g.color.withValues(alpha: 0.6));
    }
    // How far this device hears: whole inside the inner ring, nothing past the outer.
    final hear = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.18);
    canvas.drawCircle(centre, OpenWorld.far * scale, hear);
    canvas.drawCircle(centre, OpenWorld.near * scale, hear..color = ink.withValues(alpha: 0.28));
  }

  @override
  bool shouldRepaint(_FloorPainter old) => old.me != me || old.centre != centre || old.scale != scale || old.ground != ground || old.floor != floor || !_same(old.groups, groups);

  static bool _same(List<({Offset at, double radius, Color color, bool mine})> a, List<({Offset at, double radius, Color color, bool mine})> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A page for a group's name: New group's "Name it yourself", and Rename. Pops with the name, or with nothing.
class _NameGroupPage extends StatefulWidget {
  const _NameGroupPage({required this.title, this.start = ''});
  final String title;
  final String start;

  @override
  State<_NameGroupPage> createState() => _NameGroupPageState();
}

class _NameGroupPageState extends State<_NameGroupPage> {
  late final _name = TextEditingController(text: widget.start);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final words = _name.text.trim();
    Navigator.of(context).pop(words.isEmpty ? null : words);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GhostPage(
      title: widget.title,
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
          children: [
            PaneSection(title: 'Name', description: const Text('What the group is for: a game, a film, a quiet corner.'), children: [
              SettingRowBox(child: GlacierInput(controller: _name, placeholder: 'Group name', ariaLabel: 'Group name', autoFocus: true, autoCapitalize: TextCapitalization.sentences, size: GlacierFieldSize.md, onSubmitted: (_) => _done())),
            ]),
            SizedBox(height: t.space(6)),
            PaneSection(children: [
              SettingRow(key: const ValueKey('open-group-name-done'), icon: AppIcon(Lucide.check, size: 18), label: 'Done', onPress: _done),
            ]),
          ],
        ),
      ),
    );
  }
}
