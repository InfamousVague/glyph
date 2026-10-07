import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_layout.dart';
import 'package:ghost_md/home/home_organizations.dart';

import '../support/render.dart';
import 'support.dart';

/// Pictures of the home page over the seeded library, at the sizes and in the theme the reference pictures were
/// taken in (ghost-md-app-store-pack/screenshots/raw/iphone-home-dark.png, 430x932 at 3; duo-home-dark.png, 669x951
/// at 3), for looking at beside them: `flutter test --update-goldens test/home/home_shots_test.dart`, then open
/// `test/home/shots/home-*.png`.
void main() {
  setUpAll(loadAppFonts);

  /// What [shot] does after its picture, for a test that took its own: the page down, and the shadows' switch back.
  Future<void> shotDone(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the home page on a phone, as iphone-home-dark.png', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
    await shot(tester, 'home-iphone-dark');
  });

  testWidgets('the home page on an opened Fold, as duo-home-dark.png', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), size: const Size(669, 951), split: true);
    await shot(tester, 'home-duo-dark');
  });

  for (final layout in [HomeLayout.cards, HomeLayout.timeline, HomeLayout.list]) {
    testWidgets('the home page as ${layout.name}', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, layout: layout, speak: true), ratio: 2);
      await shot(tester, 'home-${layout.name}-dark');
    });
  }

  testWidgets('the filters open, a workspace chosen', (tester) async {
    final it = seeded();
    it.workspaces.chooseWorkspace('work');
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), ratio: 2);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Filters: Work'));
    await settle(tester);
    await shot(tester, 'home-filters-dark');
  });

  testWidgets('the organizations, and a pinned note filed in one', (tester) async {
    final it = seeded();
    it.workspaces.ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
    it.workspaces.fileNote('weekend', 'org-acme');
    await pumpHome(
      tester,
      Home(
        library: it.library,
        workspaces: it.workspaces,
        asked: it.asked,
        organizations: const [
          HomeOrg(id: 'acme', name: 'Acme', hue: 'violet', members: 3, here: [OrgPresence(client: 'c1', handle: 'ana', editingNote: 'weekend', editingTitle: 'Weekend trip'), OrgPresence(client: 'c2', handle: 'ali')]),
          HomeOrg(id: 'cabin', name: 'Cabin club', hue: 'moss', members: 1),
        ],
      ),
      ratio: 2,
    );
    await shot(tester, 'home-organizations-dark');
  });

  testWidgets('a card swiped to its archive, and a line to its pin', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked), ratio: 2);
    await settle(tester);
    final card = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-prd11'))));
    await card.moveBy(const Offset(-30, 0));
    await tester.pump();
    await card.moveBy(const Offset(-110, 0));
    final line = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('line-weekend'))), pointer: 9);
    await line.moveBy(const Offset(30, 0));
    await tester.pump();
    await line.moveBy(const Offset(110, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(Home), matchesGoldenFile('shots/home-swipes-dark.png'));
    await card.cancel();
    await line.cancel();
    await shotDone(tester);
  });

  testWidgets('a blank page', (tester) async {
    await pumpHome(tester, Home(library: SampleLibrary(const []), workspaces: WorkspaceStore(), asked: Asked(), speak: true), ratio: 2);
    await shot(tester, 'home-empty-dark');
  });

  testWidgets('the home page in the light', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true), theme: 'light', ratio: 2);
    await shot(tester, 'home-iphone-light');
  });
}
