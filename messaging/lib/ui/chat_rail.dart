/// A chat's map, in the gutter at its right: a short line for each message, one under another, from the oldest held
/// at the top to the newest at the foot (Matt, 2026-11-25: "in the right hand of the chat gutter add this same style of
/// chat scrolling to show frequency of messages and who differently sent messages etc", with a picture of a document's
/// outline drawn as a column of ticks). A line's colour and side are who sent it (one's own in the accent from the
/// right, each other person's in their own colour from the left, as their bubbles are), its length how fast the chat was going there (a long line is one of many within a few minutes, a short
/// one stands alone), and the lines of what is on the screen now are the bright ones. A press on it goes there, and a
/// mouse can drag along it.
///
/// With the mouse over it (a press, on a phone) the map opens into a list of the chat's stretches, a stretch being
/// what was said without a long pause: who wrote in it, by their faces, and a line about it (Matt, 2026-11-25:
/// "hovering over it should show profile pictures and a brief summary of the messages if a local AI is enabled").
/// The line is the phone's own model's summary where it has one (lib/summaries.dart: nothing leaves the phone), and
/// otherwise how the stretch began, in its first words.
///
/// The list under it is built a row at a time, so where a message is on the page is not known until it is drawn: the
/// map takes the list's scroll as a share of its whole length and the messages as evenly spread over it. Near
/// enough to read and to steer by; a press lands within a screen of what was pressed.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show Drag, GestureBinding, PointerDeviceKind, PointerScrollEvent, VerticalDragGestureRecognizer;
import 'package:flutter/rendering.dart' show RenderSliverMultiBoxAdaptor, SliverMultiBoxAdaptorParentData;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import '../summaries.dart';
import 'common.dart';
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

  /// The chat, by anything that tells it from another: summaries are kept against it.
  final String chat;

  /// Someone's face at a size; their initials where none is given.
  final Widget Function(String who, String name, bool mine, double size)? face;

  /// Sums a stretch up ([RailStretch.lines]); null from it where it cannot. The phone's own model where none is
  /// given ([own]). Given by a test.
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

  /// The space from one line to the next: as much as there is room for, between these.
  static const double tightest = 6, loosest = 12;

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

  /// The most stretches listed.
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

  /// The phone's own model, where it has one and the person has not turned summaries off; null otherwise (a
  /// computer, a phone without one): then a stretch's line is its first words.
  static Future<String?> Function(String lines)? own(BuildContext context) {
    final app = AppState.maybeOf(context);
    if (app == null || !Summaries.chosen(app) || Summaries.instance.status != 'available') return null;
    return Sms.instance.summarize;
  }

  /// Summaries made, by chat and stretch, so a stretch is summed up once; a null is one tried that came to nothing.
  static final Map<String, String?> _made = {};

  @override
  State<ChatRail> createState() => _ChatRailState();
}

class _ChatRailState extends State<ChatRail> {
  bool _live = false, _hover = false, _open = false;
  List<RailStretch>? _stretches;
  bool _summing = false;

