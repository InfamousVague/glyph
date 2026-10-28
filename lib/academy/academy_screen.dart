/// Ghost Academy: markdown taught a mark at a time, by typing it (Matt: "we need a Glyph Academy section that
/// teaches you markdown then teaches you the extra stuff we have. Build the academy section start with just the
/// markdown basics set it up as a live code type thing where it teaches you then you type it and see it format
/// below"). A port of `src/app/academy/AcademyScreen.tsx` with `AcademyScreen.module.css`.
///
/// A lesson says what a mark does and shows one line using it; then the person writes their own, in a field with the
/// note's own drawing of it underneath, changing as they type (playground.dart). The moment what they typed has the
/// mark in it the lesson is ticked and Next appears, but nothing is taken away, so they can carry on playing with
/// it. **Show me** writes the example into the field for anyone who would rather start from something that works,
/// and a lesson can always be skipped.
///
/// It opens on its contents (Matt: "Rework the ghost.md academy so that there is the option to skip default markdown
/// if the user doesn't want to learn that ... Make chapters in the lesson as well"): the chapters, each with what it
/// covers and how much of it is learned, a way to carry on where you left off, and a switch for a person who knows
/// Markdown already, which leaves out every lesson any Markdown app reads and keeps Ghost.md's own. A chapter can be
/// started from the contents, and its end is a page of its own: what it taught, any lesson to take again, and the
/// next chapter. Nothing typed here is saved as a note: it is a page to play on.
///
/// A lesson for a plugin's mark is on offer only while that mark is switched on, so the Academy never teaches what
/// the note would not draw. The bars along the top are the chapter being taken, and the count beside the title is
/// all of it.
///
/// It is read aloud and it is in colour (Matt, 2026-10-28: "Add the voiceover to the academy sections and spice up
/// the academy with more colors and iconography"), the way the walkthrough is:
/// - **The voice** (voice.dart, said by [VoiceOver], lib/guide/narrator.dart) welcomes a person as the Academy opens
///   on its chapters, says a chapter's hello as it is begun and then the lesson's teaching, and each lesson's teaching
///   as it opens. It stops as the page goes (back, Next, Skip, out of the Academy) and as the app leaves the screen.
///   The speaker in the top bar is the walkthrough's, and so is the switch it remembers: one "rather read" for both.
/// - **The colour** (looks.dart): each chapter has a hue of its own, the Market's and the walkthrough's. The contents
///   open under a band in every chapter's colour, each chapter's row wears its colour and its sign, a lesson opens
///   under a band of its chapter's with its mark in the middle, the bars along the top and the words over the title
///   are the chapter's colour, and the end of a chapter is a page in its colour, the ghost ticking every box once all
///   of it is learned. The bands stand still under Reduce motion (lib/guide/pages/band.dart [HueBand]).
/// - **Simple** (`Preferences.simple`, GHST-103): the contents show the two Markdown chapters, and the five chapters of
///   Ghost's own marks wait behind a More row that opens in place.
///
/// What differs:
/// - **The rows of the chapters and of a chapter's end are in the app's own face.** On the page they are `<button>`s
///   whose CSS never says `font: inherit`, so a browser draws them in its own button face at 13.333px (Arial on a
///   Mac, Roboto in the phone's WebView). Here they keep that size and that face's line, in Inter. A test that holds
///   the rows to the page Chromium drew sets [academyButtonFace] to the browser's face.
/// - The buttons are `.app-pill` and `.app-word` written here (`_Pill`, `_Word`) and not lib/app/widgets.dart's:
///   in a foot too narrow for both, the page's buttons shrink and their words wrap (`_Foot` is that rule of flex),
///   which those two cannot do.
/// - The row of a chapter and of a lesson to take again is lit while pressed as well as under a pointer; the page's
///   was `:hover` alone.
/// - The plugins are listened to (`plugins`, a `ChangeNotifier`) where the page called `usePlugins()`.
/// - The page had no colour but its accent, no bands, no voice and no speaker: the chapters' rows were a number in a
///   grey circle, the bars ink. Everything else is laid out as the page laid it out, under the bands
///   (test/academy/reference_test.dart holds it to the page from below each band).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/back.dart';
import '../core/preferences.dart';
import '../editor/state/state.dart' show Extension;
import '../guide/narrator.dart';
import '../guide/voice_button.dart';
import '../home/home_parts.dart' show CssLines;
import '../plugins/registry.dart';
import 'lessons.dart';
import 'looks.dart';
import 'playground.dart';
import 'voice.dart';

/// The face the rows that are `<button>`s on the page are drawn in; the app's own while null. See the header.
@visibleForTesting
String? academyButtonFace;

/// Where the Academy is: its contents, a lesson, or the end of a chapter (`Place`).
sealed class _Place {
  const _Place();
}

class _AtContents extends _Place {
  const _AtContents();
}

class _AtLesson extends _Place {
  const _AtLesson(this.id);
  final String id;
}

class _AtChapterEnd extends _Place {
  const _AtChapterEnd(this.chapter);
  final String chapter;
}

class AcademyScreen extends StatefulWidget {
  const AcademyScreen({super.key, required this.onDone, required this.onCheatSheet, this.extensions = const <Extension>[], this.voice, this.simple});

  /// Out of the Academy: its arrow, or back, from the contents.
  final VoidCallback onDone;

