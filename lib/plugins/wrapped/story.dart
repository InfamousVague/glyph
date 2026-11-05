/// The Wrapped story (docs/WRAPPED.md, "The story"; Matt, 2026-11-05: "a "ghost markdown wrapped" kinda like spotify
/// wrapped"): a full-screen run of cards, a big number or phrase on each in a bold colour, swiped or tapped through,
/// the ghost where it fits. Its cards ([storyCards]): the year in notes, words written, the busiest month, day and
/// hour, the longest streak, the themes, the most-connected notes, the to-dos, meetings and recordings, the one you
/// forgot, and a summary that can be shared as a picture.
///
/// Motion is a card's words rising into place as it comes, and nothing at all where the device asks for less
/// (`MediaQuery.disableAnimations`). The summary's picture holds the numbers alone unless the person ticks Include my
/// themes: no title or word of a note is in it otherwise.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/metrics.dart' show MetricEvent, countBucket, track;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../files/phone_documents.dart' show PhoneDocuments;
import '../../home/home_text.dart' show pageText;
import 'actions.dart' show WrappedActionKind;
import 'service.dart';
import 'stats.dart';

/// A card's two colours: its ground and its ink.
typedef StoryHue = ({Color ground, Color ink});

const List<StoryHue> storyHues = [
  (ground: Color(0xFF4B2BD6), ink: Color(0xFFFFFFFF)),
  (ground: Color(0xFFFF5A4E), ink: Color(0xFF1A0B0A)),
  (ground: Color(0xFFC6F432), ink: Color(0xFF0F1A00)),
  (ground: Color(0xFF2BA8F4), ink: Color(0xFF00121F)),
  (ground: Color(0xFFFF4FB0), ink: Color(0xFF22000F)),
  (ground: Color(0xFFFFB020), ink: Color(0xFF1F1200)),
  (ground: Color(0xFF2BD69C), ink: Color(0xFF00170E)),
];

/// The summary's ground: the page's ink, so it reads as the app's own.
const StoryHue summaryHue = (ground: Color(0xFF111111), ink: Color(0xFFFFFFFF));

/// One card of the story.
@immutable
class StoryCard {
  const StoryCard({required this.id, required this.kicker, required this.big, this.line = '', this.list = const [], this.ghost, this.noteId});

  /// Its key: `notes`, `words`, `busiest`…
  final String id;

  /// The words over the big one: "In 2026 you wrote".
  final String kicker;

  /// The big number or phrase: "312 notes".
  final String big;
  final String line;

  /// A short list under it: the themes, the notes most linked to.
  final List<String> list;
  final GhostScene? ghost;

  /// The note it is about, for Open: the one you forgot.
  final String? noteId;
}

String _n(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i += 1) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _plural(int n, String one, [String? many]) => '${_n(n)} ${n == 1 ? one : (many ?? '${one}s')}';

