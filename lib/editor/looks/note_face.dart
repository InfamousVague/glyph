/// The note's own face for something the app draws inside the editor. On the page such a drawing (the list a
/// ```comments fence is drawn as, a canvas frame's bar) is an element inside `.cm-scroller`, so unless its own
/// stylesheet says otherwise it inherits the note's face and the editor's leading:
/// `.cm-scroller { font-family: var(--app-note-font, var(--glacier-font-sans)); line-height: 1.6 }` (glyphTheme.ts).
/// A widget inherits neither, so it asks here.
library;

import 'package:flutter/painting.dart';
import 'package:glacier/glacier.dart';

import 'look.dart';

/// Words at [px] in the face a plain line of [look] is set in, at the editor's leading unless told another; the
/// app's own face where there is no look to ask.
TextStyle noteFace(Tokens t, Look? look, double px, {String weight = 'regular', Color? color, double height = 1.6}) {
  final base = look?.line(LookElement(null)).base.style;
  if (base == null) return t.textAt(px, weight: weight, color: color, height: height);
  final heavy = t.len('glacier-font-weight-$weight');
  final sized = Tokens.resized(base, px);
  return sized.copyWith(
    height: height,
    color: color,
    fontWeight: FontWeight.values[((heavy / 100).round() - 1).clamp(0, 8)],
    fontVariations: <FontVariation>[for (final variation in sized.fontVariations ?? const <FontVariation>[]) variation.axis == 'wght' ? FontVariation('wght', heavy) : variation],
    decoration: TextDecoration.none,
  );
}
