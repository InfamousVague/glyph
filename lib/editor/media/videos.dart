/// A film in the words, drawn (lib/core/video_refs.dart): its card under a line that is only a poster linked to a
/// film, and the line folded to its words, "video 0:12", away from the caret. Ports `src/app/editor/videos.ts` and
/// `src/app/editor/videos.module.css`.
///
///     [![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)
///
/// The line keeps its Markdown, as a picture's and a place's do, and the card is a block widget under it. The card
/// is the poster, the film's own frame, so it has the film's shape, with the length in a chip at its foot. Where
/// the film can play, a paper disc sits in the middle and a Full screen chip in the corner. It never plays by
/// itself.
///
/// Who is reading decides what else is said, read once:
///
/// - `play`, the note screen: the device is asked whether the film is on this phone before the disc is drawn. Not
///   here, "This video isn’t on this phone." takes the disc's place, before anyone taps; a binary older than the
///   films says to update; any device but an Android phone says the film stays on the phone it was added on.
/// - `still`, everywhere else the owner reads: the poster and its length, and the same words for another device or
///   an older binary, and nothing asked.
/// - `shared`, a shared page: "Only a still from it is shared.", since the reader never had the film.
///
/// The picture widget steps aside for these lines (images.dart), so the poster is drawn once. A film's line in
/// fenced code is the code's words, with no card and no fold.
///
/// What differs:
/// - THE FILM IS THE PHONE'S PLAYER'S. The page plays the film in a `<video>` over the poster; there is no
///   WebView here, so the card asks [FilmSeams.films] to open it ([FilmPlaying], lib/core/films.dart: on a phone
///   a texture the phone's own player draws into) and lays its frames over the poster, the same shape, with the
///   line of ink along the foot as it plays, the disc gone while it does (`data-playing`) and the press reading
///   "Pause". A film that would not open, or fails as it plays, is asked about again and its card says which:
///   gone, or not playable here (`gone`).
/// - FULL SCREEN IS THE SAME FILM, where the page made a second element at the first one's time and handed the
///   time back: the layer ([_FilmLayer], in the app's topmost overlay, black in both themes with its close in
///   white) draws the card's own film, plays it, and pauses it as it closes, so the card is where the layer left
///   it with nothing to hand back. The back gesture closes it (lib/core/back.dart).
/// - Where the film stands (core/videos.ts `filmHere`, `filmsPlay`: a HEAD to the app's own scheme, the native
///   generation) is the device's, and is asked through [FilmSeams.filmHere] and [FilmSeams.filmsPlay], or through
///   [FilmSeams.films] where those are left out. Without any a card says nothing and draws no disc: the poster
///   and its length. No binary is older than the films here, so `update` is said only by a caller's own seam.
/// - `justAdded`'s scroll (keeping the caret under a card just added in sight as its poster arrives) is kept:
///   [filmAdded] and the poster's `onSize`.
/// - The stylesheet's rules are cited where each is drawn.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/svg_path.dart';
import '../../core/back.dart';
import '../../core/films.dart';
import '../../core/video_refs.dart';
import '../editor.dart';
import '../view/blocks.dart' show ClassedBlockWidget;
import '../view/drawn_block.dart';
import '../view/line_facts.dart';
import '../view/lines.dart';
import 'images.dart';
import 'inline_box.dart';

/// Who is reading (`'play' | 'still' | 'shared'`).
enum VideoMode { play, still, shared }

/// Where a film on this phone stands, for its card: playable, not here, on a binary too old, or elsewhere
/// entirely (core/videos.ts `FilmHere`).
enum FilmHere { here, missing, update, elsewhere }

/// Where films play at all: on an Android phone that has them, on an older binary, or on another device
/// (core/videos.ts `filmsPlay`: `'phone' | 'update' | 'elsewhere'`).
enum FilmsPlay { phone, update, elsewhere }

/// What a card knows of its film: where it stands, `shared` on a shared page, `unplayable` for a film here that
/// would not play, and `quiet` while nothing needs saying (the film is here to play, or the question is still
/// out).
enum CardState { missing, update, elsewhere, shared, unplayable, quiet }

