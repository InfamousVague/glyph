/// A canvas drawn (docs/CANVAS.md): cards where the file puts them, lines between them, an infinite page under it
/// all that two fingers or a trackpad move and pinch. A port of `src/app/canvas/CanvasView.tsx` with its
/// stylesheet's page and toolbar, `LineWords.tsx`, `Remove.tsx` and `CommentMarks.tsx`.
///
/// The drawing is one render object, the world (world.dart), which the camera moves and scales (camera.dart): the
/// cards sit at their own pixel positions inside it (card.dart), the lines are painted over them in the same
/// pixels (paint.dart), and the picked card's ring, handles and bar are in it too, held to one size on the screen
/// (selection.dart). What the fingers do is gestures.dart. This file holds the canvas as it is being changed, the
/// edits, and the page they are drawn on.
///
/// What a person can do is the web's, slice for slice: a double-tap on the page makes a card of words there, open
/// with the keyboard up; a press held on a card lifts it; a tap picks a card and the next opens it; the Line tool
/// turns the next two taps into a line, and a tap on a line picks it to be written on or taken off; the + is a
/// sheet (add_sheet.dart); a tap on a card's title zooms to it, Shift+1 fits the canvas and Shift+2 goes to the
/// card; Delete, the arrows, Escape and Ctrl or Cmd+D; and the magnet (the preference `canvasSnap`) lands what is
/// moved, resized, nudged or made on the dots, with a tick. Without `onChange` the canvas is read-only, and a tap
/// opens a note card or a link.
///
/// What differs from the web:
/// - **It is handed the note's body**, and hands back the body ([CanvasView.body], [CanvasView.onChange]), which is
///   what lib/note's seam passes (`NoteSeams.canvas`); the web's took a `Canvas` its note screen had read. A body
///   that comes back as this wrote it is its own echo; any other is the note reloaded, and the view is fitted again.
/// - **Taps and what is under a press** are worked out here from the canvas's geometry (`_hit`, `_tap`), where the
///   web let the browser find an element and click it. The order of what a tap does is the web's `onClickCapture`,
///   then the card's own `onClick`, then `onClick`.
/// - **A canvas's threads are kept through an edit.** edits.dart's `withNode`, `withEdge`, `movedWithHeld` and the
///   rest answer a canvas without its `comments`, as the web's do; there, a card moved on a canvas with threads
///   writes the note without them. Here `_change` puts back the threads whose cards are still there.
/// - **Comments** draw their rounds and their button and hand the rest to [CanvasView.threads], which
///   canvas_comments.dart answers with the note's own sheet (`useCanvasComments.tsx`): lib/canvas knows neither an
///   account nor an organization, which a comment's author and colour want.
/// - **A team's canvas** is a host round this view (lib/live/team_canvas.dart, piece 6G): it draws the other
///   members' pointers over it, and is told the card being written in ([CanvasView.onEditing]) and asked who has
///   which card open ([CanvasView.editedBy]), where the page's view read the note's room itself.
/// - **Not here:** a note dragged in from the sidebar or a picture file dropped from the computer (`onDrop`: there
///   is no drag between widgets of that kind yet); `videos`.
/// - The keys are the canvas's while it has the keyboard's focus, which a press on it gives it; the web listened on
///   the window and looked at what was focused.
/// - **On a page with a dock** (lib/shell/page_dock.dart) the canvas offers it its own Add a card and Fit, beside the
///   toolbar's, and its map stands to the dock's start rather than under it.
library;

import 'dart:ui' as ui show Canvas;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart' show LucideIcon;
import '../art/ghost.dart';
import '../art/lucide.g.dart';
import '../core/images.dart';
import '../core/link_preview.dart' show LinkOpener;
import '../core/preferences.dart';
import '../editor/input/felt.dart' show fireFelt;
import '../home/home_icons.dart' show HomeGlyph;
import '../shell/page_dock.dart';
import '../perf/frame_log.dart';
import '../sheet/css.dart' show pageText;
import 'add_sheet.dart';
import 'camera.dart';
import 'card.dart';
import 'card_looks.dart';
import 'comments.dart';
import 'edits.dart';
import 'geometry.dart';
import 'gestures.dart';
import 'json_canvas.dart';
import 'minimap.dart';
import 'paint.dart';
import 'selection.dart';
import 'viewport.dart';
import 'world.dart';

export 'card.dart' show CanvasWiki;

/// Two taps this close in time and place are a double-tap: a new card on the page (`DOUBLE_MS`, `DOUBLE_PX`).
const int doubleMs = 350;
const double doublePx = 24;

/// How much closer, or further, one press of a zoom button goes (`ZOOM_STEP`).
const double zoomStep = 1.3;

/// The room a picked card's bar needs over the card, in screen pixels; with less, the bar goes under the card.
const double barRoom = 64;

/// How far off the screen a card's words are made, in screen pixels (`NEAR_PX`, Near.tsx).
const double nearPx = 300;

/// Another member with a card open: their handle and the colour they wear.
typedef CardEditor = ({String name, Color colour});

/// A canvas's threads, asked for: [start] a new one on a card (Comment, on its bar), or a card's threads opened
/// (its round). Handed the canvas as it is and the way to change it.
typedef CanvasThreads = void Function(BuildContext context, {required Canvas canvas, required String node, required bool start, required void Function(Canvas next) change});

/// A test's word on the screen's own pointer, where that is not the platform's a test runs as: the page's desktop
/// rectangles were read with a mouse for its pointer (`@media (pointer: coarse)` not met), and a test is a phone.
@visibleForTesting
bool? debugCanvasCoarse;

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.body,
    this.onChange,
    this.wiki,
    this.pictures,
    this.pickPicture,
    this.openLink,
    this.threads,
    this.threadHue,
    this.preferences,
    this.camera,
    this.felt,
    this.goTo,
    this.onEditing,
    this.editedBy,
    this.team = false,
  });

  /// The note's body: front matter that names it, then the canvas's JSON.
  final String body;

  /// The body after a change - a card moved, made, written in or taken off. Absent, the canvas cannot be changed.
  final ValueChanged<String>? onChange;
  final CanvasWiki? wiki;

  /// Where a picture card's picture is drawn from (core/images.dart).
  final PictureStore? pictures;

  /// Lets the person choose a picture and keeps it (`pickImage`); the + sheet's "A picture".
  final PicturePicker? pickPicture;

  /// Opens a web address in the phone's browser (`openLink`).
  final LinkOpener? openLink;

  /// The comment sheet, where there is one; without it a card's bar has no Comment and no round is drawn.
  final CanvasThreads? threads;

  /// The hue a member's round wears, by handle (core/comments/colours.ts `of`): one of the page's hues, or `ink`.
  final String Function(String handle)? threadHue;

  /// Where `canvasSnap` is read and kept; the app's own when null.
  final PreferencesStore? preferences;

  /// The tick a card makes landing on a new dot; the app's own motor when null (`fireFelt('selection')`).
  final VoidCallback? felt;

  /// A spot to centre on, from an organization's dashboard's Jump to cursor: a member's pointer (`goTo`).
  final Point? goTo;

  /// The card being written in, as it opens and closes: what a team's canvas says of this device in the note's
  /// room (`useSaying`'s `card`). Told once the frame that changed it is drawn.
  final ValueChanged<String?>? onEditing;

  /// Another member writing in a card (docs/SHARED.md, S9): who, and their colour, for the ring and the handle on
  /// its corner; null for a card nobody else has open.
  final CardEditor? Function(String nodeId)? editedBy;

  /// A team's canvas: its structure changes with every member's edit, and a view is not refitted for a card moved
  /// (CanvasView.tsx `if (!team) setOpened(canvas)`). It is fitted as it opens, and by its own Fit.
  final bool team;

  /// The camera, for a host that wants to move the view or a test that reads it; the view's own when null.
  final CanvasCamera? camera;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

