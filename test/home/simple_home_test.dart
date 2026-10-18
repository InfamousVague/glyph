import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home/home_organizations.dart';

import '../support/render.dart';
import 'support.dart';

/// The home page in simple mode (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): the filters'
/// panel is the Show radios alone, the search offers no operator chips and no Save, and the organizations' cards
/// are not drawn. The dock without Claude is the root's (test/root/simple_test.dart).
void main() {
  setUpAll(loadAppFonts);

  final filters = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.button == true && (widget.properties.label ?? '').startsWith('Filters'));

  /// A choice of the filters' panel, by what it says: a radio, apart from the page's heading of the same name.
  Finder radio(String label) => find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label && widget.properties.checked != null);

  Future<void> open(WidgetTester tester) async {
    await tester.tap(filters);
    await settle(tester);
  }

  /// Takes the page down, and puts back the binding's switch for shadows that [pumpApp] turned on.
  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  const orgs = [HomeOrg(id: 'acme', name: 'Acme', hue: 'violet', members: 3), HomeOrg(id: 'cabin', name: 'Cabin club', hue: 'moss', members: 1)];

  testWidgets('its panel is Show alone: no Workspace radios, no New workspace, organization or Edit', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: orgs, simple: true));
    await settle(tester);
    await open(tester);
    expect(find.text('SHOW'), findsOneWidget);
    for (final show in ['All', 'Notebooks', 'Notes', 'Pinned']) {
      expect(find.text(show), findsWidgets, reason: '$show is a choice');
    }
    expect(find.text('WORKSPACE'), findsNothing);
    expect(find.text('New workspace'), findsNothing);
    expect(find.text('New organization'), findsNothing);
    expect(find.textContaining('Edit '), findsNothing);
    // A choice still narrows the page.
    await tester.tap(radio('Pinned, 1'));
    await settle(tester);
    expect(find.bySemanticsLabel('Filters: Pinned'), findsOneWidget);
    await away(tester);
  });

  testWidgets('its search offers no operator chips while empty, and no Save as a smart notebook once typed', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, simple: true));
    await settle(tester);
    await tester.tap(find.byType(EditableText));
    await settle(tester);
    expect(find.byKey(const ValueKey('search-hints')), findsNothing);
    await tester.enterText(find.byType(EditableText), 'milk');
    await settle(tester);
    expect(find.byKey(const ValueKey('search-save')), findsNothing);
    // Plain words still search.
    expect(find.text('Groceries'), findsWidgets);
    await away(tester);
  });

  testWidgets('draws no organization cards', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: orgs, simple: true));
    await settle(tester);
    expect(find.byType(HomeOrganizations), findsNothing);
    await away(tester);
  });

  testWidgets('has the whole panel, the operators and the cards in advanced', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, organizations: orgs));
    await settle(tester);
    expect(find.byType(HomeOrganizations), findsOneWidget);
    await open(tester);
    expect(find.text('WORKSPACE'), findsOneWidget);
    expect(find.text('New workspace'), findsOneWidget);
    expect(find.text('New organization'), findsOneWidget);
    await away(tester);
  });
}