/// The words under a card, for whoever reads it; none while all is well.
String videoWords(VideoMode mode, CardState state, int? ms) {
  final length = ms == null ? '' : ' of ${lengthText(ms)}';
  if (mode == VideoMode.shared || state == CardState.shared) return 'A video$length. Only a still from it is shared.';
  if (state == CardState.missing) return 'This video isn’t on this phone.';
  if (state == CardState.unplayable) return 'This video can’t be played on this phone.';
  if (state == CardState.update) return 'Update Ghost.md to play this video.';
  if (state == CardState.elsewhere) return 'A video$length. It stays on the phone it was added on.';
  return '';
}

/// How tall a poster is for its width, learned as each is drawn: a card drawn again is laid out at its own shape.
final Map<String, double> _shapes = <String, double>{};

/// A film just picked says its shape before its poster has loaded.
void rememberShape(String poster, double width, double height) {
  if (width > 0 && height > 0) _shapes[poster] = height / width;
}

/// Posters of films just added, whose card keeps the caret under it in sight once, as the poster arrives.
final Set<String> _justAdded = <String>{};

/// A film just added: its shape, and that its card's first poster keeps the caret in sight.
void filmAdded(String poster, double width, double height) {
  rememberShape(poster, width, height);
  _justAdded.add(poster);
}

/// What the cards are told by whoever makes the editor: the device and its player.
class FilmSeams {
  const FilmSeams({this.films, this.filmHere, this.filmsPlay, this.failed});

  /// This device's films (lib/core/films.dart): where each stands, and what plays one. Absent, nothing plays.
  final Films? films;

  /// Where the film named stands on this device (`filmHere`); [films]' own answer where it is left out.
  final Future<FilmHere> Function(String video)? filmHere;

  /// Where films play at all (`filmsPlay`); [films]' own answer where it is left out.
  final Future<FilmsPlay> Function()? filmsPlay;

  /// `filmHere`, by the seam given or by the device.
  Future<FilmHere> Function(String video)? get whereIs {
    if (filmHere != null) return filmHere;
    final films = this.films;
    if (films == null) return null;
    return (video) async => !films.device.plays ? FilmHere.elsewhere : (await films.isHere(video) ? FilmHere.here : FilmHere.missing);
  }

  /// `filmsPlay`, by the seam given or by the device.
  Future<FilmsPlay> Function()? get wherePlay {
    if (filmsPlay != null) return filmsPlay;
    final films = this.films;
    if (films == null) return null;
    return () async => films.device.plays ? FilmsPlay.phone : FilmsPlay.elsewhere;
  }

  /// Films that would not play after all, by name, and what their cards now say (`missing` or `unplayable`): the
  /// player says so here, and the cards listen.
  final ValueListenable<Map<String, CardState>>? failed;
}

final Facet<FilmSeams, FilmSeams> _seams = Facet.define<FilmSeams, FilmSeams>(combine: (values) => values.isEmpty ? const FilmSeams() : values.first);

/// Lucide's marks, in the app's strokes: play, maximise and close.
const List<String> _playMark = <String>['M6 3 20 12 6 21z'];
const List<String> _fullMark = <String>['M15 3h6v6', 'M9 21H3v-6', 'M21 3l-7 7', 'M3 21l7-7'];
const List<String> _closeMark = <String>['M18 6 6 18', 'm6 6 12 12'];

/// How far a film has played, as the line along the foot (`follow`): `.progress`, scaled from the left.
class _Progress extends StatelessWidget {
  const _Progress({required this.film, required this.ink});

  final FilmPlaying film;
  final Color ink;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: film.position,
          builder: (context, ms, _) {
            final done = film.durationMs > 0 ? (ms / film.durationMs).clamp(0.0, 1.0) : 0.0;
            // '.progress': { block-size: 2px; background: var(--app-ink); transform-origin: left; transform: scaleX(…) }
            return SizedBox(height: 2, child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: done, child: ColoredBox(color: ink)));
          },
        ),
      );
}

/// The film full screen (`openFullScreen`): a layer over the whole app, black, the film contained in it, a tap to
/// pause or play, and a white close. '.layer': { --film-ground: oklch(0 0 0); --film-mark: oklch(1 0 0);
/// position: fixed; inset: 0; display: grid; place-items: center; background: var(--film-ground);
/// animation: layerIn var(--glacier-duration-fast) var(--glacier-ease-out) }
class _FilmLayer extends StatelessWidget {
  const _FilmLayer({required this.film, required this.label, required this.onClose});