  /// The cheat sheet, asked for from the contents.
  final VoidCallback onCheatSheet;

  /// More of the editor's pieces for the note a lesson shows (playground.dart `Playground.extensions`).
  final List<Extension> extensions;

  /// What reads the Academy aloud; one of its own, let go with the screen, unless given (a test's, which counts).
  final VoiceOver? voice;

  /// Simple's contents, or Advanced's; the person's own mode ([Preferences.simple]) unless told.
  final bool? simple;

  @override
  State<AcademyScreen> createState() => _AcademyScreenState();
}

class _AcademyScreenState extends State<AcademyScreen> with WidgetsBindingObserver {
  bool _skipStandard = readSkipStandard();
  Set<String> _done = readProgress();

  /// Where the Academy is, held until Next is pressed. A lesson cannot be worked out from what has been learned:
  /// passing it would then move the page on the instant the mark was typed, and the whole point is to stay and
  /// watch it format.
  _Place _place = const _AtContents();
  String _typed = '';
  bool _hinting = false;
  Registry? _registry;

  /// Simple's More on the contents, pressed: every chapter shown.
  bool _moreChapters = false;

  late final VoiceOver _voice = widget.voice ?? VoiceOver();

  /// The chapter whose hello has been said since the contents were left: begun again from the contents, it says
  /// hello again; Next from one of its lessons to the next does not.
  String? _greeted;

