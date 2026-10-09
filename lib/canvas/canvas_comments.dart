/// A canvas's comments on its screen (../glyph docs/SHARED.md, S9): a round on a card's corner for its threads, in
/// the colour of who started the first open one, with how many are open; Comment on the picked card's bar starts
/// one; and the card a thread is drawn in is the note's own (lib/comments/ui/sheet.dart), from the same shape. A
/// port of `src/app/canvas/useCanvasComments.tsx`. Every change is the canvas handed back whole, as a card moved
/// is, so a team's structure merges it (lib/live/team_canvas.dart).
///
/// What differs: the page's hook ran inside its view; the view here asks for its threads through a seam
/// ([CanvasView.threads], since lib/canvas does not know an account or an organization), so this is a widget round
/// the view that answers it. It is handed the note's body as the view is, and reads the canvas from it again
/// whenever it changes, so a reply from another member arriving under an open card is drawn in it; what it writes
/// goes through the view's own change, which the view was asked with.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../account/session.dart';
import '../comments/author.dart';
import '../comments/colours.dart';
import '../comments/format.dart' show Stamp;
import '../comments/ui/card.dart';
import '../comments/ui/sheet.dart';
import 'canvas_view.dart' show CanvasThreads;
import 'comments.dart' as on;
import 'json_canvas.dart';

class CanvasComments extends StatefulWidget {
  const CanvasComments({super.key, required this.body, required this.colours, this.account, this.now, required this.builder});

  /// The note's body, as its view is handed it.
  final String body;

  /// Who wears what in this note, as it stands now (lib/comments/colours.dart).
  final CommentColours Function() colours;

  /// The account, for the handle a comment is by; null in a build with none, where every comment is `me`'s.
  final AccountSource? account;

  /// This moment, for a stamp; the clock's unless given.
  final DateTime Function()? now;

  /// The view, given what answers its threads and the hue each handle's round wears.
  final Widget Function(BuildContext context, CanvasThreads threads, String Function(String handle) hue) builder;

  @override
  State<CanvasComments> createState() => CanvasCommentsState();
}

class CanvasCommentsState extends State<CanvasComments> {
  static final Canvas _empty = Canvas(nodes: const [], edges: const []);

  late Canvas _canvas = canvasOf(widget.body) ?? _empty;
  CommentPage? _page;

  /// The card the comment being written is for, or whose threads the list shows.
  String? _card;

  /// The view's own way to change the canvas, as it last asked with.
  void Function(Canvas next)? _write;

  /// What the sheet is showing; null while it is closed.
  CommentPage? get page => _page;

  @override
  void didUpdateWidget(CanvasComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.body != oldWidget.body) _canvas = canvasOf(widget.body) ?? _empty;
  }

  Stamp _stamp() => stampHere(widget.account, widget.now?.call());

  void _close() => setState(() => _page = null);

  bool _change(Canvas? next, HapticKind felt) {
    final write = _write;
    if (next == null || write == null) return false;
    _canvas = next;
    write(next);
    fireMotor(felt);
    if (mounted) setState(() {});
    return true;
  }

  /// Starts a thread on a card (`start`).
  void start(String nodeId) {
    if (_write == null) return;
    fireMotor(HapticKind.selection);
    setState(() {
      _card = nodeId;
      _page = NewPage(on.quoteOf(_canvas, nodeId));
    });
  }

  /// Opens a card's threads: the one, or the list of them (`open`).
  void open(String nodeId) {
    final threads = on.threadsOn(_canvas, nodeId);
    if (threads.isEmpty) return;
    fireMotor(HapticKind.selection);
    setState(() {
      _card = nodeId;
      _page = threads.length == 1 ? ThreadPage(threads.first.id) : const ListPage();
    });
  }

  void _asked(BuildContext context, {required Canvas canvas, required String node, required bool start, required void Function(Canvas next) change}) {
    _canvas = canvas;
    _write = change;
    start ? this.start(node) : open(node);
  }

  @override
  Widget build(BuildContext context) {
    final wears = widget.colours();
    final page = _page;
    final card = _card;
    final canvas = _canvas;
    Widget? sheet;
    if (page != null && _write != null) {
      final threads = on.threadsOf(canvas);
      final here = card == null ? const <String>{} : {for (final thread in on.threadsOn(canvas, card)) thread.id};
      sheet = CommentSheet(
        page: page,
        // A card's own threads in its list; a thread's card counts every thread, for its way back.
        threads: page is ListPage && card != null ? [for (final thread in threads) if (here.contains(thread.id)) thread] : threads,
        people: CardPeople(colour: wears.of, me: commentHandle(widget.account)),
        quoteOf: (id) {
          final thread = canvas.comments?.where((each) => each.id == id).firstOrNull;
          return thread == null ? null : on.quoteOf(canvas, thread.node);
        },
        onClose: _close,
        onOpen: (id) => setState(() => _page = ThreadPage(id)),
        onList: () => setState(() => _page = const ListPage()),
        onAdd: (words) {
          if (card != null && _change(on.withThread(_canvas, card, _stamp(), words), HapticKind.success)) _close();
        },
        onReply: (id, words) => _change(on.withReply(_canvas, id, _stamp(), words), HapticKind.success),
        onResolve: (id) => _change(on.resolvedThread(_canvas, id, _stamp()), HapticKind.success),
        onReopen: (id) => _change(on.reopenedThread(_canvas, id), HapticKind.selection),
        onDelete: (id) {
          if (_change(on.withoutThread(_canvas, id), HapticKind.warning)) _close();
        },
        now: widget.now?.call().millisecondsSinceEpoch,
      );
    }
    // The sheet is drawn over the window and takes no room here: the view keeps the box it was given.
    return Stack(fit: StackFit.passthrough, children: [widget.builder(context, _asked, wears.of), ?sheet]);
  }
}
