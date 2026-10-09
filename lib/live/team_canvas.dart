/// A team's canvas in its view (docs/SHARED.md, S9): what `src/app/canvas/useTeamCanvas.ts` and `Pointers.tsx`
/// are to the web's `CanvasView`.
///
/// Drawn from and edited through its structure in the team's document (lib/team/doc.dart [TeamDoc.canvas]), so two
/// members' edits merge field by field: moving different cards, or typing in the same one, both keep what they
/// did. Every change still goes to the note, which writes the JSON and saves it. Where no member has made the
/// structure yet, another's may be on its way through the room, so the room is given its moment before this
/// device seeds one from the words. Over the cards, the other members' pointers: a small arrow in each one's
/// colour with their handle beside it, at the pointer's place in the canvas's own pixels and the same size on the
/// screen at any zoom; and this device's finger said in the room for theirs, at most every [pointerEvery].
///
/// What differs from the page:
/// - The view here is handed the note's body and hands one back (lib/canvas/canvas_view.dart), so the team's
///   canvas is put into the body it is handed and read out of the one it hands back, where the page's view takes
///   the canvas itself. A change that arrives while a card is being dragged is the body handed in anew.
/// - **While it is open the document is the view's** ([TeamDoc.editing], as a note's is its editor's): what
///   arrives is saved to the note from here, and a pass does not read the note's saved words back into the types.
/// - A phone has no pointer at rest: this device's is where a finger is down, and nowhere once it lifts.
/// - The card a member has open (`card` in the room) is not said or drawn.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:glacier/glacier.dart';

import '../canvas/camera.dart';
import '../canvas/json_canvas.dart';
import 'editor_binding.dart' show memberColour;
import 'open.dart';
import 'presence.dart';
import 'team.dart';

/// How often at most the room hears where this pointer is (`POINTER_EVERY_MS`).
const Duration pointerEvery = Duration(milliseconds: 80);

/// Another member on this canvas, as the note's room has them (`Other`).
@immutable
class CanvasOther {
  const CanvasOther({required this.client, required this.name, required this.hue, required this.pointer});
  final int client;
  final String name;
  final String? hue;
  final Spot? pointer;
}

/// The other members on a canvas, read from its room (`useOthers`).
List<CanvasOther> canvasOthers(TeamRoom? room) => [
      if (room != null)
        for (final MapEntry(key: client, value: said) in room.states.entries)
          if (client != room.clientId && Me.of(said['user']) != null) CanvasOther(client: client, name: Me.of(said['user'])!.name, hue: Me.of(said['user'])!.hue, pointer: Spot.of(said['pointer'])),
    ];

/// A team's canvas round the view [draw] builds: handed the body to draw and the way to write it.
class TeamCanvasHost extends StatefulWidget {
  const TeamCanvasHost({super.key, required this.team, required this.body, required this.onChange, required this.draw});

  final TeamBinding team;

  /// The note's body as its screen has it, and the way to write it (the note's own save).
  final String body;
  final ValueChanged<String>? onChange;

  /// The canvas's view, over a camera this host reads for the pointers.
  final Widget Function(BuildContext context, String body, ValueChanged<String>? onChange, CanvasCamera camera) draw;

  @override
  State<TeamCanvasHost> createState() => _TeamCanvasHostState();
}

class _TeamCanvasHostState extends State<TeamCanvasHost> {
  late final CanvasCamera _camera = CanvasCamera(canvasOf(widget.body) ?? Canvas(nodes: const [], edges: const []));
  void Function()? _stopCanvas;
  void Function()? _stopRoom;
  Canvas? _shown;
  bool _gone = false;
  Timer? _saying;
  Spot? _latest;

