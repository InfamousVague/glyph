/// The meetings' tapes on the home page (GHST-112; Matt, 2026-10-23: "Add a shelf for meeting recordings and show
/// the note title on the cassette"): under "Meetings" and how many, a row of cassettes that scrolls sideways, the
/// newest meeting first, each with its note's title on its label on one line, centred over the window (Matt, 2026-10-24: "make
/// all cassete titles one line and center them in the open spot"), and, under it, how long it is and the
/// day it was. A tap opens the note. The meeting being recorded now is first, its reels turning and "Recording now"
/// under it. Nothing at all when there are no meetings with a tape.
///
/// A meeting is a note `prefs.meetings` has (lib/core/preferences.dart), the ones Ghost's Meet bot files among them;
/// it is shelved when it has a recording here or is known to have one elsewhere (`recordingMs`, lib/core/note_text.dart
/// `hasTape`), or is the one being recorded. The home page draws it under the notices, the upcoming meetings among
/// them, and not while searching, nor in simple mode (lib/home/home_screen.dart).
///
/// After the web's shelf of tapes (`src/app/home/TapeShelf.tsx`, gone with the dashboard, docs/DESIGN.md §147): a row
/// that scrolls, the cassettes drawn against the longest tape on the shelf, so a short meeting is a thin ring beside
/// an hour's full reel. What differs: the title is on the cassette's label (lib/tapes/tape_art.dart `centred`)
/// rather than under it, there is no caption or Summarize, and the row stays a row on a wide page.
///
/// On a computer the tapes of the cassettes in view are loaded ahead (Matt, 2026-10-24: "preload meeting audio on
/// desktop for the visible cassets so hovering is instant to play"; lib/tapes/previews.dart): those the row shows
/// and one either side, again as it scrolls and settles, none while the shelf is scrolled off the page, the page is
/// not the one shown, or the app is hidden, and all let go with the shelf. A cassette loaded ahead plays on its own
/// player the moment the rest ends; one that is not, loads on the memos' player as before.
library;

import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart' show hasTape;
import '../tapes/player.dart';
import '../tapes/previews.dart';
import '../tapes/shelf.dart';
import '../tapes/tape.dart';
import '../tapes/tape_art.dart';
import 'home_organizations.dart' show HomeHeading;
import 'home_text.dart';

/// The most cassettes the shelf holds; See all opens the rest.
const int meetingShelfMost = 12;

/// A cassette's width on the shelf, in logical pixels: its title reads at about eleven.
const double meetingTapeWidth = 188;

/// A tape played by a hover makes no touch: there is no finger.
void _quiet([HapticKind? _]) {}

/// How long the pointer rests on a cassette before its tape plays: a pointer passing over the shelf plays nothing.
const Duration meetingHoverDwell = Duration(milliseconds: 300);

/// How long the row keeps still before the cassettes in view are loaded: a fling across twelve loads only where it
/// stops.
const Duration meetingPreviewSettle = Duration(milliseconds: 120);

/// Whether the shelf's tapes are loaded ahead here: on a computer, where a mouse rests; not on a phone or a tablet.
bool get meetingPreviewsHere => switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
      _ => false,
    };

/// Which cassettes of [count] to load ahead, in order, for a row scrolled to [offset] showing [viewport] of it:
/// those in view from the left, then one past each end. Each is [width] wide, [gap] apart, after [lead].
List<int> meetingsInView({required int count, required double offset, required double viewport, double lead = 0, double width = meetingTapeWidth, double gap = 0}) {
  if (count == 0 || viewport <= 0) return const [];
  final step = width + gap;
  final seen = [
    for (var i = 0; i < count; i += 1)
      if (lead + i * step < offset + viewport && lead + i * step + width > offset) i,
  ];
  if (seen.isEmpty) return const [];
  return [...seen, if (seen.last + 1 < count) seen.last + 1, if (seen.first > 0) seen.first - 1];
}

/// When a meeting was: when it was started, as the meetings say, or when its note was made.
int meetingStart(Note note, Map<String, num> meetings) => meetings[note.id]?.toInt() ?? note.createdAt;

