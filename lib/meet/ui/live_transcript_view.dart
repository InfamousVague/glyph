/// A meeting's Transcript while it is still going on (Matt, 2026-10-30: "If possible add real time transcriptions for
/// meetings"): its live words (lib/meet/live_transcript.dart) as the meeting's turns, each its speaker and time over
/// its words as the finished transcript's are (lib/tapes/transcript_words.dart [TranscriptTurn]), the line being said
/// last in the lighter ink, and a Live badge over them.
///
/// - **Follows the newest words**, and stops the moment the person scrolls up to read back; "Back to live" over the
///   foot takes it down again and follows from there.
/// - **Ended**: the badge goes and a line says the transcript is on its way; the take's (or the write-up's) replaces
///   this view as soon as the note has it.
/// - **Simple mode** shows it too, calm: no colour, the badge's dot in the ink.
///
/// [LiveTranscriptPill] is the Note view's small way here while the meeting runs, and [LiveLines] the phone's meeting
/// screen's few scrolling lines under the cassette.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../capture/meeting_live_words.dart' show MeetingLiveWords, meetingLiveWordsHere;
import '../../art/lucide.g.dart';
import '../../tapes/transcript_words.dart' show ShownTurn, TranscriptLight, TranscriptTurn;
import '../live_transcript.dart';

