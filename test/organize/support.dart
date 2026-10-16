import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/workspaces.dart';

/// An invented library for the organizing features' tests and pictures: tags inside tags, folders inside folders, a
/// notebook and its pages, to-dos open and ticked. Nobody in it is real.
const int organizeNow = 1792160400000; // 2026-10-16.

int _ago(int days, [int hours = 0]) => organizeNow - days * Duration.millisecondsPerDay - hours * Duration.millisecondsPerHour;

Note _n(String id, String body, {int made = 1, int changed = 0, bool starred = false, int? archivedAt}) =>
    Note(id: id, body: body, createdAt: _ago(made), updatedAt: _ago(changed, 1), starred: starred, archivedAt: archivedAt);

List<Note> organizeNotes() => [
      _n('kickoff', '# Kickoff with the shop\n\nThey want the new menu up by Friday. #work/clients/kiln\n\n- [ ] Send the draft\n- [x] Book the call', made: 3, changed: 0, starred: true),
      _n('invoice', '# October invoices\n\nTwo to send. #work/clients #admin\n\n- [ ] The bakery\n- [ ] The bike shop', made: 5, changed: 1),
      _n('roadmap', '# Roadmap, winter\n\n#work Ship the reading view. Then the map.\n\n![sketch](img_roadmap.jpg)', made: 9, changed: 2),
      _n('beds', '# Raised beds\n\nGarlic goes in before the frost. #home/garden\n\n- [x] Buy the boards\n- [x] Fill with soil', made: 12, changed: 4),
      _n('seeds', '# Seeds to order\n\n#home/garden #shopping\n\n- [ ] Broad beans\n- [ ] Sweet peas', made: 2, changed: 0),
      _n('boiler', '# Boiler service\n\nThe engineer comes Tuesday. #home', made: 6, changed: 3),
      _n('novel', '# The lighthouse book\n\nHalfway. The second part drags. #reading', made: 20, changed: 6),
      _n('trip', '# Weekend by the coast\n\nTrains at 9. See [[Packing list]]. #travel', made: 8, changed: 5),
      _n('packing', '# Packing list\n\n- [ ] Rain jacket\n- [ ] Boots #travel', made: 8, changed: 5),
      _n('old', '# Last year\'s plan\n\n#work Kept for the record.', made: 300, changed: 200, archivedAt: _ago(100)),
    ];

/// Work holds Clients, which holds Kiln; Home holds Garden; Reading stands alone.
WorkspaceSheet organizeSpaces() => const WorkspaceSheet(
      list: [
        Workspace(id: 'work', name: 'Work', hue: 'moss'),
        Workspace(id: 'clients', name: 'Clients', parent: 'work'),
        Workspace(id: 'kiln', name: 'Kiln', parent: 'clients'),
        Workspace(id: 'home', name: 'Home', hue: 'sea'),
        Workspace(id: 'garden', name: 'Garden', parent: 'home', hue: 'moss'),
        Workspace(id: 'reading', name: 'Reading', hue: 'amber'),
      ],
      notes: {
        'roadmap': 'work',
        'invoice': 'clients',
        'kickoff': 'kiln',
        'boiler': 'home',
        'beds': 'garden',
        'seeds': 'garden',
        'novel': 'reading',
      },
    );

/// Writes the app as it is on screen to `build/feature-shots/organize/<name>.png`, past its entrances, for looking
/// at: not a golden, so nothing fails for a picture that changed. Then takes the screen down and gives the test
/// binding back its own switch for shadows, as `shot` does (test/support/render.dart).
Future<void> snap(WidgetTester tester, String name, {Finder? of}) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  var target = tester.renderObject(of ?? find.byType(GhostApp));
  while (!target.isRepaintBoundary) {
    target = target.parent!;
  }
  final boundary = target;
  final bytes = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    // The view's own layer is in the screen's pixels already; a boundary under it is in the app's.
    final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('build/feature-shots/organize/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
