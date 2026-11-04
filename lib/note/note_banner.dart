/// A note's header banner, across the top of its page (lib/core/banner.dart): the picture its front matter names, in
/// the page's own inks, or Lovart at work on one (lib/plugins/lovart/banners.dart).
///
/// The first banners were the ghost's dotwork in black dots on white, so they are drawn the way the ghost's scenes are
/// (lib/art/ghost.dart): in the page's colours rather than their own. White is the page's paper and black its ink, so
/// such a banner sits on the light page with no white box round it and turns over on the dark one, dots of light on
/// the night page. Since 2026-10-26 they are made in full colour (Matt: "The dotwork pre prompts should be full color
/// like the grocery store item from earlier"), and a picture in colour is drawn in its own colours: turned over, its
/// reds would come out cyan. Since 2026-11-04 no banner is turned over at all (Matt: "on dark mode the images are
/// inverted for some reason in the header", a painting drawn as its negative, then "just remove the invert logic all
/// together"): every one is drawn in its own colours, the old dotwork too. Whether one is in colour is still read
/// ([bannerInColour]), for the redo of black-and-white banners (Settings › Lovart).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show AppIcon, LucideIcon;
import '../core/banner.dart' show bannerAspect;
import '../core/images.dart' show PictureStore;
import '../editor/media/images.dart' show KeptPicture;
import '../editor/media/lovart_badge.dart' show LovartBadged;
import '../editor/media/lovart_pending.dart' show LovartPending;
import '../activity/activity_look.dart' show activityMoves;
import '../notes/note_menu.dart' show byMouse;
import '../shell/pop_menu.dart';

/// The tallest a banner is drawn, past which a wide window's banner keeps this height and is cropped to its middle.
const double noteBannerMaxHeight = 420;

/// How far apart a pixel's channels are before it counts as coloured, of 255: a grey's are equal, and a JPEG's
/// noise and a warm paper stay under it.
const int bannerColourSpread = 40;

/// The share of a banner's pixels that are coloured before it is drawn in its own colours.
const double bannerColourShare = 0.01;

/// How dark a channel is before a pixel counts as drawn rather than the white ground, of 255.
const int bannerInkBelow = 232;

/// The shapes a banner is drawn at, widest and tallest, as width over height. Lovart takes no size but in words
/// (lib/plugins/lovart/client.dart) and makes squares and 16:9s whatever it is asked (Matt, 2026-10-26: "The header
/// images also seem cut off and not generated at the right size"; the first ones were 1254×1254 drawn into a 4:1
/// strip, a quarter of each showing). So a banner is drawn at the shape of what is drawn in it, between these; and no
/// wider than 2.5:1 ("Make the banner images taller too").
const double bannerWidest = 2.5;
const double bannerTallest = 16 / 9;

/// A banner picture as read once ([bannerLook]): whether it is in colour, its own shape, and where on it the drawing
/// is, as fractions of its width and height (the white ground round it left out).
@immutable
class BannerLook {
  const BannerLook({required this.colour, required this.aspect, required this.drawn});

  /// Black and white, the whole picture, the shape it is drawn at before it is read.
  static const BannerLook unread = BannerLook(colour: false, aspect: bannerAspect, drawn: Rect.fromLTWH(0, 0, 1, 1));

  final bool colour;

  /// The picture's own width over height.
  final double aspect;

  /// Where the drawing is, in fractions of the picture.
  final Rect drawn;

  /// The shape the banner is drawn at: the drawing's own, held between [bannerTallest] and [bannerWidest].
  double get shape {
    final w = drawn.width * aspect, h = drawn.height;
    if (w <= 0 || h <= 0) return aspect.clamp(bannerTallest, bannerWidest);
    return (w / h).clamp(bannerTallest, bannerWidest);
  }

  /// Where the picture is held as it covers a box of [box]'s shape, so the drawing's middle is the box's.
  Alignment alignmentIn(double box) {
    double along(double centre, double seen) => seen >= 1 ? 0 : ((2 * (centre - seen / 2) / (1 - seen)) - 1).clamp(-1.0, 1.0);
    // Covering: a box wider than the picture shows all its width and [aspect]/[box] of its height; a narrower one
    // all its height and [box]/[aspect] of its width.
    return box >= aspect ? Alignment(0, along(drawn.center.dy, aspect / box)) : Alignment(along(drawn.center.dx, box / aspect), 0);
  }

