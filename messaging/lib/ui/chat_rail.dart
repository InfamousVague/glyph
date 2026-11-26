/// A chat's map, in the gutter at its right: a short line for each message, one under another, from the oldest held
/// at the top to the newest at the foot (Matt, 2026-11-25: "in the right hand of the chat gutter add this same style of
/// chat scrolling to show frequency of messages and who differently sent messages etc", with a picture of a document's
/// outline drawn as a column of ticks). A line's colour and side are who sent it (one's own in the accent from the
/// right, each other person's in their own colour from the left, as their bubbles are), its length how fast the chat
/// was going there (a long line is one of many within a few minutes, a short one stands alone), and the lines of what
/// is on the screen now are the bright ones.
///
/// The map has one size and one spacing: a line a message, [ChatRail.pitch] apart, standing up from its foot,
/// whatever the chat's length. Where the chat has more lines than the map has room for, the map shows a part of it
/// and is itself scrolled, kept on the part of the chat that is on the screen (Matt, 2026-11-25: "it's a bit glitchy though when getting to the top or bottom dont
/// change the main size of the chatmap scroll it up and down as we go back through history"). It used to fit every
/// message held into its height, so each older page loaded at the top drew every line again somewhere else, closer
/// together or several messages to a line.
///
/// A wheel, two fingers on a trackpad or a finger drawn over it scroll the chat as they do over the chat itself, and
/// a press on it goes to the message pressed. It no longer opens into a list of the chat's stretches, and no longer
/// swells under a finger held on it or a mouse over it (Matt, the same day: "Lets remove the popover for the
/// summarized messages on the chat map for now and remove the tap and hold just allow scrolling normally"). The list
/// and the hold are in this file as of commit 5cf3f3780, to be brought back from there; what the list was made from,
/// [ChatRail.stretchesOf], is kept here with its tests for when it comes back.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show Drag, GestureBinding, PointerDeviceKind, PointerScrollEvent, VerticalDragGestureRecognizer;
import 'package:flutter/rendering.dart' show RenderSliverMultiBoxAdaptor, SliverMultiBoxAdaptorParentData;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../summaries.dart';
import 'dialup/bevel.dart' show isBevelChrome;

/// One message, as the map needs it.
@immutable
class RailMark {
  const RailMark({required this.at, required this.who, required this.mine, this.name = '', this.text = '', this.quiet = false});

  /// When it was sent, in milliseconds.
  final int at;

  /// Who sent it, by anything that tells senders apart (an address, an id); a face is asked for by it.
  final String who;
  final bool mine;

  /// Their name as the chat shows it.
  final String name;

  /// Its words, for a stretch's line.
  final String text;

  /// Something that happened, not something said (a join, a pin): a faint line, and no part of a summary.
  final bool quiet;
}

/// One line of the map: one message, or several where there are more messages than lines.
@immutable
class RailTick {
  const RailTick({required this.who, required this.mine, required this.rate, required this.quiet});

  /// Who sent most of what it stands for.
  final String who;
  final bool mine;

  /// How fast the chat was going there, 0 (one message alone) to 1 (many within minutes).
  final double rate;
  final bool quiet;
}

/// A stretch of a chat: what was said without a long pause.
@immutable
class RailStretch {
  const RailStretch({required this.newest, required this.oldest, required this.people, required this.opening, required this.lines});

  /// Where it is in the chat's messages, newest first: from [newest] to [oldest], both in it.
  final int newest, oldest;

  /// Who wrote in it, whoever wrote most first: (who, name, mine).
  final List<({String who, String name, bool mine})> people;

  /// How it began: "Maya: are we still on for Friday".
  final String opening;

  /// The stretch as a model reads a conversation, oldest first, `<name>: <words>` a line; empty where there is too
  /// little to sum up.
  final String lines;

  int get count => oldest - newest + 1;
}

class ChatRail extends StatefulWidget {
  const ChatRail({super.key, required this.controller, required this.marks, required this.child, this.chat = '', this.face, this.summarize, this.lead = 0});

