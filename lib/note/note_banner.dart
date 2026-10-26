/// A note's header banner, across the top of its page (lib/core/banner.dart): the picture its front matter names, in
/// the page's own inks, or Lovart at work on one (lib/plugins/lovart/banners.dart).
///
/// The first banners were the ghost's dotwork in black dots on white, so they are drawn the way the ghost's scenes are
/// (lib/art/ghost.dart): in the page's colours rather than their own. White is the page's paper and black its ink, so
/// such a banner sits on the light page with no white box round it and turns over on the dark one, dots of light on
/// the night page. Since 2026-10-26 they are made in full colour (Matt: "The dotwork pre prompts should be full color
/// like the grocery store item from earlier"), and a picture in colour is drawn in its own colours: turned over, its
/// reds would come out cyan. Which a banner is, is read from the picture itself once ([bannerInColour]), so the black
/// and white ones already made keep turning over and nothing in the note says which it is.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/banner.dart' show bannerAspect;
import '../core/images.dart' show PictureStore;
import '../editor/media/images.dart' show KeptPicture;
import '../editor/media/lovart_badge.dart' show LovartBadged;
import '../editor/media/lovart_pending.dart' show LovartPending;

/// The tallest a banner is drawn, past which a wide window's banner keeps this height and is cropped to its middle.
const double noteBannerMaxHeight = 420;

/// A colour filter that draws a black-on-white picture in [ink] on [paper]: each channel's white is the paper's,
/// its black the ink's, and the greys between.
ColorFilter inkOnPaper(Color ink, Color paper) {
  List<double> row(double inkC, double paperC, int at) => [for (var i = 0; i < 3; i += 1) i == at ? paperC - inkC : 0, 0, inkC * 255];
  return ColorFilter.matrix(<double>[...row(ink.r, paper.r, 0), ...row(ink.g, paper.g, 1), ...row(ink.b, paper.b, 2), 0, 0, 0, 1, 0]);
}

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

/// The banner [name] of the note, from [store]; while [making], Lovart's stand-in in its place; with neither, nothing.
class NoteBannerView extends StatelessWidget {
  const NoteBannerView({super.key, required this.name, required this.store, this.making = false, this.prompt = '', this.start});

  final String? name;
  final PictureStore? store;
  final bool making;

  /// What the stand-in's colours are picked by while it is made.
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
          if (name == null) {
            final height = math.min(width / bannerAspect, noteBannerMaxHeight);
            return SizedBox(
              key: const ValueKey<String>('note-banner-making'),
              width: width,
              height: height,
              child: LovartPending(prompt: prompt, maxHeight: height),
            );
          }
          return _BannerPicture(name: name, store: store, width: width, radius: radius);
        },
      ),
    );
  }
}

/// The banner at its shape ([BannerLook.shape]) with its drawing in the middle, in the page's inks while it is black
/// and white (or not yet read), in its own colours once it is read to be in colour.
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
    final t = context.tokens;
    final name = widget.name, store = widget.store, width = widget.width;
    final height = math.min(width / _look.shape, noteBannerMaxHeight);
    Widget picture = FittedBox(
      fit: BoxFit.cover,
      alignment: _look.alignmentIn(width / height),
      clipBehavior: Clip.hardEdge,
      child: KeptPicture(name: name, store: store, badge: false, waiting: SizedBox(width: width, height: height)),
    );
    if (!_look.colour) picture = ColorFiltered(colorFilter: inkOnPaper(t.color('app-ink'), t.color('app-paper')), child: picture);
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