  @override
  void initState() {
    super.initState();
    // Drawn again when a plugin is switched, so its lessons come and go with its marks.
    _registry = plugins..addListener(_switched);
    preferences.addListener(_switched);
    _voice.addListener(_switched);
    WidgetsBinding.instance.addObserver(this);
    // Read once for the app (voice.dart), so a chapter begun can say its hello before its first lesson.
    unawaited(academyVoiceLengths());
    // The welcome, once, as the Academy opens on its contents.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _place is _AtContents) _voice.say([(asset: academyVoiceAsset('welcome'), length: null)]);
    });
  }

  @override
  void dispose() {
    _registry?.removeListener(_switched);
    preferences.removeListener(_switched);
    _voice.removeListener(_switched);
    WidgetsBinding.instance.removeObserver(this);
    // Out of the Academy: so is its voice.
    if (widget.voice == null) {
      _voice.dispose();
    } else {
      unawaited(_voice.hush());
    }
    super.dispose();
  }

  /// The app has left the screen: the voice stops with it, and is not started again on the way back, where the words
  /// are on the page to read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) unawaited(_voice.hush());
  }

  void _switched() {
    if (mounted) setState(() {});
  }

  /// Another place. A new lesson starts on a clean page, with its hint put away, and is said aloud: after its
  /// chapter's hello where the chapter is being begun. The contents and a chapter's end are quiet.
  void _go(_Place place) {
    final was = _place;
    final same = was is _AtLesson && place is _AtLesson && was.id == place.id;
    setState(() {
      _place = place;
      if (!same) {
        _typed = '';
        _hinting = false;
      }
    });
    if (same) return;
    if (place is _AtLesson) {
      final lesson = lessons.where((one) => one.id == place.id).firstOrNull;
      if (lesson == null) return;
      final hello = chapterVoice(lesson.chapter);
      final length = academyVoiceLengthsRead[hello];
      final greet = _greeted != lesson.chapter && length != null;
      _greeted = lesson.chapter;
      _voice.say([
        if (greet) (asset: academyVoiceAsset(hello), length: length),
        (asset: academyVoiceAsset(lesson.id), length: null),
      ]);
    } else {
      if (place is _AtContents) _greeted = null;
      // Nothing to say, and nothing to say again if the speaker is switched on here.
      _voice.say(const []);
    }
  }

  /// What is in the field now. Ticked the moment the mark appears, and only once: the tick is a fact about the
  /// person, not about the field.
  void _setTyped(Lesson lesson, String text) {
    final passed = lesson.passes(text);
    final first = passed && !_done.contains(lesson.id);
    setState(() {
      _typed = text;
      if (first) _done = {..._done, lesson.id};
    });
    if (first) {
      writeProgress(_done);
      HapticsProvider.of(context)(HapticKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = lessonsNow(_skipStandard);
    final place = _place;
    final lesson = place is _AtLesson ? all.where((one) => one.id == place.id).firstOrNull : null;
    final passed = lesson != null && lesson.passes(_typed);
    final learned = all.where((one) => _done.contains(one.id)).length;
    final chapter = lesson?.chapter ?? (place is _AtChapterEnd ? place.chapter : null);
    final bars = chapter == null ? const <Lesson>[] : lessonsIn(chapter, all);
    final atContents = place is _AtContents;
    final look = chapter == null ? academyLook : lookOf(chapter);

    /// The lesson after this one; at the end of its chapter, that chapter's end page.
    void next(Lesson from) {
      final at = all.indexOf(from) + 1;
      final following = at < all.length ? all[at] : null;
      _go(following != null && following.chapter == from.chapter ? _AtLesson(following.id) : _AtChapterEnd(from.chapter));
    }

    /// A chapter, from its first lesson not learned yet, or its first if all are.
    void startChapter(String name) {
      final its = lessonsIn(name, all);
      final first = its.where((one) => !_done.contains(one.id)).firstOrNull ?? its.firstOrNull;
      if (first != null) _go(_AtLesson(first.id));
    }

    final Widget card;
    if (lesson != null) {
      card = _LessonCard(
        lesson: lesson,
        chapter: lessonsIn(lesson.chapter, all),
        typed: _typed,
        onTyped: (text) => _setTyped(lesson, text),
        passed: passed,
        hinting: _hinting,
        onHint: () => setState(() => _hinting = true),
        onShowMe: () => _setTyped(lesson, lesson.example),
        onNext: () => next(lesson),
        extensions: widget.extensions,
      );
    } else if (place is _AtChapterEnd) {
      card = _ChapterEnd(chapter: place.chapter, lessons: all, done: _done, onAgain: (id) => _go(_AtLesson(id)), onNextChapter: startChapter, onContents: () => _go(const _AtContents()));
    } else {
      card = _Contents(
        lessons: all,
        done: _done,
        skipStandard: _skipStandard,
        onSkipStandard: (skip) {
          setState(() => _skipStandard = skip);
          writeSkipStandard(skip);
        },
        onLesson: (id) => _go(_AtLesson(id)),
        onChapter: startChapter,
        onStartOver: () {
          setState(() => _done = <String>{});
          writeProgress(const <String>{});
          final first = all.firstOrNull;
          if (first != null) _go(_AtLesson(first.id));
        },
        onCheatSheet: widget.onCheatSheet,
        simple: (widget.simple ?? preferences.value.simple) && !_moreChapters,
        onMore: () => setState(() => _moreChapters = true),
      );
    }

    final ink = t.color('app-ink');
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
    void back() => atContents ? widget.onDone() : _go(const _AtContents());

    // `.top`
    final top = Padding(
      key: const ValueKey('academy-top'),
      // `.back { margin-inline-start: calc(-1 * var(--glacier-space-2)) }`
      padding: EdgeInsets.only(left: gutterStart - t.space(2), right: gutterEnd, top: t.len('app-safe-top') + t.space(3)),
      child: Row(
        children: [
          GlacierPressable(
            key: const ValueKey('academy-back'),
            onPressed: back,
            semanticLabel: atContents ? 'Close the Academy' : 'The Academy’s chapters',
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              radius: t.radius('full'),
              child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: ink))),
            ),
          ),
          SizedBox(width: t.space(3)),
          Expanded(
            key: const ValueKey('academy-heading'),
            child: Semantics(
              header: true,
              child: Row(
                // `.heading { gap: var(--glacier-space-2) }`
                spacing: t.space(2),
                children: [
                  // The mortarboard in the colour of the chapter being taken, or the Academy's own on its contents.
                  ExcludeSemantics(child: AppIcon(Lucide.graduationCap, size: 18, color: look.ink(t))),
                  Flexible(child: Text('Ghost Academy', style: t.textAt(t.fontSize('md'), weight: 'semibold', color: ink))),
                ],
              ),
            ),
          ),
          SizedBox(width: t.space(3)),
          Semantics(
            label: '$learned of ${all.length} learned',
            child: ExcludeSemantics(
              child: Text('$learned/${all.length}', key: const ValueKey('academy-count'), style: _tabular(t.textAt(t.fontSize('sm'), color: t.color('app-ink-3')))),
            ),
          ),
          // The walkthrough's speaker, the size of the back arrow so the bar keeps its height.
          VoiceButton(key: const ValueKey('academy-voice'), off: _voice.muted, onPressed: () => _voice.setMuted(!_voice.muted), side: t.space(8), icon: 20),
        ],
      ),
    );

    return OnBack(
      // Back from a lesson or a chapter's end is the contents; from the contents, out of the Academy.
      onBack: back,
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              // `.screen { min-block-size: 100dvh }`
              constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? box.maxHeight : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  top,
                  // A bar for every lesson of the chapter: faint to come, ink for learned, lit for the one being taken.
                  if (bars.isNotEmpty)
                    ExcludeSemantics(
                      child: Padding(
                        key: const ValueKey('academy-bars'),
                        // `.bars { gap: 3px; margin: var(--glacier-space-4) 0 var(--glacier-space-2) }`
                        padding: EdgeInsets.only(left: gutterStart, right: gutterEnd, top: t.space(4), bottom: t.space(2)),
                        child: Row(
                          spacing: 3,
                          children: [
                            for (final one in bars) Expanded(key: ValueKey('bar:${one.id}'), child: _Bar(done: _done.contains(one.id), now: one.id == lesson?.id, hue: look.ink(t))),
                          ],
                        ),
                      ),
                    ),
                  // `.page`
                  Padding(
                    padding: EdgeInsets.only(left: gutterStart, right: gutterEnd, top: t.space(4), bottom: t.len('app-safe-bottom') + t.space(8)),
                    // `.card { max-inline-size: 42rem; margin-inline: auto }`
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: t.lenOf('42rem')),
                        child: KeyedSubtree(key: const ValueKey('academy-card'), child: card),
                      ),
                    ),
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

/// `font-variant-numeric: tabular-nums`.
TextStyle _tabular(TextStyle style) => style.copyWith(fontFeatures: [...?style.fontFeatures, const FontFeature.tabularFigures()]);

/// The page's own size, `1rem`: what a rule that names no size has.
double _rem(Tokens t) => t.lenOf('1rem');