/// The cards for [stats], with [themes], the note [forgotten] (its [gist]) and [now]; a card with nothing to say is
/// left out. The summary is always last.
List<StoryCard> storyCards(WrappedStats stats, {required DateTime now, List<String> themes = const [], Note? forgotten, String gist = ''}) {
  final when = stats.period.wordsFor(now);
  final inWhen = stats.period == WrappedPeriod.all ? 'In all your time here' : 'In $when';
  final cards = <StoryCard>[
    StoryCard(id: 'hello', kicker: 'Ghost.md Wrapped', big: 'Your $when in notes', line: stats.isEmpty ? 'Nothing written yet. Next year’s will be fuller.' : 'Swipe to see it.', ghost: GhostScene.welcome),
    StoryCard(id: 'notes', kicker: '$inWhen you wrote', big: _plural(stats.notes, 'note'), line: stats.edited > stats.notes ? 'and came back to edit ${_plural(stats.edited, 'note')}' : ''),
    if (stats.words > 0) StoryCard(id: 'words', kicker: 'That’s', big: _plural(stats.words, 'word'), line: stats.words >= 50000 ? 'About a novel’s worth.' : (stats.words >= 10000 ? 'A long short story’s worth.' : '')),
    if (stats.busiestMonth != null)
      StoryCard(
        id: 'busiest',
        kicker: 'You wrote the most in',
        big: stats.busiestMonthWords,
        line: [
          if (stats.busiestDay != null) 'mostly on ${stats.busiestDayWords}',
          if (stats.busiestHour != null) 'around ${stats.busiestHourWords}',
        ].join(', '),
      ),
    if (stats.longestStreak > 1) StoryCard(id: 'streak', kicker: 'Your longest streak', big: _plural(stats.longestStreak, 'day'), line: 'in a row with a note written or edited', ghost: GhostScene.listening),
    if (themes.isNotEmpty) StoryCard(id: 'themes', kicker: 'You kept coming back to', big: themes.first, list: themes.skip(1).take(4).toList()),
    if (stats.mostLinked.isNotEmpty) StoryCard(id: 'linked', kicker: 'Your most connected note', big: stats.mostLinked.first.title.trim().isEmpty ? 'Untitled' : stats.mostLinked.first.title.trim(), line: '${_plural(stats.mostLinked.first.links, 'note')} link to it', list: [for (final l in stats.mostLinked.skip(1).take(3)) l.title]),
    if (stats.todosDone + stats.todosOpen > 0)
      StoryCard(id: 'todos', kicker: 'To-dos', big: '${_n(stats.todosDone)} done', line: stats.todosOpen == 0 ? 'and none left open.' : 'and ${_n(stats.todosOpen)} still open. They’re waiting after the story.', ghost: stats.todosOpen == 0 ? GhostScene.allTicked : null),
    if (stats.meetings + stats.recordings > 0)
      StoryCard(id: 'spoken', kicker: 'You talked it out', big: stats.meetings > 0 ? _plural(stats.meetings, 'meeting') : _plural(stats.recordings, 'recording'), line: stats.meetings > 0 && stats.recordings > 0 ? 'and ${_plural(stats.recordings, 'recording')}' : ''),
    if (forgotten != null)
      StoryCard(
        id: 'forgot',
        kicker: 'The one you forgot',
        big: noteTitle(forgotten.body).trim().isEmpty ? 'Untitled' : noteTitle(forgotten.body).trim(),
        line: [if (gist.isNotEmpty) gist, 'Last opened ${_ago(now, forgotten.updatedAt)}.'].join(' · '),
        noteId: forgotten.id,
        ghost: GhostScene.searchNothing,
      ),
    StoryCard(id: 'summary', kicker: 'Ghost.md Wrapped · $when', big: _plural(stats.notes, 'note'), list: [if (stats.words > 0) _plural(stats.words, 'word'), if (stats.longestStreak > 1) '${_n(stats.longestStreak)}-day streak', if (stats.busiestMonth != null) 'Busiest in ${stats.busiestMonthWords}']),
  ];
  return cards;
}

String _ago(DateTime now, int ms) {
  final days = now.difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays;
  if (days < 60) return '$days days ago';
  if (days < 730) return '${(days / 30).round()} months ago';
  return '${(days / 365).round()} years ago';
}

/// Hands a picture's file to the device's share sheet: [path], called [name].
typedef SharePicture = Future<void> Function(String path, String name);

Future<void> _shareByDevice(String path, String name) => PhoneDocuments().share(path, name: name);

/// Opens the story over everything, for [service]'s period. [onReview] is the last card's Review, [onOpenNote] the
/// one you forgot's Open.
Future<void> openWrappedStory(BuildContext context, WrappedService service, {VoidCallback? onReview, void Function(String noteId)? onOpenNote, SharePicture? share}) {
  service.seen();
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      pageBuilder: (route, _, _) => WrappedStory(
        service: service,
        share: share,
        onClose: () => Navigator.of(route).maybePop(),
        onReview: onReview == null
            ? null
            : () {
                Navigator.of(route).maybePop();
                onReview();
              },
        onOpenNote: onOpenNote == null
            ? null
            : (id) {
                Navigator.of(route).maybePop();
                onOpenNote(id);
              },
      ),
    ),
  );
}

/// The story itself (see the library doc).
class WrappedStory extends StatefulWidget {
  const WrappedStory({super.key, required this.service, required this.onClose, this.onReview, this.onOpenNote, this.share});

  final WrappedService service;
  final VoidCallback onClose;
  final VoidCallback? onReview;
  final void Function(String noteId)? onOpenNote;