/// The Live badge: a dot and the word, small. Red in the advanced app, the ink in Simple.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.simple = false, this.label = 'Live'});

  final bool simple;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink-2');
    return Semantics(
      label: 'Live transcript',
      container: true,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('live-badge'),
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1) / 2),
          decoration: BoxDecoration(border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(t.radius('full'))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: simple ? ink : t.color('glacier-red-9'))),
              SizedBox(width: t.space(1) + 2),
              Text(label, style: t.text('xs', weight: 'semibold', color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The meeting's live words as its Transcript (see the header).
class LiveTranscriptView extends StatefulWidget {
  const LiveTranscriptView({super.key, required this.noteId, this.store, this.simple = false, this.watcher});

  final String noteId;

  /// What hears a meeting recorded on this phone while someone looks (lib/capture/meeting_live_words.dart); this
  /// device's where none is given, and nothing on a device with no meeting service.
  final MeetingLiveWords? watcher;

  /// The live words; this device's where none is given.
  final LiveTranscripts? store;
  final bool simple;

  @override
  State<LiveTranscriptView> createState() => _LiveTranscriptViewState();
}

class _LiveTranscriptViewState extends State<LiveTranscriptView> {
  final ScrollController _scroll = ScrollController();

  /// Whether the view keeps to the newest words: until the person scrolls up, and again after Back to live.
  bool _following = true;

  LiveTranscripts get _store => widget.store ?? liveTranscripts;

  VoidCallback? _offWatch;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    // Looked at: a meeting this phone records is heard while it is (never one Ghost is in, whose words are the bot's).
    final watcher = _watcher;
    if (watcher != null && _store.of(widget.noteId)?.from != LiveFrom.bot) {
      _offWatch = watcher.watch(widget.noteId);
      watcher.addListener(_changed);
    }
    _toEnd(jump: true);
  }

  MeetingLiveWords? get _watcher => widget.watcher ?? meetingLiveWordsHere;

  /// Whether this phone records the meeting now.
  bool get _recordingHere {
    final state = _watcher?.meeting.state;
    return state != null && state.recording && state.noteId == widget.noteId;
  }

  @override
  void didUpdateWidget(LiveTranscriptView old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      (old.store ?? liveTranscripts).removeListener(_changed);
      _store.addListener(_changed);
    }
  }

  @override
  void dispose() {
    if (_offWatch != null) _watcher?.removeListener(_changed);
    _offWatch?.call();
    _store.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_following) _toEnd();
  }

  /// Down to the newest words, once they are drawn.
  void _toEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump || context.tokens.reducedMotion) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  /// A person's scroll: up, away from the newest words, lets them go; back at the foot, they are followed again.
  bool _scrolled(ScrollNotification note) {
    if (note is UserScrollNotification) {
      final position = _scroll.hasClients ? _scroll.position : null;
      final atEnd = position == null || position.pixels >= position.maxScrollExtent - 24;
      if (note.direction == ScrollDirection.forward && _following) {
        setState(() => _following = false);
      } else if (note.direction == ScrollDirection.idle && atEnd && !_following) {
        setState(() => _following = true);
      }
    }
    return false;
  }

  void _backToLive() {
    setState(() => _following = true);
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = _store.of(widget.noteId);
    final here = _recordingHere;
    final live = (words?.live ?? false) || here;
    final device = words != null ? words.from == LiveFrom.device : here;
    final why = here ? _watcher?.why(widget.noteId) : null;
    final turns = words?.turns ?? const <ShownTurn>[];
    final saying = words?.saying != null;
    final room = t.space(2);
    final small = t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'));
    final gutter = EdgeInsetsDirectional.fromSTEB(math.max(0, t.len('app-gutter-start') - room), 0, math.max(0, t.len('app-gutter-end') - room), 0);
    // The badge and what the words are stay over the turns, which scroll under them: in view whichever turn is.
    final head = Padding(
      padding: gutter.add(EdgeInsets.only(top: t.space(2), bottom: t.space(2))),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: room),
        child: Row(
          children: [
            if (live) LiveBadge(simple: widget.simple),
            if (live) SizedBox(width: t.space(2)),
            Expanded(
              child: Text(
                live
                    ? why ?? (device ? 'Heard on this device while the screen is on.' : 'From the meeting’s captions, as they come.')
                    : 'The meeting has ended. Its transcript is on its way.',
                key: const ValueKey('live-line'),
                style: small,
              ),
            ),
          ],
        ),
      ),
    );
    final lines = <Widget>[
      if (turns.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: room),
          child: Semantics(liveRegion: true, child: Text(live ? (why != null ? 'No words yet.' : 'Listening. The words come as people speak.') : 'Nothing was heard.', key: const ValueKey('live-empty'), style: small)),
        ),
      for (final (i, turn) in turns.indexed) ...[
        if (i > 0) SizedBox(height: t.space(2)),
        TranscriptTurn(key: ValueKey('live-turn-$i'), turn: turn, light: saying && i == turns.length - 1 ? TranscriptLight.coming : TranscriptLight.reading),
      ],
    ];
    final padding = gutter.add(EdgeInsets.only(top: t.space(2), bottom: t.space(24)));
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head,
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _scrolled,
                child: SingleChildScrollView(
                  key: const ValueKey('live-transcript'),
                  controller: _scroll,
                  padding: padding,
                  child: SizedBox(width: double.infinity, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lines)),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: t.space(6),
          child: Center(
            child: AnimatedSwitcher(
              duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
              child: live && !_following ? _BackToLive(onPressed: _backToLive) : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Back to live, over the foot once the person has scrolled up to read back: takes the view to the newest words and
/// follows them again. The transcript's Follow, in its shape.
class _BackToLive extends StatelessWidget {
  const _BackToLive({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-paper');
    return GlacierPressable(
      key: const ValueKey('back-to-live'),
      onPressed: onPressed,
      semanticLabel: 'Back to live',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        offset: 3,
        color: t.color('app-ink'),
        child: AnimatedScale(
          scale: state.pressed ? 0.98 : 1,
          duration: t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(8)),
            padding: EdgeInsets.symmetric(horizontal: t.space(4)),
            decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(Lucide.arrowDown, size: 15, strokeWidth: 2.2, color: ink),
                  SizedBox(width: t.space(2)),
                  Text('Back to live', style: t.text('sm', weight: 'semibold', color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Note view's way to the live transcript while the meeting runs: a small pill, the badge's dot and "Live
/// transcript".
class LiveTranscriptPill extends StatelessWidget {
  const LiveTranscriptPill({super.key, required this.onPressed, this.simple = false});

  final VoidCallback onPressed;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink-2');
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), 0, t.len('app-gutter-end'), t.space(2)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GlacierPressable(
          key: const ValueKey('live-transcript-pill'),
          onPressed: onPressed,
          semanticLabel: 'Live transcript',
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('full'),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
              decoration: BoxDecoration(
                color: state.hovered || state.pressed ? t.color('app-wash') : null,
                border: Border.all(color: t.color('app-rule')),
                borderRadius: BorderRadius.circular(t.radius('full')),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: simple ? ink : t.color('glacier-red-9'))),
                    SizedBox(width: t.space(2)),
                    Text('Live transcript', style: t.text('sm', weight: 'medium', color: ink)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's meeting screen's live words: the last few turns under the cassette, the newest at the foot, the
/// oldest fading at the top. Nothing where there are none.
class LiveLines extends StatelessWidget {
  const LiveLines({super.key, required this.noteId, this.store, this.lines = 3});

  final String noteId;
  final LiveTranscripts? store;

  /// How many turns are shown.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? liveTranscripts;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = context.tokens;
        final words = store.of(noteId);
        final turns = words?.turns ?? const <ShownTurn>[];
        if (words == null || !words.live) return const SizedBox.shrink();
        final shown = turns.length > lines ? turns.sublist(turns.length - lines) : turns;
        final style = t.textAt(t.fontSize('md'), height: 1.45, color: t.color('app-ink-2'));
        final time = t.textAt(t.fontSize('sm'), color: t.color('app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.lenOf('28rem')),
          child: Semantics(
            liveRegion: true,
            label: 'Live transcript',
            child: Column(
              key: const ValueKey('live-lines'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LiveBadge(simple: true),
                SizedBox(height: t.space(2)),
                if (shown.isEmpty) Text('Listening.', style: style),
                for (final (i, turn) in shown.indexed)
                  Opacity(
                    opacity: shown.length > 1 && i == 0 && turns.length > lines ? 0.55 : 1,
                    child: Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : t.space(2)),
                      child: Text.rich(
                        TextSpan(children: [
                          if (turn.startMs != null) TextSpan(text: '${_clock(turn.startMs!)}  ', style: time),
                          if (turn.speaker != null) TextSpan(text: '${turn.speaker}  ', style: style.copyWith(fontWeight: FontWeight.w600)),
                          TextSpan(text: turn.text),
                        ]),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}