  final FilmPlaying film;
  final String label;
  final VoidCallback onClose;

  static const Color _ground = Color(0xFF000000);
  static const Color _mark = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final space3 = t.space(3);
    final layer = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: label,
      child: ColoredBox(
        color: _ground,
        child: Stack(
          children: <Widget>[
            // '.layer .film': { position: static; max-inline-size: 100%; max-block-size: 100% }
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('layer-film'),
                behavior: HitTestBehavior.opaque,
                onTap: () => film.playing.value ? film.pause() : film.play(),
                child: Center(child: film.surface()),
              ),
            ),
            // '.close': { position: absolute; inset-block-start: calc(var(--app-inset-top, 0px) +
            //   var(--glacier-space-3)); inset-inline-end: calc(var(--app-safe-right, 0px) + var(--glacier-space-3));
            //   inline-size: 2.75rem; block-size: 2.75rem; color: var(--film-mark) }
            PositionedDirectional(
              top: t.lenOf('var(--app-inset-top, 0px)') + space3,
              end: t.lenOf('var(--app-safe-right, 0px)') + space3,
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  key: const ValueKey<String>('layer-close'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox.square(
                    dimension: t.lenOf('2.75rem'),
                    child: Center(child: CustomPaint(size: Size.square(t.lenOf('1.5rem')), painter: const _MarkPainter(_closeMark, _mark, filled: false))),
                  ),
                ),
              ),
            ),
            // '.layer .progress': { display: block; inset-block-end: var(--app-safe-bottom, 0px);
            //   background: var(--film-mark) }
            Positioned(left: 0, right: 0, bottom: t.lenOf('var(--app-safe-bottom, 0px)'), child: _Progress(film: film, ink: _mark)),
          ],
        ),
      ),
    );
    if (t.reducedMotion) return layer;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: t.duration('glacier-duration-fast'),
      curve: t.curve('glacier-ease-out'),
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
      child: layer,
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.paths, this.ink, {required this.filled});

  final List<String> paths;
  final Color ink;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    for (final d in paths) {
      if (filled) canvas.drawPath(svgPath(d), Paint()..color = ink);
      canvas.drawPath(svgPath(d), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink || old.filled != filled || !identical(old.paths, paths);
}

/// The card under a film's line.
class VideoWidget extends EditorWidget implements ClassedBlockWidget, DrawnBlock {
  const VideoWidget(this.film, this.mode);

  final VideoLine film;
  final VideoMode mode;

  @override
  String get className => 'cm-videoCard';

  @override
  bool eq(VideoWidget other) => other.film.poster == film.poster && other.film.video == film.video && other.film.ms == film.ms && other.mode == mode;

  /// The poster's own height at the page's width where it is known, and a wide film's where it is not, and the
  /// words.
  @override
  double get estimatedHeight {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return 240;
    const rem = 16.0;
    final window = views.first.physicalSize / views.first.devicePixelRatio;
    final shape = _shapes[film.poster] ?? 9 / 16;
    return math.min(window.height * 0.6, (window.width - 3 * rem) * shape) + 3 * rem;
  }

  @override
  Widget build(BuildContext context) => _VideoCard(film: film, mode: mode, view: EditorViewScope.maybeOf(context));
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({required this.film, required this.mode, required this.view});

  final VideoLine film;
  final VideoMode mode;
  final EditorViewLike? view;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  CardState _state = CardState.quiet;

  /// The film is here to play: the disc and Full screen are drawn.
  bool _plays = false;
  FilmSeams _seamsNow = const FilmSeams();

  @override
  void initState() {
    super.initState();
    _seamsNow = widget.view?.state.facet(_seams) ?? const FilmSeams();
    _seamsNow.failed?.addListener(_onFailed);
    _ask();
  }

  /// Another film, another reader or another editor in this card's place: it is asked about afresh.
  @override
  void didUpdateWidget(_VideoCard old) {
    super.didUpdateWidget(old);
    if (old.film.video == widget.film.video && old.mode == widget.mode && identical(old.view, widget.view)) return;
    _seamsNow.failed?.removeListener(_onFailed);
    _seamsNow = widget.view?.state.facet(_seams) ?? const FilmSeams();
    _seamsNow.failed?.addListener(_onFailed);
    _plays = false;
    _asked += 1;
    _shut?.call();
    _letGo();
    _started = false;
    _ask();
  }

  @override
  void dispose() {
    _seamsNow.failed?.removeListener(_onFailed);
    _leaving = true;
    _shut?.call();
    _letGo();
    super.dispose();
  }

  // ---- the film, played ----------------------------------------------------------------------------------------

  /// The card's film, once it has been asked for (`filmNow`), and the one being opened.
  FilmPlaying? _film;
  Future<FilmPlaying?>? _opening;

  /// It has played at all: its frames are over the poster and its line is along the foot (`data-started`).
  bool _started = false;

  /// Closes the full screen layer while it is up.
  VoidCallback? _shut;

  /// The card is going: what its film says from here on is nobody's.
  bool _leaving = false;

  void _filmSaid() {
    final film = _film;
    if (film == null || !mounted || _leaving) return;
    if (film.failed.value) return _gone();
    setState(() {
      if (film.playing.value) _started = true;
    });
  }

  /// The card's film let go: paused, and the phone's player with it (`letGo`).
  void _letGo() {
    final film = _film;
    _film = null;
    _opening = null;
    if (film == null) return;
    film.playing.removeListener(_filmSaid);
    film.failed.removeListener(_filmSaid);
    film.close();
  }

  /// The film would not play: asked again whether it is on the phone at all, and the card says which, gone or not
  /// playable here, and plays nothing (`gone`).
  void _gone() {
    final video = widget.film.video;
    final asking = _asked;
    _shut?.call();
    _letGo();
    if (mounted) setState(() => _started = false);
    final films = _seamsNow.films;
    unawaited(
      (films?.stillHere(video) ?? Future<bool>.value(true)).then((here) {
        if (asking == _asked) _say(here ? CardState.unplayable : CardState.missing);
      }),
    );
  }

  /// The card's film, opened the first time it is wanted (`filmNow`); null where it would not open.
  Future<FilmPlaying?> _filmNow() {
    final had = _film;
    if (had != null) return Future<FilmPlaying?>.value(had);
    return _opening ??= () async {
      final films = _seamsNow.films;
      if (films == null) return null;
      final asking = _asked;
      final FilmPlaying made;
      try {
        made = await films.device.open(widget.film.video);
      } catch (_) {
        if (mounted && asking == _asked) _gone();
        return null;
      }
      // Another film in this card's place meanwhile, or the card gone: this one is nobody's.
      if (!mounted || asking != _asked) {
        made.close();
        return null;
      }
      made.playing.addListener(_filmSaid);
      made.failed.addListener(_filmSaid);
      _opening = null;
      setState(() => _film = made);
      return made;
    }();
  }

  /// The frame pressed: the film played, or paused.
  Future<void> _toggle() async {
    final film = await _filmNow();
    if (film == null || !mounted) return;
    film.playing.value ? film.pause() : film.play();
  }

  /// Full screen pressed: the card's own film in a layer over the app, played, until it is closed.
  Future<void> _fullScreen() async {
    if (_shut != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final film = await _filmNow();
    if (film == null || !mounted || overlay == null || _shut != null) return;
    final length = widget.film.ms == null ? '' : lengthText(widget.film.ms!);
    late final OverlayEntry entry;
    VoidCallback? off;
    void shut() {
      if (_shut == null) return;
      _shut = null;
      off?.call();
      film.pause();
      entry.remove();
      entry.dispose();
    }

    entry = OverlayEntry(builder: (context) => _FilmLayer(film: film, label: length.isNotEmpty ? 'The video, $length, full screen' : 'The video, full screen', onClose: shut));
    _shut = shut;
    off = BackScope.of(context).onBack(() {
      shut();
      return true;
    });
    overlay.insert(entry);
    setState(() => _started = true);
    film.play();
  }

  /// Which asking an answer belongs to: one that comes back for a film the card no longer draws is dropped.
  int _asked = 0;

  void _say(CardState state, {bool plays = false}) {
    if (!mounted) return;
    setState(() {
      _state = state;
      _plays = plays;
    });
  }

  void _ask() {
    final seams = _seamsNow;
    if (widget.mode != VideoMode.play) {
      // Nothing is asked of a still or a shared page but which device this is.
      _state = widget.mode == VideoMode.shared ? CardState.shared : CardState.quiet;
      if (widget.mode == VideoMode.still && seams.wherePlay != null) {
        final asking = _asked;
        unawaited(
          seams.wherePlay!().then((where) {
            if (asking == _asked && where != FilmsPlay.phone) _say(where == FilmsPlay.update ? CardState.update : CardState.elsewhere);
          }),
        );
      }
      return;
    }
    _state = CardState.quiet;
    if (seams.whereIs == null) return;
    final asking = _asked;
    unawaited(
      seams.whereIs!(widget.film.video).then((where) {
        if (asking != _asked) return;
        switch (where) {
          case FilmHere.here:
            _say(CardState.quiet, plays: true);
          case FilmHere.missing:
            _say(CardState.missing);
          case FilmHere.update:
            _say(CardState.update);
          case FilmHere.elsewhere:
            _say(CardState.elsewhere);
        }
      }),
    );
  }

  /// The film would not play: the card says which, gone or not playable here, and plays nothing.
  void _onFailed() {
    final said = _seamsNow.failed?.value[widget.film.video];
    if (said == null || said == _state) return;
    _shut?.call();
    _letGo();
    _started = false;
    _say(said);
  }

  /// The poster arrives a moment after the card is laid out, and the card grows to its size then. A film just
  /// added leaves the caret on the line under its card, which the growing card would push out of sight: kept in
  /// sight here, while the note has the focus. Once, for the film just added.
  void _learn(Size natural) {
    final poster = widget.film.poster;
    rememberShape(poster, natural.width, natural.height);
    if (!_justAdded.remove(poster)) return;
    final view = widget.view;
    if (view == null || !view.hasFocus || !mounted) return;
    final head = view.state.selection.main.head;
    final doc = view.state.doc;
    // The card stands under its film's line: the caret is to be on the line after that one.
    final above = doc.lineAt(head).number - 1;
    if (above < 1) return;
    final film = videoOfLine(doc.line(above).text);
    if (film == null || film.poster != poster) return;
    view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(head, y: ScrollStrategy.nearest, yMargin: 56)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final film = widget.film;
    final length = film.ms == null ? '' : lengthText(film.ms!);
    final gutter = gutterOf(context);
    final space1 = t.space(1), space2 = t.space(2);
    final paper85 = t.colorOf('color-mix(in srgb, var(--app-paper) 85%, transparent)');
    final ink = t.color('app-ink');
    final words = videoWords(widget.mode, _state, film.ms);
    final xs = t.fontSize('xs');
    final base = t.textAt(xs, color: t.color('app-ink-2'));
    final film$ = _film;
    final playing = film$?.playing.value ?? false;
    final label = playing ? 'Pause' : (length.isNotEmpty ? 'Play the video, $length' : 'Play the video');

    // '.frame': { position: relative; isolation: isolate; display: inline-block; max-inline-size: 100%;
    //   vertical-align: top; border-radius: var(--glacier-radius-md); overflow: hidden;
    //   background: var(--app-paper-2) }
    final frame = ClipRRect(
      key: const ValueKey<String>('frame'),
      borderRadius: BorderRadius.circular(t.radius('md')),
      child: ColoredBox(
        color: t.color('app-paper-2'),
        child: Stack(
          children: <Widget>[
            // '.poster': { display: block; max-inline-size: 100%; max-block-size: 60vh; min-block-size: 3rem;
            //   min-inline-size: 6rem }
            KeptPicture(
              key: const ValueKey<String>('poster'),
              name: film.poster,
              store: pictureStoreOf(context),
              label: length.isNotEmpty ? 'A video of $length' : 'A video',
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              minWidth: t.lenOf('6rem'),
              minHeight: t.lenOf('3rem'),
              waiting: SizedBox(width: t.lenOf('6rem'), height: t.lenOf('3rem')),
              onSize: _learn,
            ),
            // '.film': { position: absolute; z-index: 0; inset: 0; inline-size: 100%; block-size: 100%;
            //   object-fit: contain }
            if (film$ != null && _started) Positioned.fill(key: const ValueKey<String>('film'), child: film$.surface()),
            // '.toggle': { position: absolute; inset: 0; display: grid; place-items: center; color: var(--app-ink) }
            // '.disc': { display: grid; place-items: center; inline-size: 3.25rem; block-size: 3.25rem;
            //   border-radius: var(--glacier-radius-full); background: color-mix(in srgb, var(--app-paper) 85%,
            //   transparent); color: var(--app-ink); transition: opacity var(--glacier-duration-fast)
            //   var(--glacier-ease-out) }   '.disc svg': { margin-inline-start: 3px }
            //   '.card[data-playing] .disc': { opacity: 0 }
            if (_plays)
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_toggle()),
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: playing ? 0 : 1,
                        duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
                        curve: t.curve('glacier-ease-out'),
                        child: DecoratedBox(
                        key: const ValueKey<String>('disc'),
                        decoration: ShapeDecoration(color: paper85, shape: const CircleBorder()),
                        child: SizedBox.square(
                          dimension: t.lenOf('3.25rem'),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(start: 3),
                              child: CustomPaint(size: Size.square(t.lenOf('1.35rem')), painter: _MarkPainter(_playMark, ink, filled: true)),
                            ),
                          ),
                        ),
                      ),
                      ),
                    ),
                  ),
                ),
              ),
            // '.chip': { position: absolute; inset-block-end: var(--glacier-space-2);
            //   padding: 0 var(--glacier-space-2); border-radius: var(--glacier-radius-full);
            //   background: color-mix(in srgb, var(--app-paper) 85%, transparent); color: var(--app-ink-2);
            //   font-size: var(--glacier-font-size-xs); font-variant-numeric: tabular-nums; line-height: 1.6;
            //   pointer-events: none }   '.length': { inset-inline-start: var(--glacier-space-2) }
            if (length.isNotEmpty)
              PositionedDirectional(
                start: space2,
                bottom: space2,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      key: const ValueKey<String>('length'),
                      decoration: ShapeDecoration(color: paper85, shape: const StadiumBorder()),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: space2),
                        child: InlineWords(length, style: base.copyWith(fontFeatures: <FontFeature>[...?base.fontFeatures, const FontFeature.tabularFigures()]), lineHeight: xs * 1.6),
                      ),
                    ),
                  ),
                ),
              ),
            // '.full': { position: absolute; inset-block-end: var(--glacier-space-1);
            //   inset-inline-end: var(--glacier-space-1); display: grid; place-items: center; inline-size: 2.25rem;
            //   block-size: 2.25rem; border-radius: var(--glacier-radius-full);
            //   background: color-mix(in srgb, var(--app-paper) 85%, transparent); color: var(--app-ink) }
            if (_plays)
              PositionedDirectional(
                end: space1,
                bottom: space1,
                child: Semantics(
                  button: true,
                  label: 'Full screen',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(_fullScreen()),
                    child: DecoratedBox(
                      key: const ValueKey<String>('full'),
                      decoration: ShapeDecoration(color: paper85, shape: const CircleBorder()),
                      child: SizedBox.square(
                        dimension: t.lenOf('2.25rem'),
                        child: Center(
                          child: CustomPaint(size: Size.square(t.lenOf('1.05rem')), painter: _MarkPainter(_fullMark, ink, filled: false)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // '.progress': { position: absolute; inset-inline: 0; inset-block-end: 0 }
            //   '.card:not([data-started]) .progress': { display: none }
            if (film$ != null && _started) Positioned(key: const ValueKey<String>('progress'), left: 0, right: 0, bottom: 0, child: _Progress(film: film$, ink: ink)),
          ],
        ),
      ),
    );

    // '.card': { margin: var(--glacier-space-2) 0 var(--glacier-space-3); padding: 0 calc(var(--app-safe-right,
    //   0px) + var(--app-gutter)) 0 calc(var(--app-safe-left, 0px) + var(--app-gutter));
    //   font-family: var(--glacier-font-sans, system-ui); line-height: 1.5 }
    final sm = t.fontSize('sm');
    return Padding(
      padding: EdgeInsets.only(top: space2, bottom: t.space(3)),
      child: Padding(
        key: const ValueKey<String>('cm-videoCard'),
        padding: EdgeInsets.only(left: t.lenOf('var(--app-safe-left, 0px)') + gutter, right: t.lenOf('var(--app-safe-right, 0px)') + gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(alignment: AlignmentDirectional.topStart, child: frame),
            // '.words': { margin: var(--glacier-space-1) 0 0; color: var(--app-ink-3);
            //   font-size: var(--glacier-font-size-sm) }   '.words:empty': { display: none }
            if (words.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: space1),
                child: InlineWords(words, key: const ValueKey<String>('words'), style: t.textAt(sm, color: t.color('app-ink-3')), lineHeight: sm * 1.5, maxLines: 12),
              ),
          ],
        ),
      ),
    );
  }
}