/// The canvas as lib/note's seam takes it (`NoteSeams.canvas`): handed the note's body and the way to write it.
/// [readOnly] is a note that cannot change (one in the Trash): drawn, and its cards open on a tap. [camera] is a
/// host's own, which it reads (a team's canvas draws the other members' pointers by it, lib/live/team_canvas.dart).
Widget Function(BuildContext context, String body, ValueChanged<String> onChange) canvasSeam({
  CanvasWiki? wiki,
  PictureStore? pictures,
  PicturePicker? pickPicture,
  LinkOpener? openLink,
  CanvasThreads? threads,
  String Function(String handle)? threadHue,
  bool readOnly = false,
  CanvasCamera? camera,
  Point? goTo,
  ValueChanged<String?>? onEditing,
  CardEditor? Function(String nodeId)? editedBy,
  bool team = false,
}) =>
    (context, body, onChange) => CanvasView(
          body: body,
          onChange: readOnly ? null : onChange,
          wiki: wiki,
          pictures: pictures,
          pickPicture: pickPicture,
          openLink: openLink,
          threads: threads,
          threadHue: threadHue,
          camera: camera,
          goTo: goTo,
          onEditing: onEditing,
          editedBy: editedBy,
          team: team,
        );

class CanvasViewState extends State<CanvasView> {
  static final Canvas _empty = Canvas(nodes: const [], edges: const []);

  /// The canvas as the note last had it, and as it is being changed: with a card part-way through a drag.
  late Canvas _canvas = canvasOf(widget.body) ?? _empty;
  late Canvas _live = _canvas;

  /// The body this last wrote: handed back, it is not the note reloaded.
  String? _wrote;

  /// The card of words open to be written in, or the group whose name is, by id.
  String? _editing;

  /// Drawing a line: waiting for its first card (`from` null), or for its second.
  ({String? from})? _lining;

  /// The line picked by a tap, by id.
  String? _picked;

  /// The + sheet, and the step it is at.
  AddStep? _adding;

  /// The card picked, by id: it wears the ring, the handles and the bar.
  String? _chosen;
  bool _mapBig = false;

  /// The cards whose words have been made: near the screen now, or once.
  final Set<String> _made = <String>{};
  bool _below = false;

