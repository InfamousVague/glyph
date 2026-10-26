/// OpenStreetMap's tiles for a map card: the [MapTilesBuilder] lib/editor/media/map_card.dart leaves as a seam.
/// What Leaflet did on the page (`L.map` with nothing on it that moves, one `L.tileLayer` over
/// `https://tile.openstreetmap.org/{z}/{x}/{y}.png`), as a still picture: the standard 256 px tiles that cover the
/// box, centred on the tag, fetched once each and kept for the run.
///
/// The gates are the caller's, as on the page: a card is given this builder only in `map` mode, which is the map
/// switch on and Local only off (lib/core/location.dart `canShowTiles`), and never for a draft that may not be
/// kept. Nothing is fetched until a card that may show a map is laid out.
///
/// What differs:
/// - The app names itself to the tile server ([tilesUserAgent]), as OSM's tile usage policy asks of an app; the
///   page sent its origin as the Referer, which an app has none of.
/// - Standard tiles, not retina ones, as on the page: at a phone's density the z+1 tiles drawn at half size were
///   sharper but their labels too small to read.
/// - A tile that failed is the map's paper, and is asked for again only by another card; `onLoaded` is called once
///   the first tile is in.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../../account/api.dart' show FetchRequest, ioFetcher;
import '../../core/place_refs.dart';
import 'map_card.dart' show MapTilesBuilder;

/// OpenStreetMap's standard tiles, under its tile usage policy (`OSM_TILES`).
String osmTileUrl(int z, int x, int y) => 'https://tile.openstreetmap.org/$z/$x/$y.png';

/// The app, named, as the tile server asks.
const String tilesUserAgent = 'GhostMd/0.1.0 (https://ghostmarkdown.com)';

/// A tile's side, in the map's pixels.
const double tileSide = 256;

/// Fetches one tile's bytes; null for one that did not come.
typedef TileFetch = Future<Uint8List?> Function(int z, int x, int y);