/// Text in a row that is a `<button>` on the page: the browser's button face (see the header) at [px], with the
/// line that face gives `line-height: normal` (Arial's ascent and descent, each rounded to a whole pixel) unless
/// [height] names one.
TextStyle _buttonText(Tokens t, double px, {String weight = 'regular', Color? color, double? height, bool tabular = false}) {
  final line = height ?? ((0.905 * px).round() + (0.212 * px).round()) / px;
  var style = t.textAt(px, weight: weight, color: color, height: line);
  final face = academyButtonFace;
  if (face != null) {
    style = TextStyle(inherit: false, fontFamily: face, fontSize: px, fontWeight: t.weight(weight), color: style.color, height: line, leadingDistribution: TextLeadingDistribution.even, decoration: TextDecoration.none);
  }
  return tabular ? _tabular(style) : style;
}

/// `.bar`: one lesson of the chapter being taken, in the chapter's colour ([hue]): the one in hand full, the learned
/// ones a little lighter, the ones to come the page's faint rule.
class _Bar extends StatelessWidget {
  const _Bar({required this.done, required this.now, required this.hue});

  final bool done;
  final bool now;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `.bar[data-now]` after `.bar[data-done]`: the one in hand is lit whether or not it is learned.
    final color = now
        ? hue
        : done
        ? hue.withValues(alpha: 0.5)
        : t.color('glacier-border-strong');
    return TweenAnimationBuilder<double>(
      // `transform 260ms cubic-bezier(0.2, 1.6, 0.4, 1)`; `.bar[data-now] { transform: scaleY(2) }`
      tween: Tween<double>(end: now ? 2 : 1),
      duration: const Duration(milliseconds: 260),
      curve: const Cubic(0.2, 1.6, 0.4, 1),
      builder: (context, scale, child) => Transform.scale(scaleY: scale, child: child),
      child: AnimatedContainer(
        // `background-color 200ms ease-out`
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 4,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(t.radius('full'))),
      ),
    );
  }
}

/// `.card`: one column, `gap: var(--glacier-space-3)`.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: context.tokens.space(3), children: children);
}

/// `.chapter`: where this is, in small spaced capitals, in the chapter's colour ([look]).
Widget _eyebrow(Tokens t, String words, ChapterLook look) {
  final xs = t.fontSize('xs');
  return Text(words.toUpperCase(), key: const ValueKey('academy-chapter'), style: t.textAt(xs, weight: 'semibold', color: look.ink(t), tracking: t.len('app-tracking-caps', em: xs)));
}

/// `.title`
Widget _title(Tokens t, String words) => Semantics(
  header: true,
  child: Text(words, key: const ValueKey('academy-title'), style: t.textAt(t.fontSize('xl'), weight: 'semibold', color: t.color('app-ink'))),
);

/// `.teach`
Widget _teach(Tokens t, String words) => _lined(t, words, _rem(t), t.len('glacier-leading-lg'), t.textAt(_rem(t), color: t.color('app-ink-2'), height: t.len('glacier-leading-lg')));

/// Words of several lines whose `line-height` is not a whole pixel: as tall as the page's lines, where Flutter
/// rounds each to one (lib/home/home_parts.dart `CssLines`).
Widget _lined(Tokens t, String words, double px, double leading, TextStyle style, {Key? key}) => CssLines(key: key, lineHeight: leading * px, child: Text(words, style: style));

/// One lesson: what the mark does, a line using it, and the live page to write your own on (`LessonCard`).
class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.chapter,
    required this.typed,
    required this.onTyped,
    required this.passed,
    required this.hinting,
    required this.onHint,
    required this.onShowMe,
    required this.onNext,
    required this.extensions,
  });

  final Lesson lesson;

  /// The lessons of its chapter, for where it is among them.
  final List<Lesson> chapter;
  final String typed;
  final ValueChanged<String> onTyped;
  final bool passed;
  final bool hinting;
  final VoidCallback onHint;
  final VoidCallback onShowMe;
  final VoidCallback onNext;
  final List<Extension> extensions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final look = lookOf(lesson.chapter);
    final at = chapter.indexOf(lesson) + 1;
    final Widget said;
    if (passed) {
      // `.praise`
      said = Row(
        key: const ValueKey('academy-praise'),
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(2),
        children: [
          ExcludeSemantics(child: AppIcon(Lucide.circleCheck, size: 18, strokeWidth: 2.4, color: look.ink(t))),
          Flexible(child: Text(lesson.praise, style: t.textAt(_rem(t), weight: 'semibold', color: ink))),
        ],
      );
    } else if (hinting) {
      // `.hint`
      said = Text(lesson.hint, key: const ValueKey('academy-hint'), style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3')));
    } else {
      said = _Word(onPressed: onHint, label: 'Show me a hint');
    }
    return _Card(
      children: [
        LessonBand(chapter: lesson.chapter, symbol: lesson.symbol),
        _eyebrow(t, 'Chapter ${chapters.indexOf(lesson.chapter) + 1} · ${lesson.chapter} · $at of ${chapter.length}', look),
        _title(t, lesson.title),
        _teach(t, teachOf(lesson)),
        // `.example`: the line to look at, in the typewriter face, with a way to have it written for you.
        DecoratedBox(
          key: const ValueKey('academy-example'),
          // A wash of the chapter's colour, where the page's was the ink's.
          decoration: BoxDecoration(color: look.wash(t), borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Padding(
            padding: EdgeInsets.all(t.space(3)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Wrapped, never cut off: a video's line is longer than a phone is wide.
                Flexible(
                  child: _lined(t, lesson.example, t.fontSize('sm'), t.len('glacier-leading-md'), t.textAt(t.fontSize('sm'), mono: true, color: ink, height: t.len('glacier-leading-md')), key: const ValueKey('academy-example-text')),
                ),
                SizedBox(width: t.space(3)),
                _Word(key: const ValueKey('academy-show-me'), onPressed: onShowMe, label: 'Show me', icon: Lucide.wandSparkles, spaced: true),
              ],
            ),
          ),
        ),
        // `.task`
        Text(taskOf(lesson), key: const ValueKey('academy-task'), style: t.textAt(_rem(t), weight: 'semibold', color: ink)),
        Playground(value: typed, onChange: onTyped, placeholder: lesson.example, extensions: extensions),
        _Foot(
          start: said,
          end: passed ? _Pill(key: const ValueKey('academy-next'), onPressed: onNext, label: 'Next', colours: look.colours) : _Word(key: const ValueKey('academy-next'), onPressed: onNext, label: 'Skip'),
        ),
      ],
    );
  }
}