  /// How many rows the list has before the first of [marks] (messages still going up, at a space's foot): a mark's
  /// row in the list is its place in [marks] and these.
  final int lead;

  /// The list's own controller, on a list drawn bottom up.
  final ScrollController controller;

  /// The chat's messages, newest first, as its list has them.
  final List<RailMark> marks;

  /// The chat, by anything that tells it from another: another chat's map starts at its foot.
  final String chat;

  /// Someone's face at a size, and what sums a stretch up ([RailStretch.lines]): for the list of stretches, which is
  /// put away for now, so neither is asked for. Kept so the chats that give them need not change when it is back.
  final Widget Function(String who, String name, bool mine, double size)? face;
  final Future<String?> Function(String lines)? summarize;
  final Widget child;

  /// Fewer messages than this have no map: there is nothing to find one's way in.
  static const fewest = 12;

  /// How wide the map's lines are drawn: twice what they were, as everything of the map's is (Matt, 2026-11-25: "make the
  /// chat map twice as big").
  static const double width = 24;

  /// The room either side of the map, so it is not flush against the window's edge or the bubbles (Matt, 2026-11-25:
  /// "add a little padding on the left and right of the chat map so it's not flush against the edge").
  static const double edge = 7;

  /// The gutter a chat's list keeps at its right for the map: its list's right padding (Matt, 2026-11-25: "add a
  /// little bit of space for a gutter on the right hand side of the chats in order to render this").
  static const double gutter = width + edge * 2;

  /// The space from one line to the next, always: what a long chat's map had (Matt, 2026-11-25: "dont change the main
  /// size of the chatmap").
  static const double pitch = 6;

  /// How thick a line is.
  static const double thick = 3.2;

  /// How much of the chat's height the map may take, and its most.
  static const double share = 0.9, tallest = 680;

  /// A line's length, from one message alone to the busiest.
  static const double shortest = 8, longest = 18;

  /// Messages this near in time count toward how fast the chat was going.
  static const int near = 5 * 60 * 1000;

  /// This many near a message is as fast as the map shows.
  static const int busiest = 8;

  /// The most stretches a chat is cut into.
  static const int mostStretches = 12;

  /// The lines for [marks] (newest first) in [rows] rows, the newest first.
  static List<RailTick> ticksOf(List<RailMark> marks, int rows) {
    final n = marks.length;
    if (n == 0 || rows <= 0) return const [];
    // How many others are within [near] of each: two pointers down a list in time's order (newest first).
    final rate = List<double>.filled(n, 0);
    var lo = 0, hi = 0;
    for (var i = 0; i < n; i++) {
      while (marks[lo].at - marks[i].at > near) {
        lo++;
      }
      if (hi < i) hi = i;
      while (hi + 1 < n && marks[i].at - marks[hi + 1].at <= near) {
        hi++;
      }
      rate[i] = ((hi - lo) / busiest).clamp(0.0, 1.0);
    }
    if (n <= rows) return [for (var i = 0; i < n; i++) RailTick(who: marks[i].who, mine: marks[i].mine, rate: rate[i], quiet: marks[i].quiet)];
    return [
      for (var r = 0; r < rows; r++)
        () {
          final from = r * n ~/ rows, to = math.max(from + 1, (r + 1) * n ~/ rows);
          final by = <String, int>{};
          var sum = 0.0, quiet = true;
          for (var i = from; i < to; i++) {
            sum += rate[i];
            if (marks[i].quiet) continue;
            quiet = false;
            by[marks[i].who] = (by[marks[i].who] ?? 0) + 1;
          }
          var who = marks[from].who;
          var best = 0;
          by.forEach((k, v) {
            if (v > best) (who, best) = (k, v);
          });
          final of = marks.sublist(from, to).firstWhere((m) => m.who == who, orElse: () => marks[from]);
          return RailTick(who: who, mine: of.mine, rate: sum / (to - from), quiet: quiet);
        }(),
    ];
  }

  /// The pauses a chat is cut into stretches at, the shortest first: the first that leaves few enough is used.
  static const _pauses = [20, 60, 3 * 60, 8 * 60, 24 * 60, 3 * 24 * 60, 7 * 24 * 60, 30 * 24 * 60];

