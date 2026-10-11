// Makes lib/art/lucide.g.dart: the kit's lucide icons the web app draws, as paths, each with the shapes that wear
// the wash (lib/art/icon_wash.dart, the rule of tauri/src/app/art/iconWash.ts).
//
//   dart run tool/lucide.dart
//
// Which icons: every one the web app, its reader page and the kit's own components import from `@glacier/icons` or
// `lucide-react` (the scan art/iconWash.test.ts makes), and whatever is named in `also` below. To bring in an icon
// the web app does not draw, add its lucide name to `also` and run this again; that line is the whole change.
//
// The wash is held to the page's: every rule of tauri/src/app/iconWash.css must be what the Dart rule makes of
// the same icon, and this stops if one is not, since a wash that disagrees is a port that has drifted.
import 'dart:io';

import 'package:ghost_md/art/icon_wash.dart';

/// Icons to carry that the web app does not import, by lucide's own name (`arrow-up-right`).
const also = <String>[
  // lib/gallery/kit_gallery.dart: the menu's "Move to".
  'folder-input',
];

const glyph = 'tauri';
const lucide = '$glyph/node_modules/lucide-react/dist/esm';

Iterable<File> sources(Directory dir) sync* {
  for (final entry in dir.listSync()) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is Directory) {
      if (name == 'node_modules' || name == 'dist') continue;
      yield* sources(entry);
    } else if (entry is File && RegExp(r'\.tsx?$').hasMatch(name)) {
      yield entry;
    }
  }
}

/// Every icon brought in from the kit, by the name it is imported under.
Set<String> iconsInUse() {
  final names = <String>{};
  final imports = RegExp(r'''import\s+(?:type\s+)?\{([^}]+)\}\s+from\s+['"](?:@glacier/icons|lucide-react)['"]''');
  for (final dir in ['$glyph/src', '$glyph/vendor/@glacier/react']) {
    for (final file in sources(Directory(dir))) {
      for (final match in imports.allMatches(file.readAsStringSync())) {
        for (final part in match.group(1)!.split(',')) {
          final name = part.trim().replaceFirst(RegExp(r'^type\s+'), '').split(RegExp(r'\s+as\s+')).first.trim();
          if (RegExp(r'^[A-Z]').hasMatch(name)) names.add(name);
        }
      }
    }
  }
  return names;
}

/// The name each icon is exported under, to the file it is drawn in.
Map<String, String> exports() {
  final out = <String, String>{};
  final line = RegExp(r'''export \{([^}]+)\} from '\./icons/([a-z0-9-]+)\.mjs';''');
  for (final match in line.allMatches(File('$lucide/lucide-react.mjs').readAsStringSync())) {
    for (final part in match.group(1)!.split(',')) {
      final name = RegExp(r'default as (\w+)').firstMatch(part)?.group(1);
      if (name != null) out[name] = match.group(2)!;
    }
  }
  return out;
}

/// An icon's own name (the class its svg wears, less `lucide-`) and its shapes, from its file.
({String name, List<IconShape> shapes}) read(String file) {
  final text = File('$lucide/icons/$file.mjs').readAsStringSync();
  final name = RegExp(r'name: "([^"]+)"').firstMatch(text)!.group(1)!;
  // A short shape is written on one line and a long one over several.
  final node = text.substring(text.indexOf('node: ['), text.indexOf('\n};', text.indexOf('node: [')));
  final shapes = <IconShape>[];
  for (final shape in RegExp(r'\[\s*"(\w+)",\s*\{([^}]*)\}\s*\]').allMatches(node)) {
    final attrs = <String, String>{};
    for (final attr in RegExp(r'(\w+): "([^"]*)"').allMatches(shape.group(2)!)) {
      if (attr.group(1) != 'key') attrs[attr.group(1)!] = attr.group(2)!;
    }
    shapes.add(IconShape(shape.group(1)!, attrs));
  }
  return (name: name, shapes: shapes);
}

