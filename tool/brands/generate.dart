// Makes lib/art/brand_marks.g.dart: the marks of the companies the plugins reach (Matt, 2026-10-29: "Iconize real
// company logos for openAI todoist, GitHub, Google meets, zoom etc and use those for the plugin icons"), from the SVGs
// in assets/brands/ and what assets/brands/brands.json says of each (its name, its colour, where it came from).
//
//   dart run tool/brands/generate.dart
//
// Each SVG is one path on a 24 by 24 view box, as Simple Icons draws every brand (and as Lovart's own header mark is);
// its `d` is copied as it stands, so the drawing in the app is the file's. Nothing is drawn or traced here.
// test/art/brand_marks_test.dart holds the made file to the SVGs and the JSON, so a mark changed in one is changed in
// the other by running this again. Where the marks came from, and at which version, is assets/brands/SOURCES.md.
import 'dart:convert';
import 'dart:io';

/// The one path of an SVG [text], its view box held to 0 0 24 24.
String pathOf(String text, String slug) {
  final box = RegExp(r'viewBox="([^"]*)"').firstMatch(text)?.group(1);
  if (box != '0 0 24 24') throw FormatException('$slug.svg: a view box of "$box", not 0 0 24 24');
  final paths = RegExp(r'<path\b[^>]*\sd="([^"]*)"').allMatches(text).toList();
  if (paths.length != 1) throw FormatException('$slug.svg: ${paths.length} paths, not one');
  return paths.single.group(1)!;
}

String quoted(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

void main() {
  final brands = (jsonDecode(File('assets/brands/brands.json').readAsStringSync()) as Map).cast<String, dynamic>();
  final out = StringBuffer()
    ..writeln('// MADE, not written: `dart run tool/brands/generate.dart` copies it from assets/brands/*.svg and brands.json.')
    ..writeln('// coverage:ignore-file')
    ..writeln()
    ..writeln("import 'brand_marks.dart';")
    ..writeln()
    ..writeln('/// Every brand mark the app carries, by its slug (Simple Icons\' own name for it, or the company\'s).')
    ..writeln('const Map<String, BrandMarkData> brandMarkData = {');
  for (final slug in brands.keys.toList()..sort()) {
    final brand = (brands[slug] as Map).cast<String, dynamic>();
    final d = pathOf(File('assets/brands/$slug.svg').readAsStringSync(), slug);
    final hex = brand['hex'] as String?;
    out.writeln('  ${quoted(slug)}: BrandMarkData(slug: ${quoted(slug)}, title: ${quoted(brand['title'] as String)}, hex: ${hex == null ? 'null' : '0xFF${hex.toUpperCase()}'}, d: ${quoted(d)}),');
  }
  out.writeln('};');
  File('lib/art/brand_marks.g.dart').writeAsStringSync(out.toString());
  stdout.writeln('lib/art/brand_marks.g.dart: ${brands.length} marks');
}
