/// The card a rich embed's line gets in place of the plain link card (link_cards.dart): the service's picture,
/// the title and who made it, a play or open disc, and "Open in …".
///
/// - A YouTube video is a 16:9 still with a disc; a tap plays it in the card, in YouTube's own player, from the
///   link's start time, with Full screen in the corner while it plays (the same player moved into a layer over the
///   app, playing on).
/// - A Spotify track, album, playlist, episode or show is its artwork beside its title; a tap puts Spotify's player
///   in the card's place, compact for one song or episode and taller for the rest.
/// - A Figma file is its picture; a tap opens Figma's interactive embed full screen in a layer over the app, as a
///   diagram's Full screen does (lib/editor/diagrams/full_screen.dart): a close in its corner, Escape, and the
///   phone's back.
///
/// NOTHING PLAYS OR LOADS BEFORE A TAP: the player is made by the tap, and before it the card has asked only for
/// the oEmbed and the picture, and those only with Link previews on and Local only off ([EmbedSource.allowed]).
/// With either shut the card is the plain one, saying the service's name and the link, and a tap opens the link in
/// the service's app or the browser instead: no player in the app, which would ask the service from inside it.
/// Where no player can be made here ([EmbedPlayers.available]: a desktop without a web view), a tap opens the link
/// too. A service that would not answer for the link (a private video, a file not shared) leaves the plain card.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../../art/app_icon.dart';
import '../../../art/lucide.g.dart';
import '../../../core/back.dart';
import '../../../core/link_preview.dart';
import '../../looks/look.dart';
import '../../view/editor_view.dart';
import '../../view/plugin.dart' show EditorViewScope;
import '../images.dart' show gutterOf;
import '../inline_box.dart';
import 'oembed.dart';
import 'players.dart';
import 'providers.dart';

/// What a card is showing: the quiet plain card (the switches shut), the service's answer still out, the answer,
/// the player, or the plain card because the service did not answer.
enum EmbedCardPhase { quiet, loading, preview, playing, failed }

/// The plain link card, drawn by link_cards.dart: with `fixed` it says that instead of asking for the page.
typedef PlainCard = Widget Function(String url, LinkPreview? fixed);

/// The card under a rich embed's line.
class RichEmbedCard extends StatefulWidget {
  const RichEmbedCard({super.key, required this.link, required this.words, required this.allowed, required this.embeds, required this.players, required this.plain, this.open});

  final RichLink link;

  /// The link's own words, for `[words](address)`.
  final String? words;

  /// Link previews on and Local only off, as the card was drawn.
  final bool allowed;
  final EmbedSource embeds;
  final EmbedPlayers players;
  final PlainCard plain;

  /// Hands an address to the phone: "Open in …", and a tap where nothing may play.
  final LinkOpener? open;

  @override
  State<RichEmbedCard> createState() => RichEmbedCardState();
}

class RichEmbedCardState extends State<RichEmbedCard> {
  /// The card's player, made by a tap and let go when the card goes or another link takes its place.
  EmbedPlayback? _playback;

  /// The video is in the full-screen layer: the card holds its place.
  bool _full = false;

  /// Closes the layer while it is up.
  VoidCallback? _shut;

  /// The player's place, moved between the card and the layer without making it again.
  final GlobalKey _slot = GlobalKey(debugLabel: 'embed player');

  /// The card is letting its player go itself: the layer closing says nothing back to it.
  bool _stopping = false;

  Uint8List? _picture;
  String? _pictureAsked;
  bool _pressed = false;

  /// What the card is showing now.
  EmbedCardPhase get phase {
    if (!_mayAsk) return EmbedCardPhase.quiet;
    if (_playback != null) return EmbedCardPhase.playing;
    if (widget.embeds.failedFor(widget.link)) return EmbedCardPhase.failed;
    return widget.embeds.embedFor(widget.link) == null ? EmbedCardPhase.loading : EmbedCardPhase.preview;
  }

  bool get _mayAsk => widget.allowed && widget.embeds.allowed;

  @override
  void initState() {
    super.initState();
    widget.embeds.addListener(_heard);
    _ask();
  }