  @override
  void initState() {
    super.initState();
    final team = widget.team;
    team.doc.editing = true;
    _camera.addListener(_redraw);
    _stopRoom = team.room?.onChange(_redraw);
    unawaited(() async {
      // No structure yet: another member's may be on its way through the room.
      if (team.doc.canvas == null) await team.room?.caughtUp();
      if (_gone) return;
      final made = await team.doc.seedCanvas();
      if (_gone) return;
      _stopCanvas = team.doc.onCanvas(_arrived);
      if (made != null) _arrived(made);
    }().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _gone = true;
    widget.team.doc.editing = false;
    _saying?.cancel();
    _stopCanvas?.call();
    _stopRoom?.call();
    _camera
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  /// The camera moved, or the room's people did: the pointers are drawn where they are now. The view opens the
  /// camera on a body handed to it anew (another member's change), which is while this host is itself being
  /// built: a redraw asked for then waits for the frame to end, where asking at once left the host dirty inside
  /// its own build and the canvas an error (seen on the emulator, the first time a second member joined a canvas
  /// with a card being written).
  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// The types changed, here or by another member: drawn, and written to the note where its words differ.
  void _arrived(Canvas canvas) {
    if (!mounted) return;
    setState(() => _shown = canvas);
    if (canvasOf(widget.body) != canvas) widget.onChange?.call(withCanvas(widget.body, canvas));
  }

  /// The view's next canvas: into the types as only what differs, and to the note.
  void _changed(String next) {
    final canvas = canvasOf(next);
    if (canvas != null) {
      _shown = canvas;
      unawaited(widget.team.doc.applyCanvas(canvas).catchError((Object _) {}));
    }
    widget.onChange?.call(next);
  }

  /// This device's pointer, said in the room (`useSaying`): in the canvas's pixels, or nowhere.
  void _say(Offset? at) {
    final room = widget.team.room;
    if (room == null) return;
    if (at == null) {
      _saying?.cancel();
      _saying = null;
      _latest = null;
      room.setField('pointer', null);
      return;
    }
    final spot = _camera.under(at.dx, at.dy);
    _latest = Spot(spot.x.roundToDouble(), spot.y.roundToDouble());
    _saying ??= Timer(pointerEvery, () {
      _saying = null;
      room.setField('pointer', _latest?.toJson());
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final body = shown == null ? widget.body : withCanvas(widget.body, shown);
    final view = _camera.view;
    final t = context.tokens;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _say(event.localPosition),
      onPointerMove: (event) => _say(event.localPosition),
      onPointerUp: (_) => _say(null),
      onPointerCancel: (_) => _say(null),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.draw(context, body, widget.onChange == null ? null : _changed, _camera),
          // Over the cards, and taking no taps.
          for (final other in canvasOthers(widget.team.room))
            if (other.pointer case final at?)
              Positioned(
                left: at.x * view.scale + view.x,
                top: at.y * view.scale + view.y,
                child: IgnorePointer(child: CanvasPointer(name: other.name, colour: memberColour(t, other.hue), paper: t.color('app-paper'), label: t.textAt(t.fontSize('xs'), weight: 'medium'))),
              ),
        ],
      ),
    );
  }
}

/// One member's pointer: `Pointers.tsx`'s arrow (`M1.5 1 L14.5 7.5 L8.5 9.2 L5.2 15 Z`, sixteen pixels) in their
/// colour, their handle beside it on that colour.
class CanvasPointer extends StatelessWidget {
  const CanvasPointer({super.key, required this.name, required this.colour, required this.paper, required this.label});

  final String name;
  final Color colour;
  final Color paper;
  final TextStyle label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        CustomPaint(size: const Size(16, 16), painter: _ArrowPainter(colour, paper)),
        DecoratedBox(
          decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), child: Text(name, style: label.copyWith(color: paper), textScaler: TextScaler.noScaling)),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.colour, this.paper);
  final Color colour;
  final Color paper;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final arrow = Path()
      ..moveTo(1.5, 1)
      ..lineTo(14.5, 7.5)
      ..lineTo(8.5, 9.2)
      ..lineTo(5.2, 15)
      ..close();
    canvas.drawPath(arrow, Paint()..color = colour);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.colour != colour || old.paper != paper;
}
