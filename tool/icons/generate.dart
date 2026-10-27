// Makes lib/art/packs/*.g.dart: the app's icons as each icon pack draws them (Matt, 2026-10-27: "I would like you
// to add three icon styles (outline, solid and filled) and add a few different icon packs for the app to choose
// from"), from the packs' own SVGs and tool/icons/map.json.
//
//   tool/icons/fetch.sh "$TMPDIR/ghost-icon-packs"
//   dart run tool/icons/generate.dart "$TMPDIR/ghost-icon-packs"
//
// Only the glyphs the app draws are made: every Lucide icon lib/art/lucide.g.dart carries, and what the app's own
// drawings draw (map.json's `drawn`, lib/art/icons.dart). Each is looked up in each pack by the name map.json gives
// it there; one a pack has no name for, or whose file is not in the pack, is left out of that pack's table, and the
// app draws Lucide's in its place in the chosen style. How many did, per pack and per style, is written at the head
// of each file and said here. Every path is moved onto the 24 grid (tool/icons/path_data.dart), and each drawing the
// same in two places is written once.
//
// The packs' sources stay outside the repository; what comes in is the paths and each pack's licence, copied to
// tool/icons/licences/ and into lib/art/packs/licences.g.dart, which the app registers with Flutter's
// LicenseRegistry (lib/art/icon_packs.dart `registerIconPackLicences`).
import 'dart:convert';
import 'dart:io';

import 'package:ghost_md/art/icon_wash.dart';

import 'path_data.dart';

/// One element of an SVG: its tag and its attributes.
typedef Element = ({String tag, Map<String, String> attrs});

/// An SVG file's view box and its drawing elements, in order.
({List<double> box, List<Element> elements}) readSvg(File file) {
  final text = file.readAsStringSync();
  final svg = RegExp(r'<svg\b([^>]*)>', dotAll: true).firstMatch(text)!.group(1)!;
  final box = RegExp(r'viewBox="([^"]+)"').firstMatch(svg)!.group(1)!.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
  final elements = <Element>[];
  for (final match in RegExp(r'<(path|circle|rect|line|polyline|polygon|ellipse)\b([^>]*?)/?>', dotAll: true).allMatches(text)) {
    final attrs = <String, String>{};
    for (final attr in RegExp(r'([\w:-]+)="([^"]*)"').allMatches(match.group(2)!)) {
      attrs[attr.group(1)!] = attr.group(2)!;
    }
    elements.add((tag: match.group(1)!, attrs: attrs));
  }
  return (box: box, elements: elements);
}

