/// The words as they were spoken, lit as they are heard. The phrase under the playhead is in the first ink on the
/// wash, the ones already heard in the transcript's own ink, the ones still to come a step lighter, and the page keeps
/// the lit one in view while the tape plays. Tapping a phrase takes the tape there. A port of `TranscriptWords` in
/// `src/app/tapes/NoteTape.tsx`, with `.transcript`, `.words`, `.phrase` and `.phraseSkeleton` of
/// NoteTape.module.css.
///
/// What differs: on the page it shared a file with the tape's strip; it is split out here. A phrase's two
/// attributes (`data-current`, `data-past`) are [TranscriptPhrase]'s `current` and `past`. The page's
/// `scrollIntoView({ block: 'center', behavior: 'smooth' })` is the transcript's own scroll taken to put the lit line
/// in its middle over the kit's normal duration, since a browser's smooth scroll has no length of its own to copy;
/// the note's page around it is left where it is, so the tape and its Play stay in sight.
///
/// The port's own (Matt, 2026-10-24: "when clicking on meetings it doesn't load the transcript"): a meeting opened
/// anywhere shows this with its tape still (lib/note/land_at.dart `atTranscript`), so the words are read here and not
/// only heard. Where the phrases do not carry the meeting's words, the words the note keeps under `## Transcript` do,
/// a paragraph each ([writtenTranscript]): a meeting whose phrases have not come to this device, one whose only
/// phrase is the live recognizer's first word ([phrasesWhole]), a Meet note whose transcript is Meet's captions.
/// While its write-up is still to come the place says so first ([TranscriptWords.writeUp], "Writing up… 42%"), over
/// the captions where Meet gave any, rather than standing empty.
///
/// And lit, whichever words are shown (Matt, 2026-10-25: "the transcript for the meeting should highlight the
/// section of audio that's playing"):
///
/// - **What is lit** is the last line begun at the playhead ([litAt]), found by halves over the lines' starts, so
///   an hour's thousands of phrases cost a dozen looks a tick. It stays lit through the quiet after it until the
///   next one begins, and while the tape is paused; nothing is lit on a tape that has not moved since it rested at
///   its start ([Tape.started]): never played, or played to its end.
/// - **Paragraphs** are lit by the time they were written with: Meet's captions keep when each turn began,
///   `**Sam Lee (0:04):** …` (lib/meet/speakers.dart `captionsSection`), and a paragraph is current from that
///   moment to the next one's ([paragraphStartMs]). A paragraph with no time of its own after one that has is more
///   words of it, as `turnsOf` reads them, and is lit with it. A write-up's transcript is timed the same way since
///   2026-10-26 (lib/meet/meet_note.dart `withSpeakers`); one written before, `**Sam Lee:** …`, and the captions a
///   note was filed from where no sound was kept, say no time, and nothing here makes one up: they stay as they were,
///   not lit and not buttons. The phrases beside a written-up meeting are what is timed.
/// - **Only what changed is built again.** The lines are made once for the words shown and kept; each asks the
///   transcript's light ([_Lit], an [InheritedModel] by line) for its own, so a tick builds nothing, and a new line
///   lit builds the two whose light moved, not the meeting.
/// - **Following.** While the tape plays the lit line is kept in the middle of the transcript. Scrolling it oneself
///   stops that, and a Follow pill over its foot takes it back, as does tapping a line, which takes the tape there.
/// - Phrases are lit whole: a phrase keeps no times for its words ([Segment] has its start and end alone).
///
/// And a meeting's in turns (Matt, 2026-10-30: "Also use a button to switch to the transcript in the note"; its Note
/// and Transcript are lib/note/meeting_view.dart): with [TranscriptWords.turns], each turn is its speaker and time over
/// its words ([TranscriptTurn]), Whisper's phrases put in turns as every meeting's transcript is
/// (lib/capture/meeting_turns.dart) or the note's own written turns read back ([meetingTurnsOf]); the turn being heard
/// is lit, a press plays the recording from its start, and with no recording on this device ([TranscriptWords.note])
/// the turns are there to be read. A search's hit in the transcript brings its turn into view ([TranscriptWords.atMs]).
///
/// And named (Matt, 2026-10-26: "Also after some time all the speaker labels disappeared"): a meeting's phrases came
/// to stand in for its written transcript once Whisper's were in, and a phrase carries no speaker, so every name the
/// captions gave went from the view though the note still had them. Each phrase is given its speaker from the note's
/// own words (lib/meet/speakers.dart `phraseSpeakers`: the captions while kept, the transcript's timed paragraphs, or
/// its named ones matched by their words), and the first phrase of each speaker's run starts with the name in bold,
/// as a written paragraph does ([TranscriptPhrase.speaker]). The light, a tap to seek and Follow are the phrases' as
/// before; a recording made on the device names nobody and its phrases are drawn as they were.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/library.dart' show transcriptOf;
import '../core/note.dart';
import '../capture/meeting_turns.dart' show transcriptTurns;
import '../meet/speakers.dart' show captionIcons, phraseSpeakers;
import 'tape.dart' show counter;
import 'player.dart';

