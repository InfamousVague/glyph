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
/// **It opens on a catalog of courses** (Matt, 2026-11-02: "make it easier to browse the academy lessons sort by
/// plugins features like gantts etc redo the academy homepage to be easier to browse like codecademy lessons"): the
/// lessons filed by the feature they teach (courses.dart), where they were the web page's seven chapters. At the top,
/// the course in progress with its bar and Resume (Start before anything is learned); then the switch for a person
/// who knows Markdown already (Matt, earlier: "the option to skip default markdown if the user doesn't want to learn
/// that"), chips for the shelves (All, Markdown, Ghost, Plugins), and each shelf's courses as cards, one across on a
/// phone and two or three on the opened Fold and the Mac: the course's colour and sign, what it is about, its level,
/// its lessons and minutes, and its bar or a tick. A card opens the course's page: what it is, its lessons with their
/// ticks, and Start or Resume into the lesson playground; the end of a course is a page of its own, with any lesson to
/// take again and the next course. Back goes up a level: a lesson to its course, a course to the catalog, the catalog
/// out. Nothing typed here is saved as a note: it is a page to play on.
///
/// **A course on a plugin that is off** (Gantt and timelines, Tickets, Diagrams and math …) is on its shelf all the
/// same, saying it needs the plugin, with the app's chip to turn it on (lib/plugins/projects/tool_chip.dart); its
/// lessons are on offer once it is on, as a plugin mark's lesson always was only while the mark is switched on. The
/// bars along the top are the course being taken, and the count beside the title is every lesson on offer.
///
/// It is read aloud and it is in colour (Matt, 2026-10-28: "Add the voiceover to the academy sections and spice up
/// the academy with more colors and iconography"), the way the walkthrough is:
/// - **The voice** (voice.dart, said by [VoiceOver], lib/guide/narrator.dart) welcomes a person as the Academy opens
///   on its catalog, says a course's hello as it is begun where it has one (Markdown basics, whose hello was the first
///   chapter's), and each lesson's teaching as it opens where it has a clip (the lessons past the web page's have none
///   yet). It stops as the page goes (back, Next, Skip, out of the Academy) and as the app leaves the screen. The
///   speaker in the top bar is the walkthrough's, and so is the switch it remembers: one "rather read" for both.
/// - **The colour** (looks.dart): each course has a hue of its own, the Market's and the walkthrough's. The catalog
///   opens under a band in the Academy's colours, each card wears its course's, a course's page and its lessons open
///   under a band of its colour with its sign or the lesson's mark in the middle, the bars along the top and the words
///   over the title are the course's colour, and the end of a course is a page in its colour, the ghost ticking every
///   box once all of it is learned. The bands stand still under Reduce motion (lib/guide/pages/band.dart [HueBand]).
/// - **Simple** (`Preferences.simple`, GHST-103): the catalog shows the Markdown shelf, and the rest waits behind a
///   More row that opens in place; no chips.
///
/// What differs from the page:
/// - **The rows of a course's lessons are in the app's own face.** On the page they are `<button>`s whose CSS never
///   says `font: inherit`, so a browser draws them in its own button face at 13.333px (Arial on a Mac, Roboto in the
///   phone's WebView). Here they keep that size and that face's line, in Inter. A test that holds a lesson to the page
///   Chromium drew sets [academyButtonFace] to the browser's face.
/// - The buttons are `.app-pill` and `.app-word` written here (`_Pill`, `_Word`) and not lib/app/widgets.dart's:
///   in a foot too narrow for both, the page's buttons shrink and their words wrap (`_Foot` is that rule of flex),
///   which those two cannot do.
/// - The plugins are listened to (`plugins` and the project tools' `projectSuite`, both `ChangeNotifier`s) where the
///   page called `usePlugins()`.
/// - The page had no catalog, no colour but its accent, no bands, no voice and no speaker. A lesson is laid out as the
///   page laid it out, under its band (test/academy/reference_test.dart holds it to the page from below the band).
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
import '../plugins/projects/suite.dart' show ProjectSuite, projectSuite;
import '../plugins/projects/tool_chip.dart' show ToolChip;
import '../plugins/registry.dart';
import '../shell/desktop/mac_lights.dart' show MacLightsRow, trafficLightsRoom;
import 'courses.dart';
import 'lessons.dart';
import 'looks.dart';
import 'playground.dart';
import 'voice.dart';

/// The face the rows that are `<button>`s on the page are drawn in; the app's own while null. See the header.
@visibleForTesting
String? academyButtonFace;

/// Where the Academy is: its catalog, a course's page, a lesson, or the end of a course (`Place`).
sealed class _Place {
  const _Place();
}

class _AtCatalog extends _Place {
  const _AtCatalog();
}

class _AtCourse extends _Place {
  const _AtCourse(this.course);
  final String course;
}

class _AtLesson extends _Place {
  const _AtLesson(this.id);
  final String id;
}

