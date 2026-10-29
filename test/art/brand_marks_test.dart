import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/brand_marks.dart';
import 'package:ghost_md/art/svg_path.dart';

/// The brands' marks (lib/art/brand_marks.dart; Matt, 2026-10-29: "Iconize real company logos for openAI todoist,
/// GitHub, Google meets, zoom etc and use those for the plugin icons"): each SVG in assets/brands/ is one path on the
/// 24 grid that parses into a drawing filling that grid, brands.json and SOURCES.md say where every one came from, and
/// the made file (lib/art/brand_marks.g.dart) is the two of them as they stand.
void main() {
  final svgs = {for (final file in Directory('assets/brands').listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) file.uri.pathSegments.last.replaceAll('.svg', ''): file.readAsStringSync()};
  final brands = (jsonDecode(File('assets/brands/brands.json').readAsStringSync()) as Map).cast<String, dynamic>();
  final sources = File('assets/brands/SOURCES.md').readAsStringSync();

  String pathIn(String svg) => RegExp(r'<path\b[^>]*\sd="([^"]*)"').firstMatch(svg)!.group(1)!;

  test('every SVG, every entry of brands.json and every mark the app draws are the same set', () {
    expect(svgs.keys.toSet(), brands.keys.toSet());
    expect(brandMarkData.keys.toSet(), brands.keys.toSet());
  });

  for (final slug in svgs.keys) {
    test('$slug: one path on 0 0 24 24, which parses into a drawing that fills the grid and no more', () {
      final svg = svgs[slug]!;
      expect(RegExp(r'viewBox="0 0 24 24"').hasMatch(svg), isTrue);
      expect(RegExp(r'<path\b').allMatches(svg).length, 1);
      final bounds = parseSvgPath(pathIn(svg)).getBounds();
      expect(bounds.isEmpty, isFalse);
      // The longer side spans most of the grid (Simple Icons draws every mark edge to edge), and nothing is outside it
      // but a curve's handful of a hundredth (the bounds a path reports may take in its curves' control points).
      expect(bounds.longestSide, greaterThan(20), reason: '$bounds');
      const grid = Rect.fromLTRB(-0.5, -0.5, 24.5, 24.5);
      expect(grid.contains(bounds.topLeft) && grid.contains(bounds.bottomRight), isTrue, reason: '$bounds');
    });

    test('$slug: the app draws the file’s own path in brands.json’s colour, and SOURCES.md says where it came from', () {
      final mark = brandMarkData[slug]!;
      final brand = (brands[slug] as Map).cast<String, dynamic>();
      expect(mark.d, pathIn(svgs[slug]!), reason: 'run `dart run tool/brands/generate.dart`');
      expect((mark.slug, mark.title), (slug, brand['title']));
      final hex = brand['hex'] as String?;
      expect(mark.hex, hex == null ? isNull : int.parse('FF$hex', radix: 16));
      expect(sources, contains('`$slug`'));
      if (hex != null) expect(sources, contains('#$hex'));
      final from = brand['from'] as String;
      expect(sources, contains(from.startsWith('https://cdn.jsdelivr.net/') ? from : 'https://www.lovart.ai/'));
      if (from.startsWith('https://cdn.jsdelivr.net/')) {
        expect(brand['licence'], 'CC0-1.0');
        expect(from, contains('simple-icons@16.35.0'));
      }
    });
  }

  test('SOURCES.md says the marks are their owners’ trademarks and names the store build’s define', () {
    expect(sources, contains('trademark of its owner'));
    expect(sources, contains('GHOST_STORE_NEUTRAL'));
    expect(sources, contains('CC0 1.0'));
  });

  group('the brand’s colour, kept readable', () {
    final todoist = brandMarkData['todoist']!, github = brandMarkData['github']!, lovart = brandMarkData['lovart']!;
    const white = Color(0xFFFFFFFF), dark = Color(0xFF121212), ink = Color(0xFF777777);

    test('contrast counts as WCAG does', () {
      expect(contrastOf(const Color(0xFF000000), white), closeTo(21, 0.01));
      expect(contrastOf(white, white), 1);
    });

    test('a colour that stands out from its ground is kept; one that does not, or none, is the ink', () {
      expect(brandInkOn(todoist, ground: white, ink: ink), todoist.colour);
      expect(brandInkOn(todoist, ground: dark, ink: ink), todoist.colour);
      expect(brandInkOn(github, ground: white, ink: ink), github.colour);
      expect(brandInkOn(github, ground: dark, ink: ink), ink);
      expect(brandInkOn(lovart, ground: white, ink: ink), ink);
    });
  });

  test('a build without the store define draws the marks, and a test can say it is a store-shot build', () {
    addTearDown(() => debugStoreShots = null);
    expect((storeShotBuild, brandMarksShown), (false, true));
    debugStoreShots = true;
    expect(brandMarksShown, isFalse);
  });
}