  ScrollController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_moved);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(ChatRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, _c)) {
      old.controller.removeListener(_moved);
      _c.addListener(_moved);
      _list = null;
    }
    if (old.chat != widget.chat) _list = null;
    if (old.marks.length != widget.marks.length || old.chat != widget.chat || (widget.marks.isNotEmpty && old.marks.isNotEmpty && old.marks.first.at != widget.marks.first.at)) {
      _stretches = null;
      if (_shown) _sum();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _c.removeListener(_moved);
    super.dispose();
  }

  bool get _shown => _hover || _open;

  /// While the list is open the row of what is on the screen follows the scroll. Built again only when that row
  /// becomes another: the map's own lines are painted from the scroll without a build (Matt, 2026-11-25: "using the
  /// chat map is still pretty laggy"; every frame of a scroll built the whole list of stretches and worked the lines
  /// out again).
  void _moved() {
    if (!mounted || !_shown || _looks) return;
    // Looked at once the list is laid out where it was scrolled to: until then its rows are where they were.
    _looks = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looks = false;
      if (mounted && _shown && _hereNow()?.oldest != _hereShown) setState(() {});
    });
  }

  bool _looks = false;

  /// The stretch in the middle of the screen now.
  RailStretch? _hereNow() {
    final n = widget.marks.length;
    if (n == 0) return null;
    final (from, to) = _view();
    final middle = ((from + to) / 2 * n).floor().clamp(0, n - 1);
    for (final s in _all) {
      if (middle >= s.newest && middle <= s.oldest) return s;
    }
    return null;
  }

  /// The stretch the list was last built with as the one on the screen, by its oldest message.
  int? _hereShown;

  /// The map's lines and the people's colours, kept until the messages or the room change: a build asks for them
  /// each time, and they are a pass over every message.
  (int, int, int, int)? _ticksOf;
  List<RailTick> _ticks = const [];
  List<String> _others = const [];

  void _lines(int rows) {
    final m = widget.marks;
    final now = (m.length, m.isEmpty ? 0 : m.first.at, m.isEmpty ? 0 : m.last.at, rows);
    if (_ticksOf == now) return;
    _ticksOf = now;
    _ticks = ChatRail.ticksOf(m, rows);
    _others = {for (final x in m) if (!x.mine && !x.quiet) x.who}.toList()..sort();
  }

  /// There is a map where there is a chat to find one's way in: enough messages, and more of them than a screen.
  void _measure() {
    if (!mounted) return;
    final live = widget.marks.length >= ChatRail.fewest && _c.hasClients && _c.position.hasContentDimensions && _c.position.maxScrollExtent > 40;
    if (live != _live) setState(() => _live = live);
  }

  List<RailStretch> get _all => _stretches ??= ChatRail.stretchesOf(widget.marks);

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

  /// Which of the messages are on the screen: (from, to) as shares of them all from the newest end, each 0 to 1.
  /// Exactly, from the rows on the screen; by the scroll's share of its whole length until the list is laid out.
  (double, double) _view() {
    if (!_c.hasClients || !_c.position.hasContentDimensions) return (0, 1);
    final p = _c.position;
    final n = widget.marks.length;
    if (n > 0) {
      int? first, last;
      _laid().forEach((index, row) {
        if (row.at + row.tall <= p.pixels || row.at >= p.pixels + p.viewportDimension) return;
        final mark = index - widget.lead;
        if (mark < 0 || mark >= n) return;
        if (first == null || mark < first!) first = mark;
        if (last == null || mark > last!) last = mark;
      });
      if (first != null) return (first! / n, (last! + 1) / n);
    }
    final whole = p.maxScrollExtent + p.viewportDimension;
    if (whole <= 0) return (0, 1);
    final at = p.pixels.clamp(0.0, p.maxScrollExtent);
    return (at / whole, (at + p.viewportDimension) / whole);
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

  /// A drag along the map: the newest place asked for is gone to once a frame, not once for every move of the mouse
  /// (several come in a frame, and each began a going of its own).
  int? _dragTo;
  bool _dragWaits = false;

  void _dragGo(int mark) {
    _dragTo = mark;
    if (_dragWaits) return;
    _dragWaits = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _dragWaits = false;
      final to = _dragTo;
      _dragTo = null;
      if (mounted && to != null) _goTo(to);
    });
  }

  /// A wheel turned over the map or its list scrolls the chat, as it would over the chat itself (Matt, 2026-11-25:
  /// "i can't scroll up and down in the popup menu to scroll up and down either"): the two stand over the chat's list,
  /// which never heard the wheel there. The list of stretches follows, the one on the screen in its middle.
  void _wheel(PointerScrollEvent e) {
    if (!_c.hasClients || e.scrollDelta.dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      // The chat's list is drawn bottom up, so a turn down the page is toward its start.
      if (_c.hasClients) _c.position.pointerScroll(-(e as PointerScrollEvent).scrollDelta.dy);
    });
  }

  /// Two fingers on a trackpad, over the map or its list: the chat's own drag, with its glide after.
  Drag? _pan;

  Widget _scrollsChat(Widget child) => Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _wheel(e);
        },
        child: RawGestureDetector(
          gestures: {
            VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.trackpad}),
              (r) => r
                ..onStart = (d) {
                  _pan?.cancel();
                  _pan = _c.hasClients ? _c.position.drag(d, () => _pan = null) : null;
                }
                ..onUpdate = ((d) => _pan?.update(d))
                ..onEnd = ((d) => _pan?.end(d))
                ..onCancel = (() => _pan?.cancel()),
            ),
          },
          child: child,
        ),
      );

  /// The message a point of the map stands for: [share] of the way up it from the newest.
  int _markAt(double share) => (share.clamp(0.0, 1.0) * widget.marks.length).floor().clamp(0, math.max(0, widget.marks.length - 1));

  /// The row of the list of stretches that is the one on the screen, kept in the middle of the list as the chat is
  /// scrolled (Matt, 2026-11-25: "when scrolling up and down the chat map the popover doesn't center what we're on").
  final GlobalKey _here = GlobalKey();
  int? _hereWas;

  void _follow(int oldest) {
    if (_hereWas == oldest) return;
    _hereWas = oldest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _here.currentContext;
      if (!mounted || at == null) return;
      Scrollable.ensureVisible(at, alignment: 0.5, duration: context.tokens.reducedMotion ? Duration.zero : const Duration(milliseconds: 160), curve: Curves.easeOut);
    });
  }

  String _key(RailStretch s) => '${widget.chat}\t${widget.marks[s.oldest].at}\t${widget.marks[s.newest].at}\t${s.count}';

  /// Has each stretch worth it summed up, one after another, the newest first.
  Future<void> _sum() async {
    final make = widget.summarize ?? ChatRail.own(context);
    if (make == null || _summing) return;
    _summing = true;
    try {
      while (mounted && _shown) {
        final marks = widget.marks;
        final next = _all.where((s) => s.lines.isNotEmpty && !ChatRail._made.containsKey(_key(s))).firstOrNull;
        if (next == null) break;
        final key = _key(next);
        String? text;
        try {
          text = (await make(next.lines))?.trim();
        } catch (_) {
          text = null;
        }
        ChatRail._made[key] = text == null || text.isEmpty ? null : text;
        if (mounted && identical(marks, widget.marks)) setState(() {});
      }
    } finally {
      _summing = false;
    }
  }

  void _show({bool? hover, bool? open}) {
    final was = _shown;
    setState(() {
      _hover = hover ?? _hover;
      _open = open ?? _open;
    });
    if (_shown && !was) _sum();
  }

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
        // Opened by a press (a phone): a press anywhere else puts the list away (Matt, 2026-11-25: "you can't tap
        // outside of the map popup to close the map").
        if (_live && _open && !isBevelChrome(t))
          Positioned.fill(
            child: GestureDetector(key: const ValueKey('chat-rail-away'), behavior: HitTestBehavior.opaque, onTap: () => _show(open: false)),
          ),
        if (_live && !isBevelChrome(t))
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: LayoutBuilder(builder: (context, box) {
              final room = math.min(box.maxHeight * ChatRail.share, ChatRail.tallest);
              final rows = math.max(1, math.min(widget.marks.length, room ~/ ChatRail.tightest));
              final pitch = (room / rows).clamp(ChatRail.tightest, ChatRail.loosest);
              _lines(rows);
              final ticks = _ticks, others = _others;
              final height = ticks.length * pitch;
              double shareAt(Offset local) => (1 - local.dy / height).clamp(0.0, 1.0);
              final rail = Semantics(
                label: 'Map of this chat',
                container: true,
                child: GestureDetector(
                  key: const ValueKey('chat-rail'),
                  behavior: HitTestBehavior.opaque,
                  // Not a trackpad's two fingers, which scroll the chat (_scrollsChat).
                  supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus, PointerDeviceKind.unknown},
                  // A press goes there with a mouse over it; on a phone it opens the list of stretches, and again
                  // puts it away.
                  onTapUp: (d) => d.kind == PointerDeviceKind.mouse || d.kind == PointerDeviceKind.trackpad ? _goTo(_markAt(shareAt(d.localPosition)), run: true) : _show(open: !_open),
                  onVerticalDragUpdate: _hover ? (d) => _dragGo(_markAt(shareAt(d.localPosition))) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ChatRail.edge),
                    child: SizedBox(
                    width: ChatRail.width,
                    height: height,
                    child: CustomPaint(
                      painter: _RailPainter(
                        ticks: ticks,
                        pitch: pitch,
                        view: _view,
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
              );
              return MouseRegion(
                onEnter: (_) => _show(hover: true),
                onExit: (_) => _show(hover: false),
                child: _scrollsChat(Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  if (_shown) _panel(t, box.maxHeight),
                  rail,
                ])),
              );
            }),
          ),
      ]),
    );
  }

  /// A few colours far apart, for telling the people of a group from one another; one's own is the accent.
  static const _hues = ['#e08a1e', '#3aa675', '#c45bd6', '#2aa7b8', '#d9534f', '#8a7be8'];

  /// The list of the chat's stretches, the oldest at the top as the map has them.
  Widget _panel(Tokens t, double room) {
    final list = _all.reversed.toList();
    final here = _hereNow();
    _hereShown = here?.oldest;
    if (here != null) _follow(here.oldest);
    return Container(
      key: const ValueKey('chat-rail-list'),
      width: 300,
      constraints: BoxConstraints(maxHeight: math.max(120, room - t.space(6))),
      margin: EdgeInsets.only(left: t.space(3), right: 2),
      padding: EdgeInsets.symmetric(vertical: t.space(1)),
      decoration: BoxDecoration(
        color: t.color('app-paper'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule'), width: 1),
        boxShadow: t.shadowOf('0 8px 28px rgba(0,0,0,0.22)'),
      ),
      child: SingleChildScrollView(
        // Under a mouse the list is not scrolled by itself: a wheel over it scrolls the chat, and it follows. Opened by
        // a press (a phone) it is dragged as any list is.
        physics: _open ? null : const NeverScrollableScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in list)
            if (identical(s, here)) KeyedSubtree(key: _here, child: _row(t, s, here: true)) else _row(t, s, here: false),
        ]),
      ),
    );
  }

  Widget _row(Tokens t, RailStretch s, {required bool here}) {
    final summary = s.lines.isEmpty ? null : ChatRail._made[_key(s)];
    final when = DateTime.fromMillisecondsSinceEpoch(widget.marks[s.oldest].at);
    final faces = s.people.take(3).toList();
    const face = 20.0;
    Widget faceOf(({String who, String name, bool mine}) p) =>
        widget.face?.call(p.who, p.name, p.mine, face) ?? Avatar(people: [Person(address: p.mine ? '' : p.who, name: p.mine ? 'You' : (p.name.isEmpty ? null : p.name))], size: face, presence: false);
    return GlacierPressable(
      key: ValueKey('chat-rail-stretch-${s.oldest}'),
      onPressed: () {
        // To where the stretch begins, its first message at the top, to be read on from.
        _goTo(s.oldest, top: true, run: true);
        if (_open) _show(open: false);
      },
      semanticLabel: '${dayHeading(when)}, ${s.count} ${s.count == 1 ? 'message' : 'messages'}. ${summary ?? s.opening}',
      builder: (context, state) => Container(
        margin: EdgeInsets.symmetric(horizontal: t.space(1), vertical: 1),
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1) + 2),
        decoration: BoxDecoration(
          color: here ? t.color('app-paper-3') : (state.hovered || state.pressed ? t.color('app-paper-2') : null),
          borderRadius: BorderRadius.circular(t.radius('md')),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Their faces, each a little over the last.
          SizedBox(
            width: face + (faces.length - 1).clamp(0, 2) * 15.0,
            height: face,
            child: Stack(children: [
              for (var i = faces.length - 1; i >= 0; i--)
                Positioned(
                  left: i * 15.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.color('app-paper'), width: 1.5)),
                    position: DecorationPosition.foreground,
                    child: SizedBox.square(dimension: face, child: faceOf(faces[i])),
                  ),
                ),
            ]),
          ),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(
                summary ?? (s.opening.isEmpty ? 'No words' : s.opening),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: pageText(t, t.fontSize('sm'), weight: here ? 'semibold' : 'regular', color: t.color(here ? 'app-ink' : 'app-ink-2')),
              ),
              const SizedBox(height: 1),
              Row(children: [
                // A summary is marked as one: these are a model's words, not anyone's in the chat.
                if (summary != null) ...[
                  AppIcon(Lucide.sparkles, size: 11, color: t.color('app-ink-3'), wash: false),
                  SizedBox(width: t.space(1)),
                ],
                Flexible(
                  child: Text(
                    '${dayHeading(when)}, ${clock(when)} · ${s.count} ${s.count == 1 ? 'message' : 'messages'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.ticks, required this.pitch, required this.view, required Listenable repaint, required this.mine, required this.theirs, required this.hues, required this.quiet}) : super(repaint: repaint);
  final List<RailTick> ticks;
  final double pitch;
  final (double, double) Function() view;
  final Color mine, theirs, quiet;
  final Map<String, Color> hues;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ticks.length;
    if (n == 0) return;
    final (from, to) = view();
    final paint = Paint()
      ..strokeWidth = ChatRail.thick
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final k = ticks[i];
      // The newest at the foot.
      final y = size.height - (i + 0.5) * pitch;
      final seen = (i + 1) / n > from && i / n < to;
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
  bool shouldRepaint(_RailPainter old) => !identical(old.ticks, ticks) || old.pitch != pitch || old.mine != mine || old.theirs != theirs || old.quiet != quiet;
}
