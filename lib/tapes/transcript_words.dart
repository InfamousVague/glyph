/// The words as they were spoken, lit as they are heard. The phrase under the playhead is in ink, the ones already
/// heard in grey, the ones still to come lighter still, and the page keeps the lit one in view while the tape plays.
/// Tapping a phrase takes the tape there. A port of `TranscriptWords` in `src/app/tapes/NoteTape.tsx`, with
/// `.transcript`, `.words`, `.phrase` and `.phraseSkeleton` of NoteTape.module.css.
///
/// What differs: on the page it shared a file with the tape's strip; it is split out here. A phrase's two
/// attributes (`data-current`, `data-past`) are [TranscriptPhrase]'s `current` and `past`. The page's
/// `scrollIntoView({ block: 'center', behavior: 'smooth' })` is `Scrollable.ensureVisible` at the middle over the
/// kit's normal duration, since a browser's smooth scroll has no length of its own to copy.
///
/// The port's own (Matt, 2026-10-24: "when clicking on meetings it doesn't load the transcript"): a meeting opened
/// anywhere shows this with its tape still (lib/note/land_at.dart `atTranscript`), so the words are read here and not
/// only heard. Where the phrases do not carry the meeting's words, the words the note keeps under `## Transcript` do,
/// untimed, a paragraph each ([writtenTranscript]): a meeting whose phrases have not come to this device, one whose
/// only phrase is the live recognizer's first word ([phrasesWhole]), a Meet note whose transcript is Meet's captions.
/// While its write-up is still to come the place says so first ([TranscriptWords.writeUp], "Writing up… 42%"), over
/// the captions where Meet gave any, rather than standing empty. And until a Play the phrases are all in the second
/// ink, to be read; the fourth is for the ones still to be heard once the tape has moved.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/library.dart' show transcriptOf;
import '../core/note.dart';
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

/// The recording's phrases, following [tape] (`TranscriptWords`). It scrolls in the place it is given.
class TranscriptWords extends StatefulWidget {
  const TranscriptWords({super.key, required this.tape, this.writeUp});

  final Tape tape;

  /// Where the note's write-up is, while it is still to come ("Writing up… 42%", "Being written up on another
  /// device."), said first; null once it has come, or where nothing writes it up.
  final String? writeUp;

  @override
  State<TranscriptWords> createState() => _TranscriptWordsState();
}

class _TranscriptWordsState extends State<TranscriptWords> {
  final Map<int, GlobalKey> _keys = {};
  int _current = -1;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    widget.tape.addListener(_follow);
    _current = widget.tape.current;
    _playing = widget.tape.playing;
  }

  @override
  void didUpdateWidget(TranscriptWords old) {
    super.didUpdateWidget(old);
    if (old.tape == widget.tape) return;
    old.tape.removeListener(_follow);
    widget.tape.addListener(_follow);
    _keys.clear();
  }

  @override
  void dispose() {
    widget.tape.removeListener(_follow);
    super.dispose();
  }

  /// While the tape plays, the phrase being heard is kept in the middle of the page.
  void _follow() {
    if (!mounted) return;
    final tape = widget.tape;
    final changed = tape.current != _current || tape.playing != _playing;
    _current = tape.current;
    _playing = tape.playing;
    setState(() {});
    if (!changed || !_playing || _current < 0) return;
    final lit = _current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _keys[lit]?.currentContext;
      if (!mounted || at == null) return;
      final t = context.tokens;
      Scrollable.ensureVisible(at, alignment: 0.5, duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-normal'), curve: t.curve('glacier-ease-out'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tape = widget.tape;
    final segments = tape.segments;
    final body = tape.note.body;
    final writeUp = widget.writeUp;
    final written = writtenTranscript(body);
    final padding = EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), t.space(5), t.len('app-gutter-end'), t.space(24));
    final quiet = t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'));

    Widget page(List<Widget> children) => SingleChildScrollView(
          padding: padding,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, child) in children.indexed) ...[if (i > 0) SizedBox(height: t.space(3)), child],
              ],
            ),
          ),
        );

    final said = <Widget>[
      if (writeUp != null) Semantics(liveRegion: true, child: Text(writeUp, key: const ValueKey('transcript-write-up'), style: quiet)),
    ];
    final skeleton = Semantics(
      label: 'Loading the transcript',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, width) in const [0.88, 0.62, 0.74].indexed) ...[
            if (i > 0) SizedBox(height: t.space(3)),
            FractionallySizedBox(widthFactor: width, child: const _PhraseSkeleton()),
          ],
        ],
      ),
    );

    if (segments != null && phrasesWhole(segments, written)) {
      // Before the tape has moved, every phrase is there to be read; once it has, the ones to come are lighter.
      final still = !tape.playing && tape.at == 0;
      return page([
        ...said,
        for (final (i, segment) in segments.indexed)
          TranscriptPhrase(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            segment: segment,
            // Not the first phrase lit as if heard, for a tape nobody has played.
            current: !still && i == tape.current,
            past: i < tape.current || (tape.current == -1 && tape.at >= segment.endMs && tape.at > 0),
            reading: still,
            onPressed: () => tape.seek(segment.startMs),
          ),
      ]);
    }
    if (written != null) {
      return page([...said, for (final paragraph in written) WrittenParagraph(text: paragraph)]);
    }
    if (writeUp != null) {
      // Meet's captions, where it gave any, are what there is until the write-up comes.
      final captions = captionsKept(body);
      return page([...said, if (captions == null) skeleton else for (final paragraph in captions) WrittenParagraph(text: paragraph)]);
    }
    if (segments == null) return page([skeleton]);
    return page([Text('No words were kept with this recording.', style: quiet)]);
  }
}

/// One paragraph of the transcript the note's words keep, untimed: not a button, since there is no moment of the
/// tape to take it to. A speaker's name in bold before it (`**Sam Lee:**`) is drawn bold, and the stars go.
class WrittenParagraph extends StatelessWidget {
  const WrittenParagraph({super.key, required this.text});

  final String text;

  static final RegExp _named = RegExp(r'^\*\*(.+?)\*\*\s*(.*)$', dotAll: true);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = t.textAt(t.len('app-body'), height: 1.4, color: t.color('app-ink-2'));
    final named = _named.firstMatch(text);
    if (named == null) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: named.group(1), style: t.textAt(t.len('app-body'), height: 1.4, weight: 'semibold', color: t.color('app-ink'))),
          TextSpan(text: ' ${named.group(2)}'),
        ],
      ),
    );
  }
}

/// One phrase, as a button the width of the page (`.phrase`): the fourth ink until it is heard, the third once it
/// has been ([past]), and the first while it is ([current]).
class TranscriptPhrase extends StatelessWidget {
  const TranscriptPhrase({super.key, required this.segment, required this.current, required this.past, required this.onPressed, this.reading = false});

  final Segment segment;

  /// `data-current`: the phrase under the playhead.
  final bool current;

  /// `data-past`: a phrase already heard.
  final bool past;

  /// The tape has not moved: the phrase is there to be read, in the second ink, not waiting to be heard. The port's
  /// own.
  final bool reading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.color(current ? 'app-ink' : past ? 'app-ink-3' : reading ? 'app-ink-2' : 'app-ink-4');
    return GlacierPressable(
      onPressed: onPressed,
      haptic: null,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          // `transition: color 160ms var(--glacier-ease-out)`.
          child: AnimatedDefaultTextStyle(
            style: t.textAt(t.len('app-body'), height: 1.4, color: color),
            duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 160),
            curve: t.curve('glacier-ease-out'),
            child: Text(segment.text),
          ),
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
