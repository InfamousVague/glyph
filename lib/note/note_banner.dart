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
const double noteBannerMaxHeight = 260;

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

final Map<String, bool> _inColour = {};
final Map<String, Future<bool>> _readingColour = {};

/// Whether the picture [name] is in colour, once read: null until then, and [bannerInColour] reads it.
bool? bannerInColourKnown(String name) => _inColour[name];

/// Whether the picture [name] in [store] is in colour: read once from a small copy of it and remembered by name (a
/// kept picture's name is its content's, so it never changes under the name). One that cannot be read is taken for
/// black and white, as the banners before colour all were.
Future<bool> bannerInColour(PictureStore store, String name) {
  final known = _inColour[name];
  if (known != null) return Future<bool>.value(known);
  return _readingColour[name] ??= () async {
    var colour = false;
    try {
      final bytes = await store.bytesOf(name);
      if (bytes != null) colour = await pictureInColour(bytes);
    } catch (_) {
      colour = false;
    }
    _inColour[name] = colour;
    _readingColour.remove(name);
    return colour;
  }();
}

/// Whether the picture [bytes] is in colour: decoded small, more than [bannerColourShare] of its pixels with channels
/// [bannerColourSpread] apart.
Future<bool> pictureInColour(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return false;
    final pixels = data.lengthInBytes ~/ 4;
    var coloured = 0;
    for (var i = 0; i < pixels; i += 1) {
      final r = data.getUint8(i * 4), g = data.getUint8(i * 4 + 1), b = data.getUint8(i * 4 + 2);
      if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) > bannerColourSpread) coloured += 1;
    }
    return pixels > 0 && coloured / pixels > bannerColourShare;
  } finally {
    image.dispose();
    codec.dispose();
  }
}

@visibleForTesting
void forgetBannerColours() {
  _inColour.clear();
  _readingColour.clear();
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
          final height = math.min(width / bannerAspect, noteBannerMaxHeight);
          if (name == null) {
            return SizedBox(
              key: const ValueKey<String>('note-banner-making'),
              width: width,
              height: height,
              child: LovartPending(prompt: prompt, maxHeight: height),
            );
          }
          return Semantics(
            label: 'Header image',
            image: true,
            child: ClipRRect(
              key: ValueKey<String>('note-banner-$name'),
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox(
                width: width,
                height: height,
                child: LovartBadged(
                  name: name,
                  child: _BannerInks(
                    name: name,
                    store: store,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: KeptPicture(name: name, store: store, badge: false, waiting: SizedBox(width: width, height: height)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The banner in the page's inks while it is black and white (or not yet read), in its own colours once it is read to
/// be in colour ([bannerInColour]).
class _BannerInks extends StatefulWidget {
  const _BannerInks({required this.name, required this.store, required this.child});

  final String name;
  final PictureStore? store;
  final Widget child;

  @override
  State<_BannerInks> createState() => _BannerInksState();
}

class _BannerInksState extends State<_BannerInks> {
  bool _colour = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_BannerInks old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.store != widget.store) _read();
  }

  void _read() {
    final name = widget.name;
    _colour = bannerInColourKnown(name) ?? false;
    final store = widget.store;
    if (store == null || bannerInColourKnown(name) != null) return;
    unawaited(bannerInColour(store, name).then((colour) {
      if (mounted && widget.name == name && colour != _colour) setState(() => _colour = colour);
    }));
  }

  @override
  Widget build(BuildContext context) {
    if (_colour) return widget.child;
    final t = context.tokens;
    return ColorFiltered(colorFilter: inkOnPaper(t.color('app-ink'), t.color('app-paper')), child: widget.child);
  }
}
