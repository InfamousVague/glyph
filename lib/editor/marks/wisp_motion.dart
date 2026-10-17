/// What is in motion in a note's words, and when: the half of the Wisp treatment that decides. Ports
/// `src/app/editor/wispMotion.ts`, and of its drawing (`wispArrivals.ts`) only what typing needs: the text a
/// person takes out smoking away where it stood.
///
/// A transaction carrying the [wisp] annotation - the recorder writing what it heard, or rewriting a pending
/// phrase - sets the letters it really added arriving and the text it really took away leaving, diffed so a phrase
/// firming up moves one letter. With [typing] on, what the person takes out smokes away too; what they type or
/// paste appears at once. [revealWisp] fades a stretch already there in, as a note opens. Everything in motion is
/// held in one field, [wispState], mapped through every change, with the moment each piece starts and how long it
/// lasts at the chosen pace, until the drawing says it has settled ([settle]). With reduced motion asked for,
/// nothing is set in motion at all.
///
/// The user events are load-bearing: a board's own edits (`input.board`) and what the + beside the line adds
/// (`input.plus`) are not typing, and a tapped box's letter (`input.toggle`, `input.choice`) dissolves where it
/// stands rather than arriving.
///
/// What differs:
/// - `performance.now()` is [wispNow], which a test sets; `prefersStill()` and `motionScale()` are the facets
///   [wispStill] and [wispPace], which whoever makes the editor fills from the tokens' reduced motion and the
///   Motion setting, a state field having neither a context nor a window to ask.
/// - Arrivals (the recorder's words, the opening reveal) are decided here as on the web and drawn by the stage that
///   ports `wispArrivals.ts` with the recorder; [wispDepartures] draws the leaving half now: a ghost of the text
///   that went, at the point it left, fading and lifting through the wisp's shader over its duration
///   (`art/WispText.module.css` `wispOut`), then telling the field it has settled.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;

import '../../art/wisp_kit.dart';
import '../../art/wisp_text.dart' show paintWispLetter, wispLetterBend, wispLetterFrequency, wispLetterSoft, wispSlotSeed;
import '../editor.dart';
import '../view/line.dart' show EditorRunScope;
import 'run_paint.dart';

/// What a transaction carrying [wisp] is: the recorder's words, heard; a pending phrase rewritten; or an AI's words
/// as it types them ([typed]).
enum WispKind {
  heard,
  rewrite,

  /// Claude typing (lib/claude/live_typing.dart, and a connector's words arriving live, lib/live/editor_binding.dart):
  /// a brief, light smoke that clears within [typedArrivalMs], every word at once with no turn to wait for, since
  /// the words are already let out at a reading pace (lib/claude/typing_pacer.dart). Matt (2026-10-17): "when claude
  /// enters text we need the wisp on entry to be near instant".
  typed,
}

/// Put on a transaction that writes what was heard, or rewrites a pending phrase, or is an AI typing.
final AnnotationType<WispKind> wisp = Annotation.define<WispKind>();

/// Whether text deleted by hand smokes away (typed text never arrives through smoke: it appears as it is typed).
final Facet<bool, bool> typing = Facet.define<bool, bool>(combine: (values) => values.any((value) => value));

/// Reduced motion: nothing is set in motion.
final Facet<bool, bool> wispStill = Facet.define<bool, bool>(combine: (values) => values.any((value) => value));

/// The chosen pace (Settings › Appearance › Motion): each piece's wait and its arc stretched or shortened alike.
final Facet<double, double> wispPace = Facet.define<double, double>(combine: (values) => values.isEmpty ? 1 : values.first);

/// The clock, in ms: the app's own unless a test holds it.
double Function() wispNow = _stopwatchNow;
final Stopwatch _watch = Stopwatch()..start();
double _stopwatchNow() => _watch.elapsedMicroseconds / 1000;