String n(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
double a(Map<String, String> attrs, String name) => double.parse(attrs[name] ?? '0');

/// A shape as a path, so the app parses one grammar: the outline lucide's own element draws.
String pathOf(IconShape shape) {
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
      var rx = at.containsKey('rx') ? a(at, 'rx') : (at.containsKey('ry') ? a(at, 'ry') : 0.0);
      var ry = at.containsKey('ry') ? a(at, 'ry') : rx;
      if (rx > w / 2) rx = w / 2;
      if (ry > h / 2) ry = h / 2;
      if (rx == 0 || ry == 0) return 'M${n(x)} ${n(y)}H${n(x + w)}V${n(y + h)}H${n(x)}Z';
      final arc = 'A${n(rx)} ${n(ry)} 0 0 1';
      return 'M${n(x + rx)} ${n(y)}H${n(x + w - rx)}$arc ${n(x + w)} ${n(y + ry)}V${n(y + h - ry)}$arc ${n(x + w - rx)} ${n(y + h)}H${n(x + rx)}$arc ${n(x)} ${n(y + h - ry)}V${n(y + ry)}$arc ${n(x + rx)} ${n(y)}Z';
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

/// The other names lucide keeps for an icon, by the icon's file: `waves` for `waves-horizontal`, whose file is one
/// line handing on the other's (`export { default } from './waves-horizontal.mjs';`). A mark names its icon by a
/// word (`icon: 'waves'`, plugins/marks), and the page's kit answers to either.
Map<String, List<String>> aliases() {
  final out = <String, List<String>>{};
  final handed = RegExp(r'''^export \{ default \} from '\./([a-z0-9-]+)\.mjs';''', multiLine: true);
  for (final entry in Directory('$lucide/icons').listSync()) {
    if (entry is! File || !entry.path.endsWith('.mjs')) continue;
    final text = entry.readAsStringSync();
    if (text.length > 600) continue;
    final match = handed.firstMatch(text);
    if (match == null) continue;
    final name = entry.uri.pathSegments.last.replaceAll('.mjs', '');
    out.putIfAbsent(match.group(1)!, () => []).add(name);
  }
  return out;
}

/// `SquarePen` as a Dart name: `squarePen`.
String field(String export) => export[0].toLowerCase() + export.substring(1);

/// `square-pen` as a private Dart name: `_squarePen`.
String private(String name) => '_${name.replaceAllMapped(RegExp(r'-(\w)'), (m) => m.group(1)!.toUpperCase())}';

void main() {
  final files = exports();
  final used = iconsInUse().where(files.containsKey).toList()..sort();
  final byFile = <String, List<String>>{};
  for (final name in used) {
    byFile.putIfAbsent(files[name]!, () => []).add(name);
  }
  for (final name in also) {
    if (!File('$lucide/icons/$name.mjs').existsSync()) throw StateError('no lucide icon "$name"');
    byFile.putIfAbsent(name, () => []);
  }

  // The page's own wash, rule by rule.
  final sheet = <String, Set<int>>{};
  for (final rule in RegExp(r':where\(svg\.lucide-([a-z0-9-]+)\) > :nth-child\((\d+)\)').allMatches(File('$glyph/src/app/iconWash.css').readAsStringSync())) {
    sheet.putIfAbsent(rule.group(1)!, () => {}).add(int.parse(rule.group(2)!) - 1);
  }

  final out = StringBuffer()
    ..writeln('// MADE, not written: `dart run tool/lucide.dart` writes it from the icons the web app draws.')
    ..writeln('//')
    ..writeln("// The kit's lucide icons (lucide-react ${RegExp(r'"version": "([^"]+)"').firstMatch(File('$glyph/node_modules/lucide-react/package.json').readAsStringSync())!.group(1)}), each as its shapes' paths on the 24 grid with the places of the")
    ..writeln('// shapes that wear the wash (lib/art/icon_wash.dart), which tool/lucide.dart holds to the page\'s iconWash.css.')
    ..writeln('// coverage:ignore-file')
    ..writeln()
    ..writeln("import 'app_icon.dart';")
    ..writeln();
  final names = <String, String>{};
  final data = <String, String>{};
  var differ = 0;
  for (final file in byFile.keys.toList()..sort()) {
    final icon = read(file);
    final wash = washedShapes(icon.name, icon.shapes);
    if (!wholeWashed.contains(icon.name) && byFile[file]!.isNotEmpty) {
      final page = (sheet[icon.name] ?? {}).toList()..sort();
      if (page.join(',') != wash.join(',')) {
        stderr.writeln('${icon.name}: the page washes [${page.join(', ')}], this rule [${wash.join(', ')}]');
        differ++;
      }
    }
    data[icon.name] = "const ${private(icon.name)} = LucideIcon('${icon.name}', [${icon.shapes.map((s) => "'${pathOf(s)}'").join(', ')}], [${wash.join(', ')}]);";
    for (final export in byFile[file]!) {
      names[field(export)] = icon.name;
    }
    names.putIfAbsent(field(private(icon.name).substring(1)), () => icon.name);
  }
  if (differ > 0) {
    stderr.writeln('$differ icons are washed differently on the page: nothing written.');
    exit(1);
  }
  for (final name in data.keys.toList()..sort()) {
    out.writeln(data[name]);
  }
  out
    ..writeln()
    ..writeln("/// The kit's icons, each under the name the web app imports it by (`<SquarePen />` is `Lucide.squarePen`) and")
    ..writeln("/// under lucide's own (`Lucide.trash` beside `Lucide.trash2`).")
    ..writeln('abstract final class Lucide {');
  for (final name in names.keys.toList()..sort()) {
    out.writeln('  static const $name = ${private(names[name]!)};');
  }
  out
    ..writeln()
    ..writeln("  /// Every icon by lucide's own name, and by each other name lucide keeps for it (`waves` is")
    ..writeln("  /// `waves-horizontal`), for a screen that draws them all and for a mark that names its icon by a word.")
    ..writeln('  static const Map<String, LucideIcon> all = {');
  final known = aliases();
  final keyed = <String, String>{
    for (final name in data.keys) name: private(name),
  };
  for (final file in byFile.keys) {
    final icon = read(file).name;
    for (final other in known[file] ?? const <String>[]) {
      keyed.putIfAbsent(other, () => private(icon));
    }
  }
  for (final name in keyed.keys.toList()..sort()) {
    out.writeln("    '$name': ${keyed[name]},");
  }
  out
    ..writeln('  };')
    ..writeln('}');
  File('lib/art/lucide.g.dart').writeAsStringSync(out.toString());
  stdout.writeln('${data.length} icons, ${names.length} names, held to ${sheet.length} of the page\'s rules.');
}