/// The heading Meet's captions wait under for a meeting's write-up (lib/meet/speakers.dart `captionsHeading`).
const String _captionsHeading = '## Captions';

/// The paragraphs of [body]'s section under [heading], to the next heading of its level; null where it has none, or
/// nothing under it.
List<String>? _paragraphsUnder(String body, String heading) {
  final lines = body.split('\n');
  final at = lines.indexWhere((line) => line.trimRight() == heading);
  if (at < 0) return null;
  final paragraphs = <String>[];
  final now = StringBuffer();
  void end() {
    final text = now.toString().trim();
    if (text.isNotEmpty) paragraphs.add(text);
    now.clear();
  }

  for (final line in lines.skip(at + 1)) {
    if (line.startsWith('## ')) break;
    if (line.trim().isEmpty) {
      end();
    } else {
      if (now.isNotEmpty) now.write(' ');
      now.write(line.trim());
    }
  }
  end();
  return paragraphs.isEmpty ? null : paragraphs;
}

/// The transcript the note's words keep, a paragraph each (`**Sam Lee:** Good morning…` for a meeting's): what is
/// under its `## Transcript` heading, or null where there is none or it is empty.
List<String>? writtenTranscript(String body) => transcriptOf(body) == null ? null : _paragraphsUnder(body, '## Transcript');

/// Meet's captions, kept under `## Captions` while a Meet note waits for its write-up (lib/meet/meet_note.dart).
List<String>? captionsKept(String body) => _paragraphsUnder(body, _captionsHeading);

int _words(Iterable<String> texts) => texts.fold(0, (sum, text) => sum + text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length);

/// Whether [segments] carry the recording's words, against the transcript the note keeps ([written]): at least half
/// as many words, or there is no written one to tell by. A 13-minute meeting whose one phrase is "Go." (the live
/// recognizer's, kept from before its write-up) does not, and its written transcript is shown in its place.
bool phrasesWhole(List<Segment> segments, List<String>? written) {
  if (segments.isEmpty) return false;
  if (written == null || written.isEmpty) return true;
  return _words(segments.map((s) => s.text)) * 2 >= _words(written);
}

/// `**Sam Lee (0:04):** words`: a turn of Meet's captions as the note keeps it, named.
final RegExp _timedNamed = RegExp(r'^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\*\s*(.*)$', dotAll: true);

/// `(0:04) words`: one Meet showed no name over.
final RegExp _timedBare = RegExp(r'^\((\d+(?::\d{2}){1,2})\)\s*(.*)$', dotAll: true);

/// `**Sam Lee:** words`: named, with no time.
final RegExp _named = RegExp(r'^\*\*(.+?)\*\*\s*(.*)$', dotAll: true);

int _clockMs(String clock) => clock.split(':').fold(0, (total, part) => total * 60 + int.parse(part)) * 1000;

/// When [paragraph] of a meeting's transcript or captions began, in ms into the recording, by the time it was
/// written with (`**Sam Lee (0:04):** …`, `(1:02:03) …`: lib/meet/speakers.dart `captionsSection`); null for one
/// written with none.
int? paragraphStartMs(String paragraph) {
  final named = _timedNamed.firstMatch(paragraph);
  if (named != null) return _clockMs(named.group(2)!);
  final bare = _timedBare.firstMatch(paragraph);
  return bare == null ? null : _clockMs(bare.group(1)!);
}

/// The last of [starts] begun at [at] (each a line's start in ms, in the order spoken, never falling), or -1 before
/// the first: the line being heard. By halves, so it costs a dozen looks over an hour's phrases.
int litAt(List<int> starts, int at) {
  var low = 0, high = starts.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (starts[mid] <= at) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low - 1;
}