/// Text deleted by hand leaves quickly, and quicker still in a run of backspaces: the smoke is a trace of what
/// went, not something to wait for. A single letter leaves no trace at all.
const double _deleteMs = 140;
const double _deleteRunMs = 85;

/// Backspaces closer together than this are one run.
const double _deleteRunGapMs = 350;
double _lastDeleteAt = -1e12;

double _deleteDuration(double now) {
  final run = now - _lastDeleteAt < _deleteRunGapMs;
  _lastDeleteAt = now;
  return run ? _deleteRunMs : _deleteMs;
}

/// A letter that arrived, or the text that left, still in motion.
class Moving {
  const Moving({required this.id, required this.from, required this.to, required this.gone, required this.at, required this.dur, this.box = false, this.light = false});

  final int id;

  /// Arriving: the letter's range in the document. Leaving: an empty range at the point it left.
  final int from;
  final int to;

  /// The text, for a ghost of what left; empty for an arrival.
  final String gone;

  /// [wispNow] at which its motion starts; later than now for letters still waiting their turn.
  final double at;

  /// A tapped box's letter (`- [x]`, `- ( )`): it dissolves where it stands, without the throw or the lift.
  final bool box;

  /// An AI's word, typed ([WispKind.typed]): the brief, light smoke, drawn so (`wisp_arrivals.dart` `shapeAt`), and
  /// never drawn slower than [typedArrivalMs] whatever the pace.
  final bool light;
  final double dur;

  Moving _moved(int from, int to) => Moving(id: id, from: from, to: to, gone: gone, at: at, dur: dur, box: box, light: light);
  Moving _paced(double now, double scale) {
    // A relaxed pace stretches the person's own smoke; Claude's words stay quick to read.
    final by = light ? math.min(scale, 1.0) : scale;
    return Moving(id: id, from: from, to: to, gone: gone, at: now + (at - now) * by, dur: dur * by, box: box, light: light);
  }
}

/// Letters a phrase types in at, ms; the whole phrase never waits longer than the cap.
const double _staggerMs = 8;

/// However long a word, the next one never waits longer than this behind it.
const double _wordMaxMs = 62;
const double _staggerCapMs = 1350;
const double _inMs = 350;
const double _inJitterMs = 100;
const double _outMs = 380;

/// The arc of a word an AI types ([WispKind.typed]), ms, and its jitter: the whole word is legible by the end of it,
/// [typedArrivalMs] at most. The recorder's words take [_inMs] and wait their turn one after another; an AI's words
/// are already let out a word at a time at a reading pace, so each just clears out of a little smoke.
const double typedArrivalMs = 120;
const double _typedInMs = 96;
const double _typedJitterMs = typedArrivalMs - _typedInMs;

/// Of one change an AI types, only this many of its last words come out of smoke; the ones before are there at
/// once. A change of an AI's is a word or two at its pace, but a flush (Stop, the note closing, the connector's
/// words landing together) can be a page, and a page of smoke waits on the pool of filters (`wisp_arrivals.dart`
/// `poolMax`), unseen until its turn: the text that "comes in invisible".
const int typedSmokyWords = 8;

/// Letters done moving, by id: the drawing says so, and this lets them go.
final StateEffectType<List<int>> settle = StateEffect.define<List<int>>();

/// Fades a stretch of text that is already there in from smoke, a line at a time and quickly: the note opening.
final StateEffectType<({int from, int to})> revealWisp = StateEffect.define<({int from, int to})>();

/// The opening reveal: each piece this far behind the one before, the whole never longer than the cap; and its
/// arc.
const double _revealStepMs = 10;
const double _revealCapMs = 290;
const double _revealMs = 260;

/// A piece of the reveal is a few words, never more than this many characters: short enough to sit on one row.
const int _revealPieceChars = 24;

/// Pieces the opening reveal animates: about a screen; anything further down is already set when scrolled to.
const int _revealPieces = 48;

int _nextId = 1;
final math.Random _random = math.Random();
final RegExp _word = RegExp(r'\S+');

