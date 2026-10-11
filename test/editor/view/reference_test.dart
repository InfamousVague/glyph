// The renderer held to the web page: every case tool/editor_reference.mjs measured in Chromium (the web app's own
// CodeMirror, with the extensions lib/editor/view ports) drawn here, and each line's box, classes and runs, the
// rectangle `coordsAtPos` answers for every position, and `posAtCoords` over a grid, compared with the page's.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// Cases measured on the page that cannot be drawn the same yet, and why.
const Map<String, String> _notHeld = <String, String>{
  // With the note in the interface's face its code is in the kit's code face, JetBrains Mono, which the app does
  // not ship (pubspec.yaml has Inter and Maple Mono): a line with inline code or a to-do's box in it is another
  // width and height. Held again when the face is added.
  'inline-inter': 'needs JetBrains Mono',
  'tasks-inter': 'needs JetBrains Mono',
  'mixed-inter': 'needs JetBrains Mono',
  'mixed-formatted-inter': 'needs JetBrains Mono',
};

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in Fixture.names()) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, runs, coordsAtPos and posAtCoords as the page has them', skip: _notHeld.containsKey(name), (tester) async {
      final fixture = Fixture.read(name);
      final view = await pumpFixture(tester, fixture);
      final lines = drawnLines(tester);
      final problems = <String>[];

      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      var worstBox = 0.0, worstCoord = 0.0;
      var exact = 0, samePlace = 0, skipped = 0;
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i], line = lines[i];
        final label = '${want['from']} ${(want['text'] as String).length > 24 ? (want['text'] as String).substring(0, 24) : want['text']}';
        expect(line.from, want['from'], reason: 'line $i starts where the page\'s does');
        // Classes, and the hang.
        final classes = line.spec.projection.className.split(' ').where((c) => c.isNotEmpty).toSet();
        final wantClasses = (want['classes'] as List).cast<String>().toSet();
        if (!(classes.length == wantClasses.length && classes.containsAll(wantClasses))) problems.add('[$label] classes $classes, the page $wantClasses');
        final hang = RegExp(r'--hang: ([\d.]+)px').firstMatch(want['style'] as String)?.group(1);
        final ownHang = RegExp(r'--hang: ([\d.]+)px').firstMatch(line.spec.projection.attributes['style'] ?? '')?.group(1);
        if ((hang == null) != (ownHang == null) || (hang != null && (double.parse(hang) - double.parse(ownHang!)).abs() > 0.2)) problems.add('[$label] hang $ownHang, the page $hang');
        // The box.
        final box = borderBox(line), wantBox = Fixture.rect(want['rect'] as Map<String, dynamic>);
        final off = [(box.left - wantBox.left).abs(), (box.top - wantBox.top).abs(), (box.right - wantBox.right).abs(), (box.bottom - wantBox.bottom).abs()].reduce((a, b) => a > b ? a : b);
        if (off > worstBox) worstBox = off;
        if (off > tolerance) problems.add('[$label] box $box, the page $wantBox');
        // The runs.
        // A fenced block's lines too: the page parses a block by its language and colours its tokens, and so
        // does the port (lib/editor/code).
        {
          final runs = runsOf(line);
          final wantRuns = <(String, Set<String>)>[];
          for (final run in (want['runs'] as List).cast<Map<String, dynamic>>()) {
            final own = (run['classes'] as List).cast<String>().where((c) => !wantClasses.contains(c) && c != 'cm-line' && c != 'cm-content').toSet();
            if (wantRuns.isNotEmpty && wantRuns.last.$2.length == own.length && wantRuns.last.$2.containsAll(own)) {
              wantRuns[wantRuns.length - 1] = (wantRuns.last.$1 + (run['text'] as String), own);
            } else {
              wantRuns.add((run['text'] as String, own));
            }
          }
          final said = runs.map((r) => '${r.$1}|${(r.$2.toList()..sort()).join(',')}').join(' ¦ ');
          final wanted = wantRuns.map((r) => '${r.$1}|${(r.$2.toList()..sort()).join(',')}').join(' ¦ ');
          if (said != wanted) problems.add('[$label] runs\n      $said\n  the page\n      $wanted');
        }
      }

      // The block widgets (the front matter's fold).
      final blocks = tester.renderObjectList<RenderEditorBlock>(find.byType(EditorBlock)).toList()..sort((a, b) => a.spec.from - b.spec.from);
      expect(blocks.length, fixture.blocks.length, reason: 'as many block widgets as the page drew');
      for (var i = 0; i < blocks.length; i++) {
        final box = blocks[i].localToGlobal(Offset.zero) & blocks[i].size, wantBox = Fixture.rect(fixture.blocks[i]['rect'] as Map<String, dynamic>);
        final off = [(box.left - wantBox.left).abs(), (box.top - wantBox.top).abs(), (box.right - wantBox.right).abs(), (box.bottom - wantBox.bottom).abs()].reduce((a, b) => a > b ? a : b);
        if (off > worstBox) worstBox = off;
        if (off > tolerance) problems.add('[block $i] box $box, the page $wantBox');
      }

      // coordsAtPos, both sides of every position.
      if (!fixture.peek) {
        for (final at in fixture.coords) {
          final pos = at['pos'] as int;
          for (final side in const [1, -1]) {
            final want = at[side > 0 ? 'after' : 'before'];
            if (want == null) continue;
            final wantRect = Fixture.rect(want as Map<String, dynamic>);
            final rect = view.coordsAtPos(pos, side);
            if (rect == null) {
              problems.add('coordsAtPos($pos, $side) null, the page $wantRect');
              continue;
            }
            final off = [(rect.left - wantRect.left).abs(), (rect.top - wantRect.top).abs(), (rect.bottom - wantRect.bottom).abs()].reduce((a, b) => a > b ? a : b);
            if (off > worstCoord) worstCoord = off;
            if (off > tolerance) problems.add('coordsAtPos($pos, $side) $rect, the page $wantRect');
          }
        }
        // posAtCoords over the grid. The page's answer is CodeMirror's scan of the line's client rectangles, which
        // this does not copy step for step, so three kinds of point are not held to it: one within a pixel of where
        // two lines meet (CodeMirror takes the content's padding as a whole number of pixels, a third of a pixel
        // off); one in no line's letters or in two lines' at once (a tight heading's lines overlap, and which the
        // scan finds first is its own business); and one where the two answers are the same place on screen, either
        // side of marks that are hidden.
        var missed = 0;
        for (final hit in fixture.hits) {
          final point = Offset((hit['x'] as num).toDouble(), (hit['y'] as num).toDouble());
          final found = view.hitAt(point);
          final want = hit['pos'] as int;
          if (found?.pos == want) {
            exact += 1;
            continue;
          }
          final line = found?.line;
          if (line != null && want >= line.from && want <= line.to) {
            final proj = line.spec.projection;
            if (proj.toDisplay(found!.pos - line.from, 1) == proj.toDisplay(want - line.from, 1) && proj.toDisplay(found.pos - line.from, -1) == proj.toDisplay(want - line.from, -1)) {
              samePlace += 1;
              continue;
            }
          }
          var unsure = false;
          // A point at the very middle of a letter is either side of it.
          if (found != null) {
            final a = fixture.coords[want]['after'], b = fixture.coords[found.pos]['after'];
            if (a != null && b != null && (a as Map)['top'] == (b as Map)['top'] && (point.dx - ((a['left'] as num) + (b['left'] as num)) / 2).abs() <= 0.25) unsure = true;
          }
          for (final block in blocks) {
            final top = block.localToGlobal(Offset.zero).dy;
            if ((point.dy - top - block.size.height / 2).abs() <= 1 || (point.dy - top).abs() <= 1 || (point.dy - top - block.size.height).abs() <= 1) unsure = true;
          }
          for (final each in lines) {
            final top = each.localToGlobal(Offset.zero).dy;
            if ((point.dy - top).abs() <= 1 || (point.dy - top - each.size.height).abs() <= 1) unsure = true;
            if (point.dy < top || point.dy >= top + each.size.height) continue;
            final y = point.dy - top;
            final inside = each.visualLines.where((v) => y >= v.contentTop && y < v.contentBottom).length;
            if (inside != 1) unsure = true;
          }
          if (unsure) {
            skipped += 1;
            continue;
          }
          missed += 1;
          if (missed <= (Platform.environment['EDITOR_ALL'] != null ? 400 : 6)) problems.add('posAtCoords$point ${found?.pos}, the page $want');
        }
        if (missed > 6) problems.add('... $missed of ${fixture.hits.length} points');
      }
      // ignore: avoid_print
      print('$name: ${lines.length} lines, worst box ${worstBox.toStringAsFixed(3)}, worst coordsAtPos ${worstCoord.toStringAsFixed(3)}, posAtCoords $exact the page\'s, $samePlace the same place, $skipped not held');
      if (Platform.environment['EDITOR_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      debugDisableShadows = true;
      final report = Platform.environment['EDITOR_REPORT'];
      if (report != null && report.isNotEmpty) {
        File('$report/${name.replaceAll('/', '_')}.txt')
          ..createSync(recursive: true)
          ..writeAsStringSync(problems.join('\n'));
      }
      expect(problems, isEmpty, reason: problems.take(8).join('\n'));
    });
  }
}
