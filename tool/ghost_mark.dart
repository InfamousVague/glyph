// Makes lib/art/ghost_mark.g.dart: Ghost.md's mark, its shapes as tauri/src/app/art/ghostMark.ts writes them.
//
//   dart run tool/ghost_mark.dart
import 'dart:io';

void main() {
  final text = File('tauri/src/app/art/ghostMark.ts').readAsStringSync();
  final box = RegExp(r"GHOST_MARK_BOX = '([^']+)'").firstMatch(text)!.group(1)!;
  final out = StringBuffer()
    ..writeln('// MADE, not written: `dart run tool/ghost_mark.dart` copies it from the web app\'s art/ghostMark.ts.')
    ..writeln('// coverage:ignore-file')
    ..writeln()
    ..writeln("import 'ghost_mark.dart';")
    ..writeln()
    ..writeln('/// A square round the mark, with a little room: left, top, width, height in the drawing\'s own space.')
    ..writeln('const List<double> ghostMarkBox = [${box.split(' ').join(', ')}];')
    ..writeln()
    ..writeln('const List<MarkShape> ghostMarkShapes = [');
  for (final shape in RegExp(r"\{ part: '(\w+)', ink: (true|false), d: '([^']+)' \}").allMatches(text)) {
    out.writeln("  MarkShape(MarkPart.${shape.group(1)}, ${shape.group(2)}, '${shape.group(3)}'),");
  }
  out.writeln('];');
  File('lib/art/ghost_mark.g.dart').writeAsStringSync(out.toString());
}