  /// [marks] (newest first) as stretches, the newest first, [most] at most.
  static List<RailStretch> stretchesOf(List<RailMark> marks, {int most = mostStretches}) {
    final n = marks.length;
    if (n == 0) return const [];
    List<int> cuts(int minutes) => [
          for (var i = 1; i < n; i++)
            if (marks[i - 1].at - marks[i].at > minutes * 60 * 1000) i,
        ];
    var starts = <int>[];
    var found = false;
    for (final p in _pauses) {
      starts = cuts(p);
      if (starts.length < most) {
        found = true;
        break;
      }
    }
    // A chat with no pause long enough to cut at that few: even shares of it.
    if (!found) starts = [for (var k = 1; k < most; k++) k * n ~/ most];
    final edges = [0, ...starts, n];
    return [
      for (var k = 0; k + 1 < edges.length; k++)
        if (edges[k + 1] > edges[k]) _stretch(marks, edges[k], edges[k + 1] - 1),
    ];
  }

  static RailStretch _stretch(List<RailMark> marks, int newest, int oldest) {
    final by = <String, ({String who, String name, bool mine, int n})>{};
    RailMark? first;
    final said = <RailMark>[];
    for (var i = oldest; i >= newest; i--) {
      final m = marks[i];
      if (m.quiet) continue;
      final had = by[m.who];
      by[m.who] = (who: m.who, name: m.name, mine: m.mine, n: (had?.n ?? 0) + 1);
      if (m.text.trim().isEmpty) continue;
      first ??= m;
      said.add(m);
    }
    final people = by.values.toList()..sort((a, b) => b.n.compareTo(a.n));
    String words(RailMark m) => m.text.replaceAll('\n', ' ').trim();
    String name(RailMark m) => m.mine ? 'You' : (m.name.trim().isEmpty ? 'Them' : m.name.trim());
    // Worth a summary: a few things said, or one long one.
    final enough = said.length >= 3 || said.any((m) => m.text.trim().length >= Summaries.long);
    return RailStretch(
      newest: newest,
      oldest: oldest,
      people: [for (final p in people) (who: p.who, name: p.name, mine: p.mine)],
      opening: first == null ? '' : '${name(first)}: ${words(first)}',
      // The newest forty of a long stretch: what a small model can read at once.
      lines: !enough ? '' : [for (final m in said.length > 40 ? said.sublist(said.length - 40) : said) '${name(m)}: ${words(m)}'].join('\n'),
    );
  }

  @override
  State<ChatRail> createState() => _ChatRailState();
}

class _ChatRailState extends State<ChatRail> {
  bool _live = false;