DecorationSet _cardsOf(EditorState state, VideoMode mode) {
  final builder = RangeSetBuilder<Decoration>();
  // The lines that are films are the tree's own keeping: a keystroke reads the lines it changed, not the note.
  final films = filmFacts.of(state.doc);
  if (films.isEmpty) return builder.finish();
  final fences = DocFences.of(state.doc);
  for (final line in films) {
    if (!fences.covers(line.number)) builder.add(line.to, line.to, Decoration.widget(widget: VideoWidget(line.fact, mode), block: true, side: 1));
  }
  return builder.finish();
}

/// A block widget's height has to be known before layout, so the cards come from a field, as pictures do.
final Map<VideoMode, StateField<DecorationSet>> _cardFields = <VideoMode, StateField<DecorationSet>>{
  for (final mode in VideoMode.values)
    mode: StateField.define<DecorationSet>(
      create: (state) => _cardsOf(state, mode),
      update: (value, tr) => tr.docChanged ? _cardsOf(tr.state, mode) : value,
      provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
    ),
};

final RegExp _line = RegExp(r'\[!\[([^\]\n]*)\]\(image\/[^)\s]*\)\]\(video\/[^)\s]*\)');

/// The `[![` and the `](image/…)](video/…)` of a video line, as ranges of the document: the alt is what reads.
List<({int from, int to})> _foldsOf(int from, String text) {
  final found = _line.firstMatch(text);
  if (found == null) return const <({int from, int to})>[];
  final open = from + found.start;
  final close = open + 3 + (found.group(1)?.length ?? 0);
  return <({int from, int to})>[(from: open, to: open + 3), (from: close, to: open + found.group(0)!.length)];
}