/// How a line of the transcript stands against the playhead.
enum TranscriptLight {
  /// There to be read: the tape has not moved, or the line has no moment of the tape to be lit at. The second ink.
  reading,

  /// Heard already: the second ink, as read.
  past,

  /// Being heard: the first ink, on the wash.
  current,

  /// Still to come, once the tape has moved: the third ink.
  coming,
}

/// The recording's phrases, following [tape] (`TranscriptWords`). It scrolls in the place it is given.
class TranscriptWords extends StatefulWidget {
  const TranscriptWords({super.key, this.tape, this.note, this.writeUp, this.turns = false, this.atMs, this.onAt}) : assert(tape != null || note != null);

  /// The recording, followed and taken to a turn when one is pressed; null for a meeting this device has no recording
  /// of (Meet's captions alone, or one whose sound stayed on another device), whose turns are only read.
  final Tape? tape;

  /// The note, where there is no [tape] to read it from.
  final Note? note;

  /// A meeting's: drawn as its turns, each its speaker and time over its words, the one being heard lit, a press
  /// taking the tape to its start (Matt, 2026-10-30: "use a button to switch to the transcript in the note"). Without,
  /// a phrase a line, as a spoken note's tape shows them.
  final bool turns;

  /// A moment to bring into view, in ms (a search's hit in the transcript): its turn is put in the middle once drawn.
  final int? atMs;

  /// Told once [atMs] has been brought into view, so it is not again.
  final VoidCallback? onAt;

  /// Where the note's write-up is, while it is still to come ("Writing up… 42%", "Being written up on another
  /// device."), said first; null once it has come, or where nothing writes it up.
  final String? writeUp;

  @override
  State<TranscriptWords> createState() => _TranscriptWordsState();
}

/// The lines made for the words a tape's note shows, kept while those words stay: what [TranscriptWords] draws, the
/// start of each lit line (a unit: a phrase, or a timed paragraph with the untimed ones after it), and a key on each
/// unit's first line to find it on the page by.
class _Shown {
  _Shown({required this.segments, required this.body, required this.waiting, required this.lines, required this.starts, required this.keys});

  final List<Segment>? segments;
  final String body;
  final bool waiting;
  final List<Widget> lines;
  final List<int> starts;
  final List<GlobalKey> keys;

  bool shows(List<Segment>? segments, String body) => identical(segments, this.segments) && (identical(body, this.body) || body == this.body);
}

class _TranscriptWordsState extends State<TranscriptWords> {
  final ScrollController _scroll = ScrollController();
  _Shown? _shown;
  int _lit = -1;
  bool _started = false;
  bool _playing = false;

  /// Whether the lit line is kept in view while the tape plays: until the transcript is scrolled by hand, and again
  /// from Follow or a tapped line.
  bool _following = true;

  @override
  void initState() {
    super.initState();
    widget.tape?.addListener(_heard);
  }

  @override
  void didUpdateWidget(TranscriptWords old) {
    super.didUpdateWidget(old);
    if (old.turns != widget.turns) _shown = null;
    if (old.tape == widget.tape) return;
    old.tape?.removeListener(_heard);
    widget.tape?.addListener(_heard);
    _shown = null;
  }

  /// The note's words and its phrases, from the tape where there is one.
  String get _body => widget.tape?.note.body ?? widget.note?.body ?? '';
  List<Segment>? get _segments => widget.tape != null ? widget.tape!.segments : widget.note?.segments;

  @override
  void dispose() {
    widget.tape?.removeListener(_heard);
    _scroll.dispose();
    super.dispose();
  }

  /// The tape told something. Built again only where what it said moves the transcript: its words, which line is
  /// lit, or whether it is playing; the playhead moving inside one line is ten ticks a second of nothing to draw.
  void _heard() {
    final tape = widget.tape;
    if (!mounted || tape == null) return;
    final shown = _shown;
    if (shown == null || !shown.shows(tape.segments, tape.note.body)) {
      setState(() {});
      return;
    }
    final lit = tape.started ? litAt(shown.starts, tape.at) : -1;
    if (lit == _lit && tape.started == _started && tape.playing == _playing) return;
    final follow = tape.playing && _following && lit >= 0 && (lit != _lit || !_playing);
    setState(() {
      _lit = lit;
      _started = tape.started;
      _playing = tape.playing;
    });
    if (follow) _reveal();
  }