  ScrollController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(ChatRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, _c)) _list = null;
    if (old.chat != widget.chat) {
      _list = null;
      _at = 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _hold?.cancel();
    _pan?.cancel();
    super.dispose();
  }

  /// The map's lines and the people's colours, kept until the messages change: a build asks for them each time, and
  /// they are a pass over every message.
  (int, int, int)? _ticksOf;
  List<RailTick> _ticks = const [];
  List<String> _others = const [];

  void _lines() {
    final m = widget.marks;
    final now = (m.length, m.isEmpty ? 0 : m.first.at, m.isEmpty ? 0 : m.last.at);
    if (_ticksOf == now) return;
    _ticksOf = now;
    // A line a message, however many.
    _ticks = ChatRail.ticksOf(m, m.length);
    _others = {for (final x in m) if (!x.mine && !x.quiet) x.who}.toList()..sort();
  }

  /// There is a map where there is a chat to find one's way in: enough messages, and more of them than a screen.
  void _measure() {
    if (!mounted) return;
    final live = widget.marks.length >= ChatRail.fewest && _c.hasClients && _c.position.hasContentDimensions && _c.position.maxScrollExtent > 40;
    if (live != _live) setState(() => _live = live);
  }

  /// The list's own rows as they are laid out now: for each one built, where it starts (from the newest end) and how
  /// tall it is. Only the rows near the screen are built, and only these are known exactly.
  Map<int, ({double at, double tall})> _laid() {
    final out = <int, ({double at, double tall})>{};
    if (!_c.hasClients) return out;
    // Looked for once and kept while it is on the page: this is asked at every frame of a scroll.
    var l = _list;
    if (l == null || !l.attached) {
      RenderSliverMultiBoxAdaptor? list;
      void find(RenderObject o) {
        if (list != null) return;
        if (o is RenderSliverMultiBoxAdaptor) {
          list = o;
          return;
        }
        o.visitChildren(find);
      }

      _c.position.context.storageContext.findRenderObject()?.visitChildren(find);
      l = _list = list;
    }
    if (l == null) return out;
    // What is before the list in the scroll (its padding), where that can be told.
    if (l.constraints.scrollOffset > 0) _before = _c.position.pixels - l.constraints.scrollOffset;
    for (var child = l.firstChild; child != null; child = l.childAfter(child)) {
      final d = child.parentData;
      if (d is! SliverMultiBoxAdaptorParentData || d.index == null || d.layoutOffset == null || !child.hasSize) continue;
      out[d.index!] = (at: d.layoutOffset! + _before, tall: child.size.height);
    }
    return out;
  }

  double _before = 0;
  RenderSliverMultiBoxAdaptor? _list;

  /// Which of the messages are on the screen: from how many messages up from the newest to how many, parts of a
  /// message counted (2.5 is half way up the third), so the map moves with the chat and not a line at a time. Exactly,
  /// from the rows on the screen; by the scroll's share of its whole length until the list is laid out. Pulled past
  /// an end, as a phone's list can be, the chat is still at that end here.
  (double, double) _view() {
    final n = widget.marks.length;
    if (n == 0 || !_c.hasClients || !_c.position.hasContentDimensions) return (0, n.toDouble());
    final p = _c.position;
    final foot = p.pixels, top = p.pixels + p.viewportDimension;
    double? lo, hi;
    _laid().forEach((index, row) {
      if (row.tall <= 0 || row.at + row.tall <= foot || row.at >= top) return;
      final mark = index - widget.lead;
      if (mark < 0 || mark >= n) return;
      final a = mark + ((foot - row.at) / row.tall).clamp(0.0, 1.0), b = mark + ((top - row.at) / row.tall).clamp(0.0, 1.0);
      if (lo == null || a < lo!) lo = a;
      if (hi == null || b > hi!) hi = b;
    });
    if (lo != null) return (lo!, hi!);
    final whole = p.maxScrollExtent + p.viewportDimension;
    if (whole <= 0) return (0, n.toDouble());
    final at = p.pixels.clamp(0.0, p.maxScrollExtent);
    return (at / whole * n, (at + p.viewportDimension) / whole * n);
  }

  /// How far the map itself is scrolled: how much of its lines is below its foot, nothing with the newest message's
  /// line at the foot. Counted from the newest end, as the chat's own scroll is, so older messages loaded in at the
  /// top move no line.
  double _at = 0;

  /// Where the map is now, [tall] high, and what of the chat is on the screen ([_view]). The map stays where it is
  /// while the lines of what is on the screen are in it, and is taken along by them, no further than it must be, as
  /// they reach its top or its foot: so it moves as smoothly as the chat does, never past its own ends, and nothing
  /// in it moves when the chat grows at either end. Asked at every paint.
  ({double lo, double hi, double at}) _place(double tall) {
    final (lo, hi) = _view();
    final most = math.max(0.0, widget.marks.length * ChatRail.pitch - tall);
    var at = _at;
    if (hi * ChatRail.pitch > at + tall) at = hi * ChatRail.pitch - tall;
    if (lo * ChatRail.pitch < at) at = lo * ChatRail.pitch;
    return (lo: lo, hi: hi, at: _at = at.clamp(0.0, most));
  }

  /// Counts the goings, so a newer one stops an older one still finding its row.
  int _going = 0;

  /// Brings the message at [mark] onto the screen: its top to the screen's top where [top] (the start of a stretch,
  /// to read on from), else to the middle. The list builds only the rows near the screen, so where a far row is is
  /// not known: it goes to where the row should be by the rows it knows, looks again once those are laid out, and so
  /// on until the row itself is there to be gone to exactly (Matt, 2026-11-25: "if i click on a section in the chat
  /// map it doesn't always go right to where i clicked").
  Future<void> _goTo(int mark, {bool top = false, bool run = false}) async {
    final n = widget.marks.length;
    if (n == 0 || !_c.hasClients) return;
    final item = mark.clamp(0, n - 1) + widget.lead;
    final mine = ++_going;
    for (var tries = 0; tries < 14; tries++) {
      if (!mounted || mine != _going || !_c.hasClients || !_c.position.hasContentDimensions) return;
      final p = _c.position;
      final laid = _laid();
      final row = laid[item];
      if (row != null) {
        final to = (top ? row.at + row.tall - p.viewportDimension + 12 : row.at + row.tall / 2 - p.viewportDimension / 2).clamp(0.0, p.maxScrollExtent);
        if ((to - p.pixels).abs() < 1) return;
        if (run && tries == 0 && !context.tokens.reducedMotion) {
          await _c.animateTo(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        } else {
          _c.jumpTo(to);
        }
        return;
      }
      final double guess;
      if (laid.isEmpty) {
        guess = (item + 0.5) / (n + widget.lead) * (p.maxScrollExtent + p.viewportDimension);
      } else {
        // From the nearest row that is known, by how tall the known rows are on the whole.
        final near = laid.keys.reduce((a, b) => (a - item).abs() <= (b - item).abs() ? a : b);
        final tall = laid.values.fold<double>(0, (sum, r) => sum + r.tall) / laid.length;
        guess = laid[near]!.at + (item - near) * tall;
      }
      final to = (guess - p.viewportDimension / 2).clamp(0.0, p.maxScrollExtent);
      // As far as the list goes and the row is still not there: it is not in the list (older ones still to come).
      if ((to - p.pixels).abs() < 1) return;
      _c.jumpTo(to);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// A wheel turned over the map scrolls the chat, as it would over the chat itself: the map stands over the chat's
  /// list, which never hears the wheel there.
  void _wheel(PointerScrollEvent e) {
    if (!_c.hasClients || e.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      // The chat's list is drawn bottom up, so a turn down the page is toward its start.
      if (_c.hasClients) _c.position.pointerScroll(-(e as PointerScrollEvent).scrollDelta.dy);
    });
  }

  /// Two fingers on a trackpad or a finger drawn over the map: the chat's own drag, with its glide after, and a
  /// finger put down stops a glide as it does on the chat (Matt, 2026-11-25: "just allow scrolling normally"). Not a
  /// mouse, which does not drag the chat either.
  Drag? _pan;
  ScrollHoldController? _hold;

  Widget _scrollsChat(Widget child) => Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _wheel(e);
        },
        child: RawGestureDetector(
          gestures: {
            VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.trackpad, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus, PointerDeviceKind.unknown}),
              (r) => r
                ..onDown = (d) {
                  _hold = _c.hasClients ? _c.position.hold(() => _hold = null) : null;
                }
                ..onStart = (d) {
                  _pan?.cancel();
                  // Beginning the drag ends the hold.
                  _pan = _c.hasClients ? _c.position.drag(d, () => _pan = null) : null;
                }
                ..onUpdate = ((d) => _pan?.update(d))
                ..onEnd = ((d) => _pan?.end(d))
                ..onCancel = () {
                  _hold?.cancel();
                  _pan?.cancel();
                },
            ),
          },
          child: child,
        ),
      );

  /// The message whose line is [y] down a map [tall] high.
  int _markAt(double y, double tall) => ((_at + tall - y) / ChatRail.pitch).floor().clamp(0, math.max(0, widget.marks.length - 1));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: Stack(children: [
        widget.child,
        if (_live && !isBevelChrome(t))
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: LayoutBuilder(builder: (context, box) {
              _lines();
              final ticks = _ticks, others = _others;
              // Its one size, a whole number of lines, however few the messages: their lines stand up from its foot, as
              // the chat's rows do from the chat's, so a line stays where it is as older messages come in over it, and
              // once there are more lines than room the map is scrolled.
              final height = (math.min(box.maxHeight * ChatRail.share, ChatRail.tallest) / ChatRail.pitch).floor() * ChatRail.pitch;
              return Center(
                widthFactor: 1,
                child: _scrollsChat(Semantics(
                  label: 'Map of this chat',
                  container: true,
                  child: GestureDetector(
                    key: const ValueKey('chat-rail'),
                    behavior: HitTestBehavior.opaque,
                    // A press goes to the message pressed.
                    onTapUp: (d) => _goTo(_markAt(d.localPosition.dy, height), run: true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: ChatRail.edge),
                      child: SizedBox(
                        width: ChatRail.width,
                        height: height,
                        child: CustomPaint(
                          painter: RailPainter(
                            ticks: ticks,
                            tall: height,
                            place: _place,
                            repaint: _c,
                            mine: t.color('app-accent'),
                            theirs: t.color('app-ink-2'),
                            hues: others.length < 2 ? const {} : {for (var i = 0; i < others.length; i++) others[i]: t.colorOf(_hues[i % _hues.length])},
                            quiet: t.color('app-ink-3'),
                          ),
                        ),
                      ),
                    ),
                  ),
                )),
              );
            }),
          ),
      ]),
    );
  }

  /// A few colours far apart, for telling the people of a group from one another; one's own is the accent.
  static const _hues = ['#e08a1e', '#3aa675', '#c45bd6', '#2aa7b8', '#d9534f', '#8a7be8'];
}