  /// Where the whole picture lies as it is drawn into a banner of [box], in the banner's own coordinates: near
  /// enough that its drawing covers the banner, the drawing's middle on the banner's, held so the picture's own edge
  /// never shows (Matt, 2026-11-02: "If I remove a header image and make a new one it's not filling the space").
  /// Covering with the picture alone, as [alignmentIn] does, showed the white ground the drawing is on: since
  /// 2026-10-26 the prompt asks for the drawing in the right two-thirds of a middle band, the left third white, and a
  /// banner in colour is drawn in its own colours, so a new one was a white third and white bands round a drawing in
  /// the rest. The banner already has the drawing's shape ([shape]), so only a drawing taller than [bannerTallest]
  /// loses anything, its top and bottom.
  Rect placeIn(Size box) {
    final w = box.width, h = box.height;
    if (w <= 0 || h <= 0 || aspect <= 0) return Offset.zero & box;
    var width = math.max(w, h * aspect);
    if (drawn.width > 0 && drawn.height > 0) width = math.max(width, math.max(w / drawn.width, h * aspect / drawn.height));
    final height = width / aspect;
    double at(double room, double size, double centre) => (room / 2 - centre * size).clamp(room - size, 0.0);
    return Rect.fromLTWH(at(w, width, drawn.center.dx), at(h, height, drawn.center.dy), width, height);
  }
}

final Map<String, BannerLook> _looks = {};
final Map<String, Future<BannerLook>> _reading = {};

/// The picture [name]'s look, once read: null until then, and [bannerLook] reads it.
BannerLook? bannerLookKnown(String name) => _looks[name];

/// Whether the picture [name] is in colour, once read.
bool? bannerInColourKnown(String name) => _looks[name]?.colour;

/// The picture [name] in [store], read once from a small copy of it and remembered by name (a kept picture's name is
/// its content's, so it never changes under the name). One that cannot be read is [BannerLook.unread].
Future<BannerLook> bannerLook(PictureStore store, String name) {
  final known = _looks[name];
  if (known != null) return Future<BannerLook>.value(known);
  return _reading[name] ??= () async {
    var look = BannerLook.unread;
    try {
      final bytes = await store.bytesOf(name);
      if (bytes != null) look = await readBannerLook(bytes);
    } catch (_) {
      look = BannerLook.unread;
    }
    _looks[name] = look;
    _reading.remove(name);
    return look;
  }();
}

/// Whether the picture [name] in [store] is in colour ([bannerLook]).
Future<bool> bannerInColour(PictureStore store, String name) async => (await bannerLook(store, name)).colour;

/// Whether the picture [bytes] is in colour: more than [bannerColourShare] of its pixels with channels
/// [bannerColourSpread] apart.
Future<bool> pictureInColour(Uint8List bytes) async => (await readBannerLook(bytes)).colour;

/// The picture [bytes] read small: in colour or not, its shape, and the box round every pixel darker than the white
/// ground.
Future<BannerLook> readBannerLook(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width, h = image.height;
    if (data == null || w == 0 || h == 0) return BannerLook.unread;
    var coloured = 0;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y += 1) {
      for (var x = 0; x < w; x += 1) {
        final i = (y * w + x) * 4;
        final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
        final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
        if (hi - lo > bannerColourSpread) coloured += 1;
        if (lo < bannerInkBelow) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    final drawn = right < left ? const Rect.fromLTWH(0, 0, 1, 1) : Rect.fromLTRB(left / w, top / h, (right + 1) / w, (bottom + 1) / h);
    return BannerLook(colour: coloured / (w * h) > bannerColourShare, aspect: w / h, drawn: drawn);
  } finally {
    image.dispose();
    codec.dispose();
  }
}

@visibleForTesting
void forgetBannerColours() {
  _looks.clear();
  _reading.clear();
}

