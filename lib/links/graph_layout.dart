/// Where each note stands in the graph: a force-directed layout, worked out once, off the UI isolate for a graph
/// of any size, and then only drawn (lib/links/graph_view.dart). Every note pushes every other away and each link
/// pulls its two notes together, with a weak pull to the middle so that notes with no links (drawn dim) gather
/// round the rest rather than drifting off; the pushes are summed by a quadtree (Barnes and Hut's), so a step costs
/// about n log n and a thousand notes settle in a fraction of a second.
///
/// The same notes and links lay out the same way each time: each note starts where its id puts it, not where a
/// random number does.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// The length a link settles at, in the graph's own units (a node is drawn about 6 of them across).
const double linkLength = 46;

/// A graph to lay out: [count] notes, links between `from[i]` and `to[i]`, and each note's id for where it starts.
typedef GraphInput = ({List<String> ids, List<int> from, List<int> to});

/// Lays the graph out, answering `x, y` for each note in turn.
Float64List layOutGraph(GraphInput graph, {int? steps}) {
  final n = graph.ids.length;
  final at = Float64List(n * 2);
  if (n == 0) return at;
  // Where each starts: by its id, in a disc that grows with the graph.
  final spread = linkLength * math.sqrt(n) * 0.9;
  for (var i = 0; i < n; i += 1) {
    final h = _hash(graph.ids[i]);
    final angle = (h & 0xffff) / 0xffff * math.pi * 2;
    final radius = spread * math.sqrt(((h >> 16) & 0xffff) / 0xffff);
    at[2 * i] = math.cos(angle) * radius;
    at[2 * i + 1] = math.sin(angle) * radius;
  }
  if (n == 1) return at;
  final degree = Int32List(n);
  for (var e = 0; e < graph.from.length; e += 1) {
    degree[graph.from[e]] += 1;
    degree[graph.to[e]] += 1;
  }
  final force = Float64List(n * 2);
  final total = steps ?? (n <= 200 ? 400 : (n <= 1200 ? 300 : 200));
  final k = linkLength;
  var heat = spread * 0.12;
  // Down to a twentieth of a link's length by the last step, so the notes stand still when they are drawn.
  final cool = math.pow((linkLength * 0.05) / heat, 1 / total).toDouble();
  for (var step = 0; step < total; step += 1) {
    force.fillRange(0, force.length, 0);
    // Every note pushes every other: k² / d, summed by the quadtree.
    final tree = _Quad.of(at, n);
    for (var i = 0; i < n; i += 1) {
      tree.push(at, i, force, k * k);
    }
    // Each link pulls: d² / k.
    for (var e = 0; e < graph.from.length; e += 1) {
      final a = graph.from[e], b = graph.to[e];
      final dx = at[2 * b] - at[2 * a], dy = at[2 * b + 1] - at[2 * a + 1];
      final d = math.sqrt(dx * dx + dy * dy) + 0.01;
      final pull = d / k;
      force[2 * a] += dx * pull;
      force[2 * a + 1] += dy * pull;
      force[2 * b] -= dx * pull;
      force[2 * b + 1] -= dy * pull;
    }
    // A pull to the middle, stronger on a note with nothing to hold it.
    for (var i = 0; i < n; i += 1) {
      final g = degree[i] == 0 ? 0.06 : 0.02;
      force[2 * i] -= at[2 * i] * g;
      force[2 * i + 1] -= at[2 * i + 1] * g;
    }
    // Each moves along its force, no further than the heat lets it.
    for (var i = 0; i < n; i += 1) {
      final fx = force[2 * i], fy = force[2 * i + 1];
      final f = math.sqrt(fx * fx + fy * fy);
      if (f < 1e-9) continue;
      final move = math.min(f, heat) / f;
      at[2 * i] += fx * move;
      at[2 * i + 1] += fy * move;
    }
    heat *= cool;
  }
  return at;
}

/// [layOutGraph] in a worker isolate.
Future<Float64List> layOutGraphElsewhere(GraphInput graph) => Isolate.run(() => layOutGraph(graph), debugName: 'graph layout');

/// FNV-1a over the id's code units: the same answer in every run, which `String.hashCode` does not promise.
int _hash(String id) {
  var h = 0x811c9dc5;
  for (var i = 0; i < id.length; i += 1) {
    h ^= id.codeUnitAt(i);
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// A square of the plane, with the notes in it summed: their count and their middle.
class _Quad {
  _Quad(this.x, this.y, this.size);

  /// Every note in [at] in one tree.
  factory _Quad.of(Float64List at, int n) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i += 1) {
      minX = math.min(minX, at[2 * i]);
      maxX = math.max(maxX, at[2 * i]);
      minY = math.min(minY, at[2 * i + 1]);
      maxY = math.max(maxY, at[2 * i + 1]);
    }
    final size = math.max(maxX - minX, maxY - minY) + 1;
    final root = _Quad(minX, minY, size);
    for (var i = 0; i < n; i += 1) {
      root.add(at, i, 0);
    }
    return root;
  }

  final double x, y, size;
  int count = 0;
  double sumX = 0, sumY = 0;

  /// The one note in a leaf, or -1.
  int only = -1;
  List<_Quad?>? kids;

  void add(Float64List at, int i, int depth) {
    final px = at[2 * i], py = at[2 * i + 1];
    count += 1;
    sumX += px;
    sumY += py;
    if (count == 1) {
      only = i;
      return;
    }
    // Two notes on one spot (or deep enough): kept together in this leaf.
    if (depth > 24) return;
    final quads = kids ??= List<_Quad?>.filled(4, null);
    if (only >= 0) {
      final was = only;
      only = -1;
      _into(quads, at, was, depth);
    }
    _into(quads, at, i, depth);
  }

  void _into(List<_Quad?> quads, Float64List at, int i, int depth) {
    final half = size / 2;
    final right = at[2 * i] >= x + half, down = at[2 * i + 1] >= y + half;
    final q = (right ? 1 : 0) + (down ? 2 : 0);
    (quads[q] ??= _Quad(right ? x + half : x, down ? y + half : y, half)).add(at, i, depth + 1);
  }

  /// The push on note [i] from every note under this square: from its middle where it is far enough off.
  void push(Float64List at, int i, Float64List force, double k2) {
    if (count == 0) return;
    final px = at[2 * i], py = at[2 * i + 1];
    final cx = sumX / count, cy = sumY / count;
    var dx = px - cx, dy = py - cy;
    var d2 = dx * dx + dy * dy;
    final leaf = kids == null;
    if (leaf || size * size < 0.81 * d2) {
      if (leaf && only == i) return;
      // A note on the very spot of another: pushed apart by its id, the same way each time.
      if (d2 < 1e-6) {
        dx = ((i * 7919) % 13) - 6.0;
        dy = ((i * 104729) % 11) - 5.0;
        d2 = dx * dx + dy * dy + 1;
      }
      final mass = leaf && only < 0 ? count - (_holds(at, i) ? 1 : 0) : count;
      if (mass <= 0) return;
      final scale = k2 * mass / d2;
      force[2 * i] += dx * scale;
      force[2 * i + 1] += dy * scale;
      return;
    }
    for (final kid in kids!) {
      kid?.push(at, i, force, k2);
    }
  }

  /// Whether a leaf of several notes on one spot holds [i].
  bool _holds(Float64List at, int i) => at[2 * i] >= x && at[2 * i] <= x + size && at[2 * i + 1] >= y && at[2 * i + 1] <= y + size;
}