/// The meetings to shelve, the newest first: notes the meetings name, not archived, with a tape here or known to have
/// one, and the one being recorded now ([live]) first whatever its tape.
List<Note> shelvedMeetings(Iterable<Note> notes, Map<String, num> meetings, {String? live}) {
  if (meetings.isEmpty) return const [];
  final kept = [
    for (final note in notes)
      if (note.archivedAt == null && meetings.containsKey(note.id) && (hasTape(note) || note.id == live)) note,
  ];
  final indexed = kept.indexed.toList()
    ..sort((a, b) {
      final first = (b.$2.id == live ? 1 : 0) - (a.$2.id == live ? 1 : 0);
      if (first != 0) return first;
      final by = meetingStart(b.$2, meetings).compareTo(meetingStart(a.$2, meetings));
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
  return [for (final (_, note) in indexed) note];
}

/// What a screen reader says of a cassette: "Meeting, Standup, 23 Oct, 12:40".
String meetingSaid(Note note, Map<String, num> meetings, {bool live = false}) =>
    'Meeting, ${_title(note)}, ${tapeDate(meetingStart(note, meetings))}, ${live ? 'recording now' : counter(note.recordingMs ?? 0)}';

String _title(Note note) {
  final facts = NoteFacts.of(note);
  return facts.title.trim().isEmpty ? 'Untitled' : facts.shownTitle;
}

class MeetingShelf extends StatefulWidget {
  const MeetingShelf({super.key, required this.notes, required this.meetings, required this.onOpen, this.live, this.onSeeAll, this.player, this.previews});

  /// The notes to look through: the page's, the workspace chosen's.
  final List<Note> notes;

  /// Which notes are meetings, and when each was started (`prefs.meetings`).
  final Map<String, num> meetings;

  /// The note of the meeting being recorded now.
  final String? live;

  final ValueChanged<String> onOpen;

  /// All notes with its Tapes word on: shown when the shelf holds fewer than there are.
  final VoidCallback? onSeeAll;

  /// What a cassette plays while a mouse rests on it (Matt, 2026-10-24: "when we hover a tape, start playing it's
  /// audio and animate the cassete on desktop"): the memos' player, not the tape's, so a note open beside the shelf
  /// keeps its playhead. None, and a hover only lights the cassette.
  final TapePlayer? player;

  /// The players the cassettes in view are loaded into ahead, on a computer (lib/tapes/previews.dart): one loaded
  /// plays on its own at the end of the rest, with nothing to load. None, and every hover loads on [player].
  final TapePreviews? previews;

  @override
  State<MeetingShelf> createState() => _MeetingShelfState();
}

class _MeetingShelfState extends State<MeetingShelf> {
  final ScrollController _row = ScrollController();
  late final AppLifecycleListener _life;
  ScrollPosition? _page;
  Timer? _settling;
  bool _shown = true;

  /// The cassettes on the shelf, and the room in front of and between them, as last built.
  List<Note> _tapes = const [];
  double _lead = 0, _gap = 0;

  @override
  void initState() {
    super.initState();
    _row.addListener(_settle);
    // Hidden, nothing is loaded; back, what is in view is again.
    _life = AppLifecycleListener(onStateChange: (_) => _settle(at: Duration.zero));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page the shelf is on scrolls too: off it, nothing is loaded. And a page not shown (TickerMode off) has
    // nothing loaded.
    final page = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (page != _page) {
      _page?.removeListener(_settle);
      _page = page?..addListener(_settle);
    }
    _shown = TickerMode.valuesOf(context).enabled;
    _settle(at: Duration.zero);
  }

  @override
  void didUpdateWidget(MeetingShelf old) {
    super.didUpdateWidget(old);
    if (old.previews != widget.previews) old.previews?.releaseAll();
    _settle(at: Duration.zero);
  }

  @override
  void dispose() {
    _settling?.cancel();
    _row.dispose();
    _page?.removeListener(_settle);
    _life.dispose();
    widget.previews?.releaseAll();
    super.dispose();
  }

  /// Load what is in view once the row and the page keep still ([at] after the last move; at once after a build).
  void _settle({Duration at = meetingPreviewSettle}) {
    if (widget.previews == null) return;
    _settling?.cancel();
    _settling = Timer(at, () {
      if (!mounted) return;
      // Hidden, the app draws no frames to wait for: let go now.
      if (!_awake) return widget.previews?.releaseAll();
      WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// The app in front, or at least in sight (a Mac window not focused is still under the mouse).
  bool get _awake => switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };

  void _preview() {
    final previews = widget.previews;
    if (!mounted || previews == null) return;
    if (!meetingPreviewsHere || !_awake || !_shown || !_row.hasClients || !_onPage()) {
      previews.releaseAll();
      return;
    }
    final position = _row.position;
    final tapes = _tapes;
    final ids = [
      for (final i in meetingsInView(count: tapes.length, offset: position.pixels, viewport: position.viewportDimension, lead: _lead, gap: _gap))
        if (tapes[i].id != widget.live && (tapes[i].recordingMs ?? 0) > 0) tapes[i].id,
    ];
    previews.want(ids);
  }

  /// Whether any of the shelf is inside the page's view.
  bool _onPage() {
    final page = _page;
    final box = context.findRenderObject();
    final view = page?.context.notificationContext?.findRenderObject();
    if (page == null || box is! RenderBox || !box.hasSize || view is! RenderBox || !view.hasSize) return true;
    final at = box.localToGlobal(Offset.zero, ancestor: view);
    return (at & box.size).overlaps(Offset.zero & view.size);
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final all = shelvedMeetings(widget.notes, widget.meetings, live: widget.live);
    if (all.isEmpty) {
      _tapes = const [];
      return const SizedBox.shrink();
    }
    final shown = all.take(meetingShelfMost).toList(growable: false);
    final t = context.tokens;
    final ink3 = t.color('app-ink-3');
    // The longest tape on the shelf, at least five minutes: what every cassette here is drawn against.
    final lengthMs = shown.fold<int>(tapeMs, (most, note) => math.max(most, note.recordingMs ?? 0));
    final gap = t.space(4);
    final meetings = widget.meetings, live = widget.live, onSeeAll = widget.onSeeAll;
    final changed = !listEquals([for (final n in _tapes) n.id], [for (final n in shown) n.id]);
    _tapes = shown;
    _lead = t.space(1);
    _gap = gap;
    if (changed) _settle(at: Duration.zero);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: const ValueKey('meeting-shelf'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: HomeHeading(mark: TapeMark(em: t.fontSize('sm'), color: ink3), words: 'Meetings', count: all.length)),
              if (onSeeAll != null && all.length > shown.length) AppWord(key: const ValueKey('meeting-shelf-all'), onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          SizedBox(height: t.space(2)),
          SingleChildScrollView(
            key: const ValueKey('meeting-shelf-row'),
            controller: _row,
            scrollDirection: Axis.horizontal,
            // Room for the focus ring, which the row would clip at its edges.
            padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(1)),
            clipBehavior: Clip.hardEdge,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, note) in shown.indexed) ...[
                  if (i > 0) SizedBox(width: gap),
                  _MeetingTape(key: ValueKey('meeting-tape-${note.id}'), note: note, meetings: meetings, lengthMs: lengthMs, live: note.id == live, onOpen: widget.onOpen, player: widget.player, previews: widget.previews),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One cassette: the note's title on its label, its length and its day under it; a tap opens it. A mouse resting on
/// it plays its tape from the start, on the player [previews] loaded it into ahead where one did, else on [player],
/// the reels turning and the tape winding with whichever plays, the cassette lifted a little; the mouse leaving
/// stops it. Not the meeting being recorded, nor a tape with nothing to play it.
class _MeetingTape extends StatefulWidget {
  const _MeetingTape({super.key, required this.note, required this.meetings, required this.lengthMs, required this.live, required this.onOpen, this.player, this.previews});

  final Note note;
  final Map<String, num> meetings;
  final int lengthMs;
  final bool live;
  final ValueChanged<String> onOpen;
  final TapePlayer? player;
  final TapePreviews? previews;

  @override
  State<_MeetingTape> createState() => _MeetingTapeState();
}

class _MeetingTapeState extends State<_MeetingTape> {
  Timer? _dwell;
  Tape? _tape;
  bool _hovered = false;

  /// The player the previews lent the tape playing, to be handed back when it stops.
  TapePlayer? _lent;

  /// Which rest this is: one ended by the mouse leaving while a player was being found plays nothing.
  int _rest = 0;

  void _enter() {
    setState(() => _hovered = true);
    if ((widget.player == null && widget.previews == null) || widget.live || (widget.note.recordingMs ?? 0) <= 0) return;
    _dwell?.cancel();
    final rest = _rest += 1;
    _dwell = Timer(meetingHoverDwell, () => unawaited(_play(rest)));
  }

  /// The rest is over: play on the player loaded ahead, if there is one, or load it on the memos' as before.
  Future<void> _play(int rest) async {
    final previews = widget.previews;
    final note = widget.note;
    final lent = previews == null ? null : await previews.take(note.id);
    if (!mounted || !_hovered || rest != _rest || _tape != null || widget.note.id != note.id) {
      if (lent != null) previews!.done(lent);
      return;
    }
    final player = lent ?? widget.player;
    if (player == null) return;
    _lent = lent;
    final tape = _tape = Tape(note, player: player, haptic: _quiet, loaded: lent != null)..addListener(_redraw);
    unawaited(tape.toggle());
  }

  void _leave() {
    _dwell?.cancel();
    _dwell = null;
    _rest += 1;
    _stop();
    if (mounted) setState(() => _hovered = false);
  }

  /// A tape stopped is let go: disposing of it pauses the player, which is not its own; one lent by the previews
  /// goes back to them, at its start again.
  void _stop() {
    final tape = _tape, lent = _lent;
    _tape = null;
    _lent = null;
    tape?..removeListener(_redraw)..dispose();
    if (lent != null) widget.previews?.done(lent);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_MeetingTape old) {
    super.didUpdateWidget(old);
    if (old.note.id != widget.note.id || old.player != widget.player || old.previews != widget.previews) {
      // Handed back to the previews it came from.
      final lent = _lent;
      _lent = null;
      _stop();
      if (lent != null) old.previews?.done(lent);
    }
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note, live = widget.live;
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final radius = t.radius('md');
    final tape = _tape;
    final playing = tape != null && tape.playing;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _leave(),
      child: GlacierPressable(
        onPressed: () {
          // The note's own tape takes it from here.
          _leave();
          widget.onOpen(note.id);
        },
        semanticLabel: meetingSaid(note, widget.meetings, live: live),
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: radius,
          child: SizedBox(
            width: meetingTapeWidth,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.cassette:active`: it gives a little when pressed, as the web's did; and is lifted a little under
                  // a resting mouse.
                  AnimatedSlide(
                    offset: Offset(0, _hovered && !state.pressed ? -0.03 : 0),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: AnimatedScale(
                      scale: state.pressed ? 0.97 : (_hovered ? 1.03 : 1),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: TapeArt(
                        // Playing, the tape winds with the playhead; else it is the whole recording on the right reel.
                        positionMs: tape != null ? tape.at : note.recordingMs ?? 0,
                        lengthMs: widget.lengthMs,
                        playing: live || playing,
                        title: _title(note),
                        centred: true,
                        hue: tapeHue(note.id),
                      ),
                    ),
                  ),
                  SizedBox(height: t.space(2)),
                  Text.rich(
                    TextSpan(
                      children: [
                        ...tapeWordSpans(t, note, live: live, em: xs, dot: !live),
                        TextSpan(text: tapeDate(meetingStart(note, widget.meetings)), style: tabular(pageText(t, xs, color: t.color('glacier-text-subtle')))),
                      ],
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