  /// The device's share sheet unless a test brings its own.
  final SharePicture? share;

  @override
  State<WrappedStory> createState() => _WrappedStoryState();
}

class _WrappedStoryState extends State<WrappedStory> {
  final PageController _pages = PageController();
  final GlobalKey _summary = GlobalKey();
  int _at = 0;
  bool _withThemes = false;
  String? _said;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int by, int count) {
    final next = (_at + by).clamp(0, count - 1);
    if (next == _at) {
      if (by > 0) widget.onClose();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(next);
    } else {
      unawaited(_pages.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic));
    }
  }

  Future<void> _sharePicture() async {
    try {
      final boundary = _summary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;
      final name = 'Ghost.md Wrapped ${widget.service.state.period.wordsFor(DateTime.now())}.png';
      final file = File('${Directory.systemTemp.path}/ghost-wrapped-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await (widget.share ?? _shareByDevice)(file.path, name);
      track(MetricEvent.wrappedAction, {'kind': WrappedActionKind.share.wire, 'count': countBucket(1)});
    } catch (failure) {
      if (mounted) setState(() => _said = 'The picture couldn’t be shared here: $failure');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final stats = service.stats();
    final forgotten = service.forgotten.firstOrNull;
    final themes = service.themes(stats);
    final cards = storyCards(stats, now: DateTime.now(), themes: themes, forgotten: forgotten, gist: forgotten == null ? '' : service.gistOf(forgotten.id));
    final t = context.tokens;
    final still = MediaQuery.disableAnimationsOf(context);
    final hue = cards[_at].id == 'summary' ? summaryHue : storyHues[_at % storyHues.length];
    return Semantics(
      label: 'Your Wrapped',
      explicitChildNodes: true,
      child: ColoredBox(
        key: const ValueKey('wrapped-story'),
        color: hue.ground,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (context, i) {
                  final card = cards[i];
                  final colours = card.id == 'summary' ? summaryHue : storyHues[i % storyHues.length];
                  final body = _CardBody(card: card, hue: colours, still: still, shown: i == _at, withThemes: _withThemes, themes: themes);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (tap) => _go(tap.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? -1 : 1, cards.length),
                    child: ColoredBox(
                      key: ValueKey('wrapped-card-${card.id}'),
                      color: colours.ground,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(t.space(6), t.space(12), t.space(6), t.space(4)),
                        child: card.id == 'summary'
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: RepaintBoundary(key: _summary, child: ColoredBox(color: colours.ground, child: body))),
                                  _SummaryDo(
                                    hue: colours,
                                    withThemes: _withThemes,
                                    canTheme: themes.isNotEmpty,
                                    onTheme: (on) => setState(() => _withThemes = on),
                                    onShare: () => unawaited(_sharePicture()),
                                    onReview: widget.onReview,
                                    said: _said,
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: body),
                                  if (card.noteId != null && widget.onOpenNote != null)
                                    Align(alignment: AlignmentDirectional.centerStart, child: WrappedPill(key: const ValueKey('wrapped-open-forgotten'), label: 'Open it', hue: colours, onPressed: () => widget.onOpenNote!(card.noteId!))),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
              // The bars along the top, one a card, and the cross.
              Positioned(
                left: t.space(4),
                right: t.space(4),
                top: t.space(3),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        spacing: 4,
                        children: [
                          for (var i = 0; i < cards.length; i += 1)
                            Expanded(child: Container(height: 3, decoration: BoxDecoration(color: hue.ink.withValues(alpha: i <= _at ? 0.9 : 0.3), borderRadius: BorderRadius.circular(2)))),
                        ],
                      ),
                    ),
                    SizedBox(width: t.space(3)),
                    GlacierPressable(
                      key: const ValueKey('wrapped-story-close'),
                      onPressed: widget.onClose,
                      semanticLabel: 'Close',
                      builder: (context, state) => SizedBox.square(dimension: t.space(10), child: Center(child: AppIcon(Lucide.x, size: 20, strokeWidth: 2.2, color: hue.ink))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card's words, rising into place as it comes (and still where the device asks).
class _CardBody extends StatelessWidget {
  const _CardBody({required this.card, required this.hue, required this.still, required this.shown, required this.withThemes, required this.themes});

  final StoryCard card;
  final StoryHue hue;
  final bool still;
  final bool shown;
  final bool withThemes;
  final List<String> themes;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final summary = card.id == 'summary';
    final list = summary && withThemes ? [...card.list, if (themes.isNotEmpty) 'Into ${themes.take(3).join(', ')}'] : card.list;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(card.kicker, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: hue.ink.withValues(alpha: 0.85))),
        SizedBox(height: t.space(3)),
        Text(card.big, maxLines: 3, overflow: TextOverflow.ellipsis, style: pageText(t, card.big.length > 18 ? 40 : 56, weight: 'bold', color: hue.ink, height: 1.05, tracking: -1)),
        if (card.line.isNotEmpty) ...[SizedBox(height: t.space(3)), Text(card.line, style: pageText(t, t.fontSize('lg'), color: hue.ink.withValues(alpha: 0.9)))],
        if (list.isNotEmpty) ...[
          SizedBox(height: t.space(4)),
          for (final item in list)
            Padding(padding: EdgeInsets.only(bottom: t.space(1)), child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium', color: hue.ink))),
        ],
        if (summary) ...[SizedBox(height: t.space(6)), GhostMark(size: 40, ink: hue.ink, paper: hue.ground)],
      ],
    );
    final ghost = card.ghost;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: words),
        if (ghost != null) SizedBox(height: 120, child: Ghost(scene: ghost, size: GhostSize.small, align: GhostAlign.center, color: hue.ink.withValues(alpha: 0.8), maxWidth: 140)),
      ],
    );
    if (still) return body;
    return AnimatedSlide(
      offset: shown ? Offset.zero : const Offset(0, 0.06),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: const Duration(milliseconds: 320), child: body),
    );
  }
}