/// The contents, where the Academy opens: a way on from where it was left, the switch for a person who knows
/// Markdown already, and the chapters, each with what it covers and how much of it is learned. Once everything is
/// learned it is also the summary, with every chapter to take again (`Contents`).
class _Contents extends StatelessWidget {
  const _Contents({
    required this.lessons,
    required this.done,
    required this.skipStandard,
    required this.onSkipStandard,
    required this.onLesson,
    required this.onChapter,
    required this.onStartOver,
    required this.onCheatSheet,
    this.simple = false,
    this.onMore,
  });

  final List<Lesson> lessons;
  final Set<String> done;

  /// Simple's contents, More not yet pressed: the two Markdown chapters, and a row for the rest.
  final bool simple;
  final VoidCallback? onMore;
  final bool skipStandard;
  final ValueChanged<bool> onSkipStandard;
  final ValueChanged<String> onLesson;
  final ValueChanged<String> onChapter;
  final VoidCallback onStartOver;
  final VoidCallback onCheatSheet;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final left = lessons.where((lesson) => !done.contains(lesson.id)).firstOrNull;
    final begun = lessons.any((lesson) => done.contains(lesson.id));
    final sm = t.fontSize('sm');
    // In Simple the chapters of Ghost's own marks wait behind More, which opens in place.
    final shown = simple ? chapters.take(_simpleChapters).toList() : chapters;
    return _Card(
      children: [
        const AcademyHero(),
        _title(
          t,
          left != null
              ? begun
                    ? 'Carry on learning'
                    : 'Learn what a note can hold'
              : 'That is every mark.',
        ),
        _teach(
          t,
          left != null
              ? 'A mark at a time: what it does, an example, and a line of your own to write, drawn as the note draws it while you type.'
              : 'Every mark a note can carry is one you can now write by hand. The Markdown ones read the same in any app that knows Markdown, and Ghost’s own read as plain words there. Take any chapter again below.',
        ),
        if (left != null)
          // `.go { justify-self: start }`
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(key: const ValueKey('academy-go'), onPressed: () => onLesson(left.id), label: begun ? 'Continue: ${left.title}' : 'Start', after: Lucide.arrowRight),
          ),
        // `.skip`: the switch for a person who knows Markdown already, its words, and Glacier's switch at the end.
        MergeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSkipStandard(!skipStandard),
            child: DecoratedBox(
              key: const ValueKey('academy-skip'),
              decoration: BoxDecoration(border: Border.all(color: t.color('app-rule'), width: 1), borderRadius: BorderRadius.circular(t.radius('lg'))),
              child: Padding(
                padding: EdgeInsets.all(1 + t.space(3)),
                child: Row(
                  spacing: t.space(3),
                  children: [
                    Expanded(
                      child: Column(
                        key: const ValueKey('academy-skip-words'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 2,
                        children: [
                          Text('I know Markdown already', style: t.textAt(_rem(t), weight: 'medium', color: ink)),
                          _lined(
                            t,
                            'Skip what any Markdown app reads: headings, bold, lists, links, tables, pictures. Ghost’s own marks are still taught.',
                            sm,
                            t.len('glacier-leading-md'),
                            t.textAt(sm, color: quiet, height: t.len('glacier-leading-md')),
                            key: const ValueKey('academy-skip-said'),
                          ),
                        ],
                      ),
                    ),
                    GlacierSwitch(key: const ValueKey('academy-skip-switch'), ariaLabel: 'I know Markdown already', checked: skipStandard, onCheckedChange: onSkipStandard),
                  ],
                ),
              ),
            ),
          ),
        ),
        // `.chapters { gap: 1px }`, a little more between rows that each wear a colour.
        Semantics(
          label: 'Chapters',
          container: true,
          explicitChildNodes: true,
          child: Column(
            key: const ValueKey('academy-chapters'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: t.space(2),
            children: [
              for (final (index, chapter) in shown.indexed) _chapterRow(context, index, chapter),
              if (shown.length < chapters.length) _moreRow(context, chapters.length - shown.length),
            ],
          ),
        ),
        _teach(t, 'Every mark is in the cheat sheet as well, to look up while you write.'),
        _Foot(
          start: _Word(key: const ValueKey('academy-start-again'), onPressed: onStartOver, label: 'Start again', icon: Lucide.rotateCcw),
          end: _Pill(key: const ValueKey('academy-cheat-sheet'), onPressed: onCheatSheet, label: 'Cheat sheet', before: Lucide.listChecks),
        ),
      ],
    );
  }

  /// `.chapterRow`, in the chapter's colour: its sign on a tile of its wash (a tick once all of it is learned), a
  /// faint wash of the colour behind the row, and its count in the colour.
  Widget _chapterRow(BuildContext context, int index, String chapter) {
    final t = context.tokens;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final look = lookOf(chapter);
    final its = lessonsIn(chapter, lessons);
    final learned = its.where((lesson) => done.contains(lesson.id)).length;
    final skipped = its.isEmpty;
    final all = its.isNotEmpty && learned == its.length;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      key: ValueKey('chapter:$chapter'),
      onPressed: skipped ? null : () => onChapter(chapter),
      semanticLabel: 'Chapter ${index + 1}, $chapter',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('lg'),
        // `.chapterRow:disabled { opacity: 0.45 }`
        child: Opacity(
          opacity: skipped ? 0.45 : 1,
          // The row is named by its chapter (`aria-label`), not by everything written in it.
          child: _Named(
            constraints: BoxConstraints(minHeight: t.space(12)),
            padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(3)),
            // Deeper while pressed or under a pointer, as the page's row was lit then.
            decoration: BoxDecoration(color: look.wash(t, light: !skipped && (state.hovered || state.pressed) ? 0.14 : 0.07, dark: !skipped && (state.hovered || state.pressed) ? 0.24 : 0.14), borderRadius: BorderRadius.circular(t.radius('lg'))),
            child: Row(
              spacing: t.space(3),
              children: [
                ChapterTile(key: ValueKey('chapter-number:$chapter'), chapter: chapter, learned: all),
                Expanded(
                  child: Column(
                    key: ValueKey('chapter-words:$chapter'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 2,
                    children: [
                      Text(chapter, key: ValueKey('chapter-title:$chapter'), style: _buttonText(t, _buttonSize, weight: 'semibold', color: ink)),
                      _lined(t, chapterAbout[chapter]!, sm, t.len('glacier-leading-md'), _buttonText(t, sm, color: quiet, height: t.len('glacier-leading-md')), key: ValueKey('chapter-about:$chapter')),
                    ],
                  ),
                ),
                Text(skipped ? 'Skipped' : '$learned/${its.length}', key: ValueKey('chapter-count:$chapter'), style: _buttonText(t, t.fontSize('xs'), weight: 'semibold', color: skipped ? quiet : look.ink(t), tabular: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Simple's More: the chapters still to come, opened where they are (GHST-103).
  Widget _moreRow(BuildContext context, int more) {
    final t = context.tokens;
    final quiet = t.color('app-ink-3');
    return GlacierPressable(
      key: const ValueKey('academy-more-chapters'),
      onPressed: onMore,
      semanticLabel: 'More chapters',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('lg'),
        child: _Named(
          constraints: BoxConstraints(minHeight: t.space(12)),
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
          decoration: BoxDecoration(
            color: state.hovered || state.pressed ? t.color('app-ink').withValues(alpha: 0.06) : null,
            border: Border.all(color: t.color('app-rule')),
            borderRadius: BorderRadius.circular(t.radius('lg')),
          ),
          child: Row(
            spacing: t.space(3),
            children: [
              // The Academy's own wash, for the chapters still behind it.
              const ChapterTile(chapter: '', learned: false, icon: Lucide.layoutGrid),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text('More', style: _buttonText(t, _buttonSize, weight: 'semibold', color: t.color('app-ink'))),
                    Text('$more more chapters on what only Ghost draws: tags, boards, tickets, effects.', style: _buttonText(t, t.fontSize('sm'), color: quiet, height: t.len('glacier-leading-md'))),
                  ],
                ),
              ),
              AppIcon(Lucide.chevronDown, size: 18, color: quiet),
            ],
          ),
        ),
      ),
    );
  }
}

/// How many chapters Simple's contents show before More: the two of Markdown any app reads.
const int _simpleChapters = 2;

/// A box whose own name stands for what is in it: a `Container` under `ExcludeSemantics`.
class _Named extends StatelessWidget {
  const _Named({required this.constraints, required this.padding, required this.decoration, required this.child});

  final BoxConstraints constraints;
  final EdgeInsets padding;
  final Decoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: Container(constraints: constraints, padding: padding, decoration: decoration, child: child));
}

/// A browser's own size for a button's words, where no rule gives one: `13.3333px`.
const double _buttonSize = 40 / 3;

/// The end of a chapter: what it taught, any lesson to take again, and the chapter after it (`ChapterEnd`).
class _ChapterEnd extends StatelessWidget {
  const _ChapterEnd({required this.chapter, required this.lessons, required this.done, required this.onAgain, required this.onNextChapter, required this.onContents});

  final String chapter;
  final List<Lesson> lessons;
  final Set<String> done;
  final ValueChanged<String> onAgain;
  final ValueChanged<String> onNextChapter;
  final VoidCallback onContents;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final look = lookOf(chapter);
    final its = lessonsIn(chapter, lessons);
    final all = its.every((lesson) => done.contains(lesson.id));
    final following = chapters.skip(chapters.indexOf(chapter) + 1).where((name) => lessonsIn(name, lessons).isNotEmpty).firstOrNull;
    return _Card(
      children: [
        // The chapter seen off in its colour: the ghost ticking every box once all of it is learned.
        ChapterEndBand(chapter: chapter, learned: all),
        _eyebrow(t, 'Chapter ${chapters.indexOf(chapter) + 1} · $chapter', look),
        _title(t, all ? 'Chapter learned.' : 'The end of the chapter.'),
        _teach(t, all ? 'Every mark in $chapter is one you can write by hand now.' : 'You can come back to the ones you skipped whenever you like: tap one to take it.'),
        // `.list { gap: 1px }`
        Column(
          key: const ValueKey('academy-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 1,
          children: [
            for (final lesson in its)
              // `.again`
              GlacierPressable(
                key: ValueKey('again:${lesson.id}'),
                onPressed: () => onAgain(lesson.id),
                builder: (context, state) => GlacierFocusRing(
                  visible: state.focused,
                  radius: t.radius('md'),
                  child: Container(
                    constraints: BoxConstraints(minHeight: t.space(10)),
                    // A button's own `padding-block: 1px`, which the rule leaves as it is.
                    padding: EdgeInsets.symmetric(vertical: 1, horizontal: t.space(3)),
                    decoration: BoxDecoration(color: state.hovered || state.pressed ? ink.withValues(alpha: 0.06) : null, borderRadius: BorderRadius.circular(t.radius('md'))),
                    child: Row(
                      spacing: t.space(3),
                      children: [
                        // `.againTick { inline-size: 1.4em; block-size: 1.4em }`, of the button's own size.
                        ExcludeSemantics(
                          child: Container(
                            key: ValueKey('again-tick:${lesson.id}'),
                            width: 1.4 * _buttonSize,
                            height: 1.4 * _buttonSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: done.contains(lesson.id) ? look.colours.first : look.wash(t, light: 0.14, dark: 0.24), shape: BoxShape.circle),
                            child: done.contains(lesson.id) ? const AppIcon(Lucide.check, size: 14, strokeWidth: 2.6, color: Color(0xFFFFFFFF)) : null,
                          ),
                        ),
                        Expanded(child: Text(lesson.title, key: ValueKey('again-name:${lesson.id}'), style: _buttonText(t, _buttonSize, color: ink))),
                        // `.againMark { max-inline-size: 45%; overflow: hidden; white-space: nowrap; text-overflow: ellipsis }`
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 0.45 * (MediaQuery.sizeOf(context).width - t.len('app-gutter-start') - t.len('app-gutter-end') - 2 * t.space(3))),
                          child: Text(
                            lesson.symbol,
                            key: ValueKey('again-mark:${lesson.id}'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: t.textAt(t.fontSize('xs'), mono: true, color: t.color('app-ink-3')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        _Foot(
          start: _Word(key: const ValueKey('academy-all-chapters'), onPressed: onContents, label: 'All chapters'),
          end: following != null
              // Onward in the next chapter's colour.
              ? _Pill(key: const ValueKey('academy-next-chapter'), onPressed: () => onNextChapter(following), label: 'Next: $following', after: Lucide.arrowRight, colours: lookOf(following).colours)
              : _Pill(key: const ValueKey('academy-next-chapter'), onPressed: onContents, label: 'Done', colours: look.colours),
        ),
      ],
    );
  }
}

/// `.app-pill` (ink.css): the one loud action on the screen. Its words wrap, in the middle, where it is squeezed.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.onPressed, required this.label, this.before, this.after, this.colours});

  final VoidCallback onPressed;
  final String label;
  final LucideIcon? before;
  final LucideIcon? after;

  /// A chapter's wash in place of the ink, with white words on it: the way on, in the colour it leads to.
  final List<Color>? colours;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colours = this.colours;
    final paper = colours != null ? const Color(0xFFFFFFFF) : t.color('app-paper');
    final size = t.fontSize('md');
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        offset: 3,
        radius: t.radius('full'),
        color: colours?.first ?? t.color('app-ink'),
        child: AnimatedScale(
          // `.app-pill:active { transform: scale(0.98) }`
          scale: state.pressed ? 0.98 : 1,
          duration: t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(12)),
            padding: EdgeInsets.symmetric(horizontal: t.space(6)),
            decoration: BoxDecoration(
              color: colours == null ? t.color('app-ink') : null,
              gradient: colours == null ? null : LinearGradient(colors: colours.length > 1 ? colours : [colours.first, colours.first]),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              // `gap: var(--glacier-space-2)`
              spacing: t.space(2),
              children: [
                if (before != null) ExcludeSemantics(child: AppIcon(before!, size: 16, color: paper)),
                Flexible(child: Text(label, textAlign: TextAlign.center, style: t.textAt(size, weight: 'semibold', color: paper, tracking: -0.005 * size))),
                if (after != null) ExcludeSemantics(child: AppIcon(after!, size: 16, color: paper)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.app-word` (app.css): a button that is only its word, muted until pressed. With [icon] it carries one before
/// the word: in the line with it, a space between, or (`.wordRow`, [spaced]) in a row with it, never wrapped.
class _Word extends StatelessWidget {
  const _Word({super.key, required this.onPressed, required this.label, this.icon, this.spaced = false});

  final VoidCallback onPressed;
  final String label;
  final LucideIcon? icon;
  final bool spaced;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) {
        final color = state.pressed ? t.color('glacier-text') : t.color('glacier-text-muted');
        final style = t.textAt(_rem(t), weight: 'medium', color: color);
        final Widget words;
        if (icon == null) {
          words = Text(label, textAlign: TextAlign.center, style: style);
        } else if (spaced) {
          // `.wordRow { display: inline-flex; align-items: center; gap: var(--glacier-space-2); white-space: nowrap }`
          words = Row(
            mainAxisSize: MainAxisSize.min,
            spacing: t.space(2),
            children: [
              ExcludeSemantics(child: AppIcon(icon!, size: 16, color: color)),
              Text(label, softWrap: false, style: style),
            ],
          );
        } else {
          // The icon is a letter of the line: it stands on the line's top, and a space comes after it.
          final space = (TextPainter(text: TextSpan(text: ' ', style: style), textDirection: TextDirection.ltr)..layout()).width;
          words = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: AppIcon(icon!, size: 16, color: color)),
              SizedBox(width: space),
              Flexible(child: Text(label, textAlign: TextAlign.center, style: style)),
            ],
          );
        }
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.space(12)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(2)),
              child: Center(widthFactor: 1, heightFactor: 1, child: words),
            ),
          ),
        );
      },
    );
  }
}

/// `.foot`: two things at the two ends of a row, in the middle of its height (`display: flex; align-items: center;
/// justify-content: space-between; gap: var(--glacier-space-3); min-block-size: var(--glacier-space-8)`). Where the
/// row is too narrow for both, each gives up room in proportion to its width, never below its longest word, and
/// its words wrap: flex's own shrinking.
class _Foot extends MultiChildRenderObjectWidget {
  _Foot({required Widget start, required Widget end}) : endsInPill = end is _Pill, super(key: const ValueKey('academy-foot'), children: [start, end]);

  /// Whether the thing at the end is a pill, whose padding is no part of what it gives up: flex shrinks a thing in
  /// proportion to its content box.
  final bool endsInPill;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFoot(gap: context.tokens.space(3), minHeight: context.tokens.space(8), endInset: endsInPill ? 2 * context.tokens.space(6) : 0);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderFoot renderObject) {
    renderObject
      ..gap = context.tokens.space(3)
      ..minHeight = context.tokens.space(8)
      ..endInset = endsInPill ? 2 * context.tokens.space(6) : 0;
  }
}

class _FootParent extends ContainerBoxParentData<RenderBox> {}

class _RenderFoot extends RenderBox with ContainerRenderObjectMixin<RenderBox, _FootParent>, RenderBoxContainerDefaultsMixin<RenderBox, _FootParent> {
  _RenderFoot({required double gap, required double minHeight, required double endInset}) : _gap = gap, _minHeight = minHeight, _endInset = endInset;

  double _endInset;
  set endInset(double value) {
    if (value == _endInset) return;
    _endInset = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FootParent) child.parentData = _FootParent();
  }

  /// The two widths: each thing's own where there is room, shrunk as flex shrinks them where there is not.
  (double, double) _widths(RenderBox start, RenderBox end, double room) {
    final a = start.getMaxIntrinsicWidth(double.infinity), b = end.getMaxIntrinsicWidth(double.infinity);
    final over = a + b + _gap - room;
    if (over <= 0 || !room.isFinite) return (a, b);
    final leastA = math.min(a, start.getMinIntrinsicWidth(double.infinity)), leastB = math.min(b, end.getMinIntrinsicWidth(double.infinity));
    final inner = math.max(0.0, b - _endInset);
    var wa = a - over * a / (a + inner), wb = b - over * inner / (a + inner);
    // One held at its longest word: the other gives up the rest.
    if (wa < leastA) {
      wa = leastA;
      wb = math.max(leastB, room - _gap - wa);
    } else if (wb < leastB) {
      wb = leastB;
      wa = math.max(leastA, room - _gap - wb);
    }
    return (wa, wb);
  }

  @override
  double computeMinIntrinsicWidth(double height) => firstChild!.getMinIntrinsicWidth(height) + _gap + lastChild!.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) => firstChild!.getMaxIntrinsicWidth(height) + _gap + lastChild!.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) {
    final (a, b) = _widths(firstChild!, lastChild!, width);
    return math.max(_minHeight, math.max(firstChild!.getMinIntrinsicHeight(a), lastChild!.getMinIntrinsicHeight(b)));
  }

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void performLayout() {
    final start = firstChild!, end = lastChild!;
    final room = constraints.maxWidth;
    final (a, b) = _widths(start, end, room);
    start.layout(BoxConstraints.tightFor(width: a), parentUsesSize: true);
    end.layout(BoxConstraints.tightFor(width: b), parentUsesSize: true);
    final height = math.max(_minHeight, math.max(start.size.height, end.size.height));
    final width = room.isFinite ? room : a + _gap + b;
    size = constraints.constrain(Size(width, height));
    (start.parentData! as _FootParent).offset = Offset(0, (size.height - start.size.height) / 2);
    (end.parentData! as _FootParent).offset = Offset(size.width - b, (size.height - end.size.height) / 2);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