/// The banner [name] of the note, from [store]; while [making], Lovart's blurred stand-in where it will land
/// (lib/editor/media/lovart_pending.dart; back since 2026-11-02 in place of the activity band), at the shape the
/// banner it replaces is drawn at or, with none, the shape a banner is drawn at before it is read, the picture fading in
/// over it as it lands; with neither, nothing.
///
/// With [menu], the picture has a menu of its own (Matt, 2026-11-02: "regenerating header images by right clicking and
/// removing them should be a thing"): a mouse's right-click, or a finger's press held, opens it at that point, in the
/// app's menu (lib/shell/pop_menu.dart) as a note's right-click does (lib/notes/note_menu.dart). Its rows are asked
/// for as it opens, so they say what is true then.
class NoteBannerView extends StatelessWidget {
  const NoteBannerView({super.key, required this.name, required this.store, this.making = false, this.prompt = '', this.start, this.menu});

  /// The rows of the picture's menu; null for none.
  final List<BannerMenuRow> Function()? menu;

  final String? name;
  final PictureStore? store;
  final bool making;

  /// What Lovart was asked for, while it is made: the blurred stand-in's colours are picked by it.
  final String prompt;

  /// The column's own left edge where the page reads as a column; the gutter otherwise.
  final double? start;

  @override
  Widget build(BuildContext context) {
    final name = this.name;
    if (name == null && !making) return const SizedBox.shrink();
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final radius = t.radius('md');
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(start ?? gutter, t.space(2), start ?? gutter, t.space(3)),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          final look = (name == null ? null : bannerLookKnown(name)) ?? BannerLook.unread;
          final height = math.min(width / look.shape, noteBannerMaxHeight);
          return _Landing(
            making: making,
            band: SizedBox(
              key: const ValueKey<String>('note-banner-making'),
              width: width,
              height: height,
              // Lovart's blurred stand-in, its mark and the ring turning (Matt, 2026-11-02: "bring back the blurry image
              // with the lovart logo with the spinner when generating images and header images").
              child: LovartPending(prompt: prompt.isEmpty ? 'header image' : prompt, height: height),
            ),
            picture: name == null ? null : _BannerMenuArea(rows: menu, child: _BannerPicture(name: name, store: store, width: width, radius: radius)),
          );
        },
      ),
    );
  }
}

/// The band while the banner is made, and the [picture] once it lands, the band fading away over it (at once where
/// the device asks for less motion). At rest it is the picture alone, drawn as it always was: no layer of its own.
class _Landing extends StatefulWidget {
  const _Landing({required this.making, required this.band, required this.picture});

  final bool making;
  final Widget band;
  final Widget? picture;

  @override
  State<_Landing> createState() => _LandingState();
}

class _LandingState extends State<_Landing> with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  /// The band as it was when the picture landed, while it fades.
  Widget? _leaving;

  @override
  void didUpdateWidget(_Landing old) {
    super.didUpdateWidget(old);
    if (old.making && !widget.making && widget.picture != null && activityMoves(context)) {
      _leaving = old.band;
      _out.value = 1;
      _out.animateTo(0).whenCompleteOrCancel(() {
        if (mounted) setState(() => _leaving = null);
      });
    } else if (widget.making) {
      _out.stop();
      _leaving = null;
    }
  }

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.making) return widget.band;
    final picture = widget.picture ?? const SizedBox.shrink();
    final leaving = _leaving;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        picture,
        if (leaving != null) Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: FadeTransition(key: const ValueKey<String>('note-banner-landing'), opacity: _out, child: leaving))),
      ],
    );
  }
}

/// The banner at its shape ([BannerLook.shape]) with its drawing in the middle, always in its own colours.
class _BannerPicture extends StatefulWidget {
  const _BannerPicture({required this.name, required this.store, required this.width, required this.radius});

  final String name;
  final PictureStore? store;
  final double width;
  final double radius;

  @override
  State<_BannerPicture> createState() => _BannerPictureState();
}

