// An SVG path's data moved onto the app's 24 grid: Phosphor draws on 256, Material Symbols on 960 with its origin a
// whole height above the box (`viewBox="0 -960 960 960"`), and the app draws every icon on 24 (lib/art/app_icon.dart).
// Pure Dart, for tool/icons/generate.dart and its test (test/art/icon_pack_map_test.dart).
//
// Every point is worked out exactly, then rounded to [digits] places on the new grid, and each command is written
// whichever way is shorter, absolute or relative to where the rounded path has got to. A relative step is taken from
// the rounded point, never the exact one, so a hundred steps do not drift by a hundred halves of the last place: the
// path written lands within half of it everywhere. The numbers are written as tightly as SVG lets them be: no leading
// zero, no space before a minus or before a second decimal point, an arc's flags set against what follows them, and a
// repeated command's letter left out.

import 'dart:math' as math;

final RegExp _number = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?');
final RegExp _letter = RegExp(r'[A-Za-z]');

/// How many numbers each command takes, by its letter.
const Map<String, int> _arity = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'Q': 4, 'T': 2, 'A': 7, 'Z': 0};

/// One number of a command as it is written: a length, or (an arc's) a flag of one character.
typedef _Token = ({int value, bool flag, int places});

/// [d] scaled by [scale] about the origin and then moved by ([dx], [dy]), its numbers to [digits] places.
String rescalePath(String d, {double scale = 1, double dx = 0, double dy = 0, int digits = 2}) {
  final unit = _pow10(digits);
  int q(double value) => (value * unit).round();

  var at = 0;
  void skip() {
    while (at < d.length && ' ,\n\t\r'.contains(d[at])) {
      at++;
    }
  }

  double number() {
    skip();
    final match = _number.matchAsPrefix(d, at);
    if (match == null) throw FormatException('no number at $at in "$d"');
    at = match.end;
    return double.parse(match.group(0)!);
  }

  // An arc's flag is one character, and may be set against the next number.
  int flag() {
    skip();
    final c = d[at++];
    if (c != '0' && c != '1') throw FormatException('no flag at ${at - 1} in "$d"');
    return c == '1' ? 1 : 0;
  }

  final out = StringBuffer();
  var last = '';
  var lastText = '';

  String written(List<_Token> tokens) {
    final text = StringBuffer();
    var previous = '';
    var previousFlag = false;
    for (final token in tokens) {
      final part = token.flag ? '${token.value}' : _format(token.value, token.places);
      // A space only where the two would otherwise read as one number: never before a minus, before a point after a
      // number that has one, or after a flag (one character, whatever follows it).
      final joined = previous.isEmpty || previousFlag || part.startsWith('-') || (part.startsWith('.') && previous.contains('.'));
      if (!joined) text.write(' ');
      text.write(part);
      previous = part;
      previousFlag = token.flag;
    }
    return text.toString();
  }

  void put(String letter, List<_Token> tokens) {
    // A command's letter is left out where it repeats, as SVG lets it be; never a move's (a second move left out is a
    // line) or a close's (which has no numbers to repeat).
    final write = letter != last || 'MmZz'.contains(letter);
    if (write) out.write(letter);
    // Numbers set against the last of the command before need the same care as numbers within one.
    final text = written(tokens);
    if (!write && text.isNotEmpty && !text.startsWith('-') && !(text.startsWith('.') && lastText.contains('.'))) out.write(' ');
    out.write(text);
    last = letter;
    lastText = tokens.isEmpty ? '' : (tokens.last.flag ? '0' : _format(tokens.last.value, tokens.last.places));
  }

  /// [upper]'s command with its tokens, written absolute or relative, whichever is shorter.
  void either(String upper, List<_Token> absolute, List<_Token> relative, {bool preferRelative = false}) {
    final a = written(absolute), r = written(relative);
    final useRelative = r.length < a.length || (r.length == a.length && preferRelative);
    put(useRelative ? upper.toLowerCase() : upper, useRelative ? relative : absolute);
  }

  _Token len(int value) => (value: value, flag: false, places: digits);
  _Token flagged(int value) => (value: value, flag: true, places: 0);

  // Where the exact path is in the source's own grid, and where the rounded one is, in the new grid's units; and
  // where each subpath began.
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  var rx = 0, ry = 0, rStartX = 0, rStartY = 0;
  int sx(double v) => q(v * scale + dx);
  int sy(double v) => q(v * scale + dy);
  var begun = false;

  // The last curve's last control, exact and rounded, and whether it was a cubic's or a quadratic's.
  var cx = 0.0, cy = 0.0;
  var rcx = 0, rcy = 0;
  String? lastKind;

  String? command;
  while (true) {
    skip();
    if (at >= d.length) break;
    final c = d[at];
    if (_letter.hasMatch(c)) {
      command = c;
      at++;
    } else if (command == null) {
      throw FormatException('a number before any command in "$d"');
    } else if (command == 'M') {
      command = 'L';
    } else if (command == 'm') {
      command = 'l';
    }
    final upper = command.toUpperCase();
    final relative = command != upper;
    if (!_arity.containsKey(upper)) throw FormatException('a command this does not know: $command');
    if (upper == 'Z') {
      put('Z', const []);
      lastKind = null;
      x = startX;
      y = startY;
      rx = rStartX;
      ry = rStartY;
      continue;
    }

    // A point the command names, in the source's grid, made absolute.
    (double, double) abs(double px, double py) => relative ? (x + px, y + py) : (px, py);

    switch (upper) {
      case 'M' || 'L':
        final (ax, ay) = abs(number(), number());
        final qx = sx(ax), qy = sy(ay);
        // The first move is where the path begins whichever way it is written: written absolute.
        if (!begun) {
          put('M', [len(qx), len(qy)]);
        } else {
          either(upper, [len(qx), len(qy)], [len(qx - rx), len(qy - ry)], preferRelative: relative);
        }
        x = ax;
        y = ay;
      case 'H':
        final px = number();
        final ax = relative ? x + px : px;
        final qx = sx(ax);
        either('H', [len(qx)], [len(qx - rx)], preferRelative: relative);
        x = ax;
      case 'V':
        final py = number();
        final ay = relative ? y + py : py;
        final qy = sy(ay);
        either('V', [len(qy)], [len(qy - ry)], preferRelative: relative);
        y = ay;
      case 'C' || 'S' || 'Q' || 'T':
        // A smooth curve's first control is the last one's reflection, and a reflection of a rounded point is out by
        // twice its rounding: down a chain of them (Material Symbols' `t`s) the error grows by that at every step. So
        // the control the exact path has is worked out, and the smooth command kept only where the rounded path
        // reflects to the same point; elsewhere the curve is written with its control.
        final quadratic = upper == 'Q' || upper == 'T';
        final smooth = upper == 'S' || upper == 'T';
        final points = <(double, double)>[];
        if (smooth) {
          points.add(lastKind == (quadratic ? 'Q' : 'C') ? (2 * x - cx, 2 * y - cy) : (x, y));
        }
        for (var i = 0; i < (upper == 'C' ? 3 : (upper == 'T' ? 1 : 2)); i++) {
          points.add(abs(number(), number()));
        }
        final rounded = [for (final (px, py) in points) (sx(px), sy(py))];
        // Where the rounded path reflects to.
        final reflected = lastKind == (quadratic ? 'Q' : 'C') ? (2 * rx - rcx, 2 * ry - rcy) : (rx, ry);
        final keepSmooth = smooth && (reflected.$1 - rounded.first.$1).abs() <= 1 && (reflected.$2 - rounded.first.$2).abs() <= 1;
        final written = keepSmooth ? rounded.skip(1).toList() : rounded;
        final letter = keepSmooth ? upper : (quadratic ? 'Q' : 'C');
        either(letter, [for (final (px, py) in written) ...[len(px), len(py)]], [for (final (px, py) in written) ...[len(px - rx), len(py - ry)]], preferRelative: relative);
        // The control the next smooth curve reflects: the exact one, and the one the rounded path has.
        final control = points[points.length - 2];
        (cx, cy) = control;
        (rcx, rcy) = keepSmooth && quadratic ? reflected : rounded[rounded.length - 2];
        lastKind = quadratic ? 'Q' : 'C';
        x = points.last.$1;
        y = points.last.$2;
      case 'A':
        final radiusX = number(), radiusY = number(), turn = number(), large = flag(), sweep = flag();
        final (ax, ay) = abs(number(), number());
        final qx = sx(ax), qy = sy(ay);
        // The flags and the turn are not lengths, and stay as they were; the radii are, and are scaled. A round arc's
        // radius is rounded whichever way keeps its middle where it was ([_radius]).
        final radii = radiusX == radiusY
            ? () {
                final r = _radius(radiusX * scale * unit, (x * scale + dx) * unit, (y * scale + dy) * unit, (ax * scale + dx) * unit, (ay * scale + dy) * unit, rx, ry, qx, qy, digits);
                return [r, r];
              }()
            : [len(q(radiusX * scale)), len(q(radiusY * scale))];
        final shape = [...radii, len((turn * unit).round()), flagged(large), flagged(sweep)];
        either('A', [...shape, len(qx), len(qy)], [...shape, len(qx - rx), len(qy - ry)], preferRelative: relative);
        x = ax;
        y = ay;
    }
    if (upper != 'C' && upper != 'S' && upper != 'Q' && upper != 'T') lastKind = null;
    // Where the rounded path has got to: the exact point, rounded.
    rx = sx(x);
    ry = sy(y);
    if (upper == 'M') {
      startX = x;
      startY = y;
      rStartX = rx;
      rStartY = ry;
    }
    begun = true;
  }
  return out.toString();
}