List<Moving> _revealing(EditorState state, int from, int to, double now) {
  final moving = <Moving>[];
  var line = state.doc.lineAt(math.max(0, math.min(from, state.doc.length)));
  final end = math.min(to, state.doc.length);
  while (moving.length < _revealPieces) {
    ({int from, int to})? piece;
    void flush() {
      final one = piece;
      if (one == null) return;
      moving.add(Moving(id: _nextId++, from: line.from + one.from, to: line.from + one.to, gone: '', at: now + math.min(moving.length * _revealStepMs, _revealCapMs), dur: _revealMs + _random.nextDouble() * _inJitterMs));
      piece = null;
    }

    for (final word in _word.allMatches(line.text)) {
      if (moving.length >= _revealPieces) break;
      if (piece != null && word.end - piece!.from > _revealPieceChars) flush();
      piece = piece != null ? (from: piece!.from, to: word.end) : (from: word.start, to: word.end);
    }
    flush();
    if (line.to >= end || line.number >= state.doc.lines) break;
    line = state.doc.line(line.number + 1);
  }
  return moving;
}

/// The common prefix and suffix of `a` and `b`, as lengths, never overlapping.
({int prefix, int suffix}) commonEnds(String a, String b) {
  final shortest = math.min(a.length, b.length);
  var prefix = 0;
  while (prefix < shortest && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
    prefix += 1;
  }
  var suffix = 0;
  while (suffix < shortest - prefix && a.codeUnitAt(a.length - 1 - suffix) == b.codeUnitAt(b.length - 1 - suffix)) {
    suffix += 1;
  }
  return (prefix: prefix, suffix: suffix);
}

/// What a transaction sets in motion: the text it really took away, and, where `arrive`, the letters it really
/// added. The person's own typing sets no arrivals.
List<Moving> _movingIn(Transaction tr, double now, {double outMs = _outMs, bool singleLetters = true, bool box = false, bool arrive = true, bool light = false}) {
  final moving = <Moving>[];
  var wait = 0.0;
  final arriving = <Moving>[];
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    final removed = tr.startState.doc.sliceString(fromA, toA);
    final added = inserted.toString();
    final ends = commonEnds(removed, added);
    final gone = removed.substring(ends.prefix, removed.length - ends.suffix);
    // A letter backspaced by hand just goes: a trace of smoke on each was a stutter under the fingers. A word or a
    // selection taken out at once still smokes, and so does a letter a rewrite takes back while the words are being
    // heard, which is not typing.
    if (gone.trim().isNotEmpty && (singleLetters || gone.trim().length > 1)) {
      moving.add(Moving(id: _nextId++, from: fromB + ends.prefix, to: fromB + ends.prefix, gone: gone, at: now, dur: outMs, box: box));
    }
    if (!arrive) return;
    // A word at a time, in turn at the pace its letters would type.
    final end = added.length - ends.suffix;
    var i = ends.prefix;
    while (i < end) {
      while (i < end && added[i].trim().isEmpty) {
        i += 1;
      }
      if (i >= end) break;
      var j = i;
      while (j < end && added[j].trim().isNotEmpty) {
        j += 1;
      }
      if (light) {
        // An AI's word: no turn to wait, and a short arc.
        arriving.add(Moving(id: _nextId++, from: fromB + i, to: fromB + j, gone: '', at: now, dur: _typedInMs + _random.nextDouble() * _typedJitterMs, box: box, light: true));
      } else {
        moving.add(Moving(id: _nextId++, from: fromB + i, to: fromB + j, gone: '', at: now + math.min(wait, _staggerCapMs), dur: _inMs + _random.nextDouble() * _inJitterMs, box: box));
      }
      wait += math.min(_wordMaxMs, (j - i + 1) * _staggerMs);
      i = j;
    }
  });
  // The last few words an AI typed come out of smoke, the rest are simply there ([typedSmokyWords]).
  if (arriving.length > typedSmokyWords) arriving.removeRange(0, arriving.length - typedSmokyWords);
  return <Moving>[...moving, ...arriving];
}