  /// The screen's own pointer is a finger (`@media (pointer: coarse)`, Selection.module.css: a finger has the four
  /// corners, a little larger). The screen's, not the last press's: a phone's page answers by its touch screen with
  /// a mouse joined to it too (shell/wide_screen.dart `mousePointer` says how that was asked), so a mouse on a phone
  /// keeps the four corners, where the last press's kind gave it eight.
  final bool _coarse = debugCanvasCoarse ?? (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// The last tap on open canvas, for telling a double-tap.
  ({Duration at, double x, double y})? _lastTap;
  final Stopwatch _clock = Stopwatch()..start();

  /// Pointers that landed on something of the canvas's that takes its own presses: not the page's.
  final Set<int> _owned = <int>{};
  final FocusNode _focus = FocusNode(debugLabel: 'canvas');

  CanvasCamera? _ownCamera;
  late CanvasCamera _camera = widget.camera ?? (_ownCamera = CanvasCamera(_canvas));
  late final CanvasGestures _gestures = CanvasGestures(
    camera: _camera,
    live: () => _live,
    editable: () => _editable,
    selected: () => _chosen,
    snap: () => _snap,
    hitAt: _hit,
    onPress: () {
      if (_mapBig) setState(() => _mapBig = false);
    },
    onCarry: (next) => setState(() => _live = next),
    // A card put down is the card picked: carried by a hold or by a drag, it is the one in hand. One that was
    // only held and let go where it was is picked and nothing is written.
    onPutDown: (next, id, moved) {
      if (moved) {
        _change(next);
      } else {
        _live = _canvas;
      }
      setState(() {
        _chosen = id;
        _picked = null;
      });
    },
    onTap: _tap,
    onLifted: (_) => setState(() {}),
    felt: _felt,
  );

  void _felt() => (widget.felt ?? () => fireFelt('selection'))();

  /// Each card as it was built last, and what it was built from: a card built again from the same of it is handed
  /// back as it was, so a card carried, a card written in or a line picked builds that one card and no other, and
  /// the note's screen building this again for a letter typed builds only the card it was typed in. The edits keep
  /// every node they do not change as the very node it was (edits.dart), which is what is asked. A card that is a
  /// note is drawn from that note too, so it is asked after each time: whether there is one, and its words.
  final Map<String, ({CanvasNode node, int worn, Tokens tokens, PictureStore? pictures, bool known, String? words, List<Widget> drawn})> _cards = {};

  List<Widget> _card(BuildContext context, Tokens t, CanvasNode node, {required bool editable}) {
    final near = _made.contains(node.id), editing = _editing == node.id, lifted = _gestures.lifted == node.id;
    final selected = editable && _chosen == node.id, lineFrom = _lining?.from == node.id;
    final worn = (near ? 1 : 0) | (editable ? 2 : 0) | (editing ? 4 : 0) | (lifted ? 8 : 0) | (selected ? 16 : 0) | (lineFrom ? 32 : 0) | (widget.wiki == null ? 0 : 64);
    final wiki = widget.wiki;
    // What a note's card reads of the library (card.dart `_FileWords`).
    var known = false;
    String? words;
    if (wiki != null && node.type == NodeType.file && !isImageFile(node.file)) {
      final title = fileTitle(node.file);
      known = wiki.known(title);
      words = known ? wiki.body?.call(title) : null;
    }
    final had = _cards[node.id];
    if (had != null && had.worn == worn && identical(had.tokens, t) && identical(had.pictures, widget.pictures) && had.known == known && identical(had.words, words)) {
      if (identical(had.node, node)) return had.drawn;
      // The same card somewhere else (a card carried is another node at every move of the finger): the box it had,
      // set down at its new place. Nothing of it is built, laid out or painted again; the world sets its layer
      // down where it now stands. A group is built again: its name stands beside it, measured from its corner.
      if (!node.isGroup && had.drawn.length == 1 && node.movedFrom(had.node)) {
        final was = had.drawn.single as Placed;
        if (ghostPerf) Perf.count('canvas.card.moved');
        final drawn = <Widget>[Placed(key: was.key, at: Offset(node.x, node.y), size: was.size, child: was.child)];
        _cards[node.id] = (node: node, worn: worn, tokens: t, pictures: widget.pictures, known: known, words: words, drawn: drawn);
        return drawn;
      }
    }
    if (ghostPerf) Perf.count('canvas.card.made');
    final drawn = CanvasCard(
      node: node,
      wiki: widget.wiki,
      pictures: widget.pictures,
      near: near,
      editable: editable,
      editing: editing,
      lifted: lifted,
      selected: selected,
      lineFrom: lineFrom,
      onWrite: editable ? _writeCard : null,
      onName: editable ? _nameGroup : null,
      own: _own,
      camera: _camera,
    ).build(context);
    _cards[node.id] = (node: node, worn: worn, tokens: t, pictures: widget.pictures, known: known, words: words, drawn: drawn);
    return drawn;
  }

  List<DrawnLine>? _lines;
  Canvas? _linesOf;

  /// The canvas's lines, worked out together and once for each canvas drawn.
  List<DrawnLine> get lines {
    if (!identical(_linesOf, _live)) {
      final was = _linesOf;
      _linesOf = _live;
      // The same cards in the same places joined by the same lines (a letter written in a card, a card's colour):
      // the lines are the lines they were, the very list, so they are neither worked out nor painted again. Each
      // letter typed in a card routed every line afresh and drew them all.
      if (was != null && _lines != null && _sameShape(was, _live)) return _lines!;
      final began = ghostPerf ? Perf.now() : 0;
      _lines = drawnLines(_live);
      if (ghostPerf) Perf.add('canvas.lines', began);
    }
    return _lines!;
  }

  /// Whether two canvases have the same lines between boxes that stand where they stood.
  static bool _sameShape(Canvas a, Canvas b) {
    if (a.nodes.length != b.nodes.length || a.edges.length != b.edges.length) return false;
    for (var i = 0; i < a.edges.length; i += 1) {
      if (!identical(a.edges[i], b.edges[i])) return false;
    }
    for (var i = 0; i < a.nodes.length; i += 1) {
      final was = a.nodes[i], now = b.nodes[i];
      if (identical(was, now)) continue;
      if (was.id != now.id || was.x != now.x || was.y != now.y || was.width != now.width || was.height != now.height) return false;
    }
    return true;
  }

  PreferencesStore get _prefs => widget.preferences ?? preferences;
  bool get _editable => widget.onChange != null;
  bool get _snap => _prefs.value.canvasSnap;

  /// The camera, the canvas as drawn and what is picked, open or lifted: for a host, and for tests.
  CanvasCamera get camera => _camera;
  Canvas get live => _live;
  String? get chosen => _chosen;
  String? get editing => _editing;
  String? get pickedLine => _picked;
  String? get lifted => _gestures.lifted;
  bool get mapBig => _mapBig;

  /// Whether the picked card's bar is under it rather than over it.
  bool get debugBarBelow => _below;

  /// `from` while the Line tool waits for its first card, `to` for its second; null when it is put down.
  String? get lining => _lining == null ? null : (_lining!.from == null ? 'from' : 'to');
  String? get liningFrom => _lining?.from;

  @override
  void initState() {
    super.initState();
    _camera.open(_canvas);
    _camera.addListener(_moved);
    _prefs.addListener(_redraw);
    _centreOnSpot();
  }

  /// Jump to cursor from the dashboard: the screen centred on the member's pointer, at the scale it is at. Once
  /// the frame is drawn, since the screen's size is the camera's only then.
  void _centreOnSpot() {
    if (widget.goTo == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final spot = widget.goTo;
      if (mounted && spot != null) _camera.centreOn(spot);
    });
  }

  /// The card being written in, last told to whoever asked ([CanvasView.onEditing]).
  String? _toldEditing;