/// The summary's foot: Include my themes, Share as a picture, and Review.
class _SummaryDo extends StatelessWidget {
  const _SummaryDo({required this.hue, required this.withThemes, required this.canTheme, required this.onTheme, required this.onShare, this.onReview, this.said});

  final StoryHue hue;
  final bool withThemes;
  final bool canTheme;
  final ValueChanged<bool> onTheme;
  final VoidCallback onShare;
  final VoidCallback? onReview;
  final String? said;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space(3),
      children: [
        if (canTheme)
          GlacierPressable(
            key: const ValueKey('wrapped-share-themes'),
            onPressed: () => onTheme(!withThemes),
            semanticLabel: 'Include my themes in the picture',
            builder: (context, state) => Row(
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                AppIcon(withThemes ? Lucide.squareCheckBig : Lucide.square, size: 18, color: hue.ink),
                Text('Include my themes in the picture', style: pageText(t, t.fontSize('sm'), color: hue.ink)),
              ],
            ),
          ),
        if (said != null) Text(said!, style: pageText(t, t.fontSize('sm'), color: hue.ink.withValues(alpha: 0.8))),
        Row(
          spacing: t.space(2),
          children: [
            Flexible(child: WrappedPill(key: const ValueKey('wrapped-share'), label: 'Share', icon: Lucide.share2, hue: hue, onPressed: onShare)),
            if (onReview != null) Flexible(child: WrappedPill(key: const ValueKey('wrapped-review'), label: 'Review what to tidy', hue: (ground: hue.ink, ink: hue.ground), onPressed: onReview!, filled: true)),
          ],
        ),
      ],
    );
  }
}

/// A pill of a button in a card's own colours.
class WrappedPill extends StatelessWidget {
  const WrappedPill({super.key, required this.label, required this.hue, required this.onPressed, this.icon, this.filled = false});

  final String label;

  /// Drawn in its ground, solid: the one to press.
  final bool filled;
  final StoryHue hue;
  final VoidCallback onPressed;
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Transform.scale(
        scale: state.pressed ? 0.96 : 1,
        child: GlacierFocusRing(
          visible: state.focused,
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(10)),
            padding: EdgeInsets.symmetric(horizontal: t.space(4)),
            decoration: BoxDecoration(color: filled ? hue.ground : hue.ink.withValues(alpha: state.hovered ? 0.18 : 0.12), border: filled ? null : Border.all(color: hue.ink.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(t.radius('full'))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: t.space(2),
              children: [
                if (icon != null) AppIcon(icon!, size: 16, color: hue.ink),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: hue.ink))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
