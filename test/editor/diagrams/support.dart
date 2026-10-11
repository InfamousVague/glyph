import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';

/// The web view, stood in for: each render is held until the test lets it finish (or fail), so the order the
/// diagrams are drawn in can be watched, as src/app/editor/mermaid.test.ts holds Mermaid's. What it was asked to
/// draw is kept.
class HeldBridge implements DiagramBridge {
  /// Every ask, in the order they came.
  final List<DiagramAsk> asked = <DiagramAsk>[];
  final List<Completer<DiagramAnswer>> _held = <Completer<DiagramAnswer>>[];

  /// How many renders are in the web view at once, at most: one, if the store keeps its word.
  int most = 0;
  int _open = 0;

  /// The words of every ask, in order.
  List<String> get codes => <String>[for (final ask in asked) ask.code];

  /// How many asks have not been answered.
  int get waiting => _held.where((held) => !held.isCompleted).length;

  @override
  Future<DiagramAnswer> draw(DiagramAsk ask) {
    asked.add(ask);
    final held = Completer<DiagramAnswer>();
    _held.add(held);
    _open += 1;
    if (_open > most) most = _open;
    return held.future.whenComplete(() => _open -= 1);
  }

  /// The render asked `index`th draws: a block `block` in size with its picture at `at` in it.
  void finish(int index, {ui.Size block = const ui.Size(390, 120), ui.Rect at = const ui.Rect.fromLTWH(145, 12, 100, 80), double scale = 2}) =>
      _held[index].complete(DiagramDrawn(png: Uint8List.fromList(<int>[index]), block: block, at: at, scale: scale));

  /// The render asked `index`th says the diagram is wrong, in Mermaid's words; '' is the library itself missing.
  void fail(int index, String said) => _held[index].complete(DiagramFailed(said));
}

/// A picture for a test's PNG: two pixels by two, made at once (a real PNG decodes off the test's clock).
Future<ui.Image> smallPicture(Uint8List png) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = const ui.Color(0xff808080));
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(2, 2);
  } finally {
    picture.dispose();
  }
}

/// An ask for `code`, as a note 390 wide on a light page would make it.
DiagramAsk askFor(String code, {bool dark = false, double room = 390}) => DiagramAsk(
  code: code,
  dark: dark,
  viewport: 390,
  room: room,
  gutter: 20,
  em: 19.35,
  ui: "'Inter Variable', ui-sans-serif, system-ui, sans-serif",
  note: "'Maple Mono', ui-monospace, monospace",
  coding: true,
  ink: const ui.Color(0xff1a1a1a),
  ratio: 2,
);

/// The web view, stood in for by pictures Mermaid really drew: each ask is answered from
/// test/editor/diagrams/fixtures, where tool/diagram_fixtures.mjs keeps what the app's own page
/// (assets/diagrams/index.html) drew for it in Chromium, under the name the store would keep it by. For a test that
/// takes a picture of a screen with a diagram on it, so the picture has the diagram and not its words.
///
/// An ask with no picture there is "could not be drawn here"; run with `DIAGRAM_FIXTURES=want` it is also written
/// down beside the others (`<name>.ask.json`) for the tool to draw:
///
///     DIAGRAM_FIXTURES=want flutter test test/canvas/reference_test.dart ; node tool/diagram_fixtures.mjs
class PicturedBridge implements DiagramBridge {
  static const String folder = 'test/editor/diagrams/fixtures';

  /// What was asked for and had no picture.
  final List<DiagramAsk> missing = <DiagramAsk>[];

  static String nameOf(DiagramAsk ask) => diagramFile(ask.key).replaceAll('.diagram', '');

  @override
  Future<DiagramAnswer> draw(DiagramAsk ask) async {
    final name = nameOf(ask);
    final said = File('$folder/$name.json'), png = File('$folder/$name.png');
    if (!said.existsSync()) {
      missing.add(ask);
      if (Platform.environment['DIAGRAM_FIXTURES'] == 'want') {
        File('$folder/$name.ask.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(<String, Object?>{...ask.toJson(), 'ratio': ask.ratio})}\n');
      }
      return const DiagramFailed('');
    }
    final answer = jsonDecode(said.readAsStringSync()) as Map<String, Object?>;
    return ChannelDiagramBridge.answerOf(<String, Object?>{...answer, if (png.existsSync()) 'png': png.readAsBytesSync()});
  }
}

/// Lets the pictures of a [PicturedBridge] decode (real work, off the test's clock) and the blocks show them.
Future<void> settleDiagrams(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }
}
