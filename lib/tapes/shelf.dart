/// A recording where the notes are listed: a cassette's mark, and how long it is, "0:40", before its words; and the
/// day a tape was recorded, "26 Sep", as its label's small print says it. Ports of `KindMark`'s cassette and
/// `TapeWords` in `src/app/home/HomeScreen.tsx` (with `.rowMarkTape`, `.rowTape` and `.rowLive` of
/// HomeLayouts.module.css) and of `src/app/tapes/tapeDate.ts`.
///
/// What differs: there is no shelf to port. The web's shelf of cassettes (`home/TapeShelf.tsx`) went with the
/// dashboard (docs/DESIGN.md §147) and the file is gone: a recording is a note's row with this mark and this length
/// now, and All notes' Tapes switch is the list of them (`home/dashboard.dart` `tapedNotes` still says which notes
/// those are, and in what order). So this file is the row's two parts and the date, not a shelf. The home page's
/// rows (`home/home_rows.dart`) draw the same two from private copies of their own, written before this file; they
/// should take these. `tapeDate` asked the device's language for its order ("26 Sept", "Sep 26"): it is in English
/// in the phone's own order once the phone has said which (core/locale_dates.dart), and the day and then the month
/// until then.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/locale_dates.dart';
import '../core/note.dart';
import '../home/home_icons.dart';
import '../home/home_layout.dart' show HomeKind, kindOf;
import '../home/home_text.dart';
import 'tape.dart';

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The day and the month a tape was recorded, "26 Sep" (`tapeDate.format`): "Sep 26" on an American phone and "26
/// Sept" on a British one, once it has said. [ms] is milliseconds since the epoch.
String tapeDate(int ms) {
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  return toldDate(at, DateForm.MMMd) ?? '${at.day} ${_months[at.month - 1]}';
}

/// A recording's mark at the start of its row: the cassette, a touch larger than a page's mark, since its shape is
/// wide and low (`KindMark` for a tape, `.rowMarkTape`: 1.1em of the mark's [em]).
class TapeMark extends StatelessWidget {
  const TapeMark({super.key, this.em = 16, this.color});

  /// The size of the marks beside it; the cassette is 1.1 of it.
  final double em;

  /// The third ink unless the row says another.
  final Color? color;

  @override
  Widget build(BuildContext context) => HomeIcon(HomeGlyph.tape, size: 1.1 * em, color: color ?? context.tokens.color('app-ink-3'));
}

/// What a recording says before its words (`TapeWords`): how long it is, "0:40", or, for the meeting being
/// recorded now ([live]), that it is, in the first ink with a dot that beats. Nothing for a note that is not a tape
/// (`home_layout.dart` `kindOf`: a notebook or a canvas is its own kind, recording or not).
class TapeWords extends StatelessWidget {
  const TapeWords({super.key, required this.note, this.live = false, required this.em, this.dot = false});

  final Note note;

  /// The meeting being recorded now, whose note has no tape until it stops.
  final bool live;

  /// The size of the text it stands in.
  final double em;

  /// `.rowLead .rowTape::after`: " ·" after the length, where the note's words follow on the same line.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final spans = tapeWordSpans(context.tokens, note, live: live, em: em, dot: dot);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(children: spans), softWrap: false);
  }
}

/// [TapeWords] as spans, for a line of text that carries on after them; they end with the half em that parts them
/// from what follows (`margin-inline-end: 0.5em`). None for a note that is neither a tape nor [live].
List<InlineSpan> tapeWordSpans(Tokens t, Note note, {bool live = false, required double em, bool dot = false}) {
  if (live) {
    return [
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsetsDirectional.only(end: 0.35 * em), child: _LiveDot(size: 0.5 * em, color: t.color('app-ink')))),
      TextSpan(text: 'Recording now', style: tabular(pageText(t, em, color: t.color('app-ink')))),
      WidgetSpan(child: SizedBox(width: 0.5 * em)),
    ];
  }
  if (kindOf(note) != HomeKind.tape) return const [];
  return [
    TextSpan(text: counter(note.recordingMs ?? 0), style: tabular(pageText(t, em, color: t.color('app-ink-2')))),
    if (dot) TextSpan(text: ' ·', style: pageText(t, em, color: t.color('app-ink-3'))),
    WidgetSpan(child: SizedBox(width: 0.5 * em)),
  ];
}

/// `.rowLive::before`: a dot of ink that beats while the meeting is being recorded (`animation: live 1.6s
/// ease-in-out infinite`, to 35% at its middle); still under reduced motion.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final there = t < 0.5 ? Curves.easeInOut.transform(t * 2) : 1 - Curves.easeInOut.transform((t - 0.5) * 2);
        return Opacity(opacity: 1 - 0.65 * there, child: child);
      },
      child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}