  /// Takes the tape to [ms], from a tapped line, and follows it again.
  void _seek(int ms) {
    if (!_following) setState(() => _following = true);
    widget.tape?.seek(ms);
  }

  /// Takes the tape to [ms] and plays it from there, from a pressed turn: the playhead moved first, so a first Play
  /// starts the recording there (player.dart `toggle`).
  void _playFrom(int ms) {
    final tape = widget.tape;
    if (tape == null) return;
    _seek(ms);
    if (!tape.playing) unawaited(tape.toggle());
  }

  /// Follow: the lit line in view again, and kept there.
  void _follow() {
    setState(() => _following = true);
    _reveal();
  }

  /// The transcript scrolled by hand: it is no longer kept on the lit line.
  bool _scrolled(UserScrollNotification note) {
    if (note.direction != ScrollDirection.idle && _following) setState(() => _following = false);
    return false;
  }

  /// Whether the lit line is to be brought into view after the next frame.
  bool _revealing = false;

  /// The lit line in the middle of the transcript, once the frame it is lit in is drawn: the transcript's own
  /// scroll, not the page's. Asked any number of times before that frame, it goes once, to the line lit then.
  void _reveal() {
    if (_revealing) return;
    _revealing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealing = false;
      final keys = _shown?.keys;
      final unit = _lit;
      if (!mounted || !_scroll.hasClients || keys == null || unit < 0 || unit >= keys.length) return;
      final line = keys[unit].currentContext?.findRenderObject();
      if (line == null || !line.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(line);
      if (viewport == null) return;
      final position = _scroll.position;
      final to = viewport.getOffsetToReveal(line, 0.5).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((to - position.pixels).abs() < 1) return;
      final t = context.tokens;
      if (t.reducedMotion) {
        _scroll.jumpTo(to);
      } else {
        unawaited(_scroll.animateTo(to, duration: t.duration('glacier-duration-normal'), curve: t.curve('glacier-ease-out')));
      }
    });
  }

  /// The lines for the words [tape]'s note shows (see the header), made once for them.
  _Shown _make(bool waiting) {
    final segments = _segments;
    final body = _body;
      final seek = widget.tape == null ? null : _seek;
    // A turn pressed plays from its start (Matt, 2026-10-30: "tapping a turn plays the recording from that time").
    final play = widget.tape == null ? null : _playFrom;
    final written = writtenTranscript(body);
    _Shown shown(List<Widget> lines, [List<int> starts = const [], List<GlobalKey> keys = const []]) =>
        _Shown(segments: segments, body: body, waiting: waiting, lines: lines, starts: starts, keys: keys);

    if (widget.turns) return _turnsOf(segments, body, written, waiting, play, shown);
    if (segments != null && phrasesWhole(segments, written)) {
      final keys = [for (final _ in segments) GlobalKey()];
      // Who said each, where the note's words name them: the name before the first phrase of each speaker's run.
      final speakers = phraseSpeakers(segments, body);
      var latest = 0;
      return shown(
        [
          for (final (i, segment) in segments.indexed) ...[
            if (i > 0) const _Gap(),
            _PhraseLine(key: keys[i], unit: i, segment: segment, speaker: speakers[i] != null && (i == 0 || speakers[i - 1] != speakers[i]) ? speakers[i] : null, onSeek: _seek),
          ],
        ],
        // Never falling, so the halves hold where two phrases came out of order.
        [for (final segment in segments) latest = math.max(latest, segment.startMs)],
        keys,
      );
    }
    final paragraphs = written ?? captionsKept(body);
    if (paragraphs != null) {
      final starts = <int>[];
      final keys = <GlobalKey>[];
      final lines = <Widget>[];
      var unit = -1;
      for (final (i, paragraph) in paragraphs.indexed) {
        if (i > 0) lines.add(const _Gap());
        final at = paragraphStartMs(paragraph);
        if (at != null) {
          unit += 1;
          starts.add(math.max(at, starts.isEmpty ? 0 : starts.last));
          keys.add(GlobalKey());
        }
        lines.add(unit < 0
            // Before the first time, or a transcript with none: the words alone, as the note keeps them.
            ? WrittenParagraph(text: paragraph)
            : _ParagraphLine(key: at != null ? keys[unit] : null, unit: unit, text: paragraph, startMs: starts[unit], onSeek: seek));
      }
      return shown(lines, starts, keys);
    }
    if (waiting || segments == null) return shown(const [_Skeleton()]);
    return shown(const [_NoWords()]);
  }

  /// A meeting's turns (see [TranscriptWords.turns]): Whisper's phrases put in turns and named as the note names them
  /// (lib/capture/meeting_turns.dart, lib/meet/speakers.dart `phraseSpeakers`) where they carry its words, else the
  /// note's own written turns ([meetingTurnsOf]); a unit a timed turn, as the paragraphs are.
  _Shown _turnsOf(List<Segment>? segments, String body, List<String>? written, bool waiting, ValueChanged<int>? seek, _Shown Function(List<Widget> lines, [List<int> starts, List<GlobalKey> keys]) shown) {
    final List<ShownTurn> turns;
    if (segments != null && phrasesWhole(segments, written)) {
      final phrases = [for (final s in segments) if (s.text.trim().isNotEmpty) s];
      turns = [for (final turn in transcriptTurns(phrases, phraseSpeakers(phrases, body))) (speaker: turn.speaker, startMs: turn.startMs, text: turn.text)];
    } else {
      turns = meetingTurnsOf(body);
    }
    if (turns.isEmpty) return waiting || segments == null ? shown(const [_Skeleton()]) : shown(const [_NoWords()]);
    final starts = <int>[];
    final keys = <GlobalKey>[];
    final lines = <Widget>[];
    var unit = -1;
    for (final (i, turn) in turns.indexed) {
      if (i > 0) lines.add(const _TurnGap());
      final at = turn.startMs;
      if (at != null) {
        unit += 1;
        starts.add(math.max(at, starts.isEmpty ? 0 : starts.last));
        keys.add(GlobalKey());
      }
      lines.add(_TurnLine(key: at != null ? keys[unit] : null, unit: unit, turn: turn, onSeek: seek));
    }
    return shown(lines, starts, keys);
  }

  /// The moment last brought into view by [TranscriptWords.atMs], so a build does not bring it again.
  int? _broughtIn;

  /// [at]'s turn in the middle of the transcript, once drawn (a search's hit), the tape left where it is.
  void _bringIn(int at) {
    if (_broughtIn == at) return;
    _broughtIn = at;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shown = _shown;
      if (!mounted || shown == null || !_scroll.hasClients) return;
      final unit = litAt(shown.starts, at);
      if (unit < 0 || unit >= shown.keys.length) return;
      final line = shown.keys[unit].currentContext?.findRenderObject();
      if (line == null || !line.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(line);
      if (viewport == null) return;
      final position = _scroll.position;
      _scroll.jumpTo(viewport.getOffsetToReveal(line, 0.5).offset.clamp(position.minScrollExtent, position.maxScrollExtent));
      if (_following) setState(() => _following = false);
      widget.onAt?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tape = widget.tape;
    final writeUp = widget.writeUp;
    final was = _shown;
    final shown = _shown = was != null && was.waiting == (writeUp != null) && was.shows(_segments, _body) ? was : _make(writeUp != null);
    _started = tape?.started ?? false;
    _playing = tape?.playing ?? false;
    _lit = _started && tape != null ? litAt(shown.starts, tape.at) : -1;
    if (widget.atMs case final at?) _bringIn(at);
    // The lines stand out from the gutter by the wash's own room, so their words are where the page's are.
    final room = t.space(2);
    final padding = EdgeInsetsDirectional.fromSTEB(math.max(0, t.len('app-gutter-start') - room), t.space(5), math.max(0, t.len('app-gutter-end') - room), t.space(24));
    final follow = !_following && _lit >= 0;

    final page = NotificationListener<UserScrollNotification>(
      onNotification: _scrolled,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: padding,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (writeUp != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: room),
                  child: Semantics(liveRegion: true, child: Text(writeUp, key: const ValueKey('transcript-write-up'), style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3')))),
                ),
                SizedBox(height: t.space(3)),
              ],
              ...shown.lines,
            ],
          ),
        ),
      ),
    );
    return _Lit(
      lit: _lit,
      started: _started,
      child: Stack(
        children: [
          page,
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: t.space(6),
            child: Center(
              child: AnimatedSwitcher(
                duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
                child: follow ? _FollowPill(onPressed: _follow) : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Which line of the transcript is lit, and whether anything is: told to each line by its unit, so a line is built
/// again only when its own light moves.
class _Lit extends InheritedModel<int> {
  const _Lit({required this.lit, required this.started, required super.child});

  /// The unit being heard, or -1.
  final int lit;

  /// Whether the tape has moved ([Tape.started]); until it has, every line is to be read.
  final bool started;

  TranscriptLight _of(int unit) {
    if (unit < 0 || !started) return TranscriptLight.reading;
    if (unit == lit) return TranscriptLight.current;
    return unit < lit ? TranscriptLight.past : TranscriptLight.coming;
  }

  static TranscriptLight of(BuildContext context, int unit) => InheritedModel.inheritFrom<_Lit>(context, aspect: unit)?._of(unit) ?? TranscriptLight.reading;

  @override
  bool updateShouldNotify(_Lit old) => old.lit != lit || old.started != started;

  @override
  bool updateShouldNotifyDependent(_Lit old, Set<int> units) => units.any((unit) => old._of(unit) != _of(unit));
}

/// The room between two lines, the wash's own taken off it.
class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => SizedBox(height: context.tokens.space(1));
}

/// A phrase, with its light.
class _PhraseLine extends StatelessWidget {
  const _PhraseLine({super.key, required this.unit, required this.segment, this.speaker, required this.onSeek});

  final int unit;
  final Segment segment;

  /// The speaker, on the first phrase of their run alone.
  final String? speaker;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) => TranscriptPhrase(segment: segment, speaker: speaker, light: _Lit.of(context, unit), onPressed: () => onSeek(segment.startMs));
}

/// A timed paragraph, or one of the untimed after it, with its light: a press takes the tape to its unit's start.
class _ParagraphLine extends StatelessWidget {
  const _ParagraphLine({super.key, required this.unit, required this.text, required this.startMs, required this.onSeek});

  final int unit;
  final String text;
  final int startMs;
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    final seek = onSeek;
    return WrittenParagraph(text: text, light: _Lit.of(context, unit), onPressed: seek == null ? null : () => seek(startMs));
  }
}

/// A meeting's turn, with its light: who spoke and when, over what they said. A press takes the tape to its start
/// where there is a tape ([onSeek]).
class _TurnLine extends StatelessWidget {
  const _TurnLine({super.key, required this.unit, required this.turn, required this.onSeek});

  final int unit;
  final ShownTurn turn;
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    final seek = onSeek;
    final at = turn.startMs;
    return TranscriptTurn(turn: turn, light: unit < 0 ? TranscriptLight.reading : _Lit.of(context, unit), onPressed: seek == null || at == null ? null : () => seek(at));
  }
}

/// The ink of a line's words in its [light].
String _inkOf(TranscriptLight light) => switch (light) {
      TranscriptLight.current => 'app-ink',
      TranscriptLight.coming => 'app-ink-3',
      TranscriptLight.reading || TranscriptLight.past => 'app-ink-2',
    };

/// A line's ground: the wash while it is heard, none otherwise, with the wash's room round it either way so a line
/// lit does not move; a button the width of the page where there is a moment to take the tape to.
class _Line extends StatefulWidget {
  const _Line({required this.light, required this.onPressed, required this.child});

  final TranscriptLight light;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> {
  /// Whether this change of light fades: to or from the line being heard. The rest change at once, so a first Play
  /// or a seek across an hour does not draw thousands of lines for every frame of a fade nobody sees.
  bool _fades = false;

  @override
  void didUpdateWidget(_Line old) {
    super.didUpdateWidget(old);
    if (old.light != widget.light) _fades = old.light == TranscriptLight.current || widget.light == TranscriptLight.current;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = t.reducedMotion || !_fades ? Duration.zero : const Duration(milliseconds: 160);
    final wash = t.color('app-wash');
    final light = widget.light;
    final lit = light == TranscriptLight.current;
    final ground = Semantics(
      selected: lit,
      child: AnimatedContainer(
        duration: motion,
        curve: t.curve('glacier-ease-out'),
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
        decoration: BoxDecoration(color: lit ? wash : wash.withValues(alpha: 0), borderRadius: BorderRadius.circular(t.radius('md'))),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          // `transition: color 160ms var(--glacier-ease-out)`.
          child: AnimatedDefaultTextStyle(
            style: t.textAt(t.len('app-body'), height: 1.4, color: t.color(_inkOf(light))),
            duration: motion,
            curve: t.curve('glacier-ease-out'),
            child: widget.child,
          ),
        ),
      ),
    );
    if (widget.onPressed == null) return ground;
    return GlacierPressable(
      onPressed: widget.onPressed,
      haptic: null,
      builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: t.radius('md'), child: ground),
    );
  }
}

