// An organization's dock (docs/DOCK.md, lib/orgs/ui/organization_screen.dart `OrganizationScreen.dock`): Claude, a new
// note in this organization, Invite for an owner or an admin, and the organization's settings at its foot, each the
// page's own (the hero's New and Invite, the bar's cog).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';
import 'package:ghost_md/shell/page_dock.dart';

import '../shell/dock_support.dart' show dockOrder, done, fakeClaude;
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<List<String>> page(WidgetTester tester, Device device, String id) async {
    final asked = <String>[];
    await device.pump(
      tester,
      OrganizationScreen(
        services: device.services,
        orgId: id,
        notes: const [],
        seen: const <OrgPresence>[],
        wisp: false,
        onBack: () {},
        onOpenNote: (_) {},
        onNew: () => asked.add('new'),
        onAllNotes: () {},
        onSettings: () => asked.add('settings'),
        onOpenOrganization: (_) {},
        onLog: () {},
        onAccount: () {},
        dock: PageDockSeam(claude: fakeClaude(asked)),
      ),
      scroll: false,
    );
    await settle(tester, 14);
    return asked;
  }

  testWidgets('for its owner: Claude, New note in this organization, Invite, and its settings at the foot', (tester) async {
    final device = await Device.make();
    final id = await ghost(device);
    final asked = await page(tester, device, id);
    expect(dockOrder(tester), ['claude', 'org-new', 'org-invite', 'org-settings']);
    expect(find.bySemanticsLabel('New note in this organization'), findsOneWidget);
    expect(find.bySemanticsLabel('Invite'), findsWidgets);
    // The bar's cog and the dock's foot are the one press.
    expect(find.bySemanticsLabel('Organization settings'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('dock-claude')));
    await tester.tap(find.byKey(const ValueKey('dock-org-new')));
    await tester.tap(find.byKey(const ValueKey('dock-org-settings')));
    await settle(tester);
    expect(asked, ['claude', 'new', 'settings']);
    // Invite is the hero's: the page goes to the invite field and puts the caret in it.
    await tester.tap(find.byKey(const ValueKey('dock-org-invite')));
    await settle(tester, 10);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Invite by handle');
    await done(tester);
  });

  testWidgets('for a member who cannot invite: no Invite', (tester) async {
    final device = await Device.make();
    final id = await boo(device);
    await page(tester, device, id);
    expect(dockOrder(tester), ['claude', 'org-new', 'org-settings']);
    await done(tester);
  });
}