/// Where a place falls on the world's map at a zoom, in pixels from its top left (Web Mercator, as Leaflet's
/// `project`).
Offset worldPixel(double lat, double lon, int zoom) {
  final scale = tileSide * math.pow(2, zoom);
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final sin = math.sin(clamped * math.pi / 180);
  final x = (lon + 180) / 360 * scale;
  final y = (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale;
  return Offset(x, y);
}

/// The tiles that cover a box of `size` centred on a place, each with where its top left goes in the box.
List<({int x, int y, Offset at})> tilesOver(double lat, double lon, int zoom, Size size) {
  final centre = worldPixel(lat, lon, zoom);
  final left = centre.dx - size.width / 2, top = centre.dy - size.height / 2;
  final count = math.pow(2, zoom).toInt();
  final tiles = <({int x, int y, Offset at})>[];
  for (var ty = (top / tileSide).floor(); ty * tileSide < top + size.height; ty += 1) {
    if (ty < 0 || ty >= count) continue;
    for (var tx = (left / tileSide).floor(); tx * tileSide < left + size.width; tx += 1) {
      // The world goes round: a column past its edge is the one at the other side.
      tiles.add((x: ((tx % count) + count) % count, y: ty, at: Offset(tx * tileSide - left, ty * tileSide - top)));
    }
  }
  return tiles;
}

/// The tiles fetched this run, by their address, and the asks in flight: a second card of the same place draws
/// from the first's.
class MapTiles {
  MapTiles({TileFetch? fetch}) : _fetch = fetch ?? _osm();

  final TileFetch _fetch;
  final Map<String, ui.Image> _kept = <String, ui.Image>{};
  final Map<String, Future<ui.Image?>> _asked = <String, Future<ui.Image?>>{};

  static TileFetch _osm() {
    // In the web build, the browser's `fetch`: OpenStreetMap's tiles let any site in, and the browser sends its own
    // agent, which a page cannot change.
    if (kIsWeb) {
      final page = ioFetcher();
      return (z, x, y) async {
        try {
          final answer = await page(FetchRequest(method: 'GET', url: Uri.parse(osmTileUrl(z, x, y)), timeout: const Duration(seconds: 12)));
          return answer.status == 200 ? answer.bytes : null;
        } catch (_) {
          return null;
        }
      };
    }
    final http = HttpClient()
      ..userAgent = tilesUserAgent
      ..connectionTimeout = const Duration(seconds: 8);
    return (z, x, y) async {
      try {
        final request = await http.getUrl(Uri.parse(osmTileUrl(z, x, y)));
        final answer = await request.close().timeout(const Duration(seconds: 12));
        if (answer.statusCode != 200) {
          await answer.drain<void>();
          return null;
        }
        final bytes = BytesBuilder(copy: false);
        await answer.forEach(bytes.add);
        return bytes.takeBytes();
      } catch (_) {
        // Offline, refused, too slow: the map's paper.
        return null;
      }
    };
  }

  /// The tile already here, or null.
  ui.Image? kept(int z, int x, int y) => _kept['$z/$x/$y'];

  /// The tile, fetched once; null for one that did not come.
  Future<ui.Image?> tile(int z, int x, int y) {
    final key = '$z/$x/$y';
    final had = _kept[key];
    if (had != null) return Future<ui.Image?>.value(had);
    return _asked.putIfAbsent(key, () async {
      try {
        final bytes = await _fetch(z, x, y);
        if (bytes == null) return null;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return _kept[key] = frame.image;
      } catch (_) {
        return null;
      } finally {
        unawaited(Future<void>.microtask(() => _asked.remove(key)));
      }
    });
  }

  /// The builder a map card is given.
  MapTilesBuilder get builder => (context, {required tag, required zoom, required onLoaded}) => _TileMap(tiles: this, tag: tag, zoom: zoom, onLoaded: onLoaded);
}

class _TileMap extends StatefulWidget {
  const _TileMap({required this.tiles, required this.tag, required this.zoom, required this.onLoaded});

  final MapTiles tiles;
  final GeoTag tag;
  final int zoom;
  final VoidCallback onLoaded;

  @override
  State<_TileMap> createState() => _TileMapState();
}

class _TileMapState extends State<_TileMap> {
  Size? _askedFor;
  bool _told = false;
  int _drawn = 0;

  /// The tiles this box wants, asked for once per size: the Fold opening draws them again for the new width.
  void _ask(Size size) {
    if (_askedFor == size || size.isEmpty) return;
    _askedFor = size;
    for (final tile in tilesOver(widget.tag.lat, widget.tag.lon, widget.zoom, size)) {
      if (widget.tiles.kept(widget.zoom, tile.x, tile.y) != null) {
        _arrived();
        continue;
      }
      unawaited(widget.tiles.tile(widget.zoom, tile.x, tile.y).then((image) {
        if (image != null) _arrived();
      }));
    }
  }

  void _arrived() {
    // After the frame: the first may come while the card is being laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _drawn += 1);
      if (_told) return;
      _told = true;
      widget.onLoaded();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(_TileMap old) {
    super.didUpdateWidget(old);
    if (old.tag.lat != widget.tag.lat || old.tag.lon != widget.tag.lon || old.zoom != widget.zoom) _askedFor = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.isFinite) _ask(size);
          return ClipRect(child: CustomPaint(size: size.isFinite ? size : Size.zero, painter: _TilePainter(widget.tiles, widget.tag, widget.zoom, _drawn)));
        },
      );
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.tiles, this.tag, this.zoom, this.drawn);

  final MapTiles tiles;
  final GeoTag tag;
  final int zoom;
  final int drawn;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final tile in tilesOver(tag.lat, tag.lon, zoom, size)) {
      final image = tiles.kept(zoom, tile.x, tile.y);
      if (image == null) continue;
      // Half a pixel over its neighbour, as Leaflet's 256.5: no hairline between two tiles at a fractional place.
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(tile.at.dx, tile.at.dy, tileSide + 0.5, tileSide + 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.drawn != drawn || old.tag != tag || old.zoom != zoom || !identical(old.tiles, tiles);
}