  @override
  void didUpdateWidget(CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preferences, widget.preferences)) {
      (oldWidget.preferences ?? preferences).removeListener(_redraw);
      _prefs.addListener(_redraw);
    }
    if (!identical(oldWidget.camera, widget.camera) && widget.camera != null) {
      _camera.removeListener(_moved);
      _camera = widget.camera!..addListener(_moved);
      // The cards kept were built for the camera there was.
      _cards.clear();
    }
    if (widget.goTo != oldWidget.goTo) _centreOnSpot();
    // The note reloaded: its canvas is the canvas, and the view is fitted to it again (not a team's, whose every
    // member's edit comes this way). What this wrote, handed back, is not that.
    if (widget.body != oldWidget.body && widget.body != _wrote) {
      _canvas = canvasOf(widget.body) ?? _empty;
      _live = _canvas;
      if (!widget.team) _camera.open(_canvas);
    }
  }

  @override
  void dispose() {
    _camera.removeListener(_moved);
    _prefs.removeListener(_redraw);
    _gestures.dispose();
    _ownCamera?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// The view moved: a card's words are made when it comes near, and the picked card's bar goes over or under.
  void _moved() {
    if (!mounted) return;
    if (_takeNear() || _barBelow() != _below) setState(() {});
  }

  /// Marks the cards near the screen as made; whether any was new.
  bool _takeNear() {
    final view = _camera.view;
    if (_camera.width <= 0 || _camera.height <= 0) return false;
    final room = nearPx / view.scale;
    final seen = shown(view, _camera.width, _camera.height);
    var grew = false;
    for (final node in _live.nodes) {
      if (node.isGroup || _made.contains(node.id)) continue;
      final near = node.x < seen.x + seen.width + room && seen.x - room < node.x + node.width && node.y < seen.y + seen.height + room && seen.y - room < node.y + node.height;
      if (near) grew = _made.add(node.id) || grew;
    }
    return grew;
  }

  CanvasNode? get _picking => _live.nodeOf(_chosen);

  /// The picked card's ring, handles and bar: not while it is carried, nor while a line is being drawn from it.
  CanvasNode? get _wearing {
    final picking = _picking;
    return _editable && picking != null && _lining == null && _gestures.lifted != picking.id ? picking : null;
  }

  /// Its bar goes under it when its top is too near the top of the screen for a bar to fit over it.
  bool _barBelow() {
    final wearing = _wearing;
    return wearing != null && wearing.y * _camera.view.scale + _camera.view.y < barRoom;
  }

  // ---- changes ---------------------------------------------------------------------------------

  /// A change: drawn, and handed to the note as its body. The threads on cards still there are kept (see the
  /// header).
  void _change(Canvas next) {
    // From the canvas as the note has it: the one drawn may be a card part-way through a drag, made by an edit.
    final threads = _canvas.comments;
    if (next.comments == null && threads != null) {
      final kept = [
        for (final thread in threads)
          if (next.nodeOf(thread.node) != null) thread,
      ];
      if (kept.isNotEmpty) next = Canvas(nodes: next.nodes, edges: next.edges, comments: kept);
    }
    _threaded(next);
  }

  /// A change that is the threads' own: handed on as it is.
  void _threaded(Canvas next) {
    setState(() {
      _live = next;
      _canvas = next;
    });
    final tell = widget.onChange;
    if (tell == null) return;
    final body = withCanvas(_wrote ?? widget.body, next);
    _wrote = body;
    tell(body);
  }

  /// A new card on the canvas, picked, and open to be written in when it is one to write in. Nothing for no card.
  void _place(CanvasNode? card, bool open) {
    if (card == null) return;
    // On a dot, with the magnet on; and never exactly on a card already there.
    final dot = _snap ? atDot(card.x, card.y) : (x: card.x, y: card.y);
    final at = clearSpot(_live, dot.x, dot.y);
    final set = card.put({'x': at.x, 'y': at.y});
    _made.add(set.id);
    _change(withNode(_live, set));
    setState(() {
      _chosen = set.id;
      _picked = null;
      _editing = open ? set.id : null;
    });
  }

  /// A new card of words centred on a point of the canvas, open to be written in.
  void addCard(Point at) => _place(newTextNode(at.x - newCard.width / 2, at.y - newCard.height / 2), true);

  void addNoteCard(String title, [Point? where]) {
    final at = where ?? _camera.middle();
    _place(newFileNode(title, at.x - newCard.width / 2, at.y - 80), false);
  }

  /// A card of words that starts as something: a chart, a table. Open to be written in at once.
  void _addStartedCard(String text) {
    final at = _camera.middle();
    _place(newTextNode(at.x - newCard.width / 2, at.y - 90).put({'text': text, 'height': 180.0}), true);
  }

  void addPictureCard(String name, [Point? where]) {
    final at = where ?? _camera.middle();
    _place(newPictureNode(name, at.x - newCard.width / 2, at.y - 100), false);
  }

  /// A picture chosen from the phone, kept the way a note's pictures are kept, then a card of it.
  Future<void> _addPicture() async {
    final name = await widget.pickPicture?.call();
    if (name != null && mounted) addPictureCard(name);
  }

  void _addLinkCard(String url) {
    final at = _camera.middle();
    _place(newLinkNode(url, at.x - newCard.width / 2, at.y - 50), false);
  }

  /// A new group: about the picked card when there is one, else a box mid-screen. Its name is open to be written.
  void _addGroup() {
    final picking = _picking;
    final about = picking != null && !picking.isGroup ? picking : null;
    final middle = _camera.middle();
    final corner = (x: middle.x - newGroup.width / 2, y: middle.y - newGroup.height / 2);
    final at = _snap ? atDot(corner.x, corner.y) : corner;
    final group = newGroupNode(about, at.x, at.y);
    _change(withGroup(_live, group));
    setState(() {
      _chosen = group.id;
      _picked = null;
      _editing = group.id;
    });
  }

  /// Zoom to a card: the view fitted to its box, no larger than life.
  void zoomTo(String id) {
    final node = _live.nodeOf(id);
    if (node != null) _camera.zoomToBox(node);
  }

  void _removeCard(String id) {
    if (_editing == id) _editing = null;
    if (_chosen == id) _chosen = null;
    _change(withoutNode(_live, id));
  }

  void _copyCard(String id) {
    final node = _live.nodeOf(id);
    if (node == null) return;
    final copy = duplicated(_live, node);
    _made.add(copy.id);
    _change(node.isGroup ? withGroup(_live, copy) : withNode(_live, copy));
    setState(() {
      _editing = null;
      _chosen = copy.id;
    });
  }

  void _writeCard(String id, String text) {
    final node = _live.nodeOf(id);
    if (node != null && node.type == NodeType.text && node.text != text) _change(withNode(_live, node.put({'text': text})));
  }

  /// While a handle is dragged the card is drawn at its size; the canvas is handed on when the handle is let go.
  void _previewSize(CanvasNode sized) {
    if (_live.nodeOf(sized.id) != null) setState(() => _live = withNode(_live, sized));
  }

  void _resizeCard(CanvasNode sized) {
    if (_live.nodeOf(sized.id) != null) _change(withNode(_live, sized));
  }

  void _nameGroup(String id, String label) {
    if (!mounted) return;
    final node = _live.nodeOf(id);
    if (node != null && node.isGroup && (node.label ?? '') != label.trim()) _change(withNode(_live, labelledGroup(node, label)));
  }

  void _colourCard(String id, String? color) {
    final node = _live.nodeOf(id);
    if (node != null && node.color != color) _change(withNode(_live, colouredNode(node, color)));
  }

  void _labelLine(String id, String words) {
    if (!mounted) return;
    for (final line in _live.edges) {
      if (line.id == id) return _change(withEdge(_live, labelledEdge(line, words)));
    }
  }

  void _removeLine(String id) {
    if (_picked == id) _picked = null;
    _change(withoutEdge(_live, id));
  }

  /// Open what a card stands for: a note by its title, an address in the phone's browser.
  void _openCard(CanvasNode node) {
    if (node.type == NodeType.link) {
      widget.openLink?.call(node.url);
    } else if (node.type == NodeType.file) {
      final at = node.subpath;
      widget.wiki?.open(fileTitle(node.file), at?.substring(1));
    }
  }

  // ---- what is under a press, and what a tap does ----------------------------------------------

  /// What is at a point of the canvas's own box: the line, else the topmost card or group.
  CanvasHit _hit(double x, double y) {
    final view = _camera.view;
    final p = _camera.under(x, y);
    bool inside(Box box) => p.x >= box.x && p.x < box.x + box.width && p.y >= box.y && p.y < box.y + box.height;
    if (_editable) {
      final line = lineAt(lines, p.x, p.y);
      if (line != null) return CanvasHit(line: line);
    }
    final t = context.tokens;
    for (final node in _live.nodes.reversed) {
      if (node.isGroup) {
        final name = groupNameBox(t, node, editable: _editable, selected: _editable && _chosen == node.id);
        if (name != null && inside(name)) return CanvasHit(node: node, grip: true, name: true);
        if (!inside(node)) continue;
        // Its border, a finger's width of it on the screen.
        final reach = borderPx / view.scale;
        final border = p.x - node.x < reach || node.x + node.width - p.x < reach || p.y - node.y < reach || node.y + node.height - p.y < reach;
        return CanvasHit(node: node, grip: border);
      }
      if (!inside(node)) continue;
      final title = cardTitleBox(t, node);
      return CanvasHit(node: node, title: title != null && inside(title));
    }
    return const CanvasHit();
  }

  /*
   * A tap picks the card under it and lets go of whatever was open. A tap on the card already picked opens it: a
   * card of words to be written in, a group's name when the tap was on the name, a note and an address where they
   * go. A second tap close on the heels of the first, on the page or on a group's ground, makes a new card of
   * words there, open to be written in. While a line is being drawn a tap on a card is the line's. On a canvas
   * that cannot change, a tap opens a card as it did.
   */
  void _tap(double x, double y, CanvasHit hit) {
    final node = hit.node;
    final lining = _lining;
    if (lining != null) {
      if (node == null || node.isGroup) return;
      if (lining.from == null) {
        setState(() => _lining = (from: node.id));
      } else if (node.id != lining.from && !joined(_live, lining.from!, node.id)) {
        final line = newEdge(lining.from!, node.id);
        _change(withEdge(_live, line));
        setState(() {
          _lining = null;
          _picked = line.id;
          _chosen = null;
        });
      }
      return;
    }
    final opens = node != null && (node.type == NodeType.link || (node.type == NodeType.file && !isImageFile(node.file)));
    if (!_editable) {
      // A canvas to read: the card last tapped is what Shift+2 goes to, and a tap on its title zooms to it.
      if (node != null && node.id != _chosen) setState(() => _chosen = node.id);
      if (node != null && hit.title) {
        zoomTo(node.id);
      } else if (opens) {
        _openCard(node);
      }
      return;
    }
    // The first tap on a note or an address picks it, so it only opens from the card already picked.
    if (node != null && node.id != _chosen && (node.type == NodeType.link || node.type == NodeType.file)) {
      setState(() {
        _chosen = node.id;
        _editing = null;
        _picked = null;
        _lastTap = null;
      });
      return;
    }
    final was = _chosen;
    setState(() {
      _chosen = node?.id;
      if (_editing != null && _editing != node?.id) _editing = null;
      // A tap on a line picks it; a tap anywhere else lets it go.
      _picked = hit.line;
    });
    if (hit.line != null) return;
    if (node != null && node.id == was) {
      // The picked card, tapped again. Its title zooms to it (choice 10); the rest of it opens it.
      if (hit.title) {
        zoomTo(node.id);
      } else if (node.type == NodeType.text) {
        setState(() => _editing = node.id);
      } else if (node.isGroup && hit.name) {
        setState(() => _editing = node.id);
      } else if (opens) {
        _openCard(node);
      }
    }
    // A double-tap makes a card: on the page, and on a group's ground, which is the page's.
    if (node != null && !node.isGroup) {
      _lastTap = null;
      return;
    }
    if (hit.name) return;
    final now = _clock.elapsed;
    final last = _lastTap;
    final again = last != null && (now - last.at).inMilliseconds < doubleMs && (Offset(x, y) - Offset(last.x, last.y)).distance < doublePx;
    if (again) {
      _lastTap = null;
      addCard(_camera.under(x, y));
      return;
    }
    _lastTap = (at: now, x: x, y: y);
  }

  // ---- the keys --------------------------------------------------------------------------------

  /*
   * The keys, while nothing is being typed. Shift+1 fits the whole canvas and Shift+2 zooms to the picked card,
   * as in Obsidian. Delete takes the picked card off, the arrows nudge it - ten pixels, one with Alt, a dot with
   * the magnet on - and Ctrl or Cmd+D copies it. Escape lets go, one thing at a time: the card being written in,
   * the line tool, a picked line, then the picked card; and that one is heard from a card being written in too.
   */
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space && node.hasPrimaryFocus) {
      _gestures.spaceHeld = event is! KeyUpEvent;
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape) {
      if (_editing == null && _picked == null && _lining == null && _chosen == null) return KeyEventResult.ignored;
      setState(() {
        if (_editing != null || _picked != null || _lining != null) {
          _editing = null;
          _picked = null;
          _lining = null;
        } else {
          _chosen = null;
        }
      });
      _focus.requestFocus();
      return KeyEventResult.handled;
    }
    // Typing in a field, or in a card: the keys are its own.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final at = _editing ?? _chosen;
    final chosen = _chosen;
    final free = _editable && chosen != null && _editing == null;
    if (keys.isShiftPressed && (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.exclamation)) {
      _camera.fit();
    } else if (keys.isShiftPressed && (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.at) && at != null) {
      zoomTo(at);
    } else if (free && (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace)) {
      _removeCard(chosen);
    } else if (free && (keys.isMetaPressed || keys.isControlPressed) && key == LogicalKeyboardKey.keyD) {
      _copyCard(chosen);
    } else if (free && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
      final card = _live.nodeOf(chosen);
      if (card == null) return KeyEventResult.ignored;
      // With the magnet on, an arrow is one dot along, from the nearest dot; Alt is always one pixel, off the grid.
      final gridded = _snap && !keys.isAltPressed;
      final step = keys.isAltPressed ? 1.0 : (gridded ? grid : 10.0);
      final dx = key == LogicalKeyboardKey.arrowLeft ? -step : (key == LogicalKeyboardKey.arrowRight ? step : 0.0);
      final dy = key == LogicalKeyboardKey.arrowUp ? -step : (key == LogicalKeyboardKey.arrowDown ? step : 0.0);
      final fromX = gridded && dx != 0 ? onGrid(card.x) : card.x;
      final fromY = gridded && dy != 0 ? onGrid(card.y) : card.y;
      _change(movedWithHeld(_live, card, fromX + dx, fromY + dy));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- pointers ----------------------------------------------------------------------------------

  /// Wraps what takes its own presses, so they never reach the page's gestures (`stopPropagation`).
  Widget _own(Widget child) => Listener(behavior: HitTestBehavior.opaque, onPointerDown: (event) => _owned.add(event.pointer), child: child);

  void _down(PointerDownEvent event) {
    if (_owned.contains(event.pointer)) return;
    final at = event.localPosition;
    // A group whose name is being written: a press on it is the name's.
    final editing = _live.nodeOf(_editing);
    if (editing != null && editing.isGroup && _hit(at.dx, at.dy).node?.id == editing.id) {
      _owned.add(event.pointer);
      return;
    }
    if (!_focus.hasFocus || _editing == null) _focus.requestFocus();
    _gestures.down(event.pointer, at.dx, at.dy, kind: event.kind, middle: event.buttons & kMiddleMouseButton != 0, main: event.kind != PointerDeviceKind.mouse || event.buttons & kPrimaryMouseButton != 0);
  }

  void _up(PointerEvent event, {bool cancelled = false}) {
    if (_owned.remove(event.pointer)) return;
    _gestures.up(event.pointer, event.localPosition.dx, event.localPosition.dy, cancelled: cancelled);
    // A tap that let go of the card being written in takes the keyboard's focus back from it.
    if (_editing == null && !_focus.hasPrimaryFocus && _adding == null && _picked == null) _focus.requestFocus();
  }

  void _signal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final scroll = event as PointerScrollEvent;
        final keys = HardwareKeyboard.instance;
        _camera.wheel(scroll.scrollDelta.dx, scroll.scrollDelta.dy, x: scroll.localPosition.dx, y: scroll.localPosition.dy, zoom: keys.isControlPressed || keys.isMetaPressed);
      });
    } else if (event is PointerScaleEvent) {
      // A browser's trackpad pinch.
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final pinch = event as PointerScaleEvent;
        _camera.moveTo(zoomedAt(_camera.view, pinch.localPosition.dx, pinch.localPosition.dy, _camera.view.scale * pinch.scale));
      });
    }
  }

  // ---- drawing -----------------------------------------------------------------------------------

  /// The tools as they were built last, and what they were built from: the view is built again at every move of a
  /// card carried and every letter written in one, and the tools, six round buttons in a pill of glass, were built
  /// with it each time though nothing of them had changed.
  ({Object from, Widget tools})? _toolsKept;

  Widget _tools(BuildContext context) {
    final t = context.tokens;
    final wide = MediaQuery.sizeOf(context).width > 600;
    final lining = _lining;
    final toCard = _editing ?? _chosen;
    final from = (t, wide, lining, wide ? toCard : null, _editable, _snap);
    final kept = _toolsKept;
    if (kept != null && kept.from == from) return kept.tools;
    final made = _toolsOf(context, t, wide: wide, lining: lining, toCard: toCard);
    _toolsKept = (from: from, tools: made);
    return made;
  }

  Widget _toolsOf(BuildContext context, Tokens t, {required bool wide, required ({String? from})? lining, required String? toCard}) {
    RoundButton tool(String label, LucideIcon icon, VoidCallback onPress, {bool on = false, bool held = false, bool? pressed}) =>
        RoundButton(label: label, icon: icon, onPress: onPress, on: on, held: held, pressed: pressed, iconSize: 18);
    final tools = <Widget>[
      if (_editable) ...[
        tool('Add a card', Lucide.plus, () => setState(() => _adding = AddStep.what)),
        tool(
          lining != null ? 'Stop drawing a line' : 'Draw a line: tap one card, then another',
          Lucide.spline,
          () => setState(() {
            _lining = lining != null ? null : (from: null);
            _picked = null;
          }),
          on: lining != null,
          pressed: lining != null,
        ),
        tool('Snap to the grid', Lucide.magnet, () => _prefs.update((now) => now.copyWith(canvasSnap: !_snap)), held: _snap, pressed: _snap),
        // `.toolRule`: a hairline between the tools that make and the tools that move about.
        Container(width: t.len('glacier-hairline'), height: t.lenOf('1.25rem'), margin: const EdgeInsets.symmetric(horizontal: 2), color: t.color('glacier-border-subtle')),
      ],
      // On a phone's width two fingers zoom, and the buttons that do it would push the tools into the map.
      if (wide) tool('Zoom out', Lucide.zoomOut, () => _camera.zoomBy(1 / zoomStep)),
      if (wide) tool('Zoom in', Lucide.zoomIn, () => _camera.zoomBy(zoomStep)),
      tool('Fit the whole canvas on the screen (Shift+1)', Lucide.maximize, _camera.fit),
      if (wide && toCard != null) tool('Zoom to the card (Shift+2)', Lucide.locateFixed, () => zoomTo(toCard)),
      if (lining != null)
        Padding(
          padding: EdgeInsets.only(left: t.space(2), right: t.space(3)),
          child: Text(lining.from != null ? 'Tap the card it goes to' : 'Tap the card it starts from', maxLines: 1, softWrap: false, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'))),
        ),
    ];
    final gap = t.space(1);
    return Semantics(
      container: true,
      label: 'Canvas tools',
      child: _own(
        GlassPill(
          share: 80,
          blur: 8,
          padding: gap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tools.length; i += 1) ...[if (i > 0) SizedBox(width: gap), tools[i]],
            ],
          ),
        ),
      ),
    );
  }

  /// The picked card's bar as it was built last, and what it was built from. Where the bar stands is the card's
  /// (`CardBar.place`); what it shows is the card's kind and colour, whether it is open, and what it may do, none of
  /// which a move of the card or a letter written in it changes. It was built again at each of those all the same.
  ({Object from, Widget bar})? _barKept;

  Widget _barOf(BuildContext context, CanvasNode wearing, CanvasThreads? threads) {
    final id = wearing.id;
    final opens = (wearing.type == NodeType.link && widget.openLink != null) || (wearing.type == NodeType.file && widget.wiki != null);
    final from = (id, wearing.type, wearing.color, ownPicture(wearing) == null, _editing == id, opens, threads);
    final kept = _barKept;
    if (kept != null && kept.from == from) return kept.bar;
    final bar = _own(
      CardBar(
        key: ValueKey('bar of $id'),
        node: wearing,
        editing: _editing == id,
        onEdit: () => setState(() => _editing = id),
        onDone: () {
          setState(() => _editing = null);
          _focus.requestFocus();
        },
        // The card as it is when the button is pressed: the bar may have been built for it somewhere else.
        onOpen: opens
            ? () {
                final now = _live.nodeOf(id);
                if (now != null) _openCard(now);
              }
            : null,
        onComment: threads == null ? null : () => threads(this.context, canvas: _live, node: id, start: true, change: _threaded),
        onLine: () => setState(() {
          _editing = null;
          _picked = null;
          _lining = (from: id);
        }),
        onColour: (color) => _colourCard(id, color),
        onDuplicate: () => _copyCard(id),
        onRemove: () => _removeCard(id),
      ),
    );
    _barKept = (from: from, bar: bar);
    return bar;
  }

  /// `CommentMarks.tsx`: the rounds on the cards that have threads, one size on the screen.
  List<Widget> _rounds(BuildContext context) {
    final threads = widget.threads;
    if (!_editable || threads == null || _live.comments == null) return const [];
    final t = context.tokens;
    return [
      for (final node in _live.nodes)
        if (markOf(_live, node.id) case final mark?)
          Placed(
            key: ValueKey('round ${node.id}'),
            at: Offset(node.x, node.y),
            anchor: const Alignment(-0.2, -0.2),
            fixed: true,
            child: _own(
              _Round(
                mark: mark,
                hue: widget.threadHue?.call(mark.by) ?? 'ink',
                t: t,
                onOpen: () => threads(context, canvas: _live, node: node.id, start: false, change: _threaded),
              ),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('canvas.build');
    final t = context.tokens;
    final live = _live;
    final editable = _editable;
    final wearing = _wearing;
    final lined = lines;
    DrawnLine? pickedLine;
    for (final line in lined) {
      if (line.edge.id == _picked) pickedLine = line;
    }
    // The page's dock, where it has one: Add a card and Fit, as the toolbar has them.
    return DockOffer(
      actions: [
        if (editable) DockAction(id: 'canvas-add', label: 'Add a card', glyph: HomeGlyph.plus, motion: DockMotion.turn, onPressed: () => setState(() => _adding = AddStep.what)),
        DockAction(id: 'canvas-fit', label: 'Fit the whole canvas on the screen', tip: 'Fit to screen', icon: Lucide.maximize, onPressed: _camera.fit),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The screen's size before anything is drawn on it: the camera fits the canvas, and the cards near the
          // screen have their words from the first frame.
          _camera.resized(constraints.maxWidth, constraints.maxHeight);
          _takeNear();
          _below = _barBelow();
          // A card that has left the canvas is kept no longer.
          if (_cards.length > live.nodes.length) {
            final there = {for (final node in live.nodes) node.id};
            _cards.removeWhere((id, _) => !there.contains(id));
          }
          final threads = widget.threads;
          final editedBy = widget.editedBy;
          if (_editing != _toldEditing) {
            final now = _toldEditing = _editing;
            // After the frame: whoever hears it may draw again for it.
            final tell = widget.onEditing;
            if (tell != null) WidgetsBinding.instance.addPostFrameCallback((_) => tell(now));
          }
          return Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _key,
            child: Semantics(
              container: true,
              image: !editable,
              label: 'A canvas of ${live.nodes.length} cards',
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: (event) {
                  if (!_owned.contains(event.pointer)) _gestures.move(event.pointer, event.localPosition.dx, event.localPosition.dy);
                },
                onPointerUp: _up,
                onPointerCancel: (event) => _up(event, cancelled: true),
                onPointerSignal: _signal,
                onPointerPanZoomStart: (event) => _gestures.panZoomStart(event.localPosition.dx, event.localPosition.dy),
                onPointerPanZoomUpdate: (event) => _gestures.panZoomUpdate(event.localPan.dx, event.localPan.dy, event.scale),
                onPointerPanZoomEnd: (_) => _gestures.panZoomEnd(),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // `.canvas`: the note's ground, and the dots under the cards.
                      ColoredBox(color: t.color('glacier-bg')),
                      // A layer of their own: the dots are drawn again at every move of the camera, and without one
                      // the ground, the tools and the map's frame were drawn again with them.
                      RepaintBoundary(child: CustomPaint(painter: DotsPainter(camera: _camera, ink: t.color('app-ink')))),
                      if (live.nodes.isEmpty)
                        IgnorePointer(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // `.emptyCanvasArt { inline-size: min(70vw, 28rem, 40dvh × ratio) }`: sized by the
                                // screen, where the drawing alone filled the canvas's whole width (710 px wide on a
                                // phone where the page's is 333).
                                Ghost(scene: GhostScene.emptyCanvas, align: GhostAlign.center, maxWidth: 0.7 * t.css.vw < t.lenOf('28rem') ? 0.7 * t.css.vw : t.lenOf('28rem')),
                                SizedBox(height: t.space(3)),
                                Text(editable ? 'Double-tap to add a card.' : 'An empty canvas.', style: pageText(t, t.fontSize('md'), color: t.color('glacier-text-muted'))),
                              ],
                            ),
                          ),
                        ),
                      CanvasWorld(
                        camera: _camera,
                        children: [
                          for (final node in live.nodes) ..._card(context, t, node, editable: editable),
                          // Another member writing in a card: a ring in their colour and their handle on its corner,
                          // scaled with the world as the card is (`.card[data-edited-by]`).
                          if (editedBy != null)
                            for (final node in live.nodes)
                              if (editedBy(node.id) case final by?)
                                Placed(
                                  key: ValueKey('edited ${node.id}'),
                                  at: Offset(node.x, node.y),
                                  size: Size(node.width, node.height),
                                  child: IgnorePointer(child: EditedBy(by: by, radius: t.radius('lg') + (node.isGroup ? 4 : 0), paper: t.color('app-paper'), corner: t.radius('md'), label: t.textAt(11, weight: 'medium', height: 1.3))),
                                ),
                          Placed(
                            key: const ValueKey('lines'),
                            at: Offset.zero,
                            size: Size.zero,
                            // A layer of their own: a pan sets the lines down again and draws none of them.
                            child: RepaintBoundary(child: IgnorePointer(child: CustomPaint(painter: LinesPainter(lines: lined, picked: _picked, t: t)))),
                          ),
                          ..._rounds(context),
                          // The picked line's words and its cross, over the line's middle, in the canvas's own pixels.
                          if (pickedLine != null)
                            Placed(
                              key: ValueKey('words ${pickedLine.edge.id}'),
                              at: Offset(pickedLine.path.mid.x, pickedLine.path.mid.y),
                              anchor: Alignment.center,
                              child: _own(LineWords(key: ValueKey(pickedLine.edge.id), edge: pickedLine.edge, onLabel: _labelLine, onRemove: _removeLine)),
                            ),
                          // The picked card's ring and handles, and its bar, over everything else in the world.
                          if (wearing != null)
                            ...Handles(
                              node: wearing,
                              camera: _camera,
                              snap: _snap,
                              coarse: _coarse,
                              onPreview: _previewSize,
                              onResize: _resizeCard,
                              own: _own,
                              felt: _felt,
                            ).build(context),
                          if (wearing != null) CardBar.place(node: wearing, below: _below, child: _barOf(context, wearing, threads)),
                        ],
                      ),
                      // The toolbar: icons, floating at the bottom left; the map at the bottom right.
                      Positioned(left: t.space(3), bottom: t.space(3), child: _tools(context)),
                      Positioned(
                        // To the start of the page's dock, where there is one, rather than under it.
                        right: t.space(3) + (PageDockRoom.maybeOf(context)?.end ?? 0),
                        bottom: t.space(3),
                        child: Minimap(canvas: live, lines: lined, camera: _camera, big: _mapBig, onBig: () => setState(() => _mapBig = true), own: _own, pictures: widget.pictures),
                      ),
                      if (_adding != null)
                        AddSheet(
                          step: _adding!,
                          titles: widget.wiki?.titles?.call() ?? const [],
                          aboutCard: _picking != null && !_picking!.isGroup,
                          onClose: () => setState(() => _adding = null),
                          onWords: () {
                            setState(() => _adding = null);
                            addCard(_camera.middle());
                          },
                          onNote: (title) {
                            setState(() => _adding = null);
                            addNoteCard(title);
                          },
                          onLink: (url) {
                            setState(() => _adding = null);
                            _addLinkCard(url);
                          },
                          onPicture: () {
                            setState(() => _adding = null);
                            _addPicture();
                          },
                          onChart: () {
                            setState(() => _adding = null);
                            _addStartedCard(chartCard);
                          },
                          onTable: () {
                            setState(() => _adding = null);
                            _addStartedCard(tableCard);
                          },
                          onGroup: () {
                            setState(() => _adding = null);
                            _addGroup();
                          },
                          onStep: (step) => setState(() => _adding = step),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.card[data-edited-by]` and its `::after`: `box-shadow: 0 0 0 2px var(--editor)` round the card, and the member's
/// handle at its top corner (`padding: 1px 7px 2px; border-end-start-radius: var(--glacier-radius-md);
/// background: var(--editor); color: var(--app-paper); font-size: 11px; font-weight: medium; line-height: 1.3`),
/// inside the card's own corner as its `overflow: hidden` keeps it.
class EditedBy extends StatelessWidget {
  const EditedBy({super.key, required this.by, required this.radius, required this.paper, required this.corner, required this.label});

  final CardEditor by;

  /// The card's own corner.
  final double radius;
  final Color paper;

  /// `--glacier-radius-md`.
  final double corner;
  final TextStyle label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${by.name} is writing in this card',
        child: CustomPaint(
          foregroundPainter: _RingPainter(colour: by.colour, radius: radius),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: DecoratedBox(
                decoration: BoxDecoration(color: by.colour, borderRadius: BorderRadiusDirectional.only(bottomStart: Radius.circular(corner))),
                child: Padding(padding: const EdgeInsets.fromLTRB(7, 1, 7, 2), child: ExcludeSemantics(child: Text(by.name, maxLines: 1, style: label.copyWith(color: paper)))),
              ),
            ),
          ),
        ),
      );
}

/// A shadow with no blur and two pixels of spread: a band two wide outside the card's edge, its corners the card's
/// own and two more.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.colour, required this.radius});
  final Color colour;
  final double radius;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final card = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawDRRect(card.inflate(2), card, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.colour != colour || old.radius != radius;
}

/// `.commentRound`: how many of a card's threads are open, in the colour of who started the first open one; hollow
/// with a tick once every thread is resolved.
class _Round extends StatelessWidget {
  const _Round({required this.mark, required this.hue, required this.t, required this.onOpen});
  final ({int count, int open, String by}) mark;
  final String hue;
  final Tokens t;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final worn = CanvasHue.values.where((each) => each.name == hue).firstOrNull;
    final color = worn == null ? t.color('app-ink') : spaceColor(t, 'var(--app-space)', CardPaint.hue(worn));
    final paper = t.color('app-paper');
    final open = mark.open > 0;
    return Semantics(
      button: true,
      label: '${mark.count == 1 ? 'A comment' : '${mark.count} comments'} on this card${open ? ', ${mark.open} open' : ', resolved'}',
      onTap: onOpen,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minWidth: 22),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: open ? color : paper,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 3)],
          ),
          child: Text(open ? '${mark.open}' : '✓', style: t.textAt(12, weight: 'semibold', height: 1, color: open ? paper : color)),
        ),
      ),
    );
  }
}