final Decoration _hidden = Decoration.replace();

DecorationSet _foldAll(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  final state = view.state;
  final editable = state.facet(EditorViewLike.editable);
  // The lines the selection touches show their films whole, while the note is being written (links.dart).
  final active = editable && view.hasFocus ? selectedLines(state) : const <int>{};
  final doc = state.doc;
  final fences = DocFences.of(doc);
  for (final range in view.visibleRanges) {
    // The films among the lines on screen, from what the tree keeps of them.
    for (final line in filmFacts.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      if (active.contains(line.number) || fences.covers(line.number)) continue;
      for (final fold in _foldsOf(line.from, line.text)) {
        builder.add(fold.from, fold.to, _hidden);
      }
    }
  }
  return builder.finish();
}

/// The video lines folded to their words off the caret, looked at again whenever what they show may have moved.
class _Folds extends PluginValue {
  _Folds(EditorViewLike view) : decorations = _foldAll(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    // While an IME composes, a line must not be replaced (glyph_lines.dart).
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) decorations = _foldAll(update.view);
  }
}

final ViewPlugin<_Folds> _folds = ViewPlugin.define<_Folds>(_Folds.new, decorations: (plugin) => plugin.decorations);

/// Films in the words: a card under each line as `mode` says, and the lines folded to their words. Read once.
/// `seams` is the device and the player; the posters are drawn from the editor's `pictureStore` (images.dart).
Extension videoCards(VideoMode mode, {FilmSeams seams = const FilmSeams()}) => Extension.list(<Extension>[_seams.of(seams), _cardFields[mode]!, _folds]);