  @override
  void didUpdateWidget(RichEmbedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.embeds, widget.embeds)) {
      old.embeds.removeListener(_heard);
      widget.embeds.addListener(_heard);
    }
    // Another link in the card's place, or the switches shut: what plays stops.
    if (old.link != widget.link || !_mayAsk) _stop();
    if (old.link != widget.link) {
      _picture = null;
      _pictureAsked = null;
    }
    _ask();
  }

  @override
  void dispose() {
    widget.embeds.removeListener(_heard);
    _stop();
    super.dispose();
  }

  void _ask() {
    if (!_mayAsk) return;
    widget.embeds.wantEmbed(widget.link);
    _wantPicture();
  }

  void _heard() {
    if (!mounted) return;
    _wantPicture();
    setState(() {});
  }

  /// The service's picture: its oEmbed's, or a YouTube video's own still before that has come.
  void _wantPicture() {
    if (!_mayAsk) return;
    final address = widget.embeds.embedFor(widget.link)?.thumbnail ?? widget.link.stillGuess;
    if (address == null || address == _pictureAsked) return;
    _pictureAsked = address;
    unawaited(
      widget.embeds.picture(address).then((bytes) {
        if (!mounted || address != _pictureAsked || bytes == null) return;
        setState(() => _picture = bytes);
      }),
    );
  }

  void _openOutside() {
    final open = widget.open;
    if (open != null) unawaited(open(widget.link.openUrl).catchError((Object _) {}));
  }

  String get _title {
    final said = widget.embeds.embedFor(widget.link)?.title;
    if (said != null && said.isNotEmpty) return said;
    return widget.words ?? '${widget.link.serviceName} ${widget.link.kindName.toLowerCase()}';
  }

  EmbedPage _page(Color ground) => EmbedPage(player: widget.link.player, title: _title, ground: ground);

  /// The disc pressed: played in the card, or opened over the app; the link opened instead where nothing may play.
  void _play() {
    if (!_mayAsk || !widget.players.available) return _openOutside();
    if (!widget.link.playsInline) return _openLayer();
    if (_playback != null) return;
    final ground = widget.link.service == EmbedService.youtube ? const Color(0xFF000000) : context.tokens.color('app-paper-2');
    setState(() => _playback = widget.players.open(_page(ground), open: widget.open));
  }

  void _stop() {
    _stopping = true;
    _shut?.call();
    _stopping = false;
    _playback?.dispose();
    _playback = null;
    _full = false;
  }

  /// A layer over the app: the card's own video, moved there playing, or a Figma file's interactive embed.
  void _openLayer() {
    if (_shut != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final inline = widget.link.playsInline;
    final playback = inline ? _playback : widget.players.open(_page(context.tokens.color('app-paper')), open: widget.open);
    if (playback == null) return;
    late final OverlayEntry entry;
    VoidCallback? off;
    void shut() {
      if (_shut == null) return;
      _shut = null;
      off?.call();
      entry.remove();
      entry.dispose();
      if (inline) {
        if (mounted && !_stopping) {
          setState(() => _full = false);
        } else {
          _full = false;
        }
      } else {
        playback.dispose();
      }
    }

    final label = '${widget.link.serviceName}, $_title, full screen';
    entry = OverlayEntry(
      builder: (context) => EmbedLayer(
        label: label,
        dark: inline,
        onClose: shut,
        child: inline ? KeyedSubtree(key: _slot, child: playback.view(whole: true)) : playback.view(whole: true),
      ),
    );
    _shut = shut;
    off = BackScope.of(context).onBack(() {
      shut();
      return true;
    });
    if (inline) setState(() => _full = true);
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final phase = this.phase;
    if (phase == EmbedCardPhase.quiet) {
      // The service's name and the link, and nothing asked of it.
      return widget.plain(link.openUrl, LinkPreview(url: link.openUrl, title: widget.words ?? '${link.serviceName} ${link.kindName.toLowerCase()}', site: link.serviceName));
    }
    if (phase == EmbedCardPhase.failed) return widget.plain(link.openUrl, null);

    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    // The card is in the note's own hand and size, as the plain card is.
    final base = look?.line(LookElement(null)).base;
    final em = base?.fontSize ?? t.len('app-body');
    final ink = base?.color ?? t.color('app-ink');
    final face = (base?.style ?? t.textAt(em, mono: true)).copyWith(color: ink, decoration: TextDecoration.none);
    final border = look?.env.border(1) ?? 1.0;
    final paper85 = t.colorOf('color-mix(in srgb, var(--app-paper) 85%, transparent)');
    final embed = widget.embeds.embedFor(link);
    final title = _title;
    final about = <String>[?embed?.author, '${link.serviceName} ${link.kindName.toLowerCase()}'].join(' · ');

    Widget disc(LucideIcon icon) => ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey<String>('cm-embed-disc'),
        decoration: ShapeDecoration(color: paper85, shape: const CircleBorder()),
        child: SizedBox.square(
          dimension: t.lenOf('3.25rem'),
          child: Center(
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: icon == Lucide.play ? 3 : 0),
              child: AppIcon(icon, size: t.lenOf('1.35rem'), color: t.color('app-ink'), wash: icon == Lucide.play),
            ),
          ),
        ),
      ),
    );

    final picture = _picture == null
        ? const SizedBox.expand()
        : ExcludeSemantics(
            child: Image.memory(
              _picture!,
              key: const ValueKey<String>('cm-embed-picture'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
              // A picture that will not decode leaves the card's own ground: nothing to say about it.
              errorBuilder: (context, error, stack) => const SizedBox.expand(),
            ),
          );

    Widget pressable({required String label, required Widget child}) => Semantics(
      button: true,
      label: label,
      onTap: _play,
      child: GestureDetector(
        key: const ValueKey<String>('cm-embed-play'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _play,
        child: child,
      ),
    );

    final playing = _playback;
    final verb = link.playsInline ? 'Play' : 'Open';
    Widget media;
    switch (link.service) {
      case EmbedService.youtube:
        media = AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: playing != null
                ? Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: _full
                            ? Center(child: InlineWords('Playing full screen', style: face.copyWith(fontSize: em * 0.86, color: const Color(0xFFFFFFFF)), lineHeight: em * 1.3))
                            : KeyedSubtree(key: _slot, child: playing.view(whole: false)),
                      ),
                      if (!_full)
                        PositionedDirectional(
                          end: t.space(1),
                          bottom: t.space(1),
                          child: Semantics(
                            button: true,
                            label: 'Full screen',
                            child: GestureDetector(
                              key: const ValueKey<String>('cm-embed-full'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _openLayer,
                              child: DecoratedBox(
                                decoration: ShapeDecoration(color: paper85, shape: const CircleBorder()),
                                child: SizedBox.square(dimension: t.lenOf('2.25rem'), child: Center(child: AppIcon(Lucide.maximize, size: t.lenOf('1.05rem'), color: t.color('app-ink'), wash: false))),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : pressable(label: '$verb $title', child: Stack(children: <Widget>[Positioned.fill(child: picture), Center(child: disc(Lucide.play))])),
          ),
        );
      case EmbedService.spotify:
        if (playing != null) {
          media = SizedBox(key: const ValueKey<String>('cm-embed-player'), height: link.playerHeight, child: playing.view(whole: false));
        } else {
          final side = layoutUnit(em * 5);
          media = pressable(
            label: '$verb $title',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox.square(
                  dimension: side,
                  child: ColoredBox(
                    color: t.colorOf('color-mix(in srgb, currentColor 10%, transparent)', current: ink),
                    child: Stack(children: <Widget>[Positioned.fill(child: picture), Center(child: Transform.scale(scale: 0.8, child: disc(Lucide.play)))]),
                  ),
                ),
                Expanded(child: _words(face, em, t, title, about)),
              ],
            ),
          );
        }
      case EmbedService.figma:
        final w = embed?.thumbnailWidth, h = embed?.thumbnailHeight;
        final shape = w != null && h != null ? (w / h).clamp(0.75, 2.4) : 16 / 10;
        media = pressable(
          label: '$verb $title',
          child: AspectRatio(
            aspectRatio: shape,
            child: ColoredBox(
              color: t.colorOf('color-mix(in srgb, currentColor 6%, transparent)', current: ink),
              child: Stack(children: <Widget>[Positioned.fill(child: picture), Center(child: disc(Lucide.maximize))]),
            ),
          ),
        );
    }

    // "Open in …": the service's own app, or the browser, wherever the card is.
    final openIn = Semantics(
      link: true,
      label: 'Open in ${link.serviceName}',
      onTap: _openOutside,
      child: GestureDetector(
        key: const ValueKey<String>('cm-embed-open'),
        behavior: HitTestBehavior.opaque,
        onTap: _openOutside,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: layoutUnit(em * 0.25)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(Lucide.externalLink, size: em * 0.9, color: t.color('app-ink-2'), wash: false),
              SizedBox(width: layoutUnit(em * 0.4)),
              ExcludeSemantics(child: InlineWords('Open in ${link.serviceName}', style: face.copyWith(fontSize: em * 0.86, color: t.color('app-ink-2'), fontWeight: FontWeight.w600), lineHeight: em * 0.86 * 1.4)),
            ],
          ),
        ),
      ),
    );

    final pad = EdgeInsets.symmetric(vertical: layoutUnit(em * 0.5), horizontal: layoutUnit(em * 0.75));
    final spotifyRow = link.service == EmbedService.spotify && playing == null;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        media,
        Padding(
          padding: pad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // The Spotify row says its words beside the artwork; the player says them itself.
              if (link.service != EmbedService.spotify) ...<Widget>[_words(face, em, t, title, about, padded: false), SizedBox(height: layoutUnit(em * 0.25))],
              openIn,
            ],
          ),
        ),
      ],
    );

    final card = DecoratedBox(
      key: ValueKey<String>('cm-embedCard-${link.service.name}'),
      decoration: BoxDecoration(
        color: _pressed && spotifyRow ? t.colorOf('color-mix(in srgb, currentColor 8%, var(--app-paper-2, transparent))', current: ink) : t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: t.color('app-rule'), width: border),
      ),
      child: Padding(
        padding: EdgeInsets.all(border),
        child: ClipRRect(borderRadius: BorderRadius.circular(t.radius('lg') - border), child: body),
      ),
    );

    // Space round it as the plain card has it (link_cards.dart '.cm-linkCardWrap').
    final gutter = gutterOf(context);
    return Padding(
      key: const ValueKey<String>('cm-embedCardWrap'),
      padding: EdgeInsets.only(top: layoutUnit(em * 0.25), bottom: layoutUnit(em * 0.6), left: t.lenOf('var(--app-safe-left, 0px)') + gutter, right: t.lenOf('var(--app-safe-right, 0px)') + gutter),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: t.lenOf('32rem')), child: card),
      ),
    );
  }

  /// The title, two lines at most, and who made it with the service's name.
  Widget _words(TextStyle face, double em, Tokens t, String title, String about, {bool padded = true}) {
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InlineWords(title, key: const ValueKey<String>('cm-embed-title'), style: face.copyWith(fontWeight: FontWeight.w600), lineHeight: em * 1.3, maxLines: 2),
        SizedBox(height: layoutUnit(em * 0.1)),
        InlineWords(about, key: const ValueKey<String>('cm-embed-about'), style: face.copyWith(fontSize: em * 0.8, color: t.color('app-ink-3')), lineHeight: em * 0.8 * 1.5, ellipsis: true),
      ],
    );
    return padded ? Padding(padding: EdgeInsets.symmetric(horizontal: layoutUnit(em * 0.75)), child: ExcludeSemantics(child: words)) : ExcludeSemantics(child: words);
  }
}