String n(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
double a(Map<String, String> attrs, String name) => double.parse(attrs[name] ?? '0');

/// A shape as a path, as tool/lucide.dart makes Lucide's: the outline the element draws.
String pathOf(Element shape) {
  final at = shape.attrs;
  switch (shape.tag) {
    case 'path':
      return at['d']!;
    case 'circle':
      final cx = a(at, 'cx'), cy = a(at, 'cy'), r = a(at, 'r');
      return 'M${n(cx - r)} ${n(cy)}A${n(r)} ${n(r)} 0 1 0 ${n(cx + r)} ${n(cy)}A${n(r)} ${n(r)} 0 1 0 ${n(cx - r)} ${n(cy)}Z';
    case 'ellipse':
      final cx = a(at, 'cx'), cy = a(at, 'cy'), rx = a(at, 'rx'), ry = a(at, 'ry');
      return 'M${n(cx - rx)} ${n(cy)}A${n(rx)} ${n(ry)} 0 1 0 ${n(cx + rx)} ${n(cy)}A${n(rx)} ${n(ry)} 0 1 0 ${n(cx - rx)} ${n(cy)}Z';
    case 'rect':
      final x = a(at, 'x'), y = a(at, 'y'), w = a(at, 'width'), h = a(at, 'height');
      final rx = at.containsKey('rx') ? a(at, 'rx') : 0.0;
      if (rx == 0) return 'M${n(x)} ${n(y)}H${n(x + w)}V${n(y + h)}H${n(x)}Z';
      return 'M${n(x + rx)} ${n(y)}H${n(x + w - rx)}A${n(rx)} ${n(rx)} 0 0 1 ${n(x + w)} ${n(y + rx)}V${n(y + h - rx)}A${n(rx)} ${n(rx)} 0 0 1 ${n(x + w - rx)} ${n(y + h)}H${n(x + rx)}A${n(rx)} ${n(rx)} 0 0 1 ${n(x)} ${n(y + h - rx)}V${n(y + rx)}A${n(rx)} ${n(rx)} 0 0 1 ${n(x + rx)} ${n(y)}Z';
    case 'line':
      return 'M${at['x1']} ${at['y1']}L${at['x2']} ${at['y2']}';
    case 'polyline' || 'polygon':
      final points = at['points']!.trim().split(RegExp(r'[\s,]+'));
      final lines = [for (var i = 0; i + 1 < points.length; i += 2) '${points[i]} ${points[i + 1]}'];
      return 'M${lines.join('L')}${shape.tag == 'polygon' ? 'Z' : ''}';
    default:
      throw StateError('a shape this does not draw: ${shape.tag}');
  }
}

/// A file's drawing elements as paths on the 24 grid, leaving out what draws nothing: Tabler's `stroke="none"` box
/// that only holds the svg's size open, and anything filled with none in a filled set.
List<({String d, Map<String, String> attrs})> pathsOf(({List<double> box, List<Element> elements}) svg, {required bool lines}) {
  final scale = 24 / svg.box[2];
  final out = <({String d, Map<String, String> attrs})>[];
  for (final element in svg.elements) {
    final at = element.attrs;
    if (at['stroke'] == 'none' && (at['fill'] == 'none' || !lines)) continue;
    if (!lines && at['fill'] == 'none') continue;
    out.add((d: rescalePath(pathOf(element), scale: scale, dx: -svg.box[0] * scale, dy: -svg.box[1] * scale, digits: digits), attrs: at));
  }
  return out;
}

/// How many places a number keeps on the 24 grid: hundredths. Drawn at 48 points against ten-thousandths, every
/// glyph of the four packs lands within a third of one pixel's ink of where it was, and on average within a
/// two-thousandth; tenths kept the files a sixth smaller and moved whole pixels. `--digits` for another.
var digits = 2;

/// Where the tables are written: the app's own folder, or `--out` for a look at another precision.
var outDir = 'lib/art/packs';

/// A drawing of one glyph in one style, as the Dart it is written as.
///
/// The wash is on the glyph's body by Lucide's rule (lib/art/icon_wash.dart), and only where Lucide's own glyph of
/// the same name has one ([body]): a tick, an arrow or a letter has no body in any pack, and a pack's B filled in
/// would be a blot.
String linesGlyph(List<({String d, Map<String, String> attrs})> paths, {required bool body}) {
  final wash = body ? bodiesOf([for (final p in paths) IconShape('path', {'d': flattenPath(p.d)})]) : const <int>[];
  final solids = [
    for (var i = 0; i < paths.length; i++)
      if (paths[i].attrs['fill'] == 'currentColor') i,
  ];
  return 'PackGlyph.lines([${paths.map((p) => "'${p.d}'").join(', ')}]${wash.isEmpty ? '' : ', wash: [${wash.join(', ')}]'}${solids.isEmpty ? '' : ', solids: [${solids.join(', ')}]'})';
}

String shapesGlyph(List<({String d, Map<String, String> attrs})> paths) => 'PackGlyph.shapes([${paths.map((p) => "'${p.d}'").join(', ')}])';

/// What one pack draws a glyph as in each style, as Dart; null where the pack has not got it.
typedef Made = ({String outline, String? solid, String? filled, String? back});

/// Where a pack's files are and what each style is made of.
abstract class Pack {
  Pack(this.root);
  final String root;
  String get id;
  String get title;

  /// The `npm` names and folders whose versions map.json pins.
  Map<String, String> get folders;
  String get licenceFile;
  String get comment;
  /// [name]'s drawings in this pack; [body] is whether the app's own glyph for it has a body to wash.
  Made? make(String name, {required bool body});
}

class Phosphor extends Pack {
  Phosphor(super.root);
  @override
  String get id => 'phosphor';
  @override
  String get title => 'Phosphor';
  @override
  Map<String, String> get folders => {'phosphor': '$root/phosphor/package'};
  @override
  String get licenceFile => '$root/phosphor/package/LICENSE';
  @override
  String get comment => 'Outline is the regular weight, Solid the bold, Filled the fill; the wash is the duotone weight\'s own 20% layer.';

  File _at(String weight, String name) => File('$root/phosphor/package/assets/$weight/$name${weight == 'regular' ? '' : '-$weight'}.svg');

  @override
  Made? make(String name, {required bool body}) {
    if (!_at('regular', name).existsSync()) return null;
    final duotone = readSvg(_at('duotone', name));
    final back = pathsOf((box: duotone.box, elements: [for (final e in duotone.elements) if (e.attrs.containsKey('opacity')) e]), lines: false);
    return (
      outline: shapesGlyph(pathsOf(readSvg(_at('regular', name)), lines: false)),
      solid: shapesGlyph(pathsOf(readSvg(_at('bold', name)), lines: false)),
      filled: shapesGlyph(pathsOf(readSvg(_at('fill', name)), lines: false)),
      // The duotone layer is the wash, where the app's glyph has a body: Phosphor's tick and arrows have a tinted
      // box behind them that is not one.
      back: back.isEmpty || !body ? null : shapesGlyph(back),
    );
  }
}

class Tabler extends Pack {
  Tabler(super.root);
  @override
  String get id => 'tabler';
  @override
  String get title => 'Tabler';
  @override
  Map<String, String> get folders => {'tabler': '$root/tabler/package'};
  @override
  String get licenceFile => '$root/tabler/package/LICENSE';
  @override
  String get comment => 'Outline is the outline set, stroked as Lucide is; Solid the same lines heavier (Tabler\'s own stroke width); Filled the filled set where it has the glyph. The wash is the rule Lucide\'s is (lib/art/icon_wash.dart).';

  @override
  Made? make(String name, {required bool body}) {
    final outline = File('$root/tabler/package/icons/outline/$name.svg');
    if (!outline.existsSync()) return null;
    final filled = File('$root/tabler/package/icons/filled/$name.svg');
    return (outline: linesGlyph(pathsOf(readSvg(outline), lines: true), body: body), solid: null, filled: filled.existsSync() ? shapesGlyph(pathsOf(readSvg(filled), lines: false)) : null, back: null);
  }
}

class Material extends Pack {
  Material(super.root);
  @override
  String get id => 'material';
  @override
  String get title => 'Material Symbols';
  @override
  Map<String, String> get folders => {'material-400': '$root/material-400/package', 'material-700': '$root/material-700/package'};
  @override
  String get licenceFile => '$root/material-400/package/LICENSE';
  @override
  String get comment => 'The Rounded symbols: Outline at weight 400, Solid at 700, Filled at 400 with FILL 1; the wash is the filled symbol under the outline.';

  @override
  Made? make(String name, {required bool body}) {
    final outline = File('$root/material-400/package/rounded/$name.svg');
    if (!outline.existsSync()) return null;
    final solid = File('$root/material-700/package/rounded/$name.svg');
    final filled = File('$root/material-400/package/rounded/$name-fill.svg');
    return (
      outline: shapesGlyph(pathsOf(readSvg(outline), lines: false)),
      solid: solid.existsSync() ? shapesGlyph(pathsOf(readSvg(solid), lines: false)) : null,
      filled: filled.existsSync() ? shapesGlyph(pathsOf(readSvg(filled), lines: false)) : null,
      back: null,
    );
  }
}

class Remix extends Pack {
  Remix(super.root);
  @override
  String get id => 'remix';
  @override
  String get title => 'Remix Icon';
  @override
  Map<String, String> get folders => {'remix': '$root/remix/package'};
  @override
  String get licenceFile => '$root/remix/package/License';
  @override
  String get comment => 'Outline is the line set, Filled the fill set; Solid is the line set thickened, since Remix draws one weight. An icon Remix draws one way only (its editor\'s letters) is that drawing in every style. The wash is the filled icon under the line.';

  late final Map<String, File> _files = {
    for (final dir in Directory('$root/remix/package/icons').listSync().whereType<Directory>())
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.svg')) file.uri.pathSegments.last.replaceAll('.svg', ''): file,
  };

  @override
  Made? make(String name, {required bool body}) {
    final line = _files['$name-line'] ?? _files[name];
    if (line == null) return null;
    final fill = _files['$name-fill'];
    return (outline: shapesGlyph(pathsOf(readSvg(line), lines: false)), solid: null, filled: fill == null ? null : shapesGlyph(pathsOf(readSvg(fill), lines: false)), back: null);
  }
}

/// The names lib/art/lucide.g.dart draws, by Lucide's own name.
List<String> lucideNames() => [
      for (final match in RegExp(r"^const _\w+ = LucideIcon\('([a-z0-9-]+)'", multiLine: true).allMatches(File('lib/art/lucide.g.dart').readAsStringSync())) match.group(1)!,
    ];

/// The app's glyphs that have a body, which the wash is on: Lucide's whose wash lib/art/lucide.g.dart has, and the
/// app's own drawings with a body (lib/art/icons.dart), which map.json's `drawn` names by what they draw.
Set<String> bodiedNames(Iterable<String> drawnOnly) => {
      for (final match in RegExp(r"^const _\w+ = LucideIcon\('([a-z0-9-]+)', \[.*\], \[([\d, ]*)\]\);$", multiLine: true).allMatches(File('lib/art/lucide.g.dart').readAsStringSync()))
        if (match.group(2)!.trim().isNotEmpty) match.group(1)!,
      ...drawnOnly,
    };

/// `material-400` as a Dart name: `material400`.
String dartName(String id) => id.replaceAllMapped(RegExp(r'-(\w)'), (m) => m.group(1)!.toUpperCase());

void main(List<String> args) {
  final rest = [...args];
  String? option(String name) {
    final at = rest.indexOf(name);
    if (at < 0 || at + 1 >= rest.length) return null;
    final value = rest[at + 1];
    rest.removeRange(at, at + 2);
    return value;
  }

  digits = int.parse(option('--digits') ?? '$digits');
  outDir = option('--out') ?? outDir;
  if (rest.length != 1) {
    stderr.writeln('usage: dart run tool/icons/generate.dart <the folder tool/icons/fetch.sh fetched into> [--digits 1] [--out lib/art/packs]');
    exit(64);
  }
  final root = rest.single;
  final map = jsonDecode(File('tool/icons/map.json').readAsStringSync()) as Map<String, Object?>;
  final icons = (map['icons']! as Map).cast<String, Map<String, Object?>>();
  final drawn = (map['drawn']! as Map).cast<String, String>();
  final sources = (map['sources']! as Map).cast<String, Map<String, Object?>>();

  // Every glyph the app draws has its line in the map, and the map names nothing the app does not draw.
  final names = {...lucideNames(), ...drawn.values};
  final missing = names.where((name) => !icons.containsKey(name)).toList()..sort();
  final stray = icons.keys.where((name) => !names.contains(name)).toList()..sort();
  if (missing.isNotEmpty || stray.isNotEmpty) {
    stderr.writeln('tool/icons/map.json is not the app\'s icons: missing ${missing.join(', ')}; not drawn ${stray.join(', ')}');
    exit(1);
  }

  final lucide = lucideNames().toSet();
  final bodied = bodiedNames([for (final name in drawn.values) if (!lucide.contains(name)) name]);
  final packs = <Pack>[Phosphor(root), Tabler(root), Material(root), Remix(root)];
  Directory(outDir).createSync(recursive: true);
  Directory('tool/icons/licences').createSync(recursive: true);
  final licences = <String, String>{'lucide': File('tool/icons/licences/lucide.txt').readAsStringSync()};
  final report = StringBuffer();
  for (final pack in packs) {
    // The sources are the versions map.json pins, or nothing is written.
    for (final MapEntry(key: folder, value: dir) in pack.folders.entries) {
      final version = (jsonDecode(File('$dir/package.json').readAsStringSync()) as Map)['version'];
      if (version != sources[folder]!['version']) {
        stderr.writeln('$folder is $version in $dir, and tool/icons/map.json pins ${sources[folder]!['version']}: fetch again (tool/icons/fetch.sh).');
        exit(1);
      }
    }
    final made = <String, Made>{};
    final fellBack = <String>[];
    for (final name in icons.keys.toList()..sort()) {
      final glyph = icons[name]![pack.id] as String?;
      final drawing = glyph == null ? null : pack.make(glyph, body: bodied.contains(name));
      if (glyph != null && drawing == null) {
        stderr.writeln('${pack.id}: map.json names "$glyph" for $name, and the pack has no such icon');
        exit(1);
      }
      if (drawing == null) {
        fellBack.add(name);
      } else {
        made[name] = drawing;
      }
    }

    // Each drawing once, however many glyphs share it.
    final consts = <String, String>{};
    String ref(String? glyph) {
      if (glyph == null) return 'null';
      return consts.putIfAbsent(glyph, () => '_g${consts.length}');
    }

    final rows = <String>[];
    for (final MapEntry(key: name, value: drawing) in made.entries) {
      final parts = [ref(drawing.outline), if (drawing.solid != null) 'solid: ${ref(drawing.solid)}', if (drawing.filled != null) 'filled: ${ref(drawing.filled)}', if (drawing.back != null) 'back: ${ref(drawing.back)}'];
      rows.add("  '$name': PackGlyphs(${parts.join(', ')}),");
    }
    final solidNative = made.values.where((m) => m.solid != null).length;
    final filledNative = made.values.where((m) => m.filled != null).length;
    final versions = {for (final folder in pack.folders.keys) '${sources[folder]!['npm']} ${sources[folder]!['version']}'}.join(', ');
    final licence = sources[pack.folders.keys.first]!['licence'];
    final summary = '${made.length} of the app\'s ${icons.length} glyphs; ${fellBack.length} drawn as Lucide\'s: ${fellBack.isEmpty ? 'none' : fellBack.join(', ')}. '
        'Solid native for $solidNative, Filled native for $filledNative.';
    final out = StringBuffer()
      ..writeln('// MADE, not written: `dart run tool/icons/generate.dart <the packs\' folder>` writes it from tool/icons/map.json.')
      ..writeln('//')
      ..writeln('// ${pack.title} ($versions, $licence). ${pack.comment}')
      ..writeln('// $summary')
      ..writeln('// coverage:ignore-file')
      ..writeln()
      ..writeln("import '../icon_pack.dart';")
      ..writeln();
    for (final MapEntry(key: glyph, value: name) in consts.entries) {
      out.writeln('const $name = $glyph;');
    }
    out
      ..writeln()
      ..writeln('/// The app\'s glyphs as ${pack.title} draws them, by their Lucide name (tool/icons/map.json).')
      ..writeln('const Map<String, PackGlyphs> ${dartName(pack.id)}Glyphs = {')
      ..writeAll(rows.map((row) => '$row\n'))
      ..writeln('};');
    final file = File('$outDir/${pack.id}.g.dart')..writeAsStringSync(out.toString());
    // As the pack ships it, with its line ends made the repository's own (Phosphor's come with Windows') and no blank
    // line before it, which a Dart string would drop.
    final text = '${File(pack.licenceFile).readAsStringSync().replaceAll('\r\n', '\n').trim()}\n';
    File('tool/icons/licences/${pack.id}.txt').writeAsStringSync(text);
    licences[pack.id] = text;
    report.writeln('${pack.title.padRight(17)} ${summary.split('. ').first}; ${fellBack.length} fell back; solid native $solidNative, filled native $filledNative; ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB');
  }

  final out = StringBuffer()
    ..writeln('// MADE, not written: `dart run tool/icons/generate.dart <the packs\' folder>` copies each pack\'s licence here,')
    ..writeln('// as tool/icons/licences/ has it. Registered with Flutter\'s LicenseRegistry (lib/art/icon_packs.dart).')
    ..writeln('// coverage:ignore-file')
    ..writeln()
    ..writeln('/// Each icon pack\'s licence, as the pack ships it, by the pack\'s id.')
    ..writeln('const Map<String, String> iconPackLicenceTexts = {');
  for (final MapEntry(:key, :value) in licences.entries) {
    if (value.contains("'''")) throw StateError('$key\'s licence has three quotes in it');
    out.writeln("  '$key': r'''$value''',");
  }
  out.writeln('};');
  File('$outDir/licences.g.dart').writeAsStringSync(out.toString());
  stdout.write(report);
}