List<Moving> _paced(List<Moving> list, double now, double scale) => scale == 1 ? list : <Moving>[for (final m in list) m._paced(now, scale)];

/// Everything in motion, mapped through every change, until the drawing says it has settled.
final StateField<List<Moving>> wispState = StateField.define<List<Moving>>(
  create: (state) => const <Moving>[],
  update: (moving, tr) {
    var next = moving;
    if (tr.docChanged) {
      next = <Moving>[
        for (final m in next)
          if (_mapped(m, tr) case final Moving moved) moved,
      ];
    }
    final still = tr.state.facet(wispStill);
    final scale = tr.state.facet(wispPace);
    for (final effect in tr.effects) {
      final reveal = revealWisp.cast(effect);
      if (reveal != null && !still) {
        final now = wispNow();
        next = <Moving>[...next, ..._paced(_revealing(tr.state, reveal.value.from, reveal.value.to, now), now, scale)];
      }
      final settled = settle.cast(effect);
      if (settled != null) {
        final done = settled.value.toSet();
        next = <Moving>[
          for (final m in next)
            if (!done.contains(m.id)) m,
        ];
      }
    }
    if (!tr.docChanged || still) return next;
    final kind = tr.annotation(wisp);
    if (kind != null) {
      final now = wispNow();
      return <Moving>[...next, ..._paced(_movingIn(tr, now, light: kind == WispKind.typed), now, scale)];
    }
    // A board's own edits are not typing: a card ticked, moved or added rewrites the item's box and the fence under
    // the drawing, and none of that is a letter someone wrote.
    if (tr.isUserEvent('input.board')) return next;
    // Nor is what the + beside the line puts in: it is there at once.
    if (tr.isUserEvent('input.plus')) return next;
    if (tr.state.facet(typing) && (tr.isUserEvent('input') || tr.isUserEvent('delete'))) {
      final now = wispNow();
      final deleting = tr.isUserEvent('delete');
      // A tapped box turns one letter between two that stay put: it dissolves where it stands, the mark coming as
      // well as going, since a tap is not typing. Everything typed or pasted is simply there; only what it replaced
      // smokes.
      final box = tr.isUserEvent('input.toggle') || tr.isUserEvent('input.choice');
      return <Moving>[...next, ..._paced(_movingIn(tr, now, outMs: deleting ? _deleteDuration(now) : _outMs, singleLetters: !deleting, box: box, arrive: box), now, scale)];
    }
    return next;
  },
);

Moving? _mapped(Moving m, Transaction tr) {
  final from = tr.changes.mapPos(m.from, m.gone.isNotEmpty ? -1 : 1);
  final to = tr.changes.mapPos(m.to, -1);
  // A word the change took away entirely is done moving.
  if (m.gone.isEmpty && to <= from) return null;
  return m._moved(from, to);
}

/// The letters and ghosts in motion right now, for a test or a caller wondering whether to wait.
List<Moving> moving(EditorState state) => state.fieldOrNull(wispState) ?? const <Moving>[];

// ---- the leaving half, drawn -------------------------------------------------------------------------------------

/// How much of what left is drawn: its first line, a few words of it.
const int _ghostChars = 48;

class _GhostWidget extends EditorWidget {
  const _GhostWidget(this.moving);

  final Moving moving;

  @override
  bool eq(_GhostWidget other) => other.moving.id == moving.id;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) => _Ghost(moving: moving, view: EditorViewScope.maybeOf(context), style: EditorRunScope.maybeOf(context)?.look.style ?? DefaultTextStyle.of(context).style);
}

class _Ghost extends StatefulWidget {
  const _Ghost({required this.moving, required this.view, required this.style});

  final Moving moving;
  final EditorViewLike? view;
  final TextStyle style;

  @override
  State<_Ghost> createState() => _GhostState();
}