class _AtCourseEnd extends _Place {
  const _AtCourseEnd(this.course);
  final String course;
}

class AcademyScreen extends StatefulWidget {
  const AcademyScreen({super.key, required this.onDone, required this.onCheatSheet, this.extensions = const <Extension>[], this.voice, this.simple});

  /// Out of the Academy: its arrow, or back, from the catalog.
  final VoidCallback onDone;

  /// The cheat sheet, asked for from the catalog.
  final VoidCallback onCheatSheet;

  /// More of the editor's pieces for the note a lesson shows (playground.dart `Playground.extensions`).
  final List<Extension> extensions;

  /// What reads the Academy aloud; one of its own, let go with the screen, unless given (a test's, which counts).
  final VoiceOver? voice;

  /// Simple's catalog, or Advanced's; the person's own mode ([Preferences.simple]) unless told.
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
  _Place _place = const _AtCatalog();
  String _typed = '';
  bool _hinting = false;
  Registry? _registry;
  ProjectSuite? _suite;

  /// Simple's More on the catalog, pressed: every shelf shown.
  bool _moreCourses = false;

  /// The shelf chosen by its chip; every shelf while null.
  CourseShelf? _shelf;

  /// The page's scroll: a new one for each place, so a course opened from a card far down the catalog opens at its
  /// top, and the catalog, gone back to, where it was left.
  ScrollController _scroll = ScrollController();
  int _page = 0;
  double _catalogAt = 0;

  late final VoiceOver _voice = widget.voice ?? VoiceOver();

  /// The course whose hello has been said since the catalog was left: begun again from the catalog, it says hello
  /// again; Next from one of its lessons to the next does not.
  String? _greeted;