class _BannerPictureState extends State<_BannerPicture> {
  BannerLook _look = BannerLook.unread;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_BannerPicture old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.store != widget.store) _read();
  }

  void _read() {
    final name = widget.name;
    final known = bannerLookKnown(name);
    _look = known ?? BannerLook.unread;
    final store = widget.store;
    if (store == null || known != null) return;
    unawaited(bannerLook(store, name).then((look) {
      if (mounted && widget.name == name) setState(() => _look = look);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name, store = widget.store, width = widget.width;
    final height = math.min(width / _look.shape, noteBannerMaxHeight);
    final kept = KeptPicture(name: name, store: store, badge: false, waiting: SizedBox(width: width, height: height));
    // Before it is read its shape is a guess: covered, its middle on the banner's. Once read, laid where [placeIn]
    // puts it (still covered within that place, so a guess that was wrong never stretches it).
    Widget picture = identical(_look, BannerLook.unread)
        ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: kept)
        : ClipRect(child: Stack(children: [Positioned.fromRect(rect: _look.placeIn(Size(width, height)), child: FittedBox(fit: BoxFit.cover, child: kept))]));
    return Semantics(
      label: 'Header image',
      image: true,
      child: ClipRRect(
        key: ValueKey<String>('note-banner-$name'),
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(width: width, height: height, child: LovartBadged(name: name, child: picture)),
      ),
    );
  }
}

/// A row of a banner's menu ([NoteBannerView.menu]): [onSelect] null and [why] said where it cannot be done here.
@immutable
class BannerMenuRow {
  const BannerMenuRow({required this.id, required this.label, required this.icon, this.onSelect, this.why, this.danger = false});

  final String id;
  final String label;
  final LucideIcon icon;
  final VoidCallback? onSelect;

  /// Why it cannot be chosen now, under its label: "Add your Lovart keys in Settings › Lovart first."
  final String? why;

  /// In the one red the app has, as a note's Delete is.
  final bool danger;
}

/// The banner's picture, answering a mouse's right-click and a finger's press held with its menu at that point.
class _BannerMenuArea extends StatefulWidget {
  const _BannerMenuArea({required this.rows, required this.child});

  final List<BannerMenuRow> Function()? rows;
  final Widget child;

  @override
  State<_BannerMenuArea> createState() => _BannerMenuAreaState();
}

class _BannerMenuAreaState extends State<_BannerMenuArea> {
  /// Where the menu is open, in the window; null while it is shut.
  Offset? _at;
  bool _coarse = false;

  void _open(Offset at, {required bool coarse}) => setState(() {
        _at = at;
        _coarse = coarse;
      });

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows == null) return widget.child;
    final at = _at;
    final t = context.tokens;
    final em = _coarse ? t.fontSize('md') : t.fontSize('sm');
    return Listener(
      onPointerDown: (event) {
        if (byMouse(event.kind) && event.buttons == kSecondaryMouseButton) _open(event.position, coarse: false);
      },
      child: GestureDetector(
        // A finger's (a mouse's press held is a press); the page under it scrolls as before until it is held.
        supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus, PointerDeviceKind.unknown},
        onLongPressStart: (details) => _open(details.globalPosition, coarse: true),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (at != null)
              Positioned(
                left: 0,
                top: 0,
                child: PopMenu(
                  key: ValueKey<Offset>(at),
                  anchor: GlacierAnchor.point(at),
                  onDismiss: () {
                    if (mounted && _at == at) setState(() => _at = null);
                  },
                  ariaLabel: 'Header image',
                  coarse: _coarse,
                  children: [
                    for (final row in rows())
                      GlacierMenuItem(
                        key: ValueKey<String>('banner-menu-${row.id}'),
                        icon: AppIcon(row.icon, size: em),
                        danger: row.danger,
                        style: row.danger ? dangerRowStyle(t) : null,
                        disabled: row.onSelect == null,
                        onSelect: row.onSelect,
                        ariaLabel: row.why == null ? null : '${row.label}. ${row.why}',
                        child: row.why == null
                            ? Text(row.label)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(row.label),
                                  Text(row.why!, style: TextStyle(fontSize: t.fontSize('xs'), color: t.color('app-ink-3'))),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
