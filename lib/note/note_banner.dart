/// A note's header banner, across the top of its page (lib/core/banner.dart): the picture its front matter names, in
/// the page's own inks, or Lovart at work on one (lib/plugins/lovart/banners.dart).
///
/// The banners are the ghost's dotwork, black dots on white, so they are drawn the way the ghost's scenes are
/// (lib/art/ghost.dart): in the page's colours rather than their own. White is the page's paper and black its ink, so
/// a banner sits on the light page with no white box round it and turns over on the dark one, dots of light on the
/// night page.
library;

import 'dart:math' as math;

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
                  child: ColorFiltered(
                    colorFilter: inkOnPaper(t.color('app-ink'), t.color('app-paper')),
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
