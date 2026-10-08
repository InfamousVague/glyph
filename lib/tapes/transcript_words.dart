/// The words as they were spoken, lit as they are heard. The phrase under the playhead is in ink, the ones already
/// heard in grey, the ones still to come lighter still, and the page keeps the lit one in view while the tape plays.
/// Tapping a phrase takes the tape there. A port of `TranscriptWords` in `src/app/tapes/NoteTape.tsx`, with
/// `.transcript`, `.words`, `.phrase` and `.phraseSkeleton` of NoteTape.module.css.
///
/// What differs: on the page it shared a file with the tape's strip; it is split out here. A phrase's two
/// attributes (`data-current`, `data-past`) are [TranscriptPhrase]'s `current` and `past`. The page's
/// `scrollIntoView({ block: 'center', behavior: 'smooth' })` is `Scrollable.ensureVisible` at the middle over the
/// kit's normal duration, since a browser's smooth scroll has no length of its own to copy.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import 'player.dart';

/// The recording's phrases, following [tape] (`TranscriptWords`). It scrolls in the place it is given.
class TranscriptWords extends StatefulWidget {
  const TranscriptWords({super.key, required this.tape});

  final Tape tape;

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
    final padding = EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), t.space(5), t.len('app-gutter-end'), t.space(24));

    Widget page(Widget child) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: padding,
          child: SizedBox(width: double.infinity, child: child),
        );

    if (segments == null) {
      return Semantics(
        label: 'Loading the transcript',
        liveRegion: true,
        child: page(
          Column(
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
    if (segments.isEmpty) {
      return page(Text('No words were kept with this recording.', style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))));
    }
    return page(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, segment) in segments.indexed) ...[
            if (i > 0) SizedBox(height: t.space(3)),
            TranscriptPhrase(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              segment: segment,
              current: i == tape.current,
              past: i < tape.current || (tape.current == -1 && tape.at >= segment.endMs && tape.at > 0),
              onPressed: () => tape.seek(segment.startMs),
            ),
          ],
        ],
      ),
    );
  }
}

/// One phrase, as a button the width of the page (`.phrase`): the fourth ink until it is heard, the third once it
/// has been ([past]), and the first while it is ([current]).
class TranscriptPhrase extends StatelessWidget {
  const TranscriptPhrase({super.key, required this.segment, required this.current, required this.past, required this.onPressed});

  final Segment segment;

  /// `data-current`: the phrase under the playhead.
  final bool current;

  /// `data-past`: a phrase already heard.
  final bool past;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.color(current ? 'app-ink' : past ? 'app-ink-3' : 'app-ink-4');
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
