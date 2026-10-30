// A picture of the app as it stands, for a feature's own folder under build/feature-shots/ (not committed): to be
// looked at, not held as a golden. Written only under `flutter test --update-goldens`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';

/// The app's picture as `build/feature-shots/<folder>/<name>.png`, after a few beats so it is at rest. Nothing
/// without `--update-goldens`.
Future<void> featureShot(WidgetTester tester, String folder, String name, {int beats = 6}) async {
  if (!autoUpdateGoldenFiles) return;
  for (var i = 0; i < beats; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  var target = tester.renderObject(find.byType(GhostApp));
  while (!target.isRepaintBoundary) {
    target = target.parent!;
  }
  final boundary = target;
  final bytes = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('build/feature-shots/$folder/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}