  @override
  void initState() {
    super.initState();
    // Drawn again when a plugin is switched, so its course opens and its lessons come and go with its marks.
    _registry = plugins..addListener(_switched);
    _suite = projectSuite..addListener(_switched);
    preferences.addListener(_switched);
    _voice.addListener(_switched);
    WidgetsBinding.instance.addObserver(this);
    // Read once for the app (voice.dart), so a course begun can say its hello before its first lesson.
    unawaited(academyVoiceLengths());
    // The welcome, once, as the Academy opens on its catalog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _place is _AtCatalog) _voice.say([(asset: academyVoiceAsset('welcome'), length: null)]);
    });
  }

  @override
  void dispose() {
    _registry?.removeListener(_switched);
    _suite?.removeListener(_switched);
    preferences.removeListener(_switched);
    _voice.removeListener(_switched);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
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
  /// course's hello where the course is being begun. The catalog, a course's page and its end are quiet.
  void _go(_Place place) {
    final was = _place;
    final same = was is _AtLesson && place is _AtLesson && was.id == place.id;
    if (!same) {
      if (was is _AtCatalog && _scroll.hasClients) _catalogAt = _scroll.offset;
      final old = _scroll;
      _scroll = ScrollController(initialScrollOffset: place is _AtCatalog ? _catalogAt : 0);
      _page += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    setState(() {
      _place = place;
      if (!same) {
        _typed = '';
        _hinting = false;
      }
    });
    if (same) return;
    if (place is _AtLesson) {
      final lesson = lessonById(place.id);
      if (lesson == null) return;
      final course = courseOf(lesson);
      final hello = course.hello;
      final length = hello == null ? null : academyVoiceLengthsRead[hello];
      final greet = _greeted != course.id && hello != null && length != null;
      _greeted = course.id;
      _voice.say([
        if (greet) (asset: academyVoiceAsset(hello), length: length),
        // A lesson past the web page's has no clip yet (voice.dart): said as nothing rather than as a missing file.
        if (academyVoice.containsKey(lesson.id)) (asset: academyVoiceAsset(lesson.id), length: null),
      ]);
    } else {
      if (place is _AtCatalog) _greeted = null;
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
    final all = courseLessonsNow(_skipStandard);
    // A lesson no longer on offer (its plugin switched off while it was open) is its course's page.
    var place = _place;
    if (place is _AtLesson) {
      final id = place.id;
      if (!all.any((one) => one.id == id)) {
        final gone = lessonById(id);
        place = gone == null ? const _AtCatalog() : _AtCourse(courseOf(gone).id);
      }
    }
    final lesson = place is _AtLesson ? lessonById(place.id) : null;
    final Course? course;
    if (lesson != null) {
      course = courseOf(lesson);
    } else if (place is _AtCourse) {
      course = courseById(place.course);
    } else if (place is _AtCourseEnd) {
      course = courseById(place.course);
    } else {
      course = null;
    }
    final passed = lesson != null && lesson.passes(_typed);
    final learned = all.where((one) => _done.contains(one.id)).length;
    final run = course == null ? const <Lesson>[] : course.among(all);
    final bars = place is _AtLesson || place is _AtCourseEnd ? run : const <Lesson>[];
    final atCatalog = place is _AtCatalog || course == null;
    final look = course?.look ?? academyLook;

    /// The lesson after this one in its course; after its last, the course's end page.
    void next(Lesson from) {
      final its = courseOf(from).among(all);
      final at = its.indexOf(from) + 1;
      _go(at < its.length ? _AtLesson(its[at].id) : _AtCourseEnd(courseOf(from).id));
    }

    /// A course, from its first lesson not learned yet, or its first if all are; its page where none is on offer.
    void startCourse(Course which) {
      final its = which.among(all);
      final first = its.where((one) => !_done.contains(one.id)).firstOrNull ?? its.firstOrNull;
      _go(first != null ? _AtLesson(first.id) : _AtCourse(which.id));
    }

    final Widget card;
    if (lesson != null && course != null) {
      card = _LessonCard(
        lesson: lesson,
        course: course,
        run: run,
        typed: _typed,
        onTyped: (text) => _setTyped(lesson, text),
        passed: passed,
        hinting: _hinting,
        onHint: () => setState(() => _hinting = true),
        onShowMe: () => _setTyped(lesson, lesson.example),
        onNext: () => next(lesson),
        extensions: widget.extensions,
      );
    } else if (place is _AtCourseEnd && course != null) {
      card = _CourseEnd(course: course, lessons: all, done: _done, onAgain: (id) => _go(_AtLesson(id)), onNextCourse: startCourse, onCatalog: () => _go(const _AtCatalog()));
    } else if (place is _AtCourse && course != null) {
      final shown = course;
      card = _CoursePage(course: shown, lessons: all, done: _done, skipStandard: _skipStandard, onLesson: (id) => _go(_AtLesson(id)), onStart: () => startCourse(shown), onTurnOn: () => turnOnAcademyTool(shown.tool!));
    } else {
      final simpleMode = widget.simple ?? preferences.value.simple;
      card = _Catalog(
        lessons: all,
        done: _done,
        skipStandard: _skipStandard,
        onSkipStandard: (skip) {
          setState(() => _skipStandard = skip);
          writeSkipStandard(skip);
        },
        onLesson: (id) => _go(_AtLesson(id)),
        onCourse: (id) => _go(_AtCourse(id)),
        onTurnOn: turnOnAcademyTool,
        onStartOver: () {
          setState(() => _done = <String>{});
          writeProgress(const <String>{});
          final first = all.firstOrNull;
          if (first != null) _go(_AtLesson(first.id));
        },
        onCheatSheet: widget.onCheatSheet,
        shelf: _shelf,
        onShelf: (shelf) => setState(() => _shelf = shelf),
        chips: !simpleMode,
        simple: simpleMode && !_moreCourses,
        onMore: () => setState(() => _moreCourses = true),
      );
    }

    final ink = t.color('app-ink');
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
    // Back goes up a level: a lesson and a course's end to the course, a course to the catalog, the catalog out.
    void back() {
      if (atCatalog) {
        widget.onDone();
      } else if (place is _AtCourse) {
        _go(const _AtCatalog());
      } else {
        _go(_AtCourse(course!.id));
      }
    }

    // `.top`. On the Mac the window's three buttons sit at the bar's start (Matt, 2026-11-02, a screenshot: "the
    // academy controls intercept the traffic light controls"): the back arrow and the heading begin after their room,
    // and the row says where its centre is so the buttons sit on it, as the recorder's and the guide's bars do
    // (lib/shell/desktop/mac_lights.dart).
    final lights = trafficLightsRoom(t);
    final top = Padding(
      key: const ValueKey('academy-top'),
      // `.back { margin-inline-start: calc(-1 * var(--glacier-space-2)) }`
      padding: EdgeInsets.only(left: gutterStart - t.space(2) + lights, right: gutterEnd, top: t.len('app-safe-top') + t.space(3)),
      child: _onLights(lights > 0, Row(
        children: [
          GlacierPressable(
            key: const ValueKey('academy-back'),
            onPressed: back,
            semanticLabel: atCatalog
                ? 'Close the Academy'
                : place is _AtCourse
                ? 'All courses'
                : 'The course’s lessons',
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
                  // The mortarboard in the colour of the course being taken, or the Academy's own on its catalog.
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
      )),
    );

    return OnBack(
      // Back goes up a level, and out of the Academy from its catalog.
      onBack: back,
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            key: ValueKey('academy-page:$_page'),
            controller: _scroll,
            child: ConstrainedBox(
              // `.screen { min-block-size: 100dvh }`
              constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? box.maxHeight : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  top,
                  // A bar for every lesson of the course: faint to come, its colour for learned, lit for the one being taken.
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
                    // `.card { max-inline-size: 42rem; margin-inline: auto }`; the catalog wider, for its grid.
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: t.lenOf(atCatalog ? '72rem' : '42rem')),
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

/// `.bar`: one lesson of the course being taken, in the course's colour ([hue]): the one in hand full, the learned
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

/// `.chapter`: where this is, in small spaced capitals, in the course's colour ([look]).
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
    required this.course,
    required this.run,
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
  final Course course;

  /// The lessons of its course on offer, for where it is among them.
  final List<Lesson> run;
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
    final look = course.look;
    final at = run.indexOf(lesson) + 1;
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
        LessonBand(look: look, symbol: lesson.symbol),
        _eyebrow(t, '${course.title} · $at of ${run.length}', look),
        _title(t, lesson.title),
        _teach(t, teachOf(lesson)),
        // `.example`: the line to look at, in the typewriter face, with a way to have it written for you.
        DecoratedBox(
          key: const ValueKey('academy-example'),
          // A wash of the course's colour, where the page's was the ink's.
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

/// What a shelf is, said under its name in the catalog.
String _shelfAbout(CourseShelf shelf) => switch (shelf) {
  CourseShelf.markdown => 'What any Markdown app reads the same way.',
  CourseShelf.ghost => 'What Ghost draws of its own, built in.',
  CourseShelf.plugins => 'A course for each plugin with something to type. One that is off can be turned on from its card.',
};

/// How much of [course] is learned, of what is on offer of it ([lessons]): its lessons there, those learned, whether
/// it is open (its plugin on), and whether every lesson of it is left out as standard Markdown.
({List<Lesson> its, int learned, bool open, bool skipped, int total}) _standing(Course course, List<Lesson> lessons, Set<String> done, bool skipStandard) {
  final open = courseOpen(course);
  final its = course.among(lessons);
  final skipped = skipStandard && course.all.every((lesson) => lesson.standard);
  // Off, a course counts what it would teach once on.
  final total = open ? its.length : course.all.where((lesson) => !(skipStandard && lesson.standard)).length;
  return (its: its, learned: its.where((lesson) => done.contains(lesson.id)).length, open: open, skipped: skipped, total: total);
}

/// `3 lessons · 6 min`.
String _lessonsWords(Course course, int total) => '$total ${total == 1 ? 'lesson' : 'lessons'} · ${course.minutesFor(total)} min';

/// The catalog, where the Academy opens (`Contents` on the page, which was a list of seven chapters): the course in
/// progress with its way on, the switch for a person who knows Markdown already, chips for the shelves, and each
/// shelf's courses as cards. Once everything is learned it is also the summary, with every course to take again.
class _Catalog extends StatelessWidget {
  const _Catalog({
    required this.lessons,
    required this.done,
    required this.skipStandard,
    required this.onSkipStandard,
    required this.onLesson,
    required this.onCourse,
    required this.onTurnOn,
    required this.onStartOver,
    required this.onCheatSheet,
    required this.shelf,
    required this.onShelf,
    this.chips = true,
    this.simple = false,
    this.onMore,
  });

  final List<Lesson> lessons;
  final Set<String> done;
  final bool skipStandard;
  final ValueChanged<bool> onSkipStandard;
  final ValueChanged<String> onLesson;
  final ValueChanged<String> onCourse;
  final ValueChanged<String> onTurnOn;
  final VoidCallback onStartOver;
  final VoidCallback onCheatSheet;

  /// The shelf its chip chose; every shelf while null.
  final CourseShelf? shelf;
  final ValueChanged<CourseShelf?> onShelf;

  /// Whether the shelves have chips: not in Simple.
  final bool chips;

  /// Simple's catalog, More not yet pressed: the Markdown shelf, and a row for the rest.
  final bool simple;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final left = lessons.where((lesson) => !done.contains(lesson.id)).firstOrNull;
    final begun = lessons.any((lesson) => done.contains(lesson.id));
    final sm = t.fontSize('sm');
    final shelves = simple ? const [CourseShelf.markdown] : (chips && shelf != null ? [shelf!] : CourseShelf.values);
    final hidden = simple ? courses.where((course) => course.shelf != CourseShelf.markdown).length : 0;
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
              ? 'Courses of short lessons, a mark at a time: what it does, an example, and a line of your own to write, drawn as the note draws it while you type.'
              : 'Every mark a note can carry is one you can now write by hand. The Markdown ones read the same in any app that knows Markdown, and Ghost’s own read as plain words there. Take any course again below.',
        ),
        if (left != null) _ContinueCard(course: courseOf(left), next: left, lessons: lessons, done: done, begun: begun, onGo: () => onLesson(left.id)),
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
        if (chips) _ShelfChips(shelf: shelf, onShelf: onShelf),
        Semantics(
          label: 'Courses',
          container: true,
          explicitChildNodes: true,
          child: Column(
            key: const ValueKey('academy-courses'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: t.space(6),
            children: [
              for (final each in shelves)
                Column(
                  key: ValueKey('shelf-courses:${each.name}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(3),
                  children: [
                    Semantics(
                      header: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 2,
                        children: [
                          Text(each.label, style: t.textAt(t.fontSize('lg'), weight: 'semibold', color: ink)),
                          Text(_shelfAbout(each), style: t.textAt(sm, color: quiet)),
                        ],
                      ),
                    ),
                    _CourseGrid(
                      children: [
                        for (final course in courses.where((one) => one.shelf == each))
                          _CourseCard(course: course, lessons: lessons, done: done, skipStandard: skipStandard, onOpen: () => onCourse(course.id), onTurnOn: () => onTurnOn(course.tool!)),
                      ],
                    ),
                  ],
                ),
              if (hidden > 0) _moreRow(context, hidden),
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

  /// Simple's More: the shelves still to come, opened where they are (GHST-103).
  Widget _moreRow(BuildContext context, int more) {
    final t = context.tokens;
    final quiet = t.color('app-ink-3');
    return GlacierPressable(
      key: const ValueKey('academy-more-courses'),
      onPressed: onMore,
      semanticLabel: 'More courses',
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
              // The Academy's own wash, for the courses still behind it.
              const CourseTile(look: academyLook, learned: false, icon: Lucide.layoutGrid),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text('More', style: _buttonText(t, _buttonSize, weight: 'semibold', color: t.color('app-ink'))),
                    Text('$more more courses on what only Ghost draws: smart lines, queries, and one for each plugin, Gantt charts among them.', style: _buttonText(t, t.fontSize('sm'), color: quiet, height: t.len('glacier-leading-md'))),
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

/// The course in progress, at the top of the catalog: its colour and sign, its name, the lesson next, its bar, and
/// the way on, Resume (Start before anything of it is learned, and Up next once the course before it is done).
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.course, required this.next, required this.lessons, required this.done, required this.begun, required this.onGo});

  final Course course;
  final Lesson next;
  final List<Lesson> lessons;
  final Set<String> done;
  final bool begun;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = course.look;
    final its = course.among(lessons);
    final learned = its.where((lesson) => done.contains(lesson.id)).length;
    final xs = t.fontSize('xs');
    return Container(
      key: const ValueKey('academy-continue'),
      padding: EdgeInsets.all(t.space(4)),
      decoration: BoxDecoration(color: look.wash(t, light: 0.07, dark: 0.14), border: Border.all(color: look.ink(t).withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(t.radius('lg'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(3),
        children: [
          Row(
            spacing: t.space(3),
            children: [
              ExcludeSemantics(child: CourseTile(look: look, learned: false, size: 48)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text((learned > 0 ? 'Continue learning' : begun ? 'Up next' : 'Start here').toUpperCase(), style: t.textAt(xs, weight: 'semibold', color: look.ink(t), tracking: t.len('app-tracking-caps', em: xs))),
                    Text(course.title, key: const ValueKey('academy-continue-course'), style: t.textAt(t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink'))),
                    Text('Next: ${next.title}', key: const ValueKey('academy-continue-next'), style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
                  ],
                ),
              ),
            ],
          ),
          Row(
            spacing: t.space(3),
            children: [
              Expanded(child: _Progress(of: its.isEmpty ? 0 : learned / its.length, hue: look.ink(t))),
              Text('$learned of ${its.length}', style: _tabular(t.textAt(xs, weight: 'semibold', color: look.ink(t)))),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(key: const ValueKey('academy-go'), onPressed: onGo, label: learned > 0 ? 'Resume' : 'Start', after: Lucide.arrowRight, colours: look.colours),
          ),
        ],
      ),
    );
  }
}

/// The shelves' chips across the catalog: All, then each shelf with how many courses it has; the one chosen inked.
class _ShelfChips extends StatelessWidget {
  const _ShelfChips({required this.shelf, required this.onShelf});
  final CourseShelf? shelf;
  final ValueChanged<CourseShelf?> onShelf;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget chip(CourseShelf? which, String label) {
      final on = which == shelf;
      return GlacierPressable(
        key: ValueKey('shelf:${which?.name ?? 'all'}'),
        onPressed: () => onShelf(which),
        semanticLabel: label,
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('full'),
          child: Semantics(
            selected: on,
            child: Container(
              height: t.space(10),
              padding: EdgeInsets.symmetric(horizontal: t.space(4)),
              decoration: BoxDecoration(
                color: on ? t.color('app-ink') : (state.hovered || state.pressed ? t.color('app-ink').withValues(alpha: 0.06) : null),
                border: Border.all(color: on ? t.color('app-ink') : t.color('app-rule')),
                borderRadius: BorderRadius.circular(t.radius('full')),
              ),
              child: Center(widthFactor: 1, child: Text(label, style: t.textAt(t.fontSize('sm'), weight: 'medium', color: on ? t.color('app-paper') : t.color('app-ink-2')))),
            ),
          ),
        ),
      );
    }

    // One line, scrolling sideways where a narrow phone has no room for all four.
    return SingleChildScrollView(
      key: const ValueKey('academy-shelves'),
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: t.space(2),
        children: [
          chip(null, 'All'),
          for (final each in CourseShelf.values) chip(each, '${each.label} · ${courses.where((course) => course.shelf == each).length}'),
        ],
      ),
    );
  }
}

/// Cards in rows: one across on a phone, two on the opened Fold and a tablet, three on a wide window; each row as tall
/// as its tallest card.
class _CourseGrid extends StatelessWidget {
  const _CourseGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gap = context.tokens.space(3);
    return LayoutBuilder(
      builder: (context, box) {
        final across = box.maxWidth >= 900
            ? 3
            : box.maxWidth >= 540
            ? 2
            : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            for (var at = 0; at < children.length; at += across)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    for (var n = at; n < at + across; n += 1) Expanded(child: n < children.length ? children[n] : const SizedBox.shrink()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A course on its shelf: a band of its colour with its sign, its name and what it is about, its level, lessons and
/// minutes, and its bar, a tick once it is learned. A course whose plugin is off says so, with the chip to turn it
/// on under it; one of standard Markdown alone, for a person who knows it, is skipped.
class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.lessons, required this.done, required this.skipStandard, required this.onOpen, required this.onTurnOn});

  final Course course;
  final List<Lesson> lessons;
  final Set<String> done;
  final bool skipStandard;
  final VoidCallback onOpen;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = course.look;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final standing = _standing(course, lessons, done, skipStandard);
    final complete = standing.open && standing.its.isNotEmpty && standing.learned == standing.its.length;
    final tool = course.tool;
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final label = [
      course.title,
      course.level.label,
      _lessonsWords(course, standing.total).replaceAll(' · ', ', ').replaceAll(' min', ' minutes'),
      if (!standing.open && tool != null) 'needs ${academyToolName(tool)}',
      if (standing.skipped) 'skipped',
      if (complete) 'completed' else if (standing.open && !standing.skipped) '${standing.learned} of ${standing.total} learned',
    ].join(', ');
    final Widget foot;
    if (standing.skipped) {
      foot = Text('Skipped', key: ValueKey('course-count:${course.id}'), style: t.textAt(xs, weight: 'semibold', color: quiet));
    } else if (complete) {
      foot = Row(
        key: ValueKey('course-count:${course.id}'),
        spacing: t.space(2),
        children: [
          AppIcon(Lucide.circleCheck, size: 16, strokeWidth: 2.4, color: look.ink(t)),
          Text('Completed', style: t.textAt(xs, weight: 'semibold', color: look.ink(t))),
        ],
      );
    } else if (standing.open) {
      foot = Row(
        spacing: t.space(3),
        children: [
          Expanded(child: _Progress(of: standing.total == 0 ? 0 : standing.learned / standing.total, hue: look.ink(t))),
          Text('${standing.learned}/${standing.total}', key: ValueKey('course-count:${course.id}'), style: _tabular(t.textAt(xs, weight: 'semibold', color: look.ink(t)))),
        ],
      );
    } else {
      foot = Row(
        key: ValueKey('course-count:${course.id}'),
        spacing: t.space(2),
        children: [
          AppIcon(academyToolIcon(tool!), size: 14, color: quiet),
          Flexible(child: Text('Needs ${academyToolName(tool)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(xs, weight: 'semibold', color: quiet))),
        ],
      );
    }
    final body = GlacierPressable(
      key: ValueKey('course:${course.id}'),
      onPressed: standing.skipped ? null : onOpen,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('lg'),
        child: Opacity(
          opacity: standing.skipped ? 0.45 : 1,
          child: _Named(
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(color: !standing.skipped && (state.hovered || state.pressed) ? look.wash(t, light: 0.08, dark: 0.16) : null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CourseStrip(look: look, complete: complete),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(t.space(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: t.space(2),
                      children: [
                        Text(course.title, key: ValueKey('course-title:${course.id}'), style: t.textAt(t.fontSize('md'), weight: 'semibold', color: ink)),
                        Text(course.about, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textAt(sm, color: quiet, height: t.len('glacier-leading-md'))),
                        Wrap(
                          spacing: t.space(2),
                          runSpacing: t.space(1),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Tag(words: course.level.label, hue: look.ink(t)),
                            Text(_lessonsWords(course, standing.total), style: t.textAt(xs, color: quiet)),
                          ],
                        ),
                        const Spacer(),
                        foot,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: t.color('glacier-bg'), border: Border.all(color: t.color('app-rule')), borderRadius: BorderRadius.circular(t.radius('lg'))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          // The app's own chip, as a fence of a plugin that is off has under it (docs/PM_PLUGINS.md §5).
          if (!standing.open && tool != null)
            Padding(
              padding: EdgeInsets.only(left: t.space(4), right: t.space(4), bottom: t.space(4)),
              child: KeyedSubtree(key: ValueKey('course-turn-on:${course.id}'), child: ToolChip(tools: [tool], onPress: onTurnOn)),
            ),
        ],
      ),
    );
  }
}

/// The band across the top of a course's card: its wash, its sign on a tile of glass, a few of its icons faint at the
/// far end, and a tick there once it is learned.
class _CourseStrip extends StatelessWidget {
  const _CourseStrip({required this.look, required this.complete});
  final ChapterLook look;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colours = look.colours;
    const white = Color(0xFFFFFFFF);
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: t.space(4)),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colours.length > 1 ? colours : [colours.first, colours.first])),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x59FFFFFF), width: 1.5)),
            child: AppIcon(look.icon, size: 24, strokeWidth: 2.2, color: white),
          ),
          const Spacer(),
          if (complete)
            const AppIcon(Lucide.circleCheck, size: 22, strokeWidth: 2.4, color: white)
          else
            for (final (index, icon) in look.tiles.take(3).indexed) Padding(padding: EdgeInsets.only(left: index == 0 ? 0 : t.space(2)), child: AppIcon(icon, size: 16, strokeWidth: 2, color: white.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

/// A small tag of words in a hue: a course's level.
class _Tag extends StatelessWidget {
  const _Tag({required this.words, required this.hue});
  final String words;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
      decoration: BoxDecoration(color: hue.withValues(alpha: t.isDark ? 0.18 : 0.1), borderRadius: BorderRadius.circular(t.radius('full'))),
      child: Text(words, style: t.textAt(t.fontSize('xs'), weight: 'semibold', color: hue)),
    );
  }
}

/// A bar of how much is learned, [of] from 0 to 1, in [hue] on a faint wash of it.
class _Progress extends StatelessWidget {
  const _Progress({required this.of, required this.hue});
  final double of;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: Container(
        height: 6,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: hue.withValues(alpha: t.isDark ? 0.22 : 0.14), borderRadius: BorderRadius.circular(t.radius('full'))),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: of.clamp(0, 1).toDouble(),
          child: DecoratedBox(decoration: BoxDecoration(color: hue, borderRadius: BorderRadius.circular(t.radius('full')))),
        ),
      ),
    );
  }
}

/// A row for one lesson of a course (`.again` on the page's chapter end): a tick once it is learned, its name, and
/// its mark; pressed, the lesson. Dimmed, and pressing nothing, where it is not on offer, with why at its end.
Widget _lessonRow(BuildContext context, Lesson lesson, {required ChapterLook look, required bool learned, required VoidCallback? onPressed, String? why}) {
  final t = context.tokens;
  final ink = t.color('app-ink');
  return GlacierPressable(
    key: ValueKey('again:${lesson.id}'),
    onPressed: onPressed,
    semanticLabel: [lesson.title, if (learned) 'learned', ?why].join(', '),
    builder: (context, state) => GlacierFocusRing(
      visible: state.focused,
      radius: t.radius('md'),
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: _Named(
          constraints: BoxConstraints(minHeight: t.space(10)),
          // A button's own `padding-block: 1px`, which the rule leaves as it is.
          padding: EdgeInsets.symmetric(vertical: 1, horizontal: t.space(3)),
          decoration: BoxDecoration(color: onPressed != null && (state.hovered || state.pressed) ? ink.withValues(alpha: 0.06) : null, borderRadius: BorderRadius.circular(t.radius('md'))),
          child: Row(
            spacing: t.space(3),
            children: [
              // `.againTick { inline-size: 1.4em; block-size: 1.4em }`, of the button's own size.
              Container(
                key: ValueKey('again-tick:${lesson.id}'),
                width: 1.4 * _buttonSize,
                height: 1.4 * _buttonSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: learned ? look.colours.first : look.wash(t, light: 0.14, dark: 0.24), shape: BoxShape.circle),
                child: learned ? const AppIcon(Lucide.check, size: 14, strokeWidth: 2.6, color: Color(0xFFFFFFFF)) : null,
              ),
              Expanded(child: Text(lesson.title, key: ValueKey('again-name:${lesson.id}'), style: _buttonText(t, _buttonSize, color: ink))),
              // `.againMark { max-inline-size: 45%; overflow: hidden; white-space: nowrap; text-overflow: ellipsis }`
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 0.45 * (MediaQuery.sizeOf(context).width - t.len('app-gutter-start') - t.len('app-gutter-end') - 2 * t.space(3))),
                child: Text(
                  why ?? lesson.symbol,
                  key: ValueKey('again-mark:${lesson.id}'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: why != null ? t.textAt(t.fontSize('xs'), color: t.color('app-ink-3')) : t.textAt(t.fontSize('xs'), mono: true, color: t.color('app-ink-3')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A course's page: its band, what it is, how far through it is, the way in (or the chip that turns its plugin on),
/// and every lesson of it with its tick.
class _CoursePage extends StatelessWidget {
  const _CoursePage({required this.course, required this.lessons, required this.done, required this.skipStandard, required this.onLesson, required this.onStart, required this.onTurnOn});

  final Course course;
  final List<Lesson> lessons;
  final Set<String> done;
  final bool skipStandard;
  final ValueChanged<String> onLesson;
  final VoidCallback onStart;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = course.look;
    final standing = _standing(course, lessons, done, skipStandard);
    final complete = standing.open && standing.its.isNotEmpty && standing.learned == standing.its.length;
    final tool = course.tool;
    final sm = t.fontSize('sm');
    return _Card(
      children: [
        CourseBand(look: look),
        _eyebrow(t, '${course.shelf.label} · ${course.level.label}', look),
        _title(t, course.title),
        _teach(t, course.about),
        Text(
          [_lessonsWords(course, standing.total), if (standing.open && standing.learned > 0) '${standing.learned} learned'].join(' · '),
          key: const ValueKey('academy-course-meta'),
          style: t.textAt(sm, color: t.color('app-ink-3')),
        ),
        if (standing.open && standing.its.isNotEmpty) ...[
          _Progress(of: standing.learned / standing.its.length, hue: look.ink(t)),
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(
              key: const ValueKey('academy-course-start'),
              onPressed: onStart,
              label: complete
                  ? 'Take it again'
                  : standing.learned > 0
                  ? 'Resume'
                  : 'Start',
              after: Lucide.arrowRight,
              colours: look.colours,
            ),
          ),
        ],
        if (!standing.open && tool != null)
          Container(
            key: const ValueKey('academy-needs'),
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(color: look.wash(t), borderRadius: BorderRadius.circular(t.radius('md'))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(3),
              children: [
                _lined(
                  t,
                  'This course is taught with the ${academyToolName(tool)} plugin, which is off. Turn it on to take the course; its lessons are below.',
                  sm,
                  t.len('glacier-leading-md'),
                  t.textAt(sm, color: t.color('app-ink-2'), height: t.len('glacier-leading-md')),
                ),
                KeyedSubtree(key: const ValueKey('academy-turn-on'), child: ToolChip(tools: [tool], onPress: onTurnOn)),
              ],
            ),
          ),
        // `.list { gap: 1px }`
        Column(
          key: const ValueKey('academy-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 1,
          children: [
            for (final lesson in course.all)
              _lessonRow(
                context,
                lesson,
                look: look,
                learned: done.contains(lesson.id),
                onPressed: standing.its.contains(lesson) ? () => onLesson(lesson.id) : null,
                why: standing.its.contains(lesson)
                    ? null
                    : !standing.open
                    ? 'Off'
                    : skipStandard && lesson.standard
                    ? 'Skipped'
                    : 'Its mark is off',
              ),
          ],
        ),
      ],
    );
  }
}

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

/// The end of a course: what it taught, any lesson to take again, and the course after it (`ChapterEnd` on the page).
class _CourseEnd extends StatelessWidget {
  const _CourseEnd({required this.course, required this.lessons, required this.done, required this.onAgain, required this.onNextCourse, required this.onCatalog});

  final Course course;
  final List<Lesson> lessons;
  final Set<String> done;
  final ValueChanged<String> onAgain;
  final ValueChanged<Course> onNextCourse;
  final VoidCallback onCatalog;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = course.look;
    final its = course.among(lessons);
    final all = its.every((lesson) => done.contains(lesson.id));
    // The next course with something on offer, in the catalog's order.
    final following = courses.skip(courses.indexOf(course) + 1).where((one) => one.among(lessons).isNotEmpty).firstOrNull;
    return _Card(
      children: [
        // The course seen off in its colour: the ghost ticking every box once all of it is learned.
        CourseEndBand(look: look, learned: all),
        _eyebrow(t, course.title, look),
        _title(t, all ? 'Course learned.' : 'The end of the course.'),
        _teach(t, all ? 'Every mark in ${course.title} is one you can write by hand now.' : 'You can come back to the ones you skipped whenever you like: tap one to take it.'),
        // `.list { gap: 1px }`
        Column(
          key: const ValueKey('academy-list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 1,
          children: [
            for (final lesson in its) _lessonRow(context, lesson, look: look, learned: done.contains(lesson.id), onPressed: () => onAgain(lesson.id)),
          ],
        ),
        _Foot(
          start: _Word(key: const ValueKey('academy-all-courses'), onPressed: onCatalog, label: 'All courses'),
          end: following != null
              // Onward in the next course's colour.
              ? _Pill(key: const ValueKey('academy-next-course'), onPressed: () => onNextCourse(following), label: 'Next: ${following.title}', after: Lucide.arrowRight, colours: following.look.colours)
              : _Pill(key: const ValueKey('academy-next-course'), onPressed: onCatalog, label: 'Done', colours: look.colours),
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

/// The bar on the Mac's window buttons, where the page is drawn under the title bar.
Widget _onLights(bool mac, Widget row) => mac ? MacLightsRow(child: row) : row;