/// One paragraph of the transcript the note's words keep. A speaker's name in bold before it (`**Sam Lee:**`) is
/// drawn bold, and the stars go; a time it was written with (`**Sam Lee (0:04):**`) is drawn after the name in the
/// lighter ink. Lit, and a button to its moment of the tape, where it has one ([onPressed]); otherwise there to be
/// read.
class WrittenParagraph extends StatelessWidget {
  const WrittenParagraph({super.key, required this.text, this.light = TranscriptLight.reading, this.onPressed});

  final String text;
  final TranscriptLight light;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = t.textAt(t.len('app-body'), height: 1.4, weight: 'semibold', color: t.color(light == TranscriptLight.coming ? 'app-ink-2' : 'app-ink'));
    final time = t.textAt(t.len('app-body'), height: 1.4, color: t.color(light == TranscriptLight.coming ? 'app-ink-4' : 'app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final timed = _timedNamed.firstMatch(text);
    final bare = timed == null ? _timedBare.firstMatch(text) : null;
    final named = timed == null && bare == null ? _named.firstMatch(text) : null;
    final Widget words = timed != null
        ? Text.rich(TextSpan(children: [TextSpan(text: timed.group(1), style: name), TextSpan(text: ' (${timed.group(2)}):', style: time), TextSpan(text: ' ${timed.group(3)}')]))
        : bare != null
            ? Text.rich(TextSpan(children: [TextSpan(text: '(${bare.group(1)})', style: time), TextSpan(text: ' ${bare.group(2)}')]))
            : named != null
                ? Text.rich(TextSpan(children: [TextSpan(text: named.group(1), style: name), TextSpan(text: ' ${named.group(2)}')]))
                : Text(text);
    return _Line(light: light, onPressed: onPressed, child: words);
  }
}

/// A meeting's turn as it is shown: who (null for nobody named), when it began (null where it says no time), and the
/// words.
typedef ShownTurn = ({String? speaker, int? startMs, String text});

final RegExp _namedUntimed = RegExp(r'^\*\*([^*\n]+?):\*\*\s*(.*)$', dotAll: true);

String? _turnName(String raw) {
  final name = raw.replaceAll(RegExp(r'[*\[\]()]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r':+$'), '');
  return name.isEmpty || captionIcons.contains(name) ? null : name;
}

/// The turns a meeting's note keeps in its words (`## Transcript`, else `## Captions` while those wait for the
/// write-up): each paragraph read as `**Sam Lee (0:04):** words`, `(0:04) words`, `**Sam Lee:** words` or words
/// alone; a name that is one of Meet's icons is nobody's.
List<ShownTurn> meetingTurnsOf(String body) {
  final out = <ShownTurn>[];
  for (final raw in writtenTranscript(body) ?? captionsKept(body) ?? const <String>[]) {
    final p = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (p.isEmpty) continue;
    if (_timedNamed.firstMatch(p) case final m?) {
      out.add((speaker: _turnName(m.group(1)!), startMs: _clockMs(m.group(2)!), text: m.group(3)!.trim()));
    } else if (_timedBare.firstMatch(p) case final m?) {
      out.add((speaker: null, startMs: _clockMs(m.group(1)!), text: m.group(2)!.trim()));
    } else if (_namedUntimed.firstMatch(p) case final m?) {
      out.add((speaker: _turnName(m.group(1)!), startMs: null, text: m.group(2)!.trim()));
    } else {
      out.add((speaker: null, startMs: null, text: p));
    }
  }
  return out;
}

/// One turn of a meeting (Matt, 2026-10-30): the speaker's name and the time it began on a line of their own, the name
/// in the first ink and the time in the lighter, and the words under them. On the wash while it is being heard, and a
/// button to its moment where there is a tape ([onPressed]), as a line of the transcript is.
class TranscriptTurn extends StatelessWidget {
  const TranscriptTurn({super.key, required this.turn, this.light = TranscriptLight.reading, this.onPressed});

  final ShownTurn turn;
  final TranscriptLight light;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final coming = light == TranscriptLight.coming;
    final size = t.fontSize('sm');
    final name = t.textAt(size, height: 1.4, weight: 'semibold', color: t.color(coming ? 'app-ink-2' : 'app-ink'));
    final time = t.textAt(size, height: 1.4, color: t.color(coming ? 'app-ink-4' : 'app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final who = turn.speaker;
    final at = turn.startMs;
    final head = <InlineSpan>[
      if (who != null) TextSpan(text: who, style: name),
      if (who != null && at != null) TextSpan(text: ' · ', style: time),
      if (at != null) TextSpan(text: counter(at), style: time),
    ];
    return _Line(
      light: light,
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (head.isNotEmpty) ...[
            Text.rich(TextSpan(children: head)),
            SizedBox(height: t.space(1) / 2),
          ],
          Text(turn.text),
        ],
      ),
    );
  }
}

/// The room between two turns.
class _TurnGap extends StatelessWidget {
  const _TurnGap();

  @override
  Widget build(BuildContext context) => SizedBox(height: context.tokens.space(2));
}

/// One phrase, as a button the width of the page (`.phrase`): in the second ink to be read and once heard, the
/// first on the wash while it is ([current]), and the third while it is still to come. The first phrase of a
/// speaker's run starts with their name in bold ([speaker]), as a written paragraph's does.
class TranscriptPhrase extends StatelessWidget {
  const TranscriptPhrase({super.key, required this.segment, this.speaker, required this.light, required this.onPressed});

  final Segment segment;

  /// Who began speaking with this phrase, where the note names them (lib/meet/speakers.dart `phraseSpeakers`); null
  /// for a phrase that goes on the same speaker's words, or one nobody is named for.
  final String? speaker;
  final TranscriptLight light;
  final VoidCallback onPressed;

  /// `data-current`: the phrase under the playhead.
  bool get current => light == TranscriptLight.current;

  /// `data-past`: a phrase already heard.
  bool get past => light == TranscriptLight.past;

  /// The tape has not moved: the phrase is there to be read, not waiting to be heard. The port's own.
  bool get reading => light == TranscriptLight.reading;

  @override
  Widget build(BuildContext context) {
    final name = speaker;
    if (name == null) return _Line(light: light, onPressed: onPressed, child: Text(segment.text));
    final t = context.tokens;
    final style = t.textAt(t.len('app-body'), height: 1.4, weight: 'semibold', color: t.color(light == TranscriptLight.coming ? 'app-ink-2' : 'app-ink'));
    return _Line(light: light, onPressed: onPressed, child: Text.rich(TextSpan(children: [TextSpan(text: '$name:', style: style), TextSpan(text: ' ${segment.text}')])));
  }
}

/// Follow, over the transcript's foot once it has been scrolled away from the line being heard: takes it back there,
/// and keeps it there.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-paper');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'Follow the tape',
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
                  AppIcon(Lucide.audioLines, size: 15, strokeWidth: 2.2, color: ink),
                  SizedBox(width: t.space(2)),
                  Text('Follow', style: t.text('sm', weight: 'semibold', color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Said where a recording kept no words.
class _NoWords extends StatelessWidget {
  const _NoWords();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(2)),
      child: Text('No words were kept with this recording.', style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
    );
  }
}

/// The phrases' shapes while the recording's words are still being read.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: 'Loading the transcript',
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, width) in const [0.88, 0.62, 0.74].indexed) ...[
              if (i > 0) SizedBox(height: t.space(3)),
              FractionallySizedBox(widthFactor: width, child: const _PhraseSkeleton()),
            ],
          ],
        ),
      ),
    );
  }
}

/// A phrase's shape while the recording's words are still being read (`.phraseSkeleton`): a bar one em tall that
/// breathes to 45% and back every 1.6 s; at 70% and still under reduced motion.
class _PhraseSkeleton extends StatefulWidget {
  const _PhraseSkeleton();

  @override
  State<_PhraseSkeleton> createState() => _PhraseSkeletonState();
}

class _PhraseSkeletonState extends State<_PhraseSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!context.tokens.reducedMotion) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bar = Container(
      height: t.fontSize('md'),
      margin: EdgeInsets.symmetric(vertical: t.space(2)),
      decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(t.radius('sm'))),
    );
    if (t.reducedMotion) return Opacity(opacity: 0.7, child: bar);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        final there = v < 0.5 ? Curves.easeInOut.transform(v * 2) : 1 - Curves.easeInOut.transform((v - 0.5) * 2);
        return Opacity(opacity: 1 - 0.55 * there, child: child);
      },
      child: bar,
    );
  }
}