/// Draws the map's lines. Open to tests, which ask it where a message's line is.
@visibleForTesting
class RailPainter extends CustomPainter {
  RailPainter({required this.ticks, required this.tall, required this.place, required Listenable repaint, required this.mine, required this.theirs, required this.hues, required this.quiet}) : super(repaint: repaint);

  /// A line a message, the newest first.
  final List<RailTick> ticks;

  /// How tall the map is.
  final double tall;

  /// Which messages are on the screen and how far the map is scrolled, asked at each paint: the chat's scroll moves
  /// the map without a build.
  final ({double lo, double hi, double at}) Function(double tall) place;
  final Color mine, theirs, quiet;
  final Map<String, Color> hues;

  /// How far down the map the line of message [mark] is now (the newest is 0); off the map where it is under 0 or
  /// over [tall].
  double yOf(int mark) => tall - (mark + 0.5) * ChatRail.pitch + place(tall).at;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ticks.length;
    if (n == 0) return;
    final (:lo, :hi, :at) = place(tall);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = ChatRail.thick;
    // Only the lines in the map now: a long chat has many more.
    final first = math.max(0, (at / ChatRail.pitch).floor()), last = math.min(n - 1, ((at + tall) / ChatRail.pitch).ceil());
    for (var i = first; i <= last; i++) {
      // The newest at the foot.
      final y = tall - (i + 0.5) * ChatRail.pitch + at;
      if (y < 0 || y > tall) continue;
      final k = ticks[i];
      final seen = i + 1 > lo && i < hi;
      final colour = k.quiet ? quiet : (k.mine ? mine : (hues[k.who] ?? theirs));
      final length = k.quiet ? ChatRail.shortest : ChatRail.shortest + (ChatRail.longest - ChatRail.shortest) * k.rate;
      paint.color = colour.withValues(alpha: seen ? 1 : (k.quiet ? 0.28 : 0.42));
      // One's own from the right edge and everyone else's from the left, as their bubbles are, so the two are told
      // apart in a look whose accent is its ink.
      if (k.mine && !k.quiet) {
        canvas.drawLine(Offset(size.width - 2 - length, y), Offset(size.width - 2, y), paint);
      } else {
        canvas.drawLine(Offset(2, y), Offset(2 + length, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(RailPainter old) => !identical(old.ticks, ticks) || old.tall != tall || old.mine != mine || old.theirs != theirs || old.quiet != quiet;
}