/// A picked line's words, written in place over its middle, and the cross that takes the line off
/// (`LineWords.tsx`, `Remove.tsx`). The words are handed on when the field is left or Enter is pressed, and only
/// when they changed, so picking a line and letting it go writes nothing.
class LineWords extends StatefulWidget {
  const LineWords({super.key, required this.edge, required this.onLabel, required this.onRemove});
  final CanvasEdge edge;
  final void Function(String id, String words) onLabel;
  final void Function(String id) onRemove;

  @override
  State<LineWords> createState() => _LineWordsState();
}

class _LineWordsState extends State<LineWords> {
  late final TextEditingController _words = TextEditingController(text: widget.edge.label ?? '');
  late final FocusNode _focus = FocusNode(debugLabel: 'canvas line words')..addListener(_left);
  bool _had = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    // The field takes the keyboard as it appears; the canvas had it, so it is asked for rather than waited for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (_removed) return;
    if (_words.text.trim() != (widget.edge.label ?? '')) widget.onLabel(widget.edge.id, _words.text);
  }

  void _left() {
    if (_focus.hasFocus) {
      _had = true;
    } else if (_had) {
      _had = false;
      _commit();
    }
  }

  void _remove() {
    _removed = true;
    widget.onRemove(widget.edge.id);
  }

  @override
  void dispose() {
    // Let go while it was being written on (a tap elsewhere, Escape): the words written are the line's.
    if (_had && !_removed && _words.text.trim() != (widget.edge.label ?? '')) {
      final words = _words.text;
      final id = widget.edge.id;
      final tell = widget.onLabel;
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(id, words));
    }
    _focus
      ..removeListener(_left)
      ..dispose();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('sm');
    final style = pageText(t, size, color: t.color('app-ink'));
    final gap = t.space(1);
    final md = t.fontSize('md');
    return DecoratedBox(
      // `.lineWords`: a small field and the cross, centred on the point.
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
        boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 6), blurRadius: 18)],
      ),
      child: Padding(
        padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Words on the line',
              textField: true,
              child: Container(
                width: 11 * size + 0.7 * size * 2,
                padding: EdgeInsets.symmetric(horizontal: 0.7 * size, vertical: 0.25 * size),
                child: Stack(
                  children: [
                    ListenableBuilder(
                      listenable: _words,
                      builder: (context, _) => _words.text.isEmpty ? Text('Words on the line', maxLines: 1, style: style.copyWith(color: t.color('glacier-text-subtle'))) : const SizedBox.shrink(),
                    ),
                    EditableText(
                      controller: _words,
                      focusNode: _focus,
                      style: style,
                      cursorColor: t.color('app-ink'),
                      backgroundCursorColor: t.color('glacier-text-subtle'),
                      onSubmitted: (_) {
                        _commit();
                        _had = false;
                        _focus.unfocus();
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: gap),
            // `.remove`: the cross that takes the line off the canvas.
            Semantics(
              button: true,
              label: 'Take this line off the canvas',
              excludeSemantics: true,
              onTap: _remove,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _remove,
                child: Container(
                  width: 1.6 * md,
                  height: 1.6 * md,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: inkOf(t, 'color-mix(in oklch, var(--app-ink) 10%, transparent)'), shape: BoxShape.circle),
                  child: Text('×', style: t.textAt(md, height: 1, color: t.color('app-ink-2'))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
