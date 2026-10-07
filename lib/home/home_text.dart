/// The home page's text, as the web page sets it: the kit's faces at a size of the page's own, on a browser's
/// `line-height: normal`.
///
/// A browser makes a `normal` line of Inter from the face's ascent and descent each rounded to a whole pixel
/// (measured on the page: 13.43px text stands in a 16px line, 16.18px in 20, 11.15px in 14), where Flutter adds them
/// unrounded (16.25, 19.58, 13.49). A page of rows is that half pixel a line out by its foot, so the leading is worked
/// out here as the browser does. A workaround kept beside the page until the kit's `textAt` does the same.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// Inter's ascent and descent, as a share of its size (hhea: 1984 and 494 of 2048).
const double _interAscent = 1984 / 2048;
const double _interDescent = 494 / 2048;

/// The line a browser gives Inter at [px] under `line-height: normal`, as a multiple of the size.
double normalLeading(double px) => px <= 0 ? 1.2 : ((_interAscent * px).round() + (_interDescent * px).round()) / px;

/// Page text in the sans face at [px]: `line-height: normal` unless [height] (a unitless multiple) says another.
TextStyle pageText(Tokens t, double px, {String weight = 'regular', Color? color, double? height, double tracking = 0}) =>
    t.textAt(px, weight: weight, color: color, height: height ?? normalLeading(px), tracking: tracking);

/// `font-variant-numeric: tabular-nums`: figures of one width, added to whatever features the style has.
TextStyle tabular(TextStyle style) => style.copyWith(fontFeatures: [...?style.fontFeatures, const FontFeature.tabularFigures()]);