/// The layer over the app: a YouTube video moved there playing, on black, or a Figma file on the page's paper; a
/// close in the corner, Escape, and the phone's back (the opener's).
class EmbedLayer extends StatefulWidget {
  const EmbedLayer({super.key, required this.label, required this.onClose, required this.child, this.dark = false});

  final String label;
  final VoidCallback onClose;
  final Widget child;

  /// Black, as a film's layer is, rather than the page's paper.
  final bool dark;

  @override
  State<EmbedLayer> createState() => _EmbedLayerState();
}

class _EmbedLayerState extends State<EmbedLayer> {
  final FocusNode _keys = FocusNode(debugLabel: 'embed full screen');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final space3 = t.space(3);
    final top = t.lenOf('var(--app-inset-top, 0px)');
    final close = t.lenOf('2.75rem');
    final layer = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.label,
      child: Focus(
        focusNode: _keys,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ColoredBox(
          key: const ValueKey<String>('cm-embed-layer'),
          color: widget.dark ? const Color(0xFF000000) : t.color('app-paper'),
          child: Stack(
            children: <Widget>[
              // Under the close's row, so the embed's own controls at its top are not under the close.
              Positioned(
                left: t.lenOf('var(--app-safe-left, 0px)'),
                right: t.lenOf('var(--app-safe-right, 0px)'),
                top: top + space3 * 2 + close,
                bottom: t.lenOf('var(--app-safe-bottom, 0px)'),
                child: widget.child,
              ),
              PositionedDirectional(
                top: top + space3,
                end: t.lenOf('var(--app-safe-right, 0px)') + space3,
                child: Semantics(
                  button: true,
                  label: 'Close',
                  child: GestureDetector(
                    key: const ValueKey<String>('cm-embed-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: t.colorOf('color-mix(in srgb, var(--app-paper) 85%, transparent)'), shape: const CircleBorder()),
                      child: SizedBox.square(dimension: close, child: Center(child: AppIcon(Lucide.x, size: t.lenOf('1.5rem'), color: t.color('app-ink'), wash: false))),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