/// A round arc's radius, as it is written, for the arc from (`ax`, `ay`) to (`bx`, `by`) exactly and from
/// (`qax`, `qay`) to (`qbx`, `qby`) as rounded: the radius that keeps the arc's middle where it was over the rounded
/// chord, rounded whichever way keeps it nearer, and to two places more where that is not near enough. An arc near a
/// half circle is held by little: its middle is the root of the radius's square less the half chord's from the chord,
/// and a radius a hundredth out moves it by a third of a unit, so rounded the near way a curve bulged or flattened
/// where it met the next line (Tabler's filled alert, Phosphor's brain). A radius short of the half chord is drawn as
/// the half chord (SVG's own rule), which is the half circle itself.
_Token _radius(double exact, double ax, double ay, double bx, double by, int qax, int qay, int qbx, int qby, int digits) {
  double offset(double r, double chord) {
    final half = chord / 2;
    return r <= half ? 0 : math.sqrt(r * r - half * half);
  }

  final wanted = offset(exact, math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
  final chord = math.sqrt(((qbx - qax) * (qbx - qax) + (qby - qay) * (qby - qay)).toDouble());
  // The radius that would put the middle back exactly over the rounded chord, and the two it rounds to, in units of
  // [fine] of the last place: the last place itself first, and two places more where neither of its two lands
  // within two of the last place of the middle.
  final ideal = math.sqrt(wanted * wanted + chord * chord / 4);
  ({int value, double off}) best(int fine) {
    final down = (ideal * fine).floor(), up = (ideal * fine).ceil();
    final offDown = (offset(down / fine, chord) - wanted).abs(), offUp = (offset(up / fine, chord) - wanted).abs();
    return offDown <= offUp ? (value: down, off: offDown) : (value: up, off: offUp);
  }

  final plain = best(1);
  if (plain.off <= 2) return (value: plain.value, flag: false, places: digits);
  final finer = best(100);
  return finer.value % 100 == 0 ? (value: finer.value ~/ 100, flag: false, places: digits) : (value: finer.value, flag: false, places: digits + 2);
}

int _pow10(int digits) {
  var unit = 1;
  for (var i = 0; i < digits; i++) {
    unit *= 10;
  }
  return unit;
}

/// [value] in the last place's units (hundredths, at two [digits]) as the shortest number: `1.5`, `.5`, `-.25`, `12`.
String _format(int value, int digits) {
  final unit = _pow10(digits);
  final whole = value.abs() ~/ unit, part = value.abs() % unit;
  var text = part == 0 ? '$whole' : '${whole == 0 ? '' : whole}.${part.toString().padLeft(digits, '0').replaceFirst(RegExp(r'0+$'), '')}';
  if (text.isEmpty) text = '0';
  return value < 0 ? '-$text' : text;
}

/// [d] as straight lines alone, each curve and arc walked in [steps] pieces: what the wash's rule
/// (lib/art/icon_wash.dart `walkPath`) needs to see a shape's size, since it takes an arc by its two ends, and a circle
/// written as two arcs (Tabler writes every circle so) is a line to it with nothing inside.
String flattenPath(String d, {int steps = 8}) {
  var at = 0;
  void skip() {
    while (at < d.length && ' ,\n\t\r'.contains(d[at])) {
      at++;
    }
  }

  double number() {
    skip();
    final match = _number.matchAsPrefix(d, at)!;
    at = match.end;
    return double.parse(match.group(0)!);
  }

  int flag() {
    skip();
    return d[at++] == '1' ? 1 : 0;
  }

  final out = StringBuffer();
  String f(double v) => _format((v * 1000).round(), 3);
  void line(double px, double py) => out.write('L${f(px)} ${f(py)}');

  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0, cx = 0.0, cy = 0.0;
  String? command, last;
  while (true) {
    skip();
    if (at >= d.length) break;
    if (_letter.hasMatch(d[at])) {
      command = d[at++];
    } else if (command == 'M') {
      command = 'L';
    } else if (command == 'm') {
      command = 'l';
    }
    final upper = command!.toUpperCase();
    final relative = command != upper;
    (double, double) abs(double px, double py) => relative ? (x + px, y + py) : (px, py);
    var curve = false;
    switch (upper) {
      case 'Z':
        out.write('Z');
        x = startX;
        y = startY;
      case 'M':
        (x, y) = abs(number(), number());
        startX = x;
        startY = y;
        out.write('M${f(x)} ${f(y)}');
      case 'L':
        (x, y) = abs(number(), number());
        line(x, y);
      case 'H':
        final px = number();
        x = relative ? x + px : px;
        line(x, y);
      case 'V':
        final py = number();
        y = relative ? y + py : py;
        line(x, y);
      case 'C' || 'S' || 'Q' || 'T':
        final quadratic = upper == 'Q' || upper == 'T';
        final points = <(double, double)>[(x, y)];
        if (upper == 'S' || upper == 'T') points.add(last == (quadratic ? 'Q' : 'C') ? (2 * x - cx, 2 * y - cy) : (x, y));
        for (var i = 0; i < (upper == 'C' ? 3 : (upper == 'T' ? 1 : 2)); i++) {
          points.add(abs(number(), number()));
        }
        for (var i = 1; i <= steps; i++) {
          // de Casteljau's walk along the curve.
          var row = [...points];
          final t = i / steps;
          while (row.length > 1) {
            row = [for (var j = 0; j + 1 < row.length; j++) (row[j].$1 + (row[j + 1].$1 - row[j].$1) * t, row[j].$2 + (row[j + 1].$2 - row[j].$2) * t)];
          }
          line(row.single.$1, row.single.$2);
        }
        (cx, cy) = points[points.length - 2];
        (x, y) = points.last;
        last = quadratic ? 'Q' : 'C';
        curve = true;
      case 'A':
        var r = number();
        number();
        number();
        final large = flag(), sweep = flag();
        final (ex, ey) = abs(number(), number());
        // The middle of a round arc from its ends (SVG's own working, with an ellipse's second radius and turn left
        // out: near enough for a size).
        final mx = (x - ex) / 2, my = (y - ey) / 2;
        final half = mx * mx + my * my;
        if (half > 0) {
          if (r * r < half) r = math.sqrt(half);
          var k = math.sqrt(math.max(0, (r * r - half) / half));
          if (large == sweep) k = -k;
          final ox = (x + ex) / 2 + k * my, oy = (y + ey) / 2 - k * mx;
          final from = math.atan2(y - oy, x - ox);
          var turn = math.atan2(ey - oy, ex - ox) - from;
          if (sweep == 1 && turn < 0) turn += 2 * math.pi;
          if (sweep == 0 && turn > 0) turn -= 2 * math.pi;
          for (var i = 1; i <= steps; i++) {
            final a = from + turn * i / steps;
            line(ox + r * math.cos(a), oy + r * math.sin(a));
          }
        }
        x = ex;
        y = ey;
    }
    if (!curve) last = null;
  }
  return out.toString();
}