class _GhostState extends State<_Ghost> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: Duration(microseconds: (widget.moving.dur * 1000).round().clamp(1000, 5000000)));

  @override
  void initState() {
    super.initState();
    _run.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      // Settled: the field lets it go, and the widget with it.
      final view = widget.view;
      if (view != null && moving(view.state).any((m) => m.id == widget.moving.id)) view.dispatch(TransactionSpec(effects: settle.of(<int>[widget.moving.id])));
    });
    final wait = widget.moving.at - wispNow();
    if (wait > 1) {
      Future<void>.delayed(Duration(microseconds: (wait * 1000).round()), () {
        if (mounted) _run.forward();
      });
    } else {
      _run.forward();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gone = widget.moving.gone.split('\n').first;
    final text = gone.length > _ghostChars ? gone.substring(0, _ghostChars) : gone;
    return IgnorePointer(
      // No room of its own: the ghost is drawn from the point the text left, over what closed up behind it.
      child: CustomPaint(size: Size.zero, painter: _GhostPainter(text, widget.style, _run, widget.moving)),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter(this.text, this.style, this.run, this.moving) : super(repaint: run);

  final String text;
  final TextStyle style;
  final Animation<double> run;
  final Moving moving;

  @override
  void paint(Canvas canvas, Size size) {
    if (text.trim().isEmpty) return;
    final t = run.value.clamp(0.0, 1.0);
    // `wispOut`, eased in: whole, then mostly gone by 55%, then nothing; lifting five pixels as it goes.
    final opacity = t < 0.55 ? 1 - 0.6 * Curves.easeIn.transform(t / 0.55) : 0.4 * (1 - Curves.easeIn.transform((t - 0.55) / 0.45));
    if (opacity <= 0) return;
    final lift = moving.box ? 0.0 : -5 * Curves.easeIn.transform(t);
    final glyph = LetterGlyph.of(text, style);
    final box = Size(glyph.painter.width, glyph.painter.height);
    final bend = wispLetterBend * Curves.easeIn.transform(t), soft = wispLetterSoft * Curves.easeIn.transform(t);
    canvas.save();
    // The widget stands on the line's baseline: the letters are set back on it.
    canvas.translate(0, lift - glyph.baseline);
    final kit = WispKit.maybe;
    final seed = wispSlotSeed(moving.id % 12);
    final table = kit?.tableNow(seed);
    if (kit == null || table == null || (bend < 0.05 && soft < 0.05)) {
      final paint = Paint()..color = Color.fromRGBO(0, 0, 0, opacity);
      if (soft >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.decal);
      canvas.saveLayer(Rect.fromLTWH(-24, -24, box.width + 48, box.height + 48), paint);
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      final image = glyph.image();
      paintWispLetter(canvas, kit: kit, table: table, glyph: image, glyphRect: glyph.imageRect, box: box, smoke: WispSmoke.flat(seed: seed, frequency: wispLetterFrequency, bend: bend, blur: soft), opacity: opacity);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GhostPainter oldDelegate) => oldDelegate.text != text || oldDelegate.moving.id != moving.id;
}

DecorationSet _ghosts(List<Moving> all) {
  final leaving = <Moving>[
    for (final m in all)
      if (m.gone.isNotEmpty) m,
  ]..sort((a, b) => a.from != b.from ? a.from - b.from : a.id - b.id);
  if (leaving.isEmpty) return Decoration.none;
  return Decoration.set(<Range<Decoration>>[for (final m in leaving) Decoration.widget(widget: _GhostWidget(m), side: 1).range(m.from)]);
}

/// What the person takes out smokes away where it stood: the field, the switch, and the ghosts.
Extension wispDepartures({bool typing_ = true}) => Extension.list(<Extension>[
  wispState,
  typing.of(typing_),
  EditorViewLike.decorations.compute(<Object>[wispState], (state) => _ghosts(state.field(wispState))),
]);
